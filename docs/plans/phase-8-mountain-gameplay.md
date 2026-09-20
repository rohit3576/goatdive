# 🧗 Phase 8 — Mountain Gameplay: Execution Plan

> Expands `README.md` → *Phase 8 — Mountain Gameplay* into concrete,
> executable steps. The mission: **make the mountain itself the challenge**
> — vegetation stops being wallpaper, obstacles get jumpable, and the
> course grows optional danger shortcuts. The consequence pipeline
> (bonk → trauma → tumble → recovery) has existed since Phases 4–5;
> Phase 8 finally gives it things to hit.
> Carried assets landing here (Phase 7 handoff): vegetation placement
> records are collider-ready, rescue telemetry (`tp` counters, gate-stall
> window) is course QA, the herd is a crash-test dummy rig, goat-goat
> collision is ON, and gates are polyline vertices so routes can branch
> without touching the race system.
>
> ⚠️ **Scope fence:** no terrain reshaping (the terrain API is frozen and
> the course is proven — Phase 8 works WITH the mountain: cliff bands,
> ledges, ice and steeps already exist from Phase 5; we make them
> *matter*). Falling rocks and unstable snow are dynamic-hazard ideas
> parked for a later pass (D5) — static obstacles first.

---

## Goal

```text
        THE CORRIDOR (within ~45 m of the race line)
              ↓
   pines · rocks  ──►  REAL COLLIDERS (visual-honest, web-capped)
              ↓
   fallen logs (1–2, perpendicular, jumpable at speed)
              ↓
   DANGER CHORDS — where the walk meanders, the straight cut is
   steeper · icier · obstacle-denser — marked, player-only, rejoins
              ↓
   SAFE line: gentler, longer      ← the choice is the game
              ↓
   herd runs the gauntlet headless → bonk/tumble/rescue map → tuned
              ↓
   A MOUNTAIN THAT ARGUES BACK 🧗
```

**Definition of done:** on `F5` — hitting a pine at speed reads as a
crash (bonk/tumble/camera already know how); logs are jumpable and
jumped; at least one signed danger shortcut tempts you every race
(shorter, scarier); the herd finishes with a *bounded* crash count.
Headless: corridor structure asserts, obstacle fairness rules, a herd
gauntlet run with difficulty inside bounds, full regression green.

---

## Decisions locked in Phase 8

| # | Decision | Choice | Why |
|---|----------|--------|-----|
| D1 | Where obstacles are real | **Course corridor only** — colliders for pines/rocks within `OBSTACLE_CORRIDOR_R` (~45 m) of the race polyline; everything beyond stays visual | 595 colliders for the web build is a tax nobody racing pays for. The corridor is where gameplay lives; the far treeline is scenery. Cap in Config, count in the ledger. |
| D2 | Collider honesty | **Primitive shapes sized to the visual bounds** — cylinder for the pine trunk-cone footprint, box/sphere for the rock prism; never bigger than what you see | The gate-slab lesson inverted: triggers may be generous, obstacles must be honest. A fat collider on a thin tree is an invisible wall — the one unforgivable lie in a racing game. |
| D3 | New obstacle: fallen logs | **1–2 procedural logs per course**, laid perpendicular to the line on straights, ~0.4 m radius — jumpable at racing speed, avoidable at slow speed; placement recorded game-side like vegetation | The jumpable barrier is the classic rhythm-breaker; records keep it auditable headless and feed Phase 9 trick scoring (log-jump = a trick the moment scoring exists). |
| D4 | Danger routes | **Generated shortcut CHORDS** (1–2): where the walk meanders, the chord across the bend is the danger line (steeper/icer by construction — it leaves the groomed gradient); marked with small flag pairs at entry/exit; **player-only v1** — AI stays on the polyline (README parks AI shortcuts in the "later" list) | The mountain already meanders (domain warp + heading momentum); the chord exploits it for free. No new path truth, no progress-math rewrite — the shortcut is terrain the player may take between the same two gates. |
| D5 | Dynamic hazards | **OUT v1** — no falling rocks, no collapsing snow; static only | Dynamic bodies cost web perf and deterministic testing simultaneously. Static first; a scripted rockfall zone is a cheap Phase 8.5 if F5 begs for it. |
| D6 | Terrain untouched | Zero terrain edits — challenges come from routing the course THROUGH what Phase 5 built (band treads as narrow paths, risers as wall sections, the ice mask as it lies) | The API is frozen and regression-proven; the spawn disc, snow line and band tuning are calibrated. Reshaping the mountain to add difficulty re-opens every Phase 5 question for one phase's gain. |
| D7 | Consequence pipeline | **Zero new impact code** — colliders make `move_and_slide` meet obstacles; `goat_bonked` / tumble / trauma / results already listen | Phases 4–5 built the response; Phase 8 supplies the stimulus. If a new consequence feels needed, that's a tuning bug, not a feature gap. |
| D8 | Difficulty telemetry | **The herd grades the mountain**: headless gauntlet runs count bonks/tumbles/rescues per corridor; F3 shows a per-AI crash line; the smoke asserts crash counts inside bounds | Phase 7's rescue counters already mark "where the mountain got unfair" — formalize it into the tuning loop. Obstacles are tuned by DATA from crash-test goats, not vibes. |
| D9 | Web perf budget | **One StaticBody3D parent for all corridor shapes** (shapes, not bodies — broadphase-friendly); corridor obstacle cap in Config; collider build joins the load-time ledger; ~zero new draw calls | The 60 FPS Chrome ceiling. Bodies are the expensive unit; shapes under one body are cheap. The ledger catches a regression before the browser does. |
| D10 | Fairness rules (hard) | Obstacles: never inside gate slabs or the 10 m after a gate (braking zone), never on the respawn approach, never invisible at 20 m at speed (minimum visual read), spawn disc stays clear | An obstacle you cannot see or cannot avoid at racing speed is a bug wearing a feature costume. These rules are asserted in the smoke, not just intended. |

