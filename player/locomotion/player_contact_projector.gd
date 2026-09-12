class_name PlayerContactProjector
extends RefCounted


const MOTION_EPSILON_SQUARED: float = 0.000001
const CONSTRAINT_EPSILON: float = 0.000001
const SAME_PLANE_DOT: float = 0.999


func append_unique_plane(
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


func get_collision_normals(
	collision: KinematicCollision3D
) -> Array[Vector3]:
	var normals: Array[Vector3] = []
	if collision == null:
		return normals

	var collision_count: int = collision.get_collision_count()
	if collision_count <= 0:
		append_unique_plane(normals, collision.get_normal())
		return normals

	for collision_index: int in range(collision_count):
		append_unique_plane(
			normals,
			collision.get_normal(collision_index)
		)
	return normals


func project_contact_manifold(
	desired_motion: Vector3,
	planes: Array[Vector3]
) -> Vector3:
	if desired_motion.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO
	if planes.is_empty() or satisfies_contact_constraints(desired_motion, planes):
		return desired_motion

	# The Euclidean projection onto a homogeneous 3D contact cone lies on the
	# request itself, one active plane, a two-plane crease, or the origin.
	# Enumerating those active sets keeps the result independent of contact order.
	var best_motion: Vector3 = Vector3.ZERO
	var best_distance_squared: float = desired_motion.length_squared()

	for plane: Vector3 in planes:
		var candidate: Vector3 = desired_motion - plane * desired_motion.dot(plane)
		if not satisfies_contact_constraints(candidate, planes):
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
			if not satisfies_contact_constraints(candidate, planes):
				continue
			var distance_squared: float = candidate.distance_squared_to(desired_motion)
			if distance_squared < best_distance_squared:
				best_distance_squared = distance_squared
				best_motion = candidate

	return best_motion


func satisfies_contact_constraints(
	motion: Vector3,
	planes: Array[Vector3]
) -> bool:
	for plane: Vector3 in planes:
		if motion.dot(plane) < -CONSTRAINT_EPSILON:
			return false
	return true


func project_walkable_support_motion(
	desired_horizontal_motion: Vector3,
	support_normal: Vector3,
	contact_planes: Array[Vector3],
	minimum_support_normal_y: float
) -> Vector3:
	var normal: Vector3 = support_normal
	if normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO
	normal = normal.normalized()
	if normal.y <= minimum_support_normal_y:
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


func resolve_motion_with_vertical_priority(
	desired_motion: Vector3,
	planes: Array[Vector3]
) -> Dictionary:
	if desired_motion.length_squared() <= MOTION_EPSILON_SQUARED:
		return {
			"motion": Vector3.ZERO,
			"vertical_blocked": false,
		}
	if planes.is_empty():
		return {
			"motion": desired_motion,
			"vertical_blocked": false,
		}

	var fixed_vertical: Dictionary = _resolve_horizontal_for_fixed_vertical(
		desired_motion,
		planes
	)
	if bool(fixed_vertical["valid"]):
		return {
			"motion": fixed_vertical["motion"],
			"vertical_blocked": false,
		}

	var horizontal_only := Vector3(
		desired_motion.x,
		0.0,
		desired_motion.z
	)
	var fallback: Dictionary = _resolve_horizontal_for_fixed_vertical(
		horizontal_only,
		planes
	)
	return {
		"motion": (
			fallback["motion"]
			if bool(fallback["valid"])
			else Vector3.ZERO
		),
		"vertical_blocked": absf(desired_motion.y) > sqrt(MOTION_EPSILON_SQUARED),
	}


func _get_horizontal_constraint_axis_on_support(
	plane: Vector3,
	support_normal: Vector3
) -> Vector2:
	if plane.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector2.ZERO
	var normalized_plane: Vector3 = plane.normalized()

	# Substitute support_normal dot motion = 0 into plane dot motion >= 0.
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

	# In 2D the nearest point in a homogeneous convex cone is the request, one
	# active boundary ray, or the origin.
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


func _satisfies_horizontal_constraints(
	motion: Vector2,
	axes: Array[Vector2]
) -> bool:
	for axis: Vector2 in axes:
		if axis.dot(motion) < -CONSTRAINT_EPSILON:
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


func _get_support_tangent_motion(
	horizontal_motion: Vector2,
	support_normal: Vector3
) -> Vector3:
	var rise: float = -(
		support_normal.x * horizontal_motion.x
		+ support_normal.z * horizontal_motion.y
	) / support_normal.y
	return Vector3(horizontal_motion.x, rise, horizontal_motion.y)


func _resolve_horizontal_for_fixed_vertical(
	desired_motion: Vector3,
	planes: Array[Vector3]
) -> Dictionary:
	var desired_horizontal := Vector2(desired_motion.x, desired_motion.z)
	var fixed_y: float = desired_motion.y

	for plane: Vector3 in planes:
		var horizontal_axis := Vector2(plane.x, plane.z)
		var horizontal_length_squared: float = horizontal_axis.length_squared()
		var required_dot: float = -fixed_y * plane.y
		if (
			horizontal_length_squared <= MOTION_EPSILON_SQUARED
			and required_dot > CONSTRAINT_EPSILON
		):
			return {
				"valid": false,
				"motion": Vector3.ZERO,
			}

	if _satisfies_fixed_vertical_constraints(
		desired_horizontal,
		fixed_y,
		planes
	):
		return {
			"valid": true,
			"motion": desired_motion,
		}

	var best_horizontal: Vector2 = Vector2.ZERO
	var best_distance_squared: float = INF
	var found_candidate: bool = false

	for plane: Vector3 in planes:
		var axis := Vector2(plane.x, plane.z)
		var axis_length_squared: float = axis.length_squared()
		if axis_length_squared <= MOTION_EPSILON_SQUARED:
			continue

		var required_dot: float = -fixed_y * plane.y
		var projection_scale: float = (
			(required_dot - axis.dot(desired_horizontal))
			/ axis_length_squared
		)
		var candidate: Vector2 = desired_horizontal + axis * projection_scale
		if not _satisfies_fixed_vertical_constraints(
			candidate,
			fixed_y,
			planes
		):
			continue

		var distance_squared: float = candidate.distance_squared_to(
			desired_horizontal
		)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_horizontal = candidate
			found_candidate = true

	for first_index: int in range(planes.size()):
		for second_index: int in range(first_index + 1, planes.size()):
			var first: Vector3 = planes[first_index]
			var second: Vector3 = planes[second_index]
			var first_axis := Vector2(first.x, first.z)
			var second_axis := Vector2(second.x, second.z)
			if (
				first_axis.length_squared() <= MOTION_EPSILON_SQUARED
				or second_axis.length_squared() <= MOTION_EPSILON_SQUARED
			):
				continue

			var determinant: float = (
				first_axis.x * second_axis.y
				- first_axis.y * second_axis.x
			)
			if absf(determinant) <= CONSTRAINT_EPSILON:
				continue

			var first_required_dot: float = -fixed_y * first.y
			var second_required_dot: float = -fixed_y * second.y
			var candidate := Vector2(
				(
					first_required_dot * second_axis.y
					- first_axis.y * second_required_dot
				) / determinant,
				(
					first_axis.x * second_required_dot
					- first_required_dot * second_axis.x
				) / determinant
			)
			if not _satisfies_fixed_vertical_constraints(
				candidate,
				fixed_y,
				planes
			):
				continue

			var distance_squared: float = candidate.distance_squared_to(
				desired_horizontal
			)
			if distance_squared < best_distance_squared:
				best_distance_squared = distance_squared
				best_horizontal = candidate
				found_candidate = true

	if not found_candidate:
		return {
			"valid": false,
			"motion": Vector3.ZERO,
		}

	return {
		"valid": true,
		"motion": Vector3(best_horizontal.x, fixed_y, best_horizontal.y),
	}


func _satisfies_fixed_vertical_constraints(
	horizontal_motion: Vector2,
	fixed_y: float,
	planes: Array[Vector3]
) -> bool:
	for plane: Vector3 in planes:
		var dot_value: float = (
			horizontal_motion.x * plane.x
			+ fixed_y * plane.y
			+ horizontal_motion.y * plane.z
		)
		if dot_value < -CONSTRAINT_EPSILON:
			return false
	return true
