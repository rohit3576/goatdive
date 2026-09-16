# 🐐 Phase 4 — First-Person POV: Execution Plan

> Expands `README.md` → *Phase 4 — First-Person POV* into concrete, executable steps.
> The mission: **build the signature camera** — the goat must *sell* "animal bounding
> down a mountain", not "floating drone with legs".
> Seeds planted in Phase 3 all get consumed here: `EventBus.goat_landed(impact)`,
> `get_debug_state()`, and the isolated `Head` → `Camera3D` rig.

---

## Goal

```text
Phase 3 controller (feels like a goat — camera is still a static tripod)
        ↓
Running bob                    ← speed-scaled, grounded only, eased in/out
        ↓
Slope tilt + carve lean        ← the mountain talks to the camera
        ↓
Jump pop · landing dip · fall drift
        ↓
Speed FOV kick · collision shake
        ↓
FEELS LIKE A GOAT'S HEAD 🐐👁️🏔️
```

**Definition of done:** on `F5` — running bobs naturally, speed widens the view,
side-slopes tilt it, carving leans into turns, jumps pop, hard landings dip + shake,
wall bonks kick — and the horns stay rock-steady in frame through all of it.
`CAM_FX = false` in `Config` reproduces the exact Phase 3 feel (master kill switch,
D10). Headless smoke proves bob / FOV / dip / shake mechanics and zero Phase 2/3
regressions.

---

## Decisions locked in Phase 4

| # | Decision | Choice | Why |
|---|----------|--------|-----|
| D1 | Where effects live | **New `camera_fx.gd` on the existing `Camera3D` node** — never on `Head` | `head_camera.gd` writes `Head.rotation` *absolutely* on every mouse event; any offset on `Head` gets wiped. `Camera3D` is a free child — offsets compose cleanly. |
| D2 | Horns coupling | Horns stay **children of `Camera3D`** and inherit every offset | The horns are *on the head* — they must bob/dip/shake exactly with the eye or they swim in frame. Free correct behavior, zero work. |
| D3 | Data plumbing | **Extend `get_debug_state()`** (add `vy_world`, keep existing keys) + two new signals `goat_jumped`, `goat_bonked(impact)` | Camera reads the same dict the F3 overlay reads — no spaghetti member access, no second state mirror. |
| D4 | Composition rule | Camera FX are **additive local offsets only** (`Camera3D.position`, `.rotation`, `.fov`) — never write body yaw, `_pitch`, or controller state | Look code and feel code stay mutually blind; the kill switch (D10) becomes trivially exact. |
| D5 | Dynamics model | **Sines for continuous effects, spring-damper for impulses** — no `Tween`s, no one-shot animations | Everything reacts to live state (speed, slope, impact) and recovers physically; cheap, deterministic, headless-testable. |
| D6 | Bob | Vertical sine + slight lateral sway; **rate ∝ speed, amplitude eased in/out, grounded only** (frozen in air, no snap on landing) | The cheapest "alive" signal there is. Air-freeze hides the landing snap the dip (D8) handles better. |
| D7 | Slope tilt + lean | **Tilt from floor normal vs camera basis** (pitch + roll, ≤ ~6°, scaled up in SLIDE) + **lean ∝ velocity-heading turn rate × speed** (carve lean, not mouse lean) | Terrain must talk to the camera; mouse yaw is head-turning, *carving* is body-leaning — only the latter leans. |
| D8 | Jump / land / fall | Jump → small pitch-up pop (on `goat_jumped`); landing → **dip ∝ impact** (spring, on `goat_landed`); fall → slight pitch drift ∝ `vy_world` | Phase 3 already fires `goat_landed(impact)` with real numbers — this is the payoff subscriber. |
| D9 | Shake | **Event impulses into one decaying shake spring** (wall bonks via `goat_bonked`, stumble landings) — positional + rotational noise, `trauma²`-shaped | One shake system, two doors. Scales with impact; always decays to exactly zero. |
| D10 | Kill switch + FOV | `CAM_FX := true` master const in `Config`; **FOV kick 78 → ~88** lerped over speed 8 → 20 m/s; every amplitude/rate is a Config tunable | A/B tuning against Phase 3 feel is the only honest way to judge "better". FOV widening is the classic speed-sells-speed trick. |

