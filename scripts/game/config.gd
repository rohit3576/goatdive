extends Node
## Immutable game tunables. One source of truth.

const VERSION := "0.3.0-phase3"
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

# Horns (POV framing).
const HORN_LENGTH := 0.35
const HORN_CURVATURE := 0.5

# World.
const KILL_Y := -50.0
