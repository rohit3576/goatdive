extends SceneTree
## tools/gen_sounds.gd — Phase 12 sound-bank synthesizer (plan D1).
##
## Run:  godot --headless --script tools/gen_sounds.gd
## Then: godot --headless --import   (so load() can see the new WAVs)
##
## Synthesizes the placeholder bank into assets/sounds/ — 16-bit PCM mono
## WAVs, fully deterministic (fixed RNG seed, fixed call order), so a fresh
## checkout reproduces byte-identical files. Any slot can later be replaced
## by a real CC0 asset with the SAME FILENAME and zero code changes; the
## AudioManager skips gracefully if a file is missing (plan D10).
##
## Slots (name → consumer):
##   step / jump / land / bonk    goat controller events
##   coin / gate / trick / beep / go / levelup / bleat   scoring & UI
##   fall                         big-drop whoosh
##   wind / music_calm / music_drive    seamless loops (loop_mode set
##                                      at load time by AudioManager)

const OUT_DIR := "res://assets/sounds"
const RATE := 16000  # placeholder fidelity; real assets may use 44100
const RNG_SEED := 4212

var _fail := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var rng := RandomNumberGenerator.new()
	rng.seed = RNG_SEED

	# Fixed call order = deterministic noise draws = byte-identical bank.
	_emit("step.wav", _step(rng))
	_emit("jump.wav", _jump(rng))
	_emit("land.wav", _land(rng))
	_emit("bonk.wav", _bonk(rng))
	_emit("coin.wav", _coin())
	_emit("gate.wav", _gate())
	_emit("trick.wav", _trick())
	_emit("beep.wav", _beep())
	_emit("go.wav", _go())
	_emit("bleat.wav", _bleat())
	_emit("fall.wav", _fall(rng))
	_emit("levelup.wav", _levelup())
	_emit("wind.wav", _wind(rng))
	_emit("music_calm.wav", _music_calm())
	_emit("music_drive.wav", _music_drive(rng))

	print(
		"gen_sounds: bank written in %d ms (%s)"
		% [Time.get_ticks_msec() - t0, "PASS" if _fail == 0 else "FAIL"]
	)
	quit(_fail)


# --- synthesis helpers --------------------------------------------------------


func _emit(file: String, samples: PackedFloat32Array) -> void:
	var path := OUT_DIR + "/" + file
	var err := _write_wav(path, samples)
	if err != OK:
		_fail += 1
		printerr("gen_sounds: FAILED %s (err %d)" % [file, err])
		return
	var kb := float(samples.size() * 2 + 44) / 1024.0
	print("gen_sounds: %-18s %6.1f KB  %5.2f s" % [file, kb, float(samples.size()) / RATE])


func _write_wav(path: String, samples: PackedFloat32Array) -> int:
	var n := samples.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		# Soft clip keeps synthesis headroom from becoming digital snap.
		var s: float = samples[i] / (1.0 + absf(samples[i]))
		data.encode_s16(i * 2, int(clampf(s, -0.999, 0.999) * 32767.0))

	var p := StreamPeerBuffer.new()
	p.big_endian = false
	p.put_32(0x46464952)  # "RIFF"
	p.put_32(36 + data.size())
	p.put_32(0x45564157)  # "WAVE"
	p.put_32(0x20746D66)  # "fmt "
	p.put_32(16)  # fmt chunk size
	p.put_16(1)  # PCM
	p.put_16(1)  # mono
	p.put_32(RATE)
	p.put_32(RATE * 2)  # byte rate
	p.put_16(2)  # block align
	p.put_16(16)  # bits
	p.put_32(0x61746164)  # "data"
	p.put_32(data.size())
	p.put_data(data)

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ERR_CANT_OPEN
	f.store_buffer(p.data_array)
	f.close()
	return OK


func _n(seconds: float) -> int:
	return int(seconds * RATE)


## One-pole low-pass — cheap, stable, colors noise "windy".
func _lp(src: PackedFloat32Array, cutoff_hz: float) -> PackedFloat32Array:
	var out := src.duplicate()
	var a: float = 1.0 - exp(-TAU * cutoff_hz / RATE)
	var y := 0.0
	for i in out.size():
		y += a * (src[i] - y)
		out[i] = y
	return out


