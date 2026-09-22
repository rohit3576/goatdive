class_name RaceManager
extends Node3D
## Phase 7 multi-racer race state machine (plan D9, built on Phase 6 D4):
## COUNTDOWN → RACING → FINISHED stays player-centric (countdown, the
## race_finished emit), while gate progress, respawn, standings and
## finishing times are per-racer — record 0 is always the player.
## One clock runs from GO until the last racer finishes, so AI crossing
## after the player still get honest times.

enum State { COUNTDOWN, RACING, FINISHED }

const STATE_NAMES: PackedStringArray = ["countdown", "racing", "finished"]

var _course: CourseBuilder
var _gates: Array[Checkpoint] = []
var _state: State = State.COUNTDOWN
var _countdown := 0.0
var _clock := 0.0  # race clock — frozen only when every racer finished
var _clock_running := false
var _player_time := -1.0
var _top_speed := 0.0
var _crashes := 0
var _wrong_way := false
var _wrong_time := 0.0

# Phase 9 score (D8: per-race, dies with the scene; no persistence).
var _score := 0
var _best_trick := ""
var _best_trick_pts := 0

# Racer records (Phase 6 D6, Phase 7 D9). Index 0 = player.
# {name, node, gate_idx, splits, finished, time, progress}
var _racers: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("race_manager")
	GameState.race_time = 0.0  # autoload state must die with the scene too
	_course = get_parent().get_node_or_null("Course") as CourseBuilder
	if _course == null:
		push_warning("RaceManager: no Course sibling")
		return
	_gates = _course.get_gates()
	EventBus.goat_bonked.connect(_on_bonked)
	EventBus.goat_hit_obstacle.connect(_on_obstacle_hit)
	EventBus.trick_scored.connect(_on_trick_scored)


## Wired by mountain_level.gd AFTER racers spawn (children _ready before
## the level script runs). Entries: {"name": String, "node": GoatController}.
func begin(racers: Array) -> void:
	_racers = []
	for r in racers:
		var node := r["node"] as GoatController
		node.set_input_enabled(false)
		_racers.append({
			"name": String(r["name"]),
			"node": node,
			"gate_idx": 0,
			"splits": [],
			"finished": false,
			"time": 0.0,
			"progress": 0.0,
			"hits": 0,
		})
	_countdown = Config.RACE_COUNTDOWN
	if not _gates.is_empty():
		_gates[0].set_state(Checkpoint.State.NEXT)  # player-facing visual
		for gate in _gates:
			gate.body_entered_gate.connect(_on_gate_body.bind(gate))


func _physics_process(delta: float) -> void:
	match _state:
		State.COUNTDOWN:
			_countdown -= delta
			if _countdown <= 0.0:
				_state = State.RACING
				_clock_running = true
				for gate in _gates:
					gate.set_armed(true)  # order is manager-side now (D2 note)
				for rec in _racers:
					(rec["node"] as GoatController).set_input_enabled(true)
				EventBus.race_started.emit()
		_:
			if _clock_running:
				_clock += delta
				var all_done := true
				for rec in _racers:
					var node := rec["node"] as GoatController
					if not rec["finished"]:
						all_done = false
						if _course != null:
							rec["progress"] = (
								_course.course_length()
								- _course.distance_to_finish(node.global_position)
							)
				if all_done:
					_clock_running = false
			if _state == State.RACING:
				_player_tick(delta)


## Player-only per-tick bookkeeping (HUD mirror, feel stats, wrong way).
func _player_tick(delta: float) -> void:
	if _racers.is_empty() or _course == null:
		return
	var player := _racers[0]["node"] as GoatController
	var d := player.get_debug_state()
	_top_speed = maxf(_top_speed, float(d["speed"]))
	GameState.race_time = _clock
	_update_wrong_way(delta)


