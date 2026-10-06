extends SceneTree
## tools/perf_probe.gd — Phase 13 durable perf probe (plan D9).
##
## Run:  godot --headless --import          (after adding/removing files)
##       godot --headless --script tools/perf_probe.gd
##
## Measures the plan's hotspots A–G with deterministic structure (fixed
## seeds, fixed call counts, fixed order); timings are wall-clock, so the
## contract is same-machine A/B (before vs after the Phase 13 steps).
## Counters are exact reads of the perf_* probe surfaces in
## race_manager / goat_controller / course_builder.
##
## Sections:
##   S1  terrain build HIGH (grid 192) vs LOW (grid 128) — hotspot G +
##       the Phase 14 web load budget baseline.
##   S2  course build + distance_to_finish micro-bench — hotspot A.
##   S3  synthetic O(N) record scan (the ai_goat/coins/near-miss inner
##       loop shape, N=220) — hotspots D/E/F; after Step 5 the same
##       query runs through the spatial grid and is equality-checked.
##   S4  live scene pump (full mountain level, racing state) — snapshot
##       builds/frame (B), progression lookups (C), live d2f call rate (A).
##
## Output lines are `PROBE | key | value` — diff two runs to see the A/B.
## Exits nonzero only on internal assert failures, never on slow numbers.

const TerrainGen := preload("res://scripts/terrain/terrain_generator.gd")
const CourseBuild := preload("res://scripts/race/course_builder.gd")
const LEVEL := "res://scenes/terrain/mountain_level.tscn"

const ALPINE_SEED := 1337
const GRID_HIGH := 192
const GRID_LOW := 128
const D2F_CALLS := 3000
const SCAN_N := 220
const SCAN_TICKS := 600
const SCAN_RNG_SEED := 20261006
const PUMP_WARMUP_MS := 4500  # cross the 3 s countdown (headless ~180 fps)
const PUMP_MEASURE_MS := 3000

var _fail := 0
var _cfg: Node


func _initialize() -> void:
	_run()


func _run() -> void:
	var t_all := Time.get_ticks_msec()
	_cfg = root.get_node_or_null("Config")
	if _cfg != null:
		print("PROBE | version | %s" % String(_cfg.get("VERSION")))
	else:
		_check(false, "Config autoload mounted")

	await _s1_terrain()
	await _s2_course_d2f()
	await _s3_scan_bench()
	await _s4_live_pump()

	# Drain: let the freed S4 scene's timers/tweens release before teardown
	# (avoids a cosmetic "resources still in use" note at exit).
	await create_timer(0.15).timeout
	await process_frame
	print(
		"PROBE | done | %d ms total (%s)"
		% [Time.get_ticks_msec() - t_all, "PASS" if _fail == 0 else "FAIL"]
	)
	quit(_fail)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fail += 1
		printerr("PROBE | FAIL | %s" % what)


# --- S1: terrain build HIGH vs LOW (hotspot G + load budget) -------------------


func _s1_terrain() -> void:
	for profile in [["high", GRID_HIGH], ["low", GRID_LOW]]:
		var level := Node3D.new()
		root.add_child(level)
		var terrain := TerrainGen.new()
		terrain.name = "Terrain"
		terrain.seed_value = ALPINE_SEED
		terrain.grid = profile[1]
		# _ready (→ _build) is deferred to the next process frame only for
		# nodes added before the first tick; later adds run it synchronously
		# inside add_child. Latch BEFORE the add so both paths are timed.
		var t0 := Time.get_ticks_msec()
		level.add_child(terrain)
		await process_frame
		await process_frame
		var ms := Time.get_ticks_msec() - t0
		var tris: int = int(profile[1]) * int(profile[1]) * 2
		print("PROBE | terrain_%s_build_ms | %d" % [profile[0], ms])
		print("PROBE | terrain_%s_tris | %d" % [profile[0], tris])
		if profile[0] == "high":
			level.name = "BenchLevel"  # kept for S2/S3
		else:
			level.queue_free()
	_check(true, "s1")


# --- S2: course build + distance_to_finish bench (hotspot A) -------------------


var _bench_level: Node3D
var _bench_course: Node


