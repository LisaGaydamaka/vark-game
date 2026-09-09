class_name PlayerMantle
extends RefCounted


const PROBE_SAFE_MARGIN: float = 0.001
const ROUTE_CLEARANCE_SLACK: float = 0.002
const PROBE_MAX_COLLISIONS: int = 8
const MOTION_EPSILON_SQUARED: float = 0.000001
const MAX_EDGE_CONTINUATIONS: int = 4
const MINIMUM_CONTINUATION_WALL_ALIGNMENT: float = 0.965925826


enum Phase {
	NONE,
	LIFT,
	FORWARD,
}


class MantleCandidate:
	var source_candidate: PlayerLedgeDetector.LedgeCandidate = null
	var support: PlayerSupport = null
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
var mantle_origin_edge_point: Vector3 = Vector3.ZERO
var mantle_origin_wall_normal: Vector3 = Vector3.ZERO
var edge_continuation_count: int = 0
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
	candidate.support = support
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
	if not _configure_route(player, candidate):
		cancel()
		return false

	# One mantle input owns one immutable crossing envelope. Continuation edges
	# may help clear local geometry, but they never become a new origin from which
	# the mantle can keep walking deeper into the level.
	mantle_origin_edge_point = route_edge_point
	mantle_origin_wall_normal = active_candidate.wall_normal

	# Mantle eligibility is edge-centric. The vertical space directly above the
	# crossing edge must fit the player's current capsule height. Platform depth
	# is not part of this decision.
	if not is_edge_height_clear(player):
		cancel()
		return false

	# Separately verify that the body can actually reach the crossing height from
	# its current position. This is a traversal-path check, not the edge-height
	# eligibility rule above.
	if not is_vertical_clearance_clear(player):
		cancel()
		return false

	phase = Phase.LIFT
	if has_reached_lift_height(player.global_position):
		phase = Phase.FORWARD
		if has_reached_forward_limit(player.global_position):
			completed = true
	return true


func _configure_route(
	player: CharacterBody3D,
	candidate: MantleCandidate
) -> bool:
	if candidate == null or not candidate.valid:
		return false

	active_candidate = candidate
	route_edge_point = get_crossing_edge_point(player.global_position)
	var vertical_edge_clearance: float = get_vertical_edge_clearance()
	if not is_finite(vertical_edge_clearance):
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
	completed = false
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

				# The vertical path was validated for the current edge. A live collision
				# before the required height means that edge can no longer be cleared.
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
				if forward_distance <= 0.0:
					completed = true
					break

				var forward_direction: Vector3 = -active_candidate.wall_normal
				var collision: KinematicCollision3D = player.move_and_collide(
					forward_direction * forward_distance,
					false,
					PROBE_SAFE_MARGIN,
					false,
					PROBE_MAX_COLLISIONS
				)
				if collision != null:
					var actual_forward: float = maxf(
						0.0,
						collision.get_travel().dot(forward_direction)
					)
					remaining_distance = maxf(
						0.0,
						remaining_distance - actual_forward
					)
					if (
						actual_forward
						< forward_distance - get_route_progress_tolerance()
					):
						if _try_continue_over_forward_blocker(player, collision):
							break
						return false
				if has_reached_forward_limit(player.global_position):
					completed = true
				break

	return true


