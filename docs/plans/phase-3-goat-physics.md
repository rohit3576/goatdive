# 🐐 Phase 3 — Goat Physics: Execution Plan

> Expands `README.md` → *Phase 3 — Goat Physics* into concrete, executable steps.
> The mission: **make the goat feel like an actual mountain animal.**
> Seeds planted in Phase 2 (`_downhill_accel`, `Config` tunables, `EventBus.goat_landed`)
> all get consumed here.

---

## Goal

```text
Phase 2 movement model          (works, feels like a shopping cart)
        ↓
Surface types: rock / grass / snow / ice     ← terrain data drives both look & grip
        ↓
Grip-scaled accel / brake / turn             ← one scalar per surface
        ↓
Carving steering + momentum                  ← fixes side-slope drift
        ↓
Steep: climb < slide threshold < wall
        ↓
Coyote time + jump buffer + landing impacts + stumble
        ↓
FEELS LIKE A GOAT 🐐⬇️❄️
```

**Definition of done:** on `F5` — snow visibly slips, ice barely steers, rock grips and
brakes, steep slopes slide you unless you fight them, ledges are jumpable a beat after
leaving them, hard landings stumble you. Smoke test proves grip differential, slide, and
coyote headless. Zero regressions on the Phase 2 suite.

---

## Decisions locked in Phase 3

| # | Decision | Choice | Why |
|---|----------|--------|-----|
| D1 | Surface detection | **Derived from terrain data** (height + slope + noise mask) via `TerrainGenerator.surface_at(x, z)` | Same heights array that builds the mesh — physics can't disagree with visuals. No texture-reading hacks. |
| D2 | Ice placement | Noise-masked patches **within the snow zone**, tinted pale blue in vertex colors | Visible, data-driven, seedable; no new assets. |
| D3 | Grip model | **One scalar per surface** (rock 1.0, grass 0.85, snow 0.5, ice 0.25) multiplying accel, brake, and turn rate | One number to tune per surface; composes with everything. |
| D4 | Steering | **Carving**: velocity direction rotates toward wish at a grip-limited turn rate; speed preserved through turns | Fixes the Phase 2 side-slope drift gap; this is what momentum *feels* like. |
| D5 | Steep bands | `floor_max_angle` 45° → **55°** (goats climb); **slide threshold ~42°**; above 55° still wall | Uphill slowdown emerges free from gravity projection — climbing = carrying speed in. |
| D6 | Jump feel aids | **Coyote 0.12 s + buffer 0.12 s** | The two cheapest feel wins in platformer history. |
| D7 | Impact response | Vertical impact > 12 m/s → **stumble 0.4 s** (zero input authority). No health/damage system. | Collision response without inventing a damage economy. |
| D8 | Ragdoll | **Deferred to Phase 5** (needs a skeletal goat model — we have boxes) | Honest scope; stumble + slide-outs ship as the collision response. |
| D9 | Debug overlay | `toggle_debug` (F3) shows speed / slope / surface / state / vertical speed | A feel-tuning phase needs live instrumentation. Cheap `CanvasLayer` + `Label`. |

**Out of scope (later phases):** camera bob/tilt/shake (4), real mountain art (5), audio (12), ragdoll (5), tricks (9).

---

## Step 1 — Surface classification, shared by visuals & physics

**Files:** `scripts/terrain/terrain_generator.gd` (extend), nothing else yet.

**Do:**

* `enum Surface { ROCK, GRASS, SNOW, ICE }` + `surface_at(x: float, z: float) -> Surface`:
  * grass: low + gentle · rock: mid-band or steep · snow: above the snow line (reuse the
    existing 92 m threshold) · ice: inside the snow zone AND inside a low-frequency noise
    mask (patch-shaped, seedable)
* Keep it **pure**: same inputs as `_height_at`, no hidden state
* Refactor `_color_for_height` → `_color_for_surface` so vertex colors and the classifier
  are one code path (ice gets its pale blue tint here — currently impossible to see)
* Expose `grip_for(surface)` mapping? **No** — grip values live in `Config` (D3), the
  terrain only classifies

**Done when:** re-running the game shows distinct snow/ice/rock/grass zones (user check);
`surface_at` callable and unit-consistent with colors (headless assert in Step 5).

**Commit checkpoint:** `feat: terrain surface classification with visible ice patches`

⏱ ~45 min

---

## Step 2 — Grip-aware movement + carving steering

**Files:** `scripts/player/goat_controller.gd` (rework), `scripts/game/config.gd`.

**Do:**

* Query surface each grounded tick: `surface_at(global_position.x, global_position.z)`
  → `grip` from `Config` (`GRIP_ROCK/GRASS/SNOW/ICE`)
