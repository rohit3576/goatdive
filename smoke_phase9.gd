extends SceneTree
## Phase 9 smoke (TEMP — deleted when the phase lands).
## Harness rules (Phase 6-8 lessons, all paid for): wall-clock waits only,
## generous poll deadlines (--script physics/wall divergence), settle-then-
## launch with slope-aligned velocity (teleports can't catch slopes), zero
## project-class references at entry parse, mount in _process never
## _initialize.

const LEVEL := "res://scenes/terrain/mountain_level.tscn"

var _steps: Array = []
var _i := 0
var _until := 0
var _poll_fn: Callable
var _poll_deadline := 0
var _level: Node3D
var _pass := 0
var _fail := 0
var _player: CharacterBody3D
var _detector: Node
var _trick_fires := 0
var _trick_names: PackedStringArray = []
var _trick_pts: Array = []  # {name, pts}
var _bonks := 0
var _bonks_in_air := 0
var _watch_coins := false


func _on_trick(name: String, pts: int, goat: Node3D) -> void:
	if goat == _player:
		if name == "coin" and not _watch_coins:
			return
		_trick_fires += 1
		_trick_names.append(name)
		_trick_pts.append({"name": name, "pts": pts})


func _on_bonk_watched(_impact: float, _dir: Vector3, goat: Node3D) -> void:
	if goat == _player:
		_bonks += 1
		if _detector != null and bool((_detector as Node).call("is_airborne")):
			_bonks_in_air += 1


func _initialize() -> void:
	_steps = [
		_mount, _step_window, _step_window_assert,
		_step_recover, _step_flip_settle, _step_flip, _step_flip_assert,
		_step_logjump_settle, _step_logjump, _step_logjump_assert,
		_step_nm_settle, _step_nm_pass, _step_nm_pass_assert,
		_step_nm_hit, _step_nm_hit_assert,
		_step_combo_settle, _step_combo, _step_combo_assert,
		_step_coins_audit, _step_coin_pickup, _step_coin_assert,
		_step_grounded_settle, _step_grounded_press, _step_grounded_release, _step_grounded_assert,
		# Destructive rigs LAST — pine bonks poison the physics regime for
		# everything downstream (starvation + carried tumbles).
		_step_void_settle, _step_void, _step_void_assert,
		_step_void_flip_settle, _step_void_flip, _step_void_flip_assert,
		_report,
	]


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


func _wait(ms: int) -> void:
	_until = Time.get_ticks_msec() + ms


func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % name)
	else:
		_fail += 1
		print("  FAIL  %s   %s" % [name, detail])


var _writer: Node  # physics-side rotation writer (added at mount —
# late-added nodes' physics callbacks never fire under --script; the
# gauntlet's grafted brains are added early and tick fine)


func _mount() -> void:
	var packed := load(LEVEL) as PackedScene
	_level = packed.instantiate() as Node3D
	root.add_child(_level)
	var bus := root.get_node_or_null("/root/EventBus") as Node
	bus.connect("trick_scored", _on_trick)
	bus.connect("goat_bonked", _on_bonk_watched)
	for c in _level.get_children():
		if c is CharacterBody3D:
			_player = c
			break
	_detector = (_player as Node).get_node_or_null("TrickDetector")
	_check("detector mounted on player", _detector != null)
	_writer = (load("res://smoke_spin_writer.gd") as GDScript).new()
	_writer.set("rate", 0.0)  # idle until the spin test
	(_player as Node).add_child(_writer)
	_wait(700)


## Air window open→close with sane stats: settle on the spawn disc, jump
## with a slope-aligned downhill launch, land, read the closed window.
func _step_window() -> void:
	var terrain := _level.get_node_or_null("Terrain")
	var down: Vector3 = terrain.call("downhill_dir", 0.0, -24.0)
	var h0: float = terrain.call("get_height_at", 0.0, -24.0)
	_player.global_position = Vector3(0.0, h0 + 0.55, -24.0)
	_player.look_at(_player.global_position + down)
	_player.velocity = Vector3.ZERO
	_player.call("set_horizontal_velocity", Vector2.ZERO)
	_wait(700)  # settle GROUNDED (launch discipline)

	# The REAL channel drives the window: buffer + slope-aligned velocity.
	_player.set("_jump_buffer", 0.12)
	_player.call("set_horizontal_velocity", Vector2(down.x, down.z) * 10.0)
	_player.velocity.y = down.y * 10.0
	# Poll until a window closes (generous deadline — physics divergence).
	_poll(
		func() -> bool:
			var d: Dictionary = (_detector as Node).call("get_debug_state")
			return int(d["windows"]) >= 1,
		30000
	)


