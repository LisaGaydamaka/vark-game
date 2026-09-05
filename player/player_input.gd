class_name PlayerInput
extends RefCounted


func get_movement_direction(
	player_transform: Transform3D
) -> Vector3:
	var input: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)

	var direction := Vector3(
		input.x,
		0.0,
		input.y
	)

	direction = (
		player_transform.basis
		* direction
	)

	direction.y = 0.0

	if direction.length_squared() > 1.0:
		direction = direction.normalized()

	return direction
