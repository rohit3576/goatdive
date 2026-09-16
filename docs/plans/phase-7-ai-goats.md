# 🐐 Phase 7 — AI Goats: Execution Plan

> Expands `README.md` → *Phase 7 — AI Goats* into concrete, executable
> steps. The mission: **put three competitors on the mountain** — the
> race stops being a time trial and becomes a race.
> Carried assets landing here (Phase 6 handoff): the course polyline IS
> the AI waypoint path (D5), the racer-list takes AI entries with zero
> schema changes (D6), gate volumes + splits are free pacing data,
> `set_horizontal_velocity()` exists as a steering injection hook, and
> the terrain API is frozen for ground adherence.
>
> ⚠️ **Scope fence (README "later" list stays out):** route selection,
> shortcuts, personalities, difficulty levels, deliberate AI mistakes.
> Phase 7 ships *credible opponents*, not characters.

---

## Goal

```text
        SPAWN GRID (4 goats, countdown locks all)
                 ↓  GO
   🐐 YOU ──┐
   🐐 CAUTIOUS ├── same mountain, same physics, same gates
   🐐 BOLD   ├── waypoint lookahead + skill multipliers
   🐐 RECKLESS ┘
                 ↓
   live positions · physical bumping · overtaking
                 ↓
   FINISH — full order: 1. BOLD 1:21.4   2. YOU 1:23.9   3. …
                 ↓
   R — race again (deterministic course, fresh race)
```

**Definition of done:** on `F5` — three visibly distinct goats race you
down the mountain: they take real lines, jump real ledges, fall and
recover on the same physics you do, block and bump you at speed, and the
position counter is a live number worth watching. The finish shows the
full order with times. Headless: a 4-goat autopilot race completes with
all racers finishing, sane order, zero errors, and the Phase 2–6
regression stays green.

---

## Decisions locked in Phase 7

| # | Decision | Choice | Why |
|---|----------|--------|-----|
| D1 | Goat-vs-goat collision | **ON** — AI capsules collide with each other and the player (same layer); no special response, `move_and_slide` sliding is the interaction. *Fallback (pre-agreed):* if spawn-grid stacking or high-speed jitter reads badly, layer AI off each other for v1 and Phase 8 makes bumps real | Physical bumping is what makes "basic overtaking" (README) cost something. Cheapest honest version: let the existing capsule physics interact. The fallback is one layer-mask line, so the risk is bounded |
| D2 | AI driver | **Autopilot inside `GoatController`** — `set_ai_steering(wish_dir, want_jump)` feeds the existing input read (the Phase 6 `set_input_enabled` pattern, extended); AI goats are `goat.tscn` instances with a brain node | One physics truth: AI goats get grip, slide, stumble, tumble, coyote — the mountain treats them exactly like the player. Duplicating movement math would create a second physics that drifts |
| D3 | Path following | **Lookahead on the course polyline** — target the point `LOOKAHEAD` m ahead (per-skill: 12–20 m), steer `wish_dir` toward it, recomputed every physics tick; gates are waypoints by construction (Phase 6 D5) | The polyline already exists, already routes around pines, already ends at the finish. Zero new path truth |
| D4 | Speed = skill | **Three skill profiles** (CAUTIOUS 0.85 / BOLD 0.95 / RECKLESS 1.05 speed bias + lookahead + jump eagerness) as Config constants — no rubber-banding, no adaptive difficulty | Fixed multipliers are tunable, testable, and honest. Rubber-banding is a Phase 7.5+ flavor decision once we can feel the baseline |
| D5 | AI jumping | **Ledge lookahead** — height drop over the next `LOOKAHEAD` m exceeds a threshold → `want_jump` (eagerness per skill). No trick jumps | The controller's verified jump/coyote does the rest; jumping is steering, not choreography |
| D6 | Stuck safety net | **Teleport recovery** — speed < 1 m/s for 4 s while RACING → snap to the nearest polyline point ahead (kill velocity, small hop). Guaranteed finishers, no DNF logic in v1 | A race where an AI wedges behind a rock forever is worse than a tiny teleport. Visible rarely, logged in F3 |
| D7 | Roster & spawn | **3 AI goats**, spawn grid on the disc: player front-center, AI staggered ±3–6 m behind/side, all facing gate 0; countdown locks every racer via `begin(racers)` | README says 3 opponents. The grid guarantees a clean start (no D1 spawn overlap) and a view of the herd at GO |
| D8 | Visual distinction | **Body tint per goat** (material override on the placeholder Torso/Snout) + name in HUD/order. No models, no overhead labels v1 | The bodies are placeholder boxes until the real-goat-model phase; distinct color + distinct *behavior* is what reads "competitor" at racing speed. Overhead name labels are a stretch item |
| D9 | RaceManager multi-racer | **`begin(racers: Array)`** — player stays index 0; AI register like-for-like in the existing racer records (finished/time/progress already ranked). Positions go live: `POS 3/4`; the finish panel lists the full order as racers cross | Phase 6 D6 built the schema for exactly this. This step should be wiring, not surgery — if it isn't, D6 failed and gets fixed first |
| D10 | Perf budget (web) | 3 extra controllers + brains ≈ nothing; 3 tinted body meshes; **no** pathfinding nodes, no raycasts per frame beyond one ledge probe | The web ceiling (60 FPS Chrome) is untouched by arithmetic-heavy-but-tiny brains; the ledger habit continues |

