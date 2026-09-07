class_name PlayerLedgeCorner
extends RefCounted


const PROBE_SAFE_MARGIN: float = 0.001
const PROBE_MAX_COLLISIONS: int = 8
const MOTION_EPSILON_SQUARED: float = 0.000001

const ENDPOINT_SCAN_STEPS: int = 10
const ENDPOINT_SEARCH_STEPS: int = 10
const MAX_LOCAL_LEDGE_TURN_DEGREES: float = 15.0
const MAX_RIGHT_ANGLE_ERROR_DEGREES: float = 15.0
const MAX_ROUTE_SEGMENT_ANGLE_DEGREES: float = 5.0

const CONNECTION_TOLERANCE_RADIUS_RATIO: float = 0.15
const CONNECTION_NEAR_SAMPLE_RADIUS_RATIO: float = 0.16
const EXPECTED_ROUTE_WALL_MIN_ALIGNMENT: float = 0.9
const EXPECTED_ROUTE_WALL_PLANE_TOLERANCE_RADIUS_RATIO: float = 0.5
const EXPECTED_ROUTE_LOCALITY_RADIUS_RATIO: float = 1.5


class LedgeConnection:
	var source_candidate: PlayerLedgeDetector.LedgeCandidate = null
	var target_candidate: PlayerLedgeDetector.LedgeCandidate = null
	var connection_point: Vector3 = Vector3.ZERO
	var source_direction: Vector3 = Vector3.ZERO
	var target_direction: Vector3 = Vector3.ZERO
	var source_wall_normal: Vector3 = Vector3.ZERO
	var target_wall_normal: Vector3 = Vector3.ZERO
	var target_continuation_direction: Vector3 = Vector3.ZERO
	var signed_wall_turn_angle: float = 0.0
	var changes_wall: bool = false
	var valid: bool = false


class CornerCandidate:
	var connection: LedgeConnection = null
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
	var changes_wall: bool = false
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
	assert(turn_speed_degrees > 0.0, "PlayerLedgeCorner requires turn_speed_degrees to be greater than zero.")
	assert(detector != null, "PlayerLedgeCorner requires a PlayerLedgeDetector.")


func find_candidate(
	player: CharacterBody3D,
	support: PlayerSupport,
	source_candidate: PlayerLedgeDetector.LedgeCandidate,
	segment_wall_normal: Vector3,
	shimmy_direction: Vector3
) -> CornerCandidate:
	if source_candidate == null:
		return null

	var source_normal: Vector3 = _horizontal_normal(segment_wall_normal)
	if source_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return null

	var source_travel: Vector3 = _horizontal_normal(shimmy_direction)
	if source_travel.length_squared() <= MOTION_EPSILON_SQUARED:
		return null

	if absf(source_normal.dot(source_travel)) > sin(deg_to_rad(MAX_LOCAL_LEDGE_TURN_DEGREES)):
		return null

	var source_direction: Vector3 = get_oriented_ledge_direction(
		source_candidate.ledge_direction,
		source_travel
	)
	if source_direction.length_squared() <= MOTION_EPSILON_SQUARED:
		return null

	var endpoint_result: Dictionary = find_source_endpoint(
		player,
		support,
		source_candidate,
		source_normal,
		source_direction
	)
	if endpoint_result.is_empty():
		return null

	var endpoint_value: Variant = endpoint_result.get("point")
	var resolution_value: Variant = endpoint_result.get("resolution")
	if not (endpoint_value is Vector3):
		return null
	if typeof(resolution_value) != TYPE_FLOAT and typeof(resolution_value) != TYPE_INT:
		return null

	var endpoint: Vector3 = endpoint_value
	var endpoint_resolution: float = float(resolution_value)

	var connection: LedgeConnection = find_same_wall_connection(
		player,
		support,
		source_candidate,
		source_normal,
		source_travel,
		source_direction,
		endpoint,
		endpoint_resolution
	)

	if connection == null:
		connection = find_wall_turn_connection(
			player,
			support,
			source_candidate,
			source_normal,
			source_travel,
			source_direction,
			endpoint,
			endpoint_resolution
		)

	if connection == null or not connection.valid:
		return null

	return build_corner_candidate(source_candidate, source_travel, connection)


