class_name PlayerLedgeCorner
extends RefCounted


const PROBE_SAFE_MARGIN: float = 0.001
const PROBE_MAX_COLLISIONS: int = 8
const MOTION_EPSILON_SQUARED: float = 0.000001
const CORNER_ENDPOINT_SEARCH_STEPS: int = 8
const MAX_RIGHT_ANGLE_ERROR_DEGREES: float = 15.0
const MAX_ROUTE_SEGMENT_ANGLE_DEGREES: float = 5.0


class CornerCandidate:
	var source_candidate: PlayerLedgeDetector.LedgeCandidate = null
	var target_candidate: PlayerLedgeDetector.LedgeCandidate = null

	var corner_point: Vector3 = Vector3.ZERO

	var source_wall_normal: Vector3 = Vector3.ZERO
	var source_travel_direction: Vector3 = Vector3.ZERO

	var target_wall_normal: Vector3 = Vector3.ZERO
	var target_continuation_direction: Vector3 = Vector3.ZERO

	var source_arc_position: Vector3 = Vector3.ZERO
	var target_arc_position: Vector3 = Vector3.ZERO

	var signed_turn_angle: float = 0.0
	var valid: bool = false


var turn_speed_degrees: float
var detector: PlayerLedgeDetector

var active_corner: CornerCandidate = null
var start_position: Vector3 = Vector3.ZERO
var source_lead_length: float = 0.0
var arc_length: float = 0.0
var target_lead_length: float = 0.0
var total_route_length: float = 0.0
var route_distance: float = 0.0
var traversal_speed: float = 0.0
var current_wall_normal: Vector3 = Vector3.ZERO
var completed: bool = false


func _init(
	p_turn_speed_degrees: float,
	p_detector: PlayerLedgeDetector
) -> void:
	turn_speed_degrees = p_turn_speed_degrees
	detector = p_detector

	assert(
		turn_speed_degrees > 0.0,
		"PlayerLedgeCorner requires turn_speed_degrees to be greater than zero."
	)
	assert(
		detector != null,
		"PlayerLedgeCorner requires a PlayerLedgeDetector."
	)


