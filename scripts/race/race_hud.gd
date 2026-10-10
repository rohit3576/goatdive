extends CanvasLayer
## Phase 11 styled race HUD (plan: docs/plans/phase-11-ui.md). Replaces the
## Phase 6 text scaffold: panel-backed chip top bar with live coins,
## speedometer, minimap, pause menu, and a button-driven results panel.
## Poll-driven (D3) — one get_race_state() snapshot per frame, zero new
## signals. Runs PROCESS_MODE_ALWAYS so pause owns the input (D6/D7).

const GO_LINGER := 0.7  # s the GO! stays after release


var _manager: RaceManager
var _garage: GarageUI
var _course: CourseBuilder

# Top bar chip values.
var _v_time: Label
var _v_gate: Label
var _v_dist: Label
var _v_pos: Label
var _v_score: Label
var _v_coins: Label

var _count: Label
var _wrong: Label
var _trick_stack: VBoxContainer
var _map: MinimapCard

# Speedometer.
var _speed_val: Label
var _speed_bar: ProgressBar
var _speed_fill: StyleBoxFlat

# Results panel.
var _panel: PanelContainer
var _res_title: Label
var _res_rows: VBoxContainer
var _res_detail: Label
var _res_hint: Label

# Pause menu.
var _pause_layer: Control

var _last_tick := -1
var _go_until := 0.0
var _results_shown := false
var _next_refresh := 0
var _speed_band := -1  # 0 normal · 1 hot · 2 red (recolor only on change)
var _coins_node: Node = null  # Phase 13 Step 6: cached sibling lookup
var _map_next := 0  # msec — Phase 13 Step 6: minimap refresh gate
var _map_last_gate := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_manager = get_parent().get_node_or_null("RaceManager") as RaceManager
	_garage = get_parent().get_node_or_null("Garage") as GarageUI
	_course = get_parent().get_node_or_null("Course") as CourseBuilder
	EventBus.trick_scored.connect(_on_trick_scored)
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not _garage_open():
		_set_paused(not get_tree().paused)


func _garage_open() -> bool:
	return _garage != null and _garage.visible


# --- construction --------------------------------------------------------------


func _build() -> void:
	_build_top_bar()
	_build_center()
	_build_minimap()
	_build_speedometer()
	_build_results()
	_build_pause_menu()


func _build_top_bar() -> void:
	var row := HBoxContainer.new()
	row.anchor_left = 0.5
	row.anchor_right = 0.5
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.offset_top = 10
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	_v_time = _chip(row, "TIME", HudTheme.WHITE)
	_v_gate = _chip(row, "GATE", HudTheme.CYAN)
	_v_dist = _chip(row, "DIST", HudTheme.CYAN)
	_v_pos = _chip(row, "POS", HudTheme.WHITE)
	_v_score = _chip(row, "SCORE", HudTheme.GOLD)
	_v_coins = _chip(row, "COINS", HudTheme.GOLD)


func _chip(row: BoxContainer, caption: String, col: Color) -> Label:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", HudTheme.chip())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	var cap := HudTheme.label(caption, 11, HudTheme.MUTED)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var val := HudTheme.label("-", 20, col)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cap)
	box.add_child(val)
	p.add_child(box)
	row.add_child(p)
	return val


func _build_center() -> void:
	_count = HudTheme.label("", 110, HudTheme.GOLD)
	_count.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(_count)

	_wrong = HudTheme.label("▼ WRONG WAY ▼", 34, HudTheme.RED)
	_wrong.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_wrong.position = Vector2(0.0, 96.0)
	_wrong.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_wrong)

	# Trick label stack (Phase 9): center-top, newest under the last.
	_trick_stack = VBoxContainer.new()
	_trick_stack.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_trick_stack.position = Vector2(0.0, 150.0)
	_trick_stack.add_theme_constant_override("separation", 2)
	add_child(_trick_stack)


