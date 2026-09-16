class_name GoatController
extends CharacterBody3D
## Phase 3 goat controller: grip-aware carving movement, steep slide/climb,
## coyote/buffer jumps, landing impacts with stumble.
##
## Model: horizontal velocity lives in _horiz (XZ); vertical in velocity.y.
## Surface grip scales accel / brake / turn rate; the gravity projection
## (downhill acceleration) is grip-independent — gravity doesn't care what
## you stand on. Steering is carving: the velocity heading rotates toward
## the wish direction at a grip-limited turn rate, so speed survives turns.

var _spawn_transform := Transform3D()
var _spawn_set := false

# Phase 6 countdown lock (plan D3): zero input authority — physics keeps
# simulating (the goat settles on spawn); movement math untouched.
var _input_enabled := true

# Phase 7 autopilot (plan D2): AI drives the SAME verified body — wish
# comes from a brain instead of the Input singleton. Physics (grip,
# slide, stumble, tumble, coyote) is shared, never duplicated.
var _autopilot := false
var _ai_wish := Vector2.ZERO
var _ai_jump := false

# Movement state.
var _horiz := Vector2.ZERO
var _since_floor := 99.0
var _jump_buffer := 0.0
var _stumble := 0.0
var _floor_slope_deg := 0.0
var _in_slide := false
var _surface_name := "?"

# World vertical speed from position deltas — velocity.y reads ≈ 0 while
# floor-sliding (move_and_slide decomposes it), and Phase 4's fall-drift
# camera needs the real number (plan Step 1, quirk carried from Phase 3).
var _last_y := 0.0
var _vy_world := 0.0
var _floor_n := Vector3.UP

# Crash tumble (Phase 5 D6, ragdoll-lite): the capsule transform stays
# upright — only the visible Body node spins. Recovery realigns it and
# hands off to the verified STUMBLE beat.
var _tumbling := false
var _tumble_axis := Vector3.RIGHT
var _tumble_spin := 0.0

@onready var _body := $Body as Node3D

var _terrain: TerrainGenerator


func setup_spawn(t: Transform3D) -> void:
	_spawn_transform = t
	_spawn_set = true


## Countdown lock (Phase 6 D3): false = no move/jump input read at all.
func set_input_enabled(on: bool) -> void:
	_input_enabled = on


## Autopilot (Phase 7 D2): the brain calls this every physics tick with
## goat-local input (input.y = -1 is forward, like pressing W). Physics
## stays the only integrator — the brain never touches velocity.
func set_autopilot(on: bool) -> void:
	_autopilot = on


func set_ai_steering(wish: Vector2, want_jump: bool) -> void:
	_ai_wish = wish
	_ai_jump = want_jump


## Test/utility hook: set horizontal velocity directly (knockbacks, smoke tests).
func set_horizontal_velocity(v: Vector2) -> void:
	_horiz = v
	velocity.x = v.x
	velocity.z = v.y


## Live readout for the F3 debug overlay and the Phase 4 camera FX (D3: one
## snapshot, two consumers — no spaghetti member access).
func get_debug_state() -> Dictionary:
	return {
		"speed": Vector2(velocity.x, velocity.z).length(),
		"slope": _floor_slope_deg,
		"surface": _surface_name,
		"state": _state_name(),
		"vy": velocity.y,
		"coyote": _since_floor,
		"buffer": _jump_buffer,
		"vy_world": _vy_world,
		"floor_n": _floor_n,
		"vel": Vector2(velocity.x, velocity.z),
		"grounded": is_on_floor(),
		"tumbling": _tumbling,
		"ai": _autopilot,
	}


