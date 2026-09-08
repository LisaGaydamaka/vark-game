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
	assist_velocity: Vector3 = Vector3.ZERO,
	support_normal: Vector3 = Vector3.ZERO
) -> Array[KinematicCollision3D]:
	var collisions: Array[KinematicCollision3D] = []

	# Persistent velocity contains only horizontal locomotion plus real vertical
	# physics. Following a known floor is composed as frame-local Y displacement;
	# it never becomes persistent vertical momentum.
	var requested_velocity: Vector3 = player.velocity + assist_velocity
	if (
		player.velocity.y <= VERTICAL_NORMAL_EPSILON
		and support_normal.length_squared() > MOTION_EPSILON_SQUARED
		and support_normal.y > VERTICAL_NORMAL_EPSILON
	):
		requested_velocity.y += _get_surface_follow_vertical_velocity(
			player.velocity,
			support_normal.normalized()
		)

	var motion: Vector3 = requested_velocity * delta

	for _iteration: int in range(max_collision_iterations):
		if motion.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var collision: KinematicCollision3D = player.move_and_collide(motion)
		if collision == null:
			break

		collisions.append(collision)
		var normal: Vector3 = collision.get_normal()
		_constrain_vertical_velocity_from_collision(player, normal)

		var remainder: Vector3 = collision.get_remainder()
		var resolved_remainder: Vector3 = remainder.slide(normal)

		# Collision geometry may remove requested Y, but it may never invent upward
		# motion. Uphill displacement must already have been authorized by the current
		# support plane, step assist, or positive vertical physics before collision.
		var maximum_allowed_upward: float = maxf(0.0, remainder.y)
		if resolved_remainder.y > maximum_allowed_upward:
			resolved_remainder.y = maximum_allowed_upward

		motion = resolved_remainder

	return collisions


func _get_surface_follow_vertical_velocity(
	persistent_velocity: Vector3,
	normal: Vector3
) -> float:
	if normal.y <= VERTICAL_NORMAL_EPSILON:
		return 0.0
	return -(
		persistent_velocity.x * normal.x
		+ persistent_velocity.z * normal.z
	) / normal.y


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
		var remainder: Vector3 = collision.get_remainder()
		var resolved_remainder: Vector3 = remainder.slide(normal)
		var maximum_allowed_upward: float = maxf(0.0, remainder.y)
		if resolved_remainder.y > maximum_allowed_upward:
			resolved_remainder.y = maximum_allowed_upward
		motion = resolved_remainder
