# ✅ Phase 7 — AI Goats: Completion Report

> Companion to `phase-7-ai-goats.md` (execution plan). Records what was
> actually built, verification evidence, bugs found, and deviations.
> Phase 7 is **complete pending the user-side `F5` herd pass** at the
> bottom — the gate question: *herd, or ghosts?*

---

## Summary

| Step | Planned | Outcome |
|---|---|---|
| 1 | Autopilot hook | ✅ `set_autopilot` + `set_ai_steering` — the input read branches, physics untouched, regression green |
| 2 | AI brain | ✅ waypoint lookahead (advance-only), body-yaw steering (mouse-equivalent), speed-cap lift-off, ledge-probe jumps, dual rescue nets |
| 3 | Multi-racer | ✅ spawn grid, `begin(racers)`, per-racer gates/records/respawn/finish times, one clock until all finish |
| 4 | Visuals + standings | ✅ body tints, live `POS x/4`, finish-order panel that fills as AI cross |
| 5 | F3 | ✅ per-AI lines (gate · stuck · teleports) |
| 6 | Verification | ✅ **29/29 headless checks PASS** — the grand prix: all four finish, honest order, regression green |

**The headline race (headless, hands-off):** RECKLESS 0:32.25 · YOU 0:35.53
(autopilot) · CAUTIOUS 0:37.28 · BOLD (KILL_Y survivor, finished 4th) —
positions live-swapped 1–4 throughout.

---

## Decisions locked

All ten plan decisions held. Refinements discovered during the build:

| # | Decision | Value |
|---|---|---|
| D1 | Goat-goat collision ON | ✓ no fallback needed — 4-body spawn settled clean, standings churn proves physical racing |
| D2 | Autopilot in controller | ✓ 6 added lines; the regression suite is byte-identical to Phase 6's |
| D3 | Polyline lookahead | ✓ + **the brain owns body yaw** (the player's mouse yaws the goat BODY via head_camera — an AI without yaw ownership can't turn) |
| D4 | Skill = speed cap + lookahead + ledge eagerness | ✓ all Config consts |
| D5 | Ledge probe | ✓ one height pair 5 m ahead |
| D6 | Stuck nets | ✓ **two triggers**: speed-stall (4 s < 1 m/s) AND **gate-stall (12 s without a gate pass)** — the second is new, see bug 2 |
| D7 | Spawn grid | ✓ pulled closer to the spawn center than planned — see bug 7 |
| D8 | Tints | ✓ sage / rust / charcoal-red, one material per goat |
| D9 | Multi-racer manager | ✓ wiring as hoped; `_record_for` per body, standings sort shared with positions |
| D10 | Perf | ✓ brains are arithmetic; one ground probe + one ledge probe per tick |

---

## Files created / changed

```text
scripts/race/ai_goat.gd             # NEW — the brain (lookahead, yaw,
                                    #       speed cap, ledge jumps, rescues)
scripts/player/goat_controller.gd   # EDIT — autopilot fields + setter,
                                    #       input/jump branch, "ai" in debug
scripts/race/race_manager.gd        # REWRITE — per-racer records/gates/
                                    #       respawn/finish, standings, clock
scripts/race/checkpoint.gd          # EDIT — trigger = crossing SLAB,
                                    #       set_armed split from set_state,
                                    #       disarmed at birth
scripts/race/race_hud.gd            # EDIT — standings rows (refresh 0.5 s)
scripts/utils/debug_overlay.gd      # EDIT — per-AI F3 lines
scripts/game/event_bus.gd           # EDIT — checkpoint_passed gains racer
scripts/player/camera_fx.gd         # EDIT — FOV pop filters to the player
scripts/game/config.gd              # EDIT — v0.7.0-phase7; AI_* group
scenes/terrain/mountain_level.gd    # EDIT — herd spawn, rig strip, tints
```

Deleted after use: `phase7_smoke.gd`, `probe_b..i.gd` (temp pattern).

---

## Verification evidence

```text
$ godot --headless --path . --import / --quit-after 400   → 0 errors
COURSE: 7 gates, descent 249→38 m, length 512 m in ~2 ms

$ godot --headless --path . --script .../phase7_smoke.gd
  ok  setup: 4 brains · 4 racers · 7 gates · countdown locks all
  ok  GO: racing · race_started · player unlocked
  ok  GRAND PRIX: all four finished (BOLD after forced KILL_Y respawn,
      RECKLESS after forced stuck-spam) · race_finished exactly once ·
      player 7/7 gates · standings strictly ordered · positions live 1–4 ·
      rescues: 4 total (gate-stall doing its job)
  ok  regression: settle · jump · downhill 12.7 m/s · forced TUMBLE →
      GROUND · CAM_FX kill switch · terrain API
PHASE7-SMOKE: PASS (29 ok, 0 fail)  → exit 0
```

---

## Bugs found & fixed (the honest log)

1. **Gate triggers were a needle's eye** (THE find of the phase): the
   Phase 6 box was 3 m deep × 14 m wide. Four goats ran the ENTIRE course
   in probes (distance-to-finish → 0) with **0/7 gate passes** — one goat
   touched one box in 120 s. Miss one gate, and order enforcement locks
   the race forever. Fix: triggers became racing-style **crossing slabs**
   — 25 m deep, +14 m side margin, visuals unchanged (posts stay 10 m).
   Lesson: a checkpoint is a plane you cross, not a doorway you enter.
