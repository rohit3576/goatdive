extends Node3D
## Phase 1 bootstrap: mounts the test level and wires debug input.
## No gameplay here — goat controller is Phase 2+.

const SceneLoader := preload("res://scripts/game/scene_loader.gd")
const TEST_LEVEL := "res://scenes/main/test_level.tscn"

@onready var world: Node3D = $World


func _ready() -> void:
	print("GoatDive %s — main scene ready" % Config.VERSION)
	DisplayServer.window_set_title("GoatDive — %s" % Config.VERSION)
	GameState.current_scene_path = TEST_LEVEL
	SceneLoader.switch(world, TEST_LEVEL)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)
	elif event.is_action_pressed("restart"):
		print("[restart] wired (Phase 2)")
