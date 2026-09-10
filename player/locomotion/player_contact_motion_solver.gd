class_name PlayerContactMotionSolver
extends RefCounted


const MOTION_EPSILON_SQUARED: float = 0.000001
const CONSTRAINT_EPSILON: float = 0.000001
const SAME_PLANE_DOT: float = 0.999
const MINIMUM_SUPPORT_NORMAL_Y: float = 0.0001


var max_collision_iterations: int


func _init(p_max_collision_iterations: int) -> void:
	max_collision_iterations = p_max_collision_iterations


func move(
	player: CharacterBody3D,
	delta: float,
	support: PlayerSupport
) -> Array[KinematicCollision3D]:
	var collisions: Array[KinematicCollision3D] = []
	if delta <= 0.0:
		return collisions

	var requested_velocity: Vector3 = player.velocity
	var requested_horizontal_velocity := Vector3(
		requested_velocity.x,
		0.0,
		requested_velocity.z
	)
	var requested_destination: Vector3 = (
		player.global_position + requested_velocity * delta
	)
	var requested_horizontal_destination: Vector3 = (
		player.global_position + requested_horizontal_velocity * delta
	)

	var contact_planes: Array[Vector3] = []
	var walkable_support_active: bool = false
	var walkable_support_normal: Vector3 = Vector3.UP

	if support != null and support.has_support:
		if (
			support.walkable
			and requested_velocity.y <= sqrt(MOTION_EPSILON_SQUARED)
		):
			walkable_support_active = true
			walkable_support_normal = support.support_normal
		else:
			_append_unique_plane(contact_planes, support.support_normal)

	var motion: Vector3 = _resolve_remaining_motion(
		player,
		requested_destination,
		requested_horizontal_destination,
		walkable_support_active,
		walkable_support_normal,
		contact_planes
	)

	for _iteration: int in range(max_collision_iterations):
		if motion.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var collision: KinematicCollision3D = player.move_and_collide(motion)
		if collision == null:
			break

		collisions.append(collision)
		for normal: Vector3 in _get_collision_normals(collision):
			# Collision geometry is always physical truth. Support classification
			# may decide which contact carries the player, but it never removes a
			# simultaneous contact from the admissible-motion manifold.
			_append_unique_plane(contact_planes, normal)

		if support != null:
			support.update(player)
			if (
				support.is_grounded()
				and requested_velocity.y <= sqrt(MOTION_EPSILON_SQUARED)
			):
				# Walkable support is an equality constraint for locomotion: the
				# accepted X/Z displacement determines its terrain-following Y.
				walkable_support_active = true
				walkable_support_normal = support.support_normal
			elif support.has_support:
				# Steep support is unilateral. Gravity and controlled X/Z intent are
				# resolved against it together with every other current contact.
				_append_unique_plane(contact_planes, support.support_normal)

		motion = _resolve_remaining_motion(
			player,
			requested_destination,
			requested_horizontal_destination,
			walkable_support_active,
			walkable_support_normal,
			contact_planes
		)

	_commit_resolved_velocity(
		player,
		requested_velocity,
		requested_horizontal_velocity,
		walkable_support_active,
		walkable_support_normal,
		contact_planes
	)
	return collisions


func _resolve_remaining_motion(
	player: CharacterBody3D,
	requested_destination: Vector3,
	requested_horizontal_destination: Vector3,
	walkable_support_active: bool,
	walkable_support_normal: Vector3,
	contact_planes: Array[Vector3]
) -> Vector3:
	if walkable_support_active:
		var remaining_horizontal := Vector3(
			requested_horizontal_destination.x - player.global_position.x,
			0.0,
			requested_horizontal_destination.z - player.global_position.z
		)
		return _resolve_walkable_support_motion(
			remaining_horizontal,
			walkable_support_normal,
			contact_planes
		)

	var remaining: Vector3 = requested_destination - player.global_position
	return _resolve_contact_manifold_motion(remaining, contact_planes)


func _commit_resolved_velocity(
	player: CharacterBody3D,
	requested_velocity: Vector3,
	requested_horizontal_velocity: Vector3,
	walkable_support_active: bool,
	walkable_support_normal: Vector3,
	contact_planes: Array[Vector3]
) -> void:
	if walkable_support_active:
		var resolved_surface_velocity: Vector3 = _resolve_walkable_support_motion(
			requested_horizontal_velocity,
			walkable_support_normal,
			contact_planes
		)
		# Terrain-following Y is displacement geometry, not momentum. Persist only
		# the accepted player-controlled X/Z velocity while grounded.
		player.velocity = Vector3(
			resolved_surface_velocity.x,
			0.0,
			resolved_surface_velocity.z
		)
		return

	# For free/steep motion velocity is physical. Any component removed by a
	# static contact is removed from persistent velocity as well, so blocked fall
	# speed or wall speed cannot be stored and released later.
	player.velocity = _resolve_contact_manifold_motion(
		requested_velocity,
		contact_planes
	)