## One snapshot for the HUD, F3, and the smoke test.
func get_race_state() -> Dictionary:
	if _racers.is_empty():
		return {
			"state": STATE_NAMES[_state], "countdown": maxf(0.0, _countdown),
			"time": 0.0, "time_str": "0:00.00", "gates_passed": 0,
			"gate_count": _gates.size(), "dist_to_finish": 0.0,
			"position": 1, "racers": 0, "wrong_way": false,
			"top_speed": 0.0, "crashes": 0, "hits": 0, "splits": [], "best_split": 0.0,
			"best_split_str": "—", 			"finished": false, "standings": [],
			"score": 0, "best_trick": "",
			"ai_states": [],
		}
	var player: Dictionary = _racers[0]
	var splits: Array = player["splits"]
	var dist := 0.0
	if _course != null:
		dist = _course.distance_to_finish(
			(player["node"] as GoatController).global_position
		)
	var t := _player_time if _player_time >= 0.0 else _clock
	return {
		"state": STATE_NAMES[_state],
		"countdown": maxf(0.0, _countdown),
		"time": t,
		"time_str": _fmt_time(t),
		"gates_passed": splits.size(),
		"gate_count": _gates.size(),
		"dist_to_finish": dist,
		"position": _position_of(0),
		"racers": _racers.size(),
		"wrong_way": _wrong_way,
		"top_speed": _top_speed,
		"crashes": _crashes,
		"hits": int(_racers[0]["hits"]),  # player's corridor-obstacle hits (D8)
		"splits": splits,
		"best_split": _best_split(splits),
		"best_split_str": (
			_fmt_time(_best_split(splits)) if splits.size() >= 2 else "—"
		),
		"finished": _state == State.FINISHED,
		"score": _score,
		"best_trick": _best_trick,
		"standings": _standings(),
		"ai_states": _ai_states(),
	}


# --- gate advancement (order enforced by per-racer gate_idx) -----------------


func _on_gate_body(body: Node3D, gate: Checkpoint) -> void:
	if _state == State.COUNTDOWN or body == null:
		return
	var rec := _record_for(body)
	if rec.is_empty() or gate.idx != int(rec["gate_idx"]):
		return  # not a racer, or out of order for THIS racer
	var node := rec["node"] as GoatController
	var split := _clock
	(rec["splits"] as Array).append(split)
	EventBus.checkpoint_passed.emit(gate.idx, split, String(rec["name"]))
	node.setup_spawn(_respawn_at(gate))  # gate respawn is per-racer (D8)
	rec["gate_idx"] = int(rec["gate_idx"]) + 1
	var is_player := rec == _racers[0]
	if is_player:
		gate.set_state(Checkpoint.State.PASSED)
		if int(rec["gate_idx"]) < _gates.size():
			_gates[int(rec["gate_idx"])].set_state(Checkpoint.State.NEXT)
	if int(rec["gate_idx"]) >= _gates.size():
		rec["finished"] = true
		rec["time"] = _clock
		if is_player:
			_player_finish()


func _record_for(body: Node3D) -> Dictionary:
	for rec in _racers:
		if rec["node"] == body:
			return rec
	return {}  # caller checks is_empty() — not a racer body


## The racer's current gate index (brain rescue targeting; 0-based).
func gate_progress_for(node: Node) -> int:
	var rec := _record_for(node)
	return int(rec["gate_idx"]) if not rec.is_empty() else 0


## Player identity check (HUD trick labels filter on this).
func is_player(node: Node) -> bool:
	return not _racers.is_empty() and node == _racers[0]["node"]


func _respawn_at(gate: Checkpoint) -> Transform3D:
	return Transform3D(
		Basis.looking_at(gate.forward(), Vector3.UP),
		gate.global_position + Vector3.UP * 1.2
	)


func _player_finish() -> void:
	_state = State.FINISHED
	_player_time = _clock
	_racers[0]["time"] = _clock
	# Position bonus (Phase 9): style counts, but the podium prices in.
	match _position_of(0):
		1:
			_score += 500
		2:
			_score += 250
		3:
			_score += 100
	EventBus.race_finished.emit(_clock)


