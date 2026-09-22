class_name Obstacles
extends Node3D
## Phase 8 mountain gameplay (plan: docs/plans/phase-8-mountain-gameplay.md).
## Step 1 — the corridor: vegetation stops being wallpaper. Pine/rock
## records within OBSTACLE_CORRIDOR_R of the race polyline become real
## colliders under ONE StaticBody3D — everything beyond stays scenery.
##
## D2 collider honesty: primitives sized to what a GOAT can touch, never
## bigger. The capsule is 1.0 m tall and pine canopies start at 1.6 m —
## the touchable pine is the TRUNK (worst-case bottom radius 0.16 × max
## horizontal scale 1.92 ≈ 0.31 m), so the collider is a slim cylinder,
## not a canopy-sized fat box. A fat collider on a thin tree is an
## invisible wall — the one unforgivable lie in a racing game.
##
## D10 fairness (hard rules, smoke-asserted): no collider inside a gate
## slab, the 10 m post-gate braking strip, or the spawn disc.
##
## Records are the contract (D3/D8): get_obstacles() is the game-side
## truth that AI avoidance (Step 2), the smoke, and Phase 9 trick scoring
## all read. No record, no obstacle.
##
## D9 web perf: ONE body, many shapes — shapes are cheap, bodies are the
## expensive unit; the corridor cap bounds broadphase for the web build.

const PINE_R := 0.3  # trunk fit (worst-case visual ≈ 0.31 — D2, shrink bias)
const PINE_H := 5.0  # into the lower canopy — a jumping goat forgives edges
const ROCK_R := 0.6  # median prism half-width (scale range 0.4–1.8 is wide)
const ROCK_CY := 0.3  # sphere center height — dips below ground, never floats
const SPAWN_CLEAR_R := 42.0  # D10 spawn disc (sampler already clears it too)

# Fallen logs (Step 3, plan D3): the jumpable rhythm-breaker — laid
# perpendicular to the course line on straights, resting at radius height.
# Jump math: JUMP_VELOCITY 4.5 → apex 1.03 m; log top 0.8 m at MOVE_SPEED
# airtime ~0.9 s ≈ 7 m of travel — clearable with margin, unavoidable at
# speed without jumping. Avoidable slowly (go around) — fair by design.
const LOG_R := 0.4
const LOG_LEN := 4.6
const LOG_STRAIGHT_WINDOW := 2  # polyline vertices each side (8 m steps → ~16-20 m)
const LOG_MAX_BEND_DEG := 18.0  # heading change allowed across the window
const LOG_MIN_GAP := 60.0  # m between logs — rhythm, not spam

var _terrain: TerrainGenerator
var _course: CourseBuilder
var _body: StaticBody3D
var _records: Dictionary = {}  # kind -> Array[Dictionary] {pos, r}


## Game-side obstacle truth ("pines" / "rocks" — logs land in Step 3).
func get_obstacles(kind: String) -> Array:
	return _records.get(kind, []) as Array


func collider_count() -> int:
	var n := 0
	for kind in _records:
		n += (_records[kind] as Array).size()
	return n


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var level := get_parent()
	_terrain = level.get_node_or_null("Terrain") as TerrainGenerator
	_course = level.get_node_or_null("Course") as CourseBuilder
	var veg := level.get_node_or_null("Vegetation") as Vegetation
	if _terrain == null or _course == null or veg == null:
		push_warning("Obstacles: missing Terrain/Course/Vegetation sibling — skipping")
		return

	# Scene order guarantees Course/Vegetation are built (children ready
	# top-down; Obstacles sits after Course in mountain_level.tscn).
	var candidates: Array = []  # {kind, pos, d} — d = distance to the line
	var total := 0
	for kind in ["pines", "rocks"]:
		var placed: Array = veg.get_placements(kind)
		total += placed.size()
		for p in placed:
			var pos: Vector3 = p
			# D10: spawn disc stays clear (belt + suspenders).
			if Vector2(pos.x, pos.z).distance_to(TerrainGenerator.SPAWN_XZ) < SPAWN_CLEAR_R:
				continue
			var d := _corridor_dist(pos)
			if d <= Config.OBSTACLE_CORRIDOR_R and not _in_d10_zone(pos):
				candidates.append({"kind": kind, "pos": pos, "d": d})

	# D9 cap: nearest to the race line first — density where races run.
	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["d"] < b["d"]
	)
	var capped := false
	if candidates.size() > Config.OBSTACLE_CAP:
		candidates.resize(Config.OBSTACLE_CAP)
		capped = true

	_body = StaticBody3D.new()
	_body.name = "CorridorBody"
	_body.add_to_group("obstacles")  # hit-attribution group (D8 telemetry)
	add_child(_body)
	for kind in ["pines", "rocks", "logs"]:
		_records[kind] = []
	for c in candidates:
		var k := String(c["kind"])
		var pos: Vector3 = c["pos"]
		if k == "pines":
			_add_cylinder(pos, PINE_R, PINE_H)
			(_records[k] as Array).append({"pos": pos, "r": PINE_R})
		else:
			_add_sphere(pos, ROCK_R, ROCK_CY)
			(_records[k] as Array).append({"pos": pos, "r": ROCK_R})

	_place_logs()

	print(
		"OBSTACLES: %d corridor colliders (%d pines, %d rocks, %d logs) of %d records, built in %d ms%s"
		% [
			collider_count(),
			(_records["pines"] as Array).size(),
			(_records["rocks"] as Array).size(),
			(_records["logs"] as Array).size(),
			total,
			Time.get_ticks_msec() - t0,
			" — CAP HIT" if capped else "",
		]
	)


