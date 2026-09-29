extends Node
## Phase 10 — Progression Manager (Autoload "Progression").
## Manages persistent player progression: coins, XP, levels, stat upgrades,
## unlocked mountains, and equipped goat skins.
## Backed by ConfigFile at Config.SAVE_PATH (user://progression.cfg).

var coins: int = 0
var xp: int = 0
var level: int = 1

# Stat upgrade tiers: 0 to Config.UPGRADE_MAX_TIER (5).
var upgrades: Dictionary = {
	"speed": 0,
	"jump": 0,
	"grip": 0,
	"stamina": 0,
}

var unlocked_mountains: Array = ["alpine_valley"]
var current_mountain: String = "alpine_valley"

var unlocked_skins: Array = ["classic"]
var current_skin: String = "classic"


func _ready() -> void:
	load_from_disk()


func _bus() -> Node:
	return get_node_or_null("/root/EventBus")


# --- Currency (Coins) --------------------------------------------------------


func add_coins(amount: int) -> void:
	if amount <= 0:
		return
	coins += amount
	var b := _bus()
	if b != null and b.has_signal("coins_changed"):
		b.emit_signal("coins_changed", coins, amount)
	save_to_disk()


func spend_coins(amount: int) -> bool:
	if amount <= 0:
		return true
	if coins < amount:
		return false
	coins -= amount
	var b := _bus()
	if b != null and b.has_signal("coins_changed"):
		b.emit_signal("coins_changed", coins, -amount)
	save_to_disk()
	return true


# --- Experience & Levels -----------------------------------------------------


## Adds XP and updates level. Returns a result dict for UI celebratory displays.
func add_xp(amount: int) -> Dictionary:
	if amount <= 0:
		return {"leveled_up": false, "old_level": level, "new_level": level, "gained": 0}

	xp += amount
	var b := _bus()
	if b != null and b.has_signal("xp_gained"):
		b.emit_signal("xp_gained", xp, amount)

	var old_lvl := level
	var new_lvl := calculate_level(xp)
	var leveled_up := new_lvl > old_lvl

	if leveled_up:
		level = new_lvl
		_check_level_unlocks()
		if b != null and b.has_signal("level_up"):
			b.emit_signal("level_up", level)

	save_to_disk()
	return {
		"leveled_up": leveled_up,
		"old_level": old_lvl,
		"new_level": new_lvl,
		"gained": amount,
	}


static func calculate_level(xp_val: int) -> int:
	if xp_val <= 0:
		return 1
	return 1 + int(floor(sqrt(float(xp_val) / Config.XP_BASE_DIVISOR)))


static func xp_for_level(lvl: int) -> int:
	if lvl <= 1:
		return 0
	return int(ceil(pow(float(lvl - 1), 2) * Config.XP_BASE_DIVISOR))


## Returns 0.0..1.0 progress toward next level for HUD progress bars.
func xp_progress_ratio() -> float:
	var cur_base := xp_for_level(level)
	var next_base := xp_for_level(level + 1)
	if next_base <= cur_base:
		return 1.0
	return clampf(float(xp - cur_base) / float(next_base - cur_base), 0.0, 1.0)


# --- Stat Upgrades -----------------------------------------------------------


func get_upgrade_tier(stat: String) -> int:
	return int(upgrades.get(stat, 0))


func get_upgrade_cost(stat: String) -> int:
	var tier := get_upgrade_tier(stat)
	if tier >= Config.UPGRADE_MAX_TIER:
		return -1
	if tier < 0 or tier >= Config.UPGRADE_COSTS.size():
		return -1
	return Config.UPGRADE_COSTS[tier]


func can_upgrade(stat: String) -> bool:
	var cost := get_upgrade_cost(stat)
	return cost > 0 and coins >= cost


func buy_upgrade(stat: String) -> bool:
	if not can_upgrade(stat):
		return false
	var cost := get_upgrade_cost(stat)
	if spend_coins(cost):
		var next_tier := get_upgrade_tier(stat) + 1
		upgrades[stat] = next_tier
		var b := _bus()
		if b != null and b.has_signal("upgrade_purchased"):
			b.emit_signal("upgrade_purchased", stat, next_tier)
		save_to_disk()
		return true
	return false


## Physics multiplier applied to base constants.
func get_stat_multiplier(stat: String) -> float:
	var tier := get_upgrade_tier(stat)
	match stat:
		"speed":
			return 1.0 + float(tier) * Config.STAT_STEP_SPEED
		"jump":
			return 1.0 + float(tier) * Config.STAT_STEP_JUMP
		"grip":
			return 1.0 + float(tier) * Config.STAT_STEP_GRIP
		"stamina":
			return 1.0 + float(tier) * Config.STAT_STEP_STAMINA
		_:
			return 1.0


# --- Mountains ---------------------------------------------------------------


func unlock_mountain(mountain_id: String) -> void:
	if not (mountain_id in unlocked_mountains):
		unlocked_mountains.append(mountain_id)
		var b := _bus()
		if b != null and b.has_signal("mountain_unlocked"):
			b.emit_signal("mountain_unlocked", mountain_id)
		save_to_disk()


