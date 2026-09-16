# ✅ Phase 5 — Realistic Mountain: Completion Report

> Companion to `phase-5-realistic-mountain.md` (execution plan). Records what
> was actually built, verification evidence, bugs found, and deviations.
> Phase 5 is **complete pending the user-side `F5` look + feel pass** at the
> bottom — this was the art phase; the eyeball gate outranks every assert.

---

## Summary

| Step | Planned | Outcome |
|---|---|---|
| 1 | Terrain v2 | ✅ 1024 m / 260 peak / 192² grid, domain warp, cliff bands + treads, spawn-blend as final gate, load ledger: **73,728 tris, ~210 ms build+cook** |
| 2 | Surface look v2 | ✅ `terrain_blend.gdshader`: zone stamp from `surface_at()` in COLOR.a, strata / scree tint / snow-on-flats / wet ice — shader shades *within* zones, never invents them |
| 3 | Vegetation | ✅ MultiMesh pines (195) / rocks (400) / tufts (1689), classifier-driven placement, spawn disc clear, 39 ms |
| 4 | Atmosphere + water | ✅ altitude fog curve, 8 drifting cloud billboards (procedural texture), 7 distant peaks, animated water plane @ 6 m; FOV_BASE duplication killed (D10) |
| 5 | Tumble + directional bonks | ✅ `goat_bonked(impact, direction)`, TUMBLE state (visible `Body` spins, capsule upright), recovery → STUMBLE handoff, camera directional kick |
| 6 | Verification | ✅ 30/30 headless checks PASS incl. full Phase 2/3/4 regression (evidence below) |

---

## Decisions locked

All ten plan decisions held. Refinements discovered during the build:

| # | Decision | Value |
|---|---|---|
| D1 | One hero mountain, grown | ✓ 512→1024, cone slope unchanged (27° by construction — spawn math survived free) |
| D2 | Terrain API frozen | ✓ signatures untouched; controller/camera/vegetation all consumed it unchanged |
| D3 | 100% procedural look | ✓ shader + vertex stamps; zero assets |
| D4 | MultiMesh vegetation | ✓ 1 draw call per type, instance-color variance, tufts shadowless |
| D5 | Atmosphere + water | ✓ water plane at 6 m — lake fringe appears wherever the toe dips below it |
| D6 | Tumble-lite | ✓ + `_enter_tumble()` doubles as the smoke-test entry point |
| D7 | Physics untouched | ✓ all movement math unchanged; TUMBLE is additive state |
| D8 | Art direction user-gated | ✓ every look number is an `@export` on the generator/atmosphere |
| D9 | Web perf budget | ✓ ~210 ms terrain cook, 3 vegetation draw calls, shadow caps respected |
| D10 | FOV_BASE single source | ✓ scene's initial `fov` removed; `camera_fx._ready` writes `Config.FOV_BASE` |
| + | Vegetation keeps a game-side placement record | headless-auditable + Phase 6 race-line fuel (see Bug 2) |

---

## Files created / changed

```text
scripts/terrain/terrain_generator.gd   # REWORK — v2 shape (warp/bands/ledges),
                                       #       look @exports, snow_line var,
                                       #       ShaderMaterial + zone-id alpha,
                                       #       load-time ledger print
shaders/terrain_blend.gdshader         # NEW — zone-stamped shading (D3's hard rule)
scripts/terrain/vegetation.gd          # NEW (+.uid) — MultiMesh scatter + placement record
scripts/terrain/atmosphere.gd          # NEW (+.uid) — fog curve, clouds, peaks, water
shaders/water.gdshader                 # NEW — scrolling ripples, ALPHA transparency
scripts/player/goat_controller.gd      # EDIT — TUMBLE state, _enter_tumble/_update_tumble,
                                       #       bonk direction emit, tumble gates on
                                       #       authority/jump/air-control, respawn reset
scripts/player/camera_fx.gd            # EDIT — directional bonk kick, FOV_BASE in _ready
scripts/game/event_bus.gd              # EDIT — goat_bonked gains direction argument
scripts/game/config.gd                 # EDIT — v0.5.0-phase5; VEG_* caps, TUMBLE_* group
scenes/terrain/mountain_level.tscn     # EDIT — Vegetation + Atmosphere nodes
scenes/goat/goat.tscn                  # EDIT — initial fov removed (D10)
```

Deleted after use: `scripts/utils/phase5_smoke.gd` (+`.uid`).

---

## Verification evidence