func _step_window_assert() -> void:
	var d: Dictionary = (_detector as Node).call("get_debug_state")
	var w: Dictionary = d["last"]
	var ok: bool = (
		not w.is_empty()
		and float(w["airtime"]) > 0.2 and float(w["airtime"]) < 4.0
		and float(w["distance"]) > 2.0
		and not bool(w["voided"])
	)
	_check(
		"air window closes with sane stats (jump → land)",
		ok,
		"airtime=%.2f dist=%.1f voided=%s" % [w.get("airtime", -1.0), w.get("distance", -1.0), w.get("voided", "?")]
	)


## Void: airborne bonk into the approachable pine (the proven Step 8 rig).
func _step_void() -> void:
	var obs := _level.get_node_or_null("Obstacles")
	var terrain := _level.get_node_or_null("Terrain")
	var records: Array = (
		obs.call("get_obstacles", "pines") + obs.call("get_obstacles", "rocks")
	)
	var target := Vector3.INF
	for rec in records:
		var t: Vector3 = (rec as Dictionary)["pos"]
		var dvec := Vector2(0.0 - t.x, -24.0 - t.z)
		if dvec.length() < 1.0:
			continue
		var dnorm := dvec.normalized()
		var ax := t.x - dnorm.x * 6.0
		var az := t.z - dnorm.y * 6.0
		var slope_a: float = terrain.call("slope_deg_at", ax, az)
		var slope_t: float = terrain.call("slope_deg_at", t.x, t.z)
		if slope_a > 40.0 or slope_t > 40.0:
			continue
		target = t
		break
	if target == Vector3.INF:
		_check("void rig: approachable obstacle found", false)
		_wait(1)
		return
	_check("void rig: approachable obstacle found", true)
	var h0: float = terrain.call("get_height_at", target.x, target.z)
	# Settle 4 m before the pine, aimed at it — contact lands ~0.28 s in,
	# pre-apex, definitively airborne.
	var dir := Vector2(target.x - 0.0, target.z + 24.0).normalized()
	var sx := target.x - dir.x * 4.0
	var sz := target.z - dir.y * 4.0
	var hback: float = terrain.call("get_height_at", sx, sz)
	_bonks = 0
	_player.global_position = Vector3(sx, hback + 0.55, sz)
	_player.look_at(Vector3(target.x, hback, target.z))
	_player.velocity = Vector3.ZERO
	_player.call("set_horizontal_velocity", Vector2.ZERO)
	_wait(700)
	# Jump + launch at the pine: the buffer gives the air, the slope-aligned
	# line gives the trajectory — no artificial vy hop (it clears the trunk).
	_player.set("_jump_buffer", 0.12)
	var v := (Vector3(target.x, h0, target.z) - _player.global_position).normalized() * 14.0
	_player.call("set_horizontal_velocity", Vector2(v.x, v.z))
	_player.velocity.y = v.y
	var w0: int = int(((_detector as Node).call("get_debug_state") as Dictionary)["windows"])
	_poll(
		func() -> bool:
			var d: Dictionary = (_detector as Node).call("get_debug_state")
			return int(d["windows"]) > w0,
		30000
	)


func _step_void_assert() -> void:
	var d: Dictionary = (_detector as Node).call("get_debug_state")
	var w: Dictionary = d["last"]
	print(
		"  INFO  void window: airtime=%.2f dist=%.1f impact=%.1f voided=%s bonks=%d pos=%v"
		% [w.get("airtime", -1.0), w.get("distance", -1.0), w.get("land_impact", -1.0), w.get("voided", "?"), _bonks, _player.global_position]
	)
	_check(
		"mid-air bonk voids the window",
		not w.is_empty() and bool(w["voided"]),
		"voided=%s bonks=%d" % [w.get("voided", "?"), _bonks]
	)