**Out of scope (later phases):** horn animation/deformation, third-person or replay
cams, ragdoll-follow cam (5, deferred with ragdoll), particles/dust (12), audio (12),
motion blur (12/13), UI (11).

---

## Step 1 — Camera state plumbing

**Files:** `scripts/player/goat_controller.gd` (small extensions),
`scripts/game/event_bus.gd`, `scripts/game/config.gd`.

**Do:**

* Extend `get_debug_state()` with:
  * `vy_world` — **fix the carried Phase 3 quirk** (`velocity.y ≈ 0` while
    floor-sliding): derive from `(global_position.y - _last_y) / delta` per physics
    tick. This number is now load-bearing — it drives the fall drift (D8).
* Emit `EventBus.goat_jumped` where the jump is consumed (after the coyote/buffer
  check) — the camera's pop subscriber.
* Emit `EventBus.goat_bonked(impact)` — after `move_and_slide()`, scan
  `get_slide_collision_count()` for near-horizontal normals (walls, not floors);
  `impact` = speed into the wall. Gate on a `BONK_MIN_SPEED` const so grazing
  contact doesn't rattle the camera.
* `Config` → `v0.4.0-phase4`; add `CAM_FX := true`, `FOV_BASE := 78.0`,
  `FOV_MAX := 88.0`, `BONK_MIN_SPEED := 5.0` (the rest of the tunables land with
  their steps, below).

**Done when:** F3 overlay still renders (old keys untouched); a test emit of each
new signal prints from a temporary subscriber; `vy_world` reads ≈ real descent rate
while sliding a slope (overlay eyeball).

**Commit checkpoint:** `feat: camera state plumbing (vy_world, jumped/bonked signals)`

⏱ ~45 min

---

## Step 2 — CameraFx core: bob + FOV kick

**Files:** new `scripts/player/camera_fx.gd` on the `Camera3D` node in `goat.tscn`;
`config.gd`.

**Do:**

* `camera_fx.gd extends Camera3D`, `_process(delta)` (clamped dt — window-drag
  spikes must not teleport springs):
  * **Bob (D6)**: phase advances at `BOB_RATE · (speed / MOVE_SPEED)` rad/s;
    amplitude scales `speed / MOVE_SPEED`, eased in/out over ~0.15 s on ground
    transitions; in AIR the phase freezes (no bob), position glides to neutral.
    Offset = `Vector3(sway · sin(phase·0.5), bob · |sin(phase)|, 0)` — the `|sin|`
    double-beat reads as galloping, not bouncing.
  * **FOV (D10)**: `fov = lerp(FOV_BASE, FOV_MAX, smoothstep(MOVE_SPEED, MAX_DOWNHILL_SPEED, speed))`,
    lerped per-frame toward target so it never pops.
  * `if not Config.CAM_FX: position/rotation = identity, fov = FOV_BASE, return`.
* Reads speed / state from the controller's `get_debug_state()` dict (D3) — node
  reference found via the parent chain, same pattern as `head_camera.gd`.
* Tunables in `Config`: `BOB_RATE`, `BOB_AMPL` (~0.05), `BOB_SWAY` (~0.02),
  `FOV_LERP` (~5.0).

**Done when:** F5 — standing still is perfectly still; walking bobs gently; full
downhill speed bobs fast + view widens visibly; jumping freezes the bob without a
snap; horns stay pinned in frame (D2 — verify by watching them while bobbing).

**Commit checkpoint:** `feat: camera bob + speed FOV kick (camera_fx)`

⏱ ~60 min

---

## Step 3 — Slope tilt + carve lean

**Files:** `camera_fx.gd`, `config.gd`.

**Do:**

* **Slope tilt (D7)**: while grounded, take the floor normal (add to the state dict
  in Step 1 if not already there — `floor_normal_y/x/z` or recompute from `slope` +
  heading), express the slope **relative to the view direction**:
  * pitch offset ∝ slope in the view plane (downhill ahead → dip nose slightly)
  * roll offset ∝ lateral slope component (side-hill → tilt with the hill)
  * capped at `TILT_MAX_DEG` (~6°), scaled ×1.5 in SLIDE state (steep faces feel steep)
  * eased in/out on ground/air transitions (same envelope as bob — one shared
    grounded-blend scalar)
