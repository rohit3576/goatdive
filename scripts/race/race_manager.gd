class_name RaceManager
extends Node3D
## Phase 6 race state machine (plan: docs/plans/phase-6-race-system.md
## D3/D4/D5/D6/D8): COUNTDOWN → RACING → FINISHED. Sole owner of the
## clock — GameState.race_time is its live mirror (reset here: autoloads
## survive scene reloads, D9). The racer-list (D6) renders "1/1" honestly
## until Phase 7 fills it with AI goats.

enum State { COUNTDOWN, RACING, FINISHED }

const STATE_NAMES: PackedStringArray = ["countdown", "racing", "finished"]

var _goat: GoatController
var _course: CourseBuilder
var _gates: Array[Checkpoint] = []
var _state: State = State.COUNTDOWN
var _countdown := 0.0
var _timer := 0.0
var _gate_idx := 0  # index of the NEXT gate to pass
var _splits: Array[float] = []
var _top_speed := 0.0
var _crashes := 0
var _wrong_way := false
var _wrong_time := 0.0

# D6 racer records — the player goat is entry 0 until Phase 7.
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


## Wired by mountain_level.gd AFTER the goat spawns — children _ready
## before the level script runs, so the goat doesn't exist in our _ready.
func begin(goat: GoatController) -> void:
	_goat = goat
	_goat.set_input_enabled(false)
	_countdown = Config.RACE_COUNTDOWN
	_racers = [{"name": "YOU", "node": goat, "finished": false, "time": 0.0, "progress": 0.0}]
	if not _gates.is_empty():
		_gates[0].set_state(Checkpoint.State.NEXT)
		for gate in _gates:
			gate.body_entered_gate.connect(_on_gate_body.bind(gate))


func _physics_process(delta: float) -> void:
	match _state:
		State.COUNTDOWN:
			_countdown -= delta
			if _countdown <= 0.0:
				_state = State.RACING
				_timer = 0.0
				if _goat != null:
					_goat.set_input_enabled(true)
				EventBus.race_started.emit()
		State.RACING:
			_timer += delta
			GameState.race_time = _timer
			if _goat != null and _course != null:
				var d := _goat.get_debug_state()
				_top_speed = maxf(_top_speed, d.speed)
				_racers[0]["progress"] = (
					_course.course_length()
					- _course.distance_to_finish(_goat.global_position)
				)
			_update_wrong_way(delta)
		State.FINISHED:
			pass


## One snapshot for the HUD, F3, and the smoke test (the get_debug_state
## habit: one truth, several readouts).
func get_race_state() -> Dictionary:
	var dist := 0.0
	if _goat != null and _course != null:
		dist = _course.distance_to_finish(_goat.global_position)
	return {
		"state": STATE_NAMES[_state],
		"countdown": maxf(0.0, _countdown),
		"time": _timer,
		"time_str": _fmt_time(_timer),
		"gates_passed": _splits.size(),
		"gate_count": _gates.size(),
		"dist_to_finish": dist,
		"position": _position_of(0),
		"racers": _racers.size(),
		"wrong_way": _wrong_way,
		"top_speed": _top_speed,
		"crashes": _crashes,
		"splits": _splits,
		"best_split": _best_split(),
		"best_split_str": (
			_fmt_time(_best_split()) if _splits.size() >= 2 else "—"
		),
		"finished": _state == State.FINISHED,
	}


# --- gate advancement (D2: order enforced physically + by identity) --------


func _on_gate_body(body: Node3D, gate: Checkpoint) -> void:
	if body != _goat or _state != State.RACING or _gates.is_empty():
		return
	if _gates[mini(_gate_idx, _gates.size() - 1)] != gate:
		return  # skipped/out-of-order gate — physically unlikely, still guarded
	var split := _timer
	_splits.append(split)
	EventBus.checkpoint_passed.emit(gate.idx, split)
	gate.set_state(Checkpoint.State.PASSED)
	# D8: falling past here respawns AT the gate, not on the peak.
	if _goat != null:
		_goat.setup_spawn(_respawn_at(gate))
	_gate_idx += 1
	if _gate_idx >= _gates.size():
		_finish()
	else:
		_gates[_gate_idx].set_state(Checkpoint.State.NEXT)


func _respawn_at(gate: Checkpoint) -> Transform3D:
	return Transform3D(
		Basis.looking_at(gate.forward(), Vector3.UP),
		gate.global_position + Vector3.UP * 1.2
	)


func _finish() -> void:
	_state = State.FINISHED
	if not _racers.is_empty():
		_racers[0]["finished"] = true
		_racers[0]["time"] = _timer
	EventBus.race_finished.emit(_timer)


# --- bookkeeping -------------------------------------------------------------


func _on_bonked(impact: float, _direction: Vector3) -> void:
	# Crash proxy for the results panel: bonks at tumble strength.
	if _state == State.RACING and impact >= Config.TUMBLE_MIN_IMPACT:
		_crashes += 1


## Backtracking check (plan Step 4 stretch): velocity pointing away from
## the next gate for RACE_WRONG_WAY_TIME → the HUD flashes.
func _update_wrong_way(delta: float) -> void:
	if _goat == null or _gate_idx >= _gates.size():
		_wrong_way = false
		return
	var to_gate := _gates[_gate_idx].global_position - _goat.global_position
	to_gate.y = 0.0
	var vel := Vector2(_goat.velocity.x, _goat.velocity.z)
	if to_gate.length_squared() < 1.0 or vel.length() < 3.0:
		_wrong_time = 0.0
	elif vel.dot(Vector2(to_gate.x, to_gate.z).normalized()) < 0.0:
		_wrong_time += delta
	else:
		_wrong_time = 0.0
	_wrong_way = _wrong_time > Config.RACE_WRONG_WAY_TIME


# --- position (D6: honest with one racer, correct with many) ----------------


func _position_of(i: int) -> int:
	var pos := 1
	for j in _racers.size():
		if j != i and _racer_ahead(_racers[j], _racers[i]):
			pos += 1
	return pos


func _racer_ahead(other: Dictionary, me: Dictionary) -> bool:
	if other["finished"] and not me["finished"]:
		return true
	if other["finished"] and me["finished"]:
		return other["time"] < me["time"]
	if not other["finished"] and not me["finished"]:
		return other.get("progress", 0.0) > me.get("progress", 0.0)
	return false


func _best_split() -> float:
	if _splits.size() < 2:
		return 0.0
	var best := _splits[0]
	for i in range(1, _splits.size()):
		best = minf(best, _splits[i] - _splits[i - 1])
	return best


func _fmt_time(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]
