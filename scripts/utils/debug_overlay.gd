extends CanvasLayer
## F3 debug overlay (Phase 3, decision D9): live goat physics readout for
## feel tuning. Reads a snapshot via GoatController.get_debug_state().

var _label: Label
var _goat: GoatController
var _fx: CameraFx
var _race: RaceManager


func _ready() -> void:
	_goat = get_parent() as GoatController
	_fx = _goat.get_node_or_null("Head/Camera3D") as CameraFx
	_race = get_tree().get_first_node_in_group("race_manager") as RaceManager
	_label = Label.new()
	_label.position = Vector2(12.0, 12.0)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		visible = not visible


func _process(_delta: float) -> void:
	if not visible or _goat == null:
		return
	var d := _goat.get_debug_state()
	var fx_line := ""
	if _fx != null:
		var f := _fx.get_fx_debug()
		fx_line = "\nfx fov %.1f  trauma %.2f  dip %.3f" % [f.fov, f.trauma, f.dip]
	var race_line := ""
	if _race != null:
		var r := _race.get_race_state()
		race_line = "\nrace %s  gate %d/%d  %.0f m  respawn G%d  hits %d" % [
			r.state, r.gates_passed, r.gate_count, r.dist_to_finish, r.gates_passed, r.hits,
		]
		for ai in r.ai_states:
			race_line += "\nai %s  gate %s  stuck %.1f  tp %d  av %d" % [
				ai.profile, ai.gate, ai.stuck, ai.teleports, ai.avoid,
			]
	_label.text = "%s  %s  slope %.0f°  speed %.1f m/s\nvy %.1f  coyote %.2f  buffer %.2f%s%s" % [
		d.state, d.surface, d.slope, d.speed, d.vy, d.coyote, d.buffer, fx_line, race_line,
	]
