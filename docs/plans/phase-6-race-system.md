# 🏁 Phase 6 — Race System: Execution Plan

> Expands `README.md` → *Phase 6 — Race System* into concrete, executable
> steps. The mission: **turn a mountain you can run down into a race you can
> win** — countdown, checkpoints, timer, position, finish, restart.
> Carried debts landing here: `downhill_dir` returns ZERO on flat band treads
> (Phase 5 Bug 6 → checkpoint orientation fallback), `Vegetation.get_placements()`
> exists so the course routes *around* pines, `EventBus.race_started` /
> `race_finished` have been waiting since Phase 1, `GameState.race_time`
> exists unused.
>
> ⚠️ **Position caveat:** AI goats are Phase 7. Every position/order surface
> this phase is built on a racer-list API that renders **"1/1"** honestly —
> the data shape arrives now, the opponents arrive later (D6).

---

## Goal

```text
Spawn on the peak (input locked)
        ↓
   3 · 2 · 1 · GO ──── race_started
        ↓
GATE 1  ← ordered Area3D gates down the mountain flow line
        ↓
GATE 2 … ~10 gates (pines routed around, treads handled)
        ↓
FINISH banner ─────── race_finished(final_time)
        ↓
Results panel: time · splits · top speed · tumbles
        ↓
R restarts — scene reloads, course regenerates deterministically
```

**Definition of done:** on `F5` — the loop reads without instruction: countdown
locks then releases you, the next gate is always visibly *the* next gate,
passing it flashes feedback, the timer runs, falling respawns you at your last
gate, the finish banner ends the race with a results readout, and R does the
whole thing again. Headless: course structure asserts + countdown/timer/finish
state machine + full Phase 2–5 regression green, zero errors.

---

## Decisions locked in Phase 6

| # | Decision | Choice | Why |
|---|----------|--------|-----|
| D1 | Course layout | **Generated, not hand-placed** — a downhill-flow walk from the spawn disc to the valley floor produces ~10 ordered gates + a finish banner; seedable, regenerates with the terrain | The terrain API is frozen and proven; no level editor exists; the mountain already *is* the track. Hand-placed gates would break on every future seed. The walk *is* the Phase 7 AI racing line (D5). |
| D2 | Gate pass detection | **Ordered `Area3D` box triggers** — a gate counts only when the goat's body enters the *current* gate's volume; skipped gates do nothing; passed gates go inert | Volumes are robust to jumps, falls, and tumbles where planes/rings fail; ordering keeps the timer and distance honest; zero per-frame polling cost. |
| D3 | Countdown | **3-2-1-GO with input authority 0** — new additive `set_input_enabled(bool)` on `GoatController` (the TUMBLE authority mechanism, generalized); `race_started` fires at GO | Physics keeps simulating (the goat settles on spawn) instead of freezing the tree; movement math untouched — the Phase 5 D7 rule holds. |
| D4 | Race state machine | **One `RaceManager` node: COUNTDOWN → RACING → FINISHED** — sole owner of the timer accumulator; `GameState.race_time` becomes its live mirror | One owner, no scattered `if racing` checks. EventBus stays the cross-module pipe it already is. |
| D5 | Distance & progress | **Course is a polyline; progress = segment index + projected fraction along it**; HUD shows meters-to-finish along the course (and checkpoint i/N) | Cheap vector math, an honest wrong-way signal, and the exact waypoint path an AI goat will follow in Phase 7 — build once, use twice. |
| D6 | Position & finishing order | **Racer-list API day one, renders "1/1"** — RaceManager holds an array of racer records (name, progress, finished, finish_time); the player goat is the only entry until Phase 7 | The data shape costs nothing now; retrofitting multi-racer position logic around existing AI later is a rewrite. "1/1" must be honest, not hidden. |
| D7 | HUD | **Minimal text HUD, one `CanvasLayer`** — big centered countdown, top bar (time · gate i/N · distance · position), results panel on finish. No theming, no art | The loop needs feedback to be testable; the real HUD is Phase 11 — this is scaffolding Phase 11 reskins, not replaces. |
| D8 | Falling mid-race | **Respawn at the LAST PASSED gate** — RaceManager hands the controller a fresh respawn transform as gates pass (`setup_spawn` machinery, new point); free-roam spawn stays the default before gate 1 | Respawn-on-peak after a mid-course fall is rage-quit fuel; `KILL_Y` + `_spawn_transform` already exist — this only moves the point. |
| D9 | Restart | **R stays `reload_current_scene()`** — the course regenerates deterministically from the same seed; race state dies with the scene | Wired since Phase 1. A deterministic rebuild cannot have reset bugs; hand-resetting ten mutable fields can. |
| D10 | Gate visuals & web budget | **Shared low-poly posts + crossbar flag, procedural meshes**; the *next* gate gets a bright unlit material, upcoming gates dim, passed gates dimmer; no lights, no particles, no custom shaders | ~12 gates on one shared mesh set is negligible draw cost; `gl_compatibility`-safe; the "where do I go" answer must cost nothing at 60 FPS. |

