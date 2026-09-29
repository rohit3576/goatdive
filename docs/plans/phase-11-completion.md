# ✅ Phase 11 — UI Overhaul: Completion Report

> Companion to `phase-11-ui.md` (execution plan). Records what was
> actually built, verification evidence, bugs found, and the gauntlet
> no-regression proof.

---

## Summary

| Step | Planned | Outcome |
|---|---|---|
| 1 | Shared theme factory | ✅ `scripts/ui/hud_theme.gd` — alpine-night palette (INK/GOLD/CYAN/RED) + `StyleBoxFlat` builders (panel/chip/button/button-hot) + `styled_button`/`label` helpers. Default engine font (D2: `assets/fonts/` is empty; a font file drops into the factory later without touching callers). |
| 2 | Config tunables | ✅ `HUD_SPEEDO_MAX`, `HUD_MINIMAP_SIZE/PAD`, `HUD_CHIP_PAD_X`, `HUD_TRICK_POP_SECS`; `VERSION 0.11.0-phase11`. |
| 3 | Manager surface | ✅ `speed` (live m/s) in `get_race_state()`; `get_racer_markers()` → `{name, pos, yaw, is_player, finished, color}` — the HUD never touches racer nodes (D8 held). |
| 4 | HUD reskin | ✅ Panel-backed chip top bar **TIME · GATE · DIST · POS · SCORE · 🪙COINS** (session pickups, D9), themed countdown/GO, wrong-way banner, trick pops, styled results panel with **🏁 RACE AGAIN / 🐐 GARAGE** buttons (mouse auto-released on finish). |
| 5 | Speedometer | ✅ Bottom-right card: 42 pt m/s readout + fill bar vs `HUD_SPEEDO_MAX`, color bands CYAN → GOLD (60%) → RED (85%). |
| 6 | Minimap | ✅ Top-right 176 px card, north-up XZ projection: course spine polyline, gate dots (NEXT gold/fat, finish white square), AI dots in profile colors, player heading arrow. Pure `world_to_map()` static. |
| 7 | Pause menu | ✅ Esc → `get_tree().paused` + overlay (RESUME / RESTART RACE / GARAGE & UPGRADES). HUD + Garage run `PROCESS_MODE_ALWAYS`; delta-accumulated clock freezes for free; every reload path unpauses first (trap closed). |
| 8 | Garage reskin | ✅ Theme-factory panels/buttons; usable while paused; Esc/G ownership guarded against the HUD. |
| 9 | main.gd trim | ✅ Phase 1 Esc mouse-toggle scaffold retired — the pause menu owns Esc; `restart` (R) stays. |
| 10 | Verification | ✅ Smoke battery **27 pass / 0 fail** · Gauntlet **5 pass / 0 fail** · Boot checks 0 errors (before *and* after). |

---

## Gauntlet Results (No-Regression Proof)

Full 4-goat grand prix, Alpine Valley, player puppeted by a BOLD brain
(Phase 10 harness pattern), run headless after all UI changes:

| Racer | Time | vs Phase 10 |
|:---|:---:|:---:|
| **YOU (Player AI)** | 35.40 s | *identical* |
| **BOLD** | 35.78 s | *identical* |
| **RECKLESS** | 36.50 s | *identical* |
| **CAUTIOUS** | 36.73 s | *identical* |

* **Finish spread**: 3.8% (assert ≤ 35%)
* **Player obstacle hits**: `0` (assert ≤ 30)
* **Progression intake**: `+77 🪙 · +438 XP` banked — results panel surfaced
* Bit-identical finishing times to the Phase 10 gauntlet = **zero gameplay
  regression**: the UI layer changed rendering and input only, never physics.

---

## Smoke Battery (27/27)

| Group | Checks |
|---|---|
| Theme (S1–S2) | panel/chip/button styleboxes build with palette colors + corners; `styled_button` carries overrides |
| Minimap math (S3) | `world_to_map` maps a 100×50 world into a 100×100 map at exact corners (10,30)/(90,70) |
| Level surface (S4–S6) | HUD/manager/garage mounted; `state.speed` present; 4 markers with player flag, yaw, color |
| HUD composition (S7) | six top-bar chips, speedometer bar, minimap card, hidden pause overlay |
| Garage (S10) | themed panel + `PROCESS_MODE_ALWAYS` |
| Pause lifecycle (S8–S9) | pause engages (tree + overlay), garage-open guard reads true, unpause restores; restart unpauses **before** reload and the scene remounts |

---

## Bugs Found & Resolved During Verification

1. **Stale global class cache**:
   - *Problem*: `class_name HudTheme` (and even committed `GarageUI`) failed to resolve — `.godot/` caches are not committed, so fresh checkouts can't see new global classes until an editor/import pass.
   - *Fix*: `godot --headless --import` regenerates them. CI/export note: always import before headless runs.

2. **Harness `root` scope** (temp only):
   - *Problem*: the controller (extends `Node`) referenced SceneTree's `root` directly — parse error, silent no-op phase.
   - *Fix*: `get_tree().root`.

3. **`current_scene` assignment order** (temp only):
   - *Problem*: assigning `current_scene` before `add_child` is silently dropped → `reload_current_scene()` errored with null.
   - *Fix*: add to root first, then assign.

4. **Nonexistent stylebox getter** (temp only):
   - *Problem*: `StyleBoxFlat.get_corner_radius_all()` doesn't exist; the runtime error aborted the rest of the unit-check function (S2/S3 silently skipped — a good lesson in why "no FAIL lines" ≠ "all checks ran").
   - *Fix*: assert `corner_radius_top_left` instead; the rerun printed the previously-missing checks.

---

## Files Created & Modified

```text
scripts/ui/hud_theme.gd               # NEW: palette + StyleBoxFlat factory (HUD & garage share it)
scripts/race/race_hud.gd              # REWRITE: chips, speedometer, minimap, pause menu, results buttons
docs/plans/phase-11-ui.md             # NEW: execution plan
docs/plans/phase-11-completion.md     # NEW: this report
scripts/race/race_manager.gd          # speed feed + get_racer_markers() (+yaw)
scripts/ui/garage.gd                  # theme, PROCESS_MODE_ALWAYS, unpause-before-reload
scripts/game/config.gd                # Phase 11 tunables, VERSION 0.11.0-phase11
scenes/main/main.gd                   # Esc scaffold retired (pause menu owns it)
scripts/ui/hud_theme.gd.uid           # NEW: script UID (generated by import pass)
scripts/game/progression.gd.uid       # NEW: Phase 10 scripts' UIDs materialized by the
scripts/terrain/mountain_catalog.gd.uid  #  same import pass — belong beside their scripts
scripts/ui/garage.gd.uid              #
```

---

## Next Steps: User F5 Verification

1. **Pause menu**: press **Esc** mid-race — tree freezes (timer, AI, countdown all stop), mouse appears; RESUME / RESTART / GARAGE all work.
2. **HUD**: watch the chip bar (TIME · GATE · DIST · POS · SCORE · COINS), the bottom-right speedometer climbing through its color bands, and the top-right minimap tracking the herd.
3. **Results**: finish a race — buttons RACE AGAIN / GARAGE are clickable (mouse auto-releases); standings refresh as AI trickle in.
4. **Garage**: press **G** anytime (even paused) — themed panels and buttons throughout.

Handoff → Phase 12 (*Audio & Effects*): `assets/sounds/` is an empty stub awaiting footsteps, wind, impacts, and music.