**Out of scope (later):** dynamic hazards (8.5 candidate), tricks/scoring
(9), multiple mountains (10), goat upgrades (10), audio stings for
impacts (12), mobile touch (13/14), real goat model, water gameplay.

---

## Step 1 — The corridor: vegetation becomes real

**Files:** new `scripts/terrain/obstacles.gd`, `mountain_level.tscn`
(node), `config.gd` (OBSTACLE_* group).

**Do:**

* Walk the course polyline; for every pine/rock record within
  `OBSTACLE_CORRIDOR_R` of any segment: add a collider shape under ONE
  `StaticBody3D` — pine = `CylinderShape3D` (radius ≈ 0.5 × instance
  scale, height = trunk+cone), rock = `SphereShape3D`/`BoxShape3D`
  fitted to the prism's scaled bounds (records carry positions; the
  scale range is known vegetation behavior — use a conservative 80% of
  worst-case)
* **D10 exclusion zones:** skip records inside gate slabs, the 10 m
  post-gate braking strip, and the 8 m respawn approach line behind
  each gate
* Ledger line: `OBSTACLES: N corridor colliders (P pines, R rocks) of
  595 records, built in T ms`
* Config: `OBSTACLE_CORRIDOR_R`, `OBSTACLE_CAP` (first guess 220)
* Vegetation itself is UNTOUCHED (meshes, placement, records — same
  MultiMesh draw path)

**Done when:** headless — collider count within cap and > 0; no collider
in an exclusion zone (assert against gate geometry); a goat pushed into
a corridor pine at speed bonks (existing signal) — first real obstacle
impact in GoatDive history.

**Commit checkpoint:** `feat: corridor colliders — vegetation is real where races run`

⏱ ~75 min

---

## Step 2 — Brain avoidance: the herd lives with walls

**Files:** `ai_goat.gd`, `config.gd`.

**Do:**

* One avoidance probe per tick: pine/rock/log records within
  `AI_AVOID_R` (~9 m) ahead of the heading (dot-product cone test over
  the corridor records — a few hundred cheap checks)
* Steer offset: wish rotated away from the nearest threatening record
  (strength ∝ 1/distance, clamped to ~35°); smoothing already exists
  (`AI_WISH_SMOOTH`) — the nudge must not fight the lookahead
* Logs are avoid-first (the brain doesn't plan jumps v1 — the
  ledge-probe stays the only jump trigger)
* F3 debug line gains `av: N` (records in cone)

**Done when:** headless gauntlet run — AI pine-collision count drops
≥ 70% vs Step 1's baseline (the D8 loop's first iteration: measure,
avoid, re-measure); race finish times drift < 10% (avoidance must not
paralyze the herd).

**Commit checkpoint:** `feat: AI obstacle avoidance (record-based steering)`

⏱ ~75 min

---

## Step 3 — Fallen logs: the jumpable rhythm-breaker

**Files:** `obstacles.gd` (log mesh + placement + records), `config.gd`.

**Do:**

* Procedural log: cylinder, ~4–5 m long, radius ~0.4 m, bark-brown
  material, slight random roll; laid PERPENDICULAR to the course line
