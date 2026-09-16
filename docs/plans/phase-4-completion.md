# ✅ Phase 4 — First-Person POV: Completion Report

> Companion to `phase-4-first-person-pov.md` (execution plan). Records what was
> actually built, verification evidence, bugs found, and deviations. Phase 4 is
> **complete pending the user-side `F5` feel pass** listed at the bottom.

---

## Summary

| Step | Planned | Outcome |
|---|---|---|
| 1 | Camera state plumbing | ✅ `vy_world` (fixes the carried Phase 3 quirk), `goat_jumped` + `goat_bonked(impact)` signals, wall-bonk scan, `get_debug_state()` extended (old keys untouched) |
| 2 | Bob + FOV kick | ✅ `camera_fx.gd` on `Camera3D`: double-beat gallop bob (rate ∝ speed, grounded only, eased), FOV 78→88 across 8→20 m/s |
| 3 | Slope tilt + carve lean | ✅ tilt from floor normal vs view (≤ 6°, ×1.5 in slide), lean ∝ smoothed heading-rate × speed (carve-only, not mouse) |
| 4 | Jump/land/fall dynamics | ✅ spring-damper dip + pitch: jump pop (`goat_jumped`), impact-scaled landing dip (`goat_landed`), vy_world fall drift |
| 5 | Collision shake | ✅ trauma² model, desynced sine channels, fed by `goat_bonked` + stumble landings, strict decay |
| 6 | Verification | ✅ 23/23 headless checks PASS (evidence below) |

Steps 2–5 shipped as **one coherent script build** (the Phase 3 deviation
pattern — the channels share springs and the grounded blend, so split landings
would have been throwaway glue).

---

## Decisions locked

All ten plan decisions held. Two refinements:

| # | Decision | Value |
|---|---|---|
| D1 | Effects on `Camera3D`, never `Head` | ✓ `head_camera.gd`'s absolute rotation writes are why |
| D2 | Horns inherit all offsets | ✓ they stay children of `Camera3D` — pinned in frame, zero work |
| D3 | One state dict, two consumers | ✓ overlay + camera read the same `get_debug_state()` |
| D4 | Additive local offsets only | ✓ single compose write point in `_process` |
| D5 | Sines + spring-dampers, no Tweens | ✓ everything state-driven and headless-testable |
| D6 | Bob: rate ∝ speed, grounded only | ✓ phase truly freezes in air |
| D7 | Slope tilt + carve lean | ✓ carve-only lean confirmed by design (heading-rate source) |
| D8 | Jump pop / landing dip / fall drift | ✓ fall drift runs on `vy_world` — the quirk fix pays off |
| D9 | Trauma² shake | ✓ one system, two doors (bonk + stumble landing) |
| D10 | Kill switch + FOV kick | ✓ `CAM_FX` (static var — see Deviation 2) |
| + | Spring impulses are velocity kicks | plan's ~0.06 m figures read as *peak offsets*; with k=220 the kicks are DIP_JUMP 0.75 / DIP_LAND 2.2 m/s |
| + | F3 overlay gained an `fx` line | fov / trauma / dip live — feel-tuning instrumentation |

---

## Files created / changed

```text
scripts/player/camera_fx.gd        # NEW (+.uid) — all Phase 4 channels, ~230 lines
scripts/player/goat_controller.gd  # EDIT — vy_world (_last_y), _floor_n state,
                                   #       goat_jumped emit, wall-bonk scan,
                                   #       get_debug_state() +4 keys
scripts/game/event_bus.gd          # EDIT — +goat_jumped, +goat_bonked(impact)
scripts/game/config.gd             # EDIT — v0.4.0; +CAM_FX, FOV_*, BONK_MIN_SPEED,
                                   #       +22 camera tunables (bob/tilt/lean/
                                   #       dip/fall/shake groups)
scripts/utils/debug_overlay.gd     # EDIT — fx readout line
scenes/goat/goat.tscn              # EDIT — camera_fx.gd on Camera3D
```

Deleted after use (temp verification): `scripts/utils/phase4_smoke.gd` (+`.uid`).

---

## Verification evidence

```text
$ godot --headless --path . --import                  → 0 errors
$ godot --headless --path . --quit-after 60           → 0 errors/warnings

$ godot --headless --path . --script .../phase4_smoke.gd
  ok   settle: speed < 0.1 at spawn            (Phase 2 regression)
  ok   idle: fov == FOV_BASE / position ~ zero / tilt bounded
  ok   jump: vy > 3 on press  +  goat_jumped fired
  ok   coyote: vy > 3 after late press         (Phase 3 regression)
  ok   landing: goat_landed impact > 12  +  STUMBLE entered
  ok   fall: vy_world tracks real descent      (quirk fixed)
  ok   landing: camera dip < −0.02 m → recovers to ~ 0
  ok   shake: trauma ≈ 1 on bonk(10) → decayed to ~ 0 in 3 s
  ok   downhill run: speed > 10 with input     (Phase 3 regression)
  ok   fov: widened with speed, never exceeds FOV_MAX
  ok   bob: camera y variance while moving
  ok   slide: vy_world negative while sliding
  ok   kill switch: transform exactly identity + fov == FOV_BASE
PHASE4-SMOKE: PASS (5 landing impacts, 2 jumps)       → exit 0
```

