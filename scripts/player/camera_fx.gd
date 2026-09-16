class_name CameraFx
extends Camera3D
## Phase 4 first-person camera effects
## (plan: docs/plans/phase-4-first-person-pov.md).
##
## Additive local offsets ONLY — position / rotation / fov on this node.
## Never on Head (head_camera.gd writes Head.rotation absolutely on every
## mouse event — offsets there survive zero pixels, plan D1) and never on
## controller state (D4). Horns are children of this camera, so they
## inherit every offset and stay pinned in frame (D2).
##
## Channels:
##   bob    sine, rate ∝ speed, grounded only, eased in/out      (D6)
##   tilt   slope pitch/roll from floor normal vs view           (D7)
##   lean   roll ∝ velocity-heading turn rate × speed (carve,
##          not mouse — mouse yaws the head, carving leans it)   (D7)
##   dip    spring-damper: jump pop / landing dip / fall drift   (D8)
##   shake  trauma² decay, fed by goat_bonked + stumble landings (D9)
##   fov    FOV_BASE → FOV_MAX across MOVE_SPEED → MAX_DOWNHILL  (D10)

const TAU := 6.283185307179586

var _goat: GoatController

# Bob + shared grounded blend (tilt eases on the same envelope).
var _bob_phase := 0.0
var _ground_blend := 0.0

# Carve lean.
var _heading := 0.0
var _heading_rate := 0.0
var _heading_valid := false

# Dip springs — position dip (m, + = down) and pitch (rad, + = up) share
# constants, keep separate state.
var _dip_x := 0.0
var _dip_v := 0.0
var _pitch_x := 0.0
var _pitch_v := 0.0

# Fall-drift blend.
var _fall_amt := 0.0

# Shake.
var _trauma := 0.0
var _time := 0.0

# Directional bonk kick (Phase 5): decaying positional push, stored local.
var _kick := Vector3.ZERO

# Gate-pass FOV pop (Phase 6, plan Step 5): quick widen, ~0.3 s decay —
# a checkpoint reads "noted", not "exploded".
var _fov_pop := 0.0


func _ready() -> void:
	# Camera3D → Head → Goat rig (goat.tscn). FOV_BASE lives HERE only —
	# the scene's initial fov was removed so Config is the single source
	# (Phase 5 D10 tidy).
	fov = Config.FOV_BASE
	_goat = get_parent().get_parent() as GoatController
	EventBus.goat_jumped.connect(_on_jumped)
	EventBus.goat_landed.connect(_on_landed)
	EventBus.goat_bonked.connect(_on_bonked)
	EventBus.checkpoint_passed.connect(_on_gate_passed)


