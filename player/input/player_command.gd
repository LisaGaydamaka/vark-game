class_name PlayerCommand
extends RefCounted


const DIRECTION_EPSILON_SQUARED: float = 0.000001


## One physics-frame snapshot of player controls.
##
## Input is sampled once by PlayerInput; gameplay systems may derive movement
## directions from this snapshot without querying the global Input singleton again.
var movement_vector: Vector2 = Vector2.ZERO
var jump_pressed: bool = false
var jump_held: bool = false
var crouch_pressed: bool = false
var sprint_held: bool = false


func get_movement_direction(
	reference_transform: Transform3D
) -> Vector3:
	var right_direction: Vector3 = reference_transform.basis.x
	var forward_direction: Vector3 = -reference_transform.basis.z

	right_direction.y = 0.0
	forward_direction.y = 0.0

	if right_direction.length_squared() <= DIRECTION_EPSILON_SQUARED:
		right_direction = Vector3.RIGHT
	else:
		right_direction = right_direction.normalized()

	if forward_direction.length_squared() <= DIRECTION_EPSILON_SQUARED:
		forward_direction = Vector3.FORWARD
	else:
		forward_direction = forward_direction.normalized()

	var direction: Vector3 = (
		right_direction * movement_vector.x
		+ forward_direction * -movement_vector.y
	)
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	return direction
