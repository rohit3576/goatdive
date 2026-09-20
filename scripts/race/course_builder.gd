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

# Phase 8 D4 danger chords: {entry, exit, ratio, slope_main, slope_chord}.
var chords: Array[Dictionary] = []


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
	_find_chords()
	if gate_points.is_empty():
		push_warning("Course: walk produced no gates")
		return
	if not chords.is_empty():
		var c: Dictionary = chords[0]
		print(
			"COURSE: chord 1 — ratio %.2f, slope %.1f°→%.1f° (%s)"
			% [
				c["ratio"], c["slope_main"], c["slope_chord"],
				"steeper" if c["slope_chord"] > c["slope_main"] else "surface",
			]
		)
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


## Min XZ distance from a point to the course polyline (segment walk).
## Phase 8: the corridor definition lives with the polyline's owner —
## obstacle building (Obstacles) and difficulty telemetry (RaceManager)
## both ask here.
func corridor_dist(p: Vector3) -> float:
	var best := INF
	for i in polyline.size() - 1:
		var a: Vector3 = polyline[i]
		var b: Vector3 = polyline[i + 1]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var t := clampf(
			Vector2(p.x - a.x, p.z - a.z).dot(ab) / ab.length_squared(), 0.0, 1.0
		)
		var proj := Vector2(a.x, a.z) + ab * t
		best = minf(best, proj.distance_to(Vector2(p.x, p.z)))
	return best


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


# --- danger chords (Phase 8, plan D4) -----------------------------------------
#
# Where the walk meanders, the chord across the bend is the danger line:
# shorter by construction, steeper/icier by REQUIREMENT (a shortcut that
# costs nothing is a bug, not a feature). Marked at both ends; player-only
# v1 — the herd stays on the polyline (README parks AI shortcuts later).


const CHORD_SCAN_STEP := 4  # vertices between scan starts (~32 m)
const CHORD_MAX_ARC := 220.0  # m — beyond this the "bend" is the mountain


func _find_chords() -> void:
	var n := polyline.size()
	if n < 12 or Config.CHORD_MAX_COUNT <= 0:
		return
	var used_until := -1
	var best_ratio_seen := 1.0  # diagnostic: closest anyone came to a bend
	for _want in Config.CHORD_MAX_COUNT:
		var best := {}
		var best_score := 0.0
		var i := 2
		while i < n - 3:
			if i <= used_until:
				i += 1
				continue
			var j := i + 2
			while j < n - 2 and _cum[j] - _cum[i] <= CHORD_MAX_ARC:
				var arc := _cum[j] - _cum[i]
				if arc >= Config.CHORD_MIN_ARC:
					var a: Vector3 = polyline[i]
					var b: Vector3 = polyline[j]
					var chord_len := Vector2(b.x - a.x, b.z - a.z).length()
					var ratio := chord_len / arc
					best_ratio_seen = minf(best_ratio_seen, ratio)
					if ratio < Config.CHORD_RATIO and ratio < 1.0 - best_score:
						if _chord_qualifies(i, j, a, b):
							best = {"i": i, "j": j, "ratio": ratio}
							best_score = 1.0 - ratio
				j += 1
			i += CHORD_SCAN_STEP
		if best.is_empty():
			break
		var bi: int = best["i"]
		var bj: int = best["j"]
		_used_chord_range(bi, bj)
		used_until = bj
		var entry: Vector3 = polyline[bi]
		var exit_p: Vector3 = polyline[bj]
		_spawn_chord_flags(entry, exit_p)
		chords.append({
			"entry": entry,
			"exit": exit_p,
			"ratio": best["ratio"],
			"slope_main": _mean_slope_along(bi, bj, false),
			"slope_chord": _mean_slope_along(bi, bj, true),
		})
	if chords.is_empty():
		print(
			"COURSE: no qualifying danger chord — best bend ratio %.2f (need < %.2f); the mountain honestly has no big meander (seed decides)"
			% [best_ratio_seen, Config.CHORD_RATIO]
		)


func _used_chord_range(_i: int, _j: int) -> void:
	pass  # hook: range bookkeeping if overlap rules grow


## Danger qualification (plan D4): the chord must COST something —
## measurably steeper mean slope, or a nastier surface mix (ice/snow the
## groomed line avoids), and stay inside the playable ring.
func _chord_qualifies(i: int, j: int, a: Vector3, b: Vector3) -> bool:
	var chord_dir := Vector2(b.x - a.x, b.z - a.z)
	var chord_len := chord_dir.length()
	if chord_len < 1.0:
		return false
	chord_dir = chord_dir / chord_len
	# Bounds: midpoint + both ends inside the playable ring; spawn clear.
	var mid := (a + b) * 0.5
	if mid.length() > Config.RACE_PLAYABLE_RADIUS or a.length() > Config.RACE_PLAYABLE_RADIUS or b.length() > Config.RACE_PLAYABLE_RADIUS:
		return false
	if Vector2(a.x, a.z).distance_to(Vector2(0.0, -24.0)) < 50.0:
		return false
	var slope_main := _mean_slope_along(i, j, false)
	var slope_chord := _mean_slope_along(i, j, true)
	if slope_chord > slope_main + 2.0:
		return true  # steeper — dangerous by grade
	# Surface: sample both lines; the chord must carry more ice/snow.
	return _ice_fraction_chord(a, b, chord_dir) > _ice_fraction_window(i, j) + 0.15