func _process(delta: float) -> void:
	if _goat == null or not Config.CAM_FX:
		position = Vector3.ZERO
		rotation = Vector3.ZERO
		fov = Config.FOV_BASE
		_fov_pop = 0.0
		return

	var dt := minf(delta, 0.05)  # clamp — window-drag spikes must not explode springs
	var d := _goat.get_debug_state()
	var speed: float = d.speed
	var vel: Vector2 = d.vel
	var grounded: bool = d.grounded
	_time += dt

	# Grounded blend: eases bob/tilt in and out across air↔ground (no snaps).
	_ground_blend = move_toward(_ground_blend, 1.0 if grounded else 0.0, dt / 0.15)

	# --- Bob (D6): phase advances only while grounded (true freeze in air). ---
	var bob_scale := clampf(speed / Config.MOVE_SPEED, 0.0, 1.5)
	if grounded:
		_bob_phase += Config.BOB_RATE * bob_scale * dt
	var bob_y := Config.BOB_AMPL * bob_scale * absf(sin(_bob_phase)) * _ground_blend
	var bob_x := Config.BOB_SWAY * bob_scale * sin(_bob_phase * 0.5) * _ground_blend

	# --- Slope tilt (D7): floor normal vs view, capped, heavier in slides. ---
	var tilt_pitch := 0.0
	var tilt_roll := 0.0
	if grounded:
		var n: Vector3 = d.floor_n
		var slope_deg: float = d.slope
		if slope_deg > 1.0:
			var slope_scale := clampf(slope_deg / 45.0, 0.0, 1.0)
			if d.state == "SLIDE":
				slope_scale = minf(slope_scale * Config.SLIDE_TILT_SCALE, 1.5)
			# Downhill direction on the floor plane (gravity minus its normal part).
			var dh := Vector3.DOWN - n * Vector3.DOWN.dot(n)
			dh.y = 0.0
			if dh.length_squared() > 0.0001:
				dh = dh.normalized()
				var basis := _goat.global_transform.basis
				var fwd := -basis.z
				fwd.y = 0.0
				fwd = fwd.normalized() if fwd.length_squared() > 0.0001 else Vector3.ZERO
				var right := basis.x
				right.y = 0.0
				right = right.normalized() if right.length_squared() > 0.0001 else Vector3.ZERO
				var tilt_max := deg_to_rad(Config.TILT_MAX_DEG)
				# Facing downhill → nose dips (−X rotation looks down).
				# Downhill to the right → right shoulder down (−Z roll).
				tilt_pitch = -tilt_max * fwd.dot(dh) * slope_scale
				tilt_roll = -tilt_max * right.dot(dh) * slope_scale
	tilt_pitch *= _ground_blend
	tilt_roll *= _ground_blend

	# --- Carve lean (D7): roll ∝ smoothed velocity-heading rate × speed. ---
	if vel.length_squared() > 1.0:
		var heading := vel.angle()
		if _heading_valid:
			var rate := wrapf(heading - _heading, -PI, PI) / maxf(dt, 0.0001)
			_heading_rate = lerpf(_heading_rate, rate, minf(1.0, Config.LEAN_SMOOTH * dt))
		_heading = heading
		_heading_valid = true
	else:
		_heading_rate = move_toward(_heading_rate, 0.0, Config.LEAN_SMOOTH * dt)
	# +heading rate = turning right (XZ math) → lean right = −Z roll.
	var lean := -deg_to_rad(Config.LEAN_MAX_DEG) * clampf(
		_heading_rate * minf(speed / Config.MOVE_SPEED, 1.5) * Config.LEAN_GAIN, -1.0, 1.0
	) * _ground_blend

	# --- Dip springs (D8): semi-implicit Euler, underdamped (one bounce). ---
	_dip_v += (-Config.DIP_SPRING_K * _dip_x - Config.DIP_SPRING_C * _dip_v) * dt
	_dip_x += _dip_v * dt
	_pitch_v += (-Config.DIP_SPRING_K * _pitch_x - Config.DIP_SPRING_C * _pitch_v) * dt
	_pitch_x += _pitch_v * dt

	# --- Fall drift (D8): nose down ∝ fall speed, only meaningfully airborne. ---
	var fall_target := 0.0
	if d.state == "AIR" and d.vy_world < -Config.FALL_DRIFT_MIN:
		fall_target = clampf((-d.vy_world - Config.FALL_DRIFT_MIN) / 12.0, 0.0, 1.0)
	_fall_amt = lerpf(_fall_amt, fall_target, minf(1.0, Config.FALL_SMOOTH * dt))
	var fall_pitch := -deg_to_rad(Config.FALL_PITCH_MAX_DEG) * _fall_amt

	# --- Shake (D9): trauma² output, desynced sine channels, strict decay. ---
	_trauma = maxf(0.0, _trauma - Config.SHAKE_DECAY * dt)
	var sh := _trauma * _trauma
	var shake_pitch := (
		sin(_time * Config.SHAKE_FREQ * TAU * 0.9) * deg_to_rad(Config.SHAKE_ROT_DEG) * sh
	)
	var shake_roll := (
		sin(_time * Config.SHAKE_FREQ * TAU * 0.63 + 1.7) * deg_to_rad(Config.SHAKE_ROT_DEG) * sh
	)
	var shake_x := sin(_time * Config.SHAKE_FREQ * TAU * 0.52 + 2.4) * Config.SHAKE_POS * sh
	var shake_y := sin(_time * Config.SHAKE_FREQ * TAU * 0.4 + 0.8) * Config.SHAKE_POS * sh

	# --- Directional bonk kick (Phase 5): decay toward zero. ---
	_kick = _kick.lerp(Vector3.ZERO, minf(1.0, 8.0 * dt))

	# --- FOV kick (D10): eased toward the speed target, never pops. ---
	var fov_target := lerpf(
		Config.FOV_BASE,
		Config.FOV_MAX,
		smoothstep(Config.MOVE_SPEED, Config.MAX_DOWNHILL_SPEED, speed)
	)
	_fov_pop = move_toward(_fov_pop, 0.0, Config.RACE_GATE_PASS_FOV_POP * 3.0 * dt)
	fov = lerpf(fov, fov_target + _fov_pop, minf(1.0, Config.FOV_LERP * dt))

	# --- Compose (single write point, D4). ---
	position = Vector3(
		bob_x + shake_x + _kick.x, bob_y + _dip_x + shake_y + _kick.y, _kick.z
	)
	rotation = Vector3(tilt_pitch + _pitch_x + fall_pitch + shake_pitch, 0.0, tilt_roll + lean + shake_roll)


func _on_jumped() -> void:
	if not Config.CAM_FX:
		return
	_dip_v -= Config.DIP_JUMP  # negative dip = upward pop
	_pitch_v += Config.DIP_PITCH_JUMP


func _on_landed(impact: float) -> void:
	if not Config.CAM_FX:
		return
	var k := clampf(impact / Config.STUMBLE_IMPACT, 0.0, 1.5)
	_dip_v += Config.DIP_LAND * k  # small hops tick, cliff drops slam
	_pitch_v -= Config.DIP_PITCH_LAND * k
	if impact > Config.STUMBLE_IMPACT:
		_add_trauma(impact)


func _on_bonked(impact: float, direction: Vector3) -> void:
	if not Config.CAM_FX:
		return
	_add_trauma(impact)
	if direction.length_squared() > 0.001:
		# World push → local offset, so the kick reads "away from the wall"
		# regardless of view heading.
		var world_kick := direction.normalized() * clampf(impact * 0.008, 0.04, 0.12)
		_kick = global_transform.basis.orthonormalized().inverse() * world_kick


func _on_gate_passed(_idx: int, _split: float) -> void:
	if not Config.CAM_FX:
		return
	_fov_pop += Config.RACE_GATE_PASS_FOV_POP


func _add_trauma(impact: float) -> void:
	_trauma = minf(_trauma + clampf(impact / Config.SHAKE_REF_IMPACT, 0.0, 1.0), 1.3)


## Live FX readout for the F3 overlay and the smoke test.
func get_fx_debug() -> Dictionary:
	return {
		"fov": fov,
		"trauma": _trauma,
		"dip": _dip_x,
		"bob_phase": _bob_phase,
		"ground_blend": _ground_blend,
	}
