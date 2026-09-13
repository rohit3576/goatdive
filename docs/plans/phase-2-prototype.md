# 🏔️ Phase 2 — First 3D Prototype: Execution Plan

> Expands `README.md` → *Phase 2 — First 3D Prototype* into concrete, executable steps.
> Covers README development-order items **2–6**: 3D terrain → goat → goat physics → first-person camera → downhill movement.
> Goal quote: *"You can run a goat down a basic mountain."*

---

## Goal

```text
Procedural mountain terrain
        ↓
Placeholder goat (CharacterBody3D)
        ↓
Gravity + movement + jump + collision
        ↓
First-person camera (mouse look)
        ↓
Horns visible in POV
        ↓
Downhill acceleration + restart
        ↓
FIRST PLAYABLE SLICE 🐐⬇️
```

**Definition of done:** `F5` → you stand on a mountain peak in first person, horns framing the view, run downhill and accelerate, jump off ledges, fall and respawn, press `R` to restart. Zero script errors.

---

## Decisions locked in Phase 2

| # | Decision | Choice | Why |
|---|----------|--------|-----|
| D1 | Terrain source | **Procedural FastNoiseLite, generated at runtime** | Code-only, no binary assets, seedable, reproducible. Sculpting/import comes in Phase 5 if needed. |
| D2 | Terrain collision | **HeightMapShape3D** | Built for heightfields; cheaper and more stable than trimesh for terrain. |
| D3 | Goat physics body | **CharacterBody3D + `move_and_slide()`** | Built-in floor detection, slope handling, slide — exactly the Phase 3 foundation. |
| D4 | Goat visual | Placeholder capsule + boxes | No model work yet; art is Phase 5. Must not block physics iteration. |
| D5 | Horns | **Procedural curved ArrayMesh** swept along a Bézier, parented to the camera | Zero assets, instantly iteratable, visible in POV. Replaced by real model later. |
| D6 | Camera | `Camera3D` on a `Head` node; mouse look with captured mouse | Basic look only — bob/tilt/shake are Phase 4. |
| D7 | Restart | `get_tree().reload_current_scene()` + respawn on fall below kill plane | Simplest loop that lets physics iterate fast. |
| D8 | Terrain scale | **512 × 512 m, ~130 m peak, 128² grid** (~16.6 k verts) | ~30–40 s downhill run at realistic goat speeds; trivial perf load. |
| D9 | Movement numbers | Walk 8 m/s, downhill cap 20 m/s, jump 4.5 m/s, air control ×0.3 — all in `Config` | One source of truth; tuning is Phase 3's job, not scattered magic numbers. |

**Out of scope (later phases):** realistic mountain art (5), head bob/camera feel (4), finish line & race loop (6), AI goats (7), tricks (9), audio (12), sliding-on-steep and ragdoll (3 — Phase 2 only needs *running* to feel right).

---

## Step 1 — Terrain generator + mountain level scene

**Files:**

* `scripts/terrain/terrain_generator.gd` — static builder
* `scenes/terrain/mountain_level.tscn` + `scenes/terrain/mountain_level.gd` — level root
* `scenes/terrain/README.md` — replaced by real content

**Do:**

* `terrain_generator.gd`:
  * FastNoiseLite: fBm ridged noise for detail × radial cone falloff for the mountain mass → heights array
  * Constraint: main descent line stays **20–40°** (steeper than `floor_max_angle` ≈ 45° becomes a wall — see Risks)
  * Build `ArrayMesh` (normals computed) for visuals + `HeightMapShape3D` from the same heights for collision — one source, two consumers
  * Expose `seed`, `size`, `peak_height`, `grid` as parameters
* `mountain_level.tscn`: level root + `WorldEnvironment` (sky, **distance fog**) + `DirectionalLight3D` + `StaticBody3D` named `Terrain` with the generator script
* `mountain_level.gd`: computes spawn point (sample terrain height near peak, face downhill via gradient), stores it for the goat + respawn

**Done when:** `F5` shows a fogged mountain you can walk on (after Step 2; scene alone must at least render error-free in a headless `--quit-after` run).

**Commit checkpoint:** `feat: procedural mountain terrain + level scene`

⏱ ~60–90 min

---

## Step 2 — Goat body + controller physics

**Files:**

* `scenes/goat/goat.tscn` + `scripts/player/goat_controller.gd`
* `scripts/game/config.gd` — extend with new tunables

**Scene:**

```text
Goat (CharacterBody3D)  ← goat_controller.gd
├── CollisionShape3D    (capsule r=0.35, h=1.0 — D5 units)
├── Body                (placeholder boxes: torso + snout)
└── Head (Node3D, front-top of body, ~0.85 m)
    ├── Camera3D        (Step 3)
    └── Horns           (Step 4)
```

**Do — `goat_controller.gd` (extends CharacterBody3D):**

* **Gravity:** not on floor → `velocity += Vector3.DOWN * Config.GRAVITY * delta`
* **Ground movement:** input dir (camera-relative, from existing `move_*` actions) → accelerate toward `dir * Config.MOVE_SPEED`
* **Downhill acceleration (the core feel):** on floor, project gravity onto the floor plane — `g_proj = Vector3.DOWN - n * (Vector3.DOWN · n)` where `n = get_floor_normal()` — add `g_proj * delta` above a small slope threshold, cap horizontal speed at `Config.MAX_DOWNHILL_SPEED`
* **Jump:** on floor + `jump` pressed → `velocity += floor_normal-ish * Config.JUMP_VELOCITY` (use UP for now)
* **Air control:** reduced input authority (×`Config.AIR_CONTROL`) while airborne
* **Config additions:** `MAX_DOWNHILL_SPEED := 20.0`, `AIR_CONTROL := 0.3`, `SLOPE_ACCEL_MIN_DEG := 5.0`

