class_name Atmosphere
extends Node3D
## Phase 5 atmosphere (plan: docs/plans/phase-5-realistic-mountain.md D5):
## altitude fog curve (valley mist thick, above the snow line thin),
## drifting soft cloud billboards, a low-poly distant-peak ring beyond the
## playable radius, and one animated water plane at the valley level
## (visual only — no swim gameplay this phase).

@export var cloud_count := 8
@export var water_level := 6.0
@export var wind_dir := Vector2(1.0, 0.35)  # cloud drift, m/s

var _env: Environment
var _clouds: Array[Node3D] = []
var _cloud_radius := 620.0

# Fog curve: density by camera altitude.
const FOG_LOW := 0.0015  # thin, above ~200 m
const FOG_VALLEY := 0.006  # thick valley mist


func _ready() -> void:
	var we := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null:
		_env = we.environment
	_make_clouds()
	_make_distant_peaks()
	_make_water()


func _process(delta: float) -> void:
	# Fog follows the camera's altitude — descending into the valley should
	# feel like dropping into cloud.
	if _env != null:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var alt := cam.global_position.y
			_env.fog_density = lerpf(
				FOG_LOW, FOG_VALLEY, 1.0 - smoothstep(40.0, 200.0, alt)
			)
	# Clouds drift with the wind, wrapping around the mountain.
	for cloud in _clouds:
		cloud.global_position += Vector3(wind_dir.x, 0.0, wind_dir.y) * delta
		if Vector2(cloud.global_position.x, cloud.global_position.z).length() > _cloud_radius + 160.0:
			cloud.global_position *= -0.92  # wrap to the far side


## Soft blobby cloud sprite, painted procedurally (no texture assets).
func _cloud_texture() -> ImageTexture:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var blobs: Array[Vector2] = []
	var radii: Array[float] = []
	for i in 5:
		blobs.append(Vector2(rng.randf_range(38, 90), rng.randf_range(48, 80)))
		radii.append(rng.randf_range(26.0, 40.0))
	for y in 128:
		for x in 128:
			var a := 0.0
			for i in blobs.size():
				var d := Vector2(x, y).distance_to(blobs[i]) / radii[i]
				a = maxf(a, clampf(1.0 - d, 0.0, 1.0))
			a = pow(clampf(a * 1.15 - 0.15, 0.0, 1.0), 1.6)
			img.set_pixel(x, y, Color(1, 1, 1, a * 0.65))
	return ImageTexture.create_from_image(img)


func _make_clouds() -> void:
	var tex := _cloud_texture()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in cloud_count:
		var s := Sprite3D.new()
		s.texture = tex
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.modulate = Color(1.0, 1.0, 1.0, rng.randf_range(0.55, 0.8))
		var ang := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(_cloud_radius - 120.0, _cloud_radius + 80.0)
		var scale := rng.randf_range(140.0, 240.0)
		s.scale = Vector3(scale, scale * 0.35, 1.0)
		add_child(s)
		s.global_position = Vector3(cos(ang) * r, rng.randf_range(330.0, 420.0), sin(ang) * r)
		_clouds.append(s)


## Low-poly peak silhouettes beyond the playable radius — fog does the rest.
func _make_distant_peaks() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.52, 0.55, 0.63)
	mat.roughness = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for i in 7:
		var mesh := CylinderMesh.new()  # top_radius 0 = cone
		mesh.top_radius = 0.0
		mesh.bottom_radius = rng.randf_range(70.0, 130.0)
		mesh.height = rng.randf_range(150.0, 280.0)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ang := i * TAU / 7.0 + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(680.0, 880.0)
		add_child(mi)
		mi.global_position = Vector3(cos(ang) * r, rng.randf_range(-20.0, 10.0), sin(ang) * r)


func _make_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(2200, 2200)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3(0.0, water_level, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
