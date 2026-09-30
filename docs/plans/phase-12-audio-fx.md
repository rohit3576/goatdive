# Phase 12 — Audio & Effects: Execution Plan

> Continues from `phase-11-completion.md`. README Phase 12 list: footsteps,
> goat sounds, breathing, rocks, wind, snow, jumps, impacts, falling,
> mountain ambience, music — plus dust, snow particles, motion effects,
> camera shake, landing effects. Nearly every trigger already exists as an
> `EventBus` signal (Phase 4–10 wiring); Phase 12 is a **listener layer**:
> it consumes events and state, never emits or mutates them. Physics stays
> untouched — the gauntlet must stay bit-identical.

---

## Steps

| # | Step | Deliverable |
|---|---|---|
| 1 | Sound-bank generator | `tools/gen_sounds.gd` — headless `--script` tool that **synthesizes placeholder WAVs** into `assets/sounds/` (wind loop, thud, whoosh, bonk, coin ding, gate chime, countdown beep, GO, bleat, fall rush, level-up jingle, two music pads). Deterministic (seeded noise/sine envelopes), run once, files committed. CC0 `.ogg` files can later replace any slot by filename — no code change. |
| 2 | Audio autoload | `scripts/audio/audio_manager.gd` (autoload `Sfx`) — code-built buses `Master → Music / Sfx / Ambience`; stream registry keyed by name; `play(name, vol_db, pitch_jitter)`; **graceful skip when a stream file is missing** (fresh checkout still boots clean — same contract as Phase 11's font drop-in, D2 there / D1 here). `PROCESS_MODE_ALWAYS` so pause-menu clicks and music keep working. |
| 3 | Event one-shots | Wire existing signals: `goat_jumped` → whoosh · `goat_landed` → thud scaled by `impact_speed` · `goat_bonked` / `goat_hit_obstacle` → bonk · `trick_scored` → per-name stinger (coin, near_miss, flips) · `checkpoint_passed` → chime (player passes only, same guard as `camera_fx.gd:231`) · `race_finished` → fanfare · `coins_changed` / `xp_gained` / `level_up` / `upgrade_purchased` / `mountain_unlocked` / `skin_unlocked` → progression stingers. |
| 4 | Poll-driven loops | Footsteps (stride accumulator from speed × grounded via `get_debug_state()`, surface-aware pitch), wind ambience (volume ∝ speed + altitude), fall rush (airborne + `vy` below threshold — mirrors `camera_fx` fall-drift gating, line 148), countdown beeps on integer crossings of `race_state.countdown` + GO at zero. Zero new signals (Phase 11 D3 precedent). |
| 5 | Music | Two state-bound loops — calm pad (menu/garage/pause), driving loop (racing) — crossfaded on `race_started` / `race_finished`. Music bus volume constant in `Config`; no settings UI this phase. |
| 6 | Effects spawner | `scripts/fx/effects_spawner.gd` — code-built `GPUParticles3D` one-shots (no `.tscn`, no textures: `GradientTexture1D` + `SphereMesh`/`QuadMesh` materials): landing dust ∝ impact at the goat's position (`goat_landed` carries `Node3D`), bonk debris, coin sparkle, gate-pass ring. Listener-only, same events as audio — one wiring pattern for both senses. |
| 7 | Weather particles | Camera-following snowfall emitter gated by altitude vs `MountainCatalog` snow line — Snow Mountain heavy, Alpine Valley light dusting, Canyon dust motes instead. Data-driven per mountain (Phase 10 D5 pattern). |
| 8 | Speed streaks | Air-streak particles above ~85% of `MAX_DOWNHILL_SPEED`, `CAM_FX`-gated. FOV kick already exists (Phase 4 D10) and is **not** retuned. |
| 9 | Config + version | Phase 12 block in `scripts/game/config.gd` — bus volumes, footstep cadence, particle counts, per-mountain weather density — + `VERSION 0.12.0-phase12`. |
| 10 | Verification | Headless smoke battery (bank files exist post-gen, manager boots, buses build, missing-stream skip, spawner spawn/despawn counts, snow-line gating, footstep cadence math) + 4-goat gauntlet re-run (**must stay bit-identical**) + boot check 0 errors. |

---

## Decisions

| # | Decision | Rationale |
|---|---|---|
| **D1** | Procedural placeholder audio, committed generator | Repo has no binary-asset pipeline (Phase 11 D2 skipped fonts for the same reason). A seeded, deterministic `gen_sounds.gd` produces reviewable-by-origin files; swapping in CC0 `.ogg` later is a file rename, zero callers change. |
| **D2** | Audio is a pure listener | `Sfx` never emits, never touches racer nodes' state, never writes physics. The Phase 11 gauntlet proved UI layers can be provably inert — audio/effects must repeat that proof. |
| **D3** | One-shots on signals, loops on polls | Discrete events already ride `EventBus`; continuous layers (footsteps, wind, countdown) poll `get_race_state()` / `get_debug_state()` exactly like the HUD polls — no new signals, no per-frame allocations. |
| **D4** | Three buses, volumes in `Config` | Music / Sfx / Ambience separation from day one so Phase 13+ (settings sliders, web-mix tweaks) is a one-file change. |
| **D5** | `PROCESS_MODE_ALWAYS` | Pause menu (Phase 11 D6) needs click feedback and doesn't deserve silence; `Sfx` freezes nothing and nothing freezes it. |
| **D6** | Effects = code-built one-shot particles | Repo pattern since Phase 6: no new `.tscn`, diffs reviewable, materials constructed in code. Short-lived emitters (`one_shot` + `emitting`) self-free via `tree_exited` timeout — no pooling needed at these counts. |
| **D7** | Camera shake is NOT rebuilt | Phase 4's trauma² model already keys off landings and bonks (D9 there). Phase 12 adds particles and audio to the **same** events — rebuilding shake would risk the feel that gauntlet-verified physics produced. |
| **D8** | Player-only attribution | Gate chimes, trick stingers, footsteps: player events only (the `goat == player` guard pattern). AI herds stay silent — positional AI audio is a Phase 13+ nicety, not this phase. |
| **D9** | WAV placeholders now, `.ogg` swap later | WAV is Godot-native and generator-writable today; OGG encoding isn't scriptable in GDScript. Web-export size budget is Phase 13's problem; the swap path is designed in from the start. |
| **D10** | Headless-safe by contract | Dummy audio driver must never crash `play()`; smoke asserts **stream presence and call safety**, never audibility. Same for particles: presence/lifetime, not pixels. |

---

## Risks

| Risk | Impact | Mitigation |
|:---|:---:|:---|
| **Gauntlet regression** (audio/effects leaking into simulation) | High | Listener-only architecture (D2); gauntlet rerun must match Phase 10/11 times exactly — any drift fails the phase. |
| **Headless `play()` on dummy driver** | Medium | Wrap in availability checks; smoke battery calls every `play()` path headless — 0 errors is a gate, not a hope. |
| **Pause interaction** (frozen UI clicks / stuck loops) | Medium | `PROCESS_MODE_ALWAYS` (D5); music crossfade state machine tested in smoke incl. pause-during-countdown. |
| **Web perf from particles** (Phase 14 target, 60 FPS) | Medium | Particle caps in `Config` (landing burst ≤ 24, snow ≤ 120 alive); weather emitter is a single `GPUParticles3D`, not per-flake nodes. |
| **WAV binaries in git** | Low | Seeded generator keeps them reproducible; sizes < 100 KB each; `assets/sounds/README.md` documents provenance + replacement contract. |
| **Stale global class cache** (Phase 11 lesson) | Medium | New `class_name` types minimal; `godot --headless --import` before any smoke run — already the documented pre-run step. |

---

## Verification (gate to completion doc)

1. **Smoke battery** — generator produces every bank slot; `Sfx` autoload mounts with buses; `play()` on a missing name is a silent no-op; every Phase 12 one-shot fires from its signal (synthetic emit); footstep cadence math (steps/s vs speed) checks out; effects spawner spawns and frees on land/bonk/coin/gate; snow emitter gates on catalog snow line; music crossfades on state change; all headless, 0 errors.
2. **Gauntlet** — full 4-goat grand prix, Alpine Valley: finishing times **bit-identical** to Phase 10/11 (35.40 / 35.78 / 36.50 / 36.73 s), spread ≤ 35%, 0 obstacle-hit regressions, coin/XP intake intact.
3. **Boot check** — `--headless` boot to menu-ready, 0 errors, before and after the import pass.

Handoff → Phase 13 (*Optimization*): audio/effects budget caps set here (D-risks) become the profiling baseline; `.ogg` conversion + settings sliders land alongside LOD and instancing work.
