class_name PlayerMotionSolver
extends RefCounted


const MOTION_EPSILON_SQUARED: float = 0.000001
const VERTICAL_NORMAL_EPSILON: float = 0.0001
const CONSTRAINT_EPSILON: float = 0.000001
const SAME_PLANE_DOT: float = 0.999
const STEP_ROUTE_SAFE_MARGIN: float = 0.001
const STEP_ROUTE_PROGRESS_TOLERANCE: float = 0.002


var max_collision_iterations: int
var ground_motion: PlayerGroundMotion


func _init(p_max_collision_iterations: int) -> void:
	max_collision_iterations = p_max_collision_iterations
	ground_motion = PlayerGroundMotion.new()


func move(
	player: CharacterBody3D,
	delta: float,
	support: PlayerSupport = null,
	step_plan: PlayerStep.StepPlan = null
) -> Array[KinematicCollision3D]:
	if step_plan != null and step_plan.valid:
		return _move_step_transaction(player, delta, support, step_plan)

	if (
		support != null
		and support.has_support
		and support.walkable
		and absf(player.velocity.y) <= sqrt(MOTION_EPSILON_SQUARED)
	):
		return _move_walkable_ground(player, support, delta)
	return _move_free(player, delta, support)


func _move_step_transaction(
	player: CharacterBody3D,
	delta: float,
	support: PlayerSupport,
	step_plan: PlayerStep.StepPlan
) -> Array[KinematicCollision3D]:
	player.velocity.y = 0.0

	if not _is_step_route_clear(player, step_plan):
		return _move_without_step_progress(player, delta, support)

	var transaction_start: Transform3D = player.global_transform
	var collisions: Array[KinematicCollision3D] = []
	if step_plan.rise_distance > sqrt(MOTION_EPSILON_SQUARED):
		var rise_motion: Vector3 = Vector3.UP * step_plan.rise_distance
		var rise_collision: KinematicCollision3D = player.move_and_collide(
			rise_motion,
			false,
			STEP_ROUTE_SAFE_MARGIN,
			false,
			max_collision_iterations
		)
		if rise_collision != null:
			var traveled_up: float = maxf(
				0.0,
				rise_collision.get_travel().dot(Vector3.UP)
			)
			if (
				traveled_up
				< step_plan.rise_distance - STEP_ROUTE_PROGRESS_TOLERANCE
			):
				player.global_transform = transaction_start
				player.velocity.y = 0.0
				return _move_without_step_progress(player, delta, support)
			collisions.append(rise_collision)

	collisions.append_array(_move_step_horizontal(player, delta, support))
	return collisions


func _is_step_route_clear(
	player: CharacterBody3D,
	step_plan: PlayerStep.StepPlan
) -> bool:
	var simulated_transform: Transform3D = player.global_transform

	if step_plan.validation_lift_distance > sqrt(MOTION_EPSILON_SQUARED):
		var lift_motion: Vector3 = (
			Vector3.UP * step_plan.validation_lift_distance
		)
		if not _is_route_segment_clear(
			player,
			simulated_transform,
			lift_motion
		):
			return false
		simulated_transform.origin += lift_motion

	if step_plan.crossing_motion.length_squared() > MOTION_EPSILON_SQUARED:
		if not _is_route_segment_clear(
			player,
			simulated_transform,
			step_plan.crossing_motion
		):
			return false

	return true


func _is_route_segment_clear(
	player: CharacterBody3D,
	from_transform: Transform3D,
	motion: Vector3
) -> bool:
	var required_distance: float = motion.length()
	if required_distance <= sqrt(MOTION_EPSILON_SQUARED):
		return true

	var collision := KinematicCollision3D.new()
	var blocked: bool = player.test_move(
		from_transform,
		motion,
		collision,
		STEP_ROUTE_SAFE_MARGIN,
		false,
		max_collision_iterations
	)
	if not blocked:
		return true

	var route_direction: Vector3 = motion / required_distance
	var traveled_distance: float = maxf(
		0.0,
		collision.get_travel().dot(route_direction)
	)
	return (
		traveled_distance
		>= required_distance - STEP_ROUTE_PROGRESS_TOLERANCE
	)


func _move_without_step_progress(
	player: CharacterBody3D,
	delta: float,
	support: PlayerSupport
) -> Array[KinematicCollision3D]:
	player.velocity.y = 0.0
	if (
		support != null
		and support.has_support
		and support.walkable
	):
		return _move_walkable_ground(player, support, delta)
	return _move_free(player, delta, support)