* **Carve lean (D7)**: track velocity heading (from `velocity.x/z` in the state dict)
  per frame → heading rate; lean roll ∝ `heading_rate · speed`, capped at
  `LEAN_MAX_DEG` (~4°), heavily smoothed (lean is a promise, not a jerk).
* Tunables: `TILT_MAX_DEG`, `SLIDE_TILT_SCALE`, `LEAN_MAX_DEG`, `LEAN_SMOOTH`.

**Done when:** traversing a side-slope visibly tilts the horizon (subtly); carving
a snow turn leans into it; flicking the mouse alone does **not** lean; returning to
flat restores level within ~0.3 s.

**Commit checkpoint:** `feat: slope tilt + carve lean`

⏱ ~45 min

---

## Step 4 — Jump pop, landing dip, fall drift

**Files:** `camera_fx.gd`, `config.gd`.

**Do:**

* **One spring-damper per translational offset** (D5): `x += v·dt`,
  `v += (−k·x − c·v)·dt` — underdamped so dips bounce once and settle.
* **Jump pop** — subscribe `goat_jumped`: impulse `DIP_JUMP` (~ −0.06, i.e. small
  upward pop) + a couple degrees of pitch-up that recover with the same spring.
* **Landing dip** — subscribe `goat_landed(impact)`: dip impulse
  `∝ clamp(impact / STUMBLE_IMPACT, 0, 1.5) · DIP_LAND` (~0.15 max) + pitch-down
  ∝ impact. Stumble-class landings also dump into the shake spring (Step 5 wires
  this — same handler, second door).
* **Fall drift (D8)** — while `state == AIR` and `vy_world < −FALL_DRIFT_MIN`
  (~ −5): pitch offset drifts toward `FALL_PITCH_MAX_DEG` (~4° down) ∝ fall speed;
  eases back to 0 near touchdown. **This is why `vy_world` had to be fixed** —
  `velocity.y` reads ≈ 0 exactly when it matters (floor-slide).
* Tunables: `DIP_JUMP`, `DIP_LAND`, `DIP_SPRING_K`, `DIP_SPRING_C`,
  `FALL_DRIFT_MIN`, `FALL_PITCH_MAX_DEG`.

**Done when:** repeated small hops give a light tick-tock rhythm; one big cliff drop
lands with a visible dip-and-recover that scales with the F3-read impact; a long
fall noses down gently then levels out before landing.

**Commit checkpoint:** `feat: jump/landing/fall camera dynamics`

⏱ ~60 min

---

## Step 5 — Collision shake

**Files:** `camera_fx.gd`, `config.gd`.

**Do:**

* **Trauma model (D9)**: `trauma` ∈ [0,1]; impulses add
  `clamp(impact / SHAKE_REF_IMPACT, 0, 1)`; decays at `SHAKE_DECAY`/s; output =
  `trauma²` × noise on position (xyz) + rotation (pitch/roll) — max ~0.1 m / 2°.
