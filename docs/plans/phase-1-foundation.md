# 🏗️ Phase 1 — Project Foundation: Execution Plan

> Expands `README.md` → *Phase 1 — Project Foundation* into concrete, executable steps.
> Nothing here touches gameplay. Goal: a clean Godot 4 skeleton that Phase 2 (mountain + goat prototype) can be dropped into.

---

## Goal

```text
Git repo
   ↓ (done ✅)
Godot 4 project (Compatibility renderer, web-ready)
   ↓
Modular folder structure
   ↓
Game config (autoloads)
   ↓
Input system (action map)
   ↓
Basic scene system (Main + test scene)
   ↓
READY FOR PHASE 2 🐐
```

**Definition of done:** project opens clean in Godot 4, `F5` runs a test scene, every input action fires, `git status` stays clean, no gameplay code exists yet.

---

## Decisions locked in Phase 1

These are decided **now** because they're expensive to change later:

| # | Decision | Choice | Why |
|---|----------|--------|-----|
| D1 | Renderer | **Compatibility** (WebGL 2) | Web export only supports Compatibility. Forward+ (Vulkan) does not run in browsers. Choosing anything else breaks the Vercel target. |
| D2 | Language | **GDScript** (no C#) | C# (.NET) cannot export to web in Godot 4. GDScript is the only browser-safe choice. |
| D3 | Godot version | **4.7.2 stable** (pinned, `brew install --cask godot`) | Web export templates + Compatibility renderer maturity. |
| D4 | Input abstraction | **Action names only** (never raw keys in gameplay code) | Same actions later get touch/gamepad bindings without touching gameplay code. |
| D5 | Units | 1 unit = 1 meter; goat ≈ 0.9–1.2 m tall | Keeps physics numbers sane and asset scale consistent. |
| D6 | Physics tick | Default 60 Hz | Stable for a 60 FPS browser target. Revisit only with evidence. |

**Out of scope (Phase 2+):** terrain, goat model/movement, camera rig, physics feel, UI beyond debug prints, web export presets (Phase 14 — but D1/D2 exist *because* of it).

---

## Step 0 — Tooling setup

**Do:**

* Install Godot 4.x stable (macOS):
  * `brew install --cask godot` — or download from godotengine.org
* Verify: open Godot → Help → About → note exact version (e.g. `4.x.y`) → write it into this doc's D3 row.
* Optional but recommended: VS Code + `godot-tools` extension, and `gdtoolkit` (`pip install gdtoolkit`) for `gdlint`/`gdformat`.

**Done when:** Godot launches and the exact version is recorded.

⏱ ~10 min

---

## Step 1 — Git hygiene (before Godot touches the repo)

Godot generates a `.godot/` cache directory on first open — it must never be committed.

**Create `.gitignore`** (repo root):

```gitignore
# Godot 4
.godot/
*.translation
export_credentials.cfg
export_presets.cfg

# OS
.DS_Store
Thumbs.db

# Tooling
.gdignore-assets/
```

*Note: `export_presets.cfg` is ignored for now; we'll commit it deliberately in Phase 14 (it contains the web export config, minus credentials).*

**Done when:** `.gitignore` exists at root.

**Commit checkpoint:** `chore: add Godot 4 gitignore`

⏱ ~5 min

---

## Step 2 — Create the Godot project

**Do:**

* Godot → New Project → path = this repo root → name `GoatDive`.
* Renderer: **Compatibility** (decision D1).
* Project Settings → confirm:
  * `display/window/size/viewport` → `1280×720`, resizable
  * `display/window/vsync/vsync_mode` → Enabled
  * `application/config/name` → `GoatDive`
  * `application/config/features` → contains `GL Compatibility`
* Open the project once so it generates `.godot/`, then confirm `git status` shows **nothing new** (Step 1 doing its job).

**Done when:** project opens with zero errors/warnings in the Godot console and `git status` is clean.

**Commit checkpoint:** `feat: init Godot 4 project (Compatibility renderer)`

⏱ ~15 min

---

## Step 3 — Modular folder structure

Create under `res://`:

```text
res://
├── scenes/
│   ├── main/          # Main.tscn root + bootstrap
│   ├── terrain/       # Phase 2+: mountains
│   ├── goat/          # Phase 2+: goat + camera rig
│   └── ui/            # Phase 11+: HUD, menus
├── scripts/
│   ├── game/          # config, state, event bus, scene loader
│   ├── player/        # Phase 2+: goat controller
│   └── utils/         # helpers
├── assets/
│   ├── models/
│   ├── textures/
│   ├── sounds/        # Phase 12+
│   └── fonts/
└── docs/
    └── plans/         # this file lives here
```

Empty folders need a `.gitkeep` (or a one-line `README.md` saying what belongs there — preferred, self-documenting).

**Done when:** tree exists in the filesystem and in Godot's FileSystem dock.

**Commit checkpoint:** `chore: add modular folder structure`

⏱ ~10 min

---

## Step 4 — Game configuration (autoloads)

Three singletons, deliberately tiny — they grow per phase:

| Autoload name | File | Responsibility |
|---|---|---|
| `Config` | `scripts/game/config.gd` | Immutable tunables: gravity, speeds, jump velocity, version, debug flags |
| `GameState` | `scripts/game/game_state.gd` | Mutable runtime state: current scene, race timer stub |
| `EventBus` | `scripts/game/event_bus.gd` | Global signals (`race_started`, `race_finished`, `goat_landed` — unconnected for now, used from Phase 6) |

Skeleton `config.gd`:

```gdscript
extends Node
## Immutable game tunables. One source of truth.

const VERSION := "0.1.0-phase1"
const DEBUG := true

# Phase 3 will tune these — placeholders only.
const GRAVITY := 9.8
const MOVE_SPEED := 8.0
const JUMP_VELOCITY := 4.5
```

Register all three in **Project Settings → Globals (Autoload)**.

**Done when:** a temporary `_ready()` print of `Config.VERSION` appears in the console, then the print is removed.

**Commit checkpoint:** `feat: add Config, GameState, EventBus autoloads`

⏱ ~30 min

---

## Step 5 — Input system

**Project Settings → Input Map** — register these actions (D4: gameplay code uses action names only):

| Action | Keys | Used by |
|---|---|---|
| `move_forward` | `W`, `Up` | Phase 2 movement |
| `move_back` | `S`, `Down` | Phase 2 movement |
| `move_left` | `A`, `Left` | Phase 2 movement |
| `move_right` | `D`, `Right` | Phase 2 movement |
| `jump` | `Space` | Phase 2 jump |
| `restart` | `R` | Phase 2 restart |
| `pause` | `Esc` | Phase 11 pause (Phase 1: releases mouse) |
| `toggle_debug` | `F3` | debug HUD toggle (later) |

Mouse: **no action needed yet** — raw `Input.MOUSE_MODE_CAPTURED` handling belongs to the Phase 4 camera rig. Phase 1 only defines the action table.

**Done when:** every action above exists in the Input Map with the bindings shown.

**Commit checkpoint:** `feat: define input action map`

⏱ ~15 min

---

## Step 6 — Basic scene system

**6a. `Main.tscn`** (`scenes/main/`):

```text
Main (Node3D)
└── World (Node3D)        # test scene mounts here
```

`main.gd` (on root): on `_ready()` → print `Config.VERSION`, set window title. In `_unhandled_input()` → `pause` releases/captures mouse, `restart` prints `"[restart] wired (Phase 2)"`. Nothing else.

**6b. Test scene** (`scenes/main/test_level.tscn`): flat ground plane (20×20 m), one DirectionalLight3D, one cube on the ground, WorldEnvironment with sky + ambient light.

**6c. Scene loader stub** (`scripts/game/scene_loader.gd`): one static `switch(scene_path: String)` that frees the current `World` child and instantiates the new one. No fades, no menu — Phase 6 territory.

**Done when:** `F5` runs `Main.tscn` → cube sits on lit ground, sky visible, version prints once, `R` / `Esc` behave as wired above.

**Commit checkpoint:** `feat: add Main scene, test level, scene loader stub`

⏱ ~45 min

---

## Step 7 — Smoke test & acceptance

Run the full checklist:

* [ ] Godot console shows **zero errors/warnings** on open and on run
* [ ] `F5` → test level renders at ~60 FPS (debug monitor)
* [ ] Version string prints exactly once
* [ ] Every action in the Step 5 table fires (temporary `Input.is_action_...` debug prints in `main.gd`, removed after)
* [ ] `Esc` releases the mouse; clicking re-captures (or acceptable stub)
* [ ] `git status` clean — `.godot/` ignored, no stray files
* [ ] All new files committed (owner runs the commits)
* [ ] D3 in this doc updated with the pinned Godot version

**All boxes ticked → Phase 1 complete. Phase 2 (mountain + goat prototype) can start.**

⏱ ~15 min

---

## Effort summary

| Step | | Time |
|---|---|---|
| 0 | Tooling | ~10 min |
| 1 | Git hygiene | ~5 min |
| 2 | Godot project | ~15 min |
| 3 | Folder structure | ~10 min |
| 4 | Autoloads | ~30 min |
| 5 | Input map | ~15 min |
| 6 | Scene system | ~45 min |
| 7 | Smoke test | ~15 min |
| | **Total** | **~2.5 h** |

---

## Risks & notes

* **D1 is the load-bearing decision.** If we pick Forward+ now, the entire web/Vercel plan (Phases 14–15) dies. Compatibility has fewer fancy rendering features — acceptable for the alpine look; fog, lights, and particles all work.
* **Web export + threads:** Godot web builds with threads need `SharedArrayBuffer` → special `COOP`/`COEP` headers on Vercel. Noted now, handled in Phase 14/15.
* **`reffimg/` images** are still untracked — decide (commit vs. ignore) whenever the next commit happens.
* **Keep gameplay code out.** If a step starts feeling like a game, it belongs in Phase 2.
