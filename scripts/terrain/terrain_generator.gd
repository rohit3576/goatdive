class_name TerrainGenerator
extends StaticBody3D
## Procedural mountain terrain (Phase 2, decision D1/D2/D8).
##
## Radial cone (the mountain mass) + ridged fBm (ridges) + detail noise →
## one heights array drives the visual ArrayMesh; collision is a trimesh
## generated FROM that mesh so physics and visuals can never disagree.
## (HeightMapShape3D was tried first — its data ordering mismatched and the
## goat fell through; trimesh removed the whole class of bug. See completion doc.)

@export var seed_value: int = 1337
@export var size := 512.0
@export var peak_height := 130.0
@export var grid := 128

# Spawn disc: noise blends to zero inside this radius so the start is pure
# cone slope (~27°) — standable, runnable, no spawn-slide (plan risk #1).
const SPAWN_XZ := Vector2(0.0, -24.0)
const SPAWN_FLAT_RADIUS := 26.0

var _heights := PackedFloat32Array()
var _verts := 0  # grid + 1 samples per side
var _mesh: ArrayMesh


func _ready() -> void:
	_build()


## Bilinear-sampled terrain height at world XZ. Valid query for gameplay code.
func get_height_at(x: float, z: float) -> float:
	var half := size / 2.0
	var step := size / float(grid)
	var fx := (x + half) / step
	var fz := (z + half) / step
	var ix := clampi(int(fx), 0, grid - 1)
	var iz := clampi(int(fz), 0, grid - 1)
	var tx := fx - ix
	var tz := fz - iz
	var h00 := _heights[iz * _verts + ix]
	var h10 := _heights[iz * _verts + ix + 1]
	var h01 := _heights[(iz + 1) * _verts + ix]
	var h11 := _heights[(iz + 1) * _verts + ix + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Horizontal direction of steepest descent at world XZ (unit, XZ plane).
func downhill_dir(x: float, z: float) -> Vector3:
	var e := 4.0
	var dx := get_height_at(x - e, z) - get_height_at(x + e, z)
	var dz := get_height_at(x, z - e) - get_height_at(x, z + e)
	return Vector3(dx, 0.0, dz).normalized()


func _build() -> void:
	_verts = grid + 1

	var ridge := FastNoiseLite.new()
	ridge.seed = seed_value
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 4
	ridge.frequency = 1.0 / 180.0

	var detail := FastNoiseLite.new()
	detail.seed = seed_value + 7
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail.fractal_octaves = 3
	detail.frequency = 1.0 / 40.0

	_heights.resize(_verts * _verts)
	var half := size / 2.0
	var step := size / float(grid)
	for iz in _verts:
		for ix in _verts:
			var x := -half + ix * step
			var z := -half + iz * step
			_heights[iz * _verts + ix] = _height_at(x, z, ridge, detail)

	_make_mesh(half, step)
	_make_collision()


func _height_at(x: float, z: float, ridge: FastNoiseLite, detail: FastNoiseLite) -> float:
	var r := Vector2(x, z).length() / (size / 2.0)  # 0 at peak, 1 at edge
	var cone := clampf(1.0 - r, 0.0, 1.0)
	var noise_f := _spawn_blend(x, z)
	var h := peak_height * cone
	h += (ridge.get_noise_2d(x, z) * 0.5 + 0.5) * 18.0 * pow(cone, 0.7) * noise_f
	h += detail.get_noise_2d(x, z) * 2.0 * pow(cone, 0.5) * noise_f
	return maxf(h, 0.0)


func _spawn_blend(x: float, z: float) -> float:
	var d := Vector2(x, z).distance_to(SPAWN_XZ)
	if d >= SPAWN_FLAT_RADIUS:
		return 1.0
	var f := clampf(d / SPAWN_FLAT_RADIUS, 0.0, 1.0)
	return f * f * (3.0 - 2.0 * f)  # smoothstep


func _make_mesh(half: float, step: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	st.set_material(mat)

	for iz in _verts:
		for ix in _verts:
			var x := -half + ix * step
			var z := -half + iz * step
			var y := _heights[iz * _verts + ix]
			st.set_color(_color_for_height(y))
			st.add_vertex(Vector3(x, y, z))

	for iz in grid:
		for ix in grid:
			var a := iz * _verts + ix
			var b := a + 1
			var c := a + _verts
			var d := c + 1
			# Godot front faces are CW viewed from the front — this order
			# gives up-facing surfaces (empirically verified: the other
			# order makes the trimesh collide only from below).
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)

	st.generate_normals()

	_mesh = st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	add_child(mi)


func _make_collision() -> void:
	var cs := CollisionShape3D.new()
	cs.shape = _mesh.create_trimesh_shape()
	add_child(cs)


func _color_for_height(y: float) -> Color:
	if y > 92.0:
		return Color(0.92, 0.94, 0.97)  # snow
	if y > 25.0:
		return Color(0.42, 0.40, 0.38)  # rock
	return Color(0.30, 0.45, 0.25)  # grass