## Min XZ distance to the course polyline — the polyline owner computes.
func _corridor_dist(p: Vector3) -> float:
	return _course.corridor_dist(p)


## D10 exclusion: the polyline owner decides (shared with Coins).
func _in_d10_zone(p: Vector3) -> bool:
	return _course.in_gate_zone(p)


func _add_cylinder(pos: Vector3, radius: float, height: float) -> void:
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	cs.position = Vector3(pos.x, pos.y + height * 0.5, pos.z)
	_body.add_child(cs)


func _add_sphere(pos: Vector3, radius: float, cy: float) -> void:
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	cs.shape = shape
	cs.position = Vector3(pos.x, pos.y + cy, pos.z)
	_body.add_child(cs)


# --- fallen logs (Step 3, plan D3) ---------------------------------------------


## Place OBSTACLE_LOGS logs: straight mid-gap stretches of the polyline,
## perpendicular to the local line, D10-clean at center and both ends.
## Deterministic (terrain-seeded RNG — R reloads identically).
func _place_logs() -> void:
	var poly := _course.polyline
	if poly.size() < (LOG_STRAIGHT_WINDOW * 2 + 3) or Config.OBSTACLE_LOGS <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _terrain.seed_value + 113

	# Straight mid-gap candidates, scored by distance to the nearest gate
	# (mid-gap beats near-gap — braking zones stay calm).
	var cands: Array = []
	for i in range(LOG_STRAIGHT_WINDOW + 1, poly.size() - LOG_STRAIGHT_WINDOW - 1):
		var back: Vector3 = poly[i - LOG_STRAIGHT_WINDOW]
		var here: Vector3 = poly[i]
		var fwd: Vector3 = poly[i + LOG_STRAIGHT_WINDOW]
		var h1 := Vector2(here.x - back.x, here.z - back.z).normalized()
		var h2 := Vector2(fwd.x - here.x, fwd.z - here.z).normalized()
		var bend := absf(_rad_to_deg(h1.angle_to(h2)))
		if bend > LOG_MAX_BEND_DEG:
			continue
		var gate_d := INF
		for g in _course.gate_points:
			gate_d = minf(gate_d, Vector2(here.x - g.x, here.z - g.z).length())
		if gate_d < 20.0:
			continue  # breathing room around gates beyond the D10 slabs
		# Local travel direction (fairness probes use it below).
		var along := (poly[i + 1] - poly[i - 1])
		along.y = 0.0
		if along.length_squared() < 0.01:
			continue
		along = along.normalized()
		var h_back: float = _terrain.get_height_at(
			here.x - along.x * 8.0, here.z - along.z * 8.0
		)
		# Jumpable by GEOMETRY (D10 spirit): the approach must not rise into
		# the log — an uphill log is taller than the jump apex (1.03 m over
		# a 0.8 m top holds only from level-or-falling ground).
		if h_back < here.y - 0.1:
			continue
		# Groundable approach: a convex bulge is a launch ramp — goats fly
		# the log without touching it. No point above the back→here chord
		# (4 m) and no crest inside 2 m (the rollover blind spot — a log
		# past a crest is decorative, smoke-proven on this mountain).
		var h_mid: float = _terrain.get_height_at(
			here.x - along.x * 4.0, here.z - along.z * 4.0
		)
		if h_mid > (h_back + here.y) * 0.5 + 0.2:
			continue
		var h_two: float = _terrain.get_height_at(
			here.x - along.x * 2.0, here.z - along.z * 2.0
		)
		if h_two > lerpf(h_mid, here.y, 0.5) + 0.2:
			continue
		cands.append({"i": i, "pos": here, "gate_d": gate_d})
	cands.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["gate_d"] > b["gate_d"]
	)

	var placed: Array[Vector3] = []
	for c in cands:
		if (_records["logs"] as Array).size() >= Config.OBSTACLE_LOGS:
			break
		var i: int = c["i"]
		var here: Vector3 = c["pos"]
		# Local line direction → log axis is its horizontal perpendicular.
		var along := (
			poly[i + 1] - poly[i - 1]
		)
		along.y = 0.0
		along = along.normalized()
		var axis := Vector3(-along.z, 0.0, along.x)
		var half := LOG_LEN * 0.5
		# D10 at center and both ends — a log stradling a zone is a bug.
		if _in_d10_zone(here) or _in_d10_zone(here + axis * half) or _in_d10_zone(here - axis * half):
			continue
		# Rhythm, not spam: keep logs apart.
		var too_close := false
		for p in placed:
			if Vector2(here.x - p.x, here.z - p.z).length() < LOG_MIN_GAP:
				too_close = true
				break
		if too_close:
			continue
		_place_log(here, axis, rng)
		placed.append(here)