func _move_step_horizontal(
	player: CharacterBody3D,
	delta: float,
	support: PlayerSupport
) -> Array[KinematicCollision3D]:
	player.velocity.y = 0.0
	return _move_free(player, delta, support)


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
	var desired_horizontal_destination: Vector3 = (
		player.global_position + remaining_horizontal
	)
	var current_support_normal: Vector3 = support.support_normal

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

		var horizontal_to_destination := Vector3(
			desired_horizontal_destination.x - player.global_position.x,
			0.0,
			desired_horizontal_destination.z - player.global_position.z
		)
		remaining_horizontal = _resolve_horizontal_constraints(
			horizontal_to_destination,
			active_horizontal_planes
		)

	return collisions


func _move_free(
	player: CharacterBody3D,
	delta: float,
	support: PlayerSupport
) -> Array[KinematicCollision3D]:
	var collisions: Array[KinematicCollision3D] = []
	var active_planes: Array[Vector3] = []

	# X/Z is locomotion. Y is ballistic. During a fall, raw contacts are not
	# allowed to invent support: only PlayerSupport may promote geometry into a
	# 3D support constraint or terminate downward velocity.
	var motion: Vector3 = player.velocity * delta
	var desired_destination: Vector3 = player.global_position + motion

	for _iteration: int in range(max_collision_iterations):
		if motion.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var collision: KinematicCollision3D = player.move_and_collide(motion)
		if collision == null:
			break

		collisions.append(collision)
		var collision_normals: Array[Vector3] = _get_collision_normals(collision)
		var falling_before_collision: bool = (
			player.velocity.y < -sqrt(MOTION_EPSILON_SQUARED)
		)
		var has_validated_support: bool = false
		var landed_on_walkable_support: bool = false

		if falling_before_collision and support != null:
			support.update(player)
			has_validated_support = support.has_support
			landed_on_walkable_support = support.is_grounded()
			if landed_on_walkable_support:
				player.velocity.y = 0.0

		if falling_before_collision:
			_append_fall_collision_constraints(
				active_planes,
				player,
				collision,
				collision_normals,
				support
			)
			if (
				has_validated_support
				and not landed_on_walkable_support
			):
				# A steep support plane has been validated independently from
				# the raw contact manifold, so it may constrain full 3D motion.
				_append_unique_plane(
					active_planes,
					support.support_normal
				)
		else:
			for normal: Vector3 in collision_normals:
				_append_unique_plane(active_planes, normal)

		var desired_remaining: Vector3 = (
			desired_destination - player.global_position
		)
		if landed_on_walkable_support and desired_remaining.y < 0.0:
			desired_remaining.y = 0.0

		if falling_before_collision and not has_validated_support:
			# Unsupported falling is a hard ownership boundary. Seam, edge and
			# face normals can redirect X/Z enough to clear geometry, but the
			# requested downward displacement is preserved exactly.
			motion = _resolve_unsupported_fall_motion(
				desired_remaining,
				active_planes
			)
			continue

		var resolution: Dictionary = _resolve_motion_with_vertical_priority(
			desired_remaining,
			active_planes
		)
		motion = resolution["motion"]

		if (
			bool(resolution["vertical_blocked"])
			and absf(player.velocity.y) > sqrt(MOTION_EPSILON_SQUARED)
		):
			player.velocity.y = 0.0

	return collisions


func _append_fall_collision_constraints(
	planes: Array[Vector3],
	player: CharacterBody3D,
	collision: KinematicCollision3D,
	collision_normals: Array[Vector3],
	support: PlayerSupport
) -> void:
	var found_lateral_plane: bool = false
	for normal: Vector3 in collision_normals:
		# A raw floor/support-like feature is only candidate support. If the
		# independent support probe did not validate it, its tiny horizontal
		# component must not turn fixed ballistic Y into invented lateral motion.
		if (
			support != null
			and normal.length_squared() > MOTION_EPSILON_SQUARED
			and support.is_support_surface(normal.normalized())
		):
			continue
		if _append_fall_lateral_plane(planes, normal):
			found_lateral_plane = true

	if found_lateral_plane or collision == null:
		return

	# A convex edge can occasionally be reported with only the adjacent face's
	# vertical normal. If that face was not validated as support, infer the
	# lateral side from the contact point rather than allowing it to become a
	# fake floor. This fallback is horizontal-only, so gravity cannot amplify it.
	var contact_offset: Vector3 = player.global_position - collision.get_position()
	contact_offset.y = 0.0
	if contact_offset.length_squared() <= MOTION_EPSILON_SQUARED:
		return
	_append_fall_lateral_plane(planes, contact_offset)


