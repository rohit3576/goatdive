class_name GarageUI
extends CanvasLayer
## Phase 10 — Pre-Race Garage & Mountain Expeditions UI (Decision D8).
## Provides an in-game staging interface for:
## 1. Browsing and selecting among the 5 mountains.
## 2. Upgrading goat stats (Speed, Jump, Grip, Stamina).
## 3. Equipping/buying horn & fleece skins.
## 4. Launching into the chosen mountain expedition.

const MountainCatalog := preload("res://scripts/terrain/mountain_catalog.gd")

var _mountain_ids: Array[String] = []
var _mountain_idx: int = 0

var _panel: PanelContainer
var _status_lbl: Label
var _mountain_name_lbl: Label
var _mountain_desc_lbl: Label
var _mountain_stats_lbl: Label
var _mountain_select_btn: Button

var _stat_labels: Dictionary = {}
var _stat_buttons: Dictionary = {}
var _skin_buttons: Dictionary = {}


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS  # Phase 11: usable while paused
	_mountain_ids = MountainCatalog.get_all_ids()
	_sync_current_mountain_index()
	_build_ui()
	_refresh_all()
	visible = false

	# Connect to progression events for live UI updates.
	EventBus.coins_changed.connect(func(_tot: int, _d: int) -> void: _refresh_all())
	EventBus.xp_gained.connect(func(_tot: int, _d: int) -> void: _refresh_all())
	EventBus.level_up.connect(func(_lvl: int) -> void: _refresh_all())
	EventBus.upgrade_purchased.connect(func(_st: String, _tier: int) -> void: _refresh_all())


func _sync_current_mountain_index() -> void:
	var p := get_node_or_null("/root/Progression")
	var cur := "alpine_valley"
	if p != null:
		cur = String(p.get("current_mountain"))
	var idx := _mountain_ids.find(cur)
	_mountain_idx = maxi(0, idx)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_G:
			toggle_garage()
		elif event.keycode == KEY_ESCAPE and visible:
			close_garage()


func toggle_garage() -> void:
	if visible:
		close_garage()
	else:
		open_garage()


func open_garage() -> void:
	_sync_current_mountain_index()
	_refresh_all()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_garage() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- UI Construction ---------------------------------------------------------


