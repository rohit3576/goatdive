# ✅ Phase 8 — Mountain Gameplay: Completion Report

> Companion to `phase-8-mountain-gameplay.md` (execution plan). Records
> what was actually built, verification evidence, bugs found, and
> deviations. Phase 8 is **complete pending the user-side `F5` mountain
> pass** at the bottom — the gate question: *does the mountain argue
> back, or just get in the way?*

---

## Summary

| Step | Planned | Outcome |
|---|---|---|
| 1 | Corridor colliders | ✅ `obstacles.gd` — 21 corridor colliders (2 pines, 17 rocks) of 595 records in ~5 ms, D10 zones clean, **first real obstacle impact in GoatDive history** (smoke-proven bonk + attribution) |
| 2 | Brain avoidance | ✅ record-based cone probe, √-weighted steer-away, segment-aware for logs — **differential A/B proof** (probe displaces a launched goat ≥0.8 m away from a line-blocker, 0 hits); gauntlet pace drift 0.5% |
| 3 | Fallen logs | ✅ 2 tilt-resting logs on groundable straights, records carry `axis`+`half_len`; **no-jump bonks, jump clears clean** (both smoke-proven on the planar-approach log) |
| 4 | Danger chords | ⚪ **honest none** — best bend ratio 0.80 vs 0.70 needed; the machinery is live-proven (at 0.85 it found the bend and certified it steeper 25.5°→28.1°) but this seed's walk doesn't meander. Shipped at 0.7. |
| 5 | Telemetry | ✅ per-racer obstacle-hit counters, `goat_hit_obstacle` signal (group-attributed), F3 player `hits` + AI `av` lines, gauntlet tuning table |
| 6 | Verification | ✅ smoke 19/19 · gauntlet 6/6 (all finish, 0 obstacle hits, tp ≤ 8, drift 0.5%) · Phase 2–7 regression: 6/10 green + 3 behaviors tick-proven but idle-flaky (engine quirk, below) · import + boot clean |

**The gauntlet table (avoidance on):** YOU 0 hits · CAUTIOUS 0 ·
BOLD 0 · RECKLESS 0 — all finish 35–37 s, 4 teleports (normal rescue
cadence). Baseline (avoidance off): also 0 — see the honest findings.

---

## Decisions locked

All ten plan decisions held. Refinements discovered during the build:

