extends Node
## Immutable game tunables. One source of truth.

const VERSION := "0.2.0-phase2"
const DEBUG := true

# Gravity / movement (Phase 3 tunes the feel — numbers live here, nowhere else).
const GRAVITY := 9.8
const MOVE_SPEED := 8.0
const MOVE_ACCEL := 20.0
const FRICTION := 6.0
const MAX_DOWNHILL_SPEED := 20.0
const AIR_CONTROL := 0.3
const SLOPE_ACCEL_MIN_DEG := 5.0
const JUMP_VELOCITY := 4.5

# Camera.
const MOUSE_SENS := 0.003

# Horns (POV framing).
const HORN_LENGTH := 0.35
const HORN_CURVATURE := 0.5

# World.
const KILL_Y := -50.0