* Placement: 1–2 per course on polyline straights (curvature below a
  threshold over a 20 m window), mid-segment (D10 zones respected),
  resting on `get_height_at` + radius
* Records: `get_obstacles("logs")` → positions + axis (game-side truth
  for smoke, avoidance, and Phase 9 trick detection)
* Collider: one cylinder shape per log under the corridor body (D2
  honest bounds) + the visual `MeshInstance3D`
* Jump math check in-doc: `JUMP_VELOCITY 4.5` → apex ≈ 1.03 m over a
  0.8 m obstacle top at `MOVE_SPEED` — clearable with margin; the smoke
  proves it with a real goat jump over a real log

**Done when:** headless — a goat at `MOVE_SPEED` jumps a log clean
(no bonk, grounded past it); a goat at `MOVE_SPEED` NOT jumping bonks
(the log is real); records match placements.

**Commit checkpoint:** `feat: fallen logs — jumpable obstacles with records`

⏱ ~75 min

---

## Step 4 — Danger chords: the shortcut that argues

**Files:** `course_builder.gd` (chord detection + markers), `config.gd`.

**Do:**

* **Meander detection:** scan the polyline for windows [i, j] where
  `chord_length < CHORD_RATIO (0.7) × arc_length` and the window spans
  ≥ 80 m of arc — the walk bent, the cut is real