func _append_fall_lateral_plane(
	planes: Array[Vector3],
	normal: Vector3
) -> bool:
	if normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return false

	var normalized_normal: Vector3 = normal.normalized()
	var horizontal_axis := Vector2(normalized_normal.x, normalized_normal.z)
	if horizontal_axis.length_squared() <= MOTION_EPSILON_SQUARED:
		return false
	var horizontal_direction: Vector2 = horizontal_axis.normalized()

	for plane_index: int in range(planes.size()):
		var existing_plane: Vector3 = planes[plane_index]
		var existing_axis := Vector2(existing_plane.x, existing_plane.z)
		if existing_axis.length_squared() <= MOTION_EPSILON_SQUARED:
			continue
		if (
			horizontal_direction.dot(existing_axis.normalized())
			< SAME_PLANE_DOT
		):
			continue

		# A modular seam may yield several feature normals for the same wall.
		# Keep the most wall-like representative so top/bottom edge normals do
		# not manufacture a vertical constraint that the macroscopic wall lacks.
		if absf(normalized_normal.y) < absf(existing_plane.y):
			planes[plane_index] = normalized_normal
		return true

	planes.append(normalized_normal)
	return true


func _resolve_unsupported_fall_motion(
	desired_motion: Vector3,
	planes: Array[Vector3]
) -> Vector3:
	if desired_motion.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO

	# First retain the useful Y-to-X/Z relationship of a real angled lateral
	# contact. This lets the capsule move outward while continuing to fall down
	# a steep wall instead of merely retrying the same blocked vertical sweep.
	var fixed_vertical: Dictionary = _resolve_horizontal_for_fixed_vertical(
		desired_motion,
		planes
	)
	if bool(fixed_vertical["valid"]):
		return fixed_vertical["motion"]

	# Conflicting feature normals from a seam are not evidence that gravity is
	# blocked. Collapse them to pure horizontal topology and preserve Y exactly.
	var horizontal_planes: Array[Vector3] = []
	for plane: Vector3 in planes:
		var horizontal_plane := Vector3(plane.x, 0.0, plane.z)
		if horizontal_plane.length_squared() <= MOTION_EPSILON_SQUARED:
			continue
		_append_unique_plane(horizontal_planes, horizontal_plane)

	var horizontal_motion: Vector3 = _resolve_horizontal_constraints(
		desired_motion,
		horizontal_planes
	)
	return Vector3(
		horizontal_motion.x,
		desired_motion.y,
		horizontal_motion.z
	)


func _resolve_horizontal_constraints(
	desired_motion: Vector3,
	planes: Array[Vector3]
) -> Vector3:
	var horizontal_desired := Vector3(
		desired_motion.x,
		0.0,
		desired_motion.z
	)
	var fixed_vertical: Dictionary = _resolve_horizontal_for_fixed_vertical(
		horizontal_desired,
		planes
	)
	if bool(fixed_vertical["valid"]):
		return fixed_vertical["motion"]
	return Vector3.ZERO


func _resolve_motion_with_vertical_priority(
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
		var candidate: Vector2 = (
			desired_horizontal + axis * projection_scale
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


func move_vertical_velocity(
	player: CharacterBody3D,
	delta: float
) -> void:
	var motion: Vector3 = Vector3.UP * player.velocity.y * delta
	var desired_destination: Vector3 = player.global_position + motion
	var active_planes: Array[Vector3] = []

	for _iteration: int in range(max_collision_iterations):
		if motion.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var collision: KinematicCollision3D = player.move_and_collide(motion)
		if collision == null:
			break

		var collision_normals: Array[Vector3] = _get_collision_normals(collision)
		for normal: Vector3 in collision_normals:
			_append_unique_plane(active_planes, normal)

		var desired_remaining: Vector3 = (
			desired_destination - player.global_position
		)
		var resolution: Dictionary = _resolve_motion_with_vertical_priority(
			desired_remaining,
			active_planes
		)
		motion = resolution["motion"]
		if bool(resolution["vertical_blocked"]):
			player.velocity.y = 0.0