func _build_minimap() -> void:
	if _course == null:
		return  # detached contexts (smoke harnesses) — card omitted
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", HudTheme.panel())
	p.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_map = MinimapCard.new()
	_map.custom_minimum_size = Vector2(Config.HUD_MINIMAP_SIZE, Config.HUD_MINIMAP_SIZE)
	p.add_child(_map)
	add_child(p)


func _build_speedometer() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", HudTheme.panel())
	p.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 20)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var cap := HudTheme.label("SPEED", 11, HudTheme.MUTED)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_val = HudTheme.label("0.0", 42, HudTheme.WHITE)
	_speed_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var unit := HudTheme.label("m/s", 12, HudTheme.MUTED)
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(164.0, 10.0)
	var track := HudTheme.chip()
	track.content_margin_left = 0
	track.content_margin_right = 0
	track.content_margin_top = 0
	track.content_margin_bottom = 0
	_speed_fill = HudTheme.chip()
	_speed_fill.content_margin_left = 0
	_speed_fill.content_margin_right = 0
	_speed_fill.content_margin_top = 0
	_speed_fill.content_margin_bottom = 0
	_speed_fill.bg_color = HudTheme.CYAN
	bar.add_theme_stylebox_override("background", track)
	bar.add_theme_stylebox_override("fill", _speed_fill)
	_speed_bar = bar

	box.add_child(cap)
	box.add_child(_speed_val)
	box.add_child(unit)
	box.add_child(bar)
	p.add_child(box)
	add_child(p)


func _build_results() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", HudTheme.panel())
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.alignment = BoxContainer.ALIGNMENT_CENTER

	_res_title = HudTheme.label("", 40, HudTheme.GOLD)
	_res_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_res_rows = VBoxContainer.new()
	_res_rows.add_theme_constant_override("separation", 2)
	_res_detail = HudTheme.label("", 19, HudTheme.WHITE)
	_res_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	var again := HudTheme.styled_button("🏁 RACE AGAIN", true)
	again.pressed.connect(_restart_race)
	var garage_btn := HudTheme.styled_button("🐐 GARAGE")
	var open_garage := func() -> void:
		if _garage != null:
			_garage.open_garage()
	garage_btn.pressed.connect(open_garage)
	actions.add_child(again)
	actions.add_child(garage_btn)

	_res_hint = HudTheme.label("R — race again  |  G — garage & upgrades", 15, HudTheme.MUTED)
	_res_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	box.add_child(_res_title)
	box.add_child(_res_rows)
	box.add_child(_res_detail)
	box.add_child(actions)
	box.add_child(_res_hint)
	_panel.add_child(box)
	_panel.visible = false
	add_child(_panel)


