extends Node
## Immutable game tunables. One source of truth.

const VERSION := "0.13.0-phase13"
const DEBUG := true

# Gravity / movement (numbers are first guesses — F5 + overlay tunes them).
const GRAVITY := 9.8
const MOVE_SPEED := 8.0
const MOVE_ACCEL := 20.0
const FRICTION := 6.0
const MAX_DOWNHILL_SPEED := 20.0
const AIR_CONTROL := 0.3
const SLOPE_ACCEL_MIN_DEG := 5.0
const JUMP_VELOCITY := 4.5

# Phase 3 — surfaces & grip (one scalar per surface, decision D3).
const GRIP_ROCK := 1.0
const GRIP_GRASS := 0.85
const GRIP_SNOW := 0.5
const GRIP_ICE := 0.25
const TURN_RATE := 2.5  # rad/s at full grip

# Phase 3 — steep bands (goat.tscn floor_max_angle mirrors CLIMB_ANGLE_DEG).
const SLIDE_ANGLE_DEG := 42.0
const CLIMB_ANGLE_DEG := 55.0

# Phase 3 — jump feel & impacts.
const JUMP_COYOTE := 0.12
const JUMP_BUFFER := 0.12
const STUMBLE_IMPACT := 12.0
const STUMBLE_TIME := 0.4

# Camera.
const MOUSE_SENS := 0.003

# Phase 4 — camera FX master switch + speed FOV kick + bonk gate.
# static (not const) so the smoke test can A/B the exact Phase 3 feel at runtime.
static var CAM_FX := true
const FOV_BASE := 78.0
const FOV_MAX := 88.0
const BONK_MIN_SPEED := 5.0  # m/s into a wall before the camera cares
const BONK_COOLDOWN := 0.35  # s between bonk signals (anti-jackhammer, Ph8)

# Phase 4 — bob + FOV (plan Step 2). Amplitudes are subtle first guesses.
const BOB_RATE := 9.0  # bob phase rad/s at MOVE_SPEED (rate scales with speed)
const BOB_AMPL := 0.05  # m vertical at full scale
const BOB_SWAY := 0.02  # m lateral at full scale
const FOV_LERP := 5.0  # 1/s easing toward the speed-target FOV

# Phase 4 — slope tilt + carve lean (plan Step 3).
const TILT_MAX_DEG := 6.0  # slope tilt cap, both axes
const SLIDE_TILT_SCALE := 1.5  # tilt multiplier while sliding steeps
const LEAN_MAX_DEG := 4.0  # carve lean cap
const LEAN_GAIN := 0.25  # heading-rate (rad/s) → lean fraction
const LEAN_SMOOTH := 6.0  # 1/s heading-rate smoothing

# Phase 4 — jump/land/fall dynamics (plan Step 4). Spring impulses are
# VELOCITY kicks; with k=220 they land at ~0.05 m / ~2° peaks.
const DIP_JUMP := 0.75  # m/s upward pop on jump
const DIP_LAND := 2.2  # m/s downward dip per unit impact-scale
const DIP_PITCH_JUMP := 0.5  # rad/s pitch-up pop on jump
const DIP_PITCH_LAND := 0.8  # rad/s pitch-down per unit impact-scale
const DIP_SPRING_K := 220.0
const DIP_SPRING_C := 18.0
const FALL_DRIFT_MIN := 5.0  # m/s fall speed where nose-drift starts
const FALL_PITCH_MAX_DEG := 4.0
const FALL_SMOOTH := 3.0  # 1/s fall-drift easing

# Phase 4 — impact shake (plan Step 5), trauma² model.
const SHAKE_REF_IMPACT := 10.0  # impact mapping to full trauma
const SHAKE_DECAY := 1.6  # trauma per second
const SHAKE_FREQ := 25.0  # Hz base (rotational; positional runs slower)
const SHAKE_POS := 0.1  # m at full trauma²
const SHAKE_ROT_DEG := 2.0  # degrees at full trauma²

