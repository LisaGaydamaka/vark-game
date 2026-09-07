class_name PlayerMantle
extends RefCounted


const PROBE_SAFE_MARGIN: float = 0.001
const ROUTE_CLEARANCE_SLACK: float = 0.002
const PROBE_MAX_COLLISIONS: int = 8
const MOTION_EPSILON_SQUARED: float = 0.000001
const ANGLE_EPSILON: float = 0.00001
const MAX_ROUTE_SEGMENT_ANGLE_DEGREES: float = 5.0
const EXPECTED_ROUTE_SURFACE_PLANE_TOLERANCE_RADIUS_RATIO: float = 0.5
const OVER_LIP_TRAVEL_RADIUS_RATIO: float = 1.0


class MantleCandidate:
	var source_candidate: PlayerLedgeDetector.LedgeCandidate = null
	var edge_point: Vector3 = Vector3.ZERO
	var wall_normal: Vector3 = Vector3.ZERO
	var ledge_axis: Vector3 = Vector3.ZERO
	var top_path_normal: Vector3 = Vector3.UP
	var top_inward_direction: Vector3 = Vector3.ZERO
	var source_arc_position: Vector3 = Vector3.ZERO
	var arc_target_position: Vector3 = Vector3.ZERO
	var target_position: Vector3 = Vector3.ZERO
	var signed_arc_angle: float = 0.0
	var valid: bool = false


var traversal_speed: float
var detector: PlayerLedgeDetector

var active_candidate: MantleCandidate = null
var start_position: Vector3 = Vector3.ZERO
var source_lead_length: float = 0.0
var arc_length: float = 0.0
var over_lip_length: float = 0.0
var total_route_length: float = 0.0
var route_distance: float = 0.0
var completed: bool = false


func _init(
	p_traversal_speed: float,
	p_detector: PlayerLedgeDetector
) -> void:
	traversal_speed = p_traversal_speed
	detector = p_detector
	assert(
		traversal_speed > 0.0,
		"PlayerMantle requires traversal_speed to be greater than zero."
	)
	assert(
		detector != null,
		"PlayerMantle requires a PlayerLedgeDetector."
	)


func find_candidate(
	player: CharacterBody3D,
	support: PlayerSupport,
	source_candidate: PlayerLedgeDetector.LedgeCandidate
) -> MantleCandidate:
	return find_candidate_with_source_mode(
		player,
		support,
		source_candidate,
		true
	)


func find_air_candidate(
	player: CharacterBody3D,
	support: PlayerSupport,
	source_candidate: PlayerLedgeDetector.LedgeCandidate
) -> MantleCandidate:
	return find_candidate_with_source_mode(
		player,
		support,
		source_candidate,
		false
	)


