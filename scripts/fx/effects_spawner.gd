class_name EffectsSpawner
extends Node3D
## Phase 12 visual effects listener (plan: docs/plans/phase-12-audio-fx.md
## Step 6–8). Same contract as the audio director: consume EventBus
## signals + poll the manager snapshot, write NOTHING back — the gauntlet
## must stay bit-identical (plan D2).
##
## Layers:
##   one-shots   goat_landed dust (ALL goats — AI juice is world-visible,
##               plan Step 6), goat_bonked debris, player gate bursts,
##               coin sparkles. GPUParticles3D one-shots, code-built
##               materials (D6), timer-freed (headless-safe, D10).
##   weather     one camera-following snow emitter, altitude-gated by the
##               mountain's catalog snow line with hysteresis (D7), plus
##               always-on canyon dust.
##   streaks     air-streak particles parented to the camera, fading in
##               above STREAK_MIN_SPEED (Step 8). Camera shake is NOT
##               rebuilt here — Phase 4's trauma model already owns it (D7).

const Catalog := preload("res://scripts/terrain/mountain_catalog.gd")

var _course: Node  # CourseBuilder (duck-typed: shared game boundary)
var _mountain_id := "alpine_valley"
var _snow_line := 170.0
var _snow_max := 0
var _dust_max := 0

var _snow: GPUParticles3D
var _dust: GPUParticles3D
var _streak: GPUParticles3D
var _snow_on := false
var _snow_amt := 0.0
var _streak_amt := 0.0
var _mgr: Node  # RaceManager (duck-typed) — Phase 13 Step 4: cached ref

# F3 / smoke observability (repo debug-state pattern).
var _land_bursts := 0
var _bonk_bursts := 0
var _gate_bursts := 0
var _coin_bursts := 0
var _active := 0


func _ready() -> void:
	_course = get_parent().get_node_or_null("Course")
	EventBus.goat_landed.connect(_on_landed)
	EventBus.goat_bonked.connect(_on_bonked)
	EventBus.checkpoint_passed.connect(_on_gate_passed)
	EventBus.trick_scored.connect(_on_trick_scored)
	_setup_weather()
	_setup_streaks()


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Weather rides above the camera — snow falls INTO frame from above.
	if _snow != null:
		_snow.global_position = cam.global_position + Vector3(0.0, 9.0, 0.0)
		_snow_on = snow_gate(_snow_on, cam.global_position.y, _snow_line)
		var target := 1.0 if (_snow_on and _snow_max > 0) else 0.0
		_snow_amt = move_toward(_snow_amt, target, delta / 0.8)
		_snow.amount_ratio = _snow_amt
	if _dust != null:
		_dust.global_position = cam.global_position + Vector3(0.0, 2.0, 0.0)
	# Streaks: speed-driven ratio, CAM_FX-gated like every camera channel.
	# Phase 13 Step 2: the cheap speed accessor — no snapshot build per frame.
	if _streak != null:
		var speed := 0.0
		if _mgr == null or not is_instance_valid(_mgr):
			_mgr = get_tree().get_first_node_in_group("race_manager")
		if _mgr != null:
			speed = float(_mgr.call("get_player_speed"))
		var s_target := (
			clampf(
				(speed - Config.STREAK_MIN_SPEED)
				/ (Config.MAX_DOWNHILL_SPEED - Config.STREAK_MIN_SPEED),
				0.0,
				1.0,
			)
			if Config.CAM_FX
			else 0.0
		)
		_streak_amt = move_toward(_streak_amt, s_target, delta / 0.35)
		_streak.amount_ratio = _streak_amt


# --- one-shots (plan D6: code-built, timer-freed, headless-safe) ----------------


func _on_landed(impact: float, goat: Node3D) -> void:
	if goat == null:
		return
	var k := clampf(impact / Config.STUMBLE_IMPACT, 0.15, 1.0)
	var hard := impact >= Config.STUMBLE_IMPACT
	_burst(
		goat.global_position + Vector3(0.0, 0.15, 0.0),
		Color(0.58, 0.50, 0.38) if hard else Color(0.66, 0.60, 0.48),
		int(ceil(Config.FX_LAND_PARTICLES * k)),
		2.0 + 2.5 * k,
	)
	_land_bursts += 1


func _on_bonked(impact: float, _dir: Vector3, goat: Node3D) -> void:
	if goat == null:
		return
	var k := clampf(impact / Config.STUMBLE_IMPACT, 0.2, 1.0)
	_burst(goat.global_position, Color(0.45, 0.44, 0.42), int(ceil(Config.FX_BONK_PARTICLES * k)), 3.0 + 2.0 * k)
	_bonk_bursts += 1


func _on_gate_passed(idx: int, _split: float, racer: String) -> void:
	# Player gates only (same guard as the chime, plan D8).
	if racer != "YOU" or _course == null:
		return
	var pts: PackedVector3Array = _course.get("gate_points")
	if idx < 0 or idx >= pts.size():
		return
	_burst(pts[idx], Color(1.0, 0.82, 0.35), Config.FX_GATE_PARTICLES, 4.0)
	_gate_bursts += 1


func _on_trick_scored(name: String, _points: int, goat: Node3D) -> void:
	# Coins sparkle where they were eaten; other tricks are audio-only.
	if name != "coin" or goat == null:
		return
	_burst(goat.global_position + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.85, 0.30), Config.FX_COIN_PARTICLES, 2.5)
	_coin_bursts += 1