func _s2_course_d2f() -> void:
	_bench_level = root.get_node_or_null("BenchLevel")
	_check(_bench_level != null, "S2 bench level alive")
	if _bench_level == null:
		return
	var course := CourseBuild.new()
	course.name = "Course"
	var t0 := Time.get_ticks_msec()
	_bench_level.add_child(course)
	# Wait for the deferred _ready (terrain walk) to complete.
	for _i in 10:
		await process_frame
		if (course.get("polyline") as PackedVector3Array).size() >= 2:
			break
	print("PROBE | course_build_ms | %d" % [Time.get_ticks_msec() - t0])
	_bench_course = course

	var poly: PackedVector3Array = course.get("polyline")
	var p: int = poly.size()
	print("PROBE | course_vertices | %d" % p)
	_check(p >= 2, "course polyline non-empty (got %d)" % p)
	if p < 2:
		return

	# Deterministic probe positions: stride the polyline, lateral ±6 m.
	var t1 := Time.get_ticks_usec()
	for k in D2F_CALLS:
		var i := (k * 7) % p
		var a: Vector3 = poly[i]
		var b: Vector3 = poly[(i + 1) % p]
		var along := Vector2(b.x - a.x, b.z - a.z).normalized()
		var perp := Vector2(-along.y, along.x) * (sin(float(k) * 0.7) * 6.0)
		var pos := Vector3(a.x + perp.x, a.y, a.z + perp.y)
		course.call("distance_to_finish", pos)
	var us := float(Time.get_ticks_usec() - t1) / float(D2F_CALLS)
	print("PROBE | d2f_us_per_call | %.2f" % us)
	print(
		"PROBE | d2f_segments_per_call | %.1f"
		% (float(course.get("perf_d2f_segments")) / float(course.get("perf_d2f_calls")))
	)
	_check(us > 0.0, "d2f timing sane")


# --- S3: synthetic O(N) record scan (hotspots D/E/F) ----------------------------


func _s3_scan_bench() -> void:
	if _bench_course == null:
		return
	var poly: PackedVector3Array = _bench_course.get("polyline")
	var p: int = poly.size()
	if p < 8:
		return
	var avoid_r := float(_cfg.get("AI_AVOID_R"))

	# Deterministic obstacle field along the line: circles + log segments,
	# the exact record shapes Obstacles produces.
	var rng := RandomNumberGenerator.new()
	rng.seed = SCAN_RNG_SEED
	var records: Array = []
	for k in SCAN_N:
		var v: Vector3 = poly[(k * 3) % p]
		var pos := Vector3(v.x + rng.randf_range(-8.0, 8.0), v.y, v.z + rng.randf_range(-8.0, 8.0))
		if k % 5 == 4:
			var ax := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized()
			records.append({"pos": pos, "r": 0.4, "axis": ax, "half_len": 2.3})
		else:
			records.append({"pos": pos, "r": rng.randf_range(0.3, 0.6)})

	# Brute-force cone scan — the ai_goat._physics_process inner loop shape.
	var probe_dir := Vector2(1.0, 0.0)
	var t0 := Time.get_ticks_usec()
	var found := 0
	for t in SCAN_TICKS:
		var v: Vector3 = poly[(t * 11) % p]
		var pos := Vector2(v.x, v.z)
		var threat_d := INF
		for o in records:
			var rec: Dictionary = o
			var op: Vector3 = rec["pos"]
			var to := Vector2(op.x - pos.x, op.z - pos.y)
			var off := to
			if rec.has("axis"):
				var ax: Vector3 = rec["axis"]
				var s := clampf(-to.dot(Vector2(ax.x, ax.z)), -2.3, 2.3)
				off = to + Vector2(ax.x, ax.z) * s
			var d := off.length() - float(rec["r"]) - 0.35
			if d > avoid_r:
				continue
			if off.normalized().dot(probe_dir) < 0.35:
				continue
			if d < threat_d:
				threat_d = d
		if threat_d < INF:
			found += 1
	var brute_us := float(Time.get_ticks_usec() - t0) / float(SCAN_TICKS)
	print("PROBE | scan_bruteforce_us | %.2f" % brute_us)
	print("PROBE | scan_records | %d" % SCAN_N)
	print("PROBE | scan_ticks_with_threat | %d/%d" % [found, SCAN_TICKS])
	_check(brute_us > 0.0, "scan timing sane")

	# After Step 5: same semantic query through the spatial grid, if the
	# class exists (baseline runs simply report "absent").
	if not ResourceLoader.exists("res://scripts/race/spatial_grid.gd"):
		print("PROBE | scan_grid_us | absent")
		return
	var Grid := load("res://scripts/race/spatial_grid.gd")
	var grid = Grid.new()
	for o in records:
		if o.has("axis"):
			var op: Vector3 = o["pos"]
			var ax: Vector3 = o["axis"]
			(grid as Object).call(
				"register_segment",
				Vector2(op.x, op.z),
				Vector2(op.x + ax.x * float(o["half_len"]), op.z + ax.z * float(o["half_len"])),
				float(o["r"]),
				o
			)
		else:
			var op: Vector3 = o["pos"]
			(grid as Object).call("register_disc", Vector2(op.x, op.z), float(o["r"]), o)
	var margin := float(_cfg.get("GRID_QUERY_MARGIN")) if _cfg != null else 2.0
	var t1 := Time.get_ticks_usec()
	var grid_found := 0
	for t in SCAN_TICKS:
		var v: Vector3 = poly[(t * 11) % p]
		var pos := Vector2(v.x, v.z)
		var ids: PackedInt64Array = (grid as Object).call("query_ids", pos, avoid_r + margin)
		var threat_d := INF
		for id in ids:
			var rec: Dictionary = (grid as Object).call("get_record", id)
			var op: Vector3 = rec["pos"]
			var to := Vector2(op.x - pos.x, op.z - pos.y)
			var off := to
			if rec.has("axis"):
				var ax: Vector3 = rec["axis"]
				var s := clampf(-to.dot(Vector2(ax.x, ax.z)), -float(rec["half_len"]), float(rec["half_len"]))
				off = to + Vector2(ax.x, ax.z) * s
			var d := off.length() - float(rec["r"]) - 0.35
			if d > avoid_r:
				continue
			if off.normalized().dot(probe_dir) < 0.35:
				continue
			if d < threat_d:
				threat_d = d
		if threat_d < INF:
			grid_found += 1
	var grid_us := float(Time.get_ticks_usec() - t1) / float(SCAN_TICKS)
	print("PROBE | scan_grid_us | %.2f" % grid_us)
	print("PROBE | scan_grid_speedup | %.1fx" % (brute_us / grid_us))
	_check(found == grid_found, "grid threat parity %d vs %d" % [found, grid_found])
	(grid as Node).free()  # unmounted node — release the script ref cleanly