**Done when:** goat stands on the peak without sliding, WASD moves camera-relative, Space jumps, running downhill visibly outruns flat ground.

**Commit checkpoint:** `feat: goat body + movement physics with downhill acceleration`

⏱ ~90 min

---

## Step 3 — First-person camera + mouse look

**Files:** `scripts/player/head_camera.gd` (on `Head`), small edit in `goat_controller.gd`.

**Do:**

* Mouse look: yaw on the goat body (`rotate_y`), pitch on `Head` (clamped ±80°), sensitivity from `Config.MOUSE_SENS` (~0.003 rad/px)
* Capture flow: click window → `MOUSE_MODE_CAPTURED`; `pause` action (already wired in `main.gd`) → released. Look input ignored while uncaptured
* `FOV 78`, near plane 0.05 (horns are close)
* Goat body yaws toward camera direction so movement stays camera-relative

**Done when:** you can look around smoothly from the goat's head; horns-in-frame feel believable; no motion without mouse.

**Commit checkpoint:** `feat: first-person head camera with mouse look`

⏱ ~30 min

---

## Step 4 — Horns in POV

**Files:** `scripts/utils/horn_mesh.gd` — static `build(length, curvature, rings)` returning an `ArrayMesh`.

**Do:**

* Sweep a tapering circle (r 0.06 → 0.01) along a backward-curving Bézier — two instances parented to `Camera3D`, positioned lower-left / lower-right of frame (e.g. x ±0.22, y −0.18, z −0.45), splayed outward
* Surface material: bone-ish off-white, roughness high
* Dimensions in `Config` (`HORN_LENGTH := 0.35`) — needs instant tuning

**Done when:** both horns frame the view at all times without blocking it; they feel goat-like at a glance.

**Commit checkpoint:** `feat: procedural POV horns`

⏱ ~45 min

---

## Step 5 — Restart, respawn, level wiring

**Files:** edits in `goat_controller.gd`, `mountain_level.gd`, `main.gd`.

**Do:**

* `restart` action → `get_tree().reload_current_scene()` (replace the Phase 1 print stub)
* Kill plane: `global_position.y < Config.KILL_Y` (−50) → respawn at level spawn point
* `main.gd`: default level switches `test_level.tscn` → `mountain_level.tscn` (keep `test_level.tscn` as a sandbox)
* Print stub removed; `GameState.current_scene_path` updated by `SceneLoader`

**Done when:** full loop works — spawn, run down, fall off, respawn, `R` restarts everything.

**Commit checkpoint:** `feat: restart + respawn loop, wire mountain as default level`

⏱ ~30 min

---

## Step 6 — Verification

**Headless (automated):**

* `--quit-after` run of `mountain_level`: zero errors, goat spawns at terrain height (not floating/falling forever)
* Temp smoke script (deleted after, like Phase 1): simulate physics for N frames → assert goat `is_on_floor()` after settling; force `jump` → assert height above terrain increases; spawn on slope → assert horizontal speed grows in downhill direction

**User-side (the point of Phase 2):**

* [ ] `F5` → standing on peak, horns visible, fog + sky
* [ ] Run downhill → clear acceleration beyond flat-ground speed
* [ ] Jump works from ground; air control is reduced but present
* [ ] Falling off → respawn; `R` → fresh restart; `Esc` releases mouse
* [ ] **The feel question:** is running-down-this-mountain fun yet? (informs Phase 3 tuning priorities)

**All boxes → Phase 2 complete → write `phase-2-completion.md`.**

⏱ ~30 min

---

## Effort summary

| Step | | Time |
|---|---|---|
| 1 | Terrain + level | ~60–90 min |
| 2 | Goat physics | ~90 min |
| 3 | FP camera | ~30 min |
| 4 | Horns | ~45 min |
| 5 | Restart/respawn | ~30 min |
| 6 | Verification | ~30 min |
| | **Total** | **~5 h** |

---

## Risks & notes

* **Slope > ~45° = wall.** `move_and_slide()` treats floors steeper than `floor_max_angle` as walls. The terrain generator must shape the main descent to 20–40°; steep cliffs exist visually but the runnable line must stay under the limit. (Phase 3 makes steep = slide instead of wall.)
* **`HeightMapShape3D` input order** — heights are a flat `PackedFloat32Array` in row-major width×depth order; mismatches silently scramble collision. Test by walking, not just looking.
* **Horn placement is a framing problem, not a mesh problem** — budget time for per-eye tweaking (x/y/z, splay) via `Config` values, not scene edits.
* **Headless physics tests validate math, not fun.** The F5 feel check is the real gate for this phase.
* **No ground check raycasts yet** — `is_on_floor()` from `move_and_slide()` is enough until Phase 3 surface detection.
* **Keep Phase 3 hooks in mind:** every magic number that felt like tuning goes into `Config` now — surface grip, slide thresholds, and coyote time arrive next phase.
