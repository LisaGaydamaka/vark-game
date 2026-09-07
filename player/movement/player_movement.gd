class_name PlayerMovement
extends RefCounted


const MOTION_EPSILON_SQUARED: float = 0.000001


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
	allow_step_up: bool,
	delta: float
) -> Array[KinematicCollision3D]:
	var collisions: Array[KinematicCollision3D] = []
	var base_motion: Vector3 = player.velocity * delta
	var horizontal_motion: Vector3 = Vector3(
		base_motion.x,
		0.0,
		base_motion.z
	)

	if allow_step_up and not step_up.is_active():
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
			delta
		)

	var motion_velocity: Vector3 = step_up.get_motion_velocity(player.velocity)
	var motion: Vector3 = motion_velocity * delta

	for _iteration: int in range(max_collision_iterations):
		if motion.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var collision: KinematicCollision3D = player.move_and_collide(motion)
		if collision == null:
			step_up.refresh_after_move(player)
			break

		collisions.append(collision)
		var preserve_velocity: bool = step_up.should_preserve_velocity(collision)
		var assist_blocked: bool = step_up.is_vertical_assist_blocked(
			collision,
			player.velocity
		)
		if assist_blocked:
			step_up.cancel_traversal()

		var normal: Vector3 = collision.get_normal()
		var remainder: Vector3 = collision.get_remainder()
		var normal_velocity: float = player.velocity.dot(normal)

		if normal_velocity < 0.0 and not preserve_velocity:
			player.velocity -= normal * normal_velocity

		step_up.refresh_after_move(player)
		if assist_blocked:
			break

		motion = remainder.slide(normal)

	return collisions


func move_vertical_velocity(
	player: CharacterBody3D,
	delta: float
) -> void:
	var motion: Vector3 = Vector3.UP * player.velocity.y * delta

	for _iteration: int in range(max_collision_iterations):
		if motion.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var collision: KinematicCollision3D = player.move_and_collide(motion)
		if collision == null:
			break

		var normal: Vector3 = collision.get_normal()
		var normal_velocity: float = player.velocity.dot(normal)
		if normal_velocity < 0.0:
			player.velocity -= normal * normal_velocity

		motion = collision.get_remainder().slide(normal)