```text
$ godot --headless --path . --import                  → 0 errors
$ godot --headless --path . --quit-after 60           → 0 errors/warnings

TERRAIN: 193x193 heights, 73728 tris, build+trimesh ~210 ms   (web ledger)
VEGETATION: 195 pines / 400 rocks / 1689 tufts (caps 800/400/3000) in ~40 ms

$ godot --headless --path . --script .../phase5_smoke.gd
  ok  api sanity (40 random: heights/slopes/downhill) · band-tread flats (structured scan)
  ok  spawn disc ROCK · settle < 0.1 on v2 terrain
  ok  jump · goat_jumped · coyote · landing impact > 12 · STUMBLE · camera dip
  ok  downhill run speed > 10 on banded face · FOV widens, ≤ FOV_MAX
  ok  shake with direction: trauma 1 → 0 decay
  ok  vegetation: 2284 instances · placement record == count · sampled pines
      all GRASS · spawn disc clear
  ok  atmosphere: clouds + peaks + water · water plane @ 6 m, below snow line
  ok  tumble: forced entry → TUMBLE · body spins · jump blocked · recovers
      through STUMBLE → GROUND · body realigned upright
  ok  kill switch: identity transform + FOV_BASE (post-D10-tidy)
PHASE5-SMOKE: PASS (8 impacts, 2 jumps, 2284 veg instances)  → exit 0
```

---

## Bugs found & fixed (the honest log)

1. **Shader `TAU`** — Godot's shading language has `PI`, not `TAU`; strata
   math silently failed to compile. Fixed with a literal.
2. **Headless `--script` drops MultiMesh instance data** — the dummy
   RenderingServer doesn't back instance buffers: `set_instance_transform`
   reads back identity in every property-set order (probed A/B/C). NOT a
   game bug — real rendering is unaffected — but it means MultiMesh
   placement can't be audited through the server headless. **Fix:**
   vegetation records placements game-side (`get_placements(kind)`), which
   the smoke audits and Phase 6's race line will reuse.
3. **`render_mode transparent` doesn't exist** in Godot 4 spatial shaders —
   writing `ALPHA` is the transparency mechanism. Water shader compile
   failed until removed.
4. **`global_position` before `add_child`** — clouds/peaks errored
   `!is_inside_tree()`. Reorder.
5. **Godot 4 API nits** — no `ConeMesh` (tapered `CylinderMesh` instead);
   shadow enum is `SHADOW_CASTING_SETTING_*`; `PrismMesh` is not `ArrayMesh`.
6. **`downhill_dir` is degenerate on the new band treads** — perfectly flat
   surfaces have no downhill; `normalized()` of zero returns zero, which is
   honest. Callers: spawn-facing uses the cone (never flat) — safe. The
   smoke now treats zero-length as valid-flat. *Carried note for Phase 6:
   checkpoint placement must handle zero-downhill spots.*
7. **Pine starvation (17/800)** — the grass zone is a thin ring on a cone,
   and a slope < 25° filter fought the cone's 27° base slope. Loosened to
   28° (still under the 30° grass-classification ceiling) + 2× attempts →
   195. Caps are ceilings, not quotas — the ring is saturated, which is the
   ecologically correct outcome. Denser forest ⇒ flatter toe ⇒ cone-profile
   lever (D8 territory, F5 verdict).

---

## Deviations from plan

1. **Rocks are prisms, not jittered icospheres** — per-instance non-uniform
   squash + rotation reads boulder-ish without array surgery; flagged as a
   v1 simplification the F5 pass can reject.
2. **Pine trunks share the foliage material** (single-material MultiMesh);
   invisible at racing distance. Same F5 lever.
3. **Full-strength cliff banding occupies a mid-altitude slice** (ramps in
   55→105 m, fades 120→snow line) — deliberate relief, but it means exact
   flats are area-minor; if F5 wants bolder bands, widen the slice.
4. **Vegetation placement record** added (see Bug 2) — small API addition
   beyond the plan's "print totals".

---

## Open items (user side — the real gate)

* [ ] `F5` look pass **against `reffimg/`** (side-by-side):
  * closer to the references than the Phase 4 cone?
  * cliff bands / treads / gullies readable at racing speed?
  * treeline believable (groves, not grid; nothing on cliffs/ice)?
  * valley mist on descent · distant peaks layering the horizon · water glint
* [ ] `F5` feel pass: one deliberate mid-air cliff crash → tumble arc reads
      physical, never soft-locks; wall bonks kick directionally
* [ ] 10 min continuous run — 60 FPS *feel* on desktop Chrome
* [ ] **Gate question:** does the mountain feel like a *place*, or a *level*?
* [ ] Tune: every look number is an `@export` (terrain) or Config const;
      vegetation caps, band shape, fog curve, water level all first guesses
* [ ] Run the suggested commits
* [ ] `reffimg/` jpegs still untracked (pending since Phase 1)

---

## Handoff → Phase 6

Phase 6 target (per `README.md`): *the race system* — countdown, checkpoints,
timer, position, finish, restart.

Already in place for it:

* Terrain API frozen and regression-proven at the new scale — checkpoints
  can be placed with `get_height_at` + `downhill_dir` queries
* `Vegetation.get_placements()` exists — the race line can route around
  pines instead of through them
* `EventBus.race_started` / `race_finished(final_time)` signals have been
  waiting since Phase 1
* The distant-peak ring marks the world boundary; KILL_Y respawn exists
* Known gaps to carry: `downhill_dir` returns zero on band treads (checkpoint
  orientation needs a fallback); vegetation has no collision (Phase 8);
  water is visual-only; tumble needs a real ragdoll whenever a real goat
  model exists; band full-strength slice is narrow if the course wants
  long ledge runs