## Mean |slope| per sample — along the polyline window (chord=false) or
## straight across it (chord=true).
func _mean_slope_along(i: int, j: int, chord: bool) -> float:
	if _terrain == null:
		return 0.0
	var total := 0.0
	var count := 0
	if chord:
		var a: Vector3 = polyline[i]
		var b: Vector3 = polyline[j]
		var dir := Vector2(b.x - a.x, b.z - a.z)
		var len := dir.length()
		if len < 1.0:
			return 0.0
		dir = dir / len
		var steps := maxi(2, int(len / 8.0))
		for k in steps + 1:
			var x := a.x + dir.x * len * k / steps
			var z := a.z + dir.y * len * k / steps
			total += _terrain.slope_deg_at(x, z)
			count += 1
	else:
		for k in range(i, j + 1):
			var p: Vector3 = polyline[k]
			total += _terrain.slope_deg_at(p.x, p.z)
			count += 1
	return total / maxf(1, count)


## ICE/SNOW fraction along the straight chord.
func _ice_fraction_chord(a: Vector3, b: Vector3, dir: Vector2) -> float:
	if _terrain == null:
		return 0.0
	var nasty := 0
	var count := 0
	var len := Vector2(b.x - a.x, b.z - a.z).length()
	var steps := maxi(2, int(len / 8.0))
	for k in steps + 1:
		var x := a.x + dir.x * len * k / steps
		var z := a.z + dir.y * len * k / steps
		var surf := _terrain.surface_at(x, z)
		if surf == TerrainGenerator.Surface.ICE or surf == TerrainGenerator.Surface.SNOW:
			nasty += 1
		count += 1
	return float(nasty) / maxf(1, count)


## ICE/SNOW fraction along the polyline window [i, j].
func _ice_fraction_window(i: int, j: int) -> float:
	if _terrain == null:
		return 0.0
	var nasty := 0
	var count := 0
	for k in range(i, j + 1):
		var p: Vector3 = polyline[k]
		var surf := _terrain.surface_at(p.x, p.z)
		if surf == TerrainGenerator.Surface.ICE or surf == TerrainGenerator.Surface.SNOW:
			nasty += 1
		count += 1
	return float(nasty) / maxf(1, count)


## Flag pairs (2 posts + pennant, danger red/white) at chord entry and
## exit, nudged off the main line toward the chord so the cut reads as a
## CHOICE. Visual only — markers are neither trigger nor obstacle.
func _spawn_chord_flags(entry: Vector3, exit_p: Vector3) -> void:
	var mat := _chord_mat()
	var dir_chord := Vector3(exit_p.x - entry.x, 0.0, exit_p.z - entry.z)
	if dir_chord.length_squared() < 1.0:
		return
	dir_chord = dir_chord.normalized()
	for end_point in [entry, exit_p]:
		var base: Vector3 = end_point
		var flag := MeshInstance3D.new()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var post := CylinderMesh.new()
		post.top_radius = 0.04
		post.bottom_radius = 0.06
		post.height = 1.4
		for side in [-1.0, 1.0]:
			var perp := Vector3(-dir_chord.z, 0.0, dir_chord.x) * float(side) * 0.9
			st.append_from(
				post, 0, Transform3D(Basis.IDENTITY, base + perp + Vector3.UP * 0.7)
			)
		var pennant := PlaneMesh.new()  # faces +Y — stand it up
		pennant.size = Vector2(1.6, 0.5)
		var up := Basis(Vector3.RIGHT, PI * 0.5)
		st.append_from(
			pennant, 0, Transform3D(
				up * Basis(Vector3.UP, atan2(-dir_chord.x, -dir_chord.z)),
				base + Vector3.UP * 1.45
			)
		)
		flag.mesh = st.commit()
		flag.material_override = mat
		flag.name = "ChordFlag%d" % chords.size()
		add_child(flag)


static var _chord_flag_mat: StandardMaterial3D


func _chord_mat() -> StandardMaterial3D:
	if _chord_flag_mat == null:
		_chord_flag_mat = StandardMaterial3D.new()
		_chord_flag_mat.albedo_color = Color(0.86, 0.15, 0.12)
		_chord_flag_mat.emission_enabled = true
		_chord_flag_mat.emission = Color(0.55, 0.08, 0.05)
		_chord_flag_mat.emission_energy_multiplier = 0.6
	return _chord_flag_mat
