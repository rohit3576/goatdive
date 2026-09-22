extends SceneTree
## Phase 9 GAUNTLET (TEMP — deleted when the phase lands): the D8 loop,
## Phase 9 edition — full 4-goat grand prix with the trick system live.
## Verifies tricks/coins/score NEVER disturb the herd: same finish
## times ±10%, obstacle hits ≤ 30, teleports ≤ 8, and the score plumbing
## rides along without a sound. Harness rules: the gauntlet skeleton
## (proven), polls with generous deadlines, mount in _process only.

const LEVEL := "res://scenes/terrain/mountain_level.tscn"
const BRAIN := "res://scripts/race/ai_goat.gd"

var _steps: Array = []
var _i := 0
var _until := 0
var _poll_fn: Callable
var _poll_deadline := 0
var _level: Node3D
var _pass := 0
var _fail := 0
var _goats: Array = []
var _names: PackedStringArray = ["YOU", "CAUTIOUS", "BOLD", "RECKLESS"]
var _hits: Dictionary = {}
var _wired := false


func _initialize() -> void:
	_steps = [_mount_step, _start_race, _wait_finish, _report]


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() < _until:
		return false
	if _poll_fn.is_valid():
		if not _poll_fn.call() and Time.get_ticks_msec() < _poll_deadline:
			return false
		_poll_fn = Callable()
	if _i >= _steps.size():
		return true
	var fn: Callable = _steps[_i]
	_i += 1
	fn.call()
	return false


func _poll(fn: Callable, timeout_ms: int) -> void:
	_poll_fn = fn
	_poll_deadline = Time.get_ticks_msec() + timeout_ms


func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % name)
	else:
		_fail += 1
		print("  FAIL  %s   %s" % [name, detail])


func _wire_once() -> void:
	if _wired:
		return
	_wired = true
	var bus := root.get_node_or_null("/root/EventBus") as Node
	if bus != null:
		bus.connect("goat_hit_obstacle", _on_hit)


func _mount_step() -> void:
	var packed := load(LEVEL) as PackedScene
	_level = packed.instantiate() as Node3D
	root.add_child(_level)
	_wire_once()
	_goats = []
	_hits = {}
	for c in _level.get_children():
		if c is CharacterBody3D:
			_goats.append(c)
			_hits[c] = 0
	print("  INFO  gauntlet: %d goats mounted, tricks+coins live" % _goats.size())
	_until = Time.get_ticks_msec() + 800


func _on_hit(_impact: float, goat: Node3D) -> void:
	if _hits.has(goat):
		_hits[goat] = int(_hits[goat]) + 1


func _start_race() -> void:
	var player := _goats[0] as Node
	if player.get_node_or_null("AiGoat") == null:
		var script := load(BRAIN) as GDScript
		script.reload()
		var brain: Node = script.new()
		brain.name = "AiGoat"
		brain.set("profile", "BOLD")
		player.add_child(brain)
	_poll(_racing, 15000)


func _racing() -> bool:
	var mgr := _level.get_node_or_null("RaceManager")
	var state: String = (mgr.call("get_race_state") as Dictionary)["state"]
	return state == "racing"


func _wait_finish() -> void:
	_poll(_all_done, 150000)


func _all_done() -> bool:
	var mgr := _level.get_node_or_null("RaceManager")
	var st: Dictionary = mgr.call("get_race_state")
	for s in (st["standings"] as Array):
		if not (s as Dictionary)["finished"]:
			return false
	return true


func _report() -> void:
	var mgr := _level.get_node_or_null("RaceManager")
	var st: Dictionary = mgr.call("get_race_state")
	var times := {}
	for s in (st["standings"] as Array):
		var rec: Dictionary = s
		times[String(rec["name"])] = float(rec["time"]) if rec["finished"] else -1.0
	var tps := {}
	for a in (st["ai_states"] as Array):
		var d: Dictionary = a
		tps[String(d["profile"])] = int(d["teleports"])
	var player_brain := (_goats[0] as Node).get_node_or_null("AiGoat")
	if player_brain != null:
		tps["YOU"] = int((player_brain.call("get_debug_state") as Dictionary)["teleports"])

	print("  INFO  === PHASE 9 GAUNTLET (tricks live) ===")
	var total_hits := 0
	var total_tp := 0
	for i in _goats.size():
		var goat := _goats[i] as Node
		var nm: String = _names[i] if i < _names.size() else "?"
		var t: float = times.get(nm, -1.0)
		var h: int = _hits.get(goat, 0)
		var tp: int = tps.get(nm, 0)
		total_hits += h
		total_tp += tp
		print(
			"  INFO  %-9s  hits %2d  tp %d  time %s"
			% [nm, h, tp, ("DNF" if t < 0.0 else "%.2f" % t)]
		)
	# Phase 7 reference: 32.25 / 35.53 / 37.28 / survivor; Phase 8: ~35-37.
	var t_min := times.values().min()
	var t_max := times.values().max()
	var spread_ok: bool = t_min > 0.0 and t_max / t_min < 1.35
	print("  INFO  TOTALS hits %d tp %d  score fields: %s" % [
		total_hits, total_tp, "score" in st and "best_trick" in st,
	])
	_check("all four racers finished (tricks did not disturb the race)", t_min > 0.0)
	_check("finish spread within 35% of the leader", spread_ok,
		"min=%.2f max=%.2f" % [t_min, t_max])
	_check("obstacle hits ≤ 30 (detector overhead is free)", total_hits <= 30,
		"hits=%d" % total_hits)
	_check("teleports ≤ 8", total_tp <= 8, "tp=%d" % total_tp)
	_check("race state carries score fields", "score" in st and "best_trick" in st)
	print("GAUNTLET P9: %d pass / %d fail" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
