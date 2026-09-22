extends Node3D
## Mountain level root (Phase 2): computes spawn near the peak facing downhill,
## spawns the goat, hands it its respawn transform.
## Phase 7 (plan D7/D8): spawns the HERD — player front-center, three AI
## goats staggered behind on the disc, tinted, brain-driven, player rig
## stripped (mouse must not steer the herd, only the player camera renders).

const GOAT := preload("res://scenes/goat/goat.tscn")
const AI_BRAIN := preload("res://scripts/race/ai_goat.gd")
const SPAWN_OFFSET := Vector2(0.0, -24.0)  # 24 m north of the peak (peak at origin)


func _ready() -> void:
	var terrain := $Terrain as TerrainGenerator
	var x := SPAWN_OFFSET.x
	var z := SPAWN_OFFSET.y
	var h: float = terrain.get_height_at(x, z)
	var spawn := Vector3(x, h + 1.2, z)

	# Player first — their camera becomes the current one.
	var goat := GOAT.instantiate() as GoatController
	add_child(goat)
	goat.global_position = spawn
	goat.look_at(spawn + terrain.downhill_dir(x, z))
	goat.setup_spawn(goat.global_transform)
	(goat.get_node("Head/Camera3D") as Camera3D).current = true

	# Phase 9: the trick detector is player-only (D7) — tricks are
	# listeners on the attributed signal vocabulary, never physics.
	var tricks := TrickDetector.new()
	tricks.name = "TrickDetector"
	goat.add_child(tricks)

	# Phase 7 D7: spawn grid — staggered behind/beside the player, ≥ 3 m
	# apart, all facing gate 0. Slots stay CLOSE to the spawn center where
	# the disc is pure cone — further out, the 13% noise blend makes local
	# >42° bumps that slide AI during the countdown (probe-F finding).
	var fwd := terrain.downhill_dir(x, z)
	var right := Vector3(fwd.z, 0.0, -fwd.x)
	var slots := [
		{"name": "CAUTIOUS", "off": -fwd * 3.0 + right * 2.0, "color": Config.AI_COLOR_CAUTIOUS},
		{"name": "BOLD", "off": -fwd * 4.5 - right * 2.0, "color": Config.AI_COLOR_BOLD},
		{"name": "RECKLESS", "off": -fwd * 6.0, "color": Config.AI_COLOR_RECKLESS},
	]
	var racers: Array = [{"name": "YOU", "node": goat}]
	for slot in slots:
		racers.append({
			"name": slot["name"],
			"node": _spawn_ai(terrain, spawn, fwd, slot),
		})

	# Phase 6: the race owns countdown/timer/gates — wired here because the
	# goats don't exist during the manager's own _ready (children first).
	var race := get_node_or_null("RaceManager") as RaceManager
	if race != null:
		race.begin(racers)


func _spawn_ai(
	terrain: TerrainGenerator, spawn: Vector3, fwd: Vector3, slot: Dictionary
) -> GoatController:
	var ai := GOAT.instantiate() as GoatController
	add_child(ai)
	var p: Vector3 = spawn + slot["off"]
	p.y = terrain.get_height_at(p.x, p.z) + 1.2
	ai.global_position = p
	ai.look_at(p + fwd)
	ai.setup_spawn(ai.global_transform)

	# Strip the player rig: no overlay, no mouse-look (head_camera yaws the
	# BODY — the herd must not follow the player's mouse), no camera/FX.
	(ai.get_node("DebugOverlay") as CanvasLayer).queue_free()
	var head := ai.get_node("Head") as Node3D
	head.set_process_unhandled_input(false)
	var cam := head.get_node("Camera3D") as Camera3D
	cam.current = false
	cam.set_process(false)  # its CameraFx offsets are pointless off-screen

	# Herd tint (D8): one material, both body meshes.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = slot["color"]
	(ai.get_node("Body/Torso") as MeshInstance3D).material_override = mat
	(ai.get_node("Body/Snout") as MeshInstance3D).material_override = mat

	var brain := AI_BRAIN.new()
	brain.name = "AiGoat"
	brain.profile = slot["name"]
	ai.add_child(brain)
	return ai
