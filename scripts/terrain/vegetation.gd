class_name Vegetation
extends Node3D
## Phase 5 procedural vegetation (plan: docs/plans/phase-5-realistic-mountain.md
## D4): MultiMesh pines / rocks / grass tufts, placed by the SAME surface
## classifier that sets grip — trees never grow where physics says they
## can't, and cluster noise shapes groves instead of carpets.
##
## Visual only v1: NO collision (the trimesh is untouched); obstacles
## become real gameplay in Phase 8. One draw call per type; instance COLOR
## gives per-tree variance (web perf, plan D9).

var _terrain: TerrainGenerator
var _cluster := FastNoiseLite.new()
var _rock_cluster := FastNoiseLite.new()

# Game-side placement record (headless-verifiable: the dummy RenderingServer
# in --script mode doesn't back MultiMesh instance buffers, so the smoke
# audit reads these. Phase 6's race line will reuse them too).
var _placed: Dictionary = {}


## World positions actually used by a kind ("pines" / "rocks" / "tufts").
func get_placements(kind: String) -> Array:
	return _placed.get(kind, []) as Array


func _ready() -> void:
	_terrain = get_parent().get_node_or_null("Terrain") as TerrainGenerator
	if _terrain == null:
		push_warning("Vegetation: no Terrain sibling — skipping")
		return
	_cluster.seed = _terrain.seed_value + 41
	_cluster.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_cluster.frequency = 1.0 / 90.0
	_rock_cluster.seed = _terrain.seed_value + 43
	_rock_cluster.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_rock_cluster.frequency = 1.0 / 120.0

	var t0 := Time.get_ticks_msec()
	var pines := _spawn_type(
		_pine_mesh(), Color(0.10, 0.22, 0.12), Config.VEG_PINES, "pines",
		func(x: float, z: float) -> bool:
			return (
				_terrain.surface_at(x, z) == TerrainGenerator.Surface.GRASS
				and _terrain.slope_deg_at(x, z) < 28.0
				and _terrain.get_height_at(x, z) < _terrain.snow_line - 10.0
				and _cluster.get_noise_2d(x, z) > 0.0
			),
		Vector2(0.7, 1.6), Vector2(0.9, 1.2), true
	)
	var rocks := _spawn_type(
		_rock_mesh(), Color(0.45, 0.43, 0.40), Config.VEG_ROCKS, "rocks",
		func(x: float, z: float) -> bool:
			var slope := _terrain.slope_deg_at(x, z)
			return (
				(_terrain.surface_at(x, z) == TerrainGenerator.Surface.ROCK or slope > 32.0)
				and slope < 55.0
				and _terrain.get_height_at(x, z) > 8.0
				and _rock_cluster.get_noise_2d(x, z) > 0.25
			),
		Vector2(0.4, 1.8), Vector2(0.55, 1.5), true
	)
	var tufts := _spawn_type(
		_tuft_mesh(), Color(0.30, 0.45, 0.24), Config.VEG_TUFTS, "tufts",
		func(x: float, z: float) -> bool:
			return (
				_terrain.surface_at(x, z) == TerrainGenerator.Surface.GRASS
				and _terrain.slope_deg_at(x, z) < 28.0
			),
		Vector2(0.6, 1.3), Vector2(0.8, 1.2), false  # no shadows from tufts (D9)
	)
	print(
		"VEGETATION: %d pines / %d rocks / %d tufts (caps %d/%d/%d) in %d ms"
		% [pines, rocks, tufts, Config.VEG_PINES, Config.VEG_ROCKS, Config.VEG_TUFTS,
			Time.get_ticks_msec() - t0]
	)


## Scatter one MultiMesh type: rejection-sample the disc, apply the rule,
## vary scale/rotation/color per instance. Returns the placed count.
func _spawn_type(
	mesh: Mesh,
	base_col: Color,
	cap: int,
	kind: String,
	rule: Callable,
	scale_range: Vector2,
	y_range: Vector2,
	shadows: bool
) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = _terrain.seed_value + (
		71 if kind == "pines" else 83 if kind == "rocks" else 97
	)
	var tfms: Array[Transform3D] = []
	var cols: Array[Color] = []
	var pts: Array[Vector3] = []
	# The grass zone is a thin ring on a cone mountain — rejection rates are
	# high by nature, so the sampler gets generous attempts (still < 50 ms).
	var attempts := cap * 10
	while tfms.size() < cap and attempts > 0:
		attempts -= 1
		var x := rng.randf_range(-480.0, 480.0)
		var z := rng.randf_range(-480.0, 480.0)
		if Vector2(x, z).length() > 480.0:
			continue
		if Vector2(x, z).distance_to(Vector2(0.0, -24.0)) < 42.0:
			continue  # spawn area stays clear
		if not rule.call(x, z):
			continue
		var h := _terrain.get_height_at(x, z)
		var s := rng.randf_range(scale_range.x, scale_range.y)
		var sy := s * rng.randf_range(y_range.x, y_range.y)
		var sxz := s * rng.randf_range(0.8, 1.2)
		var basis := (
			Basis(Vector3.UP, rng.randf_range(0.0, TAU))
			* Basis.from_scale(Vector3(sxz, sy, sxz))
		)
		tfms.append(Transform3D(basis, Vector3(x, h - 0.05, z)))
		pts.append(Vector3(x, h, z))
		var v := rng.randf_range(0.8, 1.2)
		cols.append(Color(base_col.r * v, base_col.g * v, base_col.b * v))

	_placed[kind] = pts

	if tfms.is_empty():
		return 0

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = tfms.size()
	for i in tfms.size():
		mm.set_instance_transform(i, tfms[i])
		mm.set_instance_color(i, cols[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mmi.material_override = mat
	mmi.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if shadows
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	add_child(mmi)
	return tfms.size()


## Pine: cylinder trunk + three stacked cones, merged into one mesh
## (single material v1 — the trunk shares the spruce green; invisible at
## racing distance, noted in the completion doc).
func _pine_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.08
	trunk.bottom_radius = 0.16
	trunk.height = 1.4
	st.append_from(trunk, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.7, 0.0)))
	var layers := [Vector2(1.15, 1.8), Vector2(0.9, 1.5), Vector2(0.6, 1.2)]
	var y := 1.6
	for layer in layers:
		var cone := CylinderMesh.new()  # no ConeMesh in Godot 4 — taper a cylinder
		cone.bottom_radius = layer.x
		cone.top_radius = 0.02
		cone.height = layer.y
		st.append_from(
			cone, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, y + layer.y * 0.5, 0.0))
		)
		y += layer.y * 0.55
	return st.commit()


## Rock: faceted prism — per-instance non-uniform squash + rotation reads
## as a boulder field without array-surgery jitter (v1 simplification).
func _rock_mesh() -> Mesh:
	var prism := PrismMesh.new()
	prism.size = Vector3(1.0, 0.8, 1.3)
	prism.left_to_right = 0.4
	return prism


## Grass tuft: two crossed vertical cards.
func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var card := PlaneMesh.new()
	card.size = Vector2(0.55, 0.4)
	var up := Basis(Vector3.RIGHT, PI * 0.5)  # PlaneMesh faces +Y — stand it up
	st.append_from(card, 0, Transform3D(up, Vector3(0.0, 0.2, 0.0)))
	st.append_from(
		card, 0, Transform3D(
			Basis(Vector3.UP, PI * 0.5) * up, Vector3(0.0, 0.2, 0.0)
		)
	)
	return st.commit()
