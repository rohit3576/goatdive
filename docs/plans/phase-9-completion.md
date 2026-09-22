# ✅ Phase 9 — Tricks & Scoring System: Completion Report

> Companion to `phase-9-tricks-and-scoring.md` (execution plan). Records
> what was actually built, verification evidence, bugs found, engine
> physics findings, and gauntlet telemetry.

---

## Summary

| Step | Planned | Outcome |
|---|---|---|
| 1 | Air Windows & Foundation | ✅ `scripts/player/trick_detector.gd` — air window lifecycle (`goat_jumped` → `goat_landed`), physics stats (`airtime`, `distance`, `drop`, `rise`, `spin_deg`, `max_speed`), bonk/slam voiding (`impact > Config.STUMBLE_IMPACT`). Smoke verified. |
| 2 | Flips & Rotations | ✅ `Q`/`E` front/back flips, body-only quaternion spin (`start_trick_spin`) preserved through always-upright realign, mouse 360 yaw accumulation (≥300°), camera nod pitch (`FLIP_CAM_FRACTION = 0.2`), trick buffering on takeoff. |
| 3 | Auto-Tricks | ✅ Scored upon clean window close: `long_jump` (≥15 m), `cliff_jump` (≥6 m drop), `log_jump` (crossing band proximity to fallen log). Gentle launch geometry verified. |
| 4 | Near Miss | ✅ Proximity probe (1.6 m band, ≥10 m/s speed), **deferred scoring** with 0.7 s hit-retraction window, 800 ms hit lockout, 1.5 s per-obstacle cooldown. Fast pass scores, direct hit cleanly retracts. |
| 5 | Combos, Scoring & HUD | ✅ Multi-trick combo multiplier ($1.0 + 0.5 \times (n-1)$) applied across distinct tricks in a window; `RaceManager` intake + podium bonus (P1 +500, P2 +250, P3 +100); HUD top-bar `✦ score`, floating cascading trick label stack, and results panel breakdown. |
| 6 | Course Coins | ✅ `scripts/race/coins.gd` — 36 coins via single `MultiMeshInstance3D` (polyline snake ±1.5 m lateral jitter + 3-coin jump arcs over logs), D10 gate-zone clean via `CourseBuilder.in_gate_zone`, lazy player lookup, radius pickup paying +50 pts. |
| 7 | Verification & Gauntlet | ✅ Smoke battery: **14 pass / 0 fail** · Gauntlet grand prix: **5 pass / 0 fail** (all 4 goats finish 35.40–36.73 s, spread <4%, 0 obstacle hits, 4 rescues, score fields verified) · Boot check clean (0 errors). |

---

## Gauntlet Results (Tricks & Coins Live)

Phase 9 Gauntlet ran the full 4-goat grand prix with obstacle colliders, 36 coins, and real-time trick detectors live on the mountain:

| Racer | Obstacle Hits | Rescues (TP) | Time | Notes |
|:---|:---:|:---:|:---:|:---|
| **YOU (Player AI)** | 0 | 1 | 35.40 s | Leader / Winner |
| **CAUTIOUS** | 0 | 1 | 36.73 s | +1.33 s |
| **BOLD** | 0 | 1 | 35.78 s | +0.38 s |
| **RECKLESS** | 0 | 1 | 36.50 s | +1.10 s |

* **Total Hits**: `0` (assert: $\le 30$)
* **Total Teleports**: `4` (assert: $\le 8$)
* **Finish Spread**: Leader 35.40 s vs slowest 36.73 s (spread **3.7%**, assert: $\le 35\%$)
* **Score Fields**: `score` and `best_trick` present in race state and correctly populated.

---

## Decisions Locked (Plan vs Reality)

All ten architectural decisions from `phase-9-tricks-and-scoring.md` held firmly:

| # | Decision | Execution Detail |
|---|---|---|
| **D1** | Single Air Window | Liftoff initializes window stats, landing closes and evaluates; window is atomic unit of combo. |
| **D2** | One Flip per Window | Flip animation runs body-quaternion spin over 0.5 s; clean threshold set at $\ge 85\%$ completion. |
| **D3** | Head-Centric Spins | Yaw accumulation captures body rotation; 360 requires $\ge 300^\circ$ clean yaw. |
| **D4** | Bonk / Slam Voids | Any obstacle bonk during flight or landing impact $> 10.0$ (stumble threshold) marks window `voided = true` with 0 trick points awarded. |
| **D5** | Distinct-Trick Combo Multiplier | Tricks within the same window share multiplier $1.0 + 0.5 \times (n-1)$ (e.g. flip + log jump = $(500+250) \times 1.5 = 1125$). |
| **D6** | Standings-Only Herd | Only the player scores tricks and receives position bonus points; AI goats race purely for placement. |
| **D7** | Top Bar + Floating Labels | Top-right HUD shows `✦ [score]`; floating labels slide and fade from center screen without obstructing FOV. |
| **D8** | Zero Camera Trauma on Tricks | Flips induce subtle out-and-back pitch nod (`FLIP_CAM_FRACTION = 0.2`) on camera pivot; zero trauma/shake on successful tricks. |
| **D9** | Proximity Near-Misses | Near-misses check corridor obstacles within 1.6 m; deferred by 0.7 s to ensure approaching goat doesn't slam into obstacle. |
| **D10** | Deterministic MultiMesh Coins | 36 coins generated using course polyline + log arcs; shared `CourseBuilder.in_gate_zone` excludes coins from gate slabs and finish zones. |

---

## Files Created & Modified

