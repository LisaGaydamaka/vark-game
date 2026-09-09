class_name PlayerInput
extends RefCounted


const DIRECTION_EPSILON_SQUARED: float = 0.000001

var previous_physical_space_pressed: bool = false


func _init() -> void:
	previous_physical_space_pressed = Input.is_physical_key_pressed(KEY_SPACE)


func get_movement_direction(
	reference_transform: Transform3D
) -> Vector3:
	var input_vector: Vector2 = get_movement_vector()
	var right_direction: Vector3 = (
		reference_transform.basis.x
	)
	var forward_direction: Vector3 = (
		-reference_transform.basis.z
	)

	right_direction.y = 0.0
	forward_direction.y = 0.0

	if (
		right_direction.length_squared()
		<= DIRECTION_EPSILON_SQUARED
	):
		right_direction = Vector3.RIGHT
	else:
		right_direction = right_direction.normalized()

	if (
		forward_direction.length_squared()
		<= DIRECTION_EPSILON_SQUARED
	):
		forward_direction = Vector3.FORWARD
	else:
		forward_direction = forward_direction.normalized()

	var direction: Vector3 = (
		right_direction * input_vector.x
		+ forward_direction * -input_vector.y
	)

	if direction.length_squared() > 1.0:
		direction = direction.normalized()

	return direction


func get_movement_vector() -> Vector2:
	return Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)


func is_jump_just_pressed() -> bool:
	var physical_space_pressed: bool = Input.is_physical_key_pressed(KEY_SPACE)
	var physical_space_just_pressed: bool = (
		physical_space_pressed
		and not previous_physical_space_pressed
	)
	previous_physical_space_pressed = physical_space_pressed

	var action_just_pressed: bool = Input.is_action_just_pressed("jump")
	var action_pressed: bool = Input.is_action_pressed("jump")
	if physical_space_just_pressed or action_just_pressed:
		var mapping_status: String = "input_ok"
		if physical_space_just_pressed and not action_just_pressed:
			mapping_status = "space_seen_but_jump_action_missing"
		elif action_just_pressed and not physical_space_pressed:
			mapping_status = "jump_action_seen_without_physical_space"
		print(
			"[JUMP_DEBUG] frame=%d event=SPACE_INPUT raw_space_just=%s raw_space_held=%s action_just=%s action_held=%s mapping=%s"
			% [
				Engine.get_physics_frames(),
				str(physical_space_just_pressed),
				str(physical_space_pressed),
				str(action_just_pressed),
				str(action_pressed),
				mapping_status,
			]
		)
	return action_just_pressed


func is_jump_pressed() -> bool:
	return Input.is_action_pressed("jump")


func is_crouch_just_pressed() -> bool:
	return Input.is_action_just_pressed("crouch")


func is_sprint_pressed() -> bool:
	return Input.is_action_pressed("sprint")
