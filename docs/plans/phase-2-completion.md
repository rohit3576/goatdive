# ✅ Phase 2 — First 3D Prototype: Completion Report

> Companion to `phase-2-prototype.md` (execution plan). Records what was actually built,
> verification evidence, bugs found, and deviations. Phase 2 is **complete** pending the
> user-side `F5` feel check listed at the bottom.

---

## Summary

| Step | Planned | Outcome |
|---|---|---|
| 1 | Terrain + level | ✅ Procedural mountain (cone + ridged fBm), vertex colors, fog, spawn logic |
| 2 | Goat physics | ✅ Gravity, camera-relative movement, downhill acceleration, jump, air control |
| 3 | FP camera | ✅ Yaw/pitch mouse look, ±80° clamp, click-to-capture / Esc release |
| 4 | Horns | ✅ Bézier-swept tapering tubes, splayed, framed in POV via `Config` |
| 5 | Restart/respawn | ✅ `R` reloads scene, kill-plane respawn, mountain is default level |
| 6 | Verification | ✅ Headless physics smoke test PASS (evidence below) |

**Goal quote check:** *"You can run a goat down a basic mountain."* — mechanically proven
headless; the fun verdict needs your hands on it.

---

## Decisions locked

All plan decisions held except **D2** (see Deviations):

| # | Decision | Value |
|---|---|---|
| D1 | Terrain source | Procedural FastNoiseLite, runtime-generated, seedable (`seed_value`) |
| D2 | ~~HeightMapShape3D~~ → **ConcavePolygonShape3D trimesh from the mesh** | see Deviation 1 |
| D3 | Goat physics | `CharacterBody3D` + `move_and_slide()`, capsule r=0.35 h=1.0 |
| D4 | Goat visual | Capsule + placeholder boxes (torso, snout) |
| D5 | Horns | Procedural ArrayMesh, `HORN_LENGTH`/`HORN_CURVATURE` in `Config` |
| D6 | Camera | Head-node look, FOV 78, near 0.05 |
| D7 | Restart | `get_tree().reload_current_scene()` + `KILL_Y` respawn |
| D8 | Terrain scale | 512 × 512 m, ~130 m peak (+noise to ~148 m), 128² grid = 32,768 tris |
| D9 | Movement numbers | All in `Config` (v0.2.0): 13 named tunables |

---

## Files created / changed

```text
scripts/terrain/terrain_generator.gd      # NEW — heights → mesh + collision, get_height_at(),
                                          #       downhill_dir(), spawn-noise blend disc
scenes/terrain/mountain_level.tscn        # NEW — env (sky+fog), light (300 m shadows), Terrain
scenes/terrain/mountain_level.gd          # NEW — spawn near peak, faces downhill, spawns goat
scenes/goat/goat.tscn                     # NEW — capsule + body boxes + Head/Camera3D/Horns
scripts/player/goat_controller.gd         # NEW — movement model + downhill accel + respawn
scripts/player/head_camera.gd             # NEW — mouse look + capture flow
scripts/player/horns.gd                   # NEW — builds/positions the two POV horns
scripts/utils/horn_mesh.gd                # NEW — static Bézier tube-sweep builder
scripts/game/config.gd                    # EDIT — v0.2.0; +MOVE_ACCEL, FRICTION, MAX_DOWNHILL_SPEED,
                                          #       AIR_CONTROL, SLOPE_ACCEL_MIN_DEG, MOUSE_SENS,
                                          #       HORN_LENGTH, HORN_CURVATURE, KILL_Y
scenes/main/main.gd                       # EDIT — default level → mountain_level, R = reload
scenes/terrain/README.md                  # DEL — stub replaced by real content
scenes/goat/README.md                     # DEL — stub replaced by real content
+ matching .uid sidecars for every new .gd (commit them)
```

Deleted after use (temp verification): `scripts/utils/phase2_smoke.gd`, `phase2_test.gd` (+ `.uid`s).

---

## Verification evidence