# Phase 5 — vegetation caps (plan D4, web perf D9).
const VEG_PINES := 800
const VEG_ROCKS := 400
const VEG_TUFTS := 3000

# Phase 5 — crash tumble, ragdoll-lite (plan D6). The capsule transform
# stays upright; only the visible Body node spins (physics stays sane).
const TUMBLE_MIN_IMPACT := 10.0  # m/s wall hit while airborne
const TUMBLE_SPIN_GAIN := 0.8  # rad/s of spin per m/s of impact
const TUMBLE_SPIN_MAX := 12.0  # rad/s
const TUMBLE_SPIN_FRICTION := 6.0  # rad/s lost per s while grounded
const TUMBLE_RECOVER_SMOOTH := 10.0  # 1/s upright alignment
const TUMBLE_RECOVER_SPEED := 2.0  # m/s — below this, recovery may start

# Phase 6 — race system (plan: docs/plans/phase-6-race-system.md).
const RACE_COUNTDOWN := 3.0
const RACE_GATE_COUNT_MAX := 12
const RACE_GATE_SPACING := 70.0  # m of horizontal travel between gates
const RACE_GATE_WIDTH := 10.0
const RACE_GATE_AVOID_PINE_R := 4.0  # gates nudge away from pine records
const RACE_FINISH_ALT := 12.0  # valley altitude where the walk ends
const RACE_PLAYABLE_RADIUS := 440.0  # inside the distant-peak ring
const RACE_WRONG_WAY_TIME := 2.0  # s of backtracking before the flash
const RACE_GATE_PASS_FOV_POP := 2.0  # deg — a pass reads "noted", not "exploded"

# Phase 7 — AI goats (plan: docs/plans/phase-7-ai-goats.md D4/D5/D6).
# Skill profiles: speed cap (m/s, lift-off point), lookahead (m), ledge
# drop that triggers a jump (m — eagerness: lower = jumps more).
const AI_TURN_RATE := 2.5  # rad/s body yaw — matches player TURN_RATE
const AI_WISH_SMOOTH := 8.0  # 1/s steering smoothing (anti-zigzag)
const AI_LEDGE_PROBE := 5.0  # m ahead for the near-edge drop probe
const AI_STUCK_TIME := 4.0  # s below AI_STUCK_SPEED before the teleport
const AI_STUCK_SPEED := 1.0
const AI_GATE_STALL := 12.0  # s without passing a gate before the rescue
const AI_SPEED_CAUTIOUS := 15.0
const AI_SPEED_BOLD := 18.0
const AI_SPEED_RECKLESS := 20.0
const AI_LOOK_CAUTIOUS := 12.0
const AI_LOOK_BOLD := 16.0
const AI_LOOK_RECKLESS := 20.0
const AI_LEDGE_CAUTIOUS := 10.0
const AI_LEDGE_BOLD := 7.0
const AI_LEDGE_RECKLESS := 5.0
const AI_COLOR_CAUTIOUS := Color(0.45, 0.60, 0.35)  # sage
const AI_COLOR_BOLD := Color(0.75, 0.40, 0.20)  # rust
const AI_COLOR_RECKLESS := Color(0.40, 0.22, 0.22)  # charcoal-red

# Phase 8 — AI obstacle avoidance (plan Step 2): record-based cone probe;
# strength ∝ closeness of the nearest threat, clamped so the lookahead
# still owns the line (AI_WISH_SMOOTH rounds the corner). Weight is
# CONVEX (√) — strength arrives early in the approach, not at impact.
const AI_AVOID_R := 12.0  # m — probe radius ahead of the heading
const AI_AVOID_MAX_DEG := 35.0  # steer-away clamp

# Phase 8 — mountain gameplay (plan: docs/plans/phase-8-mountain-gameplay.md).
# Corridor (D1): pines/rocks are solid only within this radius of the race
# line — the far treeline stays scenery. Cap bounds web broadphase (D9).
const OBSTACLE_CORRIDOR_R := 45.0
const OBSTACLE_CAP := 220
const OBSTACLE_LOGS := 2  # fallen logs per course (D3 rhythm-breakers)