# --- S4: live scene pump (hotspots A/B/C at rest + racing) ----------------------


func _s4_live_pump() -> void:
	var level = load(LEVEL).instantiate()
	root.add_child(level)
	await create_timer(0.2).timeout

	var mgr: Node = level.get_node_or_null("RaceManager")
	_check(mgr != null, "S4 race manager mounted")
	var course: Node = level.get_node_or_null("Course")
	if mgr == null or course == null:
		return

	# Latch counters AFTER the countdown crossed (racing state, real pollers).
	await create_timer(PUMP_WARMUP_MS / 1000.0).timeout
	var b0: int = mgr.get("perf_snapshot_builds")
	var c0: int = course.get("perf_d2f_calls")
	var s0: int = course.get("perf_d2f_segments")
	var g0 := _sum_lookups(level)

	var frames := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < PUMP_MEASURE_MS:
		await process_frame
		frames += 1

	var builds: int = int(mgr.get("perf_snapshot_builds")) - b0
	var calls: int = int(course.get("perf_d2f_calls")) - c0
	var segs: int = int(course.get("perf_d2f_segments")) - s0
	var lookups: int = _sum_lookups(level) - g0
	var secs := PUMP_MEASURE_MS / 1000.0

	print("PROBE | live_frames | %d" % frames)
	print("PROBE | live_state | %s" % String(mgr.call("get_race_state").get("state")))
	print("PROBE | live_snapshot_builds_per_frame | %.2f" % (float(builds) / float(frames)))
	print("PROBE | live_progression_lookups_total | %d" % lookups)
	print("PROBE | live_progression_lookups_per_sec | %.0f" % (float(lookups) / secs))
	print("PROBE | live_d2f_calls_per_sec | %.0f" % (float(calls) / secs))
	print("PROBE | live_d2f_segments_per_sec | %.0f" % (float(segs) / secs))
	_check(frames > 100, "pump ran (%d frames)" % frames)
	level.queue_free()


func _sum_lookups(level: Node) -> int:
	var total := 0
	for c in level.get_children():
		if c is CharacterBody3D and c.get_script() != null:
			var v = c.get("perf_progression_lookups")
			if v != null:
				total += int(v)
	return total
