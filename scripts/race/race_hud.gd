extends CanvasLayer
## Phase 6 minimal race HUD (plan: docs/plans/phase-6-race-system.md D7):
## scaffolding the Phase 11 reskin replaces — countdown center, top bar,
## wrong-way blink, results panel. Default font only (web-safe).

const GO_LINGER := 0.7  # s the GO! stays after release

var _manager: RaceManager
var _top: Label
var _count: Label
var _wrong: Label
var _panel: PanelContainer
var _res_title: Label
var _res_rows: VBoxContainer
var _res_detail: Label
var _res_hint: Label

var _last_tick := -1
var _go_until := 0.0
var _results_shown := false
var _next_refresh := 0


func _ready() -> void:
	_manager = get_parent().get_node_or_null("RaceManager") as RaceManager
	if _manager == null:
		set_process(false)
		return
	_build()


func _build() -> void:
	_top = _make_label(20, Color.WHITE, Control.PRESET_CENTER_TOP)
	_top.position = Vector2(0.0, 14.0)
	add_child(_top)
	_count = _make_label(96, Color(1.0, 0.85, 0.3), Control.PRESET_CENTER)
	add_child(_count)
	_wrong = _make_label(34, Color(1.0, 0.25, 0.2), Control.PRESET_CENTER_TOP)
	_wrong.position = Vector2(0.0, 84.0)
	_wrong.text = "WRONG WAY"
	add_child(_wrong)

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_res_title = _make_label(40, Color(1.0, 0.85, 0.3), Control.PRESET_TOP_LEFT)
	_res_rows = VBoxContainer.new()
	_res_rows.add_theme_constant_override("separation", 2)
	_res_detail = _make_label(20, Color.WHITE, Control.PRESET_TOP_LEFT)
	_res_hint = _make_label(16, Color(0.7, 0.7, 0.7), Control.PRESET_TOP_LEFT)
	_res_hint.text = "R — race again"
	col.add_child(_res_title)
	col.add_child(_res_rows)
	col.add_child(_res_detail)
	col.add_child(_res_hint)
	margin.add_child(col)
	_panel.add_child(margin)
	_panel.visible = false
	add_child(_panel)


func _process(_delta: float) -> void:
	if _manager == null:
		return
	var r := _manager.get_race_state()

	# Top bar: TIME · GATE · distance · position (honest "1/1", D6).
	_top.text = "%s   GATE %d/%d   %d m   POS %d/%d" % [
		r.time_str, r.gates_passed, r.gate_count, ceili(r.dist_to_finish),
		r.position, r.racers,
	]

	# Countdown ticks (poll-driven: the bus stays for cross-module news).
	var counting: bool = r.state == "countdown"
	if counting:
		var tick := ceili(r.countdown)
		if tick != _last_tick:
			_last_tick = tick
			_pop_count(str(tick))
	elif _last_tick > 0:
		_last_tick = 0
		_go_until = Time.get_ticks_msec() / 1000.0 + GO_LINGER
		_pop_count("GO!")
	if not counting and Time.get_ticks_msec() / 1000.0 > _go_until:
		_count.text = ""
		_count.modulate.a = 0.0

	# Wrong-way blink.
	_wrong.visible = r.wrong_way
	if r.wrong_way:
		_wrong.modulate.a = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.012)

	# Results panel (lazy fill — state arrives with FINISHED, not the signal arg).
	if r.finished and not _results_shown:
		_results_shown = true
		_res_title.text = "FINISH — %s" % r.time_str
		_res_detail.text = (
			"best split %s\n top speed %.1f m/s\n crashes %d"
			% [r.best_split_str, r.top_speed, r.crashes]
		)
		_panel.visible = true
		_refresh_rows(r)
	elif r.finished and Time.get_ticks_msec() >= _next_refresh:
		_next_refresh = Time.get_ticks_msec() + 500  # AI trickle in post-finish
		_refresh_rows(r)


func _pop_count(text: String) -> void:
	_count.text = text
	_count.reset_size()
	_count.pivot_offset = _count.size * 0.5
	_count.scale = Vector2(1.6, 1.6)
	_count.modulate.a = 0.2
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_count, "scale", Vector2.ONE, 0.35)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	tw.tween_property(_count, "modulate:a", 1.0, 0.18)


func _refresh_rows(r: Dictionary) -> void:
	for child in _res_rows.get_children():
		child.queue_free()
	for s in r.standings:
		var row := _make_label(
			22,
			Color(1.0, 0.85, 0.3) if s.is_player else Color.WHITE,
			Control.PRESET_TOP_LEFT
		)
		row.text = "%d. %s  %s" % [s.pos, s.name, s.time_str]
		_res_rows.add_child(row)


func _make_label(size: int, col: Color, preset: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(preset)
	return l
