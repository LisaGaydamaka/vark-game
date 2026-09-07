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


enum Phase {
	NONE,
	LIFT,
	ARC,
	CROSS,
}


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
var route_edge_point: Vector3 = Vector3.ZERO
var lift_target_height: float = 0.0
var phase: int = Phase.NONE
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
	route_edge_point = get_nearest_edge_point(player.global_position)
	lift_target_height = (
		route_edge_point.y
		- get_bottom_cap_center_offset()
	)

	# Eligibility and the first live phase are deliberately the same motion:
	# pure vertical capsule clearance at the player's current horizontal pose.
	if not is_vertical_clearance_clear(player):
		cancel()
		return false

	phase = Phase.LIFT
	if has_reached_lift_height(player.global_position):
		phase = Phase.ARC
	return true


func update(
	player: CharacterBody3D,
	delta: float
) -> bool:
	if active_candidate == null or phase == Phase.NONE:
		return false

	player.velocity = Vector3.ZERO
	var remaining_distance: float = traversal_speed * delta

	# At most three phase transitions can occur in one frame. Motion state is
	# always derived from the capsule's actual pose after collision resolution.
	for _phase_iteration: int in range(Phase.CROSS + 1):
		if completed or remaining_distance <= 0.000001:
			break

		match phase:
			Phase.LIFT:
				if has_reached_lift_height(player.global_position):
					phase = Phase.ARC
					continue

				var lift_distance: float = minf(
					remaining_distance,
					maxf(0.0, lift_target_height - player.global_position.y)
				)
				var lift_motion: Vector3 = Vector3.UP * lift_distance
				var lift_travel: float = move_mantle_motion(player, lift_motion)
				if lift_travel < 0.0:
					return false
				remaining_distance = maxf(0.0, remaining_distance - lift_travel)
				if has_reached_lift_height(player.global_position):
					phase = Phase.ARC
					continue
				if lift_travel <= sqrt(MOTION_EPSILON_SQUARED):
					return false
				break

			Phase.ARC:
				if has_completed_arc(player.global_position):
					phase = Phase.CROSS
					continue

				var arc_motion: Vector3 = get_arc_motion(
					player.global_position,
					remaining_distance
				)
				if arc_motion.length_squared() <= MOTION_EPSILON_SQUARED:
					return false
				var arc_travel: float = move_mantle_motion(player, arc_motion)
				if arc_travel < 0.0:
					return false
				remaining_distance = maxf(0.0, remaining_distance - arc_travel)
				if has_completed_arc(player.global_position):
					phase = Phase.CROSS
					continue
				if arc_travel <= sqrt(MOTION_EPSILON_SQUARED):
					return false
				break

			Phase.CROSS:
				if has_crossed_ledge_boundary(player.global_position):
					completed = true
					break

				var cross_motion: Vector3 = get_cross_motion(
					player.global_position,
					remaining_distance
				)
				if cross_motion.length_squared() <= MOTION_EPSILON_SQUARED:
					return false
				var cross_travel: float = move_mantle_motion(player, cross_motion)
				if cross_travel < 0.0:
					return false
				remaining_distance = maxf(0.0, remaining_distance - cross_travel)
				if has_crossed_ledge_boundary(player.global_position):
					completed = true
					break
				if cross_travel <= sqrt(MOTION_EPSILON_SQUARED):
					return false
				break

	return true


func is_vertical_clearance_clear(player: CharacterBody3D) -> bool:
	if active_candidate == null:
		return false

	var vertical_distance: float = lift_target_height - player.global_position.y
	if vertical_distance <= get_route_progress_tolerance():
		return true

	# This is intentionally a pure vertical sweep. Do not slide along the wall or
	# top here: mantle eligibility means that this vertical body space actually
	# exists at the current horizontal pose.
	var collision := KinematicCollision3D.new()
	var blocked: bool = player.test_move(
		player.global_transform,
		Vector3.UP * vertical_distance,
		collision,
		PROBE_SAFE_MARGIN,
		false,
		PROBE_MAX_COLLISIONS
	)
	if not blocked:
		return true

	return (
		collision.get_travel().y
		>= vertical_distance - get_route_progress_tolerance()
	)


func move_mantle_motion(
	player: CharacterBody3D,
	motion: Vector3
) -> float:
	var start_position: Vector3 = player.global_position
	var remaining_motion: Vector3 = motion

	for _iteration: int in range(PROBE_MAX_COLLISIONS):
		if remaining_motion.length_squared() <= MOTION_EPSILON_SQUARED:
			return player.global_position.distance_to(start_position)

		var collision: KinematicCollision3D = player.move_and_collide(
			remaining_motion,
			false,
			PROBE_SAFE_MARGIN,
			false,
			PROBE_MAX_COLLISIONS
		)
		if collision == null:
			return player.global_position.distance_to(start_position)

		var previous_length_squared: float = remaining_motion.length_squared()
		var next_motion: Vector3 = collision.get_remainder()
		var collision_count: int = collision.get_collision_count()
		for collision_index: int in range(collision_count):
			if not is_expected_mantle_contact(
				collision,
				collision_index,
				active_candidate
			):
				return -1.0
			next_motion = next_motion.slide(
				collision.get_normal(collision_index)
			)

		if (
			collision.get_travel().length_squared()
			<= MOTION_EPSILON_SQUARED
			and next_motion.length_squared()
			>= previous_length_squared - MOTION_EPSILON_SQUARED
		):
			return -1.0
		remaining_motion = next_motion

	return -1.0


