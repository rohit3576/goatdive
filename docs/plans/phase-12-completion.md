# ✅ Phase 12 — Audio & Effects: Completion Report

> Companion to `phase-12-audio-fx.md` (execution plan). Records what was
> actually built, verification evidence, bugs found, and the gauntlet
> no-regression proof.

---

## Summary

| Step | Planned | Outcome |
|---|---|---|
| 1 | Sound-bank generator | ✅ `tools/gen_sounds.gd` — headless synthesizer, 15 slots (step/jump/land/bonk/coin/gate/trick/beep/go/bleat/fall/levelup + wind & two music loops), 16 kHz 16-bit PCM, seeded RNG — **regeneration is byte-identical** (SHA roundtrip verified). ~680 KB total. CC0 swap-in by filename, zero callers change. |
| 2 | Audio autoload | ✅ `scripts/audio/audio_manager.gd` (autoload `Sfx`) — code-built buses `Master → Music/Sfx/Ambience`; 15-slot registry; `play()` with pitch jitter + voice steal; **missing slots are silent no-ops**; `PROCESS_MODE_ALWAYS`. |
| 3 | Event one-shots | ✅ jump whoosh · land thud ∝ impact (+ bleat on stumble landings) · bonk · trick stingers per name (coin has its own ding) · gate chime (player-only, same guard as `camera_fx.gd:234`) · coin/level-up/upgrade/unlock stingers. |
| 4 | Poll-driven loops | ✅ footsteps (stride accumulator, surface-aware pitch ROCK/GRASS/SNOW/ICE) · wind (volume ∝ speed + altitude) · fall rush (vy-gated, once per airtime) · countdown beeps on integer crossings + GO at zero. Zero new signals (D3 held). |
| 5 | Music | ✅ calm ↔ drive crossfade keyed on `race_started`/`race_finished` only; 60 dB fade, ~1 s sweep. |
| 6 | Effects spawner | ✅ `scripts/fx/effects_spawner.gd` — code-built `GPUParticles3D` one-shots: landing dust ∝ impact (ALL goats — AI juice is world-visible), bonk debris, player gate bursts at the gate position, coin sparkles. Timer-freed (headless-safe, D10). |
| 7 | Weather | ✅ Camera-following snow emitter gated by the mountain's catalog snow line with hysteresis (`snow_gate` pure fn) — Snow Mountain 110 flakes, Alpine 36, Canyon 0; Canyon gets always-on dust (60) instead. `snow_peak=1.00` during the gauntlet's summit start. |
| 8 | Speed streaks | ✅ Camera-parented streak particles above 17 m/s (85% of `MAX_DOWNHILL_SPEED`), `CAM_FX`-gated; Phase 4 FOV kick untouched (D7). |
| 9 | Config + version | ✅ Phase 12 block (bus volumes, stride, particle caps, weather tables, streaks) · `VERSION 0.12.0-phase12`. |
| 10 | Verification | ✅ Smoke **23 pass / 0 fail** · Gauntlet **10 pass / 0 fail** · Boot checks **0 errors** (before *and* after) · generator determinism proven. |

---

## Gauntlet Results (No-Regression Proof)

Full 4-goat grand prix, Alpine Valley, player puppeted by a BOLD brain
(Phase 10/11 harness pattern), audio + effects layers live:

| Racer | Time | vs Phase 10/11 |
|:---|:---:|:---:|
| **YOU (Player AI)** | 35.40 s | *identical* |
| **BOLD** | 35.78 s | *identical* |
| **RECKLESS** | 36.50 s | *identical* |
| **CAUTIOUS** | 36.73 s | *identical* |

* **Spread**: 3.8% (assert ≤ 35%) · **Player obstacle hits**: 0 · **Intake**: `+77 🪙 · +438 XP`
* **Listener telemetry from the same run**: 98 one-shots · 32 footsteps · music `drive` mid-race · fx land=69 bonk=9 gate=7 coin=7 · snow peak 1.00 — the audio/effects layers ran the whole race and changed **nothing** about it.
* Bit-identical times for the third phase running = the Phase 12 contract (plan D2) held: `Sfx` and `EffectsSpawner` consume signals and poll snapshots; they never write physics.

### Measurement worth keeping