func _ready() -> void:
	_last_y = global_position.y
	if get_parent() != null:
		_terrain = get_parent().get_node_or_null("Terrain") as TerrainGenerator


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	_since_floor = 0.0 if on_floor else _since_floor + delta
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	_stumble = maxf(0.0, _stumble - delta)
	if _input_enabled:
		if _autopilot:
			if _ai_jump:
				_jump_buffer = Config.JUMP_BUFFER
		elif Input.is_action_just_pressed("jump"):
			_jump_buffer = Config.JUMP_BUFFER

	# Surface + slope (only meaningful when grounded).
	var grip := 1.0
	var floor_n := Vector3.UP
	if on_floor:
		floor_n = get_floor_normal()
		_floor_n = floor_n
		_floor_slope_deg = rad_to_deg(acos(clampf(floor_n.y, -1.0, 1.0)))
		_in_slide = _floor_slope_deg >= Config.SLIDE_ANGLE_DEG
		grip = _grip_at_feet()
	else:
		_in_slide = false
		_floor_slope_deg = 0.0
		_floor_n = Vector3.UP

	if not on_floor:
		velocity += Vector3.DOWN * Config.GRAVITY * delta

	# Camera-relative wish direction (goat yaws with the camera).
	var input := Vector2.ZERO
	if _input_enabled:
		input = _ai_wish if _autopilot else Input.get_vector(
			"move_left", "move_right", "move_forward", "move_back"
		)
	var tb := global_transform.basis
	var wish := tb.x * input.x + (-tb.z) * -input.y
	wish.y = 0.0
	var wish2 := Vector2(wish.x, wish.z)
	var has_input := wish2.length_squared() > 0.0001

	if on_floor:
		# Input authority: full normally, reduced in slide, zero while
		# stumbling or tumbling.
		var authority := 1.0
		if _stumble > 0.0 or _tumbling:
			authority = 0.0
		elif _in_slide:
			authority = 0.3
		if has_input and authority > 0.0:
			# Carve: rotate the velocity heading toward the wish direction.
			var wish_dir := wish2.normalized()
			if _horiz.length() > 0.3:
				var diff := wrapf(wish_dir.angle() - _horiz.angle(), -PI, PI)
				var max_turn := Config.TURN_RATE * grip * authority * delta
				_horiz = _horiz.rotated(clampf(diff, -max_turn, max_turn))
			var along := _horiz.dot(wish_dir)
			if along < Config.MOVE_SPEED:
				_horiz += wish_dir * minf(
					Config.MOVE_ACCEL * grip * authority * delta,
					Config.MOVE_SPEED - along
				)
		else:
			var brake := Config.FRICTION * grip * (0.3 if _in_slide else 1.0)
			_horiz = _horiz.move_toward(Vector2.ZERO, brake * delta)
		# Downhill: forced while sliding, gated by min slope otherwise.
		if _in_slide or _floor_slope_deg >= Config.SLOPE_ACCEL_MIN_DEG:
			# Gravity projected onto the floor plane (unit direction × GRAVITY).
			var g_dir := Vector3.DOWN - floor_n * Vector3.DOWN.dot(floor_n)
			_horiz += Vector2(g_dir.x, g_dir.z) * Config.GRAVITY * delta
	else:
		if has_input and _stumble <= 0.0 and not _tumbling:
			_horiz += wish2.normalized() * (Config.MOVE_ACCEL * Config.AIR_CONTROL * delta)

	var hs := _horiz.length()
	if hs > Config.MAX_DOWNHILL_SPEED:
		_horiz = _horiz / hs * Config.MAX_DOWNHILL_SPEED
	velocity.x = _horiz.x
	velocity.z = _horiz.y

	# Jump: buffered + coyote, consumed on use. No jumping out of a tumble.
	if (
		_jump_buffer > 0.0
		and _since_floor <= Config.JUMP_COYOTE
		and _stumble <= 0.0
		and not _tumbling
	):
		velocity.y = Config.JUMP_VELOCITY
		_jump_buffer = 0.0
		_since_floor = Config.JUMP_COYOTE + 1.0  # consume — no double jump
		EventBus.goat_jumped.emit()

	var was_on_floor := on_floor
	var pre_vy := velocity.y
	var pre_vel := velocity  # speed into walls for the bonk check
	move_and_slide()

	# Landing transition: measure impact, tell the world, maybe stumble.
	if not was_on_floor and is_on_floor():
		var impact := maxf(0.0, -pre_vy)
		EventBus.goat_landed.emit(impact)
		if impact > Config.STUMBLE_IMPACT:
			_stumble = Config.STUMBLE_TIME

	# Wall bonk: near-horizontal collision normal + enough speed into it
	# (steep-but-climbable faces are floors via floor_max_angle, not bonks).
	# Mid-air hits above the tumble threshold crash the goat (Phase 5 D6).
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if absf(n.y) < 0.35:
			var bonk := maxf(0.0, -pre_vel.dot(n))
			if bonk > Config.BONK_MIN_SPEED:
				var dir := n
				dir.y = 0.0
				EventBus.goat_bonked.emit(bonk, dir)
				if not was_on_floor and bonk > Config.TUMBLE_MIN_IMPACT:
					_enter_tumble(bonk, dir)
			break

	_update_tumble(delta)

	# World vertical speed from position delta (clamped: teleport spikes are
	# not physics). Must run before the respawn teleport resets _last_y.
	var y_now := global_position.y
	_vy_world = clampf((y_now - _last_y) / delta, -80.0, 80.0)
	_last_y = y_now

	if _spawn_set and global_position.y < Config.KILL_Y:
		global_transform = _spawn_transform
		velocity = Vector3.ZERO
		_horiz = Vector2.ZERO
		_tumbling = false
		_tumble_spin = 0.0
		_body.quaternion = Quaternion.IDENTITY
		_last_y = global_position.y
		_vy_world = 0.0


