extends Node
## Immutable game tunables. One source of truth.

const VERSION := "0.6.0-phase6"
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

# Horns (POV framing).
const HORN_LENGTH := 0.35
const HORN_CURVATURE := 0.5

# World.
const KILL_Y := -50.0