**Out of scope (later phases):** AI opponents (7), obstacle gameplay — rocks
stay visual (8), tricks/scoring (9), multiple courses/mountains (10), the
real HUD (11), audio sting on gate pass (12), mobile touch (13/14).

---

## Step 1 — Course builder: the race line down the mountain

**Files:** new `scripts/race/course_builder.gd`, `config.gd` (RACE_* group),
smoke-time structural asserts.

**Do:**

* **Downhill walk:** from the spawn disc edge, step ~8 m iteratively — heading
  = `downhill_dir` blended with the previous heading (momentum, so band-tread
  flats don't stall the walk); if `downhill_dir` is ZERO (flat tread, Phase 5
  Bug 6), sample a ring of offsets and keep the best-descent direction, else
  hold last heading
* **Gates every ~70–90 m of horizontal travel** (tunable `RACE_GATE_SPACING`),
  snapped to `get_height_at`, oriented along the walk direction (NOT
  `downhill_dir` — the carried fallback note)
* **Pine avoidance:** nudge any gate whose center sits within ~4 m of a
  `get_placements("pines")` record (rocks/tufts are passable — they're props)
* **Finish:** where the walk reaches valley/water altitude (~8–15 m) or the
  playable radius — a wider gate + banner
* Output: `Array[Transform3D]` gate transforms + the course polyline (D5's
  math substrate); print gate count + total descent (load ledger habit)
* Config: `RACE_GATE_COUNT_MAX`, `RACE_GATE_SPACING`, `RACE_GATE_AVOID_PINE_R`,
  `RACE_FINISH_ALT`, `COUNTDOWN_SECONDS`

**Done when:** headless — walk never stalls (fixed step count terminates),
gates strictly descend in altitude, no gate inside a pine radius, gate count
≥ 6, spawn-to-finish course length printed; F5 comes in Step 6.

**Commit checkpoint:** `feat: generated race course (downhill walk, pine avoidance)`

⏱ ~90 min

---

## Step 2 — Checkpoint gates: visible, ordered, inert after passing

**Files:** new `scripts/race/checkpoint.gd`, shared gate meshes built in code,
`mountain_level.tscn` (gates parented under a `Course` node).

**Do:**

* Procedural gate mesh: **two posts + crossbar flag** (tapered cylinders +
  prism — the Phase 5 pine/rock mesh lessons), one shared `ArrayMesh`, one
  `MultiMesh`-free simple spawn per gate (~12 instances is nothing)
* `Area3D` trigger box between the posts: tall (goat can jump the gate —
  that's racing) and deep enough to not tunnel at `MAX_DOWNHILL_SPEED`;
  collision **mask = goat body only**, layer that nothing else reads
* Gate states: `AHEAD` (dim) → `NEXT` (bright unlit material) → `PASSED`
  (dimmer, trigger off) → `FINISH` variant (wider + banner quad)
* Signal up to the manager on body entered; the gate never decides order —
  the manager does (D2)

**Done when:** F5 — gates read as a *line* down the mountain (the next one
visibly brighter than the rest); headless — trigger reports the goat body
only, material states cycle AHEAD→NEXT→PASSED correctly.

**Commit checkpoint:** `feat: checkpoint gates (Area3D pass detection, next-gate highlight)`

⏱ ~75 min

---

## Step 3 — RaceManager: the state machine and the clock

**Files:** new `scripts/race/race_manager.gd`, `goat_controller.gd` (+
`set_input_enabled`), `event_bus.gd` (+ `checkpoint_passed`), `game_state.gd`
(`race_time` goes live), `mountain_level.gd` (wire-up), `config.gd`.

**Do:**

* **States:** `COUNTDOWN` (3.0 s, input authority 0) → `RACING` (emit
  `race_started`, authority 1, timer accumulates in `_physics_process`) →
  `FINISHED` (emit `race_finished(final_time)`, authority stays 1 — freeroam
  after the line is fine)
* `set_input_enabled(false)` on the controller: the TUMBLE authority pattern
  as a public setter — additive, movement math untouched
* Gate advancement: on trigger, only if it's the current gate → emit
  `EventBus.checkpoint_passed(idx, split_time)`; update next gate; **hand the
  controller the gate transform as the new respawn point** (D8)
* Progress/distance: project goat xz onto the course polyline →
  meters-to-finish along the course (D5); expose `get_race_state()` for the
  HUD and F3 (the `get_debug_state()` habit)
* Racer records array (D6): the player goat is entry 0; position = rank by
  (finished first, then progress) — renders "1/1" today, scales to AI tomorrow
* Finish payload: total time, splits, top speed (hook `get_debug_state`
  speed max — no new truth), tumble count (hook `goat_bonked` above
  `TUMBLE_MIN_IMPACT` while airborne)

**Done when:** headless — countdown blocks input then releases; timer starts
at GO, stops at finish; teleporting through gates in order advances state;
teleport past KILL_Y respawns at last gate; `race_finished` carries a sane
payload; full movement regression still green (the D3 edit is invisible to
Phase 2–4 behavior).

**Commit checkpoint:** `feat: race manager (countdown, ordered gates, timer, gate respawn)`

⏱ ~90 min

---

## Step 4 — HUD: countdown, clock, progress, results

**Files:** new `scripts/race/race_hud.gd` + `CanvasLayer` in
`mountain_level.tscn`; default Godot font only.

**Do:**

* **Countdown:** centered big "3 · 2 · 1 · GO" with a scale/fade tween per
  tick (Tween node — free juice, no particles)
* **Top bar:** `TIME 0:42.17 · GATE 3/10 · 540 m · POS 1/1` — one `Label`,
  monospace-ish default font, updates from `get_race_state()` in `_process`
* **Gate flash:** next-gate label / small edge flash on `checkpoint_passed`
* **Results panel** on `race_finished`: total time, best split, top speed,
  tumbles, and "R — race again" (the existing key does it — just say so)
* **Wrong-way flash** (stretch, cap 30 min): velocity·gate-direction < 0
  sustained > 2 s → "WRONG WAY" blink. Cut it if it fights back.

**Done when:** F5 — every number on screen is readable at racing speed without
squinting; countdown readable from across the room; results panel blocks
nothing (race over, world alive).

**Commit checkpoint:** `feat: race HUD (countdown, timer, progress, results panel)`

⏱ ~90 min

---

## Step 5 — F3 + juice wiring

**Files:** `debug_overlay.gd` (race line), `camera_fx.gd` (one-liner, maybe).

**Do:**

* F3 gains a race line: `RACE racing · gate 3/10 · 540 m · 41.7s · respawn G2`
  (the established `get_debug_state()` pattern)
* One feedback beat on gate pass: tiny FOV pop (existing `FOV` kick path,
  ~1°) or HUD flash — pick one, not both; gates should feel *noted*, not
  *exploded*

**Done when:** F3 race line matches HUD numbers exactly (one truth, two
readouts); the pass beat doesn't read as a bonk.

**Commit checkpoint:** `feat: F3 race debug line + gate pass feedback`

⏱ ~45 min

---

## Step 6 — Verification: regression + race loop + the eyeball gate

**Headless (temp smoke, deleted after — Phase 4 `--script` lessons: no
autoload identifiers at parse time, fetch via `root.get_node("/root/...")`
at runtime, audit via game-side records):**

* **Course structure:** gate count ≥ 6, strictly descending, no gate in a
  pine radius, spacing within tolerance, finish below `RACE_FINISH_ALT`,
  walk terminates in bounded steps
* **Countdown lock:** authority 0 during COUNTDOWN (input injected → no
  velocity), authority 1 within one tick of GO
* **Gate order:** teleport through gates 1→N (state advances) and teleport
  to gate 3 while current is 1 (nothing happens — order enforced)
* **Timer:** starts at GO, monotonic during RACING, frozen after finish;
  `GameState.race_time` mirrors the manager
* **Gate respawn:** teleport below `KILL_Y` mid-course → respawn at last
  passed gate, not the peak
* **Finish payload:** total ≈ sum of splits; top speed ≥ observed max;
  `race_finished` fires exactly once
* **Full regression:** Phase 2/3/4/5 equivalents — settle / jump / coyote /
  downhill / landing-stumble / camera suite / tumble / kill switch — the
  `set_input_enabled` edit must be invisible

**User-side (the real gate — this is the *game* phase):**

* [ ] Countdown locks you, GO releases you — no movement before, full
      control after
* [ ] The gate line is readable at speed — you always know where to go
      without a minimap
* [ ] Gate pass feels *noted* (not exploded); wrong-way flash helps or is
      gone
* [ ] A deliberate fall mid-course respawns at your last gate — relief, not
      punishment
* [ ] Finish + results read in one glance; R restarts the whole loop clean
* [ ] One full race end-to-end: does crossing the line make you want to
      press R? (**the gate question: loop, or tech demo?**)
* [ ] 60 FPS feel unchanged on the race line (gates cost nothing)

**All boxes → write `phase-6-completion.md`.**

⏱ ~60 min

---

## Effort summary

| Step | | Time |
|---|---|---|
| 1 | Course builder | ~90 min |
| 2 | Checkpoint gates | ~75 min |
| 3 | RaceManager | ~90 min |
| 4 | HUD | ~90 min |
| 5 | F3 + juice | ~45 min |
| 6 | Verification | ~60 min |
| | **Total** | **~7.5 h** |

---

## Risks & notes

* **The walk getting stuck** — a local bowl (warp noise) could trap the
  downhill walk. Defenses: heading momentum + best-of-ring fallback + a hard
  step cap that forces the finish wherever the walk died (a short course
  beats an infinite loop). If courses come out short, widen the ring.
* **Gates on band treads** — flat treads return ZERO downhill (Phase 5
  Bug 6, the carried note). Orientation comes from the walk's segment
  direction, never from `downhill_dir` at the gate point. The smoke asserts
  no two gates share one tread flat *and* spacing.
* **Area3D vs trimesh terrain** — trigger boxes must not brush the terrain
  collision (ghost triggers). Gate boxes: thin, between the posts, mask =
  goat body only. If phantom triggers appear, layer separation fixes it —
  that's what layers are for.
* **Tunneling at speed** — 20 m/s + thin trigger box = possible skip at low
  tick rates. Box depth ≥ `MAX_DOWNHILL_SPEED / physics_ticks` × safety 3;
  physics is 60 Hz, so ~1 m deep minimum. Assert in smoke with a
  full-speed teleport sweep.
* **The `set_input_enabled` edit is the only controller touch** — additive,
  movement math untouched, full regression in Step 6 is the proof. If
  regression fails, the edit backs out and the countdown freezes the scene
  instead (plan B, uglier but zero-risk).
* **HUD text on web** — default Godot font renders fine in
  `gl_compatibility`; no custom font loading this phase (Phase 11's problem).
* **"1/1" must be honest** — with one racer, position displays as 1/1, not
  "1st!". Phase 7 makes it a real number; lying now makes the UI a liar
  forever.
* **Respawn griefing** — gate respawn means a fall near the finish still
  costs time (fair) but never the run (kind). If speedrun-fall exploits
  emerge later (checkpoint skipping via air), Phase 8's collision work is
  where they get fixed.
* **Course quality is F5-verdict, like all generated content** — gate
  spacing/width/height are Config tunables; if the line feels bad, tuning
  comes before code.

---

## Handoff → Phase 7

Phase 7 target (per `README.md`): *AI goats* — 3 opponents, waypoint racing,
downhill movement, avoidance, basic overtaking.

Already in place for it:

* The **course polyline IS the AI waypoint path** (D5) — no second path
  representation will exist
* The **racer records array** (D6) takes AI entries without schema changes —
  position/finishing-order logic arrives pre-built
* Gate volumes already answer "who passed where when" for AI split pacing
* AI needs what the goat has: `TerrainGenerator` queries for ground
  adherence, `get_placements` for avoidance — both frozen
* Known gaps to carry: gates have no AI-side skip rules (air skips);
  difficulty/personalities are Phase 7's own decisions; goat-vs-goat
  collision policy is undecided (that phase's D1, probably)
