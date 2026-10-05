extends Node
## Autoload "Sfx" — Phase 12 audio director (plan: docs/plans/
## phase-12-audio-fx.md). A pure LISTENER (plan D2): it consumes EventBus
## signals and polls RaceManager's snapshot; it never emits, never touches
## racer nodes, never writes physics. The gauntlet must stay bit-identical.
##
## Layers:
##   one-shots  signal-driven (jump/land/bonk/trick/gate/progression)
##   loops      poll-driven (plan D3, Phase 11 D3 precedent): footsteps,
##              wind, fall rush, countdown beeps — zero new signals
##   music      two crossfaded loops, calm ↔ drive, keyed on
##              race_started / race_finished only
##
## Buses are code-built (D4): Master → Music / Sfx / Ambience, volumes in
## Config. PROCESS_MODE_ALWAYS (D5): the pause menu keeps its clicks and
## its soundtrack. Missing bank slots are silent no-ops (D10) — a fresh
## checkout without the generated WAVs still boots and races clean.

const BANK := "res://assets/sounds/"
const LOOPS := {"wind": true, "music_calm": true, "music_drive": true}
const BANK_SLOTS: PackedStringArray = [
	"step", "jump", "land", "bonk", "coin", "gate", "trick", "beep", "go",
	"bleat", "fall", "levelup", "wind", "music_calm", "music_drive",
]
const TRICK_STINGERS: Dictionary = {
	# trick_scored name → bank slot (coin rides the same signal, Ph9 D1).
	"coin": "coin", "near_miss": "trick",
	"front_flip": "trick", "back_flip": "trick", "spin": "trick",
	"long_jump": "trick", "cliff_drop": "trick", "log_hop": "trick",
}
const FADE_DB_FLOOR := -60.0

var _streams: Dictionary = {}  # slot → AudioStreamWAV | null (missing)
var _pool: Array[AudioStreamPlayer] = []
var _pool_idx := 0
var _music: Dictionary = {}  # id → {"player": AudioStreamPlayer, "vol": float}
var _music_id := "calm"
var _wind: AudioStreamPlayer

# Poll state.
var _stride_acc := 0.0
var _fall_armed := true
var _last_beep := -1
var _prev_race_state := ""

# F3 / smoke observability (repo debug-state pattern).
var _one_shots := 0
var _skipped := 0
var _footsteps := 0
var _beeps := 0
var _last_one_shot := ""
## Headless contract (plan D10): presence + call-safety, never audibility.
## The Dummy audio driver's playbacks are never released at forced quit
## (engine-level "resources still in use" on the loop streams), so in
## headless runs play() registers in the counters and skips the mixer.
var _audible := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_audible = DisplayServer.get_name() != "headless"
	_build_buses()
	_load_bank()
	_build_players()
	_connect_events()
	_set_music("calm")


func _process(delta: float) -> void:
	_music_tick(delta)
	_poll_tick(delta)


func _exit_tree() -> void:
	# Release loop playbacks before the resource cache clears (quit hygiene
	# for audible runs — see the _audible note above).
	if _wind != null:
		_wind.stop()
	for id in _music:
		(_music[id]["player"] as AudioStreamPlayer).stop()


# --- buses & bank -------------------------------------------------------------


func _build_buses() -> void:
	for pair in [
		["Music", Config.SFX_VOL_MUSIC_DB],
		["Sfx", Config.SFX_VOL_SFX_DB],
		["Ambience", Config.SFX_VOL_AMBIENCE_DB],
	]:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, pair[0])
		AudioServer.set_bus_send(idx, "Master")
		AudioServer.set_bus_volume_db(idx, pair[1])


func _load_bank() -> void:
	for slot in BANK_SLOTS:
		var path := BANK + slot + ".wav"
		var stream: AudioStreamWAV = null
		if ResourceLoader.exists(path):
			stream = load(path) as AudioStreamWAV
			if stream != null and LOOPS.has(slot):
				# The WAV importer defaults loop OFF — looping is a runtime
				# property of the consumer, not the file (CC0 swap-in
				# freedom, plan D1).
				stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
				stream.loop_begin = 0
				stream.loop_end = stream.data.size() / 2
		_streams[slot] = stream