func _resolve_walkable_support_motion(
	desired_horizontal_motion: Vector3,
	support_normal: Vector3,
	contact_planes: Array[Vector3]
) -> Vector3:
	var normal: Vector3 = support_normal
	if normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO
	normal = normal.normalized()
	if normal.y <= MINIMUM_SUPPORT_NORMAL_Y:
		return Vector3.ZERO

	var desired := Vector2(
		desired_horizontal_motion.x,
		desired_horizontal_motion.z
	)
	if desired.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO

	var constraint_axes: Array[Vector2] = []
	for plane: Vector3 in contact_planes:
		var axis: Vector2 = _get_horizontal_constraint_axis_on_support(
			plane,
			normal
		)
		_append_unique_axis(constraint_axes, axis)

	var resolved: Vector2 = _resolve_horizontal_halfspaces(
		desired,
		constraint_axes
	)
	return _get_support_tangent_motion(resolved, normal)


func _get_horizontal_constraint_axis_on_support(
	plane: Vector3,
	support_normal: Vector3
) -> Vector2:
	if plane.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector2.ZERO
	var normalized_plane: Vector3 = plane.normalized()

	# Substitute the walkable-support equality
	# support_normal dot motion = 0
	# into the unilateral contact inequality
	# plane dot motion >= 0.
	# This leaves a homogeneous half-space directly in locomotion X/Z space.
	return Vector2(
		normalized_plane.x
		- normalized_plane.y * support_normal.x / support_normal.y,
		normalized_plane.z
		- normalized_plane.y * support_normal.z / support_normal.y
	)


func _resolve_horizontal_halfspaces(
	desired: Vector2,
	axes: Array[Vector2]
) -> Vector2:
	if axes.is_empty() or _satisfies_horizontal_constraints(desired, axes):
		return desired

	# In two-dimensional locomotion space the Euclidean projection onto a
	# homogeneous convex cone is either the request, one active boundary ray, or
	# the origin. This keeps wall/corner resolution independent of contact order.
	var best: Vector2 = Vector2.ZERO
	var best_distance_squared: float = desired.length_squared()

	for axis: Vector2 in axes:
		var axis_length_squared: float = axis.length_squared()
		if axis_length_squared <= MOTION_EPSILON_SQUARED:
			continue
		var candidate: Vector2 = (
			desired
			- axis * (axis.dot(desired) / axis_length_squared)
		)
		if not _satisfies_horizontal_constraints(candidate, axes):
			continue
		var distance_squared: float = candidate.distance_squared_to(desired)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best = candidate

	return best


func _get_support_tangent_motion(
	horizontal_motion: Vector2,
	support_normal: Vector3
) -> Vector3:
	var rise: float = -(
		support_normal.x * horizontal_motion.x
		+ support_normal.z * horizontal_motion.y
	) / support_normal.y
	return Vector3(horizontal_motion.x, rise, horizontal_motion.y)


func _resolve_contact_manifold_motion(
	desired_motion: Vector3,
	planes: Array[Vector3]
) -> Vector3:
	if desired_motion.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO
	if planes.is_empty() or _satisfies_contact_constraints(desired_motion, planes):
		return desired_motion

	# Projection onto the homogeneous intersection of static contact half-spaces
	# is non-expansive. In 3D the nearest feasible point can lie on one plane, a
	# two-plane crease, or the origin when the contact set fully blocks motion.
	var best_motion: Vector3 = Vector3.ZERO
	var best_distance_squared: float = desired_motion.length_squared()

	for plane: Vector3 in planes:
		var candidate: Vector3 = desired_motion - plane * desired_motion.dot(plane)
		if not _satisfies_contact_constraints(candidate, planes):
			continue
		var distance_squared: float = candidate.distance_squared_to(desired_motion)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_motion = candidate

	for first_index: int in range(planes.size()):
		for second_index: int in range(first_index + 1, planes.size()):
			var crease: Vector3 = planes[first_index].cross(planes[second_index])
			var crease_length_squared: float = crease.length_squared()
			if crease_length_squared <= MOTION_EPSILON_SQUARED:
				continue
			crease /= sqrt(crease_length_squared)
			var candidate: Vector3 = crease * desired_motion.dot(crease)
			if not _satisfies_contact_constraints(candidate, planes):
				continue
			var distance_squared: float = candidate.distance_squared_to(desired_motion)
			if distance_squared < best_distance_squared:
				best_distance_squared = distance_squared
				best_motion = candidate

	return best_motion


func _satisfies_horizontal_constraints(
	motion: Vector2,
	axes: Array[Vector2]
) -> bool:
	for axis: Vector2 in axes:
		if axis.dot(motion) < -CONSTRAINT_EPSILON:
			return false
	return true


func _satisfies_contact_constraints(
	motion: Vector3,
	planes: Array[Vector3]
) -> bool:
	for plane: Vector3 in planes:
		if motion.dot(plane) < -CONSTRAINT_EPSILON:
			return false
	return true


func _append_unique_axis(
	axes: Array[Vector2],
	axis: Vector2
) -> void:
	if axis.length_squared() <= MOTION_EPSILON_SQUARED:
		return
	var normalized_axis: Vector2 = axis.normalized()
	for existing_axis: Vector2 in axes:
		if normalized_axis.dot(existing_axis) >= SAME_PLANE_DOT:
			return
	axes.append(normalized_axis)


func _append_unique_plane(
	planes: Array[Vector3],
	normal: Vector3
) -> void:
	if normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return
	var normalized_normal: Vector3 = normal.normalized()
	for existing_plane: Vector3 in planes:
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
