# ✅ Phase 14 — Web Build: Completion Report

> Companion to `phase-14-web-build.md` (execution plan). Records what was
> actually built, the on-device numbers, the integration fixes, and the
> headless no-regression proof.

---

## Summary

| Step | Planned | Outcome |
|---|---|---|
| 1 | Export pre-flight | ✅ Done previous session — 4.7.2 templates, `export_presets.cfg` committed-pending (compat renderer, **non-threaded** D2, canvas resize policy 2, focus-on-start), `build/` gitignored. |
| 2 | Durable build script | ✅ `tools/build_web.sh` — headless export + artifact ledger (raw/gzip/brotli). **40.27 MB raw / 7.38 MB brotli**, PASS. |
| 3 | Local serve + boot smoke | ✅ `python3 -m http.server 8060 --directory build/web`; real Chrome over CDP (`:9222`, occlusion/throttle flags off — the MCP browser throttled to 2 fps, unusable). **Boot 0 errors**, `RENDER: web floor applied` present, LOW self-activates. Note: the game boots **straight into the race** (no menu scene — `main.gd → mountain_level`), so "menu→race" = boot→countdown→GO. |
| 4 | Chrome measurement | ✅ See table below. `?quality=high` URL lever added (`Config._init`, plan D3) and oracle-verified (193×193 terrain). |
| 5 | Cross-browser matrix | ✅ with caveats — resize matrix PASS; **Edge not installed on this machine** (Chromium coverage stands via Chrome, D4); **Safari = owner eyeball** (launched; console capture needs `safaridriver --enable`, an owner action). |
| 6 | Web integration fixes | ✅ 3 fixes, each F5-verified (below). Audio + canvas-focus verified as already-correct. |
| 7 | Profile tuning | ✅ **Data-driven no-op** — Chrome never dropped a frame even at HIGH (grid 192); `grid_low` stays 128 on all five mountains (D8), HIGH frozen. |
| 8 | Config + version | ✅ Phase 14 block in `config.gd` (documents the lever + lock policy + the no-op tuning); `VERSION 0.14.0-phase14`. No new numeric knobs survived step 6. |
| 9 | Verification | ✅ Gauntlet **bit-identical** (35.40/35.78/36.50/36.73), probe counters **exact** vs Phase 13, boot 0 errors, final build PASS + browser-gated. |

---

## Chrome desktop (the gate)

Method: rAF frame-count sampling over 1 s buckets (devtools-equivalent —
the F3 overlay is human-read by design, D6), goat driven with held W +
Space on the CDP-attached real Chrome, window visible. Synthetic input
was proven to reach the game via the Esc → `UI: pause on` console oracle.

| Profile | Terrain | avg fps (×3) | min fps | load to content |
|---|---|---|---|---|
| LOW (default) | 129×129, 86–104 ms | **60.4 / 60.4 / 60.4** | **60** | ~550 ms |
| HIGH (`?quality=high`) | 193×193, 180–206 ms | **60.6 / 60.3 / 60.4** | **60** | ~610 ms |

Both profiles vsync-locked, zero dropped seconds. Gate (avg ≥ 55) passed
with the entire display budget to spare. Time-to-race is countdown-bound
(3.0 s) in both. Full boot ledger: engine 150 ms → main scene ~300 ms →
terrain ~475 ms → veg/course/obstacles/coins by ~550 ms.

### Resize matrix (mid-race, HIGH profile)

| Size | fps | Notes |
|---|---|---|
| 1280×720 | 60.2 | input alive after resize (pause oracle fired) |
| 1470×560 (ultrawide ~2.6:1) | 60.2 | |
| 900×870 (near-square) | 60.1 | |

HUD visual intactness at the three ratios: screenshots saved
(`step3-boot-state.png` in repo root, `.playwright-mcp/`) — owner eyeball
recommended, no DOM to assert against.

---

## Web integration fixes (step 6)

| Fix | Root cause | Change | F5 oracle |
|---|---|---|---|
| **Pointer-lock re-capture** | Chrome denies `requestPointerLock` from keydown handlers (+ cooldown right after Esc-exit) → resume/garage-close/restart spammed warnings and left a freed invisible mouse mid-race | `race_hud.gd` (`_set_paused`, `_restart_race`) + `garage.gd` (`close_garage`): recapture requests now **web-gated**; desktop path untouched. head_camera's existing click-to-capture is the web recovery; pause hint now says "click to re-capture the mouse" on web | Esc×2 → pause prints, **no lock warning** |
| **`get_global_transform` error on every scene reload** | The `Sfx` autoload polls `get_race_state()` across the reload teardown window — player goat already out-of-tree → `node_3d.cpp` error once per reload | `race_manager.gd`: `get_race_state()` returns the empty snapshot when manager or player is out-of-tree (audio fades to floor — the correct answer); literal extracted to `_empty_race_state()` | R-reload → clean re-boot, **no error** (browser + headless) |
| **Garage `G` key** | `keycode` (layout-mapped) vs the input map's `physical_keycode` — broke on non-US layouts | `garage.gd` `_unhandled_input` on `physical_keycode` (G + Esc) | G×2 → garage open/close prints |