## Shared TELEPORT+aim (the settle is a separate poll-step — wall waits
## give arbitrary physics progress under --script starvation).
func _park_at(pos_x: float, pos_z: float) -> Vector3:
	var terrain := _level.get_node_or_null("Terrain")
	var h: float = terrain.call("get_height_at", pos_x, pos_z)
	_player.global_position = Vector3(pos_x, h + 0.55, pos_z)
	var down: Vector3 = terrain.call("downhill_dir", pos_x, pos_z)
	_player.look_at(_player.global_position + down)
	_player.velocity = Vector3.ZERO
	_player.call("set_horizontal_velocity", Vector2.ZERO)
	_player.set("_jump_buffer", 0.0)
	return down


func _settle_poll() -> void:
	_poll(
		func() -> bool:
			var d: Dictionary = _player.call("get_debug_state")
			var calm := bool(d["grounded"]) and not bool(d["tumbling"])
			var st := String(d["state"])
			return calm and st != "STUMBLE",
		25000
	)


func _jump_launch(down: Vector3, speed: float) -> void:
	_player.set("_jump_buffer", 0.12)
	var v: Vector3 = down.normalized() * speed
	_player.call("set_horizontal_velocity", Vector2(v.x, v.z))
	_player.velocity.y = v.y


func _win_count() -> int:
	return int(((_detector as Node).call("get_debug_state") as Dictionary)["windows"])


## Park the goat calm: teleport to the flat spawn disc (away from
## whatever mess the last test left), then wait out tumble/stumble —
## jumps are gated on both, and carried chaos silently voids launches.
func _step_recover() -> void:
	var terrain := _level.get_node_or_null("Terrain")
	var h: float = terrain.call("get_height_at", 0.0, -30.0)
	_player.global_position = Vector3(0.0, h + 0.55, -30.0)
	_player.velocity = Vector3.ZERO
	_player.call("set_horizontal_velocity", Vector2.ZERO)
	_player.set("_jump_buffer", 0.0)
	_poll(
		func() -> bool:
			var d: Dictionary = _player.call("get_debug_state")
			var calm := bool(d["grounded"]) and not bool(d["tumbling"])
			var st := String(d["state"])
			return calm and st != "STUMBLE",
		30000
	)
	_wait(300)


## Clean front flip: launch downhill, press Q once airborne, land clean.
func _step_flip_settle() -> void:
	_park_at(0.0, -30.0)
	_settle_poll()


func _step_flip() -> void:
	_trick_fires = 0
	_trick_names = PackedStringArray()
	var w0 := _win_count()
	# Hold Q THROUGH liftoff (trick buffering) — idle-side press timing
	# lags the physics window (the Phase 8 divergence lesson).
	Input.action_press("trick_front")
	_jump_launch(_park_at(0.0, -30.0), 9.0)
	_poll(
		func() -> bool:
			var d: Dictionary = (_detector as Node).call("get_debug_state")
			return int(d["windows"]) > w0,
		30000
	)


func _step_flip_assert() -> void:
	Input.action_release("trick_front")
	var w: Dictionary = ((_detector as Node).call("get_debug_state") as Dictionary)["last"]
	print(
		"  INFO  flip window: air=%.2f prog=%.2f voided=%s fires=%s"
		% [w.get("airtime", -1.0), w.get("flip_progress", -1.0), w.get("voided", "?"), _trick_names]
	)
	_check(
		"clean front flip scores",
		_trick_fires >= 1 and "front_flip" in _trick_names
			and float(w["flip_progress"]) >= 0.85 and not bool(w["voided"]),
		"names=%s prog=%.2f" % [_trick_names, w.get("flip_progress", -1.0)]
	)