func get_arc_motion(
	position: Vector3,
	maximum_distance: float
) -> Vector3:
	if active_candidate == null or maximum_distance <= 0.0:
		return Vector3.ZERO

	var current_angle: float = get_current_arc_angle(position)
	var target_angle: float = active_candidate.signed_arc_angle
	var remaining_angle: float = target_angle - current_angle
	if absf(remaining_angle) <= get_arc_angle_tolerance():
		return Vector3.ZERO

	var maximum_angle_step: float = minf(
		deg_to_rad(MAX_ROUTE_SEGMENT_ANGLE_DEGREES),
		maximum_distance / get_clearance_radius()
	)
	var angle_step: float = minf(absf(remaining_angle), maximum_angle_step)
	angle_step *= signf(remaining_angle)
	var next_angle: float = current_angle + angle_step

	var target_bottom_cap_center: Vector3 = (
		route_edge_point
		+ active_candidate.wall_normal.rotated(
			active_candidate.ledge_axis,
			next_angle
		) * get_clearance_radius()
	)
	var target_position: Vector3 = (
		target_bottom_cap_center
		- Vector3.UP * get_bottom_cap_center_offset()
	)
	var motion: Vector3 = target_position - position
	if motion.length() > maximum_distance:
		motion = motion.normalized() * maximum_distance
	return motion


func get_cross_motion(
	position: Vector3,
	maximum_distance: float
) -> Vector3:
	if active_candidate == null or maximum_distance <= 0.0:
		return Vector3.ZERO

	var remaining_progress: float = (
		get_required_cross_progress()
		- get_cross_progress(position)
	)
	if remaining_progress <= get_route_progress_tolerance():
		return Vector3.ZERO
	return (
		active_candidate.top_inward_direction
		* minf(maximum_distance, remaining_progress)
	)


func get_current_arc_angle(position: Vector3) -> float:
	if active_candidate == null:
		return 0.0

	var bottom_cap_center: Vector3 = get_bottom_cap_center_position(position)
	var delta: Vector3 = bottom_cap_center - route_edge_point
	var radial_delta: Vector3 = (
		delta
		- active_candidate.ledge_axis
		* delta.dot(active_candidate.ledge_axis)
	)
	if radial_delta.length_squared() <= MOTION_EPSILON_SQUARED:
		return 0.0
	radial_delta = radial_delta.normalized()

	var current_angle: float = atan2(
		active_candidate.wall_normal.cross(radial_delta).dot(
			active_candidate.ledge_axis
		),
		clampf(
			active_candidate.wall_normal.dot(radial_delta),
			-1.0,
			1.0
		)
	)
	if active_candidate.signed_arc_angle > 0.0:
		return clampf(
			current_angle,
			0.0,
			active_candidate.signed_arc_angle
		)
	return clampf(
		current_angle,
		active_candidate.signed_arc_angle,
		0.0
	)


func has_completed_arc(position: Vector3) -> bool:
	if active_candidate == null:
		return false
	return (
		absf(
			active_candidate.signed_arc_angle
			- get_current_arc_angle(position)
		)
		<= get_arc_angle_tolerance()
	)


func has_reached_lift_height(position: Vector3) -> bool:
	return (
		position.y
		>= lift_target_height - get_route_progress_tolerance()
	)


func has_crossed_ledge_boundary(position: Vector3) -> bool:
	if active_candidate == null:
		return false
	return (
		get_cross_progress(position)
		>= get_required_cross_progress() - get_route_progress_tolerance()
	)


func get_cross_progress(position: Vector3) -> float:
	if active_candidate == null:
		return -INF
	var bottom_cap_center: Vector3 = get_bottom_cap_center_position(position)
	return (
		(bottom_cap_center - route_edge_point).dot(
			active_candidate.top_inward_direction
		)
	)


func get_required_cross_progress() -> float:
	return get_over_lip_distance()


func get_nearest_edge_point(position: Vector3) -> Vector3:
	if active_candidate == null:
		return Vector3.ZERO
	var bottom_cap_center: Vector3 = get_bottom_cap_center_position(position)
	var axis: Vector3 = active_candidate.ledge_axis
	return (
		active_candidate.edge_point
		+ axis * (bottom_cap_center - active_candidate.edge_point).dot(axis)
	)


func get_bottom_cap_center_position(position: Vector3) -> Vector3:
	return position + Vector3.UP * get_bottom_cap_center_offset()


func get_arc_angle_tolerance() -> float:
	return maxf(
		ANGLE_EPSILON,
		get_route_progress_tolerance() / get_clearance_radius()
	)


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

	var local_edge_point: Vector3 = candidate.edge_point
	if candidate == active_candidate and phase != Phase.NONE:
		local_edge_point = route_edge_point
	var delta: Vector3 = point - local_edge_point
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
	route_edge_point = Vector3.ZERO
	lift_target_height = 0.0
	phase = Phase.NONE
	completed = false
