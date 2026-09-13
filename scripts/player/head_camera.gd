extends Node3D
## First-person look (Phase 2): yaw on the goat body, pitch on this node.
## Bob / tilt / shake arrive in Phase 4.

const PITCH_LIMIT := deg_to_rad(80.0)

var _pitch := 0.0

@onready var body: Node3D = get_parent()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		body.rotate_y(-event.relative.x * Config.MOUSE_SENS)
		_pitch = clampf(
			_pitch - event.relative.y * Config.MOUSE_SENS, -PITCH_LIMIT, PITCH_LIMIT
		)
		rotation = Vector3(_pitch, 0.0, 0.0)
	elif event is InputEventMouseButton:
		if (
			event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
		):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