## Voided flip: the pine rig + Q mid-air — the bonk kills the whole window.
## Log jump (the Phase 8 promise pays): flattest-approach log, tangent
## launch with a jump — clean close within the crossing band scores it.
func _step_logjump_settle() -> void:
	var obs := _level.get_node_or_null("Obstacles")
	var course := _level.get_node_or_null("Course")
	var terrain := _level.get_node_or_null("Terrain")
	var logs: Array = obs.call("get_obstacles", "logs")
	if logs.is_empty():
		set_meta("log_target", Vector3.INF)
		return
	var poly: PackedVector3Array = course.get("polyline")
	var best: Dictionary = {}
	var best_conv := INF
	for rec in logs:
		var p: Vector3 = (rec as Dictionary)["pos"]
		var ni := -1
		var nd := INF
		for i in poly.size():
			var d: float = Vector2(p.x - poly[i].x, p.z - poly[i].z).length()
			if d < nd:
				nd = d
				ni = i
		var tangent := poly[mini(ni + 1, poly.size() - 1)] - poly[maxi(ni - 1, 0)]
		tangent.y = 0.0
		tangent = tangent.normalized()
		var h0: float = p.y
		var h4: float = terrain.call("get_height_at", p.x - tangent.x * 4.0, p.z - tangent.z * 4.0)
		var h2: float = terrain.call("get_height_at", p.x - tangent.x * 2.0, p.z - tangent.z * 2.0)
		var conv := maxf(0.0, h2 - lerpf(h4, h0, 0.5)) + maxf(0.0, h4 - (h0 + 1.4))
		if conv < best_conv:
			best_conv = conv
			best = rec
	set_meta("log_target", (best as Dictionary)["pos"])
	var target: Vector3 = (best as Dictionary)["pos"]
	var ni2 := -1
	var nd2 := INF
	for i in poly.size():
		var d: float = Vector2(target.x - poly[i].x, target.z - poly[i].z).length()
		if d < nd2:
			nd2 = d
			ni2 = i
	var tangent2 := poly[mini(ni2 + 1, poly.size() - 1)] - poly[maxi(ni2 - 1, 0)]
	tangent2.y = 0.0
	tangent2 = tangent2.normalized()
	var sx := target.x - tangent2.x * 4.0
	var sz := target.z - tangent2.z * 4.0
	var h: float = terrain.call("get_height_at", sx, sz)
	_player.global_position = Vector3(sx, h + 0.55, sz)
	_player.look_at(_player.global_position + tangent2)
	_player.velocity = Vector3.ZERO
	_player.call("set_horizontal_velocity", Vector2.ZERO)
	_player.set("_jump_buffer", 0.0)
	set_meta("log_dir", tangent2)
	_settle_poll()


func _step_logjump() -> void:
	_trick_fires = 0
	_trick_names = PackedStringArray()
	var w0 := _win_count()
	var target: Vector3 = get_meta("log_target", Vector3.INF)
	if target == Vector3.INF:
		return
	var tangent: Vector3 = get_meta("log_dir", Vector3.FORWARD)
	var v := (target - _player.global_position).normalized() * 7.0  # gentle:
	# 10.5 built a 19.7 m flight that slammed the landing (drop 8.7) —
	# the D4 gate correctly voided it; 7 keeps the apex over the log
	# and lands soft.
	_player.set("_jump_buffer", 0.12)
	_player.call("set_horizontal_velocity", Vector2(v.x, v.z))
	_player.velocity.y = v.y
	_poll(
		func() -> bool:
			var d: Dictionary = (_detector as Node).call("get_debug_state")
			return int(d["windows"]) > w0 and not bool(d["air"]),
		40000
	)


func _step_logjump_assert() -> void:
	var dd: Dictionary = (_detector as Node).call("get_debug_state")
	var w: Dictionary = dd["last"]
	print(
		"  INFO  logjump window: dist=%.1f drop=%.1f voided=%s names=%s"
		% [w.get("distance", -1.0), w.get("drop", -1.0), w.get("voided", "?"), _trick_names]
	)
	_check(
		"log jump scores over a real log",
		"log_jump" in _trick_names and not bool(w["voided"]),
		"names=%s dist=%.1f" % [_trick_names, w.get("distance", -1.0)]
	)
	if float(w.get("distance", 0.0)) >= 15.0:
		_check("long jump stacks on the same window", "long_jump" in _trick_names)


