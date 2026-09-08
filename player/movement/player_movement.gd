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
	support: PlayerSupport = null
) -> Array[KinematicCollision3D]:
	var collisions: Array[KinematicCollision3D] = []

	# Persistent velocity is locomotion/physics state. Movement resolves only the
	# requested displacement for this frame. A raw collision normal is geometry,
	# not permission to climb: only a validated walkable surface may redirect
	# motion upward. Steep slopes and walls block/slide XZ while preserving Y.
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
		var remainder: Vector3 = collision.get_remainder()

		if support == null:
			# Ledge action paths do not use normal locomotion support classification.
			# Preserve their established collision behavior.
			_constrain_vertical_velocity_legacy(player, normal)
			motion = remainder.slide(normal)
			continue

		if support.is_walkable_surface(normal):
			_constrain_walkable_floor_velocity(player, normal)
			motion = remainder.slide(normal)
			continue

		# A non-walkable surface is a blocker, even if its normal has a positive Y
		# component. Resolve only the horizontal component against the obstacle so a
		# steep slope cannot convert forward motion into upward displacement.
		motion = _resolve_blocking_motion(
			player,
			remainder,
			normal
		)

	return collisions


func _constrain_walkable_floor_velocity(
	player: CharacterBody3D,
	normal: Vector3
) -> void:
	if player.velocity.y < 0.0 and normal.y > VERTICAL_NORMAL_EPSILON:
		player.velocity.y = 0.0
	elif player.velocity.y > 0.0 and normal.y < -VERTICAL_NORMAL_EPSILON:
		player.velocity.y = 0.0


func _resolve_blocking_motion(
	player: CharacterBody3D,
	remainder: Vector3,
	normal: Vector3
) -> Vector3:
	var vertical_remainder: float = remainder.y

	# A downward-facing blocker is ceiling-like: it may stop genuine upward
	# physics or traversal motion, but it still must not invent horizontal motion.
	if normal.y < -VERTICAL_NORMAL_EPSILON and vertical_remainder > 0.0:
		vertical_remainder = 0.0
		if player.velocity.y > 0.0:
			player.velocity.y = 0.0

	var horizontal_remainder := Vector3(
		remainder.x,
		0.0,
		remainder.z
	)
	var horizontal_normal := Vector3(
		normal.x,
		0.0,
		normal.z
	)

	if horizontal_normal.length_squared() > MOTION_EPSILON_SQUARED:
		horizontal_remainder = horizontal_remainder.slide(
			horizontal_normal.normalized()
		)

	return horizontal_remainder + Vector3.UP * vertical_remainder


func _constrain_vertical_velocity_legacy(
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
	delta: float,
	support: PlayerSupport = null
) -> void:
	var motion: Vector3 = Vector3.UP * player.velocity.y * delta

	for _iteration: int in range(max_collision_iterations):
		if motion.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var collision: KinematicCollision3D = player.move_and_collide(motion)
		if collision == null:
			break

		var normal: Vector3 = collision.get_normal()
		var remainder: Vector3 = collision.get_remainder()

		if support == null:
			_constrain_vertical_velocity_legacy(player, normal)
			motion = remainder.slide(normal)
			continue

		if support.is_walkable_surface(normal):
			_constrain_walkable_floor_velocity(player, normal)
			motion = remainder.slide(normal)
			continue

		motion = _resolve_blocking_motion(
			player,
			remainder,
			normal
		)
