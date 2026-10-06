extends Node3D
## Bootstrap: mounts the default level and wires restart.
## No gameplay here — goat controller owns movement.
## Phase 11: Esc/pause moved to the HUD pause menu (docs/plans/phase-11-ui.md
## D7) — this scaffold released the mouse; the menu owns it now.

const SceneLoader := preload("res://scripts/game/scene_loader.gd")
const LEVEL := "res://scenes/terrain/mountain_level.tscn"

@onready var world: Node3D = $World


func _ready() -> void:
	print("GoatDive %s — main scene ready" % Config.VERSION)
	DisplayServer.window_set_title("GoatDive — %s" % Config.VERSION)
	_apply_render_profile()
	GameState.current_scene_path = LEVEL
	SceneLoader.switch(world, LEVEL)


## Phase 13 D8 web render floor: on web builds only, cap the compat
## renderer's directional shadow atlas (4096 default is heavy for GLES3)
## and leave MSAA off — a bandwidth tax the vertex-color + fog art style
## doesn't pay back. Desktop boots untouched. Knobs live in Config so
## Phase 14 can A/B them on-device without code edits.
func _apply_render_profile() -> void:
	if not OS.has_feature("web"):
		return
	RenderingServer.directional_shadow_atlas_set_size(Config.WEB_SHADOW_SIZE, true)
	get_viewport().msaa = Viewport.MSAA_DISABLED
	print("RENDER: web floor applied — shadow %d, msaa off" % Config.WEB_SHADOW_SIZE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
