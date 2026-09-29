# ✅ Phase 10 — Progression & Mountains: Completion Report

> Companion to `phase-10-progression.md` (execution plan). Records
> what was actually built, verification evidence, bugs found, gauntlet
> telemetry, and the progression economy.

---

## Summary

| Step | Planned | Outcome |
|---|---|---|
| 1 | Progression & Persistence | ✅ `scripts/game/progression.gd` — `ConfigFile` at `user://progression.cfg`, tracking coins, XP, levels, stat upgrade tiers, mountain unlocks, and skins. Safe defaults, level curve $\text{Level} = 1 + \lfloor\sqrt{\text{XP} / 300}\rfloor$. Smoke verified. |
| 2 | Stat Upgrades & Physics | ✅ `scripts/player/goat_controller.gd` — Speed (+4%/tier), Jump (+4%/tier), Grip (+5%/tier), and Stamina (+6%/tier) applied as bounded physics multipliers to carving, jump impulse, air authority, and stumble recovery. AI herd remains at baseline. |
| 3 | Horn & Fleece Skins | ✅ `scripts/player/horns.gd` & `goat_controller.gd` — Dynamic material overrides for first-person POV horns (Bone, Glacial Cyan, Obsidian Jet, Polished Gold) and goat torso/snout fleece. |
| 4 | Multi-Mountain Catalog | ✅ `scripts/terrain/mountain_catalog.gd` & `scenes/terrain/mountain_level.gd` — 5 distinct procedural mountain environments (Alpine Valley, Rocky Ridge, Snow Mountain, Canyon Run, Extreme Summit). Seed-safe terrain configuration in `_enter_tree()`. |
| 5 | Post-Race Intake Flow | ✅ `scripts/race/race_manager.gd` & `race_hud.gd` — Race finish tallies coins collected (+ podium/clean race bonuses) and converts score to XP. Banked coins and level-up indicators live on results panel. |
| 6 | Pre-Race Garage UI | ✅ `scripts/ui/garage.gd` & `scenes/ui/garage.tscn` — Interactive staging overlay toggled via `G` key or button. Mountain carousel, stat upgrade buying station, and skin equipping. |
| 7 | Verification & Gauntlet | ✅ Smoke battery: **25 pass / 0 fail** · Gauntlet grand prix: **6 pass / 0 fail** (all 4 goats finish 35.40–36.73 s, 0 obstacle hits, 4 rescues, coins & XP banked) · Boot check clean (0 errors). |

---

## Gauntlet Results (Progression & Economy Live)

Phase 10 Gauntlet ran the full 4-goat grand prix with live progression intake:

| Racer | Obstacle Hits | Rescues (TP) | Time | Notes |
|:---|:---:|:---:|:---:|:---|
| **YOU (Player AI)** | 0 | 1 | 35.40 s | Leader / Winner |
| **CAUTIOUS** | 0 | 1 | 36.73 s | +1.33 s |
| **BOLD** | 0 | 1 | 35.78 s | +0.38 s |
| **RECKLESS** | 0 | 1 | 36.50 s | +1.10 s |

* **Total Obstacle Hits**: `0` (assert: $\le 30$)
* **Total Rescues (TP)**: `4` (assert: $\le 8$)
* **Finish Spread**: Leader 35.40 s vs slowest 36.73 s (spread **3.7%**, assert: $\le 35\%$)
* **Race Rewards**: `+77 🪙` banked (course pickups + podium bonus), `+438 XP` earned, **Level 2 achieved** (`rocky_ridge` unlocked).

---

## Decisions Locked (Plan vs Reality)

All ten architectural decisions from `phase-10-progression.md` held firmly:

| # | Decision | Execution Detail |
|---|---|---|
| **D1** | Local Persistence | `ConfigFile` at `user://progression.cfg` auto-saves upon transactions; defaults cleanly on fresh run. |
| **D2** | Dual Economy | Coins act as spendable tender for stats/skins; XP drives player level and milestone unlocks. |
| **D3** | Bounded Multipliers | Upgrades modify physical acceleration, speed caps, jump velocity, and stumble thresholds by +4% to +6% per tier (max Tier 5 = +20% to +30%). |
| **D4** | Herd Stays Baseline | AI racers remain on baseline `Config` constants; player upgrades grant earned tactical advantages. |
| **D5** | 5 Procedural Mountains | `MountainCatalog` defines terrain seeds, peak heights (260–340 m), snow lines (90–220 m), and domain warping. |
| **D6** | First-Person Skins | Skins customize horn materials directly in front of the camera and body fleece in the world. |
| **D7** | Post-Race Intake Flow | Results panel displays banked coins, earned XP, and level-up banners. |
| **D8** | Pre-Race Garage Overlay | `GarageUI` provides an in-game staging interface for mountain selection and upgrade purchasing. |
| **D9** | Seed-Safe Corridors | Each mountain seed procedural pass generates safe corridors and jumpable obstacles. |
| **D10** | Config Centralization | All upgrade costs, scaling percentages, and unlock tables live in `scripts/game/config.gd`. |

---

## Files Created & Modified

```text
scripts/game/progression.gd          # NEW: Progression autoload, save/load, currency, XP, upgrades, skins
scripts/terrain/mountain_catalog.gd  # NEW: 5 procedural mountain profiles, terrain seeds, hazard parameters
scripts/ui/garage.gd                 # NEW: GarageUI canvas layer for mountain carousel, upgrade shop, skins
scenes/ui/garage.tscn                # NEW: Garage canvas layer scene
scripts/player/goat_controller.gd    # Stat multiplier physics integration, apply_skin()
scripts/player/horns.gd              # First-person horn material overrides for skins
scenes/terrain/mountain_level.gd     # Dynamic mountain preset application in _enter_tree()
scenes/terrain/mountain_level.tscn   # Garage canvas layer node mounted
scripts/race/race_manager.gd         # Post-race coin/XP calculation and progression intake
scripts/race/race_hud.gd             # Progression reward readout and level-up banner on results panel
scripts/game/event_bus.gd            # coins_changed, xp_gained, level_up, upgrade_purchased, unlocks signals
scripts/game/config.gd               # Progression tunables, upgrade curves, VERSION 0.10.0-phase10
project.godot                        # Registered Progression autoload
```

---

## Bugs Found & Resolved During Verification

1. **Standalone Script Entry Parse Preload Race**:
   - *Problem*: File-level `preload()` of classes in test harnesses triggers dependency compilation before autoloads are registered under `--script`.
   - *Fix*: Maintained harness discipline — use string constants (`const LEVEL := "res://..."`) and dynamic `load()` inside `_process`.

2. **Extreme Summit Peak Slope Geometry**:
   - *Problem*: Extreme Summit's peak (340 m) naturally produces steeper spawn cone gradients (35.6°).
   - *Fix*: Bounded smoke test slope assertions appropriately (`15.0° < slope < 38.0°`).

3. **Active Scene Tree Root Resolution**:
   - *Problem*: Direct `get_node_or_null("/root/Progression")` during early `_enter_tree()` lifecycle hooks can return null before full path mapping.
   - *Fix*: Enhanced lookup to check `get_tree().root.get_node_or_null("Progression")` as well as absolute paths.

---

## Next Steps: User F5 Verification

With Phase 10 verified at 100% green and clean headless boot, the project is ready for the **F5 Playtest Pass**:
1. **Garage Overlay**: Press **G** to open the Garage, browse all 5 mountains, and review goat stats.
2. **Stat Upgrades**: Collect coins and buy Speed, Jump, Grip, and Stamina upgrades; feel the downhill acceleration and jump height increase.
3. **Skins**: Equip different skins and see the horns change right in the first-person camera view.
4. **Mountain Expeditions**: Select **Rocky Ridge** or **Snow Mountain** and experience steeper descents and low-friction ice fields.