**Out of scope (README "later" + future phases):** route selection,
shortcuts, personalities beyond the 3 skill constants, difficulty
settings, deliberate mistakes/crashes, audio (12), real goat models,
goat-vs-vegetation collision (Phase 8), trick scoring (9), mobile.

---

## Step 1 — Autopilot: the AI drives the verified body

**Files:** `goat_controller.gd` (+`set_ai_steering`, `_ai_wish`,
`_ai_jump`, `_autopilot`), `config.gd` (nothing yet — hooks only).

**Do:**

* Autopilot fields + setter — the input read becomes:
  `_ai_wish` when `_autopilot`, else `Input.get_vector` (both still gated
  by `_input_enabled` — the countdown lock composes)
* Jump source: `_ai_jump` (held bool) when autopilot, else the buffered
  `Input.is_action_just_pressed` path — the existing coyote/buffer
  machinery is shared, not duplicated
* `get_debug_state()` gains `ai: bool` (F3 + smoke visibility)
* **Regression gate first:** full movement suite on a player goat with
  autopilot off — the diff must be invisible (Phase 6 D3 discipline)

**Done when:** headless — a goat with `set_ai_steering(Vector2.UP-ish,
false)` held walks forward at the expected carve accel; jump via
`want_jump` fires `goat_jumped`; input-lock + autopilot compose
(countdown freezes AI too); player regression green.

**Commit checkpoint:** `feat: goat autopilot hook (set_ai_steering)`

⏱ ~60 min

---

## Step 2 — The brain: waypoint lookahead, skill, ledges, stuck net

**Files:** new `scripts/race/ai_goat.gd`, `config.gd` (AI_* group).

**Do:**