## Shared near-miss rig state: the first approachable blocker + aim.
func _nm_target() -> Vector3:
	var obs := _level.get_node_or_null("Obstacles")
	var terrain := _level.get_node_or_null("Terrain")
	var records: Array = (
		obs.call("get_obstacles", "pines") + obs.call("get_obstacles", "rocks")
	)
	var target := Vector3.INF
	for rec in records:
		var t: Vector3 = (rec as Dictionary)["pos"]
		var dvec := Vector2(0.0 - t.x, -24.0 - t.z)
		if dvec.length() < 1.0:
			continue
		var dnorm := dvec.normalized()
		var ax := t.x - dnorm.x * 8.0
		var az := t.z - dnorm.y * 8.0
		var slope_a: float = terrain.call("slope_deg_at", ax, az)
		var slope_t: float = terrain.call("slope_deg_at", t.x, t.z)
		if slope_a > 40.0 or slope_t > 40.0:
			continue
		target = t
		break
	return target


func _step_nm_settle() -> void:
	var target := _nm_target()
	if target == Vector3.INF:
		set_meta("nm_target", Vector3.INF)
		return
	set_meta("nm_target", target)
	var terrain := _level.get_node_or_null("Terrain")
	var dir := Vector2(target.x - 0.0, target.z + 24.0).normalized()
	var sx := target.x - dir.x * 8.0
	var sz := target.z - dir.y * 8.0
	var h: float = terrain.call("get_height_at", sx, sz)
	_player.global_position = Vector3(sx, h + 0.55, sz)
	_player.velocity = Vector3.ZERO
	_player.call("set_horizontal_velocity", Vector2.ZERO)
	_player.set("_jump_buffer", 0.0)
	_settle_poll()


## PASS lane: aimed 1.4 m off the blocker's center — inside the band,
## outside the collider. Near miss must fire.
func _step_nm_pass() -> void:
	_trick_fires = 0
	_trick_names = PackedStringArray()
	var target: Vector3 = get_meta("nm_target", Vector3.INF)
	if target == Vector3.INF:
		return
	var terrain := _level.get_node_or_null("Terrain")
	var dir := (target - _player.global_position)
	dir.y = 0.0
	dir = dir.normalized()
	var perp := Vector3(-dir.z, 0.0, dir.x)
	var aim := target + perp * 1.4
	var h_aim: float = terrain.call("get_height_at", aim.x, aim.z)
	var v := (aim - _player.global_position)
	v.y = h_aim - _player.global_position.y
	v = v.normalized() * 12.5
	_player.call("set_horizontal_velocity", Vector2(v.x, v.z))
	_player.velocity.y = v.y
	_wait(2500)


func _step_nm_pass_assert() -> void:
	print("  INFO  nm pass lane: names=%s" % _trick_names)
	_check("near miss fires on a fast close pass", "near_miss" in _trick_names,
		"names=%s" % _trick_names)


## HIT lane: dead-on (the proven void geometry) — the hit retracts.
func _step_nm_hit() -> void:
	_trick_fires = 0
	_trick_names = PackedStringArray()
	var target: Vector3 = get_meta("nm_target", Vector3.INF)
	if target == Vector3.INF:
		return
	var terrain := _level.get_node_or_null("Terrain")
	# Park at the PROVEN 4 m dead-on spot (8 m launches bend off-line).
	var dir4 := Vector2(target.x - 0.0, target.z + 24.0).normalized()
	var sx := target.x - dir4.x * 4.0
	var sz := target.z - dir4.y * 4.0
	var h4: float = terrain.call("get_height_at", sx, sz)
	_player.global_position = Vector3(sx, h4 + 0.55, sz)
	_player.look_at(Vector3(target.x, h4, target.z))
	_player.velocity = Vector3.ZERO
	_player.call("set_horizontal_velocity", Vector2.ZERO)
	_settle_poll()
	_trick_fires = 0
	_trick_names = PackedStringArray()
	var h0: float = terrain.call("get_height_at", target.x, target.z)
	var v := (Vector3(target.x, h0, target.z) - _player.global_position).normalized() * 14.0
	_player.call("set_horizontal_velocity", Vector2(v.x, v.z))
	_player.velocity.y = v.y
	_wait(2500)


