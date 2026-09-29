extends Node3D
## Builds the two POV horns under the camera (Phase 2, decision D5).
## Placement/splay values are tuning bait — move them to Config if they churn.

const HornMesh := preload("res://scripts/utils/horn_mesh.gd")

const SIDE_OFFSET := 0.06
const PITCH_DEG := -18.0
const SPLAY_DEG := 14.0


func _ready() -> void:
	_build_horn(-1.0)
	_build_horn(1.0)


func _build_horn(side: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = HornMesh.build(Config.HORN_LENGTH, Config.HORN_CURVATURE)
	mi.position = Vector3(side * SIDE_OFFSET, 0.0, 0.0)
	mi.rotation = Vector3(deg_to_rad(PITCH_DEG), 0.0, deg_to_rad(side * SPLAY_DEG))

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.80, 0.72)
	mat.roughness = 0.55
	mi.material_override = mat

	add_child(mi)


## Phase 10: updates horn materials for the first-person camera view.
func apply_skin(skin_id: String) -> void:
	var mat := StandardMaterial3D.new()
	match skin_id:
		"snow_phantom":
			mat.albedo_color = Color(0.75, 0.95, 1.0)
			mat.roughness = 0.15
			mat.metallic = 0.2
			mat.emission_enabled = true
			mat.emission = Color(0.08, 0.25, 0.35)
		"obsidian_ram":
			mat.albedo_color = Color(0.12, 0.12, 0.14)
			mat.roughness = 0.2
			mat.metallic = 0.8
		"golden_capra":
			mat.albedo_color = Color(1.0, 0.84, 0.2)
			mat.roughness = 0.12
			mat.metallic = 0.95
		_:
			mat.albedo_color = Color(0.85, 0.80, 0.72)
			mat.roughness = 0.55
	for child in get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = mat

