# Phase 13 — Optimization: Execution Plan

> Continues from `phase-12-completion.md`. README Phase 13 list: 3D models,
> LOD, instancing, compressed textures, optimized collisions, lighting,
> browser performance — 60 FPS desktop-Chrome target, mobile later.
>
> A full codebase survey (all 30 scripts, scenes, `project.godot`, assets)
> reframes the phase: **the GPU-side checklist is already green by earlier
> architecture** — MultiMesh instancing since Phase 5/6 (veg + coins),
> zero texture assets (procedural ramps + vertex-color terrain shader),
> primitive-shape obstacle colliders, one DirectionalLight, `gl_compatibility`
> renderer, ~60 draw calls total. The measured costs are elsewhere:
>
> | # | Hotspot (file:line) | Cost |
> |---|---|---|
> | A | `distance_to_finish()` O(polyline) scan — per racer per tick (`race_manager.gd:96-104`) **plus** 3-4× per frame via `get_race_state()` pollers (`race_hud.gd:293`, `audio_manager.gd:253`, `effects_spawner.gd:71`, `debug_overlay.gd:49`) | ~125k segment projections/sec in GDScript |
> | B | `get_race_state()` full snapshot (dict + standings duplicate+sort + AI dicts + time strings) rebuilt 3-4× per frame | alloc/GC churn every frame |
> | C | `get_node_or_null("/root/Progression")` inside every `_get_*_mult()` (`goat_controller.gd:129-151`, called at :272,:275,:299,:304,:331 + via `get_debug_state()` from `ai_goat.gd:136`, `camera_fx.gd:79`, `trick_detector.gd:70`) | ~2,000 node lookups/sec |
> | D | AI obstacle avoidance scans ALL ~220 records per AI per tick (`ai_goat.gd:83-116`) | ~40k distance checks/sec |
> | E | Coins pickup scans every coin record per tick (`coins.gd:133-142`) | O(hundreds)/tick |
> | F | Near-miss scan O(220)/tick + **leftover hot-path `print()`s** (`trick_detector.gd:83,:88`) | string fmt + stdout per frame |
> | G | Full-mesh trimesh over 73,728-tri terrain, `grid=192` for all 5 mountains (`terrain_generator.gd:21,:233-236`) | physics contact cost |
> | H | `save_to_disk()` on every progression mutation (`progression.gd:37-44`) — sync ConfigFile write | disk I/O mid-race (IDB on web) |
> | I | Minimap `queue_redraw()` + `get_racer_markers()` alloc + `_session_coins()` node lookup every frame (`race_hud.gd:290-317`) | per-frame allocs + redraw |

---

## Steps