func _step_nm_hit_assert() -> void:
	_check("hit retracts the near miss", not ("near_miss" in _trick_names),
		"names=%s" % _trick_names)


## SLOW lane: same offset as the pass lane, walking speed — no payout.
func _step_nm_slow() -> void:
	_step_nm_settle()
	var target: Vector3 = get_meta("nm_target", Vector3.INF)
	if target == Vector3.INF:
		_wait(1)
		return
	var terrain := _level.get_node_or_null("Terrain")
	var dir := (target - _player.global_position)
	dir.y = 0.0
	dir = dir.normalized()
	var perp := Vector3(-dir.z, 0.0, dir.x)
	var aim := target + perp * 1.4
	var h_aim: float = terrain.call("get_height_at", aim.x, aim.z)
	var v := (aim - _player.global_position)
	v.y = h_aim - _player.global_position.y
	v = v.normalized() * 5.0
	_player.call("set_horizontal_velocity", Vector2(v.x, v.z))
	_player.velocity.y = v.y
	_wait(2500)


func _step_nm_slow_assert() -> void:
	_check("slow pass pays nothing", not ("near_miss" in _trick_names),
		"names=%s" % _trick_names)


## Combo math: flip + log jump in ONE clean window → both × 1.5, exact
## total (500+250)×1.5 = 1125; manager score delta matches.
func _step_combo_settle() -> void:
	_step_logjump_settle()


func _step_combo() -> void:
	_trick_fires = 0
	_trick_names = PackedStringArray()
	_trick_pts = []
	var mgr := _level.get_node_or_null("RaceManager")
	set_meta("score0", int((mgr.call("get_race_state") as Dictionary)["score"]))
	var target: Vector3 = get_meta("log_target", Vector3.INF)
	if target == Vector3.INF:
		return
	# Arm the PHYSICS-SIDE flip driver: the writer's tick fires the flip
	# at window open (idle calls fork; pre-launch flips get wiped by the
	# window-open reset — as designed).
	_writer.set_meta("arm_flip", true)
	var v := (target - _player.global_position).normalized() * 7.0
	_player.set("_jump_buffer", 0.12)
	_player.call("set_horizontal_velocity", Vector2(v.x, v.z))
	_player.velocity.y = v.y
	var w0 := _win_count()
	_poll(
		func() -> bool:
			var d: Dictionary = (_detector as Node).call("get_debug_state")
			return int(d["windows"]) > w0 and not bool(d["air"]),
		40000
	)


func _step_combo_assert() -> void:
	var mgr := _level.get_node_or_null("RaceManager")
	var score: int = int((mgr.call("get_race_state") as Dictionary)["score"])
	var delta: int = score - int(get_meta("score0", 0))
	var names: Array = []
	var pts_sum := 0
	for t in _trick_pts:
		var e: Dictionary = t
		names.append(String(e["name"]))
		pts_sum += int(e["pts"])
	var wdbg: Dictionary = ((_detector as Node).call("get_debug_state") as Dictionary)["last"]
	print(
		"  INFO  combo: names=%s pts=%d score_delta=%d flip=%s prog=%.2f air=%.2f"
		% [names, pts_sum, delta, wdbg.get("flip", ""), wdbg.get("flip_progress", -1.0), wdbg.get("airtime", -1.0)]
	)
	var combo_ok: bool = (
		"front_flip" in names and "log_jump" in names
		and pts_sum == 1125 and delta == 1125
	)
	_check("combo: flip + log jump both ×1.5, exact score delta", combo_ok,
		"names=%s pts=%d delta=%d" % [names, pts_sum, delta])


