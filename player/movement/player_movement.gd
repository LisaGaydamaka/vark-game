class_name PlayerMovement
extends RefCounted


const MOTION_EPSILON_SQUARED: float = 0.000001
const VERTICAL_NORMAL_EPSILON: float = 0.0001


var max_collision_iterations: int
var ground_motion: PlayerGroundMotion


func _init(p_max_collision_iterations: int) -> void:
	max_collision_iterations = p_max_collision_iterations
	ground_motion = PlayerGroundMotion.new()


func move(
	player: CharacterBody3D,
	delta: float,
	assist_velocity: Vector3 = Vector3.ZERO,
	support: PlayerSupport = null
) -> Array[KinematicCollision3D]:
	if (
		support != null
		and support.has_support
		and support.walkable
		and absf(player.velocity.y) <= sqrt(MOTION_EPSILON_SQUARED)
		and assist_velocity.length_squared() <= MOTION_EPSILON_SQUARED
	):
		return _move_walkable_ground(player, support, delta)

	return _move_free(player, delta, assist_velocity)


func _move_walkable_ground(
	player: CharacterBody3D,
	support: PlayerSupport,
	delta: float
) -> Array[KinematicCollision3D]:
	var collisions: Array[KinematicCollision3D] = []
	var remaining_horizontal := Vector3(
		player.velocity.x,
		0.0,
		player.velocity.z
	) * delta
	var current_support_normal: Vector3 = support.support_normal

	# Walkable-ground Y is derived from the horizontal displacement that remains
	# after each collision. A wall may remove some or all X/Z travel; the next
	# segment then recomputes its slope rise from that surviving X/Z instead of
	# preserving stale upward motion from the original slope projection.
	for _iteration: int in range(max_collision_iterations):
		if remaining_horizontal.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var motion: Vector3 = ground_motion.get_surface_motion(
			remaining_horizontal,
			current_support_normal
		)
		if motion.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var collision: KinematicCollision3D = player.move_and_collide(motion)
		if collision == null:
			break

		collisions.append(collision)
		var normal: Vector3 = collision.get_normal()
		_constrain_vertical_velocity_from_collision(player, normal)

		if (
			normal.y < -VERTICAL_NORMAL_EPSILON
			and motion.y > 0.0
		):
			break

		var remainder: Vector3 = collision.get_remainder()
		var horizontal_remainder := Vector3(
			remainder.x,
			0.0,
			remainder.z
		)

		if support.is_walkable_surface(normal):
			if normal.length_squared() > MOTION_EPSILON_SQUARED:
				current_support_normal = normal.normalized()
			remaining_horizontal = horizontal_remainder
			continue

		var horizontal_normal := Vector3(normal.x, 0.0, normal.z)
		if horizontal_normal.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		remaining_horizontal = horizontal_remainder.slide(
			horizontal_normal.normalized()
		)

	return collisions


func _move_free(
	player: CharacterBody3D,
	delta: float,
	assist_velocity: Vector3
) -> Array[KinematicCollision3D]:
	var collisions: Array[KinematicCollision3D] = []

	# Persistent velocity is locomotion/physics state owned by the motor.
	# Temporary traversal assist contributes only to this frame's displacement.
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

		# Collision response may terminate persistent vertical physics at a floor
		# or ceiling, but never rewrites X/Z locomotion.
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
