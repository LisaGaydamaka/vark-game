class_name PlayerMotionSolver
extends RefCounted


const MOTION_EPSILON_SQUARED: float = PlayerContactProjector.MOTION_EPSILON_SQUARED
const VERTICAL_NORMAL_EPSILON: float = 0.0001
const CONSTRAINT_EPSILON: float = PlayerContactProjector.CONSTRAINT_EPSILON
const SAME_PLANE_DOT: float = PlayerContactProjector.SAME_PLANE_DOT
const STEP_ROUTE_SAFE_MARGIN: float = 0.001
const STEP_ROUTE_PROGRESS_TOLERANCE: float = 0.002


var max_collision_iterations: int
var ground_motion: PlayerGroundMotion
var contact_projector: PlayerContactProjector


func _init(p_max_collision_iterations: int) -> void:
	max_collision_iterations = p_max_collision_iterations
	ground_motion = PlayerGroundMotion.new()
	contact_projector = PlayerContactProjector.new()


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
	var active_contact_planes: Array[Vector3] = []
	var remaining_horizontal := Vector3(
		player.velocity.x,
		0.0,
		player.velocity.z
	) * delta
	var desired_horizontal_destination: Vector3 = (
		player.global_position + remaining_horizontal
	)
	var current_support_normal: Vector3 = support.support_normal
	contact_projector.append_unique_plane(
		active_contact_planes,
		current_support_normal
	)

	for _iteration: int in range(max_collision_iterations):
		if remaining_horizontal.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var preferred_motion: Vector3 = ground_motion.get_surface_motion(
			remaining_horizontal,
			current_support_normal
		)
		var motion: Vector3 = _resolve_ground_contact_motion(
			preferred_motion,
			remaining_horizontal,
			active_contact_planes
		)
		if motion.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var collision: KinematicCollision3D = player.move_and_collide(motion)
		if collision == null:
			break

		collisions.append(collision)
		var collision_normals: Array[Vector3] = (
			contact_projector.get_collision_normals(collision)
		)
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
				# A walkable contact can become the primary support for slope
				# mapping, but it remains part of the simultaneous contact manifold.
				# Never discard the previous walkable plane just because another
				# floor-like plane was reported by the same capsule configuration.
				contact_projector.append_unique_plane(
					active_contact_planes,
					normal
				)
				if normal.y > next_support_y:
					next_support_y = normal.y
					next_support_normal = normal
				continue

			# Ground locomotion keeps wall/steep-obstacle constraints horizontal.
			# This preserves the established slope-following policy while allowing
			# multiple walkable planes to retain their real 3D normals.
			var horizontal_normal := Vector3(normal.x, 0.0, normal.z)
			if horizontal_normal.length_squared() <= MOTION_EPSILON_SQUARED:
				continue
			contact_projector.append_unique_plane(
				active_contact_planes,
				horizontal_normal
			)

		if blocked_above:
			break
		if next_support_y > -INF:
			current_support_normal = next_support_normal

		remaining_horizontal = Vector3(
			desired_horizontal_destination.x - player.global_position.x,
			0.0,
			desired_horizontal_destination.z - player.global_position.z
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
		var collision_normals: Array[Vector3] = (
			contact_projector.get_collision_normals(collision)
		)
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
				contact_projector.append_unique_plane(
					active_planes,
					support.support_normal
				)
		else:
			for normal: Vector3 in collision_normals:
				contact_projector.append_unique_plane(
					active_planes,
					normal
				)

		var desired_remaining: Vector3 = (
			desired_destination - player.global_position
		)
		if landed_on_walkable_support and desired_remaining.y < 0.0:
			desired_remaining.y = 0.0

		if falling_before_collision and not has_validated_support:
			# Unsupported contacts may constrain or redirect requested motion,
			# but they cannot manufacture a longer displacement just to preserve
			# ballistic Y. The stored velocity remains ballistic until support is
			# independently validated; only realized displacement is constrained.
			motion = _resolve_unsupported_fall_motion(
				desired_remaining,
				active_planes
			)
			continue

		var resolution: Dictionary = (
			contact_projector.resolve_motion_with_vertical_priority(
				desired_remaining,
				active_planes
			)
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
	if planes.is_empty():
		return desired_motion

	# Project into the admissible contact half-spaces instead of holding Y fixed.
	# Projection onto a unit-normal half-space can only remove motion magnitude,
	# so gravity may produce a small physical slide on an angled lateral contact
	# but can never be amplified into a larger horizontal displacement.
	var resolved_motion: Vector3 = desired_motion
	for _pass: int in range(max_collision_iterations):
		var changed: bool = false
		for plane: Vector3 in planes:
			var inward_motion: float = resolved_motion.dot(plane)
			if inward_motion >= -CONSTRAINT_EPSILON:
				continue
			resolved_motion -= plane * inward_motion
			changed = true
		if not changed:
			return resolved_motion

	# If a pathological set of feature normals has not converged within the same
	# collision-iteration budget, stopping realized motion is safer than inventing
	# displacement. Ballistic velocity itself is intentionally left untouched.
	for plane: Vector3 in planes:
		if resolved_motion.dot(plane) < -CONSTRAINT_EPSILON:
			return Vector3.ZERO
	return resolved_motion


func _resolve_ground_contact_motion(
	desired_motion: Vector3,
	desired_horizontal: Vector3,
	planes: Array[Vector3]
) -> Vector3:
	var resolved_motion: Vector3 = contact_projector.project_contact_manifold(
		desired_motion,
		planes
	)

	# Static contact resolution may redirect or remove locomotion, but it must
	# never create extra horizontal travel. Scaling a feasible vector toward zero
	# preserves every homogeneous contact half-space constraint.
	var requested_horizontal_length: float = Vector2(
		desired_horizontal.x,
		desired_horizontal.z
	).length()
	var resolved_horizontal_length: float = Vector2(
		resolved_motion.x,
		resolved_motion.z
	).length()
	if (
		resolved_horizontal_length
		<= requested_horizontal_length + CONSTRAINT_EPSILON
	):
		return resolved_motion
	if requested_horizontal_length <= sqrt(MOTION_EPSILON_SQUARED):
		return Vector3.ZERO

	return resolved_motion * (
		requested_horizontal_length / resolved_horizontal_length
	)


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

		var collision_normals: Array[Vector3] = (
			contact_projector.get_collision_normals(collision)
		)
		for normal: Vector3 in collision_normals:
			contact_projector.append_unique_plane(
				active_planes,
				normal
			)

		var desired_remaining: Vector3 = (
			desired_destination - player.global_position
		)
		var resolution: Dictionary = (
			contact_projector.resolve_motion_with_vertical_priority(
				desired_remaining,
				active_planes
			)
		)
		motion = resolution["motion"]
		if bool(resolution["vertical_blocked"]):
			player.velocity.y = 0.0