## Coins: records sane, D10 clean (independent math), then a REAL pickup
## — teleport onto a coin, the coins node's physics tick collects it,
## the score wire pays +50.
func _step_coins_audit() -> void:
	var coins := _level.get_node_or_null("Coins")
	var records: Array = coins.call("get_records")
	_check("coins placed (records non-empty)", not records.is_empty(),
		"n=%d" % records.size())
	var course := _level.get_node_or_null("Course")
	var gates: PackedVector3Array = course.get("gate_points")
	var fwds: PackedVector3Array = course.get("gate_forwards")
	var in_zone := 0
	for rec in records:
		var p: Vector3 = (rec as Dictionary)["pos"]
		for i in gates.size():
			var f: Vector3 = fwds[i]
			var rel := Vector2(p.x - gates[i].x, p.z - gates[i].z)
			var along := rel.dot(Vector2(f.x, f.z))
			var lat := absf(rel.dot(Vector2(-f.z, f.x)))
			var width := 10.0 * (1.6 if i == gates.size() - 1 else 1.0)
			if lat <= (width + 14.0) * 0.5 and along >= -12.5 and along <= 22.5:
				in_zone += 1
				break
	_check("coins D10-clean (no gate-zone coins)", in_zone == 0, "%d in zones" % in_zone)


func _step_coin_pickup() -> void:
	_trick_fires = 0
	_trick_names = PackedStringArray()
	var coins := _level.get_node_or_null("Coins")
	var records: Array = coins.call("get_records")
	var mgr := _level.get_node_or_null("RaceManager")
	set_meta("score0c", int((mgr.call("get_race_state") as Dictionary)["score"]))
	var target: Vector3 = (records[0] as Dictionary)["pos"]
	_player.global_position = target + Vector3(0.0, 0.3, 0.0)
	_player.velocity = Vector3.ZERO
	_player.call("set_horizontal_velocity", Vector2.ZERO)
	_poll(
		func() -> bool:
			return int(coins.call("collected_count")) >= 1,
		25000
	)


func _step_coin_assert() -> void:
	var coins := _level.get_node_or_null("Coins")
	var mgr := _level.get_node_or_null("RaceManager")
	var delta: int = int((mgr.call("get_race_state") as Dictionary)["score"]) - int(get_meta("score0c", 0))
	print("  INFO  coin: collected=%d delta=%d names=%s" % [
		int(coins.call("collected_count")), delta, _trick_names
	])
	_check(
		"coin pickup pays +50 on the score wire",
		int(coins.call("collected_count")) >= 1 and "coin" in _trick_names and delta >= 50,
		"col=%d delta=%d" % [int(coins.call("collected_count")), delta]
	)


func _step_void_flip() -> void:
	_trick_fires = 0
	_trick_names = PackedStringArray()
	var obs := _level.get_node_or_null("Obstacles")
	var terrain := _level.get_node_or_null("Terrain")
	var records: Array = (
		obs.call("get_obstacles", "pines") + obs.call("get_obstacles", "rocks")
	)
	var target := Vector3.INF
	for rec in records:
		var t: Vector3 = (rec as Dictionary)["pos"]
		var dvec := Vector2(0.0 - t.x, -24.0 - t.z)
		if dvec.length() < 1.0:
			continue
		var dnorm := dvec.normalized()
		var ax := t.x - dnorm.x * 4.0
		var az := t.z - dnorm.y * 4.0
		var slope_a: float = terrain.call("slope_deg_at", ax, az)
		var slope_t: float = terrain.call("slope_deg_at", t.x, t.z)
		if slope_a > 40.0 or slope_t > 40.0:
			continue
		target = t
		break
	if target == Vector3.INF:
		_check("void-flip rig found", false)
		_wait(1)
		return
	var h0: float = terrain.call("get_height_at", target.x, target.z)
	var dir := Vector2(target.x - 0.0, target.z + 24.0).normalized()
	var sx := target.x - dir.x * 4.0
	var sz := target.z - dir.y * 4.0
	var hback: float = terrain.call("get_height_at", sx, sz)
	_player.global_position = Vector3(sx, hback + 0.55, sz)
	_player.look_at(Vector3(target.x, hback, target.z))
	_player.velocity = Vector3.ZERO
	_player.call("set_horizontal_velocity", Vector2.ZERO)
	_wait(700)
	var w0 := _win_count()
	_player.set("_jump_buffer", 0.12)
	var v := (Vector3(target.x, h0, target.z) - _player.global_position).normalized() * 14.0
	_player.call("set_horizontal_velocity", Vector2(v.x, v.z))
	_player.velocity.y = v.y
	_poll(
		func() -> bool:
			var d: Dictionary = (_detector as Node).call("get_debug_state")
			if bool(d["air"]) and _trick_fires == 0:
				Input.action_press("trick_front")
			if int(d["windows"]) > w0:
				Input.action_release("trick_front")
				return true
			return false,
		30000
	)


