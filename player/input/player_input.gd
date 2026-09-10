class_name PlayerInput
extends RefCounted


var current_command: PlayerCommand = PlayerCommand.new()


func sample() -> PlayerCommand:
	var command := PlayerCommand.new()
	command.movement_vector = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)
	command.jump_pressed = Input.is_action_just_pressed("jump")
	command.jump_held = Input.is_action_pressed("jump")
	command.crouch_pressed = Input.is_action_just_pressed("crouch")
	command.sprint_held = Input.is_action_pressed("sprint")
	current_command = command
	return current_command


func get_movement_direction(
	reference_transform: Transform3D
) -> Vector3:
	return current_command.get_movement_direction(reference_transform)


func get_movement_vector() -> Vector2:
	return current_command.movement_vector


func is_jump_just_pressed() -> bool:
	return current_command.jump_pressed


func is_jump_pressed() -> bool:
	return current_command.jump_held


func is_crouch_just_pressed() -> bool:
	return current_command.crouch_pressed


func is_sprint_pressed() -> bool:
	return current_command.sprint_held