## Crash tumble (Phase 5 D6): spin the visible Body around the axis the
## impact implies; the capsule stays upright so move_and_slide stays sane.
## Also the smoke-test entry point for forced tumbles.
func _enter_tumble(impact: float, dir: Vector3) -> void:
	_tumbling = true
	if dir.length_squared() < 0.001:
		dir = Vector3.BACK
	_tumble_axis = dir.normalized().cross(Vector3.UP).normalized()
	_tumble_spin = clampf(impact * Config.TUMBLE_SPIN_GAIN, 3.0, Config.TUMBLE_SPIN_MAX)


func _update_tumble(delta: float) -> void:
	if not _tumbling:
		return
	if is_on_floor():
		# Skidding on the ground bleeds spin; once slow AND nearly stopped,
		# realign upright and hand off to the verified STUMBLE beat.
		_tumble_spin = move_toward(_tumble_spin, 0.0, Config.TUMBLE_SPIN_FRICTION * delta)
		if _horiz.length() < Config.TUMBLE_RECOVER_SPEED:
			var q := _body.quaternion.slerp(
				Quaternion.IDENTITY, minf(1.0, Config.TUMBLE_RECOVER_SMOOTH * delta)
			)
			_body.quaternion = q
			if _body.quaternion.angle_to(Quaternion.IDENTITY) < 0.05:
				_body.quaternion = Quaternion.IDENTITY
				_tumbling = false
				_tumble_spin = 0.0
				_stumble = Config.STUMBLE_TIME
			return
	_body.global_rotate(_tumble_axis, _tumble_spin * delta)

	if _spawn_set and global_position.y < Config.KILL_Y:
		global_transform = _spawn_transform
		velocity = Vector3.ZERO
		_horiz = Vector2.ZERO


func _grip_at_feet() -> float:
	if _terrain == null:
		return 1.0
	var surf := _terrain.surface_at(global_position.x, global_position.z)
	match surf:
		TerrainGenerator.Surface.ICE:
			_surface_name = "ICE"
			return Config.GRIP_ICE
		TerrainGenerator.Surface.SNOW:
			_surface_name = "SNOW"
			return Config.GRIP_SNOW
		TerrainGenerator.Surface.ROCK:
			_surface_name = "ROCK"
			return Config.GRIP_ROCK
		_:
			_surface_name = "GRASS"
			return Config.GRIP_GRASS


func _state_name() -> String:
	if _tumbling:
		return "TUMBLE"
	if _stumble > 0.0:
		return "STUMBLE"
	if not is_on_floor():
		return "AIR"
	if _in_slide:
		return "SLIDE"
	return "GROUND"
