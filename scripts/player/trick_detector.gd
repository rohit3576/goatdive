class_name TrickDetector
extends Node
## Phase 9 tricks (plan: docs/plans/phase-9-tricks-and-scoring.md D1/D4):
## the air WINDOW is the atom of the whole system — goat_jumped opens it,
## goat_landed closes it, bonks void it. Everything scoreable (flips,
## spins, long/cliff/log jumps, combos) is measured against this window.
##
## Listeners only (D1): physics lives in the verified controller; this
## node samples get_debug_state() and the signal vocabulary — it never
## integrates anything itself. Player-only v1 (D7): mountain_level mounts
## exactly one, on the player.

var _goat: GoatController
var _course: CourseBuilder
var _logs: Array = []  # log records (segment obstacles — D9)
var _near: Array = []  # ALL obstacle records (near-miss candidates)
var _near_cd: PackedInt64Array = []  # per-record cooldown, msec
var _near_count := 0
var _pending: Array = []  # {i, at} band entries awaiting hit-retraction
var _hit_lock := 0  # msec — suppress scoring right after a hit

# --- air window state ---
var _in_air := false
var _voided := false
var _t := 0.0
var _start := Vector3.ZERO
var _max_speed := 0.0
var _peak_y := -INF
var _spin := 0.0  # accumulated |body yaw| rad in the window (mouse 360s)
var _last_yaw := 0.0
var _yaw_valid := false
var _flip := ""  # "", "front", "back" — set by the input edge below
var _flip_t := 0.0
var _prev_front := false
var _prev_back := false

# Last closed window (the smoke + HUD read this snapshot).
var last_window: Dictionary = {}
var windows := 0  # closed-window count (smokes detect NEW windows)


func _ready() -> void:
	_goat = get_parent() as GoatController
	var level := _goat.get_parent()
	_course = level.get_node_or_null("Course") as CourseBuilder
	var obs := level.get_node_or_null("Obstacles") as Obstacles
	if obs != null:
		_logs = obs.get_obstacles("logs")
		for kind in ["pines", "rocks", "logs"]:
			_near.append_array(obs.get_obstacles(kind))
		_near_cd.resize(_near.size())
		_near_cd.fill(0)
	EventBus.goat_jumped.connect(_on_jump)
	EventBus.goat_landed.connect(_on_landed)
	EventBus.goat_bonked.connect(_on_bonk)
	EventBus.goat_hit_obstacle.connect(_on_obstacle_hit)
	_last_yaw = _goat.global_rotation.y


var _log_pass := false  # flew within a log's crossing band this window


func _physics_process(delta: float) -> void:
	# Input edges are tracked on PRESSED (not just_pressed) — robust under
	# the --script frame-timing chaos and identical in a real window.
	var front_now := Input.is_action_pressed("trick_front")
	var back_now := Input.is_action_pressed("trick_back")
	if _in_air:
		_t += delta
		var d := _goat.get_debug_state()
		_max_speed = maxf(_max_speed, float(d["speed"]))
		_peak_y = maxf(_peak_y, _goat.global_position.y)
		# Accumulate wrapped body-yaw delta (the mouse-spin channel).
		var yaw := _goat.global_rotation.y
		if _yaw_valid:
			_spin += absf(wrapf(yaw - _last_yaw, -PI, PI))
		_last_yaw = yaw
		_yaw_valid = true
		# Rotation trick input: one flip per air window (D2).
		if _flip == "" and not _voided:
			if front_now and not _prev_front:
				if _t < 1.0:
					print("EDGE front t=%.2f" % _t)
				_begin_flip("front")
			elif back_now and not _prev_back:
				_begin_flip("back")
		if _t < 0.5 and Engine.get_physics_frames() % 15 == 0:
			print("INP t=%.2f front=%s prev=%s air=%s" % [_t, front_now, _prev_front, _in_air])
		if _flip != "":
			_flip_t += delta
		# Log-jump proximity (D9): within the crossing band of any log
		# segment — scored on a clean close (a hit voids anyway).
		if not _log_pass:
			var px := _goat.global_position.x
			var pz := _goat.global_position.z
			for rec in _logs:
				var r: Dictionary = rec
				var lp: Vector3 = r["pos"]
				var to := Vector2(lp.x - px, lp.z - pz)
				var ax: Vector3 = r["axis"]
				var s := clampf(
					-to.dot(Vector2(ax.x, ax.z)), -float(r["half_len"]), float(r["half_len"])
				)
				var off := to + Vector2(ax.x, ax.z) * s
				if off.length() <= float(r["r"]) + 1.2:
					_log_pass = true
					break
	_prev_front = front_now
	_prev_back = back_now
	_near_miss_tick()


