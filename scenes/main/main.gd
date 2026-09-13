extends Node3D
## Bootstrap: mounts the default level and wires pause/restart.
## No gameplay here — goat controller owns movement.

const SceneLoader := preload("res://scripts/game/scene_loader.gd")
const LEVEL := "res://scenes/terrain/mountain_level.tscn"

@onready var world: Node3D = $World


func _ready() -> void:
	print("GoatDive %s — main scene ready" % Config.VERSION)
	DisplayServer.window_set_title("GoatDive — %s" % Config.VERSION)
	GameState.current_scene_path = LEVEL
	SceneLoader.switch(world, LEVEL)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)
	elif event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