# Phase 8 — danger chords (plan D4): where the walk meanders, the straight
# cut is the danger line — shorter by ratio, must be measurably worse
# terrain (steeper / icier) or it's rejected: a free shortcut is a bug.
const CHORD_RATIO := 0.7  # chord length < this × arc length = a real bend
const CHORD_MIN_ARC := 80.0  # m of arc — chords are for big meanders only
const CHORD_MAX_COUNT := 2

# Phase 9 — tricks & scoring (plan: docs/plans/phase-9-tricks-and-scoring.md).
# Every number is a first guess; F5 tunes the feel, never the code (D10).
const TRICK_FLIP_TIME := 0.55  # s for the full Body 360 (Q/E)
const TRICK_FLIP_CLEAN := 0.85  # flip completion that still banks on landing
const TRICK_SPIN_DEG := 300.0  # mouse yaw in one air window = "360"
const TRICK_LONG_JUMP_M := 15.0
const TRICK_CLIFF_DROP_M := 6.0
const TRICK_NEAR_MISS_R := 1.6  # m surface distance at speed
const TRICK_NEAR_MISS_SPEED := 10.0
const TRICK_NEAR_MISS_CD := 1.5  # s per obstacle between near-miss payouts
const TRICK_PTS_FLIP := 500
const TRICK_PTS_SPIN := 300
const TRICK_PTS_LONG := 200
const TRICK_PTS_CLIFF := 400
const TRICK_PTS_LOG := 250
const TRICK_PTS_NEAR := 100
const TRICK_PTS_COIN := 50
const TRICK_COMBO_STEP := 0.5  # multiplier step per distinct trick in a window
const FLIP_CAM_FRACTION := 0.2  # D3: camera shares this much of the flip

# Horns (POV framing).
const HORN_LENGTH := 0.35
const HORN_CURVATURE := 0.5

# World.
const KILL_Y := -50.0

# Phase 10 — progression & upgrades (plan: docs/plans/phase-10-progression.md).
const SAVE_PATH := "user://progression.cfg"
const XP_BASE_DIVISOR := 300.0

const UPGRADE_MAX_TIER := 5
const UPGRADE_COSTS: Array[int] = [100, 250, 500, 1000, 2000]

const STAT_STEP_SPEED := 0.04     # +4% per tier
const STAT_STEP_JUMP := 0.04      # +4% per tier
const STAT_STEP_GRIP := 0.05      # +5% per tier
const STAT_STEP_STAMINA := 0.06   # +6% slam absorption per tier

const MOUNTAIN_UNLOCK_LEVELS: Dictionary = {
	"alpine_valley": 1,
	"rocky_ridge": 2,
	"snow_mountain": 4,
	"canyon_run": 6,
	"extreme_summit": 8,
}

const SKIN_UNLOCK_LEVELS: Dictionary = {
	"classic": 1,
	"snow_phantom": 3,
	"obsidian_ram": 5,
	"golden_capra": 8,
}

const SKIN_COIN_COSTS: Dictionary = {
	"classic": 0,
	"snow_phantom": 0,
	"obsidian_ram": 800,
	"golden_capra": 2500,
}

# Phase 11 — UI overhaul (plan: docs/plans/phase-11-ui.md). Numbers are
# first guesses; F5 tunes the look, never the code (D10 pattern).
const HUD_SPEEDO_MAX := 30.0  # m/s bar ceiling (above MAX_DOWNHILL_SPEED
# purely so upgrades + fall speed don't pin the bar)
const HUD_MINIMAP_SIZE := 176.0  # px card edge (square)
const HUD_MINIMAP_PAD := 10.0  # px world→map inset margin
const HUD_CHIP_PAD_X := 14.0  # px chip horizontal padding
const HUD_TRICK_POP_SECS := 1.35  # s a trick label lives before fading

