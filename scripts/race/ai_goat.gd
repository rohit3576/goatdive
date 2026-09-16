class_name AiGoat
extends Node
## Phase 7 AI brain (plan: docs/plans/phase-7-ai-goats.md D2–D6): feeds the
## verified GoatController through autopilot — grip, slide, stumble, tumble
## and coyote are shared with the player; physics stays the only integrator.
##
## Steering = yaw the body toward the lookahead waypoint (the brain owns
## rotation, like the mouse does for the player), then push forward in
## body-local input space. Speed shaping = lift off above the skill cap.
## Ledge lookahead = one height probe; stuck net = polyline teleport.

const POLY_STEP := 8.0  # course_builder walk step (lookahead conversion)

var profile := "BOLD"  # "CAUTIOUS" / "BOLD" / "RECKLESS"

var _goat: GoatController
var _course: CourseBuilder
var _terrain: TerrainGenerator
var _idx := 0  # nearest polyline index — advance-only
var _wish := Vector2.ZERO  # smoothed body-local input
var _stuck := 0.0
var _gate_stall := 0.0
var _last_gate := -1
var _teleports := 0
var _racing := false


func _ready() -> void:
	_goat = get_parent() as GoatController
	var level := _goat.get_parent()
	_course = level.get_node_or_null("Course") as CourseBuilder
	_terrain = level.get_node_or_null("Terrain") as TerrainGenerator
	_goat.set_autopilot(true)
	EventBus.race_started.connect(func() -> void: _racing = true)
	EventBus.race_finished.connect(func(_t: float) -> void: _racing = false)


func _physics_process(delta: float) -> void:
	if _goat == null:
		return
	if not _racing or _course == null:
		_goat.set_ai_steering(Vector2.ZERO, false)
		return
	var poly := _course.polyline
	var pos := _goat.global_position

	# --- Advance-only nearest waypoint (windowed, no back-sliding). ---
	var best := _idx
	var best_d := _xz2(pos, poly[_idx])
	for k in range(_idx + 1, mini(_idx + 12, poly.size())):
		var d := _xz2(pos, poly[k])
		if d < best_d:
			best_d = d
			best = k
	_idx = best

	# --- Lookahead target + world direction to it. ---
	var target_i := mini(_idx + ceili(_lookahead() / POLY_STEP), poly.size() - 1)
	var target: Vector3 = poly[target_i]
	var dir := Vector2(target.x - pos.x, target.z - pos.z)
	if dir.length() < 0.5:
		dir = Vector2(-_goat.global_transform.basis.z.z, -_goat.global_transform.basis.z.x).normalized()
	else:
		dir = dir.normalized()

	# --- Own the yaw: rotate the body toward the target (mouse-equivalent,
	#     rate-limited so AI carving reads like player carving). ---
	# dir is Vector2(x, z) — the world-Z component lives in dir.y.
	var want_yaw := atan2(-dir.x, -dir.y)
	var diff := wrapf(want_yaw - _goat.global_rotation.y, -PI, PI)
	_goat.rotate_y(clampf(diff, -Config.AI_TURN_RATE * delta, Config.AI_TURN_RATE * delta))

	# --- Body-local input (input.y = -1 is forward). ---
	var basis := _goat.global_transform.basis
	var fwd := -basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := basis.x
	right.y = 0.0
	right = right.normalized()
	var input := Vector2(right.dot(Vector3(dir.x, 0.0, dir.y)), -fwd.dot(Vector3(dir.x, 0.0, dir.y)))

	# --- Speed shaping: lift off above the skill cap (physics coasts). ---
	var d_goat := _goat.get_debug_state()
	if float(d_goat["speed"]) > _speed_cap():
		input = Vector2.ZERO

	_wish = _wish.lerp(input, minf(1.0, Config.AI_WISH_SMOOTH * delta))

	# --- Ledge probe: near-edge drop check, one height pair per tick. ---
	var want_jump := false
	if _terrain != null:
		var probe_x := pos.x + dir.x * Config.AI_LEDGE_PROBE
		var probe_z := pos.z + dir.y * Config.AI_LEDGE_PROBE
		var drop: float = (
			_terrain.get_height_at(pos.x, pos.z) - _terrain.get_height_at(probe_x, probe_z)
		)
		want_jump = drop > _ledge_drop()

	_goat.set_ai_steering(_wish, want_jump)

	# --- Stuck net (D6): guaranteed finisher. Two triggers:
	#   1. speed stall — wedged against something (speed < 1 for 4 s)
	#   2. gate stall — racing forward but skipping gates (cut a corner
	#      past a slab; order enforcement then blocks all later gates and
	#      the goat can never finish — the Phase 7 deadlock)
	# Rescue lands 6 m BEFORE the racer's current gate (never past it).
	var mgr := get_tree().get_first_node_in_group("race_manager")
	if float(d_goat["speed"]) < Config.AI_STUCK_SPEED:
		_stuck += delta
	else:
		_stuck = 0.0
	var gate_now: int = mgr.gate_progress_for(_goat) if mgr != null else _idx
	if gate_now != _last_gate:
		_last_gate = gate_now
		_gate_stall = 0.0
	else:
		_gate_stall += delta
	if _stuck > Config.AI_STUCK_TIME or _gate_stall > Config.AI_GATE_STALL:
		var gates: PackedVector3Array = _course.gate_points
		var gi: int = gate_now
		var rescue := Vector3.ZERO
		if gi < gates.size():
			var fwd_g: Vector3 = _course.gate_forwards[gi]
			rescue = gates[gi] - Vector3(fwd_g.x, 0.0, fwd_g.z) * 6.0
		else:
			rescue = gates[gates.size() - 1]
		if _terrain != null:
			rescue.y = _terrain.get_height_at(rescue.x, rescue.z) + 1.5
		_goat.global_position = rescue
		_goat.velocity = Vector3.ZERO
		_goat.set_horizontal_velocity(Vector2.ZERO)
		_teleports += 1
		_stuck = 0.0
		_gate_stall = 0.0


func get_debug_state() -> Dictionary:
	return {
		"profile": profile,
		"target_idx": _idx,
		"gate": _gate_from_idx(),
		"stuck": _stuck,
		"teleports": _teleports,
	}


func _gate_from_idx() -> int:
	# Waypoints-per-gate estimate for F3 (gates are polyline vertices).
	if _course == null:
		return 0
	var pts: int = _course.polyline.size()
	var gates: int = _course.get_gates().size()
	if gates <= 1 or pts <= 1:
		return 0
	return clampi(_idx * gates / pts, 0, gates - 1) + 1


# --- skill profile accessors (all knobs live in Config, plan Step 5) ------

func _speed_cap() -> float:
	match profile:
		"CAUTIOUS":
			return Config.AI_SPEED_CAUTIOUS
		"RECKLESS":
			return Config.AI_SPEED_RECKLESS
		_:
			return Config.AI_SPEED_BOLD


func _lookahead() -> float:
	match profile:
		"CAUTIOUS":
			return Config.AI_LOOK_CAUTIOUS
		"RECKLESS":
			return Config.AI_LOOK_RECKLESS
		_:
			return Config.AI_LOOK_BOLD


func _ledge_drop() -> float:
	match profile:
		"CAUTIOUS":
			return Config.AI_LEDGE_CAUTIOUS
		"RECKLESS":
			return Config.AI_LEDGE_RECKLESS
		_:
			return Config.AI_LEDGE_BOLD


func _xz2(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length_squared()