func find_candidate_with_source_mode(
	player: CharacterBody3D,
	support: PlayerSupport,
	source_candidate: PlayerLedgeDetector.LedgeCandidate,
	refresh_source_attachment: bool
) -> MantleCandidate:
	if source_candidate == null:
		return null

	var refreshed_source: PlayerLedgeDetector.LedgeCandidate = source_candidate
	if refresh_source_attachment:
		# Mantling only needs the current attachment to remain valid. A full
		# shimmy span is unrelated to whether the body can clear the lip.
		refreshed_source = detector.find_attachment_candidate_at_position(
			player,
			support,
			source_candidate,
			source_candidate.wall_normal,
			player.global_position
		)
		if refreshed_source == null:
			return null

	var wall_normal := Vector3(
		refreshed_source.wall_normal.x,
		0.0,
		refreshed_source.wall_normal.z
	)
	if wall_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return null
	wall_normal = wall_normal.normalized()

	var top_normal: Vector3 = refreshed_source.top_normal
	if top_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return null
	top_normal = top_normal.normalized()
	if not detector.is_ledge_top_surface(top_normal):
		return null

	var ledge_axis: Vector3 = refreshed_source.ledge_direction
	if ledge_axis.length_squared() <= MOTION_EPSILON_SQUARED:
		ledge_axis = detector.get_ledge_direction(
			refreshed_source.wall_normal,
			refreshed_source.top_normal
		)
	if ledge_axis.length_squared() <= MOTION_EPSILON_SQUARED:
		return null
	ledge_axis = ledge_axis.normalized()
	if not detector.is_ledge_line_tilt_allowed(ledge_axis):
		return null

	# This radial direction describes the top side of the edge-clearance arc.
	# It does not imply that any platform depth exists behind the ledge.
	var top_path_normal: Vector3 = top_normal.slide(ledge_axis)
	if top_path_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return null
	top_path_normal = top_path_normal.normalized()
	if top_path_normal.dot(Vector3.UP) <= 0.0:
		return null

	# The final traversal phase moves along the actual top plane only far enough
	# to carry the capsule to the far side of the lip. No surface is searched for
	# or required along this direction.
	var top_inward_direction: Vector3 = detector.get_top_inward_direction(
		wall_normal,
		top_normal
	)
	if top_inward_direction.length_squared() <= MOTION_EPSILON_SQUARED:
		return null
	top_inward_direction = top_inward_direction.normalized()

	var normal_dot: float = clampf(
		wall_normal.dot(top_path_normal),
		-1.0,
		1.0
	)
	var cross_axis: float = (
		wall_normal.cross(top_path_normal).dot(ledge_axis)
	)
	var signed_arc_angle: float = atan2(cross_axis, normal_dot)
	var absolute_arc_angle: float = absf(signed_arc_angle)
	if (
		absolute_arc_angle <= ANGLE_EPSILON
		or absolute_arc_angle >= PI - ANGLE_EPSILON
	):
		return null

	var clearance_radius: float = get_clearance_radius()
	var bottom_cap_center_offset: float = get_bottom_cap_center_offset()
	var candidate := MantleCandidate.new()
	candidate.source_candidate = refreshed_source
	candidate.edge_point = refreshed_source.edge_point
	candidate.wall_normal = wall_normal
	candidate.ledge_axis = ledge_axis
	candidate.top_path_normal = top_path_normal
	candidate.top_inward_direction = top_inward_direction
	candidate.source_arc_position = (
		candidate.edge_point
		+ wall_normal * clearance_radius
		- Vector3.UP * bottom_cap_center_offset
	)
	candidate.arc_target_position = (
		candidate.edge_point
		+ top_path_normal * clearance_radius
		- Vector3.UP * bottom_cap_center_offset
	)
	candidate.target_position = (
		candidate.arc_target_position
		+ top_inward_direction * get_over_lip_distance()
	)
	candidate.signed_arc_angle = signed_arc_angle
	candidate.valid = true
	return candidate


func try_start(
	player: CharacterBody3D,
	candidate: MantleCandidate
) -> bool:
	if candidate == null or not candidate.valid:
		return false

	cancel()
	active_candidate = candidate
	start_position = player.global_position
	source_lead_length = start_position.distance_to(
		candidate.source_arc_position
	)
	arc_length = (
		get_clearance_radius()
		* absf(candidate.signed_arc_angle)
	)
	over_lip_length = candidate.arc_target_position.distance_to(
		candidate.target_position
	)
	total_route_length = (
		source_lead_length
		+ arc_length
		+ over_lip_length
	)

	if total_route_length <= 0.000001:
		cancel()
		return false

	# Mantle eligibility is deliberately limited to upward body clearance. The
	# arc and over-lip travel are not prevalidated as a landing: once this pure
	# vertical capsule sweep succeeds, mantle starts and live collision handling
	# owns the rest of the traversal.
	if not is_vertical_clearance_clear(player):
		cancel()
		return false

	return true


