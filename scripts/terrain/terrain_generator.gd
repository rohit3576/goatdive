class_name TerrainGenerator
extends StaticBody3D
## Procedural alpine terrain (Phase 2 foundation, Phase 5 v2: domain warp,
## cliff bands, ledges — plan: docs/plans/phase-5-realistic-mountain.md D2).
##
## Radial cone (the mountain mass) + domain-warped ridged fBm (ridges) +
## detail noise → quantized cliff bands carve walkable treads and steep
## risers into the rock zone → one heights array drives the visual
## ArrayMesh; collision is a trimesh generated FROM that mesh so physics
## and visuals can never agree to disagree. (HeightMapShape3D was tried in
## Phase 2 — its data ordering mismatched and the goat fell through;
## trimesh removed the whole class of bug. See completion doc.)
##
## API FROZEN (Phase 5 D2 — controller, camera, vegetation, future race
## system all depend on these): get_height_at / downhill_dir / surface_at /
## slope_deg_at. New look lives in @export tunables, not new signatures.

@export var seed_value: int = 1337
@export var size := 1024.0
@export var peak_height := 260.0
@export var grid := 192

# Phase 5 look tunables (first guesses — F5 + reffimg/ steer, plan D8).
@export var snow_line := 170.0
@export var warp_strength := 60.0  # m of domain warp on structural noise
@export var ridge_amp := 34.0
@export var detail_amp := 3.5
@export var band_height := 10.0  # m per cliff band
@export var band_tread := 0.5  # fraction of a band that stays flat (ledges)
@export var band_rise := 0.35  # fraction over which the riser climbs

# Spawn disc: noise blends to zero inside this radius so the start is pure
# cone slope (~27°) — standable, runnable, no spawn-slide (plan risk #1).
# The blend is the FINAL gate: warp/bands never touch the spawn disc.
const SPAWN_XZ := Vector2(0.0, -24.0)
const SPAWN_FLAT_RADIUS := 26.0

# Surface classification (Phase 3, decision D1/D2).
enum Surface { ROCK, GRASS, SNOW, ICE }
const ICE_MASK_THRESHOLD := 0.35

var _heights := PackedFloat32Array()
var _verts := 0  # grid + 1 samples per side
var _mesh: ArrayMesh
var _ice_mask := FastNoiseLite.new()
var _warp_noise := FastNoiseLite.new()


func _ready() -> void:
	_ice_mask.seed = seed_value + 13
	_ice_mask.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ice_mask.frequency = 1.0 / 60.0
	_warp_noise.seed = seed_value + 29
	_warp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_warp_noise.fractal_octaves = 2
	_warp_noise.frequency = 1.0 / 300.0
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


## Surface type at world XZ — the one classifier shared by grip and vertex
## colors, so what you see is what you slide on.
func surface_at(x: float, z: float) -> int:
	# Spawn disc: bare rock — full grip start, no snow/ice slides at spawn.
	if _spawn_blend(x, z) < 1.0:
		return Surface.ROCK
	var h := get_height_at(x, z)
	if h > snow_line:
		if _ice_mask.get_noise_2d(x, z) > ICE_MASK_THRESHOLD:
			return Surface.ICE
		return Surface.SNOW
	if h > 45.0 or slope_deg_at(x, z) > 30.0:
		return Surface.ROCK
	return Surface.GRASS


## Terrain slope in degrees at world XZ (finite-difference gradient).
func slope_deg_at(x: float, z: float) -> float:
	var e := 2.0
	var hx := get_height_at(x + e, z) - get_height_at(x - e, z)
	var hz := get_height_at(x, z + e) - get_height_at(x, z - e)
	return rad_to_deg(atan(sqrt(hx * hx + hz * hz) / (2.0 * e)))