```text
scripts/player/trick_detector.gd     # NEW: Window lifecycle, flips, spins, auto-tricks, near-miss, combos
scripts/race/coins.gd                # NEW: MultiMesh coin renderer, spatial records, lazy pickup loop
scripts/player/goat_controller.gd    # start_trick_spin() body quaternion, upright realign preservation
scripts/player/camera_fx.gd          # Trick pitch nod (FLIP_CAM_FRACTION), trick detector binding
scripts/race/race_manager.gd         # Score bookkeeping, trick_scored handler, podium bonuses, race state
scripts/race/race_hud.gd             # ✦ Score counter, floating cascading trick notification labels
scripts/race/course_builder.gd       # in_gate_zone() helper shared between obstacles and coins
scripts/terrain/obstacles.gd         # Refactored _in_d10_zone to delegate to CourseBuilder.in_gate_zone
scripts/game/event_bus.gd            # trick_scored(name, points, goat) signal
scripts/game/config.gd               # TRICK_* tuning parameters, FLIP_CAM_FRACTION, VERSION 0.9.0-phase9
project.godot                        # trick_front (Q) and trick_back (E) input actions
scenes/terrain/mountain_level.tscn   # Coins node added to level hierarchy
scenes/terrain/mountain_level.gd     # Coins initialization pass
scripts/utils/debug_overlay.gd       # F3 overlay trick diagnostics
```

---

## Bugs Found & Resolved During Verification

1. **Static Ready vs Dynamic Goat Spawn (Lazy Player Lookup)**:
   - *Problem*: `Coins._ready()` searched `_level` for player `CharacterBody3D`, but level children are readied before goats spawn in `MountainLevel._ready()`, resulting in `_player == null` and disabled pickups.
   - *Fix*: Made player lookup lazy inside `_physics_process()`. First frame finds the player and binds pickup tracking.

2. **D10 Gate-Zone Logic Duplication**:
   - *Problem*: `obstacles.gd` had inline gate bounding box checks that needed to be mirrored for coin placement.
   - *Fix*: Extracted `CourseBuilder.in_gate_zone()` as a single source of truth for both obstacle colliders and coin snakes.

3. **Log-Jump Launch Trajectory & Slam Avoidance**:
   - *Problem*: Initial test launched goat at 10.5 m/s, flying 19.7 m and dropping 8.7 m; the violent impact triggered D4 stumble voiding as designed.
   - *Fix*: Calibrated test launch to gentle 7.0 m/s — cleared log with 5.2 m drop and clean landing, proving D4 logic works accurately.

4. **Event Pollution in Test Harness**:
   - *Problem*: Smoke test trick listener caught ambient `"coin"` pickup events from teleports occurring during unrelated unit tests, causing grounded input and coin assertions to fail or race.
   - *Fix*: Gated `_watch_coins` in smoke test harness, cleared trick name buffers between test steps, and polled score delta synchronously with collection count.

5. **Physics Starvation & Airborne Bonk Timing**:
   - *Problem*: Under headless `--script` mode, wall-clock sleeps failed to guarantee character grounding before launch, causing occasional grounded collisions after window closure.
   - *Fix*: Replaced wall-clock sleeps with observation-gated settle polls (`grounded && !tumbling && !stumble`) and added an airborne bonk witness.

---

## The Headless `--script` Engine Saga (Hard-Won Lessons)

During Phase 9 verification under Godot 4.7.2 `--headless --script`, several critical engine-level execution characteristics were established:

1. **Idle vs Physics State Decoupling**:
   - Under `--script`, `Input.action_press()` called from idle / process steps can intermittently miss detection in `_physics_process()`.
   - Script variables, exported properties, and metadata (`get_meta`/`set_meta`) cross boundaries reliably, as do Godot signals.
   - **Pattern**: When testing physics-timed triggers (such as mid-air flips or rotational changes), use file-backed helper nodes mounted in the tree that execute within `_physics_process()`.

2. **Dynamic Script Compilation vs File-Backed Resources**:
   - Nodes compiled in-memory via `GDScript.new() + source_code` do not always register engine lifecycle callbacks (`_physics_process`) under `--script`.
   - File-backed scripts (e.g., `smoke_spin_writer.gd`) consistently register and execute engine ticks.

3. **Observation-Gated Settling**:
   - Fixed millisecond pauses (`_wait(700)`) are insufficient across variable host load under headless execution. All teleports and repositioning must poll the character's real physical state (`grounded && !tumbling && state != "STUMBLE"`).

4. **Mouse 360 Verification Channel**:
   - Mouse rotation in GoatDive operates through `InputEventMouseMotion` -> `HeadCamera` -> body yaw rotation.
   - Headless script injection cannot emulate mouse motion delta to child cameras cleanly without display drivers; hence yaw accumulation was smoke-verified via body rotation while full mouse feel is designated for user F5 playtesting.

---

## Next Steps: User F5 Verification

With Phase 9 automated tests passing at 100% green and clean headless boot, the project is ready for the **F5 Playtest Pass**:
- **Flip Feel**: Test `Q` (front flip) and `E` (back flip) off natural crests and ramps.
- **Camera Pitch Nod**: Verify the 0.2 fraction out-and-back camera dip feels responsive without motion sickness.
- **Log Jumps & Near Misses**: Test clearance jumps over fallen logs and skimming past rock boulders at speed.
- **Combo Greed**: String together flip + log jump + near miss before landing cleanly.
- **Coin Lines**: Collect line of coins along the spine and over fallen tree arcs.
