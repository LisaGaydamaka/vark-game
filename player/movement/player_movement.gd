class_name PlayerMovement
extends RefCounted


var max_collision_iterations: int
var step_up: PlayerStepUp


func _init(
	p_max_collision_iterations: int,
	p_step_up: PlayerStepUp
) -> void:
	max_collision_iterations = p_max_collision_iterations
	step_up = p_step_up


func move(
	player: CharacterBody3D,
	support: PlayerSupport,
	input_direction: Vector3,
	delta: float
) -> void:
	var motion: Vector3 = player.velocity * delta
	var horizontal_motion: Vector3 = Vector3(
		motion.x,
		0.0,
		motion.z
	)

	if not step_up.is_active():
		step_up.try_start_step(
			player,
			horizontal_motion,
			input_direction,
			support
		)

	if step_up.is_active():
		step_up.update_traversal(
			player,
			input_direction,
			support,
			delta
		)

	motion = player.velocity * delta

	for _iteration: int in range(
		max_collision_iterations
	):
		if motion.length_squared() <= 0.000001:
			break

		var collision: KinematicCollision3D = (
			player.move_and_collide(motion)
		)

		if collision == null:
			break

		var normal: Vector3 = collision.get_normal()
		var remainder: Vector3 = collision.get_remainder()
		var normal_velocity: float = (
			player.velocity.dot(normal)
		)

		if (
			normal_velocity < 0.0
			and not step_up.should_preserve_velocity(
				collision
			)
		):
			player.velocity -= normal * normal_velocity

		motion = remainder.slide(normal)
