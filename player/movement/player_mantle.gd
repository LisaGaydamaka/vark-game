class_name PlayerMantle
extends RefCounted


const PROBE_SAFE_MARGIN: float = 0.001
const ROUTE_CLEARANCE_SLACK: float = 0.002
const PROBE_MAX_COLLISIONS: int = 8
const MOTION_EPSILON_SQUARED: float = 0.000001


enum Phase {
	NONE,
	LIFT,
	FORWARD,
}


class MantleCandidate:
	var source_candidate: PlayerLedgeDetector.LedgeCandidate = null
	var edge_point: Vector3 = Vector3.ZERO
	var wall_normal: Vector3 = Vector3.ZERO
	var ledge_axis: Vector3 = Vector3.ZERO
	var traversal_axis: Vector3 = Vector3.ZERO
	var target_position: Vector3 = Vector3.ZERO
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

	var traversal_axis := Vector3(
		ledge_axis.x,
		0.0,
		ledge_axis.z
	)
	if traversal_axis.length_squared() <= MOTION_EPSILON_SQUARED:
		return null
	traversal_axis = traversal_axis.normalized()

	var candidate := MantleCandidate.new()
	candidate.source_candidate = refreshed_source
	candidate.edge_point = refreshed_source.edge_point
	candidate.wall_normal = wall_normal
	candidate.ledge_axis = ledge_axis
	candidate.traversal_axis = traversal_axis
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
	route_edge_point = get_crossing_edge_point(player.global_position)
	var vertical_edge_clearance: float = get_vertical_edge_clearance()
	if not is_finite(vertical_edge_clearance):
		cancel()
		return false

	lift_target_height = (
		route_edge_point.y
		+ vertical_edge_clearance
		- get_bottom_cap_center_offset()
	)
	active_candidate.target_position = Vector3(
		route_edge_point.x,
		lift_target_height,
		route_edge_point.z
	)

	# Eligibility and live traversal share the same first contract: the capsule
	# must be able to move straight upward at its current horizontal position.
	if not is_vertical_clearance_clear(player):
		cancel()
		return false

	phase = Phase.LIFT
	if has_reached_lift_height(player.global_position):
		phase = Phase.FORWARD
		if has_reached_forward_limit(player.global_position):
			completed = true
	return true


func update(
	player: CharacterBody3D,
	delta: float
) -> bool:
	if active_candidate == null or phase == Phase.NONE:
		return false

	player.velocity = Vector3.ZERO
	var remaining_distance: float = traversal_speed * delta

	for _phase_iteration: int in range(2):
		if completed or remaining_distance <= 0.000001:
			break

		match phase:
			Phase.LIFT:
				if has_reached_lift_height(player.global_position):
					phase = Phase.FORWARD
					continue

				var lift_distance: float = minf(
					remaining_distance,
					maxf(0.0, lift_target_height - player.global_position.y)
				)
				if lift_distance <= 0.000001:
					phase = Phase.FORWARD
					continue

				var collision: KinematicCollision3D = player.move_and_collide(
					Vector3.UP * lift_distance,
					false,
					PROBE_SAFE_MARGIN,
					false,
					PROBE_MAX_COLLISIONS
				)
				var actual_lift: float = lift_distance
				if collision != null:
					actual_lift = maxf(0.0, collision.get_travel().y)
				remaining_distance = maxf(0.0, remaining_distance - actual_lift)

				if has_reached_lift_height(player.global_position):
					phase = Phase.FORWARD
					continue

				# The vertical path was prevalidated. A live collision before the
				# required height therefore means traversal can no longer stay valid.
				if collision != null or actual_lift <= sqrt(MOTION_EPSILON_SQUARED):
					return false
				break

			Phase.FORWARD:
				if has_reached_forward_limit(player.global_position):
					completed = true
					break

				var outward_distance: float = get_outward_distance(
					player.global_position
				)
				var forward_distance: float = minf(
					remaining_distance,
					maxf(0.0, outward_distance)
				)
				if forward_distance <= get_route_progress_tolerance():
					completed = true
					break

				# Forward travel has a hard geometric ceiling: the capsule centerline
				# may reach the edge/wall plane but may never be carried beyond it.
				# If any geometry blocks that request earlier, mantle ends at the
				# physically reached position and normal physics owns the result.
				var collision: KinematicCollision3D = player.move_and_collide(
					-active_candidate.wall_normal * forward_distance,
					false,
					PROBE_SAFE_MARGIN,
					false,
					PROBE_MAX_COLLISIONS
				)
				if collision != null:
					completed = true
					break
				if has_reached_forward_limit(player.global_position):
					completed = true
				break

	return true