func _place_log(center: Vector3, axis: Vector3, rng: RandomNumberGenerator) -> void:
	var half := LOG_LEN * 0.5
	var roll := rng.randf_range(-0.25, 0.25)  # slight bark roll around the axis
	# End heights follow terrain; the log TILTS across the side-slope so both
	# ends rest. The CENTER rests on the HIGHEST of five samples along the
	# log — on a convex cross-profile (side-dome) a chord-placement floats
	# above the gully at the middle and goats slip UNDER it (smoke-caught
	# twice: max-end floated the downhill half, midpoint floated the dome).
	var h_a: float = _terrain.get_height_at(
		center.x + axis.x * half, center.z + axis.z * half
	)
	var h_b: float = _terrain.get_height_at(
		center.x - axis.x * half, center.z - axis.z * half
	)
	var h_rest := maxf(h_a, h_b)
	for k in [-0.25, 0.0, 0.25]:
		var s: float = k * LOG_LEN  # quarters + center (ends already sampled)
		h_rest = maxf(
			h_rest,
			_terrain.get_height_at(center.x + axis.x * s, center.z + axis.z * s)
		)
	# End-to-end vector → tilted axis; length-preserving, unit after norm.
	var axis_t := Vector3(axis.x * 2.0 * half, h_a - h_b, axis.z * 2.0 * half).normalized()
	var pos := Vector3(center.x, h_rest + LOG_R, center.z)
	var roll_b := Basis(axis_t, roll)

	# Collider under the corridor body (D9): tilted cylinder, honest radius
	# = visual radius (D2).
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = LOG_R
	shape.height = LOG_LEN
	cs.shape = shape
	cs.transform = Transform3D(_axis_basis(axis_t) * roll_b, pos)
	_body.add_child(cs)

	# Visual: bark-brown cylinder, slight taper via top radius, one mesh.
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = LOG_R * 0.85
	mesh.bottom_radius = LOG_R
	mesh.height = LOG_LEN
	mesh.radial_segments = 9
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.29, 0.20, 0.13)
	mat.roughness = 1.0
	mi.material_override = mat
	mi.transform = Transform3D(_axis_basis(axis_t) * roll_b, pos)
	mi.name = "Log%d" % (_records["logs"] as Array).size()  # Log0, Log1, …
	add_child(mi)

	# Records are the contract (D3/D8): the XZ projection of the tilted
	# axis is the avoidance segment; Phase 9's log-jump trick reads the
	# same record.
	(_records["logs"] as Array).append({
		"pos": pos,
		"r": LOG_R,
		"axis": Vector3(axis_t.x, 0.0, axis_t.z).normalized(),
		"half_len": half,
	})


## Orthonormal basis whose Y column is the given horizontal axis (the
## cylinder's long direction), stable for any horizontal input.
func _axis_basis(axis: Vector3) -> Basis:
	var y_a := axis.normalized()
	var x_a := y_a.cross(Vector3.UP).normalized()
	var z_a := x_a.cross(y_a).normalized()
	return Basis(x_a, y_a, z_a)


func _rad_to_deg(v: float) -> float:
	return v * 180.0 / PI