## First-difference high-pass — makes noise read as "rush/hiss".
func _hp(src: PackedFloat32Array) -> PackedFloat32Array:
	var out := src.duplicate()
	var prev := 0.0
	for i in src.size():
		out[i] = src[i] - prev
		prev = src[i]
	return out


## Crossfade the tail into the head so the loop point is seamless.
func _loopify(src: PackedFloat32Array) -> PackedFloat32Array:
	var body := src.size() - _n(0.6)
	if body <= 0:
		return src
	var fade := src.size() - body
	var out := PackedFloat32Array()
	out.resize(body)
	for i in body:
		var w: float = float(i) / float(fade)
		out[i] = lerpf(src[i + fade], src[i], w)
	return out


func _noise(rng: RandomNumberGenerator, count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		out[i] = rng.randf_range(-1.0, 1.0)
	return out


func _env_exp(t: float, k: float) -> float:
	return exp(-k * t)


# --- the bank -----------------------------------------------------------------


func _step(rng: RandomNumberGenerator) -> PackedFloat32Array:
	# Grit burst + low thump — neutral timbre; surface sells it via pitch.
	var n := _n(0.09)
	var grit := _lp(_noise(rng, n), 900.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = grit[i] * 0.5 * _env_exp(t, 60.0) + sin(TAU * 95.0 * t) * 0.5 * _env_exp(t, 45.0)
	return out


func _jump(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := _n(0.35)
	var hiss := _lp(_noise(rng, n), 1400.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var rise: float = t / 0.35
		var f: float = lerpf(180.0, 430.0, rise)
		out[i] = (
			hiss[i] * 0.34 * rise * (1.0 - rise * 0.4)
			+ sin(TAU * f * t) * 0.22 * sin(PI * minf(rise, 1.0))
		)
	return out


func _land(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := _n(0.28)
	var slap := _lp(_noise(rng, n), 600.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = (
			sin(TAU * 68.0 * t) * 0.85 * _env_exp(t, 16.0)
			+ slap[i] * 0.30 * _env_exp(t, 42.0)
		)
	return out


func _bonk(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := _n(0.22)
	var click := _hp(_noise(rng, n))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = (
			sin(TAU * 165.0 * t) * 0.7 * _env_exp(t, 22.0)
			+ click[i] * 0.28 * _env_exp(t, 130.0)
		)
	return out


func _coin() -> PackedFloat32Array:
	var n := _n(0.32)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var a := sin(TAU * 1318.5 * t) * _env_exp(t, 11.0)
		var b := 0.0
		if t > 0.07:
			b = sin(TAU * 1760.0 * (t - 0.07)) * 0.8 * _env_exp(t - 0.07, 9.0)
		out[i] = (a + b) * 0.55 + sin(TAU * 2637.0 * t) * 0.08 * _env_exp(t, 18.0)
	return out


func _gate() -> PackedFloat32Array:
	var n := _n(0.5)
	var out := PackedFloat32Array()
	out.resize(n)
	var notes := [523.25, 659.25, 783.99]
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for k in notes.size():
			var start := 0.05 * k
			if t >= start:
				var lt: float = t - start
				s += sin(TAU * notes[k] * lt) * 0.4 * _env_exp(lt, 6.5)
		out[i] = s
	return out


func _trick() -> PackedFloat32Array:
	var n := _n(0.35)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var rise: float = t / 0.35
		var f: float = lerpf(620.0, 1580.0, rise)
		var shimmer: float = 0.6 + 0.4 * sin(TAU * 34.0 * t)
		out[i] = sin(TAU * f * t) * 0.5 * shimmer * _env_exp(t, 4.0)
	return out


func _beep() -> PackedFloat32Array:
	var n := _n(0.14)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := 1.0 if t < 0.11 else _env_exp(t - 0.11, 60.0)
		out[i] = (sin(TAU * 880.0 * t) + 0.35 * sin(TAU * 1760.0 * t)) * 0.42 * env
	return out


func _go() -> PackedFloat32Array:
	var n := _n(0.45)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := _env_exp(t, 3.5) * minf(t / 0.01, 1.0)
		out[i] = (
			(sin(TAU * 1046.5 * t) + 0.6 * sin(TAU * 1568.0 * t) + 0.2 * sin(TAU * 2093.0 * t))
			* 0.34 * env
		)
	return out


func _bleat() -> PackedFloat32Array:
	# Saw-ish stack under a goat-y 7 Hz tremolo with a little pitch wobble.
	var n := _n(0.55)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var wobble := 1.0 + 0.03 * sin(TAU * 6.0 * t)
		var f := 196.0 * wobble
		var saw := sin(TAU * f * t) + 0.5 * sin(TAU * 2.0 * f * t) + 0.33 * sin(TAU * 3.0 * f * t)
		var tremolo := 0.55 + 0.45 * sin(TAU * 7.0 * t)
		var env := minf(t / 0.02, 1.0) * _env_exp(t, 3.0)
		out[i] = saw * 0.28 * tremolo * env
	return out


func _fall(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := _n(1.4)
	var rush := _hp(_lp(_noise(rng, n), 2600.0))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t: float = float(i) / RATE
		var ramp: float = pow(t / 1.4, 2.0)
		out[i] = rush[i] * 0.55 * ramp * minf((1.4 - t) / 0.05, 1.0)
	return out


func _levelup() -> PackedFloat32Array:
	var n := _n(1.1)
	var out := PackedFloat32Array()
	out.resize(n)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for k in notes.size():
			var start := 0.12 * k
			if t >= start:
				var lt: float = t - start
				s += sin(TAU * notes[k] * lt) * 0.4 * _env_exp(lt, 3.2)
		out[i] = s
	return out


func _wind(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := _n(4.0) + _n(0.6)
	var base := _lp(_noise(rng, n), 420.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		# Slow deterministic gust LFOs — three sines, no RNG order risk.
		var gust := 0.45 + 0.30 * sin(TAU * 0.11 * t) + 0.25 * sin(TAU * 0.23 * t + 1.3)
		out[i] = base[i] * clampf(gust, 0.12, 1.0) * 1.5
	return _loopify(out)


func _music_calm() -> PackedFloat32Array:
	var n := _n(6.0) + _n(0.6)
	var out := PackedFloat32Array()
	out.resize(n)
	# Warm open-fifth pad (C3+G3) with a slow breathe LFO — menu/garage.
	for i in n:
		var t := float(i) / RATE
		var breathe := 0.5 + 0.28 * sin(TAU * 0.05 * t)
		var detune := 1.0 + 0.0012 * sin(TAU * 0.083 * t + 0.7)
		out[i] = (
			(sin(TAU * 130.81 * t) + sin(TAU * 130.81 * detune * t)) * 0.30
			+ sin(TAU * 196.0 * t) * 0.22
			+ sin(TAU * 261.63 * t) * 0.10
		) * breathe
	return _loopify(out)


func _music_drive(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := _n(6.0) + _n(0.6)
	var tick := _hp(_noise(rng, n))
	var out := PackedFloat32Array()
	out.resize(n)
	# 150 BPM pulse: gated A-minor bass + pentatonic arp + noise hats.
	var beat := 60.0 / 150.0
	for i in n:
		var t := float(i) / RATE
		var bt := fmod(t, beat)
		var bar_t := fmod(t, beat * 4.0)
		# Bass: A2, gated eighths.
		var bass := sin(TAU * 110.0 * t) * 0.42 * _env_exp(bt, 9.0)
		# Arp: A minor pentatonic, one note per beat, 4-bar cycle.
		var pent := [220.0, 261.63, 329.63, 440.0]
		var note: float = pent[int(t / beat) % 4]
		var arp := sin(TAU * note * t) * 0.20 * _env_exp(bt, 6.0)
		# Hats: offbeat ticks.
		var hat := tick[i] * 0.10 * _env_exp(fmod(bar_t + beat * 0.5, beat), 55.0)
		out[i] = bass + arp + hat
	return _loopify(out)
