# Phase 14 — Web Build: Execution Plan

> Continues from `phase-13-completion.md`. README Phase 14 list: export
> for Web (HTML/WASM), test Chrome/Edge/Safari, screen sizes, keyboard +
> mouse; mobile controls later. Target: **60 FPS desktop-Chrome** — the
> number Phase 13's whole optimization effort was aimed at.
>
> The ground is already prepared: `gl_compatibility` everywhere (Phase 2
> D1), zero texture assets, MultiMesh instancing, the Phase 13 LOW profile
> (grid 128, terrain build 96 ms vs 221 HIGH) **wired to auto-activate on
> web** via `OS.has_feature("web")`, the web render floor (shadow atlas
> 2048, MSAA off) applied at boot in `main.gd`, and two durable
> instruments: `tools/perf_probe.gd` (headless A/B) and the F3 overlay
> (fps / proc ms / phys ms — readable in-browser). The load-time ledger
> (`TERRAIN/COURSE/OBSTACLES/COINS` prints) lands in the browser console
> where devtools can timestamp it.
>
> What Phase 14 adds: an export preset + durable build script, a real
> on-device measurement loop, the cross-browser matrix, whatever small
> web-integration fixes the loop surfaces, and the `grid_low` per-mountain
> tuning pass — all without touching a single desktop physics value (the
> gauntlet gate rides again).

---

## Steps

