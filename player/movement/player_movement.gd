class_name PlayerMovement
extends RefCounted


const MOTION_EPSILON_SQUARED: float = 0.000001
const VERTICAL_NORMAL_EPSILON: float = 0.0001
const CONSTRAINT_EPSILON: float = 0.000001
const SAME_PLANE_DOT: float = 0.999


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
	var active_horizontal_planes: Array[Vector3] = []
	var remaining_horizontal := Vector3(
		player.velocity.x,
		0.0,
		player.velocity.z
	) * delta
	var current_support_normal: Vector3 = support.support_normal

	# Ground locomotion is solved in XZ. Walkable terrain contributes only the
	# temporary Y required to follow the support surface. Blocking contacts are
	# accumulated for the whole move so a later wall cannot reintroduce motion
	# into an earlier wall merely because collision order changed.
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
		var collision_normals: Array[Vector3] = _get_collision_normals(collision)
		var blocked_above: bool = false
		var next_support_normal: Vector3 = current_support_normal
		var next_support_y: float = -INF

		for normal: Vector3 in collision_normals:
			_constrain_vertical_velocity_from_collision(player, normal)

			if (
				normal.y < -VERTICAL_NORMAL_EPSILON
				and motion.y > 0.0
			):
				blocked_above = true

			if support.is_walkable_surface(normal):
				if normal.y > next_support_y:
					next_support_y = normal.y
					next_support_normal = normal
				continue

			var horizontal_normal := Vector3(normal.x, 0.0, normal.z)
			if horizontal_normal.length_squared() <= MOTION_EPSILON_SQUARED:
				continue
			_append_unique_plane(
				active_horizontal_planes,
				horizontal_normal
			)

		if blocked_above:
			break
		if next_support_y > -INF:
			current_support_normal = next_support_normal

		var remainder: Vector3 = collision.get_remainder()
		var horizontal_remainder := Vector3(
			remainder.x,
			0.0,
			remainder.z
		)
		remaining_horizontal = _resolve_horizontal_constraints(
			horizontal_remainder,
			active_horizontal_planes
		)

	return collisions


func _move_free(
	player: CharacterBody3D,
	delta: float,
	assist_velocity: Vector3
) -> Array[KinematicCollision3D]:
	var collisions: Array[KinematicCollision3D] = []
	var active_planes: Array[Vector3] = []

	# Persistent velocity is locomotion/physics state owned by the motor.
	# Temporary traversal assist contributes only to this frame's displacement.
	var motion: Vector3 = (
		player.velocity + assist_velocity
	) * delta

	# Each collision adds constraints to one active contact manifold. The next
	# remainder is projected into the feasible cone of every plane encountered so
	# far, making corners and cracks independent of collision ordering.
	for _iteration: int in range(max_collision_iterations):
		if motion.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var collision: KinematicCollision3D = player.move_and_collide(motion)
		if collision == null:
			break

		collisions.append(collision)
		var collision_normals: Array[Vector3] = _get_collision_normals(collision)
		for normal: Vector3 in collision_normals:
			# Collision response may terminate persistent vertical physics at a floor
			# or ceiling, but never rewrites X/Z locomotion.
			_constrain_vertical_velocity_from_collision(player, normal)
			_append_unique_plane(active_planes, normal)

		motion = _resolve_3d_constraints(
			collision.get_remainder(),
			active_planes
		)

	return collisions


func _resolve_horizontal_constraints(
	desired_motion: Vector3,
	planes: Array[Vector3]
) -> Vector3:
	var desired := Vector3(
		desired_motion.x,
		0.0,
		desired_motion.z
	)
	if desired.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO
	if planes.is_empty() or _satisfies_constraints(desired, planes):
		return desired

	# In 2D the closest feasible point is either the desired point, a projection
	# onto one active boundary, or the corner at zero. Testing each boundary
	# against every plane makes the answer independent of which wall was hit first.
	var best_motion: Vector3 = Vector3.ZERO
	var best_distance_squared: float = desired.length_squared()

	for plane: Vector3 in planes:
		var candidate: Vector3 = desired.slide(plane)
		candidate.y = 0.0
		if not _satisfies_constraints(candidate, planes):
			continue
		var distance_squared: float = candidate.distance_squared_to(desired)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_motion = candidate

	return best_motion


func _resolve_3d_constraints(
	desired_motion: Vector3,
	planes: Array[Vector3]
) -> Vector3:
	if desired_motion.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO
	if planes.is_empty() or _satisfies_constraints(desired_motion, planes):
		return desired_motion

	# Project the desired remainder onto the feasible contact cone. In 3D the
	# closest point can lie on one plane, on the crease formed by two planes, or
	# at the fully constrained origin. Every candidate must satisfy every active
	# plane, so a new contact can only remove freedom; it cannot reopen an older
	# blocked direction.
	var best_motion: Vector3 = Vector3.ZERO
	var best_distance_squared: float = desired_motion.length_squared()

	for plane: Vector3 in planes:
		var candidate: Vector3 = desired_motion.slide(plane)
		if not _satisfies_constraints(candidate, planes):
			continue
		var distance_squared: float = candidate.distance_squared_to(desired_motion)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_motion = candidate

	for first_index: int in range(planes.size()):
		for second_index: int in range(first_index + 1, planes.size()):
			var crease: Vector3 = planes[first_index].cross(planes[second_index])
			if crease.length_squared() <= MOTION_EPSILON_SQUARED:
				continue
			crease = crease.normalized()
			var candidate: Vector3 = (
				crease * desired_motion.dot(crease)
			)
			if not _satisfies_constraints(candidate, planes):
				continue
			var distance_squared: float = candidate.distance_squared_to(
				desired_motion
			)
			if distance_squared < best_distance_squared:
				best_distance_squared = distance_squared
				best_motion = candidate

	return best_motion


func _satisfies_constraints(
	motion: Vector3,
	planes: Array[Vector3]
) -> bool:
	for plane: Vector3 in planes:
		if motion.dot(plane) < -CONSTRAINT_EPSILON:
			return false
	return true


func _append_unique_plane(
	planes: Array[Vector3],
	normal: Vector3
) -> void:
	if normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return
	var normalized_normal: Vector3 = normal.normalized()
	for existing_plane: Vector3 in planes:
		# Same-facing near-parallel contacts describe the same constraint. Opposite
		# normals are intentionally retained because together they can constrain a
		# body between two opposing surfaces.
		if normalized_normal.dot(existing_plane) >= SAME_PLANE_DOT:
			return
	planes.append(normalized_normal)


func _get_collision_normals(
	collision: KinematicCollision3D
) -> Array[Vector3]:
	var normals: Array[Vector3] = []
	if collision == null:
		return normals

	var collision_count: int = collision.get_collision_count()
	if collision_count <= 0:
		_append_unique_plane(normals, collision.get_normal())
		return normals

	for collision_index: int in range(collision_count):
		_append_unique_plane(
			normals,
			collision.get_normal(collision_index)
		)
	return normals


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
	var active_planes: Array[Vector3] = []

	for _iteration: int in range(max_collision_iterations):
		if motion.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var collision: KinematicCollision3D = player.move_and_collide(motion)
		if collision == null:
			break

		var collision_normals: Array[Vector3] = _get_collision_normals(collision)
		for normal: Vector3 in collision_normals:
			_constrain_vertical_velocity_from_collision(player, normal)
			_append_unique_plane(active_planes, normal)

		motion = _resolve_3d_constraints(
			collision.get_remainder(),
			active_planes
		)