* Two doors feed it: `goat_bonked(impact)` (walls/rocks — also a small directional
  kick *along the bonk* if the normal is cheap to pass) and stumble-class landings
  (from Step 4's landing handler).
* Noise: two desynced sine channels are enough (no `FastNoiseLite` dependency);
  frequencies `SHAKE_FREQ` ~ 25–35 Hz reads as impact, not earthquake.
* Tunables: `SHAKE_REF_IMPACT`, `SHAKE_DECAY`, `SHAKE_FREQ`, `SHAKE_POS`,
  `SHAKE_ROT_DEG`.

**Done when:** charging a rock face at speed kicks the camera once and it's gone in
~0.4 s; grazing contact does nothing; a stumble landing shakes *and* dips together
coherently; standing still after any event is perfectly still (trauma strictly
decays to 0).

**Commit checkpoint:** `feat: impact shake (trauma model)`

⏱ ~45 min

---

## Step 6 — Verification: regression + camera assertions

**Headless (temp smoke script, deleted after — same pattern as Phases 2/3):**

* **Regression**: full Phase 2 + Phase 3 suites still pass (controller untouched
  apart from additions — this proves it)
* **Bob**: standing → camera local position variance ≈ 0; `set_horizontal_velocity`
  on flat ground, sample 2 s → variance > 0 and mean offset returns near 0
* **FOV**: speed 0 → `fov == FOV_BASE`; speed `MAX_DOWNHILL_SPEED` → `fov`
  within 1° of `FOV_MAX`; never exceeds either
* **Dip**: emit `goat_landed(15)` → camera local y dips below baseline within 3
  frames, recovers to baseline within ~1 s
* **Shake**: emit `goat_bonked(10)` → shake energy > 0, decays to < 1% within
  `1 / SHAKE_DECAY` s
* **Kill switch**: `Config.CAM_FX = false`, repeat bob test → variance exactly 0,
  `fov == FOV_BASE`, local transform identity

**User-side (the real gate — this is the *feel* phase, round two):**

* [ ] Run on grass — bob says "alive", not "trampoline"
* [ ] Full downhill — FOV widens; speed *feels* earned
* [ ] Cross a steep side-slope — horizon tilts with the terrain
* [ ] Carve snow at speed — leans in; mouse-only turns don't
* [ ] Ledge-hopping — pop → fall drift → dip reads as one motion
* [ ] One big cliff drop — dip + shake scale with the F3 impact number
* [ ] Charge a wall — single kick, gone fast
* [ ] Horns steady in frame through *all* of the above (D2's payoff)
* [ ] Flip `CAM_FX` off mid-run — exact Phase 3 tripod feel returns (and feels
      *worse* now — that's the point)
* [ ] 10 minutes continuous play — zero nausea; if any, halve amplitudes first

**All boxes → write `phase-4-completion.md`.**

⏱ ~60 min

---

## Effort summary

| Step | | Time |
|---|---|---|
| 1 | State plumbing (vy_world, signals) | ~45 min |
| 2 | Bob + FOV kick | ~60 min |
| 3 | Slope tilt + carve lean | ~45 min |
| 4 | Jump/land/fall dynamics | ~60 min |
| 5 | Collision shake | ~45 min |
| 6 | Verification | ~60 min |
| | **Total** | **~5–5.5 h** |

---

## Risks & notes

* **The Head-rotation wipe (why D1 exists)** — `head_camera.gd` sets
  `Head.rotation = Vector3(_pitch, 0, 0)` on *every mouse event*. Any effect placed
  on `Head` survives exactly zero mouse pixels. `Camera3D` is the only safe offset
  home; do not "simplify" this later into Head.
* **Motion sickness is the failure mode of this phase** — every amplitude above is
  a first guess tuned for *subtle*. Order of operations when it feels wrong: halve
  amplitudes → lower tilt caps → slow bob rate → only then touch the spring consts.
* **Physics/process jitter** — FX run in `_process` reading physics-tick state.
  Speeds and slopes change slowly, so this is safe; if heading-rate sampling (Step 3)
  jitters at 60 Hz physics, smooth the heading before differentiating, don't move
  the FX into `_physics_process`.
* **`vy_world` derivation** — one-line position delta per physics tick; keep it in
  the controller (it owns `_last_y`), camera just reads the dict. Don't
  double-derive it in the camera (frame timing differs → wrong numbers).
* **FOV vs. horn framing** — horns sit close to the near plane (`near = 0.05`);
  wide FOV stretches frame edges where the horn tips live. If tips distort at
  `FOV_MAX`, pull `HORN_LENGTH`/positions in before capping FOV lower.
* **Scope creep via "while we're here"** — no movement numbers change in Phase 4.
  If a feel problem traces to the *controller* (e.g. slide authority), it's a
  Phase 3 tunable — fix it there, note it in the completion doc.
* **Bonk false positives** — steep-but-climbable faces are floors, not walls
  (`floor_max_angle` handles it); the near-horizontal-normal check must reject
  floor contacts explicitly or every steep climb will rattle.

---

## Handoff → Phase 5

Phase 5 target (per `README.md`): *the realistic alpine mountain* — terrain art,
vegetation, fog, and the deferred **ragdoll** (D8 of Phase 3).

Already in place for it:

* Camera FX are pure local offsets — a ragdoll-follow mode (Phase 5's hardest
  camera problem) can blend them out via the existing `CAM_FX` path
* `goat_landed` impact pipeline + shake scale with whatever terrain throws at it
* Vertex-color surfacing already classifies visually — Phase 5's real materials
  key off the same `Surface` enum
* Known gaps to carry: bonk normals aren't passed with the signal (add when
  ragdoll needs direction); `FOV_BASE` duplicated between `goat.tscn` (initial)
  and `Config` (runtime) — harmless, but tidy it when the scene next changes