* **Terrain sanity on the chord:** sample slope/surface along it — it
  qualifies as DANGER only if it is measurably worse (mean slope >
  main line's, or crosses ICE/SNOW the main line avoids); otherwise
  skip (a shortcut that's just shorter is a bug — it must cost
  something)
* **Markers:** small flag pairs (two short posts + pennant, shared
  mesh, skull-white/danger-red material) at chord entry and exit;
  corridor obstacles STAY on the chord (that's the point)
* **Gates unchanged** — both lines run gate i → gate i+1; progress
  math keeps using the main polyline (a chord-riding player's projected
  distance snaps across the gap — accepted v1 flicker, noted in risks)
* 1–2 chords max; everything tunable (`CHORD_RATIO`, min arc, flag size)

**Done when:** headless — chord(s) found or the mountain honestly has
no qualifying meander (the seed decides; assert whichever); chord mean
slope > main-line slope (it's actually dangerous); markers exist at
both ends; F5 is where "does it tempt?" gets answered.

**Commit checkpoint:** `feat: danger chords — marked shortcut lines (player v1)`

⏱ ~90 min

---

## Step 5 — Telemetry: the mountain's report card

**Files:** `debug_overlay.gd`, `race_manager.gd` (crash counters),
`config.gd`.

**Do:**

* Manager counts per-racer `goat_bonked` events (all strengths — the
  current crash counter only counts tumble-grade; add `hits` = all
  bonks) and exposes them in `get_race_state`
* F3: player line gains `hits N`; AI lines gain `hits N` (per-AI bonk
  counts via the bus, filtered by body — one signal arg addition, same
  pattern as `checkpoint_passed`)
* The gauntlet runner grows a summary print: per-AI
  hits/tumbles/teleports + finish times — the D8 tuning table, one line
  per goat, ready to paste into the completion doc

**Done when:** F3 shows hits live; the smoke's gauntlet summary matches
its internal counters.

**Commit checkpoint:** `feat: difficulty telemetry — per-racer hit counters`

⏱ ~45 min

---

## Step 6 — Verification: fairness rules + the gauntlet + regression

**Headless (temp smoke, deleted after — the standing `--script`
lessons, now including: wall-clock timing only, duck-typed calls get
explicit types, action steps carry the waits):**

* **Corridor structure:** collider count ∈ (0, CAP]; zero colliders in
  D10 exclusion zones (gate slabs, braking strips, respawn approaches,
  spawn disc); ledger printed
* **Collider honesty:** sampled pine collider radius ≤ visual instance
  worst-case (D2 — no fat boxes)
* **Logs:** jump-over works (speed + jump → no bonk, lands past);
  no-jump bonks; records == placements
* **Chords:** qualification holds (shorter AND steeper); markers at
  both ends; gates untouched (7, same transforms as Phase 7 — the race
  system did not move)
* **The gauntlet:** full 4-goat grand prix (Phase 7 harness) — all
  finish; total hits inside a bound (first guess ≤ 30 — the number is
  a tuning baseline, not a law); teleports ≤ 8; finish times within
  25% of Phase 7's (obstacles slowed the herd, not stopped it)
* **Regression:** the full Phase 2–7 suite — settle / jump / downhill /
  tumble / kill switch / terrain API / race flow / autopilot invisibility

**User-side (the real gate — difficulty is a feel question):**

* [ ] Pines and rocks read as SOLID from 20 m out at speed — no
      invisible walls, no ghost passes
* [ ] First full-speed pine hit: bonk → (tumble at speed) → recovery —
      the arc reads fair, not cheap
* [ ] Logs: you jump them by choice and feel good; you can also avoid
      them without rage
* [ ] The danger chord TEMPTS you — you take it, it scares you, you
      either gain or eat consequences (the flag pair is visible early)
* [ ] The herd visibly dodges trees; nobody warp-spams
* [ ] A 10-run session: the mountain feels like the opponent, not the
      obstacles
* [ ] 60 FPS feel on the web renderer unchanged (F3 + eyeball)
* [ ] **Gate question: does the mountain argue back — or just get in
      the way?**

**All boxes → write `phase-8-completion.md`.**

⏱ ~75 min

---

## Effort summary

| Step | | Time |
|---|---|---|
| 1 | Corridor colliders | ~75 min |
| 2 | Brain avoidance | ~75 min |
| 3 | Fallen logs | ~75 min |
| 4 | Danger chords | ~90 min |
| 5 | Telemetry | ~45 min |
| 6 | Verification | ~75 min |
| | **Total** | **~7.5 h** |

---

## Risks & notes

* **Web perf is the phase's silent tax** — 200+ collision shapes on the
  trimesh. The one-body/many-shapes layout keeps broadphase sane, and
  the ledger prints build time, but if `--quit-after` frame time or a
  browser run sours: shrink `OBSTACLE_CORRIDOR_R` before anything else.
  The corridor is a dial, not a commitment.
* **AI avoidance vs paralysis** — a strong avoid nudge on a dense field
  makes the herd drunk; too weak and they're bowling pins. The Step 2
  done-condition (−70% hits, < 10% time drift) forces the balance.
  Tune order: probe radius → offset strength → smoothing.
* **The chord progress flicker** — a player on the chord projects to
  the main polyline across the gap; `dist-to-finish` and position may
  blip. Player-only and advisory v1; if it reads badly, the fix is
  progress-by-gates (next-gate distance + gate index), which is a
  Phase 9-era refactor with real benefits (trick detection wants it
  too).
* **Collider-vs-visual drift on scaled instances** — vegetation scale
  variance (0.7–1.6×) makes bounds fuzzy; use the record + the known
  scale range with a conservative fit, and accept "slightly generous
  on the biggest trees" over "fat on the smallest" (D2 bias: shrink,
  don't grow).
* **Tumble-lock in obstacle fields** — a bad corridor section
  (rock field + steep) can chain-tumble a goat past every rescue
  window; the gauntlet bound catches it, the D8 map locates it, and
  the fix is exclusion zones or fewer obstacles THERE — never a
  weaker tumble.
* **The seed decides everything** — chords may not qualify on this
  mountain (meanders too gentle). That's an honest outcome; the
  assert accepts "none found" and the completion doc says so. Forcing
  a fake shortcut is worse than none.
* **Goat-vs-obstacle while TUMBLING** — the capsule stays upright
  (Phase 5 design); a tumbled goat sliding into a pine bonks again —
  chained consequences are physical and fine, but watch for
  infinite-bonk pockets in the gauntlet data.
* **Records are the contract** — every new obstacle lands in
  `get_obstacles()`; anything placed without a record is invisible to
  avoidance, smoke, and Phase 9 scoring. No record, no obstacle.

---

## Handoff → Phase 9

Phase 9 target (per `README.md`): *Tricks & Scoring* — flips, spins,
long jumps, near misses, coins, score.

Already in place for it:

* **Obstacle records with positions + axes** — near-miss detection is
  a distance query against `get_obstacles()` during the run
* **Log records** — the log-jump trick is `grounded → airborne over a
  log record → grounded, no bonk`
* **Danger chords** — chord completion (gate i → gate i+1 via the
  chord) is a scoreable route event; markers mark the camera moment
* **`goat_jumped` / `goat_landed(impact)` / `goat_bonked(impact, dir)`**
  — the entire trick event vocabulary has existed since Phase 4; tricks
  are listeners, not new physics
* **Air state in `get_debug_state()`** (vy_world, tumbling) — flip/spin
  detection reads body rotation + air time
* **The gauntlet harness** — trick verification reuses it: force air
  time over a log, assert the trick fired
* Known gaps to carry: dynamic hazards parked; progress-by-gates
  refactor is the natural Phase 9 sidequest; real goat model still
  pending for visual flips (the visible Body already spins in tumble —
  flips are the same channel)