func find_candidate(
	player: CharacterBody3D,
	support: PlayerSupport,
	source_candidate: PlayerLedgeDetector.LedgeCandidate,
	segment_wall_normal: Vector3,
	shimmy_direction: Vector3
) -> CornerCandidate:
	if source_candidate == null:
		return null

	var source_normal: Vector3 = segment_wall_normal
	source_normal.y = 0.0

	if (
		source_normal.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return null

	source_normal = source_normal.normalized()

	var source_travel: Vector3 = shimmy_direction
	source_travel.y = 0.0

	if (
		source_travel.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return null

	source_travel = source_travel.normalized()

	if (
		absf(source_normal.dot(source_travel))
		> sin(
			deg_to_rad(
				MAX_RIGHT_ANGLE_ERROR_DEGREES
			)
		)
	):
		return null

	var endpoint_result: Dictionary = find_source_endpoint(
		player,
		source_candidate,
		source_normal,
		source_travel
	)

	if endpoint_result.is_empty():
		return null

	var endpoint_value: Variant = endpoint_result.get("point")
	var endpoint_resolution_value: Variant = (
		endpoint_result.get("resolution")
	)

	if not (endpoint_value is Vector3):
		return null

	if (
		typeof(endpoint_resolution_value) != TYPE_FLOAT
		and typeof(endpoint_resolution_value) != TYPE_INT
	):
		return null

	var endpoint_guess: Vector3 = endpoint_value
	var endpoint_resolution: float = float(
		endpoint_resolution_value
	)
	var endpoint_tolerance: float = maxf(
		PROBE_SAFE_MARGIN * 2.0,
		endpoint_resolution + PROBE_SAFE_MARGIN * 2.0
	)

	var expected_target_normal: Vector3 = source_travel
	var expected_target_continuation: Vector3 = -source_normal

	var target_probe_inset: float = (
		detector.get_ledge_span_half_width()
		+ detector.get_top_probe_inset()
		+ PROBE_SAFE_MARGIN
	)
	var target_probe_point: Vector3 = (
		endpoint_guess
		+ expected_target_continuation
		* target_probe_inset
	)

	var target_wall: PlayerLedgeDetector.WallHit = (
		detector.find_wall_near_edge(
			player,
			expected_target_normal,
			target_probe_point
		)
	)

	if target_wall == null:
		return null

	var minimum_target_alignment: float = cos(
		deg_to_rad(
			MAX_RIGHT_ANGLE_ERROR_DEGREES
		)
	)

	if (
		target_wall.normal.dot(
			expected_target_normal
		)
		< minimum_target_alignment
	):
		return null

	var signed_turn_angle: float = get_signed_horizontal_angle(
		source_normal,
		target_wall.normal
	)
	var absolute_turn_degrees: float = rad_to_deg(
		absf(signed_turn_angle)
	)

	if (
		absolute_turn_degrees
		< 90.0 - MAX_RIGHT_ANGLE_ERROR_DEGREES
		or absolute_turn_degrees
		> 90.0 + MAX_RIGHT_ANGLE_ERROR_DEGREES
	):
		return null

	var target_continuation: Vector3 = (
		get_oriented_wall_tangent(
			target_wall.normal,
			expected_target_continuation
		)
	)

	if (
		target_continuation.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return null

	var corner_point_result: Dictionary = (
		find_wall_plane_corner_point(
			source_candidate.edge_point,
			source_normal,
			target_wall.point,
			target_wall.normal,
			source_candidate.edge_point.y
		)
	)

	if corner_point_result.is_empty():
		return null

	var corner_point_value: Variant = (
		corner_point_result.get("point")
	)

	if not (corner_point_value is Vector3):
		return null

	var corner_point: Vector3 = corner_point_value
	var corner_guess_delta: Vector3 = Vector3(
		corner_point.x - endpoint_guess.x,
		0.0,
		corner_point.z - endpoint_guess.z
	)

	if (
		corner_guess_delta.length()
		> endpoint_tolerance
	):
		return null

	target_probe_point = (
		corner_point
		+ target_continuation
		* target_probe_inset
	)
	target_wall = detector.find_wall_near_edge(
		player,
		expected_target_normal,
		target_probe_point
	)

	if target_wall == null:
		return null

	if (
		target_wall.normal.dot(
			expected_target_normal
		)
		< minimum_target_alignment
	):
		return null

	signed_turn_angle = get_signed_horizontal_angle(
		source_normal,
		target_wall.normal
	)
	absolute_turn_degrees = rad_to_deg(
		absf(signed_turn_angle)
	)

	if (
		absolute_turn_degrees
		< 90.0 - MAX_RIGHT_ANGLE_ERROR_DEGREES
		or absolute_turn_degrees
		> 90.0 + MAX_RIGHT_ANGLE_ERROR_DEGREES
	):
		return null

	target_continuation = get_oriented_wall_tangent(
		target_wall.normal,
		expected_target_continuation
	)

	if (
		target_continuation.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return null

	var target_top: PlayerLedgeDetector.TopHit = (
		detector.find_top_for_hang(
			player,
			support,
			target_wall,
			source_candidate.edge_point.y
		)
	)

	if target_top == null:
		return null

	if (
		absf(
			target_top.point.y
			- source_candidate.edge_point.y
		)
		> detector.get_shimmy_level_tolerance()
	):
		return null

	var target_edge_point: Vector3 = Vector3(
		target_wall.point.x,
		target_top.point.y,
		target_wall.point.z
	)
	var target_from_corner: Vector3 = Vector3(
		target_edge_point.x - corner_point.x,
		0.0,
		target_edge_point.z - corner_point.z
	)
	var target_progress: float = target_from_corner.dot(
		target_continuation
	)

	if (
		target_progress
		< target_probe_inset - endpoint_tolerance
	):
		return null

	var target_ledge_axis: Vector3 = (
		Vector3.UP.cross(target_wall.normal)
	)

	if (
		target_ledge_axis.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return null

	target_ledge_axis = target_ledge_axis.normalized()

	if (
		absf(
			target_ledge_axis.dot(
				target_continuation
			)
		)
		< minimum_target_alignment
	):
		return null

	if not detector.has_usable_ledge_span(
		player,
		support,
		target_edge_point,
		target_wall.normal,
		target_top.point.y,
		target_ledge_axis
	):
		return null

	var target_hang_position: Vector3 = (
		detector.get_hang_position(
			target_edge_point,
			target_wall.normal
		)
	)
	var target_candidate: PlayerLedgeDetector.LedgeCandidate = (
		PlayerLedgeDetector.LedgeCandidate.new()
	)
	target_candidate.wall_collider_rid = (
		target_wall.collider_rid
	)
	target_candidate.wall_shape_index = (
		target_wall.shape_index
	)
	target_candidate.top_collider_rid = (
		target_top.collider_rid
	)
	target_candidate.top_shape_index = (
		target_top.shape_index
	)
	target_candidate.edge_point = target_edge_point
	target_candidate.wall_normal = target_wall.normal
	target_candidate.top_point = target_top.point
	target_candidate.top_normal = target_top.normal
	target_candidate.ledge_direction = target_ledge_axis
	target_candidate.hang_position = target_hang_position
	target_candidate.hangable = detector.is_hang_pose_valid(
		player,
		target_candidate,
		target_hang_position
	)

	if not target_candidate.hangable:
		return null

	var arc_radius: float = get_arc_radius()
	var source_arc_position: Vector3 = (
		corner_point
		+ source_normal * arc_radius
	)
	source_arc_position.y = (
		source_candidate.hang_position.y
	)

	var target_arc_position: Vector3 = (
		corner_point
		+ target_wall.normal * arc_radius
	)
	target_arc_position.y = target_hang_position.y

	var candidate: CornerCandidate = CornerCandidate.new()
	candidate.source_candidate = source_candidate
	candidate.target_candidate = target_candidate
	candidate.corner_point = corner_point
	candidate.source_wall_normal = source_normal
	candidate.source_travel_direction = source_travel
	candidate.target_wall_normal = target_wall.normal
	candidate.target_continuation_direction = (
		target_continuation
	)
	candidate.source_arc_position = source_arc_position
	candidate.target_arc_position = target_arc_position
	candidate.signed_turn_angle = signed_turn_angle
	candidate.valid = true
	return candidate


func find_source_endpoint(
	player: CharacterBody3D,
	source_candidate: PlayerLedgeDetector.LedgeCandidate,
	source_normal: Vector3,
	travel_direction: Vector3
) -> Dictionary:
	var start_wall: PlayerLedgeDetector.WallHit = (
		detector.find_wall_near_edge(
			player,
			source_normal,
			source_candidate.edge_point
		)
	)

	if (
		start_wall == null
		or not detector.is_wall_continuous(
			start_wall,
			source_normal,
			source_candidate.edge_point
		)
	):
		return {}

	var search_distance: float = (
		detector.get_max_horizontal_reach()
	)
	var far_point: Vector3 = (
		source_candidate.edge_point
		+ travel_direction * search_distance
	)
	var far_wall: PlayerLedgeDetector.WallHit = (
		detector.find_wall_near_edge(
			player,
			source_normal,
			far_point
		)
	)

	if (
		far_wall != null
		and detector.is_wall_continuous(
			far_wall,
			source_normal,
			far_point
		)
	):
		return {}

	var lower_distance: float = 0.0
	var upper_distance: float = search_distance

	for _iteration: int in range(
		CORNER_ENDPOINT_SEARCH_STEPS
	):
		var middle_distance: float = (
			(lower_distance + upper_distance)
			* 0.5
		)
		var sample_point: Vector3 = (
			source_candidate.edge_point
			+ travel_direction
			* middle_distance
		)
		var sample_wall: PlayerLedgeDetector.WallHit = (
			detector.find_wall_near_edge(
				player,
				source_normal,
				sample_point
			)
		)
		var source_exists: bool = (
			sample_wall != null
			and detector.is_wall_continuous(
				sample_wall,
				source_normal,
				sample_point
			)
		)

		if source_exists:
			lower_distance = middle_distance
		else:
			upper_distance = middle_distance

	var endpoint: Vector3 = (
		source_candidate.edge_point
		+ travel_direction
		* lower_distance
	)
	endpoint.y = source_candidate.edge_point.y

	return {
		"point": endpoint,
		"resolution": upper_distance - lower_distance,
	}


func find_wall_plane_corner_point(
	source_point: Vector3,
	source_normal: Vector3,
	target_point: Vector3,
	target_normal: Vector3,
	height: float
) -> Dictionary:
	var determinant: float = (
		source_normal.x * target_normal.z
		- source_normal.z * target_normal.x
	)

	if absf(determinant) <= 0.000001:
		return {}

	var source_distance: float = (
		source_normal.x * source_point.x
		+ source_normal.z * source_point.z
	)
	var target_distance: float = (
		target_normal.x * target_point.x
		+ target_normal.z * target_point.z
	)
	var corner_x: float = (
		(
			source_distance * target_normal.z
			- source_normal.z * target_distance
		)
		/ determinant
	)
	var corner_z: float = (
		(
			source_normal.x * target_distance
			- source_distance * target_normal.x
		)
		/ determinant
	)

	return {
		"point": Vector3(
			corner_x,
			height,
			corner_z
		)
	}


func try_start(
	player: CharacterBody3D,
	candidate: CornerCandidate
) -> bool:
	if candidate == null or not candidate.valid:
		return false

	cancel()
	active_corner = candidate
	start_position = player.global_position

	source_lead_length = start_position.distance_to(
		candidate.source_arc_position
	)
	arc_length = (
		get_arc_radius()
		* absf(candidate.signed_turn_angle)
	)
	target_lead_length = (
		candidate.target_arc_position.distance_to(
			candidate.target_candidate.hang_position
		)
	)
	total_route_length = (
		source_lead_length
		+ arc_length
		+ target_lead_length
	)

	if total_route_length <= 0.000001:
		cancel()
		return false

	traversal_speed = (
		get_arc_radius()
		* deg_to_rad(turn_speed_degrees)
	)

	if traversal_speed <= 0.000001:
		cancel()
		return false

	current_wall_normal = (
		candidate.source_wall_normal
	)

	if not is_route_clear(player):
		cancel()
		return false

	return true


func update(
	player: CharacterBody3D,
	delta: float
) -> bool:
	if active_corner == null:
		return false

	player.velocity = Vector3.ZERO

	var remaining_distance: float = minf(
		traversal_speed * delta,
		total_route_length - route_distance
	)
	var maximum_segment_distance: float = (
		get_maximum_segment_distance()
	)

	while remaining_distance > 0.000001:
		var segment_distance: float = minf(
			remaining_distance,
			maximum_segment_distance
		)
		var next_route_distance: float = minf(
			route_distance + segment_distance,
			total_route_length
		)
		var target_position: Vector3 = (
			get_route_position(
				next_route_distance
			)
		)

		if not move_corner_to_position(
			player,
			target_position
		):
			return false

		route_distance = next_route_distance
		current_wall_normal = get_route_wall_normal(
			route_distance
		)
		remaining_distance -= segment_distance

	if (
		total_route_length - route_distance
		<= 0.000001
	):
		route_distance = total_route_length
		current_wall_normal = (
			active_corner.target_wall_normal
		)
		completed = true

	return true


func is_route_clear(
	player: CharacterBody3D
) -> bool:
	if active_corner == null:
		return false

	var simulated_transform: Transform3D = (
		player.global_transform
	)
	var simulated_distance: float = 0.0
	var maximum_segment_distance: float = (
		get_maximum_segment_distance()
	)

	while (
		total_route_length - simulated_distance
		> 0.000001
	):
		var next_distance: float = minf(
			simulated_distance
			+ maximum_segment_distance,
			total_route_length
		)
		var target_position: Vector3 = (
			get_route_position(next_distance)
		)
		var result: Dictionary = simulate_corner_to_position(
			player,
			simulated_transform,
			target_position
		)

		if result.is_empty():
			return false

		var transform_value: Variant = (
			result.get("transform")
		)

		if not (transform_value is Transform3D):
			return false

		simulated_transform = transform_value
		simulated_distance = next_distance

	return true


func simulate_corner_to_position(
	player: CharacterBody3D,
	from_transform: Transform3D,
	target_position: Vector3
) -> Dictionary:
	var simulated_transform: Transform3D = from_transform
	var remaining_motion: Vector3 = (
		target_position
		- simulated_transform.origin
	)

	for _iteration: int in range(
		PROBE_MAX_COLLISIONS
	):
		if (
			remaining_motion.length_squared()
			<= MOTION_EPSILON_SQUARED
		):
			break

		var collision: KinematicCollision3D = (
			KinematicCollision3D.new()
		)
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
			remaining_motion = Vector3.ZERO
			break

		var previous_length_squared: float = (
			remaining_motion.length_squared()
		)
		var next_motion: Vector3 = (
			collision.get_remainder()
		)
		var collision_count: int = (
			collision.get_collision_count()
		)

		for collision_index: int in range(
			collision_count
		):
			if not is_expected_corner_contact(
				collision,
				collision_index
			):
				return {}

			next_motion = next_motion.slide(
				collision.get_normal(
					collision_index
				)
			)

		var travel: Vector3 = collision.get_travel()
		simulated_transform.origin += travel

		if (
			travel.length_squared()
			<= MOTION_EPSILON_SQUARED
			and next_motion.length_squared()
			>= previous_length_squared
			- MOTION_EPSILON_SQUARED
		):
			return {}

		remaining_motion = next_motion

	if (
		simulated_transform.origin.distance_to(
			target_position
		)
		> get_route_position_tolerance()
	):
		return {}

	return {
		"transform": simulated_transform
	}


func move_corner_to_position(
	player: CharacterBody3D,
	target_position: Vector3
) -> bool:
	var remaining_motion: Vector3 = (
		target_position
		- player.global_position
	)

	for _iteration: int in range(
		PROBE_MAX_COLLISIONS
	):
		if (
			remaining_motion.length_squared()
			<= MOTION_EPSILON_SQUARED
		):
			break

		var collision: KinematicCollision3D = (
			player.move_and_collide(
				remaining_motion,
				false,
				PROBE_SAFE_MARGIN,
				false,
				PROBE_MAX_COLLISIONS
			)
		)

		if collision == null:
			remaining_motion = Vector3.ZERO
			break

		var previous_length_squared: float = (
			remaining_motion.length_squared()
		)
		var next_motion: Vector3 = (
			collision.get_remainder()
		)
		var collision_count: int = (
			collision.get_collision_count()
		)

		for collision_index: int in range(
			collision_count
		):
			if not is_expected_corner_contact(
				collision,
				collision_index
			):
				return false

			next_motion = next_motion.slide(
				collision.get_normal(
					collision_index
				)
			)

		if (
			collision.get_travel().length_squared()
			<= MOTION_EPSILON_SQUARED
			and next_motion.length_squared()
			>= previous_length_squared
			- MOTION_EPSILON_SQUARED
		):
			return false

		remaining_motion = next_motion

	return (
		player.global_position.distance_to(
			target_position
		)
		<= get_route_position_tolerance()
	)


func is_expected_corner_contact(
	collision: KinematicCollision3D,
	collision_index: int
) -> bool:
	if active_corner == null:
		return false

	var matches_source: bool = matches_candidate_wall(
		collision,
		collision_index,
		active_corner.source_candidate
	)
	var matches_target: bool = matches_candidate_wall(
		collision,
		collision_index,
		active_corner.target_candidate
	)

	if not matches_source and not matches_target:
		return false

	var collision_normal: Vector3 = collision.get_normal(
		collision_index
	)
	collision_normal.y = 0.0

	if (
		collision_normal.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return false

	collision_normal = collision_normal.normalized()

	return is_normal_in_corner_sector(
		collision_normal
	)


func is_normal_in_corner_sector(
	normal: Vector3
) -> bool:
	if active_corner == null:
		return false

	var normal_angle: float = get_signed_horizontal_angle(
		active_corner.source_wall_normal,
		normal
	)
	var total_angle: float = (
		active_corner.signed_turn_angle
	)
	var margin: float = deg_to_rad(
		MAX_RIGHT_ANGLE_ERROR_DEGREES
	)

	if total_angle > 0.0:
		return (
			normal_angle >= -margin
			and normal_angle <= total_angle + margin
		)

	return (
		normal_angle <= margin
		and normal_angle >= total_angle - margin
	)


func matches_candidate_wall(
	collision: KinematicCollision3D,
	collision_index: int,
	candidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	if candidate == null:
		return false

	if (
		collision.get_collider_rid(
			collision_index
		)
		!= candidate.wall_collider_rid
	):
		return false

	var collider_shape_index: int = (
		collision.get_collider_shape_index(
			collision_index
		)
	)

	if (
		candidate.wall_shape_index >= 0
		and collider_shape_index >= 0
		and collider_shape_index
		!= candidate.wall_shape_index
	):
		return false

	return true


func get_route_position(
	distance_along_route: float
) -> Vector3:
	if active_corner == null:
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
		var source_fraction: float = (
			clamped_distance
			/ source_lead_length
		)
		return start_position.lerp(
			active_corner.source_arc_position,
			source_fraction
		)

	var arc_distance: float = (
		clamped_distance - source_lead_length
	)

	if (
		arc_length > 0.000001
		and arc_distance <= arc_length
	):
		var arc_fraction: float = clampf(
			arc_distance / arc_length,
			0.0,
			1.0
		)
		var angle: float = (
			active_corner.signed_turn_angle
			* arc_fraction
		)
		var radial_offset: Vector3 = (
			active_corner.source_wall_normal.rotated(
				Vector3.UP,
				angle
			)
			* get_arc_radius()
		)
		var arc_position: Vector3 = (
			active_corner.corner_point
			+ radial_offset
		)
		arc_position.y = lerpf(
			active_corner.source_arc_position.y,
			active_corner.target_arc_position.y,
			arc_fraction
		)
		return arc_position

	if target_lead_length <= 0.000001:
		return active_corner.target_candidate.hang_position

	var target_distance: float = (
		clamped_distance
		- source_lead_length
		- arc_length
	)
	var target_fraction: float = clampf(
		target_distance / target_lead_length,
		0.0,
		1.0
	)
	return active_corner.target_arc_position.lerp(
		active_corner.target_candidate.hang_position,
		target_fraction
	)


func get_route_wall_normal(
	distance_along_route: float
) -> Vector3:
	if active_corner == null:
		return Vector3.ZERO

	var clamped_distance: float = clampf(
		distance_along_route,
		0.0,
		total_route_length
	)

	if clamped_distance <= source_lead_length:
		return active_corner.source_wall_normal

	var arc_distance: float = (
		clamped_distance - source_lead_length
	)

	if (
		arc_length > 0.000001
		and arc_distance <= arc_length
	):
		var arc_fraction: float = clampf(
			arc_distance / arc_length,
			0.0,
			1.0
		)
		return (
			active_corner.source_wall_normal.rotated(
				Vector3.UP,
				active_corner.signed_turn_angle
				* arc_fraction
			).normalized()
		)

	return active_corner.target_wall_normal


func get_oriented_wall_tangent(
	wall_normal: Vector3,
	preferred_direction: Vector3
) -> Vector3:
	var tangent: Vector3 = (
		Vector3.UP.cross(wall_normal)
	)
	tangent.y = 0.0

	if (
		tangent.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return Vector3.ZERO

	tangent = tangent.normalized()

	var preferred: Vector3 = preferred_direction
	preferred.y = 0.0

	if (
		preferred.length_squared()
		> MOTION_EPSILON_SQUARED
		and tangent.dot(preferred) < 0.0
	):
		tangent = -tangent

	return tangent


func get_signed_horizontal_angle(
	from_normal: Vector3,
	to_normal: Vector3
) -> float:
	var normalized_from: Vector3 = from_normal
	normalized_from.y = 0.0

	var normalized_to: Vector3 = to_normal
	normalized_to.y = 0.0

	if (
		normalized_from.length_squared()
		<= MOTION_EPSILON_SQUARED
		or normalized_to.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return 0.0

	normalized_from = normalized_from.normalized()
	normalized_to = normalized_to.normalized()

	var normal_dot: float = clampf(
		normalized_from.dot(normalized_to),
		-1.0,
		1.0
	)
	var cross_y: float = (
		normalized_from.cross(normalized_to).dot(
			Vector3.UP
		)
	)

	return atan2(
		cross_y,
		normal_dot
	)


func get_arc_radius() -> float:
	return (
		detector.get_hang_wall_distance()
		+ PROBE_SAFE_MARGIN
	)


func get_maximum_segment_distance() -> float:
	return maxf(
		PROBE_SAFE_MARGIN,
		get_arc_radius()
		* deg_to_rad(
			MAX_ROUTE_SEGMENT_ANGLE_DEGREES
		)
	)


func get_route_position_tolerance() -> float:
	return PROBE_SAFE_MARGIN * 2.0


func is_active() -> bool:
	return active_corner != null


func has_completed() -> bool:
	return completed


func get_current_wall_normal() -> Vector3:
	return current_wall_normal


func get_target_candidate() -> PlayerLedgeDetector.LedgeCandidate:
	if active_corner == null:
		return null

	return active_corner.target_candidate


func get_target_wall_normal() -> Vector3:
	if active_corner == null:
		return Vector3.ZERO

	return active_corner.target_wall_normal


func get_release_candidates() -> Array[PlayerLedgeDetector.LedgeCandidate]:
	var result: Array[PlayerLedgeDetector.LedgeCandidate] = []

	if active_corner == null:
		return result

	if active_corner.source_candidate != null:
		result.append(
			active_corner.source_candidate
		)

	if active_corner.target_candidate != null:
		result.append(
			active_corner.target_candidate
		)

	return result


func cancel() -> void:
	active_corner = null
	start_position = Vector3.ZERO
	source_lead_length = 0.0
	arc_length = 0.0
	target_lead_length = 0.0
	total_route_length = 0.0
	route_distance = 0.0
	traversal_speed = 0.0
	current_wall_normal = Vector3.ZERO
	completed = false