func _try_continue_over_forward_blocker(
	player: CharacterBody3D,
	collision: KinematicCollision3D
) -> bool:
	if (
		active_candidate == null
		or active_candidate.support == null
		or collision == null
		or mantle_origin_wall_normal.length_squared() <= MOTION_EPSILON_SQUARED
		or edge_continuation_count >= MAX_EDGE_CONTINUATIONS
	):
		return false

	var blocker_normal: Vector3 = collision.get_normal()
	var blocker_wall_normal := Vector3(
		blocker_normal.x,
		0.0,
		blocker_normal.z
	)
	if blocker_wall_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return false
	blocker_wall_normal = blocker_wall_normal.normalized()
	if (
		blocker_wall_normal.dot(mantle_origin_wall_normal)
		< MINIMUM_CONTINUATION_WALL_ALIGNMENT
	):
		return false

	# A forward blocker close enough to touch the capsule may itself be another
	# local edge required to clear the original crossing. Search only around the
	# live contact; acceptance below remains anchored to the immutable origin.
	var next_source: PlayerLedgeDetector.LedgeCandidate = (
		detector.find_local_candidate(
			player,
			active_candidate.support,
			blocker_wall_normal,
			collision.get_position(),
			get_clearance_radius(),
			false,
			false
		)
	)
	if next_source == null:
		return false
	if not active_candidate.support.is_walkable_surface(next_source.top_normal):
		return false

	# The next edge must make real progress beyond the current route, but that
	# progress is never allowed to reset the mantle objective. Total inward travel
	# and total rise are always measured from the original edge and are limited to
	# the capsule-sized local crossing envelope.
	var current_wall_normal: Vector3 = active_candidate.wall_normal
	var current_edge_point: Vector3 = route_edge_point
	var current_inward_direction: Vector3 = -current_wall_normal
	var inward_progress: float = (
		next_source.edge_point - current_edge_point
	).dot(current_inward_direction)
	if inward_progress <= get_route_progress_tolerance():
		return false
	if (
		next_source.edge_point.y
		< current_edge_point.y - get_route_progress_tolerance()
	):
		return false

	var origin_inward_direction: Vector3 = -mantle_origin_wall_normal
	var total_inward_progress: float = (
		next_source.edge_point - mantle_origin_edge_point
	).dot(origin_inward_direction)
	var total_rise: float = (
		next_source.edge_point.y - mantle_origin_edge_point.y
	)
	var local_envelope: float = get_clearance_radius()
	var envelope_tolerance: float = get_route_progress_tolerance()
	if total_inward_progress <= envelope_tolerance:
		return false
	if total_inward_progress > local_envelope + envelope_tolerance:
		return false
	if total_rise > local_envelope + envelope_tolerance:
		return false

	var next_candidate: MantleCandidate = find_candidate_with_source_mode(
		player,
		active_candidate.support,
		next_source,
		false
	)
	if next_candidate == null:
		return false
	if (
		next_candidate.wall_normal.dot(mantle_origin_wall_normal)
		< MINIMUM_CONTINUATION_WALL_ALIGNMENT
	):
		return false
	if not _configure_route(player, next_candidate):
		return false
	if not is_edge_height_clear(player):
		return false
	if not is_vertical_clearance_clear(player):
		return false

	edge_continuation_count += 1
	phase = Phase.LIFT
	if has_reached_lift_height(player.global_position):
		phase = Phase.FORWARD
	return true


func is_edge_height_clear(player: CharacterBody3D) -> bool:
	if active_candidate == null:
		return false

	var required_height: float = detector.get_capsule_height()
	if required_height <= 0.0:
		return false

	# Probe a hair inward so an edge shared by the wall and top surface is sampled
	# on the platform side rather than in empty space outside the wall. The height
	# itself is still measured vertically from the reconstructed crossing edge.
	var probe_origin: Vector3 = (
		route_edge_point
		- active_candidate.wall_normal * PROBE_SAFE_MARGIN
		+ Vector3.UP * PROBE_SAFE_MARGIN
	)
	var probe_target := Vector3(
		probe_origin.x,
		route_edge_point.y + required_height + get_route_progress_tolerance(),
		probe_origin.z
	)
	var query := PhysicsRayQueryParameters3D.create(
		probe_origin,
		probe_target,
		player.collision_mask,
		[player.get_rid()]
	)
	query.collide_with_areas = false

	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true

	var position_value: Variant = hit.get("position")
	if not (position_value is Vector3):
		return false
	var ceiling_point: Vector3 = position_value
	var available_height: float = ceiling_point.y - route_edge_point.y
	return (
		available_height
		>= required_height - get_route_progress_tolerance()
	)


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
	if active_candidate == null or active_candidate.source_candidate == null:
		return INF

	# At the wall/edge plane the bottom cap center must remain one clearance
	# radius away from the sampled top plane. A purely vertical offset contributes
	# top_normal.y * vertical_clearance to that plane distance, so an uphill top
	# requires more lift than a flat top. This also subsumes the previous
	# ledge-line-tilt correction while correctly handling slope across the ledge.
	var top_normal: Vector3 = active_candidate.source_candidate.top_normal
	if top_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return INF
	top_normal = top_normal.normalized()
	var vertical_factor: float = top_normal.dot(Vector3.UP)
	if vertical_factor <= sqrt(MOTION_EPSILON_SQUARED):
		return INF
	return get_clearance_radius() / vertical_factor


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
	return get_outward_distance(position) <= 0.0


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
	mantle_origin_edge_point = Vector3.ZERO
	mantle_origin_wall_normal = Vector3.ZERO
	edge_continuation_count = 0
	phase = Phase.NONE
	completed = false