func find_same_wall_connection(
	player: CharacterBody3D,
	support: PlayerSupport,
	source_candidate: PlayerLedgeDetector.LedgeCandidate,
	source_normal: Vector3,
	source_travel: Vector3,
	source_direction: Vector3,
	endpoint: Vector3,
	endpoint_resolution: float
) -> LedgeConnection:
	var target_probe_distance: float = get_target_probe_distance()
	var target_hint: Vector3 = endpoint + source_travel * target_probe_distance
	var target_candidate: PlayerLedgeDetector.LedgeCandidate = find_local_ledge_candidate(
		player,
		support,
		source_normal,
		target_hint,
		get_slope_aware_height_window(support, target_probe_distance),
		true,
		true
	)
	if target_candidate == null:
		return null

	var target_normal: Vector3 = _horizontal_normal(target_candidate.wall_normal)
	if target_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return null

	var minimum_wall_alignment: float = cos(deg_to_rad(MAX_LOCAL_LEDGE_TURN_DEGREES))
	if target_normal.dot(source_normal) < minimum_wall_alignment:
		return null

	var target_direction: Vector3 = get_oriented_ledge_direction(
		target_candidate.ledge_direction,
		source_travel
	)
	if target_direction.length_squared() <= MOTION_EPSILON_SQUARED:
		return null

	# Smooth parallel continuation belongs to normal shimmy. Refuse to use the
	# transition system as a bridge across a gap between parallel ledges.
	if target_direction.dot(source_direction) >= minimum_wall_alignment:
		return null

	return build_validated_connection(
		player,
		support,
		source_candidate,
		target_candidate,
		source_normal,
		target_normal,
		source_direction,
		target_direction,
		source_travel,
		endpoint,
		endpoint_resolution,
		target_probe_distance,
		false
	)


func find_wall_turn_connection(
	player: CharacterBody3D,
	support: PlayerSupport,
	source_candidate: PlayerLedgeDetector.LedgeCandidate,
	source_normal: Vector3,
	source_travel: Vector3,
	source_direction: Vector3,
	endpoint: Vector3,
	endpoint_resolution: float
) -> LedgeConnection:
	var expected_target_normal: Vector3 = source_travel
	var expected_target_continuation: Vector3 = -source_normal
	var target_probe_distance: float = get_target_probe_distance()

	var preliminary_hint: Vector3 = endpoint + expected_target_continuation * target_probe_distance
	var preliminary_wall: PlayerLedgeDetector.WallHit = detector.find_wall_near_edge(
		player,
		expected_target_normal,
		preliminary_hint
	)
	if preliminary_wall == null:
		return null

	var target_normal: Vector3 = _horizontal_normal(preliminary_wall.normal)
	if target_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return null

	var minimum_target_alignment: float = cos(deg_to_rad(MAX_RIGHT_ANGLE_ERROR_DEGREES))
	if target_normal.dot(expected_target_normal) < minimum_target_alignment:
		return null

	var signed_turn_angle: float = get_signed_horizontal_angle(source_normal, target_normal)
	var absolute_turn_degrees: float = rad_to_deg(absf(signed_turn_angle))
	if absolute_turn_degrees < 90.0 - MAX_RIGHT_ANGLE_ERROR_DEGREES or absolute_turn_degrees > 90.0 + MAX_RIGHT_ANGLE_ERROR_DEGREES:
		return null

	var target_continuation: Vector3 = get_oriented_wall_tangent(
		target_normal,
		expected_target_continuation
	)
	if target_continuation.length_squared() <= MOTION_EPSILON_SQUARED:
		return null

	# This wall-plane intersection is only an X/Z discovery hint. The real
	# connection height comes later from the two sampled 3D ledge segments.
	var horizontal_corner_result: Dictionary = find_wall_plane_corner_point(
		source_candidate.edge_point,
		source_normal,
		preliminary_wall.point,
		target_normal,
		endpoint.y
	)
	if horizontal_corner_result.is_empty():
		return null

	var horizontal_corner_value: Variant = horizontal_corner_result.get("point")
	if not (horizontal_corner_value is Vector3):
		return null
	var horizontal_corner: Vector3 = horizontal_corner_value

	var endpoint_horizontal_delta := Vector3(
		horizontal_corner.x - endpoint.x,
		0.0,
		horizontal_corner.z - endpoint.z
	)
	var discovery_tolerance: float = endpoint_resolution + detector.get_top_probe_inset() + get_connection_tolerance()
	if endpoint_horizontal_delta.length() > discovery_tolerance:
		return null

	var target_hint: Vector3 = horizontal_corner + target_continuation * target_probe_distance
	target_hint.y = endpoint.y
	var target_candidate: PlayerLedgeDetector.LedgeCandidate = find_local_ledge_candidate(
		player,
		support,
		target_normal,
		target_hint,
		get_slope_aware_height_window(support, target_probe_distance),
		true,
		true
	)
	if target_candidate == null:
		return null

	target_normal = _horizontal_normal(target_candidate.wall_normal)
	if target_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return null
	if target_normal.dot(expected_target_normal) < minimum_target_alignment:
		return null

	signed_turn_angle = get_signed_horizontal_angle(source_normal, target_normal)
	absolute_turn_degrees = rad_to_deg(absf(signed_turn_angle))
	if absolute_turn_degrees < 90.0 - MAX_RIGHT_ANGLE_ERROR_DEGREES or absolute_turn_degrees > 90.0 + MAX_RIGHT_ANGLE_ERROR_DEGREES:
		return null

	target_continuation = get_oriented_wall_tangent(target_normal, expected_target_continuation)
	if target_continuation.length_squared() <= MOTION_EPSILON_SQUARED:
		return null

	var target_direction: Vector3 = get_oriented_ledge_direction(
		target_candidate.ledge_direction,
		target_continuation
	)
	if target_direction.length_squared() <= MOTION_EPSILON_SQUARED:
		return null

	var target_horizontal_direction: Vector3 = _horizontal_normal(target_direction)
	if target_horizontal_direction.length_squared() <= MOTION_EPSILON_SQUARED:
		return null
	if target_horizontal_direction.dot(target_continuation) < minimum_target_alignment:
		return null

	return build_validated_connection(
		player,
		support,
		source_candidate,
		target_candidate,
		source_normal,
		target_normal,
		source_direction,
		target_direction,
		target_continuation,
		endpoint,
		endpoint_resolution,
		target_probe_distance,
		true
	)