func _build_ui() -> void:
	# Dimmed background backdrop.
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.07, 0.88)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", HudTheme.panel())
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_panel.add_child(margin)
	add_child(_panel)

	var root_col := VBoxContainer.new()
	root_col.add_theme_constant_override("separation", 16)
	root_col.custom_minimum_size = Vector2(760, 520)
	margin.add_child(root_col)

	# 1. Header (Title + Status Coins/XP)
	var header := HBoxContainer.new()
	var title := _make_label("🐐 GOAT GARAGE & EXPEDITIONS", 26, Color(1.0, 0.85, 0.3))
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_status_lbl = _make_label("Coins: 0 🪙  Level 1 (0 XP)", 18, Color.WHITE)
	header.add_child(_status_lbl)
	root_col.add_child(header)

	var divider1 := HSeparator.new()
	root_col.add_child(divider1)

	# 2. Mountain Expeditions Station
	var mtn_box := VBoxContainer.new()
	mtn_box.add_theme_constant_override("separation", 6)
	var mtn_header := _make_label("🏔️ SELECT EXPEDITION", 18, Color(0.6, 0.85, 1.0))
	mtn_box.add_child(mtn_header)

	var carousel_row := HBoxContainer.new()
	carousel_row.add_theme_constant_override("separation", 12)
	var prev_btn := _make_button(" ◀ ")
	prev_btn.pressed.connect(_prev_mountain)
	carousel_row.add_child(prev_btn)

	var mtn_info := VBoxContainer.new()
	mtn_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mountain_name_lbl = _make_label("Alpine Valley [Beginner]", 22, Color.WHITE)
	_mountain_desc_lbl = _make_label("Rolling green meadows & gentle fall lines", 14, Color(0.8, 0.8, 0.8))
	_mountain_stats_lbl = _make_label("Peak: 260m  Snowline: 170m", 14, Color(0.7, 0.75, 0.8))
	mtn_info.add_child(_mountain_name_lbl)
	mtn_info.add_child(_mountain_desc_lbl)
	mtn_info.add_child(_mountain_stats_lbl)
	carousel_row.add_child(mtn_info)

	var next_btn := _make_button(" ▶ ")
	next_btn.pressed.connect(_next_mountain)
	carousel_row.add_child(next_btn)

	_mountain_select_btn = _make_button("SELECT")
	_mountain_select_btn.custom_minimum_size = Vector2(160, 42)
	_mountain_select_btn.pressed.connect(_select_mountain)
	carousel_row.add_child(_mountain_select_btn)

	mtn_box.add_child(carousel_row)
	root_col.add_child(mtn_box)

	var divider2 := HSeparator.new()
	root_col.add_child(divider2)

	# 3. Middle Section: Upgrades (Left) & Skins (Right)
	var mid_row := HBoxContainer.new()
	mid_row.add_theme_constant_override("separation", 24)
	mid_row.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Upgrades Column
	var upg_col := VBoxContainer.new()
	upg_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upg_col.add_theme_constant_override("separation", 8)
	var upg_header := _make_label("⚡ GOAT ATHLETICISM (UPGRADES)", 18, Color(0.4, 0.95, 0.5))
	upg_col.add_child(upg_header)

	var stats: Array[String] = ["speed", "jump", "grip", "stamina"]
	for st in stats:
		var stat_row := HBoxContainer.new()
		stat_row.add_theme_constant_override("separation", 8)
		var lbl := _make_label("", 15, Color.WHITE)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_stat_labels[st] = lbl
		stat_row.add_child(lbl)

		var btn := _make_button("")
		btn.custom_minimum_size = Vector2(110, 30)
		btn.pressed.connect(_buy_upgrade.bind(st))
		_stat_buttons[st] = btn
		stat_row.add_child(btn)
		upg_col.add_child(stat_row)

	mid_row.add_child(upg_col)

	# Skins Column
	var skin_col := VBoxContainer.new()
	skin_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skin_col.add_theme_constant_override("separation", 8)
	var skin_header := _make_label("✨ HORN & COAT SKINS", 18, Color(1.0, 0.7, 0.9))
	skin_col.add_child(skin_header)

	var skin_ids := ["classic", "snow_phantom", "obsidian_ram", "golden_capra"]
	var skin_names := {
		"classic": "Alpine Classic",
		"snow_phantom": "Snow Phantom",
		"obsidian_ram": "Obsidian Ram",
		"golden_capra": "Golden Capra",
	}
	for s_id in skin_ids:
		var skin_row := HBoxContainer.new()
		skin_row.add_theme_constant_override("separation", 8)
		var s_lbl := _make_label(skin_names[s_id], 15, Color.WHITE)
		s_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		skin_row.add_child(s_lbl)

		var s_btn := _make_button("")
		s_btn.custom_minimum_size = Vector2(110, 30)
		s_btn.pressed.connect(_select_or_buy_skin.bind(s_id))
		_skin_buttons[s_id] = s_btn
		skin_row.add_child(s_btn)
		skin_col.add_child(skin_row)

	mid_row.add_child(skin_col)
	root_col.add_child(mid_row)

	var divider3 := HSeparator.new()
	root_col.add_child(divider3)

	# 4. Footer (Action Buttons)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	var hint := _make_label("Press G to toggle  |  ESC to close", 14, Color(0.6, 0.6, 0.6))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(hint)

	var race_btn := _make_button("  🏁 RACE MOUNTAIN  ", true)
	race_btn.custom_minimum_size = Vector2(180, 44)
	race_btn.pressed.connect(_on_race_pressed)
	footer.add_child(race_btn)
	root_col.add_child(footer)


func _make_button(text: String, hot := false) -> Button:
	return HudTheme.styled_button(text, hot)


func _make_label(text: String, size: int, color: Color) -> Label:
	return HudTheme.label(text, size, color)


# --- Refresh Logic -----------------------------------------------------------


