extends Node3D
## Mountain level root (Phase 2): computes spawn near the peak facing downhill,
## spawns the goat, hands it its respawn transform.

const GOAT := preload("res://scenes/goat/goat.tscn")
const SPAWN_OFFSET := Vector2(0.0, -24.0)  # 24 m north of the peak (peak at origin)


func _ready() -> void:
	var terrain := $Terrain as TerrainGenerator
	var x := SPAWN_OFFSET.x
	var z := SPAWN_OFFSET.y
	var h: float = terrain.get_height_at(x, z)
	var spawn := Vector3(x, h + 1.2, z)

	var goat := GOAT.instantiate() as GoatController
	add_child(goat)
	goat.global_position = spawn
	goat.look_at(spawn + terrain.downhill_dir(x, z))
	goat.setup_spawn(goat.global_transform)