func build_validated_connection(
	player: CharacterBody3D,
	support: PlayerSupport,
	source_candidate: PlayerLedgeDetector.LedgeCandidate,
	target_candidate: PlayerLedgeDetector.LedgeCandidate,
	source_normal: Vector3,
	target_normal: Vector3,
	source_direction: Vector3,
	target_direction: Vector3,
	target_continuation: Vector3,
	endpoint: Vector3,
	endpoint_resolution: float,
	target_probe_distance: float,
	changes_wall: bool
) -> LedgeConnection:
	var source_horizontal_factor: float = _horizontal_factor(source_direction)
	var target_horizontal_factor: float = _horizontal_factor(target_direction)
	if source_horizontal_factor <= 0.000001 or target_horizontal_factor <= 0.000001:
		return null

	var connection_tolerance: float = get_connection_tolerance()
	var closest_result: Dictionary = find_bounded_ledge_connection(
		endpoint,
		source_direction,
		endpoint_resolution + connection_tolerance,
		target_candidate.edge_point,
		target_direction,
		target_probe_distance + connection_tolerance,
		connection_tolerance,
		connection_tolerance
	)
	if closest_result.is_empty():
		return null

	var connection_value: Variant = closest_result.get("connection_point")
	if not (connection_value is Vector3):
		return null
	var connection_point: Vector3 = connection_value

	# The target must physically exist almost all the way back to the computed
	# connection. This rejects valid-looking infinite-line intersections across
	# real gaps.
	if not target_reaches_connection(
		player,
		support,
		target_candidate,
		target_direction,
		connection_point
	):
		return null

	var signed_turn_angle: float = 0.0
	if changes_wall:
		signed_turn_angle = get_signed_horizontal_angle(source_normal, target_normal)

	var connection := LedgeConnection.new()
	connection.source_candidate = source_candidate
	connection.target_candidate = target_candidate
	connection.connection_point = connection_point
	connection.source_direction = source_direction
	connection.target_direction = target_direction
	connection.source_wall_normal = source_normal
	connection.target_wall_normal = target_normal
	connection.target_continuation_direction = target_continuation
	connection.signed_wall_turn_angle = signed_turn_angle
	connection.changes_wall = changes_wall
	connection.valid = true
	return connection


func find_bounded_ledge_connection(
	source_origin: Vector3,
	source_direction: Vector3,
	source_horizontal_bound: float,
	target_origin: Vector3,
	target_direction: Vector3,
	target_backward_horizontal_bound: float,
	target_forward_horizontal_bound: float,
	connection_tolerance: float
) -> Dictionary:
	if source_horizontal_bound < 0.0 or target_backward_horizontal_bound < 0.0 or target_forward_horizontal_bound < 0.0 or connection_tolerance < 0.0:
		return {}

	var source: Vector3 = source_direction
	var target: Vector3 = target_direction
	if source.length_squared() <= MOTION_EPSILON_SQUARED or target.length_squared() <= MOTION_EPSILON_SQUARED:
		return {}
	source = source.normalized()
	target = target.normalized()

	var source_horizontal_factor: float = _horizontal_factor(source)
	var target_horizontal_factor: float = _horizontal_factor(target)
	if source_horizontal_factor <= 0.000001 or target_horizontal_factor <= 0.000001:
		return {}

	var between: Vector3 = source_origin - target_origin
	var source_target_dot: float = source.dot(target)
	var denominator: float = 1.0 - source_target_dot * source_target_dot

	# Near-parallel local ledge lines do not define a unique connection.
	if absf(denominator) <= 0.00001:
		return {}

	var source_between_dot: float = source.dot(between)
	var target_between_dot: float = target.dot(between)
	var source_parameter: float = (source_target_dot * target_between_dot - source_between_dot) / denominator
	var target_parameter: float = (target_between_dot - source_target_dot * source_between_dot) / denominator

	var source_horizontal_progress: float = source_parameter * source_horizontal_factor
	var target_horizontal_progress: float = target_parameter * target_horizontal_factor
	if absf(source_horizontal_progress) > source_horizontal_bound:
		return {}
	if target_horizontal_progress < -target_backward_horizontal_bound or target_horizontal_progress > target_forward_horizontal_bound:
		return {}

	var source_point: Vector3 = source_origin + source * source_parameter
	var target_point: Vector3 = target_origin + target * target_parameter
	if source_point.distance_to(target_point) > connection_tolerance:
		return {}

	return {
		"connection_point": (source_point + target_point) * 0.5,
		"source_point": source_point,
		"target_point": target_point,
		"source_parameter": source_parameter,
		"target_parameter": target_parameter,
	}