func _build_players() -> void:
	for i in Config.SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Sfx"
		add_child(p)
		_pool.append(p)
	for id in ["calm", "drive"]:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.stream = _streams["music_" + id]
		p.volume_db = FADE_DB_FLOOR
		add_child(p)
		if _audible and p.stream != null:
			p.play()
		_music[id] = {"player": p, "vol": FADE_DB_FLOOR}
	_wind = AudioStreamPlayer.new()
	_wind.bus = "Ambience"
	_wind.stream = _streams["wind"]
	_wind.volume_db = FADE_DB_FLOOR
	add_child(_wind)
	if _audible and _wind.stream != null:
		_wind.play()


# --- events (one-shots, plan D8: player-only attribution) ----------------------


func _connect_events() -> void:
	EventBus.goat_jumped.connect(_on_jumped)
	EventBus.goat_landed.connect(_on_landed)
	EventBus.goat_bonked.connect(_on_bonked)
	EventBus.goat_hit_obstacle.connect(_on_obstacle_hit)
	EventBus.trick_scored.connect(_on_trick_scored)
	EventBus.checkpoint_passed.connect(_on_gate_passed)
	EventBus.coins_changed.connect(_on_coins_changed)
	EventBus.level_up.connect(_on_level_up)
	EventBus.upgrade_purchased.connect(_on_upgrade)
	EventBus.mountain_unlocked.connect(_on_unlock)
	EventBus.skin_unlocked.connect(_on_unlock)
	EventBus.race_started.connect(func() -> void: _set_music("drive"))
	EventBus.race_finished.connect(func(_t: float) -> void: _set_music("calm"))


func _on_jumped(goat: Node3D) -> void:
	if _is_player(goat):
		play("jump", -4.0)


func _on_landed(impact: float, goat: Node3D) -> void:
	if not _is_player(goat):
		return
	# Small hops tick, cliff drops slam — same curve the camera dip uses
	# (camera_fx.gd:213).
	var k := clampf(impact / Config.STUMBLE_IMPACT, 0.25, 1.25)
	play("land", linear_to_db(0.45 + 0.55 * k))
	if impact >= Config.STUMBLE_IMPACT:
		play("bleat", -6.0)  # the goat objects


func _on_bonked(_impact: float, _dir: Vector3, goat: Node3D) -> void:
	if _is_player(goat):
		play("bonk", -2.0)


func _on_obstacle_hit(_impact: float, goat: Node3D) -> void:
	if _is_player(goat):
		play("bonk", -2.0)


func _on_trick_scored(name: String, _points: int, goat: Node3D) -> void:
	if not _is_player(goat):
		return
	play(String(TRICK_STINGERS.get(name, "trick")), -3.0)


func _on_gate_passed(_idx: int, _split: float, racer: String) -> void:
	# Same guard as camera_fx.gd:234 — AI gates stay silent.
	if racer == "YOU":
		play("gate", -4.0)


func _on_coins_changed(_total: int, _delta: int) -> void:
	play("coin", -5.0)


func _on_level_up(_level: int) -> void:
	play("levelup", -3.0)


func _on_upgrade(_stat: String, _tier: int) -> void:
	play("levelup", -8.0, 1.3)


func _on_unlock(_id: String) -> void:
	play("levelup", -3.0)


## Player-only guard (plan D8). No manager (menu / smoke / synthetic emit)
## → treat as player: the smoke battery drives these paths directly.
func _is_player(goat: Node3D) -> bool:
	var mgr := get_tree().get_first_node_in_group("race_manager")
	return mgr == null or (mgr as Node).call("is_player", goat)


# --- one-shot API --------------------------------------------------------------


func play(slot: String, vol_db := 0.0, pitch := 1.0) -> void:
	var stream: AudioStreamWAV = _streams.get(slot)
	if stream == null:
		_skipped += 1
		return
	_one_shots += 1
	_last_one_shot = slot
	if not _audible:
		return  # headless: registered, never mixed (D10)
	var p := _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % _pool.size()
	if p.playing:
		p.stop()  # voice steal — round robin, oldest by construction
	p.stream = stream
	p.volume_db = vol_db
	p.pitch_scale = maxf(
		0.05, pitch + randf_range(-Config.SFX_PITCH_JITTER, Config.SFX_PITCH_JITTER)
	)
	p.play()


