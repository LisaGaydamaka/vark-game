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
	var horizontal_motion: Vector3 = Vector3(
		motion.x,
		0.0,
		motion.z
	)

	# Step detection is a horizontal pre-sweep only. The player's actual
	# fallback movement remains the normal combined velocity * delta sweep.
	# This keeps floor/gravity collisions from stealing the step candidate
	# without introducing axis-order movement artifacts.
	if step_up.try_step(
		player,
		support,
		horizontal_motion,
		input_direction
	):
		if step_up.debug_enabled:
			print("STEP MOVE: pre-sweep geometric step committed")
		return

	for iteration: int in range(
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

		if step_up.debug_enabled:
			print("STEP MOVE: normal solver collision iteration ", iteration)
			print("STEP MOVE: normal ", normal)
			print("STEP MOVE: remainder ", remainder)

		var normal_velocity: float = (
			player.velocity.dot(normal)
		)

		if normal_velocity < 0.0:
			player.velocity -= normal * normal_velocity

		motion = remainder.slide(normal)
