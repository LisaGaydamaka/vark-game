class_name PlayerMovement
extends RefCounted


var max_collision_iterations: int
var step_push_threshold: float
var step_progress_ratio_threshold: float

var step_up: PlayerStepUp


func _init(
	p_max_collision_iterations: int,
	p_step_push_threshold: float,
	p_step_progress_ratio_threshold: float,
	p_step_up: PlayerStepUp
) -> void:
	max_collision_iterations = (
		p_max_collision_iterations
	)

	step_push_threshold = (
		p_step_push_threshold
	)

	step_progress_ratio_threshold = (
		p_step_progress_ratio_threshold
	)

	step_up = p_step_up


func move(
	player: CharacterBody3D,
	input_direction: Vector3,
	support: PlayerSupport,
	delta: float
) -> void:
	# Clear the previous frame's candidate only after
	# its acceleration has already been used.
	step_up.begin_frame()

	var horizontal_input := Vector3(
		input_direction.x,
		0.0,
		input_direction.z
	)

	if horizontal_input.length_squared() > 0.000001:
		horizontal_input = (
			horizontal_input.normalized()
		)

	# Save position before movement so actual forward
	# progress can be measured afterward.
	var start_position := (
		player.global_position
	)

	# Horizontal motion the player attempted.
	var desired_horizontal_motion := Vector3(
		player.velocity.x,
		0.0,
		player.velocity.z
	) * delta

	var motion: Vector3 = (
		player.velocity
		* delta
	)

	var had_collision := false
	var first_collision: KinematicCollision3D = null

	for _iteration: int in range(
		max_collision_iterations
	):
		if motion.length_squared() <= 0.000001:
			break

		var collision: KinematicCollision3D = (
			player.move_and_collide(
				motion
			)
		)

		if collision == null:
			break

		if not had_collision:
			had_collision = true
			first_collision = collision

		var normal: Vector3 = (
			collision.get_normal()
		)

		var remainder: Vector3 = (
			collision.get_remainder()
		)

		var normal_velocity: float = (
			player.velocity.dot(
				normal
			)
		)

		if normal_velocity < 0.0:
			player.velocity -= (
				normal
				* normal_velocity
			)

		motion = (
			remainder.slide(
				normal
			)
		)

	# Measure actual movement.
	var actual_displacement := (
		player.global_position
		- start_position
	)

	var actual_horizontal_displacement := Vector3(
		actual_displacement.x,
		0.0,
		actual_displacement.z
	)

	# Evaluate whether a blocked collision can become
	# a step candidate.
	if (
		had_collision
		and horizontal_input.length_squared() > 0.000001
	):
		var desired_progress: float = (
			desired_horizontal_motion.dot(
				horizontal_input
			)
		)

		var actual_progress: float = (
			actual_horizontal_displacement.dot(
				horizontal_input
			)
		)

		if desired_progress > 0.000001:
			var progress_ratio: float = (
				actual_progress
				/ desired_progress
			)

			if (
				progress_ratio
				< step_progress_ratio_threshold
			):
				step_up.process_collision(
					player,
					first_collision,
					horizontal_input,
					support
				)