* Scale by grip: `MOVE_ACCEL`, `FRICTION`, and the new turn rate
* **Carving (D4)** — replace the additive-only horizontal model:
  * speed scalar `s` + heading `θ` state (or vector with restricted rotation)
  * wish direction rotates `θ` toward input at `TURN_RATE * grip` rad/s
  * accel changes `s`, not direction directly — turns preserve momentum
  * downhill accel still adds along the fall line, grip-independent (gravity doesn't care)
* Slippery feel emerges: on ice, `TURN_RATE × 0.25` and `FRICTION × 0.25` → you *drift*
  into turns carrying speed; rock bites

**Done when:** the Phase 2 smoke test still passes *and* new grip assertions pass (Step 5);
`F5`: grass brakes in ~1 goat-length, ice glides for many.

**Commit checkpoint:** `feat: grip-scaled movement with carving steering`

⏱ ~90 min

---

## Step 3 — Steep mechanics: climbing, sliding, walls

**Files:** `goat_controller.gd`, `goat.tscn` (one property), `config.gd`.

**Do:**

* `floor_max_angle = 55°` on the goat (D5) — steep faces become floors
* **Slide state** (slope ≥ 42° and grounded):
  * forced downhill accel (skip the input-gate — gravity wins on steep)
  * input authority ×0.3 — you *steer* the slide, not stop it
  * jump still allowed (goats launch off steeps)
* Climbing needs no new code: uphill `g_proj` opposes motion; carrying speed in is the
  mechanic. Verify it emerges (Step 5 asserts uphill deceleration)
* Watch capsule behavior on 45–55° — jitter means tune `floor_snap_length` (risk #2)

**Done when:** a 45° face can be entered with speed and climbed while bleeding it, or slid
down with steering; standing still on it slowly slides you.

**Commit checkpoint:** `feat: climb/slide steep bands with slide state`

⏱ ~60 min

---

## Step 4 — Jump feel, landing impacts, stumble

**Files:** `goat_controller.gd`, `config.gd`, `scripts/game/event_bus.gd` (already has the signal).

**Do:**

* **Coyote (0.12 s)**: `jump` works for 0.12 s after leaving floor
* **Buffer (0.12 s)**: `jump` pressed mid-air fires on touchdown
* **Landing**: track `was_on_floor`; on transition air→floor compute
  `impact = -pre_land_velocity.y`; emit `EventBus.goat_landed.emit(impact)` — first real
  EventBus consumer (Phase 4 camera subscribes next phase)
* **Stumble (D7)**: impact > `STUMBLE_IMPACT` (12) → `STUMBLE_TIME` (0.4 s) of zero input
  authority; friction still applies (you skid)
* Light landing (< 4 m/s): horizontal speed retained × `grip` — snow landings slide out,
  rock landings bite

**Done when:** ledge-jumping a beat late still jumps; a big cliff drop lands with a visible
skid + dead controls for a beat; `goat_landed` fires with sane numbers (overlay shows).

**Commit checkpoint:** `feat: coyote/buffer jumps, landing impacts, stumble`

⏱ ~60 min

---

## Step 5 — Debug overlay (F3)

**Files:** new `scripts/utils/debug_overlay.gd` + node in `goat.tscn` (CanvasLayer/Label).

**Do:**

* Shows: speed (m/s), slope (°), surface name, state (GROUND/AIR/SLIDE/STUMBLE), vertical
  speed, coyote/buffer state
* Reads goat state via a small `get_debug_state() -> Dictionary` on the controller (no
  spaghetti access)
* Toggled by the existing `toggle_debug` action; hidden by default

**Done when:** F3 flips it, values move believably during a run.

**Commit checkpoint:** `feat: F3 debug overlay for physics tuning`

⏱ ~30 min

---

## Step 6 — Verification: regression + new physics assertions

**Headless (temp smoke script, deleted after — same pattern as Phase 2):**

* **Regression**: settle / jump / downhill from the Phase 2 suite still pass
* **Grip differential**: same start speed, let it coast on grass vs ice patch (teleport
  goat onto each) — ice coast distance > 3× grass
* **Slide**: teleport onto a ≥ 45° face, no input → speed grows along fall line
* **Coyote**: walk off a ledge, press jump within 0.12 s → vertical velocity ≈ jump
  velocity (assert `velocity.y > 3` right after)
* **Landing**: drop from 30 m → `goat_landed` fired with impact > 12, control authority 0
  for the stumble window

**User-side (this phase's real gate — it IS the feel phase):**

* [ ] Run the line: grass → rock → snow → ice — each feels different at a glance
* [ ] Carve a turn on snow at speed — drift, don't teleport-direction
* [ ] Climb a steep face with a run-up; slide it without one
* [ ] Ledge-hop with late jumps (coyote) and early presses (buffer)
* [ ] Take one big cliff fall — skid + stumble, no ragdoll weirdness
* [ ] **Gate question:** does the goat feel like an animal now, or still a shopping cart?

**All boxes → write `phase-3-completion.md`.**

⏱ ~60 min

---

## Effort summary

| Step | | Time |
|---|---|---|
| 1 | Surface classification | ~45 min |
| 2 | Grip + carving | ~90 min |
| 3 | Steep bands | ~60 min |
| 4 | Jump/landing/stumble | ~60 min |
| 5 | Debug overlay | ~30 min |
| 6 | Verification | ~60 min |
| | **Total** | **~5.5–6 h** |

---

## Risks & notes

* **Movement rewrite risk** — Step 2 replaces the verified Phase 2 model. The Phase 2
  smoke test is the regression gate; run it after *every* step, not just at the end.
* **45–55° capsule jitter** — known CharacterBody3D zone (snap vs slide fighting). If it
  jitters, tune `floor_snap_length` before touching the state machine.
* **Ice on the race line** — the noise mask could drop ice patches onto the descent path.
  Tune mask frequency/coverage; the spawn disc already stays noise-free.
* **Feel is not headless-verifiable** — assertions prove mechanics; the F3 overlay + your
  hands tune the *feel*. Budget real F5 iteration time; this doc's numbers are first guesses.
* **`get_floor_normal()` only when `is_on_floor()`** — already true in the current code;
  keep it that way in the rework.
* **Phase 2's vy-quirk** (velocity.y reads 0 while floor-sliding) — if carving makes it
  load-bearing, fix it; otherwise leave for Phase 4's camera work.
