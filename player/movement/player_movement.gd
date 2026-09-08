class_name PlayerMovement
extends RefCounted


const MOTION_EPSILON_SQUARED: float = 0.000001
const VERTICAL_NORMAL_EPSILON: float = 0.0001


var max_collision_iterations: int


func _init(p_max_collision_iterations: int) -> void:
	max_collision_iterations = p_max_collision_iterations


func move(
	player: CharacterBody3D,
	delta: float,
	assist_velocity: Vector3 = Vector3.ZERO
) -> Array[KinematicCollision3D]:
	var collisions: Array[KinematicCollision3D] = []

	# Persistent velocity is locomotion/physics state owned by the motor. Movement
	# resolves only this frame's requested displacement. A wall or stair may clip
	# displacement without erasing the horizontal speed the motor is carrying.
	# Temporary traversal assist contributes to displacement only and is never
	# copied back into persistent velocity.
	var motion: Vector3 = (
		player.velocity + assist_velocity
	) * delta

	for _iteration: int in range(max_collision_iterations):
		if motion.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var collision: KinematicCollision3D = player.move_and_collide(motion)
		if collision == null:
			break

		collisions.append(collision)
		var normal: Vector3 = collision.get_normal()

		# Collision response may terminate persistent vertical physics at a floor or
		# ceiling, but never rewrites X/Z locomotion. Horizontal blocking/sliding is
		# represented exclusively by the clipped remainder for this movement frame.
		_constrain_vertical_velocity_from_collision(player, normal)
		motion = collision.get_remainder().slide(normal)

	return collisions


func _constrain_vertical_velocity_from_collision(
	player: CharacterBody3D,
	normal: Vector3
) -> void:
	if absf(normal.y) <= VERTICAL_NORMAL_EPSILON:
		return

	if player.velocity.y < 0.0 and normal.y > 0.0:
		player.velocity.y = 0.0
	elif player.velocity.y > 0.0 and normal.y < 0.0:
		player.velocity.y = 0.0


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
		_constrain_vertical_velocity_from_collision(player, normal)
		motion = collision.get_remainder().slide(normal)