func target_reaches_connection(
	player: CharacterBody3D,
	support: PlayerSupport,
	target_candidate: PlayerLedgeDetector.LedgeCandidate,
	target_direction: Vector3,
	connection_point: Vector3
) -> bool:
	if target_candidate == null:
		return false

	var horizontal_factor: float = _horizontal_factor(target_direction)
	if horizontal_factor <= 0.000001:
		return false

	var near_horizontal_distance: float = maxf(
		PROBE_SAFE_MARGIN * 4.0,
		detector.get_capsule_radius() * CONNECTION_NEAR_SAMPLE_RADIUS_RATIO
	)
	var sample_point: Vector3 = connection_point + target_direction * (near_horizontal_distance / horizontal_factor)
	var sample_candidate: PlayerLedgeDetector.LedgeCandidate = find_local_ledge_candidate(
		player,
		support,
		target_candidate.wall_normal,
		sample_point,
		maxf(
			get_slope_aware_height_window(support, near_horizontal_distance),
			detector.get_shimmy_attachment_correction_limit()
		),
		false,
		false
	)
	if sample_candidate == null:
		return false

	var sample_direction: Vector3 = get_oriented_ledge_direction(sample_candidate.ledge_direction, target_direction)
	if sample_direction.length_squared() <= MOTION_EPSILON_SQUARED:
		return false

	var minimum_alignment: float = cos(deg_to_rad(MAX_LOCAL_LEDGE_TURN_DEGREES))
	if sample_direction.dot(target_direction) < minimum_alignment:
		return false

	var position_tolerance: float = get_connection_tolerance() + detector.get_shimmy_attachment_correction_limit()
	return sample_candidate.edge_point.distance_to(sample_point) <= position_tolerance


func build_corner_candidate(
	source_candidate: PlayerLedgeDetector.LedgeCandidate,
	source_travel: Vector3,
	connection: LedgeConnection
) -> CornerCandidate:
	if connection == null or not connection.valid:
		return null

	var source_arc_position: Vector3 = detector.get_hang_position(
		connection.connection_point,
		connection.source_wall_normal
	)
	var target_arc_position: Vector3 = source_arc_position
	if connection.changes_wall:
		target_arc_position = detector.get_hang_position(
			connection.connection_point,
			connection.target_wall_normal
		)

	var candidate := CornerCandidate.new()
	candidate.connection = connection
	candidate.source_candidate = source_candidate
	candidate.target_candidate = connection.target_candidate
	candidate.corner_point = connection.connection_point
	candidate.source_wall_normal = connection.source_wall_normal
	candidate.source_travel_direction = source_travel
	candidate.target_wall_normal = connection.target_wall_normal
	candidate.target_continuation_direction = connection.target_continuation_direction
	candidate.source_arc_position = source_arc_position
	candidate.target_arc_position = target_arc_position
	candidate.signed_turn_angle = connection.signed_wall_turn_angle
	candidate.changes_wall = connection.changes_wall
	candidate.valid = true
	return candidate


func find_source_endpoint(
	player: CharacterBody3D,
	support: PlayerSupport,
	source_candidate: PlayerLedgeDetector.LedgeCandidate,
	source_normal: Vector3,
	travel_direction: Vector3
) -> Dictionary:
	if not source_ledge_continues_at_distance(
		player,
		support,
		source_candidate,
		source_normal,
		travel_direction,
		0.0
	):
		return {}

	var search_distance: float = detector.get_max_horizontal_reach()
	var lower_distance: float = 0.0
	var upper_distance: float = -1.0
	var previous_distance: float = 0.0

	for scan_index: int in range(1, ENDPOINT_SCAN_STEPS + 1):
		var sample_distance: float = search_distance * float(scan_index) / float(ENDPOINT_SCAN_STEPS)
		if source_ledge_continues_at_distance(
			player,
			support,
			source_candidate,
			source_normal,
			travel_direction,
			sample_distance
		):
			previous_distance = sample_distance
			continue
		lower_distance = previous_distance
		upper_distance = sample_distance
		break

	if upper_distance < 0.0:
		return {}

	for _iteration: int in range(ENDPOINT_SEARCH_STEPS):
		var middle_distance: float = (lower_distance + upper_distance) * 0.5
		if source_ledge_continues_at_distance(
			player,
			support,
			source_candidate,
			source_normal,
			travel_direction,
			middle_distance
		):
			lower_distance = middle_distance
		else:
			upper_distance = middle_distance

	return {
		"point": get_ledge_point_at_horizontal_distance(
			source_candidate.edge_point,
			travel_direction,
			lower_distance
		),
		"resolution": upper_distance - lower_distance,
	}


