# Phase 11 — UI Overhaul: Execution Plan

> Continues from `phase-10-completion.md`. Replaces the Phase 6 "minimal
> text HUD" scaffold (its own header says *"scaffolding the Phase 11
> reskin replaces"*) with a styled desktop HUD: themed top bar with live
> coins, speedometer, minimap, pause menu, button-driven results panel,
> and a garage reskin. README Phase 11 list: distance, speed, timer,
> position, coins, pause, restart, race results.

---

## Steps

| # | Step | Deliverable |
|---|---|---|
| 1 | Shared theme factory | `scripts/ui/hud_theme.gd` — one palette + `StyleBoxFlat` builders (panel / chip / button) consumed by HUD **and** garage. Default engine font (no font assets exist in-repo; a font file can drop into the factory later without touching callers). |
| 2 | Config tunables | `scripts/game/config.gd` — Phase 11 block (speedometer max, minimap size/margins, chip colors stay in the factory) + `VERSION 0.11.0-phase11`. |
| 3 | Manager surface | `scripts/race/race_manager.gd` — `speed` (m/s, player horizontal) added to `get_race_state()`; `get_racer_markers()` → `[{name, pos, is_player, finished, color}]` so the minimap never reaches into racer nodes (D8 pattern held since Phase 7). |
| 4 | HUD reskin | `scripts/race/race_hud.gd` — panel-backed chip top bar **TIME · GATE · DIST · POS · ✦SCORE · 🪙(session pickups)**, themed countdown/GO, wrong-way banner, trick pops (kept), styled results panel + **RACE AGAIN / GARAGE buttons** (keys R/G still work). |
| 5 | Speedometer | Bottom-right card: big m/s number + fill bar vs `HUD_SPEEDO_MAX` (bar color shifts amber→red near max). |
| 6 | Minimap | Top-right card, custom `_draw()`: course polyline through gate XZ positions, gate dots (NEXT highlighted), finish dot, AI dots (Config profile colors), player heading arrow. North-up; pure `map_transform()` is headless-testable. |
| 7 | Pause menu | Esc → `get_tree().paused` + overlay (RESUME / RESTART / GARAGE). HUD + Garage run `PROCESS_MODE_ALWAYS`; RaceManager's clock is delta-accumulated so it freezes for free. Mouse released on pause, recaptured on resume. **Unpause before any scene reload** (paused-reload trap). |
| 8 | Garage reskin | `scripts/ui/garage.gd` — theme factory panels/buttons; usable while paused; Esc-guard: HUD skips pause toggle while garage is visible (garage owns Esc then). |
| 9 | main.gd trim | Phase 1 Esc mouse-toggle scaffold retired — the pause menu owns Esc. `restart` (R) stays in `main.gd`. |
| 10 | Verification | Headless smoke battery (theme, chips, speed, markers, minimap transform, pause lifecycle, garage-while-paused, boot-clean) + 4-goat gauntlet re-run (no regression) + boot check 0 errors. |

---

## Decisions

| # | Decision | Rationale |
|---|---|---|
| **D1** | UI stays code-built canvas | Repo pattern since Phase 6 — no new `.tscn` for HUD, diffs stay reviewable, nothing to merge in the editor. |
| **D2** | Default font + StyleBox theming | `assets/fonts/` is empty; fetching binaries mid-phase is out of scope. Panels, chips, color ramps, and size ramps carry the style. |
| **D3** | Poll-driven HUD | `get_race_state()` snapshot per `_process` frame (existing pattern); the only new data path is `coins_changed` — no, even coins poll `Coins.collected_count()` — zero new signals. |
| **D4** | Speedometer = number + bar, m/s | Physics units everywhere else in the game; an arc gauge is prettier but the number is the contract. |
| **D5** | Minimap north-up | Rotating maps cost orientation; a downhill race reads fine fixed. Pure transform fn → unit-testable headless. |
| **D6** | Pause = tree pause + ALWAYS layers | Delta-accumulated clocks freeze correctly; AI/physics/goat input all stop for free. One trap: reload while paused — every reload path unpauses first. |
| **D7** | Esc ownership: HUD (menu), garage (close) | `main.gd` Esc branch deleted; HUD checks garage visibility before toggling pause — no double handling. |
| **D8** | Manager is the only racer surface | HUD reads `speed` + `get_racer_markers()`; it never walks racer nodes (Phase 7 attribution discipline). |
| **D9** | Coins chip = session pickups | During the race the chip counts THIS run's pickups (`Coins.collected_count()`); bank total stays on results/garage where progression already shows it. |
| **D10** | Buttons mirror keys | RACE AGAIN/GARAGE buttons duplicate R/G hints — desktop parity today, touch-ready for Phase 14. |

---

## Risks

| Risk | Impact | Mitigation |
|:---|:---:|:---|
| **Paused scene reload** (tree stays paused after reload) | High | Every reload path (`_restart_race`, garage RACE MOUNTAIN, results button) calls `get_tree().paused = false` first. |
| **Input double-handling** (Esc/G while garage open) | Medium | HUD guards pause toggle on garage visibility; garage keeps its own Esc close. |
| **Minimap per-frame cost** | Low | One `_draw()` with < 20 primitives; `queue_redraw()` only while racing. |
| **Results refresh churn** (post-finish AI trickle) | Low | Existing 500 ms refresh cadence kept; rows diffed by text before rebuild. |
| **Headless `--script` preload race** (Phase 9/10 saga) | Medium | Harnesses: string-path consts, `load()` inside functions, scaffolding mounted early, no macOS `timeout`. |

---

## Verification (gate to completion doc)

1. **Smoke battery** — theme factory styles build; HUD builds with and without manager; `speed` present in race state; `get_racer_markers()` returns player + 3 AI; minimap transform maps corners correctly; pause toggles tree + overlay and unpause-on-reload holds; garage theme applies.
2. **Gauntlet** — full 4-goat grand prix headless on Alpine Valley: all finish, spread ≤ 35%, 0 obstacle-hit regressions, coins/XP intake intact.
3. **Boot check** — `--headless` boot to menu-ready, 0 errors.

Handoff → Phase 12 (*Audio & Effects*): `assets/sounds/` is an empty stub; Phase 12 fills it.