**Verified already-correct (no code needed):**
- Canvas keyboard focus — the preset's focus-on-start works: keys land
  with no click-first (R drove a reload on a fresh, never-clicked load).
- Page scroll steal — the page is canvas-only, nothing to scroll.
- Audio — `AudioContext` warnings fire pre-gesture (expected), stop after
  first input; engine's resume-on-input handles it. **Owner checklist:
  click once on load and confirm wind/music is audible.**

---

## Headless regression (the gauntlet gate)

Recovered the Phase 9 harness from git (`5cbea3b^:gauntlet_phase9.gd`,
temp file, deleted after — lifecycle rule), fixed two Variant-inference
lines for the strict parser:

| Racer | Phase 13 | Phase 14 |
|---|---:|---:|
| YOU | 35.40 s | **35.40 s** |
| BOLD | 35.78 s | **35.78 s** |
| RECKLESS | 36.50 s | **36.50 s** |
| CAUTIOUS | 36.73 s | **36.73 s** |

**Bit-identical.** 0 obstacle hits, 4 teleports, 5/5 harness checks, boot
0 errors (only the harness's own benign `script.reload` note).

`tools/perf_probe.gd` vs the Phase 13 after-table — deterministic counters
**exact**: snapshot builds/frame 1.00, progression lookups 0, live d2f
6,848 segments/s, grid parity 590/600, speedup 4.1×. Wall-clock timings
within jitter (terrain HIGH 213 ms vs 221, LOW 91 vs 96). Version line
prints `0.14.0-phase14`.

---

## Bugs Found & Resolved During Verification

1. **Stale `index.pck` from browser cache** — the first `?quality=high`
   run silently booted LOW because Chrome served the old pck (python
   `http.server` sends no cache headers; the pck URL is stable across
   rebuilds). Diagnosis: byte-size check; fix for measurement: CDP
   `Page.reload({ignoreCache:true})`. **Phase 15 must send
   `Cache-Control: no-cache` + ETag/immutable-hashed assets or the same
   trap ships to users after every deploy.**
2. **First ?quality=high attempt had no lever** — plan D3 said "tiny URL
   param override" but it wasn't landed in steps 1–2; added in `Config._init`
   via `JavaScriptBridge.eval` (web branch only; desktop env path byte-identical).
3. **Occlusion throttling kills the game loop** — a backgrounded/covered
   browser window freezes rAF → engine; even `--disable-renderer-backgrounding`
   wasn't enough on macOS without `--disable-features=…,OcclusionWindowing`.
   The QA Chrome launch line (in this doc's serve step) is the durable recipe.

---

## Owner checklist (needs human eyes/ears)

- [ ] Safari (window opened to `http://localhost:8060/`): boots, race
      completes, audio after first click. Console capture would need
      `safaridriver --enable` (sudo, once) — skipped per D4 best-effort.
- [ ] Audio on Chrome: click once on load → wind/music audible.
- [ ] HUD eyeball at 1280×720 / ultrawide / near-square (screenshots saved).

## Handoff → Phase 15 (*Vercel Deployment*)

- **Artifacts**: `build/web/` — 9 files, ledger in `build/size-ledger.txt`.
  Totals: **40.27 MB raw / 10.61 MB gzip / 7.38 MB brotli (q11)**. The
  wasm is 97% of the payload; everything else is noise.
- **Thread mode**: **non-threaded** (D2 held — 60 fps locked without it).
  No COOP/COEP headers needed; any static host works, including
  GitHub-Pages-style ones.
- **Compression**: serve wasm with `Content-Encoding: brotli` (or gzip:
  10.6 MB) — configure on Vercel; verify the ledger numbers in
  devtools Network after deploy.
- **Caching (the trap)**: `index.html` must be `no-cache`; hashed/immutable
  for the rest if the host supports it. See bug #1 above.
- **Default profile**: LOW on web (auto via `OS.has_feature("web")`);
  `?quality=high` is the A/B bookmark (D3) — HIGH is a curiosity, not shipped.
- **Integration notes the deploy must respect**: click-to-capture pointer
  lock (no auto-lock without gesture — do not "fix" this host-side);
  audio resumes on first gesture; page should stay canvas-only (no
  scrollable chrome that could steal arrow/space keys).
- **Env**: QA recipe = `python3 -m http.server 8060 --directory build/web`
  + dedicated Chrome with `--remote-debugging-port=9222
  --disable-background-timer-throttling --disable-backgrounding-occluded-windows
  --disable-renderer-backgrounding
  --disable-features=CalculateNativeWinOcclusion,OcclusionWindowing
  --user-data-dir=/tmp/goatdive-chrome-profile --app=http://localhost:8060/`.