func update(
	player: CharacterBody3D,
	delta: float
) -> bool:
	if active_candidate == null:
		return false

	player.velocity = Vector3.ZERO
	var remaining_distance: float = minf(
		traversal_speed * delta,
		total_route_length - route_distance
	)
	var maximum_segment_distance: float = get_maximum_segment_distance()

	while remaining_distance > 0.000001:
		var segment_distance: float = minf(
			remaining_distance,
			maximum_segment_distance
		)
		var next_route_distance: float = minf(
			route_distance + segment_distance,
			total_route_length
		)
		var target_position: Vector3 = get_route_position(next_route_distance)
		var motion: Vector3 = target_position - player.global_position
		if not move_mantle_motion(player, motion):
			return false

		# The route is a clearance corridor, not an exact waypoint contract.
		# Expected wall/top contacts may slide the capsule a small amount away
		# from the sampled point; successful motion still advances the traversal.
		route_distance = next_route_distance
		remaining_distance -= segment_distance

	if total_route_length - route_distance <= 0.000001:
		route_distance = total_route_length
		# Completion is geometric: the capsule must actually cross to the far side
		# of the ledge. Reaching a numerically exact target point is irrelevant.
		if not has_crossed_ledge_boundary(player.global_position):
			return false
		completed = true
	return true


func is_vertical_clearance_clear(player: CharacterBody3D) -> bool:
	if active_candidate == null:
		return false

	var vertical_distance: float = (
		active_candidate.source_arc_position.y
		- start_position.y
	)
	if vertical_distance <= 0.000001:
		return true

	var from_transform: Transform3D = player.global_transform
	var vertical_motion: Vector3 = Vector3.UP * vertical_distance
	var result: Dictionary = simulate_mantle_motion(
		player,
		from_transform,
		vertical_motion
	)
	if result.is_empty():
		return false

	var transform_value: Variant = result.get("transform")
	if not (transform_value is Transform3D):
		return false
	var required_height: float = (
		from_transform.origin.y
		+ vertical_distance
		- get_route_progress_tolerance()
	)
	return transform_value.origin.y >= required_height


func simulate_mantle_motion(
	player: CharacterBody3D,
	from_transform: Transform3D,
	motion: Vector3
) -> Dictionary:
	var simulated_transform: Transform3D = from_transform
	var remaining_motion: Vector3 = motion

	for _iteration: int in range(PROBE_MAX_COLLISIONS):
		if remaining_motion.length_squared() <= MOTION_EPSILON_SQUARED:
			return {"transform": simulated_transform}

		var collision := KinematicCollision3D.new()
		var blocked: bool = player.test_move(
			simulated_transform,
			remaining_motion,
			collision,
			PROBE_SAFE_MARGIN,
			false,
			PROBE_MAX_COLLISIONS
		)
		if not blocked:
			simulated_transform.origin += remaining_motion
			return {"transform": simulated_transform}

		var previous_length_squared: float = remaining_motion.length_squared()
		var next_motion: Vector3 = collision.get_remainder()
		var collision_count: int = collision.get_collision_count()
		for collision_index: int in range(collision_count):
			if not is_expected_mantle_contact(
				collision,
				collision_index,
				active_candidate
			):
				return {}
			next_motion = next_motion.slide(
				collision.get_normal(collision_index)
			)

		var travel: Vector3 = collision.get_travel()
		simulated_transform.origin += travel
		if (
			travel.length_squared() <= MOTION_EPSILON_SQUARED
			and next_motion.length_squared()
			>= previous_length_squared - MOTION_EPSILON_SQUARED
		):
			return {}
		remaining_motion = next_motion

	return {}


func move_mantle_motion(
	player: CharacterBody3D,
	motion: Vector3
) -> bool:
	var remaining_motion: Vector3 = motion
	for _iteration: int in range(PROBE_MAX_COLLISIONS):
		if remaining_motion.length_squared() <= MOTION_EPSILON_SQUARED:
			return true

		var collision: KinematicCollision3D = player.move_and_collide(
			remaining_motion,
			false,
			PROBE_SAFE_MARGIN,
			false,
			PROBE_MAX_COLLISIONS
		)
		if collision == null:
			return true

		var previous_length_squared: float = remaining_motion.length_squared()
		var next_motion: Vector3 = collision.get_remainder()
		var collision_count: int = collision.get_collision_count()
		for collision_index: int in range(collision_count):
			if not is_expected_mantle_contact(
				collision,
				collision_index,
				active_candidate
			):
				return false
			next_motion = next_motion.slide(
				collision.get_normal(collision_index)
			)

		if (
			collision.get_travel().length_squared()
			<= MOTION_EPSILON_SQUARED
			and next_motion.length_squared()
			>= previous_length_squared - MOTION_EPSILON_SQUARED
		):
			return false
		remaining_motion = next_motion
	return false


