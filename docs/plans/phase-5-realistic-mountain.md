# 🏔️ Phase 5 — Realistic Mountain: Execution Plan

> Expands `README.md` → *Phase 5 — Realistic Mountain* into concrete, executable
> steps. The mission: **replace the prototype cone with a believable alpine
> environment** — the mountain itself becomes the antagonist.
> Carried debts landing here: ragdoll (Phase 3 D8 → tumble-lite, D6), directional
> bonk normals (Phase 4 handoff), FOV_BASE duplication tidy-up.
>
> ⚠️ **Art-direction note:** the `reffimg/` references could not be machine-read
> this session — so every look parameter below is a **tunable first guess** and
> the references gate the phase via the user-side checklist (D8). "Look like the
> references" is an eyeball verdict, never a headless assert.

---

## Goal

```text
Phase 2-4 prototype (one smooth noise cone, flat vertex colors)
        ↓
Terrain v2: bigger, domain-warped, cliff bands, narrow ledges
        ↓
Surface look v2: slope/altitude blending, snow on flats, strata hints
        ↓
Vegetation: MultiMesh pines / rocks / grass in believable clusters
        ↓
Atmosphere: valley mist, drifting clouds, fake distant peaks, water glinting
        ↓
Crash tumble (ragdoll-lite) + directional camera response
        ↓
A MOUNTAIN YOU BELIEVE 🏔️🌲🌫️
```

**Definition of done:** on `F5` — the environment reads as a real alpine
mountain at a glance against `reffimg/`; trees cluster where trees would grow;
cliffs and ledges are visible and *playable*; fog gives depth; water glints in
valleys; a high-speed crash tumbles and recovers; 60 FPS feel on desktop
Chrome. Headless: terrain API regression + Phase 2/3/4 suites green, zero
errors.

---

## Decisions locked in Phase 5

