class_name CourseBuilder
extends Node3D
## Phase 6 race course (plan: docs/plans/phase-6-race-system.md D1/D5): a
## downhill-flow walk from the spawn disc generates the ordered gate line
## AND the course polyline. The polyline is the progress-math substrate and
## the Phase 7 AI waypoint path — built once, used twice.
##
## Deterministic (D9): a pure function of the terrain seed — R reloads the
## scene and the course regenerates identically. No state to leak.
##
## Carried Phase 5 notes honored: downhill_dir returns ZERO on flat band
## treads (probe-ring fallback, completion doc Bug 6); pines route around
## via Vegetation.get_placements() game-side records.

const WALK_STEP := 8.0  # m per walk step
const WALK_MAX_STEPS := 2000  # hard cap — a short course beats an infinite loop
const HEADING_BLEND := 0.35  # weight of fresh downhill vs heading momentum
const RING_R := 10.0  # flat-tread probe radius

var _terrain: TerrainGenerator
var _pines: Array = []
var _gates: Array[Checkpoint] = []

# Course outputs (gates included as polyline vertices — D5).
var polyline := PackedVector3Array()
var gate_points := PackedVector3Array()  # last entry is the finish
var gate_forwards := PackedVector3Array()
var _cum := PackedFloat32Array()  # cumulative length at each polyline vertex
var _length := 0.0


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	_terrain = get_parent().get_node_or_null("Terrain") as TerrainGenerator
	if _terrain == null:
		push_warning("Course: no Terrain sibling — skipping")
		return
	var veg := get_parent().get_node_or_null("Vegetation") as Vegetation
	if veg != null:
		_pines = veg.get_placements("pines")
	_walk()
	_spawn_gates()
	if gate_points.is_empty():
		push_warning("Course: walk produced no gates")
		return
	print(
		"COURSE: %d gates, descent %.0f→%.0f m, length %.0f m in %d ms"
		% [
			gate_points.size(), polyline[0].y,
			gate_points[gate_points.size() - 1].y, _length,
			Time.get_ticks_msec() - t0,
		]
	)


func course_length() -> float:
	return _length


func get_gates() -> Array[Checkpoint]:
	return _gates


## D5 progress: project XZ onto the course polyline, return meters to the
## finish along the course (not straight-line — honest wrong-way math).
func distance_to_finish(pos: Vector3) -> float:
	if polyline.size() < 2:
		return 0.0
	var best_d2 := INF
	var best_i := 0
	var best_t := 0.0
	for i in polyline.size() - 1:
		var a := polyline[i]
		var b := polyline[i + 1]
		var ab := b - a
		var t := clampf((pos - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var proj := Vector2(a.x + ab.x * t, a.z + ab.z * t)
		var d2 := proj.distance_squared_to(Vector2(pos.x, pos.z))
		if d2 < best_d2:
			best_d2 = d2
			best_i = i
			best_t = t
	return _length - (_cum[best_i] + (polyline[best_i + 1] - polyline[best_i]).length() * best_t)


# --- walk -------------------------------------------------------------------


## Steepest-descent walk with heading momentum; zero-downhill treads fall
## back to a probe ring, then to held heading.
func _walk() -> void:
	var pos := TerrainGenerator.SPAWN_XZ
	var heading := _terrain.downhill_dir(pos.x, pos.y)
	if heading.length_squared() < 0.5:
		heading = Vector3.FORWARD  # spawn cone downhill (away from the peak)
	_polyline_add(Vector3(pos.x, _terrain.get_height_at(pos.x, pos.y), pos.y))

	var since_gate := 0.0
	for _i in WALK_MAX_STEPS:
		var down := _terrain.downhill_dir(pos.x, pos.y)
		var dir: Vector3
		if down.length_squared() > 0.5:
			dir = (heading * (1.0 - HEADING_BLEND) + down * HEADING_BLEND).normalized()
		else:
			dir = _ring_fallback(pos, heading)
		heading = dir
		pos += Vector2(dir.x, dir.z) * WALK_STEP
		var h := _terrain.get_height_at(pos.x, pos.y)
		_polyline_add(Vector3(pos.x, h, pos.y))
		since_gate += WALK_STEP

		# Finish wherever the mountain runs out (or the gate cap binds).
		if h <= Config.RACE_FINISH_ALT or pos.length() >= Config.RACE_PLAYABLE_RADIUS:
			_place_gate(pos, dir, true)
			return
		if since_gate >= Config.RACE_GATE_SPACING:
			if gate_points.size() < Config.RACE_GATE_COUNT_MAX - 1:
				_place_gate(pos, dir, false)
				since_gate = 0.0
			else:
				_place_gate(pos, dir, true)
				return
	# Step cap: force a finish wherever the walk died.
	_place_gate(pos, heading, true)


## Flat band tread (Phase 5 Bug 6): sample a probe ring, take the best
## descent; if nothing is meaningfully lower, hold the heading.
func _ring_fallback(pos: Vector2, heading: Vector3) -> Vector3:
	var h_here := _terrain.get_height_at(pos.x, pos.y)
	var best_h := INF
	var best := Vector3.ZERO
	for k in 8:
		var a := TAU * k / 8.0
		var probe := pos + Vector2(cos(a), sin(a)) * RING_R
		var h := _terrain.get_height_at(probe.x, probe.y)
		if h < best_h:
			best_h = h
			best = Vector3(cos(a), 0.0, sin(a))
	if best_h > h_here - 0.05:
		return heading
	return best.normalized()


# --- gates -------------------------------------------------------------------


func _place_gate(pos: Vector2, dir: Vector3, is_finish: bool) -> void:
	var spot := _avoid_pines(pos, dir)
	gate_points.append(Vector3(spot.x, _terrain.get_height_at(spot.x, spot.y), spot.y))
	gate_forwards.append(dir.normalized())


## Nudge the gate off pine records (visual-only obstacles, Phase 8 makes
## them real — routing around them today costs nothing).
func _avoid_pines(pos: Vector2, dir: Vector3) -> Vector2:
	if _pine_clear(pos):
		return pos
	var perp := Vector2(-dir.z, dir.x)
	var along := Vector2(dir.x, dir.z)
	for off in [
		perp * 3.0, perp * -3.0, perp * 6.0, perp * -6.0,
		along * 5.0, along * -5.0, perp * 9.0, perp * -9.0,
	]:
		var spot: Vector2 = pos + off
		if _pine_clear(spot):
			return spot
	return pos  # worst case: overlap — pines have no collision yet


func _pine_clear(pos: Vector2) -> bool:
	var r2 := Config.RACE_GATE_AVOID_PINE_R * Config.RACE_GATE_AVOID_PINE_R
	for pine in _pines:
		var p: Vector3 = pine
		if Vector2(p.x, p.z).distance_squared_to(pos) < r2:
			return false
	return true


func _spawn_gates() -> void:
	for i in gate_points.size():
		var cp := Checkpoint.new()
		cp.transform = Transform3D(Basis.looking_at(gate_forwards[i], Vector3.UP), gate_points[i])
		add_child(cp)
		cp.setup(i, i == gate_points.size() - 1, gate_forwards[i])
		_gates.append(cp)


func _polyline_add(p: Vector3) -> void:
	if polyline.size() > 0:
		_length += p.distance_to(polyline[polyline.size() - 1])
	_cum.append(_length)
	polyline.append(p)