func is_expected_mantle_contact(
	collision: KinematicCollision3D,
	collision_index: int,
	candidate: MantleCandidate
) -> bool:
	if candidate == null:
		return false

	var collision_point: Vector3 = collision.get_position(collision_index)
	if not is_contact_local_to_mantle_geometry(collision_point, candidate):
		return false

	var collision_normal: Vector3 = collision.get_normal(collision_index)
	if collision_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return false
	var planar_normal: Vector3 = collision_normal.slide(candidate.ledge_axis)
	if planar_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return false
	planar_normal = planar_normal.normalized()

	# Edge solvers can report any normal between the wall face and top face.
	# Treat that whole local sector as expected instead of requiring the normal
	# to match either neighboring face exactly.
	var contact_dot: float = clampf(
		candidate.wall_normal.dot(planar_normal),
		-1.0,
		1.0
	)
	var contact_cross: float = (
		candidate.wall_normal.cross(planar_normal).dot(candidate.ledge_axis)
	)
	var contact_angle: float = atan2(contact_cross, contact_dot)
	var total_angle: float = candidate.signed_arc_angle
	if total_angle > 0.0:
		return (
			contact_angle >= -ANGLE_EPSILON
			and contact_angle <= total_angle + ANGLE_EPSILON
		)
	return (
		contact_angle <= ANGLE_EPSILON
		and contact_angle >= total_angle - ANGLE_EPSILON
	)


func is_contact_local_to_mantle_geometry(
	point: Vector3,
	candidate: MantleCandidate
) -> bool:
	if candidate == null:
		return false
	if not is_within_local_ledge_width(point, candidate):
		return false

	var tolerance: float = get_expected_route_surface_plane_tolerance()
	if is_point_near_plane(
		point,
		candidate.edge_point,
		candidate.wall_normal,
		tolerance
	):
		return true

	if (
		candidate.source_candidate != null
		and is_point_near_plane(
			point,
			candidate.source_candidate.top_point,
			candidate.source_candidate.top_normal,
			tolerance
		)
	):
		return true

	# Intermediate edge normals need not belong closely to either face plane,
	# but their contact point must remain local to the actual ledge line.
	return distance_to_edge_line(point, candidate) <= tolerance


func is_within_local_ledge_width(
	point: Vector3,
	candidate: MantleCandidate
) -> bool:
	var horizontal_axis := Vector3(
		candidate.ledge_axis.x,
		0.0,
		candidate.ledge_axis.z
	)
	if horizontal_axis.length_squared() <= MOTION_EPSILON_SQUARED:
		return false
	horizontal_axis = horizontal_axis.normalized()
	var delta: Vector3 = point - candidate.edge_point
	var horizontal_delta := Vector3(delta.x, 0.0, delta.z)
	var lateral_distance: float = absf(horizontal_delta.dot(horizontal_axis))
	return lateral_distance <= get_expected_route_lateral_tolerance()


func distance_to_edge_line(
	point: Vector3,
	candidate: MantleCandidate
) -> float:
	var axis: Vector3 = candidate.ledge_axis
	if axis.length_squared() <= MOTION_EPSILON_SQUARED:
		return INF
	axis = axis.normalized()
	var delta: Vector3 = point - candidate.edge_point
	var radial_delta: Vector3 = delta - axis * delta.dot(axis)
	return radial_delta.length()


func is_point_near_plane(
	point: Vector3,
	plane_point: Vector3,
	plane_normal: Vector3,
	tolerance: float
) -> bool:
	if plane_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return false
	var normalized_normal: Vector3 = plane_normal.normalized()
	return absf(
		(point - plane_point).dot(normalized_normal)
	) <= tolerance


