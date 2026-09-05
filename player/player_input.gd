class_name PlayerInput
extends RefCounted


const DIRECTION_EPSILON_SQUARED: float = 0.000001


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
	return Input.is_action_just_pressed("jump")


func is_crouch_just_pressed() -> bool:
	return Input.is_action_just_pressed("crouch")