func source_ledge_continues_at_distance(
	player: CharacterBody3D,
	support: PlayerSupport,
	source_candidate: PlayerLedgeDetector.LedgeCandidate,
	source_normal: Vector3,
	travel_direction: Vector3,
	horizontal_distance: float
) -> bool:
	var expected_point: Vector3 = get_ledge_point_at_horizontal_distance(
		source_candidate.edge_point,
		travel_direction,
		horizontal_distance
	)
	var sample_candidate: PlayerLedgeDetector.LedgeCandidate = find_local_ledge_candidate(
		player,
		support,
		source_normal,
		expected_point,
		detector.get_capsule_radius(),
		false,
		false
	)
	if sample_candidate == null:
		return false

	var sample_normal: Vector3 = _horizontal_normal(sample_candidate.wall_normal)
	if sample_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return false

	var minimum_alignment: float = cos(deg_to_rad(MAX_LOCAL_LEDGE_TURN_DEGREES))
	if sample_normal.dot(source_normal) < minimum_alignment:
		return false

	var correction_limit: float = detector.get_shimmy_attachment_correction_limit() + detector.get_shimmy_level_tolerance()
	if sample_candidate.edge_point.distance_to(expected_point) > correction_limit:
		return false

	var sample_direction: Vector3 = get_oriented_ledge_direction(
		sample_candidate.ledge_direction,
		travel_direction
	)
	if sample_direction.length_squared() <= MOTION_EPSILON_SQUARED:
		return false

	return sample_direction.dot(travel_direction) >= minimum_alignment


func find_local_ledge_candidate(
	player: CharacterBody3D,
	support: PlayerSupport,
	expected_wall_normal: Vector3,
	edge_hint: Vector3,
	height_window: float,
	require_span: bool,
	require_hang_pose: bool
) -> PlayerLedgeDetector.LedgeCandidate:
	if height_window <= 0.0:
		return null

	var expected_normal: Vector3 = _horizontal_normal(expected_wall_normal)
	if expected_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return null

	var wall_hit: PlayerLedgeDetector.WallHit = detector.find_wall_near_edge(
		player,
		expected_normal,
		edge_hint
	)
	if wall_hit == null:
		return null

	var wall_normal: Vector3 = _horizontal_normal(wall_hit.normal)
	if wall_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return null

	var minimum_wall_alignment: float = cos(deg_to_rad(MAX_LOCAL_LEDGE_TURN_DEGREES))
	if wall_normal.dot(expected_normal) < minimum_wall_alignment:
		return null

	var top_hit: PlayerLedgeDetector.TopHit = find_top_near_wall(
		player,
		support,
		wall_hit,
		edge_hint.y,
		height_window
	)
	if top_hit == null:
		return null

	var edge_point := Vector3(wall_hit.point.x, top_hit.point.y, wall_hit.point.z)
	if not detector.is_edge_exposed(player, edge_point, wall_normal):
		return null

	var ledge_direction: Vector3 = detector.get_ledge_direction(wall_normal, top_hit.normal)
	if ledge_direction.length_squared() <= MOTION_EPSILON_SQUARED:
		return null

	var candidate := PlayerLedgeDetector.LedgeCandidate.new()
	candidate.wall_collider_rid = wall_hit.collider_rid
	candidate.wall_shape_index = wall_hit.shape_index
	candidate.top_collider_rid = top_hit.collider_rid
	candidate.top_shape_index = top_hit.shape_index
	candidate.edge_point = edge_point
	candidate.wall_normal = wall_normal
	candidate.top_point = top_hit.point
	candidate.top_normal = top_hit.normal
	candidate.ledge_direction = ledge_direction
	candidate.hang_position = detector.get_hang_position(edge_point, wall_normal)

	if require_span and not detector.has_usable_ledge_span(
		player,
		support,
		edge_point,
		wall_normal,
		top_hit.point.y,
		ledge_direction
	):
		return null

	candidate.hangable = detector.is_hang_pose_valid(
		player,
		candidate,
		candidate.hang_position
	)
	if require_hang_pose and not candidate.hangable:
		return null

	return candidate


func find_top_near_wall(
	player: CharacterBody3D,
	support: PlayerSupport,
	wall_hit: PlayerLedgeDetector.WallHit,
	center_height: float,
	height_window: float
) -> PlayerLedgeDetector.TopHit:
	if wall_hit == null or height_window <= 0.0:
		return null

	# Always probe inward from the wall plane, matching normal ledge detection.
	# The previous regression came from casting this ray on the edge seam.
	var probe_center: Vector3 = wall_hit.point - wall_hit.normal * detector.get_top_probe_inset()
	probe_center.y = center_height
	return detector.raycast_top(
		player,
		support,
		probe_center + Vector3.UP * height_window,
		probe_center - Vector3.UP * height_window
	)