func is_mountain_unlocked(mountain_id: String) -> bool:
	return mountain_id in unlocked_mountains


func set_current_mountain(mountain_id: String) -> bool:
	if not is_mountain_unlocked(mountain_id):
		return false
	current_mountain = mountain_id
	save_to_disk()
	return true


# --- Skins -------------------------------------------------------------------


func unlock_skin(skin_id: String) -> void:
	if not (skin_id in unlocked_skins):
		unlocked_skins.append(skin_id)
		var b := _bus()
		if b != null and b.has_signal("skin_unlocked"):
			b.emit_signal("skin_unlocked", skin_id)
		save_to_disk()


func is_skin_unlocked(skin_id: String) -> bool:
	return skin_id in unlocked_skins


func buy_skin(skin_id: String) -> bool:
	if is_skin_unlocked(skin_id):
		return true
	var cost: int = int(Config.SKIN_COIN_COSTS.get(skin_id, -1))
	if cost <= 0:
		return false
	if spend_coins(cost):
		unlock_skin(skin_id)
		return true
	return false


func set_current_skin(skin_id: String) -> bool:
	if not is_skin_unlocked(skin_id):
		return false
	current_skin = skin_id
	save_to_disk()
	return true


# --- Automated Level Unlocks -------------------------------------------------


func _check_level_unlocks() -> void:
	for m_id in Config.MOUNTAIN_UNLOCK_LEVELS:
		var req: int = int(Config.MOUNTAIN_UNLOCK_LEVELS[m_id])
		if level >= req and not is_mountain_unlocked(m_id):
			unlock_mountain(m_id)

	for s_id in Config.SKIN_UNLOCK_LEVELS:
		var req: int = int(Config.SKIN_UNLOCK_LEVELS[s_id])
		if level >= req and not is_skin_unlocked(s_id):
			unlock_skin(s_id)


# --- Storage (ConfigFile) ----------------------------------------------------


func save_to_disk() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "coins", coins)
	cfg.set_value("profile", "xp", xp)
	cfg.set_value("profile", "level", level)

	cfg.set_value("upgrades", "speed", int(upgrades.get("speed", 0)))
	cfg.set_value("upgrades", "jump", int(upgrades.get("jump", 0)))
	cfg.set_value("upgrades", "grip", int(upgrades.get("grip", 0)))
	cfg.set_value("upgrades", "stamina", int(upgrades.get("stamina", 0)))

	cfg.set_value("mountains", "unlocked", unlocked_mountains)
	cfg.set_value("mountains", "current", current_mountain)

	cfg.set_value("skins", "unlocked", unlocked_skins)
	cfg.set_value("skins", "current", current_skin)

	var err := cfg.save(Config.SAVE_PATH)
	return err == OK


func load_from_disk() -> bool:
	var cfg := ConfigFile.new()
	var err := cfg.load(Config.SAVE_PATH)
	if err != OK:
		# Clean default profile on first launch or missing file.
		_check_level_unlocks()
		return false

	coins = int(cfg.get_value("profile", "coins", 0))
	xp = int(cfg.get_value("profile", "xp", 0))
	level = int(cfg.get_value("profile", "level", calculate_level(xp)))

	upgrades["speed"] = clampi(int(cfg.get_value("upgrades", "speed", 0)), 0, Config.UPGRADE_MAX_TIER)
	upgrades["jump"] = clampi(int(cfg.get_value("upgrades", "jump", 0)), 0, Config.UPGRADE_MAX_TIER)
	upgrades["grip"] = clampi(int(cfg.get_value("upgrades", "grip", 0)), 0, Config.UPGRADE_MAX_TIER)
	upgrades["stamina"] = clampi(int(cfg.get_value("upgrades", "stamina", 0)), 0, Config.UPGRADE_MAX_TIER)

	var saved_mountains: Variant = cfg.get_value("mountains", "unlocked", ["alpine_valley"])
	if saved_mountains is Array:
		unlocked_mountains = saved_mountains
	if not ("alpine_valley" in unlocked_mountains):
		unlocked_mountains.push_front("alpine_valley")
	current_mountain = String(cfg.get_value("mountains", "current", "alpine_valley"))

	var saved_skins: Variant = cfg.get_value("skins", "unlocked", ["classic"])
	if saved_skins is Array:
		unlocked_skins = saved_skins
	if not ("classic" in unlocked_skins):
		unlocked_skins.push_front("classic")
	current_skin = String(cfg.get_value("skins", "current", "classic"))

	_check_level_unlocks()
	return true


func reset_progression() -> void:
	coins = 0
	xp = 0
	level = 1
	upgrades = {"speed": 0, "jump": 0, "grip": 0, "stamina": 0}
	unlocked_mountains = ["alpine_valley"]
	current_mountain = "alpine_valley"
	unlocked_skins = ["classic"]
	current_skin = "classic"
	_check_level_unlocks()
	save_to_disk()
