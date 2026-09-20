# 🤸 Phase 9 — Tricks & Scoring: Execution Plan

> Expands `README.md` → *Phase 9 — Tricks & Scoring* into concrete,
> executable steps. The mission: **make skill pay** — the air the goat
> already catches becomes scoreable, danger becomes profitable, and the
> finish line grades the whole run, not just the clock.
> Carried assets landing here (Phase 8 handoff): the entire trick event
> vocabulary has existed since Phase 4 and gained attribution in Phase 8
> (`goat_jumped(who)` / `goat_landed(impact, who)` / `goat_bonked(…,
> who)` / `goat_hit_obstacle(impact, who)`); obstacle records
> (`get_obstacles()`) make near-miss and log-jump detection distance
> queries; the gauntlet harness pattern verifies tricks headless by
> forcing the state and asserting the signal.
>
> ⚠️ **Scope fence:** tricks are LISTENERS, never new physics — the
> controller's verified air/slide/tumble behavior is the substrate
> everything scores on top of. One small addition is allowed: the
> deliberate trick SPIN channel (Body visual only, capsule untouched —
> the same discipline as Phase 5's tumble). No XP, no upgrades, no
> multiple mountains (Phase 10); no persistence (Phase 16 backend).

---

## Goal

```text
        AIR WINDOW  (goat_jumped → … → goat_landed)
               ↓
   rotation tricks        auto tricks           danger tricks
   Q = front flip         long jump (≥15 m)     near miss (≤1.6 m
   E = back flip          cliff jump (≥6 m drop)  at ≥10 m/s, no hit)
   mouse 360 in air       LOG JUMP (Phase 8      coins on the line
   (yaw ≥ 300°)             records, no bonk)      (distance pickup)
               ↓
   combo: tricks in ONE air window chain a multiplier (bonk voids it)
               ↓
   clean landing = banked  ·  slam/tumble = voided  (risk ↔ reward)
               ↓
   SCORE on the HUD, per-trick popups, graded on the results panel
               ↓
   THE MOUNTAIN BECOMES A PLAYGROUND THAT PAYS 🤸
```

**Definition of done:** on `F5` — a flip reads and FEELS like a flip
(horns swing, landing pops); chaining tricks in one jump feels greedy and
great; near-misses make you thread closer to pines on purpose; coins bend
your racing line; the results panel grades score next to time. Headless:
every trick type fires from forced state (the gauntlet pattern), combos
multiply, bonks void chains, coins collect, full regression green.

---

## Decisions locked in Phase 9

| # | Decision | Choice | Why |
|---|----------|--------|-----|
| D1 | Tricks are listeners | **Zero physics changes** — detectors consume the attributed signal vocabulary + `get_debug_state()` air stats; one allowance: a deliberate Body-spin channel (visual only, the tumble discipline) | The Phase 8 promise ("tricks are listeners, not new physics") — the substrate is regression-proven; scoring must not re-open it |
| D2 | Trick inputs | **Flips: dedicated keys** (Q front / E back, new input actions); **spin: mouse** (accumulated body-yaw ≥ 300° in one air window = "360"); everything else auto-detected | Air WASD already does translation (conflict); mouse spins are ALREADY how players style downhill — detecting them is free and feels earned, not button-y |
| D3 | Camera choreography | **Partial** — the Body does the full 360°, the camera pitches/rolls a Config fraction (~20%), killable via CAM_FX | A full first-person flip is nausea city (Phase 4 lesson: camera levers halve first); partial reads as "I flipped" without the vomit — F3/F5 tunes the fraction |
| D4 | Clean-landing gate | Tricks bank **only on a grounded landing without tumble**; a slam (impact > STUMBLE_IMPACT) or tumble **voids the whole air window's chain** | Risk↔reward is the entire game: a flip you can't land is worth nothing, which makes choosing WHEN to flip the skill |
| D5 | Combos | **Multiplier per distinct trick in one air window**: x1.0 → +0.5 each (x1.5, x2.0, …), shown live; reset on bonk/tumble/landing | Chain-greed is the loop; distinct-only stops Q-spam (repeat flip = same trick, no extra multiplier — points still bank flat) |
| D6 | Coins | **Distance-pickup (no Area3D storm), placed on the racing line by the corridor logic, D10-fairness-clean, one MultiMesh draw** + game-side records | The web-perf pattern continues; coins are a SCORE pickup in Phase 9 — Phase 10's economy may consume the same counter |
| D7 | Player-only v1 | AI goats race but **don't trick**; their scoring is Phase 10's "later" list (personalities/mistakes) | README parks AI tricks; the herd's job is pressure, not style |
| D8 | Per-race score | No persistence, no meta — results panel + best-of-session in memory only | Backend is Phase 16; a fake save system now is a bug factory |
| D9 | Records are the truth | Near-miss and log-jump read `get_obstacles()` records; coin pickups read coin records — **no physics queries, ever** | Deterministic headless grading + the Phase 8 contract ("no record, no obstacle") extends to pickups |
| D10 | Numbers are Config | Every threshold (flip progress %, near-miss radius, combo step, coin value…) is a const; F5 tunes, code never | The whole feel lives in one file, like every phase before |

**Out of scope (later):** XP/currency economy + shop (10), multiple
mountains (10), AI tricks (10), trick replays/ghosts (12+), mobile
touch tricks (13/14), trick audio stings (12), score persistence (16).

---

## Step 1 — The air window: detector skeleton + stats

**Files:** new `scripts/player/trick_detector.gd` (child of the player
goat), `event_bus.gd` (`trick_scored(name, points, combo, goat)`),
`config.gd` (TRICK_* group).

**Do:**

* Detector listens: `goat_jumped` opens a window; `goat_landed(impact)`
  closes it; window stats sampled per tick from `get_debug_state()`
  (airtime, horizontal distance, drop, entry/exit speed, max yaw rate)
* Emit the signal contract now (fire with zero tricks yet) — HUD, smoke
  and the score system all hang off the same wire
* Bonk/tumble inside a window marks it voided (D4 plumbing)
* Config first guesses: `TRICK_LONG_JUMP_M := 15.0`,
  `TRICK_CLIFF_DROP_M := 6.0`, values in the table below

**Done when:** headless — a forced jump (teleport + slope-aligned
velocity, the Phase 8 launch discipline) produces one closed window with
sane stats (airtime ≈ physics, distance > 0); a bonk mid-window voids it.

**Commit checkpoint:** `feat: trick detector — air windows, stats, signal contract`

⏱ ~75 min

---

## Step 2 — Rotation tricks: flips + the 360

**Files:** `trick_detector.gd`, `goat_controller.gd` (spin channel),
`camera_fx.gd` (partial choreography), `project.godot` (input actions
`trick_front` = Q, `trick_back` = E), `config.gd`.

**Do:**

* Controller gains `start_trick_spin(axis, duration)` — a controlled
  quaternion slerp of the visible Body over the axis (front/back =
  pitch), ~0.55 s for the full turn; the capsule and physics NEVER move
  (the tumble discipline, deliberately triggered)
* Flip input: only while airborne (and not tumbling); re-press during a
  running flip is ignored v1; flip progress tracked 0–1
* Landing rule (D4): flip ≥ 85% complete at touchdown = clean → score;
  incomplete = SLAM → window voided + the verified stumble beat plays
* 360: accumulate body-yaw delta during the window (mouse spins are body
  yaws via head_camera); ≥ 300° = "360" (front/back direction noted for
  the label, v1 score is flat)
* Camera: `FLIP_CAM_FRACTION := 0.2` of the flip rotation applied to the
  camera's pitch/roll springs (D3) — horn sway sells it; CAM_FX-gated
* F3: current window stats + flip progress line

**Done when:** headless — forced air + `Input.action_press("trick_front")`
fires `trick_scored("front_flip", …)` on clean landing; incomplete flip
slams (window voided); a scripted 300°+ yaw accumulation scores the 360;
grounded Q/E does nothing.

**Commit checkpoint:** `feat: rotation tricks — flips, 360s, clean-landing gate`

⏱ ~90 min

---

## Step 3 — Auto tricks: long jump, cliff jump, LOG JUMP

**Files:** `trick_detector.gd`, `config.gd`.

**Do:**

* On window close (clean): distance ≥ 15 m → long jump; drop ≥ 6 m →
  cliff jump (both can stack with flips — that's the combo)
* **Log jump** (the Phase 8 promise): during the window, if the goat's
  XZ passed within `LOG_R + 1.2 m` of a log record's segment and no
  `goat_hit_obstacle` followed → score it. The trick that pays for the
  risk the logs finally take
* Labels carry the multiplier context; values:
  front/back flip 500 · 360 300 · long jump 200 · cliff jump 400 ·
  log jump 250 (all Config, all F5-tunable)

**Done when:** headless — the gauntlet-pattern launch over the planar
log (Phase 8's proven setup) scores the log jump; a long ballistic
flight scores long jump + cliff jump stacked; a bonk on the log scores
nothing (window voided).

**Commit checkpoint:** `feat: auto tricks — long/cliff/log jumps`

⏱ ~75 min

---

## Step 4 — Near miss: the danger dividend

**Files:** `trick_detector.gd`, `config.gd`.

**Do:**

* While grounded-or-air at speed ≥ 10 m/s: nearest obstacle record
  (pines/rocks/logs) within `TRICK_NEAR_MISS_R := 1.6 m` surface
  distance (record r + 1.6) — and no hit on it within a 1.5 s cooldown
  window → near miss, 100 pts
* Per-obstacle cooldown (an obstacle pays once per pass — grinding a
  parked goat next to a pine earns nothing: speed gate handles it)
* F3: `nm` counter on the player line

**Done when:** headless — the differential-A/B launch rig (Phase 8's,
reused verbatim) passes within 1.6 m of the blocker at 12 m/s → one
near-miss fires; a head-on hit fires zero; a slow pass fires zero.

**Commit checkpoint:** `feat: near-miss detection — danger pays`

⏱ ~60 min

---

## Step 5 — Score system + HUD

**Files:** new `scripts/game/score.gd` (autoload or manager-side —
manager-side, autoloads are for cross-scene state and this dies with
the race), `race_hud.gd`, `race_manager.gd` (score into race state +
results), `config.gd`.

**Do:**

* Score owns: running total, per-window combo multiplier (D5: distinct
  tricks chain +0.5), void logic, session best
* HUD: score counter (top bar, next to time), floating per-trick labels
  ("FRONT FLIP +500 ×2") — a label stack, 1.2 s fade, no layout shift
* Results panel gains the score line + best-trick of the run
* `get_race_state()` gains score fields (smoke + HUD read one snapshot)

**Done when:** headless — a scripted window with flip + long jump
scores (500 + 200) × 1.5; a bonked window scores 0 and resets the
multiplier; HUD/results smoke-assert on state fields.

**Commit checkpoint:** `feat: scoring — combos, multiplier, HUD, results`

⏱ ~75 min

---

## Step 6 — Coins on the line

**Files:** new `scripts/race/coins.gd` (sibling under Course —
course-side placement), `trick_detector.gd` or player-side pickup tick,
`race_hud.gd` (counter), `config.gd` (`COIN_COUNT := 60`, value 50).

**Do:**

* Placement: snake along the course polyline (every ~8 m, alternating
  ±1.5 m lateral jitter, `get_height_at + 0.8`), skipping D10 zones —
  the corridor logic again; arcs of 3 over the logs (a coin trail over
  a log is a tutorial that teaches itself)
* Visual: one MultiMesh (golden octahedron ~0.35 m), game-side records
  `{pos, collected}` — D6, one draw call, web-cheap
* Pickup: distance ≤ 1.4 m at any speed → collected (hide instance by
  scale-zero transform), counter, +50; F3 count; results line
* No magnets, no animation v1 — F5 decides if they need juice

**Done when:** headless — records match placements (the log test
pattern), a pass through a coin's position collects exactly it, D10
zones clean, ledger line prints (`COINS: 60 placed in T ms`).

**Commit checkpoint:** `feat: coins — line placement, distance pickup`

⏱ ~75 min

---

## Step 7 — Verification: the trick battery + regression

**Headless (temp smoke, deleted after — the standing lessons: wall-clock
waits only, polls with generous deadlines, tick-side witnesses for
physics assertions, zero project-class references at entry parse,
mount in _process):**

* **Trick battery:** forced air + trick inputs via `Input.action_press`
  (physics DOES tick under --script — races prove it daily) → every
  trick type fires; incomplete flip slams; bonk voids; combo math
  exact (500+200 ×1.5 cases); near-miss A/B reuses the Phase 8 rig
* **Coins:** placement audit + pickup + D10
* **Regression:** settle / jump / downhill-witness / tumble-witness /
  kill switch / terrain API / race flow / autopilot invisibility — the
  Phase 8 suite shape, plus the gauntlet (tricks must not disturb the
  herd: same finish times ±10%, hits still ≤ 30)
* Ledger + boot clean, no new draw-call taxes (F3)

**User-side (the real gate — feel is the product):**

* [ ] Q mid-jump: the flip READS (horns swing, ~20% camera, landing
      pop) — and the nausea check passes at the current fraction
* [ ] Landing a flip clean vs slamming it: the risk feels fair
* [ ] One mouse-360 in the air scores and feels EARNED, not button-y
* [ ] Log jumps pay — do the coins-over-logs trail teach the jump?
* [ ] Near misses make you thread closer to pines on purpose
* [ ] Combos: chaining greed is legible on the HUD, the void on bonk
      stings correctly
* [ ] Score next to time on the results panel: do you RACE differently
      knowing style counts?
* [ ] 60 FPS feel unchanged (F3 + eyeball)
* [ ] **Gate question: does the mountain pay for skill — or just
      survive it?**

**All boxes → write `phase-9-completion.md`.**

⏱ ~75 min

---

## Effort summary

| Step | | Time |
|---|---|---|
| 1 | Air window detector | ~75 min |
| 2 | Rotation tricks | ~90 min |
| 3 | Auto tricks (incl. log jump) | ~75 min |
| 4 | Near miss | ~60 min |
| 5 | Score + HUD | ~75 min |
| 6 | Coins | ~75 min |
| 7 | Verification | ~75 min |
| | **Total** | **~8.75 h** |

---

## Risks & notes

* **Flip nausea** — the one true product risk. The fraction lever
  (`FLIP_CAM_FRACTION`) is the first dial, halving is the second, zero
  (Body-only) is the honest fallback — the trick still scores, the
  camera just watches. F5 decides with the owner's stomach, not vibes.
* **Trick-spam degeneracy** — Q-mashing every air window. Guards:
  distinct-trick-only multiplier (D5), incomplete-flip slam (D4), and
  the flip lockout during a running flip. If F5 still finds spam,
  the next lever is per-window trick caps — config, not redesign.
* **Near-miss noise** — too generous and every gate pass "near-misses"
  a pine (records are corridor-dense in gaps 0/2). The 1.6 m + speed
  gate + per-obstacle cooldown is the first cut; the gauntlet prints
  per-run near-miss counts to calibrate before F5.
* **Coins vs. the racing line** — coins that punish the fast line are
  a bug: placement follows the polyline (the line the herd proves),
  jitter is small, and log arcs reward the EXISTING racing choice.
  If coins warp lines badly at F5: reduce count, not brightness.
* **The mouse-360 false positive** — normal cornering yaws accumulate;
  the window resets at landing and 300° in <1 s of air is never
  accidental steering. If it still false-fires: raise to 330° (Config).
* **Slam-on-flip could chain-void fun** — flipping off every little
  bump and eating slams feels punitive; v1 keeps it strict (pure is
  tunable later — a "sketchy landing = half points" tier exists in
  config space if F5 begs).
* **Score inflation vs. race time** — if style dominates position,
  the race stops being a race. Position bonus on the results panel
  (P1 +500 / P2 +250 / P3 +100) prices the win into the score —
  one line in Step 5, tune at F5.
* **--script physics chaos (Phase 8 lesson)** — trick tests MUST use
  the proven patterns: settle-then-launch, slope-aligned velocity,
  per-frame polls with long deadlines, tick-side witnesses for
  anything timing-sensitive. No new harness inventions.
* **Progress-by-gates refactor** — parked unless a trick NEEDS it
  (log-jump detection is record-distance, not progress). It remains
  the natural pre-Phase-10 sidequest (route events want it).

---

## Handoff → Phase 10

Phase 10 target (per `README.md`): *Progression* — XP, coins economy,
goat upgrades (speed/jump/grip/stamina), skins, multiple mountains.

Already in place for it:

* **Coin pickup counter** — Phase 10's economy consumes the same event
  (swap +50 score for +1 currency is a listener change)
* **Score + best-trick per race** — the XP feed
* **Trick values in Config** — the upgrade economy's price list is a
  file edit, not a refactor
* **Course/generation is seed-parameterized** — multiple mountains is
  N seed configs + a mountain picker (the biggest structural lift:
  menu UI, which is Phase 11's warm-up)
* Carried: AI tricks/personalities; chord machinery awaiting a
  meanderier seed; bump-fairness verdict; real goat model; reffimg/
  still untracked