| # | Decision | Choice | Why |
|---|----------|--------|-----|
| D1 | Scope | **One hero mountain, grown** (512→1024 m, peak ~130→260 m) — not a range; distant peaks are a fake backdrop | README MVP letter: *one* realistic mountain. A range multiplies cost, splits perf budget, helps nothing yet. |
| D2 | Terrain structure | **Domain-warped ridged fBm + quantized cliff bands + ledge carving**, grid 128→**192** (256 only if collision cook stays web-sane) | Bands and ledges are the README's "cliffs, rock faces, narrow ledges" — cheap in noise, expensive only in tuning. **API frozen:** `get_height_at` / `surface_at` / `slope_deg_at` / `downhill_dir` signatures unchanged; spawn blend stays the *final* gate so the spawn disc survives the warp. |
| D3 | Look pipeline | **100% procedural** — vertex colors v2 + one spatial shader (slope/altitude blend, snow-on-flats, strata hint) | Zero assets = tiny web build, no pipeline, seedable. `gl_compatibility`-safe features only. |
| D4 | Vegetation | **Procedural meshes + MultiMeshInstance3D per type** (pine = trunk + 3 cones; rock = deformed icosphere; grass = crossed quads), placed by the *same* surface classifier + slope/altitude rules + cluster noise | 1 draw call per type (web perf); placement code reuses the classifier so trees never grow where grip says they can't. Counts capped in Config. |
| D5 | Atmosphere & water | **Altitude fog curve** (valley mist), **~8 drifting alpha-billboard clouds**, **low-poly distant-peak ring** beyond playable radius, **one global animated water plane** at valley level (visual only) | Depth cues sell scale for near-zero cost. Water has no gameplay in v1 — goat wades visually; swim mechanics are a later-phase question. |
| D6 | Ragdoll → **tumble-lite** | Airborne bonk/wall hit above a speed threshold → **TUMBLE state**: goat `Body` spins with angular velocity, input authority 0; grounded + slow → STUMBLE recovery. `goat_bonked` gains a **direction** argument (Phase 4 handoff). Camera: trauma + directional kick via the existing `CAM_FX` offset path | True skeletal ragdoll needs a real goat model — we still have boxes. Tumble gives the *consequence* (crash → chaos → recover) without the model dependency. |
| D7 | Physics untouched | Movement math, grip bands, coyote/jump/stumble paths unchanged; TUMBLE is a new state carved alongside, reusing STUMBLE's recovery | The verified Phase 2/3/4 behavior is the regression gate; this phase must not destabilize it for art. |
| D8 | Art direction is user-gated | References are a **direction, not a contract**: every look number tunable, first-guess values in-doc; the F5 checklist compares against `reffimg/` and steers | "Looks like the reference" cannot be asserted headless (and the refs weren't machine-readable this session). Timebox per step; resist the realism ratchet. |
| D9 | Perf budget (web) | 60 FPS desktop Chrome @1080p: one directional light, shadow distance capped, grass tufts cast **no** shadows, fog as the far-plane helper, no post-FX | Compatibility renderer + browser GPUs. Headless proves *structure* (instance counts, draw setup, zero errors); FPS itself is F5-verdict. |
| D10 | Scene hygiene | Kill the `FOV_BASE` duplication (`goat.tscn` initial vs `Config`) while scenes are open anyway | Phase 4 handoff note; two sources of truth always bite later. |

**Out of scope (later phases):** race/checkpoint placement (6), AI goats (7),
obstacle gameplay like falling rocks (8), tricks (9), any audio (12), LOD
passes beyond MultiMesh caps (13), mobile (13/14), swimming mechanics, a real
goat model / skeletal ragdoll.

---

## Step 1 — Terrain v2: shape

**Files:** `scripts/terrain/terrain_generator.gd` (rework `_height_at` +
`_build`), `scenes/terrain/mountain_level.tscn` (bounds), tunables at the top
of the generator.

**Do:**

* Size 512→1024, peak ~260, grid 128→192 (`@export`, so tuning needs no code)
* **Domain warp**: ridge/detail noise sampled at warped coordinates
  (`warp(x,z)` from a second low-frequency noise) → ridges stop feeling
  radar-cone regular
* **Cliff bands**: height quantization in the mid-altitude rock zone — smooth
  steps of ~8–15 m with steep risers → walkable bands separated by faces
  (45–55° stays climbable-with-speed, > 55° walls — the bands feed the existing
  steep mechanics for free)
* **Ledges**: where band risers meet the ridge noise, carve narrow shelf
  overhangs (ledge width tunable, 2–4 m first guess)
* Spawn blend applies **last** (after warp/bands) — the disc stays a pure 27°
  rock cone; verify `surface_at` there still returns ROCK
* Keep the trimesh-from-mesh single source (Phase 2 lesson); print build time +
  tri count at generation for the web load-time ledger

**Done when:** headless regression green (settle/jump/downhill/landing); F5:
bands + ledges visible on the mountain flanks; spawn holds still; no falling
through (trimesh intact).

**Commit checkpoint:** `feat: structured alpine terrain v2 (warp, cliff bands, ledges)`

⏱ ~90 min

---

## Step 2 — Surface look v2: materials that agree with physics

**Files:** `terrain_generator.gd` (classification bands + colors), new
`shaders/terrain_blend.gdshader` + material hookup in `_make_mesh`, `config.gd`
(look tunables if shared).

**Do:**

* Extend color logic into the shader: **slope/altitude blending** instead of
  hard vertex bands (grass→scree→rock transitions over ~10° / ~15 m)
* **Snow accumulation**: flat + high = thick snow; steep faces shed to rock —
  drive from the same slope/height inputs (visual snow ≠ grip snow is
  FORBIDDEN: both read the classifier's zone rules, D7's little brother)
* **Strata hint**: faint horizontal banding in rock zones (cheap noise in the
  shader — sells "rock face")
* Ice patches: keep the mask, boost the wet-specular look
* Vertex colors stay as blend *weights* where useful (classifier still owns
  truth)

**Done when:** no hard color seams at band boundaries; steep gullies read as
rock, flats above the snow line read as deep snow; grip still matches what you
see (F3 cross-check while running the same line).

**Commit checkpoint:** `feat: slope/altitude material blending with snow accumulation`

⏱ ~75 min

---

## Step 3 — Vegetation: pines, rocks, grass

**Files:** new `scripts/terrain/vegetation.gd` (+ meshes built in code),
`mountain_level.tscn` (node), `config.gd` (density caps).

**Do:**

* Procedural meshes: **pine** (cylinder trunk + 3 stacked cones, slight random
  lean/scale per instance), **rock** (icosphere, vertices jittered by hash —
  instanced variety), **grass tuft** (2 crossed quads, alpha or plain color)
* `MultiMeshInstance3D` per type; per-instance `Transform` + color variance via
  instance `COLOR` (gl_compatibility supports it)
* **Placement rules** (all derived from existing APIs, no new truth):
  * pine: GRASS zone, slope < 25°, altitude < snow line − 10 m, cluster noise
    mask (groves, not carpet), min spacing
  * rock: ROCK zone or slope > 35°, sparser, cluster noise
  * grass tufts: GRASS, slope < 30°, high count but shadow-off
* Caps in `Config` (first guesses: ~800 pines, ~400 rocks, ~3000 tufts);
  print totals at build
* Vegetation is **visual only** v1 — no collision (trimesh untouched); note for
  Phase 8 which will make obstacles real

**Done when:** trees cluster on gentle grass shelves, never on cliffs/ice/snow;
counts under caps; one draw call per type shows in the F3/metrics; FPS feel
unchanged on the walk-around.

**Commit checkpoint:** `feat: procedural vegetation (MultiMesh pines, rocks, grass)`

⏱ ~90 min

---

## Step 4 — Atmosphere & water

**Files:** `mountain_level.tscn` (Environment tweaks), new
`scripts/terrain/atmosphere.gd` (clouds + distant peaks), new
`shaders/water.gdshader` + water plane, `config.gd`.

**Do:**

* **Fog curve**: density scales with camera altitude via a small script
  (valley mist thick, above the snow line thin) — replaces the flat 0.003
* **Clouds**: ~8 large soft alpha billboards (unshaded, `Billboard` + slow
  drift), placed in a loose ring at ~1.5× peak height
* **Distant peaks**: low-poly cone cluster ring at ~1.3–1.8× terrain radius,
  fog-faded so they read as miles away; zero collision, zero interaction
* **Water**: one big plane at the valley water level (tune ~6 m), animated
  shader (scrolling normals fake + fresnel-ish tint), transparent; goat wades
  visually — no gameplay hook yet
* **D10 tidy:** kill the `FOV_BASE` duplication (scene reads it from Config or
  stays in lockstep comment) while the scene file is open

**Done when:** valley approaches mist over; horizon shows layered peaks;
water glints in the valley bottoms from altitude; no transparency sorting
weirdness against fog; screenshots compared to `reffimg/` by you.

**Commit checkpoint:** `feat: atmosphere (fog curve, clouds, distant peaks) + valley water`

⏱ ~75 min

---

## Step 5 — Crash tumble (ragdoll-lite) + directional bonks

**Files:** `goat_controller.gd` (TUMBLE state), `event_bus.gd` (bonk gains
direction), `camera_fx.gd` (directional kick + blend), `goat.tscn`, `config.gd`.

**Do:**

* `goat_bonked(impact, direction)` — controller passes the collision normal's
  horizontal component (Phase 4 handoff debt); update camera subscriber
* **TUMBLE trigger**: airborne AND bonk impact > `TUMBLE_MIN_IMPACT` (~10 m/s)
  → TUMBLE: input authority 0, `Body` node spins (integrate angular velocity
  from the bonk direction — the *visual* body rotates, the capsule transform
  stays upright so physics stays sane)
* **Recovery**: grounded AND speed < 2 → align body upright over ~0.3 s →
  STUMBLE (reuse the verified recovery beat) → control returns
* Camera: directional kick (translate offset along the bonk direction) + big
  trauma; fall-drift already handles the airborne nose-down
* Landing mid-tumble still fires `goat_landed` (impact pipeline unchanged)
* Tunables: `TUMBLE_MIN_IMPACT`, `TUMBLE_SPIN_MAX`, `TUMBLE_RECOVER_TIME`

**Done when:** charging a cliff wall mid-air at speed → visible tumble,
chaotic camera, hard landing, dazed recovery, controls back — the whole arc
reads in ~2 s and never soft-locks (worst case: slide to a stop → recover).

**Commit checkpoint:** `feat: crash tumble state with directional camera response`

⏱ ~90 min

---

## Step 6 — Verification: regression + structure + the eyeball gate

**Headless (temp smoke, deleted after — and using the Phase 4 `--script`
lessons: fully dynamic runtime fetches):**

* **Terrain API compatibility**: `get_height_at` / `surface_at` /
  `slope_deg_at` / `downhill_dir` return sane values at a sample grid (no NaN,
  snow line respected, spawn disc = ROCK)
* **Full regression**: Phase 2/3/4 suite equivalents — settle / jump / coyote /
  downhill run / landing-stumble / camera idle + dip + shake + kill switch
* **Vegetation structure**: instance counts > 0 and ≤ caps; every pine placed
  on GRASS with slope < 25° (assert against classifier at N samples)
* **Tumble**: force a bonk mid-air → state TUMBLE → grounded + slow →
  STUMBLE → GROUND; control authority 0 during, 1 after
* **Water level sanity**: no water above the snow line; plane exists at valley
  bottoms
* **Load-time ledger**: terrain build + trimesh cook ms printed — the web
  budget's first data point

**User-side (the real gate — this is the art phase):**

* [ ] Compare against `reffimg/` side by side — closer than Phase 4's cone?
* [ ] Cliff bands, ledges, gullies readable at racing speed
* [ ] Trees cluster like a forest, not a grid; nothing grows on cliffs/ice
* [ ] Valley mist on descent; distant peaks layer the horizon
* [ ] Water glints in valleys (and goat wading looks acceptable v1)
* [ ] One deliberate cliff-face crash → tumble arc reads physical
* [ ] 10 min continuous run — 60 FPS *feel* on desktop Chrome, no stutter on
      vegetation transitions
* [ ] **Gate question:** does the mountain feel like a place, or a level?

**All boxes → write `phase-5-completion.md`.**

⏱ ~60 min

---

## Effort summary

| Step | | Time |
|---|---|---|
| 1 | Terrain v2 (shape) | ~90 min |
| 2 | Surface look v2 (shader) | ~75 min |
| 3 | Vegetation (MultiMesh) | ~90 min |
| 4 | Atmosphere + water | ~75 min |
| 5 | Tumble + directional bonks | ~90 min |
| 6 | Verification | ~60 min |
| | **Total** | **~8 h** |

---

## Risks & notes

* **Trimesh cook time at 192² (web load!)** — the biggest silent risk. Measure
  from Step 1; if ugly: drop to 160², or split collision (full-res inside the
  playable radius, simplified/no collision beyond). The load-time ledger exists
  so this never surprises us at Phase 14.
* **Domain warp vs. the old feel** — warp changes where steep/flat live; the
  ice mask, snow line, and slide-band tuning were calibrated on the old cone.
  Expect one re-tune pass; keep everything seedable.
* **The realism ratchet** — D8 is the defense: timebox each step, references
  are direction not contract. A believable mountain this phase; a *beautiful*
  one is what Phase 12/13 polish is for.
* **Visual snow must equal grip snow** — the moment the shader invents its own
  snow rules, the game lies about friction. Both read the classifier (Step 2's
  hard rule).
* **Tumble vs. verified physics** — the capsule transform stays upright; only
  the visible `Body` spins. If tumble misbehaves, it can be feature-flagged off
  without touching movement code.
* **Water plane quirks** — gl_compatibility transparency + fog can interact
  oddly; if it fights, drop fresnel, keep plain scroll. Goat-underwater camera
  is out of scope (kill plane is far below; wading depth is shallow).
* **Vegetation without collision** — deliberately visual v1; Phase 8 makes
  obstacles real. Note it in the completion doc so future-us doesn't "find"
  this bug.
* **Spawn disc integrity** — Phase 3's bug 3 (spawn must hold still) gets
  re-verified after every terrain change; it's regression check #1 for a
  reason.

---

## Handoff → Phase 6

Phase 6 target (per `README.md`): *the race system* — countdown, checkpoints,
timer, position, finish, restart.

Already in place for it:

* Terrain API (`get_height_at`, `downhill_dir`) is checkpoint-placement-ready
  and frozen — race nodes can sit on any x,z with a height query
* Seedable noise everywhere → a race-line exclusion mask can join the
  vegetation placement without touching the classifier
* The distant-peak ring marks the playable boundary — course design knows
  where the world ends
* `EventBus` already carries the race signals (`race_started`,
  `race_finished`) — Phase 6 fills the other side
* Known gaps to carry: water has no gameplay; vegetation has no collision
  (Phase 8); tumble needs a real ragdoll whenever a real goat model lands