* `AiGoat extends Node3D` parented to each AI goat instance (or a script
  ON the goat — follow the scene's existing composition style); holds
  the skill profile + race state, runs in `_physics_process`:
  * **Target:** nearest-ahead polyline index (advance-only while RACING),
    then the point `LOOKAHEAD_SKILL` m further; `wish_dir` = global
    direction to it (XZ, normalized)
  * **Speed shaping:** skill bias modulates wish *magnitude* (how hard
    to push into the carve), never raw velocity — physics stays the
    only integrator
  * **Ledge probe:** one height query pair (`get_height_at` at target
    vs. current); drop > `AI_LEDGE_DROP` → `want_jump` (eagerness gates)
  * **Stuck net:** D6 timer → teleport to polyline point, zero velocity
* Skill profiles as Config constants: `AI_SKILL_CAUTIOUS / _BOLD /
  _RECKLESS` (speed bias, lookahead m, jump eagerness)
* `get_debug_state()` habit: `{target_idx, wish, stuck_t, teleports}`
  for F3/smoke

**Done when:** headless — one AI goat in autopilot completes the full
course unaided (teleports ≤ 1, finish time sane), on the real countdown
schedule; it tumbles and recovers at least once across 3 seeded runs
(the mountain polices it for free).

**Commit checkpoint:** `feat: ai_goat brain — waypoint lookahead, ledge jumps, stuck recovery`

⏱ ~90 min

---

## Step 3 — The herd: roster, spawn grid, multi-racer manager

**Files:** `race_manager.gd` (`begin(racers)`), `mountain_level.gd`
(spawn grid + AI instantiation), `goat.tscn` untouched (instantiate),
`config.gd`.

**Do:**

* Spawn grid (D7): player at the Phase 2 spawn; AI at
  `spawn + forward×(-4..-8) + right×(±3)` — staggered, all facing
  gate 0 (`Basis.looking_at`), all `setup_spawn`'d at their grid slot
* `RaceManager.begin(racers)`: player index 0 + 3 AI records
  (`name` from skill profile); countdown `set_input_enabled(false)`
  for ALL racers; progress tracking (D5 projection) for all — the
  per-racer loop replaces the player-only lines
* Position math goes live as a side effect (Phase 6 `_position_of`
  ranks by progress mid-race, time at finish)
* Gate triggers: one Area3D per gate already exists — AI bodies enter
  volumes like the player (manager's identity check extends to "which
  racer's body") — per-racer gate progress, same ordered rule
* Respawn: AI get gate respawn too (their own `setup_spawn` re-point)

**Done when:** headless — 4-goat race (player on autopilot) runs
countdown → gates → finish with a full ordered result, each racer's
splits recorded; no double-fires; manager state machine unchanged.

**Commit checkpoint:** `feat: four-racer field — spawn grid, multi-racer manager, AI gate progress`

⏱ ~90 min

---

## Step 4 — Seeing the herd: tints, names, live standings

**Files:** `ai_goat.gd` or spawn code (tint), `race_hud.gd` (position +
finish order), `config.gd` (colors).

**Do:**

* Per-goat body tint (D8): override material on Torso/Snout —
  CAUTIOUS sage / BOLD rust / RECKLESS charcoal-red; player stays
  default (first-person anyway — only shadows/tumble view show it)
* HUD top bar: `POS 3/4` goes live (already wired through
  `get_race_state` — verify formatting at speed)
* Finish panel: full order list (`1. BOLD 1:21.4` … `4. CAUTIOUS
  1:29.0`), populated as racers cross; player row highlighted
* Stretch (cap 20 min): small colored name labels above AI goats
  (Label3D, distance-faded) — cut if they clutter

**Done when:** F5 — you can tell who's who mid-race without the HUD;
the finish order reads in one glance; headless order matches the
asserted ranking.

**Commit checkpoint:** `feat: herd visuals — tints, live position, finish order`

⏱ ~60 min

---

## Step 5 — F3 + tuning hooks

**Files:** `debug_overlay.gd` (AI lines), `config.gd`.

**Do:**

* F3 gains one line per AI when visible:
  `BOLD  gate 3/7  310m  stuck 0.2  tp 0` (the `get_debug_state` habit)
* Verify every AI number is a Config const or @export — F5 tuning is
  knob-turning, not code edits (the Phase 5 D8 rule, now for behavior)

**Done when:** F3 lines match HUD positions; no AI tunable hides in
script literals.

**Commit checkpoint:** `feat: F3 herd debug lines`

⏱ ~30 min

---

## Step 6 — Verification: the headless grand prix + regression

**Headless (temp smoke, deleted after — Phase 4 `--script` lessons +
Phase 6 additions: wait in real seconds, single mount point, waits on
ACTION steps, engine pre-increments step index):**

* **Autopilot regression:** player goat, autopilot off — settle / jump /
  coyote / downhill / landing / tumble / kill switch (the Phase 2–6
  suite; the D2 edit must be invisible)
* **Solo AI finish:** each skill profile alone completes the course
  (teleports ≤ 1 each)
* **Full grand prix:** 4 racers (player on autopilot), real countdown:
  all finish; order strictly by finish time; splits per racer = gate
  count; no double `race_finished`; position of player mid-race was
  non-constant (assert it changed at least once)
* **Collision co-existence (D1):** goats overlap the start grid without
  physics explosions (spawn settle < 0.3 m jitter); if the jitter
  fallback triggers here, apply it and log the decision
* **Gate respawn for AI:** force one AI below `KILL_Y` mid-course →
  respawns at its last gate, finishes anyway
* **Stuck net:** plant one AI inside a forced-stop (zero velocity spam)
  → teleport fires, race completes

**User-side (the real gate — opponents are a feel question):**

* [ ] The start reads as a herd, not a clone parade (tints + stagger)
* [ ] AI lines look intentional — they carve, they don't vibrate
* [ ] Overtaking feels physical: bumps cost something, neither party
      warps; nobody punts you off a cliff unfairly (if so → D1 fallback)
* [ ] AI jump the same ledges you would; nobody flies
* [ ] `POS x/4` is alive — you check it (that's the product)
* [ ] Full race, default skills: you can beat BOLD and lose to RECKLESS
      on a clean run (beatable-but-not-free)
* [ ] 60 FPS feel with 4 goats on screen (F3 + eyeball)
* [ ] **Gate question: herd, or ghosts?** — do they read as goats
      racing, or floating hitboxes executing a spline?

**All boxes → write `phase-7-completion.md`.**

⏱ ~75 min

---

## Effort summary

| Step | | Time |
|---|---|---|
| 1 | Autopilot hook | ~60 min |
| 2 | AI brain | ~90 min |
| 3 | Roster + multi-racer manager | ~90 min |
| 4 | Visuals + standings | ~60 min |
| 5 | F3 + tuning hooks | ~30 min |
| 6 | Verification | ~75 min |
| | **Total** | **~7 h** |

---

## Risks & notes

* **The controller edit is the only physics-adjacent touch** — same
  discipline as Phase 6 D3: additive, gated, regression-first. If the
  suite reddens, the edit backs out and AI drives via
  `set_horizontal_velocity` injections instead (uglier, zero-risk — the
  hook has existed since Phase 3).
* **D1 collision is the live wire.** CharacterBody-vs-CharacterBody at
  20 m/s on trimesh can jitter, stack, or punt. The pre-agreed fallback
  (layer AI off each other) is one line — take it the moment bumping
  reads worse than ghosting. Phase 8 owns making bumps *feel* like
  goats, not bowling balls.
* **AI oscillation on steeps/ice** — lookahead steering + the existing
  carve turn-rate can resonate (zig-zag). Dampers: longer lookahead at
  speed, wish smoothing (lerp), and grip already limits turn rate. Tune
  order: lookahead → smoothing → skill bias.
* **Skill constants are first guesses derived headless** — the spread
  (0.85/0.95/1.05) exists to make order *observable*; F5 narrows it.
  RECKLESS at 1.05 with full jump-eagerness will eat crashes — that's
  the point, but if it DNFs-by-tumble the stuck net catches it (ugly;
  tune the eagerness down).
* **Determinism caveat:** physics + 4 interacting bodies will not be
  bit-identical across runs — the smoke asserts *structure* (all
  finish, order consistent, no crashes), not exact times.
* **Gate volumes + 4 bodies** — trigger boxes only monitor for the
  current gate per racer; volume entries are per-body, so per-racer
  gate state must key off body identity (a Dictionary keyed by racer,
  not an index assumption).
* **The spawn disc is small (26 m radius)** — a 4-goat grid + countdown
  settle must not slide anyone (Phase 6 proved input-lock holds on the
  27° spawn; verify for grid slots near the disc edge — keep everyone
  ≥ 6 m inside).
* **Course quality compounds** — AI expose course flaws the player
  improvises around (a gate reachable only via one narrow line). If an
  AI teleports repeatedly at the same gate, that's a *course* bug —
  fix `RACE_GATE_*`, not the brain.

---

## Handoff → Phase 8

Phase 8 target (per `README.md`): *Mountain Gameplay* — real obstacles
(rock/vegetation collision), terrain challenges, route branching
(safe vs danger).

Already in place for it:

* Vegetation placement records exist — pines/rocks become colliders by
  adding shapes at recorded positions (the race line already avoids
  pines, so the course stays fair)
* The stuck-net + F3 teleport counter is the telemetry that tells us
  where the mountain got unfair
* AI goats are crash-test dummies for obstacle difficulty (run the herd
  through a candidate obstacle field headless)
* Goat-vs-goat collision policy settles here (D1 or its fallback) —
  Phase 8's knockback work builds on whichever shipped
* Known gaps to carry: real goat model/skeletal ragdoll; water still
  visual; finish-altitude tuning; AI "later list" (personalities,
  shortcuts) deliberately deferred
