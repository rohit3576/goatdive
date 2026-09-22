class_name Coins
extends Node3D
## Phase 9 coins (plan: docs/plans/phase-9-tricks-and-scoring.md D6/D9):
## score pickups snaking the racing line — one MultiMesh draw (the
## web-perf pattern), game-side records as the single truth, distance
## pickup (no Area3D storm), D10-fairness-clean via the polyline owner's
## zone test. Arcs of three over each log teach the jump by temptation.
##
## Pickup emits trick_scored("coin", …) — the score intake, HUD label
## and results panel all ride the existing wire (D8: no new plumbing).

const COIN_R := 0.35
const COIN_H := 0.12
const JITTER := 1.5  # m lateral — coins follow the line, not warp it
const PICKUP_R := 1.4

var _terrain: TerrainGenerator
var _course: CourseBuilder
var _player: GoatController
var _records: Array = []  # {pos, collected} — the contract (D9)
var _mm: MultiMesh
var _collected := 0


func get_records() -> Array:
	return _records


func collected_count() -> int:
	return _collected


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var level := get_parent()
	_terrain = level.get_node_or_null("Terrain") as TerrainGenerator
	_course = level.get_node_or_null("Course") as CourseBuilder
	if _terrain == null or _course == null:
		push_warning("Coins: no Terrain/Course sibling — skipping")
		return
	for c in level.get_children():
		if c is CharacterBody3D:
			_player = c
			break

	var rng := RandomNumberGenerator.new()
	rng.seed = _terrain.seed_value + 131

	# Snake the line: one coin per polyline vertex, lateral jitter,
	# D10 zones respected (gates and braking strips stay clean).
	var poly := _course.polyline
	var placed: Array = []
	for i in range(2, poly.size() - 2):
		var v: Vector3 = poly[i]
		var along := poly[mini(i + 1, poly.size() - 1)] - poly[maxi(i - 1, 0)]
		along.y = 0.0
		if along.length_squared() < 0.01:
			continue
		along = along.normalized()
		var perp := Vector2(-along.z, along.x) * rng.randf_range(-JITTER, JITTER)
		var cx: float = v.x + perp.x
		var cz: float = v.z + perp.y
		if _course.in_gate_zone(Vector3(cx, v.y, cz)):
			continue
		if Vector2(cx, cz).distance_to(TerrainGenerator.SPAWN_XZ) < 20.0:
			continue
		var h: float = _terrain.get_height_at(cx, cz)
		if h < 2.0:
			continue  # valley floor: the race ends before the water
		placed.append(Vector3(cx, h + 0.8, cz))

	# Log arcs: three coins along each log's jump path — a trail that
	# teaches the trick by temptation (one before, one over, one after).
	var obs := level.get_node_or_null("Obstacles") as Obstacles
	if obs != null:
		for rec in obs.get_obstacles("logs"):
			var r: Dictionary = rec
			var lp: Vector3 = r["pos"]
			var ax: Vector3 = r["axis"]
			var along2 := Vector2(-ax.z, ax.x)  # travel direction (axis ⟂ line)
			var away := Vector2(lp.x - 0.0, lp.z + 24.0)
			if along2.dot(away) < 0.0:
				along2 = -along2
			for off in [-4.0, 0.0, 3.0]:
				var f_off: float = off
				var ax2: float = lp.x + along2.x * f_off
				var az2: float = lp.z + along2.y * f_off
				var base: float = _terrain.get_height_at(ax2, az2)
				var lift := 1.6 if absf(f_off) < 0.5 else 0.8  # the over-log coin floats
				placed.append(Vector3(ax2, maxf(base, lp.y) + lift, az2))

	# Visuals: one MultiMesh, standing golden discs (no per-instance
	# animation v1 — F5 decides if they need juice).
	_records = []
	for p in placed:
		_records.append({"pos": p, "collected": false})
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = _coin_mesh()
	_mm.instance_count = _records.size()
	for i in _records.size():
		var p: Vector3 = (_records[i] as Dictionary)["pos"]
		var basis := Basis(Vector3(-1.0, 0.0, 0.0).cross(Vector3.UP).normalized(), PI * 0.5)
		_mm.set_instance_transform(i, Transform3D(basis, p))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.75, 0.2)
	mat.metallic = 0.6
	mat.roughness = 0.35
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.4, 0.05)
	mat.emission_energy_multiplier = 0.5
	mmi.material_override = mat
	add_child(mmi)
	print("COINS: %d placed in %d ms" % [_records.size(), Time.get_ticks_msec() - t0])


## Distance pickup per physics tick (D9: records, never physics queries).
## The player lookup is LAZY: static children ready before the level
## script spawns goats, so an eager lookup finds nobody.
func _physics_process(_delta: float) -> void:
	if _player == null:
		for c in get_parent().get_children():
			if c is CharacterBody3D:
				_player = c
				break
		if _player == null:
			return
	if _records.is_empty():
		return
	var p := _player.global_position
	for i in _records.size():
		var rec: Dictionary = _records[i]
		if rec["collected"]:
			continue
		var c: Vector3 = rec["pos"]
		if Vector2(c.x - p.x, c.z - p.z).length() <= PICKUP_R and absf(c.y - p.y) < 2.0:
			rec["collected"] = true
			_collected += 1
			_hide_instance(i)
			EventBus.trick_scored.emit("coin", Config.TRICK_PTS_COIN, _player)


func _hide_instance(i: int) -> void:
	var t := _mm.get_instance_transform(i)
	t.basis = t.basis.scaled(Vector3.ZERO)
	_mm.set_instance_transform(i, t)


## Standing disc: flat cylinder rotated upright.
func _coin_mesh() -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = COIN_R
	m.bottom_radius = COIN_R
	m.height = COIN_H
	m.radial_segments = 12
	return m
