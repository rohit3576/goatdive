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