What the key checks prove:

* **Idle = tripod** — speed 0 gives exactly zero offset; the kill switch gives
  *exactly* the Phase 3 feel (identity transform, not approximately)
* **Dip round-trip** — impact-scaled dip goes visibly negative and the spring
  settles back to ~0 (D5, no one-shot animations anywhere)
* **FOV discipline** — widens only above MOVE_SPEED (8), never exceeds 88
* **vy_world load-bearing** — tracks real descent in free fall *and* while
  floor-sliding (where `velocity.y` reads ≈ 0)
* **Regressions green** — settle / jump / coyote / downhill / landing all pass
  after the controller additions

---

## Bugs found & fixed (the honest log)

1. **`--script` mode compiles the entry script before autoload globals
   register** — the first smoke run failed with `Identifier not found: EventBus`
   in `goat_controller.gd` / `camera_fx.gd`, pulled in as compile-time
   dependencies (class_name references + literal `load()` paths) of the entry
   script; the goat then failed to instantiate and the coroutine died before
   `quit()`, hanging the run. **Fix:** the smoke fetches everything dynamically
   at runtime (no autoload identifiers, no game class_names, no constant-string
   loads, dynamically built resource path). This is *the* pattern for future
   `--script` smokes — documented in the script header before deletion.
2. **Coyote test defeated itself** — the teleport helper reset
   `_since_floor = 1.0` (stale-window hygiene), so the "late press" landed
   outside the window and correctly didn't jump. **Fix:** simulate "left the
   floor 50 ms ago" (`_since_floor = 0.05`) while genuinely airborne. Test
   fix only.
3. **FOV test expected the kick below its floor** — a no-input slide tops out
   ≤ 8 m/s = MOVE_SPEED, exactly where `smoothstep(8, 20, ·)` is still 0; fov
   staying 78.0 was *correct*. **Fix:** run the face with forward input
   (Phase 3's 18 m/s pattern). Test-calibration fix, no engine code touched.

---

## Deviations from plan

1. **Steps 2–5 shipped as one coherent `camera_fx.gd` build** instead of four
   landings — channels share the dip springs and grounded blend.
2. **`CAM_FX` is a `static var`, not a `const`** — the smoke test A/Bs the
   exact Phase 3 feel at runtime (kill-switch asserts need to flip it).
   F5 cannot toggle it live; if a runtime toggle is wanted later it's a
   one-line input hook.
3. **Two extra Config tunables** (`DIP_PITCH_JUMP`, `DIP_PITCH_LAND`) — the
   plan listed the dip springs' shared constants but the pitch impulses needed
   their own knobs.
4. **Grip-differential surface asserts not re-run** — controller edits this
   phase are purely additive (no movement-math changes); the smoke covers
   settle/jump/coyote/downhill/landing as the regression set.

---

## Open items (user side)

* [ ] `F5` feel pass (the real gate):
  * run on grass — bob says "alive", not "trampoline"
  * full downhill — FOV widens, speed feels earned
  * steep side-slope — horizon tilts subtly
  * carve snow — leans in; mouse-only turns don't
  * ledge-hops — pop → fall drift → dip reads as one motion
  * big cliff drop — dip + shake scale with the F3 impact number
  * charge a wall — single kick, gone fast
  * horns steady in frame through all of it
  * 10 min continuous — zero nausea (first lever: halve amplitudes)
* [ ] **Gate question:** animal bounding, or floating drone with legs?
* [ ] Tune with F3 (now shows `fx fov/trauma/dip`) — every number is a first guess
* [ ] Run the suggested commits
* [ ] `reffimg/` jpegs still untracked (pending since Phase 1)

---

## Handoff → Phase 5

Phase 5 target (per `README.md`): *the realistic alpine mountain* — terrain
art, vegetation, fog, and the deferred **ragdoll**.

Already in place for it:

* Camera FX are pure local offsets with a single kill path — a ragdoll-follow
  cam can blend them out via `CAM_FX`
* `goat_bonked` gates on `BONK_MIN_SPEED`; direction-carrying normals are a
  one-argument addition when ragdoll needs them
* The `Surface` enum still drives both grip and vertex colors — real materials
  key off the same classifier
* `FOV_BASE` is duplicated between `goat.tscn` (initial) and `Config` (runtime)
  — harmless; tidy when the scene next changes