func _build() -> void:
	var t0 := Time.get_ticks_msec()
	_verts = grid + 1

	var ridge := FastNoiseLite.new()
	ridge.seed = seed_value
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 4
	ridge.frequency = 1.0 / 360.0

	var detail := FastNoiseLite.new()
	detail.seed = seed_value + 7
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail.fractal_octaves = 3
	detail.frequency = 1.0 / 80.0

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
	# Load-time ledger (plan risk #1): the web build budget's first number.
	print(
		"TERRAIN: %dx%d heights, %d tris, build+trimesh %d ms"
		% [_verts, _verts, grid * grid * 2, Time.get_ticks_msec() - t0]
	)


func _height_at(x: float, z: float, ridge: FastNoiseLite, detail: FastNoiseLite) -> float:
	var r := Vector2(x, z).length() / (size / 2.0)  # 0 at peak, 1 at edge
	var cone := clampf(1.0 - r, 0.0, 1.0)
	var noise_f := _spawn_blend(x, z)
	var h := peak_height * cone
	if noise_f > 0.0:
		# Domain warp — ridges stop reading as concentric cone ripples.
		var wx := x + _warp_noise.get_noise_2d(x * 0.7, z * 0.7) * warp_strength
		var wz := z + _warp_noise.get_noise_2d(x * 0.7 + 137.0, z * 0.7 + 91.0) * warp_strength
		h += (ridge.get_noise_2d(wx, wz) * 0.5 + 0.5) * ridge_amp * pow(cone, 0.7) * noise_f
		h += detail.get_noise_2d(wx, wz) * detail_amp * pow(cone, 0.5) * noise_f
		h = maxf(h, 0.0)
		# Cliff bands: quantize the rock zone — flat treads (ledges) between
		# steep risers. Fades in above the grassy toe, out toward the snow
		# line. Bands follow the (warped) height contours, so they read as
		# cliff strata, not staircases.
		var band_mask := (
			smoothstep(55.0, 105.0, h) * (1.0 - smoothstep(snow_line - 50.0, snow_line, h))
		)
		if band_mask > 0.001:
			h = lerpf(h, _band(h), band_mask)
	return h


## Cliff-band remap (plan D2): the first band_tread fraction of every band
## stays flat (the tread/ledge), the riser climbs over band_rise — locally
## steepening slopes without changing the total drop. Heightmap-honest:
## no overhangs, just aggressive treads.
func _band(h: float) -> float:
	var steps := floorf(h / band_height)
	var f := (h - steps * band_height) / band_height
	var rise := smoothstep(band_tread, band_tread + band_rise, f)
	return (steps + rise) * band_height


func _spawn_blend(x: float, z: float) -> float:
	var d := Vector2(x, z).distance_to(SPAWN_XZ)
	if d >= SPAWN_FLAT_RADIUS:
		return 1.0
	var f := clampf(d / SPAWN_FLAT_RADIUS, 0.0, 1.0)
	return f * f * (3.0 - 2.0 * f)  # smoothstep


func _make_mesh(half: float, step: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Phase 5 look v2 (plan D3): the shader shades WITHIN classifier zones;
	# COLOR.rgb carries the zone color, COLOR.a the zone id / 3.0. Visual
	# snow == grip snow — both come from surface_at().
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain_blend.gdshader")
	mat.set_shader_parameter("snow_line", snow_line)
	st.set_material(mat)

	for iz in _verts:
		for ix in _verts:
			var x := -half + ix * step
			var z := -half + iz * step
			var surf := surface_at(x, z)
			var c := _color_for_surface(surf)
			c.a = float(surf) / 3.0
			st.set_color(c)
			st.add_vertex(Vector3(x, _heights[iz * _verts + ix], z))

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


func _color_for_surface(surf: int) -> Color:
	match surf:
		Surface.ICE:
			return Color(0.72, 0.84, 0.95)
		Surface.SNOW:
			return Color(0.92, 0.94, 0.97)
		Surface.ROCK:
			return Color(0.42, 0.40, 0.38)
		_:
			return Color(0.30, 0.45, 0.25)