func get_ledge_point_at_horizontal_distance(
	origin: Vector3,
	ledge_direction: Vector3,
	horizontal_distance: float
) -> Vector3:
	var direction: Vector3 = ledge_direction
	if direction.length_squared() <= MOTION_EPSILON_SQUARED:
		return origin
	direction = direction.normalized()

	var horizontal_factor: float = _horizontal_factor(direction)
	if horizontal_factor <= 0.000001:
		return origin

	return origin + direction * (horizontal_distance / horizontal_factor)


func get_oriented_ledge_direction(
	ledge_direction: Vector3,
	preferred_direction: Vector3
) -> Vector3:
	var direction: Vector3 = ledge_direction
	if direction.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO
	direction = direction.normalized()

	var horizontal: Vector3 = _horizontal_normal(direction)
	var preferred: Vector3 = _horizontal_normal(preferred_direction)
	if horizontal.length_squared() <= MOTION_EPSILON_SQUARED or preferred.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO

	if horizontal.dot(preferred) < 0.0:
		direction = -direction
	return direction


func find_wall_plane_corner_point(
	source_point: Vector3,
	source_normal: Vector3,
	target_point: Vector3,
	target_normal: Vector3,
	height: float
) -> Dictionary:
	var determinant: float = source_normal.x * target_normal.z - source_normal.z * target_normal.x
	if absf(determinant) <= 0.000001:
		return {}

	var source_distance: float = source_normal.x * source_point.x + source_normal.z * source_point.z
	var target_distance: float = target_normal.x * target_point.x + target_normal.z * target_point.z
	var corner_x: float = (source_distance * target_normal.z - source_normal.z * target_distance) / determinant
	var corner_z: float = (source_normal.x * target_distance - source_distance * target_normal.x) / determinant
	return {"point": Vector3(corner_x, height, corner_z)}


func try_start(player: CharacterBody3D, candidate: CornerCandidate) -> bool:
	if candidate == null or not candidate.valid:
		return false

	cancel()
	active_corner = candidate
	start_position = player.global_position
	source_lead_length = start_position.distance_to(candidate.source_arc_position)
	arc_length = get_arc_radius() * absf(candidate.signed_turn_angle) if candidate.changes_wall else 0.0
	target_lead_length = candidate.target_arc_position.distance_to(candidate.target_candidate.hang_position)
	total_route_length = source_lead_length + arc_length + target_lead_length

	if total_route_length <= 0.000001:
		cancel()
		return false

	traversal_speed = get_arc_radius() * deg_to_rad(turn_speed_degrees)
	if traversal_speed <= 0.000001:
		cancel()
		return false

	current_wall_normal = candidate.source_wall_normal
	if not is_route_clear(player):
		cancel()
		return false
	return true


func update(player: CharacterBody3D, delta: float) -> bool:
	if active_corner == null:
		return false

	player.velocity = Vector3.ZERO
	var remaining_distance: float = minf(
		traversal_speed * delta,
		total_route_length - route_distance
	)
	var maximum_segment_distance: float = get_maximum_segment_distance()

	while remaining_distance > 0.000001:
		var segment_distance: float = minf(remaining_distance, maximum_segment_distance)
		var next_route_distance: float = minf(route_distance + segment_distance, total_route_length)
		var target_position: Vector3 = get_route_position(next_route_distance)
		if not move_corner_to_position(player, target_position):
			return false
		route_distance = next_route_distance
		current_wall_normal = get_route_wall_normal(route_distance)
		remaining_distance -= segment_distance

	if total_route_length - route_distance <= 0.000001:
		route_distance = total_route_length
		current_wall_normal = active_corner.target_wall_normal
		completed = true
	return true


func is_route_clear(player: CharacterBody3D) -> bool:
	if active_corner == null:
		return false

	var simulated_transform: Transform3D = player.global_transform
	var simulated_distance: float = 0.0
	var maximum_segment_distance: float = get_maximum_segment_distance()

	while total_route_length - simulated_distance > 0.000001:
		var next_distance: float = minf(
			simulated_distance + maximum_segment_distance,
			total_route_length
		)
		var target_position: Vector3 = get_route_position(next_distance)
		var result: Dictionary = simulate_corner_to_position(
			player,
			simulated_transform,
			target_position
		)
		if result.is_empty():
			return false
		var transform_value: Variant = result.get("transform")
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
	var remaining_motion: Vector3 = target_position - simulated_transform.origin

	for _iteration: int in range(PROBE_MAX_COLLISIONS):
		if remaining_motion.length_squared() <= MOTION_EPSILON_SQUARED:
			break

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
			remaining_motion = Vector3.ZERO
			break

		var previous_length_squared: float = remaining_motion.length_squared()
		var next_motion: Vector3 = collision.get_remainder()
		var collision_count: int = collision.get_collision_count()
		for collision_index: int in range(collision_count):
			if not is_expected_corner_contact(collision, collision_index):
				return {}
			next_motion = next_motion.slide(collision.get_normal(collision_index))

		var travel: Vector3 = collision.get_travel()
		simulated_transform.origin += travel
		if travel.length_squared() <= MOTION_EPSILON_SQUARED and next_motion.length_squared() >= previous_length_squared - MOTION_EPSILON_SQUARED:
			return {}
		remaining_motion = next_motion

	if simulated_transform.origin.distance_to(target_position) > get_route_position_tolerance():
		return {}
	return {"transform": simulated_transform}