# --- poll loops (plan D3) -------------------------------------------------------


func _poll_tick(delta: float) -> void:
	var mgr := get_tree().get_first_node_in_group("race_manager")
	if mgr == null:
		_wind.volume_db = lerpf(_wind.volume_db, FADE_DB_FLOOR, 0.05)
		_prev_race_state = ""
		_last_beep = -1
		return
	var r: Dictionary = (mgr as Node).call("get_race_state")

	_footsteps_tick(r, delta)
	_wind_tick(r)
	_fall_tick(r)
	_countdown_tick(r)


func _footsteps_tick(r: Dictionary, delta: float) -> void:
	var grounded := bool(r.get("grounded", false))
	var speed := float(r.get("speed", 0.0))
	if speed < Config.FOOT_MIN_SPEED:
		_stride_acc = 0.0  # standing still — a stride half-walked is noise
		return
	if not grounded:
		return  # airborne PAUSES the stride — distance is distance; the
		# gauntlet's 69 landings say the herd mini-hops constantly on steep
		# terrain, and resetting here starved the footfall cadence.
	_stride_acc += speed * delta
	if _stride_acc >= Config.FOOT_STRIDE_M:
		_stride_acc -= Config.FOOT_STRIDE_M
		var pitch := float(Config.FOOT_SURFACE_PITCH.get(String(r.get("surface", "ROCK")), 1.0))
		play("step", -8.0, pitch)
		_footsteps += 1


func _wind_tick(r: Dictionary) -> void:
	var speed := float(r.get("speed", 0.0))
	var alt := float(r.get("alt", 0.0))
	var by_speed := clampf(speed / Config.MAX_DOWNHILL_SPEED, 0.0, 1.0)
	var by_alt := clampf(alt / 300.0, 0.0, 1.0)
	var lin := clampf(0.10 + 0.60 * by_speed + 0.30 * by_alt, 0.0, 1.0)
	var target := lerpf(-30.0, Config.WIND_MAX_DB, lin)
	_wind.volume_db = lerpf(_wind.volume_db, target, 0.1)


func _fall_tick(r: Dictionary) -> void:
	if bool(r.get("grounded", true)):
		_fall_armed = true
	elif float(r.get("vy", 0.0)) < Config.FALL_RUSH_VY and _fall_armed:
		_fall_armed = false
		play("fall", -4.0)


func _countdown_tick(r: Dictionary) -> void:
	var state := String(r.get("state", ""))
	if state == "countdown":
		var c := float(r.get("countdown", 0.0))
		if c > 0.0 and beep_at(float(_last_beep), c):
			play("beep", -3.0)
			_beeps += 1
		if c > 0.0:
			_last_beep = int(ceil(c))
	elif _prev_race_state == "countdown":
		play("go", -3.0)
		_last_beep = -1
	_prev_race_state = state


## Pure: does crossing from prev-ceil → now earn a beep? (smoke-testable)
static func beep_at(prev_ceil: float, now: float) -> bool:
	if prev_ceil < 0.0:
		return true  # first sighting of a live countdown
	return int(ceil(now)) < int(prev_ceil)


# --- music ----------------------------------------------------------------------


func _set_music(id: String) -> void:
	_music_id = id


func _music_tick(delta: float) -> void:
	for id in _music:
		var target := 0.0 if id == _music_id else FADE_DB_FLOOR
		var m: Dictionary = _music[id]
		# 60 dB of fade at MUSIC_FADE×60 dB/s — audible ~1 s, silent ~2 s.
		m["vol"] = move_toward(float(m["vol"]), target, Config.MUSIC_FADE * 60.0 * delta)
		(m["player"] as AudioStreamPlayer).volume_db = float(m["vol"])


## F3 overlay / smoke battery surface.
func get_debug_state() -> Dictionary:
	var loaded := 0
	for slot in _streams:
		if _streams[slot] != null:
			loaded += 1
	return {
		"music": _music_id,
		"one_shots": _one_shots,
		"skipped": _skipped,
		"footsteps": _footsteps,
		"beeps": _beeps,
		"last_one_shot": _last_one_shot,
		"bank_loaded": loaded,
		"bank_missing": BANK_SLOTS.size() - loaded,
	}