# Phase 12 — audio & effects (plan: docs/plans/phase-12-audio-fx.md).
# Listener-layer numbers only: nothing here touches physics — the gauntlet
# must stay bit-identical across this phase (plan D2).
const SFX_VOL_MUSIC_DB := -7.0  # Music bus ceiling
const SFX_VOL_SFX_DB := -3.0  # one-shots bus
const SFX_VOL_AMBIENCE_DB := -13.0  # wind / fall-rush bus
const SFX_POOL_SIZE := 8  # simultaneous one-shot voices
const SFX_PITCH_JITTER := 0.07  # ± fraction — anti-machine-gun
const MUSIC_FADE := 1.6  # 1/s crossfade lerp (calm ↔ drive)
const FOOT_MIN_SPEED := 1.5  # m/s below which the goat is "standing"
const FOOT_STRIDE_M := 2.35  # m of horizontal travel per footfall
const FOOT_SURFACE_PITCH: Dictionary = {
	# The placeholder bank is timbre-neutral; pitch carries the surface.
	"ROCK": 1.0, "GRASS": 0.94, "SNOW": 0.82, "ICE": 0.76,
}
const FALL_RUSH_VY := -11.0  # m/s fall speed that triggers the whoosh
const WIND_MAX_DB := -9.0  # ambience ceiling at full speed/altitude

const FX_LAND_PARTICLES := 26  # dust burst ceiling at STUMBLE_IMPACT
const FX_BONK_PARTICLES := 16
const FX_COIN_PARTICLES := 12
const FX_GATE_PARTICLES := 20
const FX_LIFETIME := 0.9  # s one-shot emitter lifetime (free follows)

const WEATHER_SNOW_COUNT: Dictionary = {
	# Per-mountain snowfall density (0 = never snows there).
	"alpine_valley": 36, "rocky_ridge": 28, "snow_mountain": 110,
	"canyon_run": 0, "extreme_summit": 90,
}
const WEATHER_DUST_COUNT: Dictionary = {
	# Canyon grit — always on, no snow line applies.
	"canyon_run": 60,
}
const WEATHER_SNOW_BAND := 12.0  # m hysteresis around the snow line
const STREAK_MIN_SPEED := 17.0  # m/s where air streaks fade in (85% max)
const STREAK_MAX_PARTICLES := 70  # alive at MAX_DOWNHILL_SPEED

# Phase 13 — optimization (plan: docs/plans/phase-13-optimization.md).
# Spatial-grid query margin: record surfaces reach up to ~0.95 m past
# their center (max obstacle r 0.6 + goat capsule 0.35), so every grid
# query adds this slack — the candidate set stays a strict superset.
const GRID_QUERY_MARGIN := 2.0
# Minimap refresh ceiling (Step 6) — strategic aid, not an instrument.
const HUD_MINIMAP_HZ := 12.0
# Save debounce window (Step 7, D7): mutations flush at most this late;
# finish/purchase/unlock/tree_exiting flush immediately.
const SAVE_DEBOUNCE_S := 2.0

# Quality profiles (Step 8, D6/D8): HIGH is the desktop default — terrain
# grid and physics stay EXACTLY as Phases 5-12 built them, so the gauntlet
# stays bit-identical. LOW is the web/mobile candidate (Phase 14 decides
# on-device): halved terrain grid, web render floor.
const QUALITY_HIGH := "HIGH"
const QUALITY_LOW := "LOW"
static var QUALITY := QUALITY_HIGH

# Web render floor (Step 9, D8): compat-renderer shadow atlas 2048 (the
# 4096 default is heavy for GLES3 web) and MSAA off — a bandwidth tax the
# vertex-color + fog art style doesn't need. Applied at boot, A/B-able.
const WEB_SHADOW_SIZE := 2048


func _init() -> void:
	# Web builds boot LOW unless Phase 14's on-device numbers say otherwise
	# (desktop never enters this branch — gauntlet guarantee, plan D2).
	# GOATDIVE_QUALITY=LOW forces the profile on desktop — the durable A/B
	# knob for Phase 14 device work and the LOW-profile smoke gate.
	if OS.has_feature("web") or OS.get_environment("GOATDIVE_QUALITY") == "LOW":
		QUALITY = QUALITY_LOW