| # | Step | Deliverable |
|---|---|---|
| 1 | Export pre-flight | Verify Godot **4.7.2** web export templates installed (`--export-release` fails loudly if not — fix before anything else). Commit `export_presets.cfg` (Web preset, compat renderer, canvas resize policy, thread-support setting per D2). `.gitignore` the build output dir. |
| 2 | Durable build script | `tools/build_web.sh` (gen_sounds/perf_probe precedent): headless `--export-release`, then an artifact ledger — every file, raw bytes, gzip + brotli estimates, total — PASS/FAIL. The Phase 15 deploy reads this ledger, so it stays durable. |
| 3 | Local serve + boot smoke | Serve `build/web/` over HTTP (browsers block wasm from `file://`), open in desktop Chrome: **0 console errors**, boot ledger captured (LOW profile must self-activate — `RENDER: web floor applied` line present), main menu → race start works with mouse + keyboard. |
| 4 | Chrome measurement pass | Full Alpine race with F3 up: avg/min fps, proc ms, phys ms — recorded per quality profile (LOW default; HIGH via the `?quality=high` URL lever, D3). Repeat ×3. Load budget from the devtools console timestamps (terrain/veg/course/obstacles/coins + time-to-menu). |
| 5 | Cross-browser matrix | Edge + Safari (desktop): boot 0 errors, full race completes, audio works. Window sizes: 1280×720, an ultrawide, a near-square — HUD chips/minimap/speedometer intact, resize mid-race doesn't break pointer lock or HUD. |
| 6 | Web integration fixes | Whatever 3–5 surface — expected candidates: pointer-lock re-capture after Esc releases it (our pause key collides with the browser's release gesture), audio-start-on-first-gesture, canvas keyboard focus (arrows/space must not scroll the page). Minimal diffs, each F5-verified in-browser. |
| 7 | Profile tuning | `grid_low` per mountain driven by the Chrome numbers — mountains with fps headroom try 96 (catalog keys exist for exactly this). Desktop HIGH never touched; headless gauntlet re-run as the no-regression gate. |
| 8 | Config + version | Phase 14 block in `config.gd` if any new knobs survive step 6 (URL quality lever, pointer-lock policy); `VERSION 0.14.0-phase14`. |
| 9 | Verification | Build script PASS · Chrome fps gate (below) · matrix results · input/gesture checklist · headless regression: gauntlet HIGH bit-identical (35.40/35.78/36.50/36.73), boot 0 errors, `perf_probe.gd` unchanged from the Phase 13 A/B table. Completion doc + Phase 15 handoff (artifact layout, sizes, headers/compression notes). |

---

## Decisions

| # | Decision | Rationale |
|---|---|---|
| **D1** | Compat renderer + WebGL2 stays; no WebGPU | Phase 2 D1 was the call; the art style (vertex colors, one light, fog) doesn't need more, and WebGL2 is the widest browser floor. |
| **D2** | Export **non-threaded** first; threaded only as a measured fallback | No-thread exports deploy anywhere (no COOP/COEP headers); threaded buys engine-thread-off-main-loop at the cost of cross-origin-isolation requirements on every host — a Phase 15 constraint we only accept if the fps gate fails without it. A/B both if the gate is marginal. |
| **D3** | LOW is the web default (already wired); `?quality=high` URL param is the A/B lever | `GOATDIVE_QUALITY` env doesn't exist in a browser; `OS.has_feature("web")` already selects LOW. A tiny URL-param override in `Config._init` keeps on-device A/B one bookmark away. HIGH on web is a curiosity, not a shipped mode. |
| **D4** | Desktop Chrome is the 60 FPS gate; Edge/Safari are smoke gates | README's own ordering — Chrome first, then mobile. Edge is Chromium (cheap confirm); Safari is best-effort desktop-only this phase. |
| **D5** | `export_presets.cfg` committed, build artifacts never | The preset is config (reviewable, reproducible); `build/web/` is output — gitignored like any build dir. |
| **D6** | Measurement = F3 overlay + console load ledger; no new telemetry | Phase 13 built the instruments precisely so Phase 14 wouldn't need to. In-browser numbers are read by hand from F3/devtools and recorded in the completion doc — same-machine A/B discipline as the probe. |
| **D7** | Mobile/touch explicitly skipped | README parks mobile controls "later"; pointer events, touch HUD, and iOS Safari quirks are their own phase, not a stretch goal here. |
| **D8** | `grid_low` tuning is Chrome-data-driven; HIGH is frozen | The catalog's per-mountain grid keys exist for this exact pass. Any tuning lands on LOW only — the desktop gauntlet stays bit-identical by construction (Phase 13 D2). |

---

## Risks

| Risk | Impact | Mitigation |
|---|:---:|---|
| **Export templates missing / version drift** | Blocks all | Step 1 pre-flight; pin 4.7.2 (the editor version in `project.godot` features). |
| **wasm payload weight** (~25–40 MB raw, ~8–12 MB brotli expected — measure, don't assume) | Medium | Ledger in step 2 quantifies it; transfer-size + cache headers are Phase 15 host config, not engine work. If first-load is brutal, note it — a loading screen is a Phase 15 polish item, not a silent scope creep. |
| **Esc = browser pointer-lock release AND our pause** | Medium | Expect a "pause shows, mouse freed, click to recapture" flow; step 6 makes it deliberate (re-capture on click while paused, or pause-on-lock-loss). F5 in all three browsers. |
| **Audio silent until first user gesture** | Low | Browser rule, engine handles resume-on-input; verify music starts after the first click/keypress (step 6 checklist). |
| **Threaded export needs COOP/COEP headers** | Medium | Only relevant if D2's fallback triggers; then Phase 15 `vercel.json` sets the headers and GitHub-Pages-style hosts are off the table. |
| **Safari WebGL2 quirks** (desktop) / iOS | Low | D4: Safari is a smoke gate; anything broken is documented, not blocking. Mobile is D7. |
| **Keyboard focus / page scroll stealing arrows-space** | Low | Engine canvas grabs keys when focused; verify a click in-canvas before racing; step 6 fix if needed. |
| **HUD at extreme aspect ratios** | Low | Anchored layout from Phase 11; eyeball three sizes (step 5); chips/minimap use corner presets that should hold. |
| **Tuning changes LOW race feel** | Medium | Only grid values move; LOW gauntlet gate = race-completes + spread ≤ 35% (Phase 13's LOW run: 0.6% spread); HIGH gauntlet re-run untouched. |

---

## Verification (gate to completion doc)

1. **Build** — `tools/build_web.sh` PASS: export completes, ledger lists every artifact with raw/compressed sizes.
2. **Chrome desktop (the gate)** — 0 console errors on boot; full Alpine race completes; F3 **avg fps ≥ 55** (60 target with tolerance), phys ms within the Phase 13 budget × device factor; load ledger captured; ×3 runs consistent.
3. **Edge + Safari** — boot, full race, 0 errors; Safari quirks documented either way.
4. **Sizes + input** — 1280×720 / ultrawide / near-square: HUD intact, resize mid-race safe; WASD + arrows + space + mouse + pause + pointer re-capture all behave; audio starts after first gesture.
5. **Headless regression** — gauntlet HIGH bit-identical (35.40 / 35.78 / 36.50 / 36.73), spread ≤ 35%, intake intact; `perf_probe.gd` matches the Phase 13 after-table; boot 0 errors.
6. **Handoff** → Phase 15 (*Vercel Deployment*): artifact dir + ledger, chosen thread mode and its header requirements, compression expectations, default profile (LOW), and any step-6 integration notes the deploy must respect.

Handoff → Phase 15 (*Vercel Deployment*).