## One radial burst of billboarded, fading particles. The emitter is a
## short-lived scene node freed by a SceneTreeTimer — deterministic in
## headless (GPUParticles' own `finished` signal needs a renderer, D10).
func _burst(pos: Vector3, color: Color, count: int, velocity: float) -> void:
	if count <= 0:
		return
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = count
	p.lifetime = 0.7
	p.emitting = true

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 65.0
	mat.gravity = Vector3(0.0, -7.0, 0.0)
	mat.initial_velocity_min = velocity * 0.4
	mat.initial_velocity_max = velocity
	mat.damping_min = 1.5
	mat.damping_max = 3.0
	mat.scale_min = 0.5
	mat.scale_max = 1.4
	var ramp := GradientTexture1D.new()
	var g := Gradient.new()
	g.set_color(0, Color(color.r, color.g, color.b, 0.95))
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	g.add_point(0.35, Color(color.r, color.g, color.b, 0.85))
	ramp.gradient = g
	mat.color_ramp = ramp
	p.process_material = mat

	p.draw_pass_1 = _quad(color, 0.22)

	add_child(p)
	p.global_position = pos
	_active += 1
	get_tree().create_timer(Config.FX_LIFETIME).timeout.connect(
		func() -> void:
			if is_instance_valid(p):
				p.queue_free()
			_active -= 1
	)


## Shared billboard quad for every effect (one material per burst — bursts
## are rare, pooling would be premature).
func _quad(_color: Color, edge: float) -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(edge, edge)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh.material = mat
	return mesh


# --- weather & streaks (plan Step 7–8) ------------------------------------------


func _setup_weather() -> void:
	var p := get_tree().root.get_node_or_null("Progression")
	if p == null:
		p = get_node_or_null("/root/Progression")
	if p != null:
		_mountain_id = String(p.get("current_mountain"))
	if _mountain_id == "":
		_mountain_id = "alpine_valley"
	var preset: Dictionary = Catalog.get_mountain(_mountain_id)
	_snow_line = float(preset.get("snow_line", 170.0))
	_snow_max = int(Config.WEATHER_SNOW_COUNT.get(_mountain_id, 0))
	_dust_max = int(Config.WEATHER_DUST_COUNT.get(_mountain_id, 0))

	if _snow_max > 0:
		_snow = _weather_emitter(
			_snow_max, Color(0.95, 0.97, 1.0), Vector3(9.0, 0.5, 9.0),
			Vector3(0.0, -2.6, 0.0), 8.0, 5.0, 0.09
		)
		_snow.amount_ratio = 0.0
		add_child(_snow)
	if _dust_max > 0:
		_dust = _weather_emitter(
			_dust_max, Color(0.72, 0.60, 0.45), Vector3(10.0, 3.0, 10.0),
			Vector3(0.6, 0.0, 0.3), 25.0, 4.5, 0.06
		)
		add_child(_dust)


func _weather_emitter(
	count: int, color: Color, box: Vector3, vel: Vector3, spread: float, life: float, edge: float
) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = count
	p.lifetime = life
	p.emitting = true

	var mat := ParticleProcessMaterial.new()
	mat.direction = vel.normalized()
	mat.spread = spread
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = vel.length() * 0.8
	mat.initial_velocity_max = vel.length() * 1.2
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = box
	var ramp := GradientTexture1D.new()
	var g := Gradient.new()
	var c := Color(color.r, color.g, color.b, 0.0)
	g.set_color(0, c)
	g.set_color(1, c)
	g.add_point(0.1, Color(color.r, color.g, color.b, 0.75))
	g.add_point(0.9, Color(color.r, color.g, color.b, 0.75))
	ramp.gradient = g
	mat.color_ramp = ramp
	p.process_material = mat
	p.draw_pass_1 = _quad(color, edge)
	return p


func _setup_streaks() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return  # harness level without a live camera — streaks simply absent
	var p := GPUParticles3D.new()
	p.amount = Config.STREAK_MAX_PARTICLES
	p.lifetime = 0.22
	p.amount_ratio = 0.0
	p.emitting = true

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 0.0, -1.0)
	mat.spread = 18.0
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = 11.0
	mat.initial_velocity_max = 16.0
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(1.6, 1.1, 0.4)
	mat.scale_min = 0.7
	mat.scale_max = 1.3
	p.process_material = mat

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.03, 0.34)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 1.0, 1.0, 0.4)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh.material = m
	p.draw_pass_1 = mesh

	cam.add_child(p)
	p.position = Vector3(0.0, 0.0, -1.5)
	_streak = p


## Pure hysteresis gate (smoke-testable both directions).
## Snow starts a band ABOVE the line, stops a band below it.
static func snow_gate(on: bool, alt: float, snow_line: float) -> bool:
	if on:
		return alt > snow_line - Config.WEATHER_SNOW_BAND
	return alt > snow_line + Config.WEATHER_SNOW_BAND


## F3 overlay / smoke battery surface.
func get_debug_state() -> Dictionary:
	return {
		"mountain": _mountain_id,
		"land_bursts": _land_bursts,
		"bonk_bursts": _bonk_bursts,
		"gate_bursts": _gate_bursts,
		"coin_bursts": _coin_bursts,
		"active": _active,
		"snow_on": _snow_on,
		"snow_amt": _snow_amt,
		"snow_max": _snow_max,
		"dust_max": _dust_max,
		"streak_amt": _streak_amt,
	}