func move_corner_to_position(player: CharacterBody3D, target_position: Vector3) -> bool:
	var remaining_motion: Vector3 = target_position - player.global_position

	for _iteration: int in range(PROBE_MAX_COLLISIONS):
		if remaining_motion.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var collision: KinematicCollision3D = player.move_and_collide(
			remaining_motion,
			false,
			PROBE_SAFE_MARGIN,
			false,
			PROBE_MAX_COLLISIONS
		)
		if collision == null:
			remaining_motion = Vector3.ZERO
			break

		var previous_length_squared: float = remaining_motion.length_squared()
		var next_motion: Vector3 = collision.get_remainder()
		var collision_count: int = collision.get_collision_count()
		for collision_index: int in range(collision_count):
			if not is_expected_corner_contact(collision, collision_index):
				return false
			next_motion = next_motion.slide(collision.get_normal(collision_index))

		if collision.get_travel().length_squared() <= MOTION_EPSILON_SQUARED and next_motion.length_squared() >= previous_length_squared - MOTION_EPSILON_SQUARED:
			return false
		remaining_motion = next_motion

	return player.global_position.distance_to(target_position) <= get_route_position_tolerance()


func is_expected_corner_contact(
	collision: KinematicCollision3D,
	collision_index: int
) -> bool:
	if active_corner == null:
		return false

	var collision_normal: Vector3 = _horizontal_normal(collision.get_normal(collision_index))
	if collision_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return false

	var collision_point: Vector3 = collision.get_position(collision_index)
	if not is_point_near_connection_region(collision_point):
		return false

	var tolerance: float = get_expected_route_wall_plane_tolerance()
	if is_contact_on_candidate_wall(
		collision_point,
		collision_normal,
		active_corner.source_candidate,
		tolerance
	):
		return true
	if is_contact_on_candidate_wall(
		collision_point,
		collision_normal,
		active_corner.target_candidate,
		tolerance
	):
		return true

	# Beveled/chamfered outward corners can have an intermediate normal.
	return active_corner.changes_wall and is_point_near_arc_region(collision_point) and is_normal_in_corner_sector(collision_normal)


func is_contact_on_candidate_wall(
	point: Vector3,
	normal: Vector3,
	candidate: PlayerLedgeDetector.LedgeCandidate,
	tolerance: float
) -> bool:
	if candidate == null:
		return false

	var expected_normal: Vector3 = _horizontal_normal(candidate.wall_normal)
	if expected_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return false
	if normal.dot(expected_normal) < EXPECTED_ROUTE_WALL_MIN_ALIGNMENT:
		return false
	return is_point_near_candidate_wall_plane(point, candidate, tolerance)


func is_point_near_candidate_wall_plane(
	point: Vector3,
	candidate: PlayerLedgeDetector.LedgeCandidate,
	tolerance: float
) -> bool:
	if candidate == null:
		return false
	var wall_normal: Vector3 = _horizontal_normal(candidate.wall_normal)
	if wall_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return false
	return absf((point - candidate.edge_point).dot(wall_normal)) <= tolerance


func is_point_near_connection_region(point: Vector3) -> bool:
	if active_corner == null:
		return false
	var delta: Vector3 = point - active_corner.corner_point
	delta.y = 0.0
	var locality_limit: float = maxf(
		detector.get_max_horizontal_reach(),
		detector.get_capsule_radius() * EXPECTED_ROUTE_LOCALITY_RADIUS_RATIO
	)
	return delta.length_squared() <= locality_limit * locality_limit


func is_point_near_arc_region(point: Vector3) -> bool:
	if active_corner == null:
		return false
	var delta: Vector3 = point - active_corner.corner_point
	delta.y = 0.0
	var limit: float = get_arc_radius() + get_expected_route_wall_plane_tolerance()
	return delta.length_squared() <= limit * limit


func is_normal_in_corner_sector(normal: Vector3) -> bool:
	if active_corner == null or not active_corner.changes_wall:
		return false

	var normal_angle: float = get_signed_horizontal_angle(
		active_corner.source_wall_normal,
		normal
	)
	var total_angle: float = active_corner.signed_turn_angle
	var margin: float = deg_to_rad(MAX_RIGHT_ANGLE_ERROR_DEGREES)
	if total_angle > 0.0:
		return normal_angle >= -margin and normal_angle <= total_angle + margin
	return normal_angle <= margin and normal_angle >= total_angle - margin