func is_vertical_clearance_clear(player: CharacterBody3D) -> bool:
	if active_candidate == null:
		return false

	var vertical_distance: float = lift_target_height - player.global_position.y
	if vertical_distance <= get_route_progress_tolerance():
		return true

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


func get_vertical_edge_clearance() -> float:
	if active_candidate == null:
		return INF

	# The capsule stays in a vertical cross-edge plane while the true ledge line
	# may climb along its horizontal direction. For a normalized ledge axis with
	# horizontal factor h, distance from the bottom-cap center to the 3D edge is
	# sqrt(outward^2 + h^2 * vertical^2). At the centerline crossing outward=0,
	# so the required vertical offset is clearance_radius / h.
	var horizontal_factor: float = Vector3(
		active_candidate.ledge_axis.x,
		0.0,
		active_candidate.ledge_axis.z
	).length()
	if horizontal_factor <= sqrt(MOTION_EPSILON_SQUARED):
		return INF
	return get_clearance_radius() / horizontal_factor


func get_crossing_edge_point(position: Vector3) -> Vector3:
	if active_candidate == null:
		return Vector3.ZERO

	# Freeze the player's horizontal along-ledge coordinate. The real 3D ledge
	# axis contributes only the corresponding local edge height.
	var bottom_cap_center: Vector3 = get_bottom_cap_center_position(position)
	var ledge_axis: Vector3 = active_candidate.ledge_axis
	var horizontal_ledge := Vector3(
		ledge_axis.x,
		0.0,
		ledge_axis.z
	)
	var horizontal_factor: float = horizontal_ledge.length()
	if horizontal_factor <= sqrt(MOTION_EPSILON_SQUARED):
		return active_candidate.edge_point

	var horizontal_delta := Vector3(
		bottom_cap_center.x - active_candidate.edge_point.x,
		0.0,
		bottom_cap_center.z - active_candidate.edge_point.z
	)
	var horizontal_along_distance: float = horizontal_delta.dot(
		active_candidate.traversal_axis
	)
	var distance_along_3d_axis: float = (
		horizontal_along_distance / horizontal_factor
	)
	return (
		active_candidate.edge_point
		+ ledge_axis * distance_along_3d_axis
	)


func has_reached_lift_height(position: Vector3) -> bool:
	return (
		position.y
		>= lift_target_height - get_route_progress_tolerance()
	)


func has_reached_forward_limit(position: Vector3) -> bool:
	return (
		get_outward_distance(position)
		<= get_route_progress_tolerance()
	)


func get_outward_distance(position: Vector3) -> float:
	if active_candidate == null:
		return INF
	var bottom_cap_center: Vector3 = get_bottom_cap_center_position(position)
	return (
		(bottom_cap_center - route_edge_point).dot(
			active_candidate.wall_normal
		)
	)


func get_bottom_cap_center_position(position: Vector3) -> Vector3:
	return position + Vector3.UP * get_bottom_cap_center_offset()


func get_route_progress_tolerance() -> float:
	return PROBE_SAFE_MARGIN + ROUTE_CLEARANCE_SLACK


func get_clearance_radius() -> float:
	return (
		detector.get_capsule_radius()
		+ PROBE_SAFE_MARGIN
		+ ROUTE_CLEARANCE_SLACK
	)


func get_bottom_cap_center_offset() -> float:
	return (
		detector.get_capsule_bottom_offset()
		+ detector.get_capsule_radius()
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
