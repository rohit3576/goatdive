# ✅ Phase 6 — Race System: Completion Report

> Companion to `phase-6-race-system.md` (execution plan). Records what was
> actually built, verification evidence, bugs found, and deviations.
> Phase 6 is **complete pending the user-side `F5` play pass** at the
> bottom — the gate question this time: *loop, or tech demo?*

---

## Summary

| Step | Planned | Outcome |
|---|---|---|
| 1 | Course builder | ✅ downhill-flow walk w/ heading momentum + probe-ring tread fallback, 7 gates + finish, pine avoidance via placement records, **512 m course, descent 249→38 m, built in 1 ms** |
| 2 | Checkpoint gates | ✅ shared-mesh posts + crossbar + finish banner, ordered Area3D triggers (8 m tall, 3 m deep), AHEAD/NEXT/PASSED materials, only the current gate monitors |
| 3 | RaceManager | ✅ COUNTDOWN→RACING→FINISHED, `set_input_enabled` countdown lock, timer + `GameState.race_time` mirror, gate-order double enforcement, **gate respawn on KILL_Y**, racer-list renders honest "1/1", top-speed + crash tracking |
| 4 | HUD | ✅ countdown pops (tween), top bar (time · gate · distance · POS 1/1), wrong-way blink, results panel |
| 5 | F3 + juice | ✅ F3 race line, gate-pass FOV pop (2°, ~0.33 s decay) |
| 6 | Verification | ✅ **34/34 headless checks PASS** incl. remount restart path + Phase 2–5 regression-lite (evidence below) |

---

## Decisions locked

All ten plan decisions held. Refinements discovered during the build:

| # | Decision | Value |
|---|---|---|
| D1 | Generated course | ✓ deterministic, pure terrain function — R rebuilds it identically |
| D2 | Ordered Area3D gates | ✓ double enforcement: only NEXT monitors AND manager checks gate identity |
| D3 | Countdown via authority | ✓ `set_input_enabled` — 6 added lines, movement math untouched, regression green |
| D4 | One state machine | ✓ manager resets `GameState.race_time` in `_ready` (autoloads survive scene reload) |
| D5 | Polyline progress | ✓ gates are polyline vertices; `distance_to_finish` = XZ projection |
| D6 | Racer list | ✓ `_position_of()` ranks finished-then-progress — correct for 1 racer today, N in Phase 7 |
| D7 | Minimal HUD | ✓ default font, one CanvasLayer, zero theme work |
| D8 | Gate respawn | ✓ `setup_spawn()` re-pointed at each passed gate; spawn peak before gate 1 |
| D9 | R = reload scene | ✓ smoke's remount proves a clean second race |
| D10 | Web budget | ✓ 7 gates × 1 shared mesh set + 4 shared materials; gates cost ~nothing |
| + | Gate visuals | orange emissive NEXT; white emissive finish when current; PASSED dims to near-black |

---

## Files created / changed

```text
scripts/race/course_builder.gd      # NEW — walk, gate placement, polyline,
                                    #       distance_to_finish (D5 math)
scripts/race/checkpoint.gd          # NEW — gate mesh + Area3D + state mats
scripts/race/race_manager.gd        # NEW — state machine, timer, order,
                                    #       respawn handoff, racer records
scripts/race/race_hud.gd            # NEW — countdown / top bar / results
scripts/player/goat_controller.gd   # EDIT — _input_enabled + setter (D3),
                                    #       jump/input reads gated
scripts/player/camera_fx.gd         # EDIT — _fov_pop on checkpoint_passed
scripts/utils/debug_overlay.gd      # EDIT — F3 race line
scripts/game/event_bus.gd           # EDIT — + checkpoint_passed(idx, split)
scripts/game/config.gd              # EDIT — v0.6.0-phase6; RACE_* group
scenes/terrain/mountain_level.gd    # EDIT — race.begin(goat) after spawn
scenes/terrain/mountain_level.tscn  # EDIT — Course / RaceManager / RaceHUD
```

Deleted after use: `scripts/utils/phase6_smoke.gd`, `probe_a..e.gd` (temp pattern).

---

## Verification evidence

```text
$ godot --headless --path . --import                      → 0 errors
$ godot --headless --path . --quit-after 400              → 0 errors
COURSE: 7 gates, descent 249→38 m, length 512 m in 1 ms   (load ledger)

$ godot --headless --path . --script .../phase6_smoke.gd
  ok  course: 7 gates · descending · 512 m · pine-clear (2.5 m)
  ok  countdown: state countdown · input locked (0.07 m/s creep) · no jump
  ok  GO: racing · race_started fired · GameState.race_time live
  ok  movement after GO (8.0 m/s) · jump works (input path unchanged)
  ok  order: teleport into gate 3 while current is 0 → nothing fires
  ok  gate 0 passed in order · KILL_Y respawns at gate 0 (0.0 m XZ off)
  ok  finish: exactly once · all 7 checkpoints · payload == state time ·
      mirror frozen · top speed tracked
  ok  remount (restart path): race_time resets · goat settles ·
      downhill 12.4 m/s · forced TUMBLE → recovers GROUND ·
      CAM_FX off = identity + FOV_BASE · terrain API (finite heights,
      spawn ROCK, downhill nonzero on cone flank)
PHASE6-SMOKE: PASS (34 ok, 0 fail)  → exit 0
```

