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
	input_direction: Vector3,
	support: PlayerSupport,
	delta: float
) -> void:
	var motion: Vector3 = player.velocity * delta

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

		# The first normal move has already brought the capsule to the
		# blocking contact. Try to consume the remaining horizontal
		# movement through an alternate UP -> FORWARD -> DOWN path.
		var horizontal_remainder: Vector3 = Vector3(
			remainder.x,
			0.0,
			remainder.z
		)

		if step_up.try_step(
			player,
			support,
			horizontal_remainder,
			input_direction,
			collision
		):
			# Support will be refreshed immediately after movement by
			# Player.gd. Do not also run the normal slide response for the
			# collision we just stepped over.
			return

		var normal_velocity: float = (
			player.velocity.dot(normal)
		)

		if normal_velocity < 0.0:
			player.velocity -= normal * normal_velocity

		motion = remainder.slide(normal)