## Near miss (D9/D10): inside the band at speed, scored DEFERRED — a hit
## on any obstacle within 0.7 s of band entry retracts the payout (a hit
## is not a near miss; 0.7 s covers an 8 m approach's entry→impact gap).
func _near_miss_tick() -> void:
	var now := Time.get_ticks_msec()
	# Retract/expire pending entries.
	if not _pending.is_empty():
		var still: Array = []
		for p in _pending:
			var e: Dictionary = p
			if now - int(e["at"]) > 700:
				if now >= _hit_lock:
					_near_count += 1
					EventBus.trick_scored.emit("near_miss", Config.TRICK_PTS_NEAR, _goat)
			else:
				still.append(e)
		_pending = still
	if now < _hit_lock:
		return
	var d := _goat.get_debug_state()
	if float(d["speed"]) < Config.TRICK_NEAR_MISS_SPEED:
		return
	var px := _goat.global_position.x
	var pz := _goat.global_position.z
	for i in _near.size():
		if now < _near_cd[i]:
			continue
		var r: Dictionary = _near[i]
		var op: Vector3 = r["pos"]
		var to := Vector2(op.x - px, op.z - pz)
		var dist := to.length()
		if r.has("axis"):
			var ax: Vector3 = r["axis"]
			var s := clampf(-to.dot(Vector2(ax.x, ax.z)), -float(r["half_len"]), float(r["half_len"]))
			dist = (to + Vector2(ax.x, ax.z) * s).length()
		if dist - float(r["r"]) <= Config.TRICK_NEAR_MISS_R:
			_near_cd[i] = now + int(Config.TRICK_NEAR_MISS_CD * 1000.0)
			_pending.append({"i": i, "at": now})


func _on_obstacle_hit(_impact: float, goat: Node3D) -> void:
	if goat != _goat:
		return
	_pending.clear()  # a hit retracts its own band entry (and neighbors')
	_hit_lock = Time.get_ticks_msec() + 800


func _begin_flip(kind: String) -> void:
	_flip = kind
	_flip_t = 0.0
	# Front = nose-down-first around the goat's local right (visual sign;
	# F5 flips it if the first read is backwards).
	var axis := _goat.global_transform.basis.x
	if kind == "front":
		axis = -axis
	_goat.start_trick_spin(axis, Config.TRICK_FLIP_TIME)


# --- window open / close / void -------------------------------------------------


func _on_jump(goat: Node3D) -> void:
	if goat != _goat:
		return
	_in_air = true
	_voided = false
	_t = 0.0
	_start = _goat.global_position
	_peak_y = _start.y
	_max_speed = 0.0
	_spin = 0.0
	_yaw_valid = false
	_flip = ""
	_flip_t = 0.0
	# Trick buffering (like jump buffering): a key held through liftoff
	# re-edges at window open — flip at the moment of takeoff.
	_prev_front = false
	_prev_back = false


func _on_landed(impact: float, goat: Node3D) -> void:
	if goat != _goat or not _in_air:
		return
	_in_air = false
	windows += 1
	var flip_progress := minf(_flip_t / Config.TRICK_FLIP_TIME, 1.0) if _flip != "" else 0.0
	var end := _goat.global_position
	var dist := Vector2(end.x - _start.x, end.z - _start.z).length()
	var spin_deg := rad_to_deg(_spin)
	last_window = {
		"airtime": _t,
		"distance": dist,
		"drop": _start.y - end.y,  # landing drop (cliff jump reads this)
		"rise": _peak_y - _start.y,
		"max_speed": _max_speed,
		"spin_deg": spin_deg,
		"flip": _flip,
		"flip_progress": flip_progress,
		"land_impact": impact,
		"voided": _voided or impact > Config.STUMBLE_IMPACT,  # D4: slam voids
	}
	# --- Scoring (D4 clean windows only; D5 distinct-trick combo) --------
	if not last_window["voided"]:
		var tricks: Array = []  # {name, pts}
		if _flip != "" and flip_progress >= Config.TRICK_FLIP_CLEAN:
			tricks.append({"name": "%s_flip" % _flip, "pts": Config.TRICK_PTS_FLIP})
		if spin_deg >= Config.TRICK_SPIN_DEG:
			tricks.append({"name": "360", "pts": Config.TRICK_PTS_SPIN})
		if dist >= Config.TRICK_LONG_JUMP_M:
			tricks.append({"name": "long_jump", "pts": Config.TRICK_PTS_LONG})
		if last_window["drop"] >= Config.TRICK_CLIFF_DROP_M:
			tricks.append({"name": "cliff_jump", "pts": Config.TRICK_PTS_CLIFF})
		if _log_pass:
			tricks.append({"name": "log_jump", "pts": Config.TRICK_PTS_LOG})
		# Every trick in the window shares the window's multiplier.
		var mult := 1.0 + Config.TRICK_COMBO_STEP * maxi(0, tricks.size() - 1)
		for t in tricks:
			EventBus.trick_scored.emit(
				String(t["name"]), int(round(float(t["pts"]) * mult)), _goat
			)
	_log_pass = false


func _on_bonk(_impact: float, _dir: Vector3, goat: Node3D) -> void:
	if goat == _goat and _in_air:
		_voided = true


## Airborne check the input layer (Step 2) and HUD read.
func is_airborne() -> bool:
	return _in_air


func get_debug_state() -> Dictionary:
	var flipping := _in_air and _flip != "" and _flip_t < Config.TRICK_FLIP_TIME
	return {
		"air": _in_air,
		"t": _t,
		"voided": _voided,
		"spin_deg": rad_to_deg(_spin),
		"flip": _flip,
		"flip_progress": minf(_flip_t / Config.TRICK_FLIP_TIME, 1.0),
		"flipping": flipping,
		"nm": _near_count,
		"last": last_window,
		"windows": windows,
	}
