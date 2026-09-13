class_name GoatController
extends CharacterBody3D
## Phase 2 goat controller: gravity, camera-relative movement, downhill
## acceleration, jump, air control, fall respawn. Feel tuning is Phase 3.

var _spawn_transform := Transform3D()
var _spawn_set := false


func setup_spawn(t: Transform3D) -> void:
	_spawn_transform = t
	_spawn_set = true


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	if not on_floor:
		velocity += Vector3.DOWN * Config.GRAVITY * delta

	# Camera-relative wish direction (goat yaws with the camera).
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var tb := global_transform.basis
	var wish := tb.x * input.x + (-tb.z) * -input.y
	wish.y = 0.0
	var horiz := Vector2(velocity.x, velocity.z)
	var wish2 := Vector2(wish.x, wish.z)
	var has_input := wish2.length_squared() > 0.0001

	if on_floor:
		if has_input:
			# Accelerate along wish up to MOVE_SPEED; downhill momentum above
			# the cap is never braked by input (that's the whole point).
			var dir := wish2.normalized()
			var along := horiz.dot(dir)
			if along < Config.MOVE_SPEED:
				horiz += dir * minf(Config.MOVE_ACCEL * delta, Config.MOVE_SPEED - along)
		else:
			horiz = horiz.move_toward(Vector2.ZERO, Config.FRICTION * delta)
		horiz += _downhill_accel(delta)
	else:
		if has_input:
			horiz += wish2.normalized() * (Config.MOVE_ACCEL * Config.AIR_CONTROL * delta)

	var hs := horiz.length()
	if hs > Config.MAX_DOWNHILL_SPEED:
		horiz = horiz / hs * Config.MAX_DOWNHILL_SPEED
	velocity.x = horiz.x
	velocity.z = horiz.y

	if on_floor and Input.is_action_just_pressed("jump"):
		velocity.y = Config.JUMP_VELOCITY

	move_and_slide()

	if _spawn_set and global_position.y < Config.KILL_Y:
		global_transform = _spawn_transform
		velocity = Vector3.ZERO


## Gravity projected onto the floor plane, gated by a minimum slope angle —
## the downhill acceleration core (plan Step 2).
func _downhill_accel(delta: float) -> Vector2:
	var n := get_floor_normal()
	var g_proj := Vector3.DOWN - n * Vector3.DOWN.dot(n)
	var slope_deg := rad_to_deg(acos(clampf(n.y, -1.0, 1.0)))
	if slope_deg < Config.SLOPE_ACCEL_MIN_DEG:
		return Vector2.ZERO
	return Vector2(g_proj.x, g_proj.z) * delta