2. **The skip-gate deadlock** — even with slabs, a goat that cuts a
   corner wide rejoins the course PAST its current gate; the brain steers
   only forward, so it can never go back through the gate behind it, and
   the speed-based stuck net never fires (the goat is happily fast).
   Fix: the **gate-stall rescue** — no gate progress for 12 s → teleport
   to 6 m before the current gate. This is D6's second trigger.
3. **Brain type-inference cascade** — `var gate_now := mgr.gate_progress_
   for(...)` (Variant return) failed to parse → the brain script died →
   `mountain_level.gd` (which preloads it) died → no spawn, no race, and
   a standing cascade of five downstream failures. One explicit type
   annotation fixed eleven errors. Rule: duck-called game methods always
   get explicit types.
4. **The mouse steers the herd** — `head_camera.gd` yaws the goat BODY on
   mouse motion; every AI goat carries one, so the player's mouse would
   have yawed all four goats. Fix: AI rigs are stripped at spawn —
   overlay freed, head input off, camera not current, CameraFx idle.
5. **Vector2 `.z` slip** — `atan2(-dir.x, -dir.z)` on a Vector2(x, z);
   parse error. The XZ Vector2's world-Z lives in `.y`.
6. **Empty-record vs null** — `_record_for` returns `{}` for non-racers;
   the caller checked `== null` (an empty dict passes) → would crash on
   `rec["node"]`. Fix: `is_empty()`.
7. **AI slid during the countdown** — spawn slots 4–8 m out sit where the
   spawn-disc blend is ~13% noise: local >42° bumps exist OUTSIDE the
   pure-cone center. Grid pulled to 3–6 m. (Player at the exact center
   never slid — that's why only AI crept.)
8. **Gates monitored from birth** — Area3D.monitoring defaults true; the
   "armed at GO" design was fictional until `_build_trigger` set it false
   at birth. Terrain-body enter events during countdown were harmlessly
   rejected, but arming now means arming.
9. **Smoke harness: inverted step waits AGAIN** — the Phase 6 lesson
   (waits live on ACTION steps) was documented and then re-violated in
   the P7 regression tail: settle ran at +0.0 s (goat mid-air, grounded
   false), jump pressed during countdown, speed checked at press-time.
   Now a hard rule: action step carries the wait; checks carry zero.
10. **Probe frame-math kept lying** — headless fps varies 100–200 between
    runs; "frame N ≈ N/60 s" produced two false diagnoses before every
    probe moved to `Time.get_ticks_msec()` wall clock. Frame counts are
    banned from timing assertions.

---

## Deviations from plan

1. **Gate trigger geometry** (bug 1) — 25×24 m slabs vs the plan's thin
   ordered boxes. Visual gates unchanged; capture volume is now honest
   about what a checkpoint means at racing speed.
2. **Gate-stall rescue** (bug 2) — plan D6 had one net; shipped two.
   Tunable: `AI_GATE_STALL`.
3. **Rescue teleports are visible** — 4 fired in the grand prix (160 s,
   four goats). The slab fix made them rare; the stall window makes them
   guaranteed-finite. If F5 reads them as warping: raise `AI_GATE_STALL`,
   widen slabs, or improve corner-cutting lines in Phase 8.
4. **Grid slots tighter** than the plan's D7 (3–6 m vs 4–8 m offsets) —
   bug 7.
5. **Player FOV pop filters by racer name** ("YOU") — the signal now
   carries the racer; camera responds only to the player's gates.

---

## Open items (user side — the real gate)

* [ ] The start reads as a herd: tints + stagger + everyone locked then
      released together
* [ ] AI lines look intentional — carving, not vibrating; nobody warps
      noticeably (if they do: `AI_GATE_STALL` up, slab width up)
* [ ] Bumping is physical but fair — no pinball, no cliff-punting
      (fallback is one layer line if F5 says no)
* [ ] AI jump the same ledges you would
* [ ] `POS x/4` is alive and you check it mid-race
* [ ] Default skills: beat CAUTIOUS/BOLD on a clean run; RECKLESS is a
      coin flip (it won the headless GP at 0:32)
* [ ] 60 FPS feel with four goats on screen (F3 + eyeball)
* [ ] **Gate question: herd, or ghosts?**

---

## Handoff → Phase 8

Phase 8 target (per `README.md`): *Mountain Gameplay* — real obstacles,
terrain challenges, safe-vs-danger routes.

Already in place for it:

* **Vegetation placement records → colliders**: add shapes at recorded
  pine/rock positions; the course already routes around pines, so the
  race line stays fair
* **The rescue telemetry is course QA**: F3's `tp` counters and the
  gate-stall window mark exactly where the mountain got unfair — the
  obstacle-difficulty map writes itself
* **AI goats are crash-test dummies**: run the herd through a candidate
  obstacle field headless and count rescues
* **Goat-goat collision shipped ON** (D1, no fallback) — Phase 8's
  knockback work builds on real bumping
* Course geometry: gates are polyline vertices — a second, dangerous
  route can branch at any gate and rejoin at another without touching
  the race system
* Known gaps to carry: real goat model / skeletal ragdoll; water
  visual-only; AI "later list" (personalities, shortcuts, mistakes)
  deliberately deferred; finish-altitude tuning