The gauntlet puppet is **airborne 81% of the race** (28.25 s air vs 6.5 s
grounded; 764 m flown vs 72 m run). 32 footsteps × 2.35 m stride = 75 m ≈
the grounded distance — the cadence math is exact; the goat simply flies
down the mountain. The soundscape's body is land thuds + fall rush + wind;
footsteps are touchdown punctuation. (F5 note: if flight feels excessive,
that's a physics-tuning question for Phase 13+, not an audio bug.)

---

## Smoke Battery (23/23)

| Group | Checks |
|---|---|
| Bank (S1) | all 15 WAVs on disk |
| Autoload (S2a–b) | `Sfx` mounted; Music/Sfx/Ambience buses built |
| Registry (S3–S4) | 15 loaded / 0 missing; `play()` on unknown slot skips safely, known slot registers |
| Event wiring (S5a–e) | jump→jump · stumble landing→bleat · coin trick→coin · gate chime player-only (AI gate silent) · level_up→levelup |
| Pure math (S6–S7) | `beep_at` crossings; `snow_gate` hysteresis both directions |
| Live level (S8a–c) | level + manager mount; real countdown yields exactly 3 beeps; GO fires at racing |
| Manager surface (S9) | race_state carries `grounded`/`surface`/`alt`/`vy` |
| Music (S10) | drive during racing, calm after finish signal |
| Spawner (S11a–e) | mounted; land/coin/gate bursts spawn; active count drains to 0 via timer (headless) |
| Weather (S12) | Alpine: snow 36 / dust 0 / ramps on above the line |

---

## Bugs Found & Resolved During Verification

1. **Dummy audio driver holds loop playbacks at exit**:
   - *Problem*: `--quit-after` boots reported `3 resources still in use` — the Dummy driver never releases `AudioStreamPlaybackWAV` refs for actively-playing loops (wind/music). A/B-tested: not the `loop_mode` mutation, not `_exit_tree` ordering.
   - *Fix*: headless contract enforced where it belongs — `Sfx._audible = DisplayServer.get_name() != "headless"`; in headless runs `play()` registers in the counters (smoke-observable) and never touches the mixer. Boot: 0 errors, 0 leaks.

2. **Footstep cadence starved by mini-hops** (design fix):
   - *Problem*: original `_footsteps_tick` reset the stride accumulator whenever `grounded` flickered false — on steep fast terrain that wiped progress dozens of times per race.
   - *Fix*: airborne **pauses** accumulation (distance is distance); only standing still resets. Then measured: grounded distance is genuinely just 72 m — cadence was exact after the fix.

3. **Autoload identifiers don't compile under `--script`** (Phase 10 lesson, hit again):
   - *Problem*: `EventBus.goat_jumped.emit(...)` in the harness = compile error.
   - *Fix*: `root.get_node("EventBus").emit_signal(...)` + dynamic `Config` const access via node lookup.

4. **Headless frames are unthrottled (~180 fps)**:
   - *Problem*: frame-budget waits starved — 400 frames didn't clear a 3 s countdown; smoke asserted too early (GO/music "missing").
   - *Fix*: all harness waits are wall-clock (`create_timer`), watchdogs are `Time.get_ticks_msec` deadlines. Gauntlet poll samples latch ("drive" wins over post-finish "calm").

5. **Spawner detection in the harness**:
   - *Problem*: probing `child.get("land_bursts")` — the var is `_land_bursts`; the public surface is the debug dict (the spawner was mounted all along).
   - *Fix*: match by script resource path; assert via `get_debug_state()` keys.

---

## Files Created & Modified

```text
tools/gen_sounds.gd                      # NEW: deterministic WAV synthesizer (plan D1)
tools/gen_sounds.gd.uid                  # NEW: script UID
scripts/audio/audio_manager.gd           # NEW: Sfx autoload — buses, bank, one-shots,
scripts/audio/audio_manager.gd.uid       #      poll loops, music crossfade, headless gate
scripts/fx/effects_spawner.gd            # NEW: one-shot bursts, weather, speed streaks
scripts/fx/effects_spawner.gd.uid        # NEW: script UID
assets/sounds/*.wav           (15 files) # NEW: generated placeholder bank (~680 KB)
assets/sounds/*.wav.import    (15 files) # NEW: import companions
docs/plans/phase-12-audio-fx.md          # NEW: execution plan (pre-work)
docs/plans/phase-12-completion.md        # NEW: this report
scripts/game/config.gd                   # Phase 12 tunables, VERSION 0.12.0-phase12
scripts/race/race_manager.gd             # grounded/surface/alt/vy in get_race_state()
scenes/terrain/mountain_level.gd         # EffectsSpawner mount (TrickDetector precedent)
project.godot                            # Sfx autoload registered
```

Temp harnesses (`smoke_phase12.gd`, `gauntlet_phase12.gd`) ran, passed,
and were deleted per repo lifecycle.

---

## Next Steps: User F5 Verification

1. **Sound**: run a race — countdown beeps into GO, wind rising with speed and altitude, footstep pitch changing on rock vs snow, land thuds scaled by drop size, the goat's bleat on hard slams, coin dings, gate chimes, level-up sting.
2. **Music**: calm pad at the start/menu → drive loop kicks in at GO → back to calm on finish.
3. **Effects**: dust bursts on every landing (watch the AI herd too), gold gate bursts, coin sparkles, snowfall above the snow line (race Snow Mountain for the full storm), air streaks above ~17 m/s.
4. **Pause**: Esc — music and UI feedback keep working (D5).
5. Optional: replace any `assets/sounds/*.wav` with a CC0 file of the same name — no code changes needed.

Handoff → Phase 13 (*Optimization*): the particle caps and headless audio
gate set here are the profiling baseline; `.ogg` conversion, LOD, and
instancing work land next, targeting the 60 FPS web build.