| # | Decision | Value |
|---|---|---|
| D1 | Corridor-only | ✓ 45 m radius, cap 220 (19 veg + 2 logs placed — the race line follows the rocky fall line; density datum recorded) |
| D2 | Collider honesty | ✓ **trunk-fit pines (r=0.3)** — the plan's "0.5×scale" number was canopy-sized; the goat is 1.0 m tall, canopies start at 1.6 m: a fat cylinder there is an invisible wall. D2's spirit ("shrink, don't grow") beat the plan's first-guess number. |
| D3 | Fallen logs | ✓ 4.6 m × r 0.4, perpendicular, tilt-resting on a 5-sample max-height; jumpable by geometry (1.03 m apex over 0.8 m top) and placement (no uphill approaches, no convex launch ramps) |
| D4 | Danger chords | ✓ machinery shipped, honest-none on this seed (best ratio 0.80; forcing a fake shortcut is worse than none) |
| D5 | Dynamic hazards | ✓ out, as planned |
| D6 | Terrain untouched | ✓ zero terrain edits |
| D7 | Consequence pipeline | ✓ zero new impact code — plus **BONK_COOLDOWN 0.35 s** (a pinned goat re-bonked at ~10 Hz = trauma jackhammer; one crash is ONE crash) |
| D8 | Herd grades the mountain | ✓ the gauntlet A/B is the tuning loop; **corridor-hit attribution via collider group** (`goat_hit_obstacle`), not position-filtering — start-line goat-goat bumps (77 of CAUTIOUS's "hits") never pollute the report card |
| D9 | One body many shapes | ✓ single `CorridorBody`, 21 shapes, ~5 ms build in the load ledger |
| D10 | Fairness | ✓ smoke-asserted: zero colliders in gate slabs / braking strips / spawn disc; logs jumpable-by-geometry; markers visual-only |

---

## Files created / changed

```text
scripts/terrain/obstacles.gd         # NEW — corridor colliders, logs,
                                     #       records (get_obstacles), ledger
scripts/race/course_builder.gd       # corridor_dist() shared helper;
                                     #       danger-chord detection + flags
scripts/race/ai_goat.gd              # avoidance probe (cone, √ weight,
                                     #       segment-aware for logs), F3 av
scripts/player/goat_controller.gd    # bonk attribution (collider group),
                                     #       bonk cooldown; signal args
scripts/game/event_bus.gd            # goat_* signals carry the emitter;
                                     #       + goat_hit_obstacle
scripts/player/camera_fx.gd          # per-goat filtering (Phase 7 fix)
scripts/race/race_manager.gd         # per-racer hits; player-only crashes
scripts/utils/debug_overlay.gd       # F3: player hits, AI av
scripts/game/config.gd               # OBSTACLE_* / CHORD_* / AI_AVOID_* /
                                     #       BONK_COOLDOWN; VERSION 0.8.0
scenes/terrain/mountain_level.tscn   # Obstacles node (after Course)
```

---

## Bugs found & fixed (the honest log)

1. **Phase 7 cross-talk (pre-existing, latent):** `goat_jumped/landed/bonked`
   were unattributed globals — the player camera popped trauma and the
   manager counted crashes on ANY goat's events since the herd landed.
   All goat signals now carry their emitter; camera FX filters per goat.
2. **Crash-counter attribution:** `_crashes` counted any racer's tumble as
   a player crash. Now player-only; `hits` is a separate per-racer count.
3. **Start-line jackhammer:** the spawn-grid pile-up produced 77 goat-goat
   bonk events on CAUTIOUS in one race. Root-caused via 10 m-grid bonk
   maps; fixed by attribution (those aren't mountain difficulty) and the
   bonk cooldown (10 Hz → 1 event). **The pile-up itself is the owner's
   open Phase 7 F5 item (bump fairness) — unchanged by design.**
4. **Log under-pass ×3:** a horizontal log placed at max-end height floats
   over its downhill half; at chord-midpoint it floats over convex
   side-domes. Final rule: rest on the **max of 5 height samples** along
   the log, tilt to follow the end heights — underside always hugs the
   line. Smoke-caught by a goat literally walking through a "solid" log.
5. **Convex launches:** a teleported goat with horizontal velocity cannot
   catch a >3° slope (gravity needs 0.4 s to build 4 m/s of vy) — it
   flies the approach over convex rollovers. Fixed in *placement* (no
   uphill approaches, no crest within 2 m, no mid-chord bulge) and in
   *testing* (settle-then-launch, slope-aligned velocity).
6. **Avoidance sign:** first implementation steered TOWARD threats
   (Vector2 cross-product sign). Caught by review before measurement;
   the differential A/B test now guards it permanently.
7. **Auto-renamed siblings:** two children both named "Log" become
   "Log"/"@MeshInstance3D@72" in 4.7 — logs are named `Log0/Log1`;
   smoke matches by prefix.
8. **Poll-after-wait:** a poll returning true advances the step machine
   the same frame — post-action waits must live inside the poll
   (the jump test raced its own assert twice before this was pinned).

---

## The --script physics saga (engine lesson, recorded for every future phase)

The regression harness hit a wall: single mid-wait reads showed a frozen
world (buffers undecayed, speeds 0) while instrumented ticks proved the
simulation running (jump fired, downhill 6→10.5 m/s). Bisected to
absurdity — including one print statement whose argument list was the
sole difference between "physics alive" and "physics dead" — before the
truth: **in `--script` mode, wall-clock time and physics time diverge
chaotically and run-to-run. Idle-side reads starve during physics
catch-up storms; the engine's scheduling is load-dependent.**

Working rules (updated handoff):

- **Physics events are proven from the TICK side** (instrument the
  controller, print from `_physics_process`) or via signals — never
  trust a single idle-side read after a wall-clock wait.
- **Poll per-frame with generous wall deadlines** — races (the gauntlet
  pattern) always complete; short single-sample assertions lie.
- **Static writes (`Config.CAM_FX`) need a runtime-compiled helper**
  (`GDScript.new()` + `source_code` + `reload()` — instance `.set()` on
  statics fails silently). Now understood WHY the Phase 4 lesson existed.
- Entry scripts: **zero project-class references at parse** (class-type
  references drag game scripts into a compile pass that runs before
  autoload identifiers exist, poisoning them for the whole run);
  **mount in `_process`, never `_initialize`**.

The three regression behaviors (downhill acceleration, tumble arc, kill
switch) are **tick-proven correct** and idle-flaky headless; the owner's
F5 is their real gate (a windowed engine never starves like this).

---

## Honest findings (the data, not the vibes)

- **The corridor is thin:** 19 vegetation colliders over 512 m — the
  race line follows the rocky fall line where pines don't grow. The
  herd's baseline obstacle-hits were already ~0: lookahead steering
  threads the sparse field. Corridor radius / vegetation caps are the
  density dials if F5 wants more arguments.
- **The herd flies the middle course:** at racing speed the AI spends
  much of the steep middle airborne over convex terrain — knee-high
  logs are cleared by flight. Logs engage *grounded* play (post-gate
  braking, climbs, the player's actual lines). If F5 wants logs to
  argue with the speeding herd, the levers are: taller fallen-TREE
  variants (r 0.55 — breaks the 1.03 m jump contract from flat, needs
  downhill-jump design) or placement on grounded racing sections.
- **Chords: the seed decides.** The detection, terrain qualification,
  and flag markers are live-proven; this mountain honestly has no
  ≥80 m bend under 0.7 ratio. Phase 10's multiple mountains will meet
  meanderier seeds.

---

## User-side F5 gate (the real questions)

- [ ] Pines and rocks read as SOLID from 20 m at speed — no invisible
      walls (trunk-fit colliders: you stop AT the tree, not before it),
      no ghost passes
- [ ] First full-speed pine hit: bonk → tumble arc → recovery reads fair
- [ ] Logs: you jump them by choice and feel good; you can avoid them
      without rage; do they MATTER at racing speed, or only when
      grounded? (the herd-flight finding above)
- [ ] Start-line pile-up: does the bump scrum read as racing or as
      pinball? (carried Phase 7 question — now with 0.35 s bonk
      cooldown damping the camera side)
- [ ] Chords: none this seed — flag machinery idle. Skip or admire the
      honesty.
- [ ] A 10-run session: the mountain as opponent, or the obstacles as
      furniture?
- [ ] 60 FPS feel unchanged (F3 + eyeball; collider build adds ~5 ms
      load-time, zero per-frame cost)
- [ ] **Gate question: does the mountain argue back — or just get in
      the way?**

---

## Handoff → Phase 9

Ready for tricks & scoring, as planned:

- **Obstacle records** (`get_obstacles()`): near-miss = distance query
  during the run; log-jump trick = `grounded → airborne over a log
  record → grounded, no bonk`
- **Signal vocabulary** now fully attributed (`goat_jumped(who)`,
  `goat_landed(impact, who)`, `goat_bonked(impact, dir, who)`,
  `goat_hit_obstacle(impact, who)`) — tricks are listeners
- **Chord records** ship (`chords` array on CourseBuilder) — chord
  completion is scoreable the moment a meanderier seed exists
- **The gauntlet** (deleted with the smokes, pattern in this doc +
  git-less) is the Phase 9 trick-verification harness: force air over a
  log, assert the trick fired
- Carried: bump-fairness verdict; log-vs-flight density decision;
  progress-by-gates refactor (natural Phase 9 sidequest); real goat
  model; reffimg/ still untracked

## Commit (owner)

```text
feat: phase 8 mountain gameplay — corridor colliders, AI avoidance,
fallen logs, chord machinery, difficulty telemetry

scripts/terrain/obstacles.gd (new)   scripts/race/course_builder.gd
scripts/race/ai_goat.gd              scripts/player/goat_controller.gd
scripts/game/event_bus.gd            scripts/player/camera_fx.gd
scripts/race/race_manager.gd         scripts/utils/debug_overlay.gd
scripts/game/config.gd               scenes/terrain/mountain_level.tscn
docs/plans/phase-8-completion.md
```
