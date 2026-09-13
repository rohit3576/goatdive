# ✅ Phase 1 — Project Foundation: Completion Report

> Companion to `phase-1-foundation.md` (execution plan). Records what was actually built,
> verification evidence, and deviations. Phase 1 is **complete** pending the two
> user-side checks listed at the bottom.

---

## Summary

| Step | Planned | Outcome |
|---|---|---|
| 0 | Tooling setup | ✅ Godot **4.7.2 stable** installed via `brew install --cask godot`, `godot` on PATH |
| 1 | Git hygiene | ✅ `.gitignore` covers `.godot/`, export credentials/presets, translations, OS junk |
| 2 | Godot project | ✅ `project.godot` authored — Compatibility renderer, 1280×720, main scene set |
| 3 | Folder structure | ✅ Full `scenes/` `scripts/` `assets/` tree with README stubs |
| 4 | Autoloads | ✅ `Config`, `GameState`, `EventBus` registered + implemented |
| 5 | Input map | ✅ All 8 actions registered (WASD/arrows, Space, R, Esc, F3) |
| 6 | Scene system | ✅ `Main.tscn` → `main.gd` bootstrap → `SceneLoader` stub → `test_level.tscn` |
| 7 | Smoke test | ✅ Headless import + run + input-map assertion all passed (evidence below) |

**Total hands-on time:** well under the ~2.5 h estimate (automated).

---

## Decisions locked

| # | Decision | Value |
|---|---|---|
| D1 | Renderer | **Compatibility** (WebGL 2) — browser/Vercel safe |
| D2 | Language | **GDScript** only |
| D3 | Godot version | **4.7.2 stable** (`brew install --cask godot`) |
| D4 | Input abstraction | Action names only; no raw keys in gameplay code |
| D5 | Units | 1 unit = 1 m |
| D6 | Physics tick | 60 Hz (explicit in `project.godot`) |

---

## Files created / changed

```text
.gitignore                        # engine + OS junk (pre-existing from Step 1)
project.godot                     # NEW — project config, autoloads, input map
icon.svg                          # NEW — temporary mountain-silhouette icon
scenes/
├── main/
│   ├── main.tscn                 # NEW — root scene (Main → World)
│   ├── main.gd                   # NEW — bootstrap + pause/restart wiring
│   └── test_level.tscn           # NEW — sky, sun (shadows), 20 m ground, cube
├── terrain/README.md             # NEW — stub (Phase 2+)
├── goat/README.md                # NEW — stub (Phase 2+)
└── ui/README.md                  # NEW — stub (Phase 11+)
scripts/
├── game/
│   ├── config.gd                 # NEW — VERSION, DEBUG, physics tunables
│   ├── game_state.gd             # NEW — runtime state stub
│   ├── event_bus.gd              # NEW — signals: race_started/finished, goat_landed
│   └── scene_loader.gd           # NEW — static switch() stub
├── player/README.md              # NEW — stub (Phase 2+)
└── utils/README.md               # NEW — stub
assets/
├── models/README.md              # NEW — stub
├── textures/README.md            # NEW — stub
├── sounds/README.md              # NEW — stub (Phase 12+)
└── fonts/README.md               # NEW — stub
reffimg/.gdignore                 # NEW — stops Godot importing design references
docs/plans/phase-1-foundation.md  # EDIT — D3 pinned to 4.7.2
docs/plans/phase-1-completion.md  # NEW — this file
```

Also generated (commit these — standard Godot practice): `icon.svg.import`.

Deleted after use: `scripts/utils/check_input_map.gd` (temp verification script, per plan Step 7).

---

## Verification evidence

All checks run headless with the installed engine binary:

```text
$ godot --headless --path . --import
→ DONE, exit 0 — no errors/warnings

$ godot --headless --path . --quit-after 5
→ "GoatDive 0.1.0-phase1 — main scene ready", exit 0
→ proves: autoloads load, main.gd runs, SceneLoader mounts test_level.tscn

$ godot --headless --path . --script res://scripts/utils/check_input_map.gd
→ "INPUT-MAP-OK: all 8 actions registered", exit 0

$ git check-ignore -v .godot/
→ ".gitignore:2:.godot/  .godot/" — engine cache ignored
```

---

## Deviations from plan

Small, all benign:

1. **Project authored as files, not via editor GUI.** `project.godot` / `.tscn` written directly (text formats), then imported headlessly. Same result, fully reproducible.
2. **`icon.svg` added** — plan didn't specify one; `project.godot` references it. Placeholder mountain silhouette.
3. **`reffimg/.gdignore` added** — Godot started generating `.import` files for the design reference jpegs. Now skipped. Stale `.jpeg.import` files removed.
4. **`SceneLoader` called via `preload()`, not `class_name`/autoload** — avoids dependency on the editor's global-class cache under headless runs. Same static API as planned.
5. **gdtoolkit / VS Code extension skipped** — optional in plan Step 0.
6. **Version-print check** — done through the smoke run output instead of a temp `_ready()` print (same evidence, one less edit).

---

## Open items (user side)

* [ ] Open the project in the Godot editor → `F5` → confirm: cube on lit ground, sky visible, ~60 FPS, `Esc` releases mouse, `R` prints `[restart] wired (Phase 2)`
* [ ] Run the suggested commits (see session handoff): project init, scenes+scripts, docs+gdignore
* [ ] Decide `reffimg/` jpegs: commit as design refs, or add `reffimg/` to `.gitignore`

---

## Handoff → Phase 2

Phase 2 target (per `README.md`): **one mountain + placeholder goat + first-person camera with visible horns + gravity/jump/collision/downhill acceleration + restart.**

Everything Phase 2 needs is in place:

- Input actions (`move_*`, `jump`, `restart`) waiting to be consumed
- `Config` tunables (`GRAVITY`, `MOVE_SPEED`, `JUMP_VELOCITY`) ready to be wired into a `CharacterBody3D`
- `SceneLoader.switch()` ready to swap `test_level.tscn` for a real mountain scene
- `scenes/terrain/` and `scenes/goat/` folders waiting