func _build_pause_menu() -> void:
	_pause_layer = Control.new()
	_pause_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_layer.visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.05, 0.07, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_layer.add_child(dim)

	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", HudTheme.panel())
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER

	var title := HudTheme.label("⏸ PAUSED", 34, HudTheme.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var resume := HudTheme.styled_button("RESUME", true)
	resume.pressed.connect(func() -> void: _set_paused(false))
	var restart := HudTheme.styled_button("RESTART RACE")
	restart.pressed.connect(_restart_race)
	var garage_btn := HudTheme.styled_button("GARAGE & UPGRADES")
	garage_btn.pressed.connect(_open_garage_from_pause)
	var hint := HudTheme.label("Esc — resume", 13, HudTheme.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	box.add_child(title)
	box.add_child(resume)
	box.add_child(restart)
	box.add_child(garage_btn)
	box.add_child(hint)
	p.add_child(box)
	_pause_layer.add_child(p)
	add_child(_pause_layer)


# --- pause (D6/D7) ---------------------------------------------------------------


func _set_paused(on: bool) -> void:
	get_tree().paused = on
	_pause_layer.visible = on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	print("UI: pause %s" % ["on" if on else "off"])


func _restart_race() -> void:
	get_tree().paused = false  # paused-reload trap (plan risk table)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()


func _open_garage_from_pause() -> void:
	_set_paused(false)
	if _garage != null:
		_garage.open_garage()


# --- per-frame --------------------------------------------------------------------


func _process(_delta: float) -> void:
	if _manager == null:
		return
	var r := _manager.get_race_state()
	_update_chips(r)
	_update_countdown(r)
	_update_wrong_way(r)
	_update_speedo(r)
	_update_minimap(r)
	_update_results(r)


func _update_chips(r: Dictionary) -> void:
	_v_time.text = r.time_str
	_v_gate.text = "%d/%d" % [r.gates_passed, r.gate_count]
	_v_dist.text = "%d m" % [ceili(r.dist_to_finish)]
	_v_pos.text = "%d/%d" % [r.position, r.racers]
	_v_score.text = "%d ✦" % r.score
	_v_coins.text = "%d 🪙" % _session_coins()


func _session_coins() -> int:
	# D9: during the race the chip counts THIS run's pickups; the bank
	# total lives on the results panel and garage.
	if _manager == null:
		return 0
	if _coins_node == null:
		_coins_node = get_parent().get_node_or_null("Coins")
	return int(_coins_node.call("collected_count")) if _coins_node != null else 0


func _update_countdown(r: Dictionary) -> void:
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


func _update_wrong_way(r: Dictionary) -> void:
	_wrong.visible = r.wrong_way
	if r.wrong_way:
		_wrong.modulate.a = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.012)


func _update_speedo(r: Dictionary) -> void:
	var s := float(r.speed)
	_speed_val.text = "%.1f" % s
	var frac := clampf(s / Config.HUD_SPEEDO_MAX, 0.0, 1.0)
	_speed_bar.value = frac * 100.0
	var band := 2 if frac > 0.85 else (1 if frac > 0.6 else 0)
	if band != _speed_band:
		_speed_band = band
		_speed_fill.bg_color = (
			HudTheme.RED if band == 2 else (HudTheme.GOLD if band == 1 else HudTheme.CYAN)
		)


func _update_minimap(r: Dictionary) -> void:
	if _map == null or _course == null:
		return
	# Phase 13 Step 6: throttled to HUD_MINIMAP_HZ — the map is a strategic
	# aid, not a per-frame instrument. A gate change feeds immediately so
	# the NEXT highlight never lags a twelfth of a second.
	var now := Time.get_ticks_msec()
	var gate := int(r.gates_passed)
	if now < _map_next and gate == _map_last_gate:
		return
	_map_next = now + int(1000.0 / Config.HUD_MINIMAP_HZ)
	_map_last_gate = gate
	_map.feed(_manager.get_racer_markers(), _course.get_gates(), gate)


func _update_results(r: Dictionary) -> void:
	if r.finished and not _results_shown:
		_results_shown = true
		_res_title.text = "FINISH — %s" % r.time_str
		var prog: Dictionary = r.get("progression", {})
		var prog_text := ""
		if not prog.is_empty():
			prog_text = "\n +%d 🪙 (bank: %d)   +%d XP (Lvl %d)" % [
				prog.get("coins_earned", 0), prog.get("total_coins", 0),
				prog.get("xp_earned", 0), prog.get("new_level", 1),
			]
			if bool(prog.get("leveled_up", false)):
				prog_text += "  ⭐ LEVEL UP!"
		_res_detail.text = (
			"best split %s\n top speed %.1f m/s\n crashes %d\n score %d ✦%s%s"
			% [
				r.best_split_str, r.top_speed, r.crashes, r.score,
				(" — " + String(r.best_trick).replace("_", " ")) if r.best_trick != "" else "",
				prog_text,
			]
		)
		_panel.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # buttons are clickable
		_refresh_rows(r)
	elif r.finished and Time.get_ticks_msec() >= _next_refresh:
		_next_refresh = Time.get_ticks_msec() + 500  # AI trickle in post-finish
		_refresh_rows(r)


# --- tricks (Phase 9, restyled) ----------------------------------------------------


func _on_trick_scored(name: String, points: int, goat: Node3D) -> void:
	if _manager == null or not _manager.is_player(goat):
		return
	var l := HudTheme.label("%s  +%d" % [name.to_upper().replace("_", " "), points], 26, HudTheme.GOLD)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_trick_stack.add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(Config.HUD_TRICK_POP_SECS * 0.65)
	tw.tween_property(l, "modulate:a", 0.0, Config.HUD_TRICK_POP_SECS * 0.35)
	tw.tween_callback(l.queue_free)


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
	var fresh := false
	for s in r.standings:
		if not s.finished:
			fresh = true
			break
	if not fresh and _res_rows.get_child_count() > 0:
		return  # all in — stop rebuilding (plan risk: refresh churn)
	for child in _res_rows.get_children():
		child.queue_free()
	for s in r.standings:
		var row := HudTheme.label(
			"%d. %s  %s" % [s.pos, s.name, s.time_str],
			22,
			HudTheme.GOLD if s.is_player else HudTheme.WHITE
		)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_res_rows.add_child(row)


# --- minimap (D5) -------------------------------------------------------------------


class MinimapCard:
	extends Control
	## North-up XZ projection (plan D5): course polyline through gate
	## positions, gate dots (NEXT highlighted), finish marker, AI dots in
	## profile colors, player heading arrow. Pure world_to_map transform.

	var markers: Array[Dictionary] = []
	var gate_pts: PackedVector2Array = PackedVector2Array()
	var next_gate := -1

	func feed(racers: Array[Dictionary], gates: Array, player_gate_idx: int) -> void:
		markers = racers
		gate_pts.clear()
		for g in gates:
			var gp: Vector3 = g.global_position
			gate_pts.append(Vector2(gp.x, gp.z))
		next_gate = player_gate_idx
		queue_redraw()

	func _draw() -> void:
		if gate_pts.size() < 2:
			return
		var b := _bounds()
		# Course spine — muted cyan.
		var line := PackedVector2Array()
		for p in gate_pts:
			line.append(world_to_map(p, b, size))
		draw_polyline(line, Color(HudTheme.CYAN, 0.55), 2.0)
		# Gates: passed dim, NEXT gold & fat, finish white square.
		for i in gate_pts.size():
			var m := world_to_map(gate_pts[i], b, size)
			if i == gate_pts.size() - 1:
				draw_rect(Rect2(m - Vector2(4, 4), Vector2(8, 8)), HudTheme.WHITE)
			elif i == next_gate:
				draw_circle(m, 5.0, HudTheme.GOLD)
			else:
				draw_circle(m, 3.0, Color(0.8, 0.85, 0.9, 0.5))
		# Racers: AI dots, player arrow.
		for mk in markers:
			var m := world_to_map(Vector2(mk.pos.x, mk.pos.z), b, size)
			var col: Color = mk.color
			if bool(mk.finished):
				col = Color(col, 0.4)
			if bool(mk.is_player):
				var dir := Vector2(-sin(float(mk.yaw)), -cos(float(mk.yaw)))
				draw_set_transform(m, atan2(dir.y, dir.x), Vector2.ONE)
				var arrow := PackedVector2Array([Vector2(8, 0), Vector2(-5, 5), Vector2(-5, -5)])
				draw_colored_polygon(arrow, col)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				draw_circle(m, 4.0, col)

	func _bounds() -> Rect2:
		var r := Rect2(gate_pts[0], Vector2.ZERO)
		for p in gate_pts:
			r = r.expand(p)
		for mk in markers:
			r = r.expand(Vector2(mk.pos.x, mk.pos.z))
		return r

	## Pure world(XZ)→map transform — smoke-testable headless (plan D5).
	static func world_to_map(p: Vector2, b: Rect2, map_size: Vector2) -> Vector2:
		var span := Vector2(
			maxf(b.size.x, 1.0), maxf(b.size.y, 1.0)
		)
		var scale := minf(
			(map_size.x - Config.HUD_MINIMAP_PAD * 2.0) / span.x,
			(map_size.y - Config.HUD_MINIMAP_PAD * 2.0) / span.y
		)
		var centered := p - b.position - span * 0.5
		return Vector2(centered.x, centered.y) * scale + map_size * 0.5