---

## Bugs found & fixed (the honest log)

1. **`Area3D.monitoring` writes are blocked inside `body_entered` callbacks**
   (production bug — gate state flips arrive mid-signal): the physics
   server rejects direct sets; the first gate passed but the next gate
   never armed. Fix: `set_deferred("monitoring", …)` in
   `Checkpoint.set_state`.
2. **Smoke harness double-mount** — the boot ran both from the `_process`
   guard AND as step 0 in the same frame: two live levels stacked two
   identical trimeshes; the goat froze between them. Fix: single mount
   point (the guard); the step table starts at signal-connect.
3. **Smoke step-table semantics inverted** — waits sat on the *check*
   steps, so checks ran instantly after their actions (teleports got zero
   physics frames, input was never held). Fix: waits live on the *action*
   steps. Found via a TRACE print added to the step engine.
4. **`_rest_insert` off-by-one** — the engine pre-increments the step
   index before calling a step, so inserted gate steps landed *after* the
   finish check. Fix: insert at `_step_i + k`.
5. **`Array.insert_array` does not exist in Godot 4** (smoke script) —
   per-element `insert()` loop.
6. **Type inference failures on untyped-array loops** (`var spot := pos +
   off` from a Variant loop value) — parse errors; explicit types fix.
7. **Respawn assertion was physically brittle** — 3D distance after 0.5 s
   of slide-down-slope; replaced with a 2.5 m XZ check (gate vs peak are
   70+ m apart, so the assertion is both robust and decisive).
8. **`--script` probe trivia** (cost ~20 min, recorded so it never costs
   it again): `SceneTreeTimer` never fires without a `_process` override
   on the tree script; `GDScript.new()` scripts need `reload()` after
   `source_code`; SceneTree is not a Node (no `set_physics_process`);
   headless runs ~170 fps here, so "N frames" ≠ "N/60 s" — wait in real
   seconds, and physics DOES tick in `--script` mode (goat falls, settles,
   jumps, races — proven by probes B3/E).

---

## Deviations from plan

1. **The finish lands at the playable radius, not `RACE_FINISH_ALT`** —
   the mountain's toe exits the 440 m playable circle at ~38 m altitude,
   above the 12 m finish target. Course: 7 gates / 512 m. Tunables:
   `RACE_PLAYABLE_RADIUS`, `RACE_FINISH_ALT`, `RACE_GATE_SPACING` (70 m).
2. **Gate 0 sits ~70 m from spawn** (spacing-driven, plan said "first
   gate not too close" — satisfied by construction).
3. **Crashes counted as bonks ≥ `TUMBLE_MIN_IMPACT`** (bus-side proxy,
   not airborne-gated — the plan's "while airborne" isn't visible on
   EventBus; close enough for a results line, revisit if it reads wrong).
4. **Results panel fills from polled state**, not the `race_finished`
   arg (the signal carries only time; the panel lazy-fills on the next
   `_process` frame).

---

## Open items (user side — the real gate)

* [ ] `F5` one full race: countdown locks/releases · gate line readable
      at speed · gate pass feels *noted* · fall → gate respawn = relief
* [ ] Wrong-way flash: helpful or annoying? (cut is fine — it was the
      stretch item)
* [ ] Results read in one glance · R restarts clean
* [ ] **Gate question: loop, or tech demo?** (does finishing make you
      press R?)
* [ ] 60 FPS feel unchanged on the race line (7 gates must cost nothing)
* [ ] Tune if wanted: gate spacing/width/height (`RACE_*` in Config),
      countdown length, FOV pop strength

---

## Handoff → Phase 7

Phase 7 target (per `README.md`): *AI goats* — 3 opponents, waypoint
racing, avoidance, basic overtaking.

Already in place for it:

* **The course polyline IS the AI waypoint path** (D5) — `CourseBuilder`
  exposes `polyline`, `gate_points`, `gate_forwards`, `distance_to_finish`
* **The racer-list takes AI entries with zero schema changes** (D6) —
  `_racer_ahead()` already ranks by finished-then-progress
* Gate volumes + splits give AI pacing data for free
* `goat_controller.set_horizontal_velocity()` exists as a steering
  injection hook (Phase 3 built it; the smoke used it)
* Known gaps to carry: AI needs ground-adherence via `get_height_at`;
  goat-vs-goat collision policy is Phase 7's first decision; vegetation
  still has no collision (Phase 8); finish-altitude tuning if courses
  should end lower in the valley