func get_route_position(distance_along_route: float) -> Vector3:
	if active_corner == null:
		return start_position

	var clamped_distance: float = clampf(distance_along_route, 0.0, total_route_length)
	if source_lead_length > 0.000001 and clamped_distance <= source_lead_length:
		return start_position.lerp(
			active_corner.source_arc_position,
			clamped_distance / source_lead_length
		)

	var arc_distance: float = clamped_distance - source_lead_length
	if arc_length > 0.000001 and arc_distance <= arc_length:
		var arc_fraction: float = clampf(arc_distance / arc_length, 0.0, 1.0)
		var angle: float = active_corner.signed_turn_angle * arc_fraction
		var radial_offset: Vector3 = active_corner.source_wall_normal.rotated(
			Vector3.UP,
			angle
		) * get_arc_radius()
		var arc_position: Vector3 = active_corner.corner_point + radial_offset
		arc_position.y = active_corner.corner_point.y - detector.get_hang_anchor_height()
		return arc_position

	if target_lead_length <= 0.000001:
		return active_corner.target_candidate.hang_position

	var target_distance: float = clamped_distance - source_lead_length - arc_length
	var target_fraction: float = clampf(target_distance / target_lead_length, 0.0, 1.0)
	return active_corner.target_arc_position.lerp(
		active_corner.target_candidate.hang_position,
		target_fraction
	)


func get_route_wall_normal(distance_along_route: float) -> Vector3:
	if active_corner == null:
		return Vector3.ZERO

	var clamped_distance: float = clampf(distance_along_route, 0.0, total_route_length)
	if clamped_distance <= source_lead_length:
		return active_corner.source_wall_normal

	var arc_distance: float = clamped_distance - source_lead_length
	if arc_length > 0.000001 and arc_distance <= arc_length:
		var arc_fraction: float = clampf(arc_distance / arc_length, 0.0, 1.0)
		return active_corner.source_wall_normal.rotated(
			Vector3.UP,
			active_corner.signed_turn_angle * arc_fraction
		).normalized()
	return active_corner.target_wall_normal


func get_oriented_wall_tangent(
	wall_normal: Vector3,
	preferred_direction: Vector3
) -> Vector3:
	var tangent: Vector3 = Vector3.UP.cross(_horizontal_normal(wall_normal))
	tangent.y = 0.0
	if tangent.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO
	tangent = tangent.normalized()

	var preferred: Vector3 = _horizontal_normal(preferred_direction)
	if preferred.length_squared() > MOTION_EPSILON_SQUARED and tangent.dot(preferred) < 0.0:
		tangent = -tangent
	return tangent


func get_signed_horizontal_angle(from_normal: Vector3, to_normal: Vector3) -> float:
	var normalized_from: Vector3 = _horizontal_normal(from_normal)
	var normalized_to: Vector3 = _horizontal_normal(to_normal)
	if normalized_from.length_squared() <= MOTION_EPSILON_SQUARED or normalized_to.length_squared() <= MOTION_EPSILON_SQUARED:
		return 0.0
	var normal_dot: float = clampf(normalized_from.dot(normalized_to), -1.0, 1.0)
	var cross_y: float = normalized_from.cross(normalized_to).dot(Vector3.UP)
	return atan2(cross_y, normal_dot)


func get_target_probe_distance() -> float:
	return detector.get_ledge_span_half_width() + detector.get_top_probe_inset() + PROBE_SAFE_MARGIN


func get_slope_aware_height_window(
	support: PlayerSupport,
	horizontal_distance: float
) -> float:
	var maximum_slope_radians: float = deg_to_rad(
		clampf(support.max_walkable_slope, 0.0, 89.0)
	)
	return absf(horizontal_distance) * tan(maximum_slope_radians) + detector.get_shimmy_attachment_correction_limit() + PROBE_SAFE_MARGIN


func get_connection_tolerance() -> float:
	return maxf(
		PROBE_SAFE_MARGIN * 4.0,
		detector.get_capsule_radius() * CONNECTION_TOLERANCE_RADIUS_RATIO
	)


func _horizontal_factor(direction: Vector3) -> float:
	return Vector3(direction.x, 0.0, direction.z).length()


func _horizontal_normal(direction: Vector3) -> Vector3:
	var result := Vector3(direction.x, 0.0, direction.z)
	if result.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO
	return result.normalized()


func get_arc_radius() -> float:
	return detector.get_hang_wall_distance() + PROBE_SAFE_MARGIN


func get_maximum_segment_distance() -> float:
	return maxf(
		PROBE_SAFE_MARGIN,
		get_arc_radius() * deg_to_rad(MAX_ROUTE_SEGMENT_ANGLE_DEGREES)
	)


func get_route_position_tolerance() -> float:
	return PROBE_SAFE_MARGIN * 2.0


func get_expected_route_wall_plane_tolerance() -> float:
	return maxf(
		PROBE_SAFE_MARGIN,
		detector.get_capsule_radius() * EXPECTED_ROUTE_WALL_PLANE_TOLERANCE_RADIUS_RATIO
	)


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
		result.append(active_corner.source_candidate)
	if active_corner.target_candidate != null:
		result.append(active_corner.target_candidate)
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