# --- bookkeeping -------------------------------------------------------------


func _on_bonked(impact: float, _direction: Vector3, goat: Node3D) -> void:
	# Player crash proxy for the results panel: the player's own tumble-grade
	# bonks, anywhere, any collider (Phase 8: attribution makes it player-only
	# — pre-Phase 8, ANY goat's tumble counted as a player crash).
	if _state == State.RACING and impact >= Config.TUMBLE_MIN_IMPACT and not _racers.is_empty() and goat == _racers[0]["node"]:
		_crashes += 1


## Difficulty telemetry (Phase 8 D8): per-racer OBSTACLE hits — the signal
## only fires for corridor-body colliders, so goat-goat bumps and terrain
## bonks never pollute the mountain's report card.
func _on_obstacle_hit(_impact: float, goat: Node3D) -> void:
	var rec := _record_for(goat)
	if rec.is_empty():
		return
	rec["hits"] = int(rec["hits"]) + 1


## Score intake (Phase 9): the detector's points are final (combo applied
## window-side). Player-only — the herd races, it doesn't style.
func _on_trick_scored(name: String, points: int, goat: Node3D) -> void:
	if _state != State.RACING or _racers.is_empty() or goat != _racers[0]["node"]:
		return
	_score += points
	if points > _best_trick_pts:
		_best_trick_pts = points
		_best_trick = name


func _update_wrong_way(delta: float) -> void:
	if _racers.is_empty() or int(_racers[0]["gate_idx"]) >= _gates.size():
		_wrong_way = false
		return
	var player := _racers[0]["node"] as GoatController
	var to_gate := _gates[int(_racers[0]["gate_idx"])].global_position - player.global_position
	to_gate.y = 0.0
	var vel := Vector2(player.velocity.x, player.velocity.z)
	if to_gate.length_squared() < 1.0 or vel.length() < 3.0:
		_wrong_time = 0.0
	elif vel.dot(Vector2(to_gate.x, to_gate.z).normalized()) < 0.0:
		_wrong_time += delta
	else:
		_wrong_time = 0.0
	_wrong_way = _wrong_time > Config.RACE_WRONG_WAY_TIME


# --- standings (D6: correct for 1 racer, honest for N) -----------------------


func _standings() -> Array[Dictionary]:
	var order := _racers.duplicate()
	order.sort_custom(_ahead_of)
	var out: Array[Dictionary] = []
	for i in order.size():
		var r: Dictionary = order[i]
		out.append({
			"pos": i + 1,
			"name": r["name"],
			"finished": r["finished"],
			"time": float(r["time"]),
			"time_str": _fmt_time(r["time"]) if r["finished"] else "racing…",
			"is_player": r == _racers[0],
		})
	return out


func _position_of(i: int) -> int:
	var pos := 1
	for j in _racers.size():
		if j != i and _ahead_of(_racers[j], _racers[i]):
			pos += 1
	return pos


func _ahead_of(a: Dictionary, b: Dictionary) -> bool:
	if a["finished"] and not b["finished"]:
		return true
	if a["finished"] and b["finished"]:
		return a["time"] < b["time"]
	if not a["finished"] and not b["finished"]:
		return a["progress"] > b["progress"]
	return false


func _best_split(splits: Array) -> float:
	if splits.size() < 2:
		return 0.0
	var best := splits[0] as float
	for i in range(1, splits.size()):
		best = minf(best, (splits[i] as float) - (splits[i - 1] as float))
	return best


func _ai_states() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _racers.size() < 2:
		return out
	for rec in _racers.slice(1):
		var brain := (rec["node"] as GoatController).get_node_or_null("AiGoat")
		if brain != null:
			out.append(brain.get_debug_state())
	return out


func _fmt_time(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]