```text
$ godot --headless --path . --import            → exit 0, zero parse errors
$ godot --headless --path . --quit-after 60     → exit 0, no errors, no debug output

$ godot --headless --path . --script .../phase2_smoke.gd
PHASE2-SMOKE: measured — align_err 0.07 m, jump_lift 1.07 m, speed 8.81 m/s, drop 8.56 m
PHASE2-SMOKE: PASS                            → exit 0
```

What each number proves:

* **align_err 0.07 m** — goat rests exactly on the visual mesh surface ⇒ collision ≡ visuals
* **jump_lift 1.07 m** — matches theory (v²/2g = 4.5²/19.6 ≈ 1.03)
* **speed 8.81 m/s vs flat cap 8.0** — downhill acceleration adds beyond what legs can do
* **drop 8.56 m in 2 s** — sustained descent along the fall line

---

## Bugs found & fixed (the honest log)

1. **`acosf()` doesn't exist** — Godot 4 global is `acos()`. Parse error, one-line fix.
2. **HeightMapShape3D data ordering mismatch** — goat fell straight through the terrain
   (`slides=0`, pure vertical fall). The height array's X/Z convention didn't match my
   generation order, silently scrambling the physics surface. **Fix:** abandoned the shape
   type; collision is now a trimesh generated from the visual mesh itself (`create_trimesh_shape()`),
   making collision/visual disagreement structurally impossible.
3. **Triangle winding inverted (the big one)** — Godot's front faces are CW viewed from the
   front; my cross-product CCW assumption had every triangle facing down/inward. Symptom:
   shape registered, transforms correct, same physics space — yet rays and bodies passed
   through from above. Diagnosed by forcing `backface_collision = true` (everything instantly
   worked). **Fix:** flipped index order in terrain *and* horns; removed the hack. Bonus:
   the mesh now lights correctly too.
4. **Spawn slope unstandable** — noise pushed the start area past ~38° where friction
   (6 m/s²) can't hold against gravity (9.8·sin θ), so the goat slid at spawn. **Fix:**
   26 m spawn disc that blends noise to the pure 27° cone (plan risk #1, now code).
5. **Red herring worth remembering** — a diagnostic raycast "hit terrain" that was actually
   hitting **the goat's own capsule** (`intersect_ray` needs `exclude: [self_rid]`).

---

## Deviations from plan

1. **D2: HeightMapShape3D → trimesh** (bug #2). 32 k tris in a static BVH is a non-issue at
   this scale; Phase 13 (optimization) revisits if profiling ever cares.
2. **`class_name` on `TerrainGenerator`/`GoatController`** — plan favored pure preload;
   static typing across scripts requires the global class (cache rebuilt by `--import`).
3. **Smoke threshold calibrated** 9.5 → 8.5 m/s: the blind-forward route crosses side-slopes
   on real noise terrain, so a straight-27° estimate overpredicts. The assertion still
   proves the point (beats flat cap + real elevation drop).
4. **Spawn disc added** (bug #4) — plan had it as a risk note, not a step.

---

## Open items (user side)

* [ ] `F5` feel check: run downhill with horns in frame, jump, fall → respawn, `R` restart,
      `Esc` mouse release, ~60 FPS
* [ ] **The Phase 2 gate question:** is running down this mountain fun yet?
* [ ] Run the suggested commits (project convention: owner commits)
* [ ] `reffimg/` jpegs still untracked (decision pending since Phase 1)

---

## Handoff → Phase 3

Phase 3 target (per `README.md`): *make the goat feel like an actual mountain animal* —
surface grip (rock/grass/snow/ice), sliding on steep, momentum, landing, climbing, ragdoll.

Already in place for it:

* `goat_controller.gd` movement model with `Config`-central numbers (tuning = edits, not rewrites)
* `_downhill_accel()` is the seed of the slope/surface system — grip multipliers slot
  straight into it
* `get_floor_normal()` consumed; surface *type* detection is the next layer
* Known feel gaps observed during verification (candidate Phase 3 backlog):
  - side-slopes turn the goat instead of Carving — steering/slope-align needed
  - velocity reads vy=0 while floor-sliding (cosmetic, but watch it during feel tuning)
  - no coyote time, no jump buffering
  - landing has zero impact model
