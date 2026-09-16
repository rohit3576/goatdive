# ✅ Phase 3 — Goat Physics: Completion Report

> Companion to `phase-3-goat-physics.md` (execution plan). Records what was actually
> built, verification evidence, bugs found, and deviations. Phase 3 is **complete**
> pending the user-side `F5` feel pass listed at the bottom.

---

## Summary

| Step | Planned | Outcome |
|---|---|---|
| 1 | Surface classification | ✅ `Surface` enum + `surface_at()` + `slope_deg_at()`, ice patches via noise mask, vertex colors driven by the same classifier |
| 2 | Grip + carving | ✅ Controller rework: grip-scaled accel/brake/turn, heading-rotation carving |
| 3 | Steep bands | ✅ `floor_max_angle` 55°, slide state ≥ 42° (forced downhill, 0.3 authority), climb emerges from gravity projection |
| 4 | Jump/landing/stumble | ✅ Coyote + buffer (consumed on use), landing impact → `EventBus.goat_landed`, stumble > 12 m/s |
| 5 | Debug overlay | ✅ F3 readout: state / surface / slope / speed / vy / coyote / buffer |
| 6 | Verification | ✅ Full suite PASS incl. Phase 2 regression (evidence below) |

---

## Decisions locked

All nine plan decisions held. Two refinements discovered during verification:

| # | Decision | Value |
|---|---|---|
| D1 | Surface detection | Terrain-data classifier, shared by grip & vertex colors ✓ |
| D2 | Ice placement | Noise-masked patches in snow zone, pale blue tint ✓ |
| D3 | Grip model | One scalar per surface (1.0 / 0.85 / 0.5 / 0.25) ✓ |
| D4 | Steering | Carving — heading rotates at `TURN_RATE · grip`, speed survives turns ✓ |
| D5 | Steep bands | climb < 42° slide < 55° wall ✓ |
| D6 | Jump aids | Coyote 0.12 s + buffer 0.12 s ✓ |
| D7 | Impact response | > 12 m/s vertical → 0.4 s stumble, no damage system ✓ |
| D8 | Ragdoll | Deferred to Phase 5 ✓ |
| D9 | Debug overlay | F3 ✓ |
| + | **Spawn disc = bare rock** | see Deviation 2 |
| + | **Gravity projection corrected** | see Bug 1 — changes every downhill number |

---

## Files created / changed

```text
scripts/terrain/terrain_generator.gd   # EDIT — Surface enum, surface_at(), slope_deg_at(),
                                       #       ice-mask noise, colors from classifier,
                                       #       spawn disc classified ROCK
scripts/player/goat_controller.gd       # REWRITE — _horiz model, carving, slide state,
                                       #         coyote/buffer, landing/stumble,
                                       #         set_horizontal_velocity() + get_debug_state()
scenes/goat/goat.tscn                   # EDIT — floor_max_angle 0.9599 (55°), DebugOverlay node
scripts/game/config.gd                  # EDIT — v0.3.0; +GRIP_*, TURN_RATE, SLIDE/CLIMB_ANGLE,
                                       #         JUMP_COYOTE/BUFFER, STUMBLE_* (12 tunables)
scripts/utils/debug_overlay.gd          # NEW (+.uid) — F3 live physics readout
```

Deleted after use (temp verification): `scripts/utils/phase3_smoke.gd`, `phase3_test.gd` (+ `.uid`s).

---

## Verification evidence

```text
$ godot --headless --path . --import                  → exit 0, zero parse errors
$ godot --headless --path . --quit-after 60           → exit 0, zero errors

$ godot --headless --path . --script .../phase3_smoke.gd
PHASE3-SMOKE: jump_lift 1.07 | run speed 18.37 drop 9.75 | grass coast 9.7 m |
              ice coast 46.3 m | slide gain 5.32 m/s | coyote vy 4.34 | impact 25.2
PHASE3-SMOKE: PASS                                  → exit 0
```

What each number proves:

* **grass 9.7 m vs ice 46.3 m coast (4.8×)** — grip differential is real and large
* **run speed 18.37 m/s** (flat cap 8) — downhill acceleration properly forceful now
* **slide gain 5.32 m/s** — steep faces accelerate you with reduced control
* **coyote vy 4.34** — jump fires 3 ticks after leaving ground
* **impact 25.2 → state STUMBLE** — landing pipeline + EventBus wired
* **Phase 2 regression** (settle / jump / downhill) — still green after the rewrite

---

## Bugs found & fixed (the honest log)

1. **Latent Phase 2 gravity bug (the big one)** — the downhill projection used the
   *unit* `Vector3.DOWN` and never multiplied by `GRAVITY`, so downhill acceleration
   ran at ~10× reduced strength since the first prototype. It hid because friction
   numbers were tuned in the same broken world (friction "held" spawns it shouldn't
   have; the Phase 2 run test topped out at 8.81 and passed a threshold that was
   itself calibrated to the bug). Surfaced when the slide test refused to move:
   instrumented `g_h.length() = 0.498` where ~4.75 was expected. **Fix:** multiply
   the projected direction by `Config.GRAVITY`. Every downhill number changed
   (18.37 m/s runs, slides that slide).
2. **Steep-point finder had no upper bound** — the slide test first teleported the
   goat onto a > 55° face (a wall); it fell to the base and sat still (gain 0.00).
   **Fix:** search band 45–52°. Test-calibration fix, no engine code touched.
3. **Spawn would slide under corrected gravity** — the spawn disc (27° cone) classifies
   as snow at ~118 m altitude; with real gravity, snow grip (0.5 → friction 3.0) can't
   hold a 27° grade (needs ~4.4). **Fix:** the spawn disc classifies as **bare rock**
   (full grip) — thematically fine for a rocky peak start.

---

## Deviations from plan

1. **Steps 2–4 shipped as one coherent controller rewrite** instead of three
   landings — the systems share state (`_horiz`, `_in_slide`, `_stumble`) and
   splitting them would have meant three rounds of throwaway glue. The plan's
   per-step smoke runs collapsed into the one suite.
2. **Spawn disc = ROCK** (bug 3) — a D1 refinement, not a D1 change.
3. **Phase 2's "verified" downhill numbers were wrong** (bug 1) — corrected
   behavior documented here; the Phase 2 completion doc's 8.81 m/s figure is
   historical, superseded by 18.37 m/s.

---

## Open items (user side)

* [ ] `F5` feel pass: grass → rock → snow → ice distinct; carve on snow; climb with
      run-up / slide without; coyote + buffer ledge hops; one big cliff drop → skid + stumble
* [ ] **Gate question:** animal or shopping cart?
* [ ] Tune with the F3 overlay — every number is a first guess in `Config`
* [ ] Run the suggested commits
* [ ] `reffimg/` jpegs still untracked (pending since Phase 1)

---

## Handoff → Phase 4

Phase 4 target (per `README.md`): *the signature first-person camera* — head movement,
running bob, slope tilt, jump/landing feel, speed effects, collision shake.

Already in place for it:

* `EventBus.goat_landed(impact)` fires with real impact numbers — the camera's
  landing-dip subscriber plugs straight in
* `get_debug_state()` exposes live speed / state / slope — bob rate and tilt can
  read the same source
* Head/camera rig isolated in `Head` + `Camera3D` + `head_camera.gd` — Phase 4 work
  has a clean home without touching movement code
* Known gaps to carry: the `velocity.y ≈ 0 while floor-sliding` quirk becomes
  load-bearing for camera tilt — fix it there if needed