func get_route_position(distance_along_route: float) -> Vector3:
	if active_candidate == null:
		return start_position

	var clamped_distance: float = clampf(
		distance_along_route,
		0.0,
		total_route_length
	)
	if (
		source_lead_length > 0.000001
		and clamped_distance <= source_lead_length
	):
		return start_position.lerp(
			active_candidate.source_arc_position,
			clamped_distance / source_lead_length
		)

	var arc_end_distance: float = source_lead_length + arc_length
	if (
		arc_length > 0.000001
		and clamped_distance <= arc_end_distance
	):
		var arc_distance: float = clamped_distance - source_lead_length
		var arc_fraction: float = clampf(
			arc_distance / arc_length,
			0.0,
			1.0
		)
		var angle: float = active_candidate.signed_arc_angle * arc_fraction
		var radial_offset: Vector3 = (
			active_candidate.wall_normal.rotated(
				active_candidate.ledge_axis,
				angle
			)
			* get_clearance_radius()
		)
		return (
			active_candidate.edge_point
			+ radial_offset
			- Vector3.UP * get_bottom_cap_center_offset()
		)

	if over_lip_length <= 0.000001:
		return active_candidate.target_position
	var over_lip_distance: float = clamped_distance - arc_end_distance
	var over_lip_fraction: float = clampf(
		over_lip_distance / over_lip_length,
		0.0,
		1.0
	)
	return active_candidate.arc_target_position.lerp(
		active_candidate.target_position,
		over_lip_fraction
	)


func has_crossed_ledge_boundary(position: Vector3) -> bool:
	if active_candidate == null:
		return false
	var required_progress: float = (
		(active_candidate.target_position - active_candidate.edge_point).dot(
			active_candidate.top_inward_direction
		)
		- get_route_progress_tolerance()
	)
	var current_progress: float = (
		(position - active_candidate.edge_point).dot(
			active_candidate.top_inward_direction
		)
	)
	return current_progress >= required_progress


func get_route_progress_tolerance() -> float:
	return PROBE_SAFE_MARGIN + ROUTE_CLEARANCE_SLACK


func get_clearance_radius() -> float:
	# The route owns a clearance envelope outside the physics solver margin.
	# Inflate it further for the chord error introduced by straight segments
	# approximating the circular edge arc.
	var collision_envelope_radius: float = (
		detector.get_capsule_radius()
		+ PROBE_SAFE_MARGIN
		+ ROUTE_CLEARANCE_SLACK
	)
	var half_segment_angle: float = deg_to_rad(
		MAX_ROUTE_SEGMENT_ANGLE_DEGREES * 0.5
	)
	return collision_envelope_radius / maxf(cos(half_segment_angle), 0.0001)


func get_bottom_cap_center_offset() -> float:
	return (
		detector.get_capsule_bottom_offset()
		+ detector.get_capsule_radius()
	)


func get_over_lip_distance() -> float:
	return get_clearance_radius() * OVER_LIP_TRAVEL_RADIUS_RATIO


func get_maximum_segment_distance() -> float:
	return maxf(
		PROBE_SAFE_MARGIN,
		get_clearance_radius()
		* deg_to_rad(MAX_ROUTE_SEGMENT_ANGLE_DEGREES)
	)


func get_expected_route_surface_plane_tolerance() -> float:
	return maxf(
		PROBE_SAFE_MARGIN,
		detector.get_capsule_radius()
		* EXPECTED_ROUTE_SURFACE_PLANE_TOLERANCE_RADIUS_RATIO
	)


func get_expected_route_lateral_tolerance() -> float:
	return (
		detector.get_capsule_radius()
		+ detector.get_shimmy_attachment_correction_limit()
	)


func is_active() -> bool:
	return active_candidate != null


func has_completed() -> bool:
	return completed


func get_release_candidate() -> PlayerLedgeDetector.LedgeCandidate:
	if active_candidate == null:
		return null
	return active_candidate.source_candidate


func get_target_position() -> Vector3:
	if active_candidate == null:
		return Vector3.ZERO
	return active_candidate.target_position


func cancel() -> void:
	active_candidate = null
	start_position = Vector3.ZERO
	source_lead_length = 0.0
	arc_length = 0.0
	over_lip_length = 0.0
	total_route_length = 0.0
	route_distance = 0.0
	completed = false