func _refresh_all() -> void:
	var p := get_node_or_null("/root/Progression")
	if p == null:
		return

	# Header status.
	var cur_coins: int = int(p.get("coins"))
	var cur_xp: int = int(p.get("xp"))
	var cur_lvl: int = int(p.get("level"))
	_status_lbl.text = "%d 🪙  |  Level %d  (%d XP)" % [cur_coins, cur_lvl, cur_xp]

	# Mountain Carousel.
	var m_id := _mountain_ids[_mountain_idx]
	var m_data: Dictionary = MountainCatalog.get_mountain(m_id)
	var req_lvl: int = int(m_data.get("unlock_level", 1))
	var is_unlocked: bool = bool(p.call("is_mountain_unlocked", m_id))
	var is_current: bool = (String(p.get("current_mountain")) == m_id)

	_mountain_name_lbl.text = "%s  [%s]" % [m_data.get("name", ""), m_data.get("difficulty", "")]
	_mountain_desc_lbl.text = String(m_data.get("subtitle", ""))
	_mountain_stats_lbl.text = "Peak: %.0fm  |  Snowline: %.0fm  |  Warp: %.0fm" % [
		float(m_data.get("peak_height", 260.0)),
		float(m_data.get("snow_line", 170.0)),
		float(m_data.get("warp_strength", 60.0)),
	]

	if not is_unlocked:
		_mountain_select_btn.text = "LOCKED (Lvl %d)" % req_lvl
		_mountain_select_btn.disabled = true
	elif is_current:
		_mountain_select_btn.text = "SELECTED ✓"
		_mountain_select_btn.disabled = true
	else:
		_mountain_select_btn.text = "SELECT"
		_mountain_select_btn.disabled = false

	# Stat upgrades.
	var stat_names := {"speed": "Speed", "jump": "Jump", "grip": "Grip", "stamina": "Stamina"}
	var stat_percents := {"speed": "+4%/tier", "jump": "+4%/tier", "grip": "+5%/tier", "stamina": "+6%/tier"}
	for st in stat_names:
		var tier: int = int(p.call("get_upgrade_tier", st))
		var cost: int = int(p.call("get_upgrade_cost", st))
		_stat_labels[st].text = "%-7s  Tier %d/5  (%s)" % [stat_names[st], tier, stat_percents[st]]
		var btn: Button = _stat_buttons[st]
		if tier >= Config.UPGRADE_MAX_TIER:
			btn.text = "MAXED"
			btn.disabled = true
		else:
			btn.text = "%d 🪙" % cost
			btn.disabled = (cur_coins < cost)

	# Skins.
	var cur_skin: String = String(p.get("current_skin"))
	for s_id in _skin_buttons:
		var s_btn: Button = _skin_buttons[s_id]
		var unlocked: bool = bool(p.call("is_skin_unlocked", s_id))
		if s_id == cur_skin:
			s_btn.text = "EQUIPPED"
			s_btn.disabled = true
		elif unlocked:
			s_btn.text = "EQUIP"
			s_btn.disabled = false
		else:
			var coin_cost: int = int(Config.SKIN_COIN_COSTS.get(s_id, 0))
			var lvl_req: int = int(Config.SKIN_UNLOCK_LEVELS.get(s_id, 1))
			if coin_cost > 0:
				s_btn.text = "%d 🪙" % coin_cost
				s_btn.disabled = (cur_coins < coin_cost)
			else:
				s_btn.text = "Lvl %d" % lvl_req
				s_btn.disabled = true


# --- Button Actions ----------------------------------------------------------


func _prev_mountain() -> void:
	_mountain_idx = (_mountain_idx - 1 + _mountain_ids.size()) % _mountain_ids.size()
	_refresh_all()


func _next_mountain() -> void:
	_mountain_idx = (_mountain_idx + 1) % _mountain_ids.size()
	_refresh_all()


func _select_mountain() -> void:
	var m_id := _mountain_ids[_mountain_idx]
	var p := get_node_or_null("/root/Progression")
	if p != null and p.call("set_current_mountain", m_id):
		_refresh_all()


func _buy_upgrade(stat: String) -> void:
	var p := get_node_or_null("/root/Progression")
	if p != null:
		p.call("buy_upgrade", stat)
		_refresh_all()


func _select_or_buy_skin(skin_id: String) -> void:
	var p := get_node_or_null("/root/Progression")
	if p == null:
		return
	if p.call("is_skin_unlocked", skin_id):
		p.call("set_current_skin", skin_id)
		_refresh_all()
		# Live update player skin in world.
		var player := _find_player()
		if player != null and player.has_method("apply_skin"):
			player.call("apply_skin", skin_id)
	else:
		if p.call("buy_skin", skin_id):
			p.call("set_current_skin", skin_id)
			_refresh_all()
			var player := _find_player()
			if player != null and player.has_method("apply_skin"):
				player.call("apply_skin", skin_id)


func _on_race_pressed() -> void:
	close_garage()
	get_tree().paused = false  # Phase 11: paused-reload trap (plan risk table)
	# Reload current scene with selected mountain.
	get_tree().reload_current_scene()


func _find_player() -> Node:
	var level := get_tree().current_scene
	if level != null:
		for c in level.get_children():
			if c is CharacterBody3D and c.name == "Goat":
				return c
	return null