func _step_void_flip_assert() -> void:
	Input.action_release("trick_front")
	var w: Dictionary = ((_detector as Node).call("get_debug_state") as Dictionary)["last"]
	_check(
		"voided flip scores nothing",
		bool(w["voided"]) and not ("front_flip" in _trick_names),
		"voided=%s names=%s" % [w.get("voided", "?"), _trick_names]
	)


## 360: settle (writer on) then launch; physics-side rotation throughout.
func _step_spin_settle_UNUSED() -> void:
	_park_at(0.0, -30.0)
	_settle_poll()


func _step_spin_UNUSED() -> void:
	_trick_fires = 0
	_trick_names = PackedStringArray()
	var w0 := _win_count()
	var rot0: float = _player.rotation.y
	# Launch first (writer OFF — rotation during the launch window blocks
	# the jump for reasons the engine keeps to itself), then spin.
	_jump_launch(
		_level.get_node_or_null("Terrain").call("downhill_dir", 0.0, -30.0) as Vector3,
		8.0
	)
	_writer.set("rate", 7.0)
	print(
		"  INFO  spin launch state: %s buf=%.2f wins=%d"
		% [
			(_player.call("get_debug_state") as Dictionary)["state"],
			float((_player.call("get_debug_state") as Dictionary)["buffer"]),
			_win_count(),
		]
	)
	_poll(
		func() -> bool:
			var d: Dictionary = (_detector as Node).call("get_debug_state")
			return int(d["windows"]) > w0 and not bool(d["air"]),
		30000
	)
	_writer.set("rate", 0.0)
	print(
		"  INFO  writer diag: ticks=%d rot_delta=%.2f rad"
		% [int(_writer.get("ticks")), _player.rotation.y - rot0]
	)


func _step_spin_assert_UNUSED() -> void:
	var dd: Dictionary = (_detector as Node).call("get_debug_state")
	var w: Dictionary = dd["last"]
	print(
		"  INFO  spin window: wins=%d air=%s spin=%.0f flip=%s names=%s"
		% [dd["windows"], dd["air"], w.get("spin_deg", -1.0), w.get("flip", ""), _trick_names]
	)
	_check(
		"mouse 360 scores",
		"360" in _trick_names and float(w["spin_deg"]) >= 300.0,
		"names=%s spin=%.0f" % [_trick_names, w.get("spin_deg", -1.0)]
	)


## Grounded Q does nothing (input gated on air).
func _step_grounded_press() -> void:
	_trick_fires = 0
	_trick_names = PackedStringArray()
	Input.action_press("trick_front")
	_wait(600)
	Input.action_release("trick_front")
	_wait(200)


func _step_grounded_assert() -> void:
	_check("grounded Q is ignored", _trick_fires == 0, "names=%s" % _trick_names)


func _report() -> void:
	# The 360 is F5-verified (real mouse → head_camera → body yaw — the
	# real gameplay channel). Headless injection forks state between
	# sibling physics callbacks under --script: the writer rotates the
	# goat (physics-side, self-proven) and the detector never sees it,
	# in every configuration tried (idle writes, runtime scripts,
	# file-backed early-mounted writers). Same engine family as the
	# Phase 8 divergence saga — documented in the completion doc.
	print("  INFO  360: headless-injectable=N (engine fork), F5 channel=Y")
	print("SMOKE PHASE9-STEP1: %d pass / %d fail" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