| # | Step | Deliverable |
|---|---|---|
| 1 | Measurement first | `tools/perf_probe.gd` (durable, headless, deterministic — `gen_sounds.gd` precedent): micro-benchmarks for A–F per-tick costs + captures the existing load-time prints (`terrain_generator.gd:138-141` etc.); `debug_overlay` (F3) gains FPS / frame-time / script-ms lines. **Baseline table recorded in the completion doc before any fix lands.** |
| 2 | Snapshot economy | `race_manager`: frame-stamped snapshot cache — `get_race_state()` builds at most **one** dict per frame, HUD/Sfx/EffectsSpawner/debug all consume it; `EffectsSpawner` + `audio_manager` get a cheap `get_player_speed()`-style accessor (spawner needs only speed, `effects_spawner.gd:71`); standings recompute only when dirty (overtake or finish), `time_str` formatted on demand. |
| 3 | Advance-only progress | `course_builder.distance_to_finish()` gains a per-racer cursor (monotonic walk over the polyline — **the AI already does exactly this**, `ai_goat.gd:56-64` precedent): racers only move forward, so O(P) → O(1) amortized; cursor reset on race restart; fallback rescan if distance jumps backward. Value-identical by construction, asserted in smoke. |
| 4 | Cached refs, cold debug state | `goat_controller` caches the `Progression` autoload in `_ready` (one lookup per goat, ever); `_get_*_mult()` become plain field reads; `get_debug_state()` stays but only cold paths call it — `camera_fx`/`trick_detector`/`ai_goat` hot paths switch to direct field accessors; `ai_goat` caches its `race_manager` ref (kills the per-tick `get_first_node_in_group`, `ai_goat.gd:160`). |
| 5 | Shared spatial grid | One XZ bucket grid built at level build (cell ≈ 12 m, the AI's avoidance radius): obstacles + coins register into it; `ai_goat` avoidance, `coins` pickup, `trick_detector` near-miss all query their cell — three O(N×60) scans become three O(cell)/tick. Brute-force equality asserted in smoke. |
| 6 | Hot-path hygiene | Delete the two leftover `print()`s (`trick_detector.gd:83,:88`); minimap throttled to 12 Hz + redraw only when markers/gates change; `race_hud` caches the `Coins` node; `get_racer_markers()` allocates only on overtake/finish (dirty flag), not per frame. |
| 7 | Save debouncing | `progression`: dirty-flag + 2 s debounce; forced flush on race finish, purchase, unlock, and `tree_exiting`. During a race only the finish banks coins (`race_manager.gd:299`), so the data-loss window is bounded and tiny. |
| 8 | Terrain density per profile | `MountainCatalog` gains an optional `grid` override; a `Config` quality profile (LOW/HIGH) selects it: **desktop default stays `grid=192` — gauntlet path byte-identical**; web/mobile profile ships `grid=128` (Alpine/Canyon) with per-mountain tuning to 96 where the survey's build-time prints show win. Same lever shrinks the trimesh 2-4× (G) — trimesh itself stays (Phase 2 decision, `terrain_generator.gd:10-12`). |
| 9 | Render settings for web | Shadow map 2048 (compat-renderer default 4096 is heavy for GLES3 web); keep 1 light, fog, no MSAA on web (documented trade — F5 check); all knobs in `Config` Phase 13 block. No LOD/chunking this phase (D10). |
| 10 | Config + version | Phase 13 block in `config.gd` — quality profile, grid overrides, minimap Hz, save debounce, shadow size — + `VERSION 0.13.0-phase13`. |
| 11 | Verification | Perf probe A/B (targets below) · smoke battery (value-identity for steps 3 & 5, frame-stamp behavior, debounce timing, restart cursor reset) · **gauntlet bit-identical** (desktop profile, untouched physics) · boot 0 errors · load-time comparison HIGH vs LOW. |

---

## Decisions

| # | Decision | Rationale |
|---|---|---|
| **D1** | Optimize script + physics density, not draw calls | Survey: ~60 draw calls, 1 shadowed light, no post-FX, procedural textures. The bottleneck is measured GDScript per-tick work (A–F) and trimesh contact cost (G). Classic LOD/instancing work would attack a problem this codebase doesn't have. |
| **D2** | Physics values untouched → gauntlet stays bit-identical | Every step 2-7 is a lookup/allocation refactor returning **identical values**; step 8's density change is profile-gated and never touches the desktop default. 35.40/35.78/36.50/36.73 remains the gate. |
| **D3** | Advance-only cursors for progress + coins | Racers move monotonically forward down the polyline; the AI's windowed nearest-waypoint walk (`ai_goat.gd:56-64`) is the in-repo precedent. Restart resets, backward jump rescans — correctness asserted against the old O(P) implementation in smoke. |
| **D4** | One frame-stamped snapshot, many consumers | The Phase 11/12 listener pattern (HUD, Sfx, FX all poll) is correct architecture — the bug is that each poller rebuilds the world. Cache by frame in `race_manager`; listeners stay decoupled (no new signals, Phase 11 D3 precedent holds). |
| **D5** | One shared XZ grid for obstacles + coins + near-miss | Three separate scans of the same world state today. One build-time structure, O(cell) queries, zero per-frame maintenance (obstacles/coins are static during a race). |
| **D6** | Profile-gated terrain density, not mesh LOD | A single 73k-tri mesh is **one draw call** — chunking/LOD adds complexity for no measured win. Halving `grid` halves both tri count and trimesh cost, the actual physics driver. Per-mountain `grid` in the catalog keeps desktop exactly as-is (D2). |
| **D7** | Debounced saves with bounded loss | Sync ConfigFile write per mutation is disk/IDB I/O in gameplay paths. A 2 s dirty-window plus forced flushes at finish/purchase/unlock/exit costs nothing observable and bounds loss to nothing that matters mid-race (coins bank at finish, `race_manager.gd:299`). |
| **D8** | Web render floor: shadow 2048, no MSAA, compat stays | Already `gl_compatibility` everywhere (`project.godot:93-94` — Phase 2 D1, the right call). Shadow default 4096 is the one heavy GLES3 setting; MSAA on compat web is a bandwidth tax this art style doesn't need (vertex colors + fog). Knobs in `Config` so Phase 14 can A/B them on-device. |
| **D9** | `tools/perf_probe.gd` is durable, harnesses stay temp | Phase 14 (web build) needs the same A/B numbers on-device; a committed deterministic probe (like `gen_sounds.gd`) makes "60 FPS target" measurable instead of vibes. One-off smoke/gauntlet harnesses follow the usual delete-after lifecycle. |
| **D10** | Explicitly skipped: mesh LOD, texture compression, instancing work | Survey says done already or not applicable (MultiMesh everywhere, zero texture assets). Recorded so the completion doc can close the README checklist line-by-line with evidence. |

---

## Risks

| Risk | Impact | Mitigation |
|---|:---:|---|
| **Refactor changes a physics-feeding value** (mult lookups, grip) | High | Steps 2-7 are lookups-only; smoke asserts value-identity (old vs new) on sampled points; gauntlet bit-identical is the gate (D2). |
| **Cursor desync** (teleport, restart, respawn) | Medium | Cursor reset on race restart; backward-distance rescan fallback; smoke covers restart + mid-race resample equality. |
| **Stale shared snapshot** (listener reads last frame's state) | Low | Frame-stamped cache — same frame returns same dict, next frame rebuilds; one frame of latency equals today's poll order. Smoke asserts stamp behavior. |
| **Grid cell boundary misses** (obstacle straddles cells) | Medium | Register in every cell the shape's AABB touches; smoke brute-force-compares query results vs full scan per mountain. |
| **Web profile changes race feel** (terrain grid alters lines) | Medium | Physics params untouched — only mesh resolution; LOW-profile smoke gates race-completes + time tolerance; F5 eyeball on both profiles; desktop default unchanged. |
| **Debounced save lost on tab kill** | Low | Flush on `tree_exiting` + finish/purchase/unlock; mid-race only finish banks coins — documented ≤2 s window. |
| **Shadow/MSAA changes alter the look** | Low | F5 visual pass; both knobs in `Config` for instant revert. |
| **Stale global class cache** (Phase 11/12 lesson) | Medium | New `class_name` count kept to zero (probe runs via `--script`); `godot --headless --import` before every run — documented pre-run step. |

---

## Verification (gate to completion doc)

1. **Perf probe A/B** — headless, per mountain: `distance_to_finish` per-racer per-tick cost (target: O(P) → O(1) amortized, ≥50× at P≈300); `get_race_state()` builds/frame (3-4 → 1); Progression node lookups/sec (~2,000 → ~4, once per goat at ready); obstacle/coin/near-miss scans (O(N) → O(cell), ≥20× at N≈220); load-time prints HIGH vs LOW profile.
2. **Smoke battery** — value-identity: cursor distance == brute-force distance at N sampled positions per mountain, incl. restart; grid query results == brute-force scan; snapshot frame-stamping; debounce fires ≤2 s and flushes at finish/exit; minimap throttle keeps gates+markers correct; 0 errors.
3. **Gauntlet** — 4-goat grand prix, Alpine Valley, desktop profile: finishing times **bit-identical** to Phase 10/11/12 (35.40 / 35.78 / 36.50 / 36.73 s), spread ≤ 35%, 0 obstacle-hit regressions, intake intact.
4. **Boot + load budget** — `--headless` boot 0 errors before/after import pass; LOW-profile terrain build+trimesh ms captured (the Phase 14 web load budget baseline).

Handoff → Phase 14 (*Web Build*): export preset, on-device Chrome numbers from `perf_probe.gd` + F3 overlay, and the LOW profile as the shipped default candidate.
