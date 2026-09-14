extends CanvasLayer
## F3 debug overlay (Phase 3, decision D9): live goat physics readout for
## feel tuning. Reads a snapshot via GoatController.get_debug_state().

var _label: Label
var _goat: GoatController


func _ready() -> void:
	_goat = get_parent() as GoatController
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
	_label.text = "%s  %s  slope %.0f°  speed %.1f m/s\nvy %.1f  coyote %.2f  buffer %.2f" % [
		d.state, d.surface, d.slope, d.speed, d.vy, d.coyote, d.buffer,
	]
