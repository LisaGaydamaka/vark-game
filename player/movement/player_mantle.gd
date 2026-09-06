class_name PlayerMantle
extends RefCounted


const PROBE_SAFE_MARGIN: float = 0.001
const PROBE_MAX_COLLISIONS: int = 8
const MOTION_EPSILON_SQUARED: float = 0.000001
const ANGLE_EPSILON: float = 0.00001
const MAX_ROUTE_SEGMENT_ANGLE_DEGREES: float = 5.0


class MantleCandidate:
	var source_candidate: PlayerLedgeDetector.LedgeCandidate = null
	var target_top: PlayerLedgeDetector.TopHit = null
	var edge_point: Vector3 = Vector3.ZERO
	var wall_normal: Vector3 = Vector3.ZERO
	var ledge_axis: Vector3 = Vector3.ZERO
	var top_path_normal: Vector3 = Vector3.UP
	var source_arc_position: Vector3 = Vector3.ZERO
	var target_arc_position: Vector3 = Vector3.ZERO
	var target_position: Vector3 = Vector3.ZERO
	var signed_arc_angle: float = 0.0
	var valid: bool = false


var traversal_speed: float
var detector: PlayerLedgeDetector

var active_candidate: MantleCandidate = null
var start_position: Vector3 = Vector3.ZERO
var source_lead_length: float = 0.0
var arc_length: float = 0.0
var target_lead_length: float = 0.0
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
	refresh_source_as_hang: bool
) -> MantleCandidate:
	if source_candidate == null:
		return null

	var refreshed_source: PlayerLedgeDetector.LedgeCandidate = (
		source_candidate
	)

	if refresh_source_as_hang:
		refreshed_source = (
			detector.find_hang_candidate_at_position(
				player,
				support,
				source_candidate,
				source_candidate.wall_normal,
				player.global_position
			)
		)

		if refreshed_source == null:
			return null

	var wall_normal: Vector3 = refreshed_source.wall_normal
	wall_normal.y = 0.0

	if (
		wall_normal.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return null

	wall_normal = wall_normal.normalized()

	var ledge_axis: Vector3 = (
		Vector3.UP.cross(wall_normal)
	)

	if (
		ledge_axis.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return null

	ledge_axis = ledge_axis.normalized()

	var clearance_radius: float = get_clearance_radius()
	var maximum_slope_radians: float = deg_to_rad(
		clampf(
			support.max_walkable_slope,
			0.0,
			89.0
		)
	)
	var target_surface_inset: float = (
		clearance_radius
		* (
			1.0
			+ sin(maximum_slope_radians)
		)
	)
	var target_probe_point: Vector3 = (
		refreshed_source.edge_point
		- wall_normal * target_surface_inset
	)
	var maximum_height_change: float = (
		target_surface_inset
		* tan(maximum_slope_radians)
		+ clearance_radius
	)
	var ray_from: Vector3 = target_probe_point
	ray_from.y = (
		refreshed_source.edge_point.y
		+ maximum_height_change
	)
	var ray_to: Vector3 = target_probe_point
	ray_to.y = (
		refreshed_source.edge_point.y
		- maximum_height_change
	)

	var target_top: PlayerLedgeDetector.TopHit = (
		detector.raycast_top(
			player,
			support,
			ray_from,
			ray_to
		)
	)

	if target_top == null:
		return null

	var target_normal: Vector3 = target_top.normal

	if (
		target_normal.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return null

	target_normal = target_normal.normalized()

	var allowed_height_change: float = (
		target_surface_inset
		* tan(maximum_slope_radians)
		+ PROBE_SAFE_MARGIN
	)

	if (
		absf(
			target_top.point.y
			- refreshed_source.edge_point.y
		)
		> allowed_height_change
	):
		return null

	var top_path_normal: Vector3 = (
		target_normal.slide(ledge_axis)
	)

	if (
		top_path_normal.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return null

	top_path_normal = top_path_normal.normalized()

	if top_path_normal.dot(Vector3.UP) <= 0.0:
		return null

	var normal_dot: float = clampf(
		wall_normal.dot(top_path_normal),
		-1.0,
		1.0
	)
	var cross_axis: float = (
		wall_normal.cross(top_path_normal).dot(
			ledge_axis
		)
	)
	var signed_arc_angle: float = atan2(
		cross_axis,
		normal_dot
	)
	var absolute_arc_angle: float = absf(
		signed_arc_angle
	)
	var minimum_arc_angle: float = (
		PI * 0.5 - maximum_slope_radians
	)
	var maximum_arc_angle: float = (
		PI * 0.5 + maximum_slope_radians
	)

	if (
		absolute_arc_angle
		< minimum_arc_angle
		or absolute_arc_angle
		> maximum_arc_angle
	):
		return null

	var top_inward_direction: Vector3 = (
		(-wall_normal).slide(target_normal)
	)

	if (
		top_inward_direction.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return null

	top_inward_direction = top_inward_direction.normalized()

	var edge_plane_offset: float = (
		(
			refreshed_source.edge_point
			- target_top.point
		).dot(target_normal)
	)
	var landing_surface_point: Vector3 = (
		refreshed_source.edge_point
		- target_normal * edge_plane_offset
		+ top_inward_direction * PROBE_SAFE_MARGIN
	)
	var bottom_cap_center_offset: float = (
		get_bottom_cap_center_offset()
	)
	var source_arc_position: Vector3 = (
		refreshed_source.edge_point
		+ wall_normal * clearance_radius
		- Vector3.UP * bottom_cap_center_offset
	)
	var target_arc_position: Vector3 = (
		refreshed_source.edge_point
		+ top_path_normal * clearance_radius
		- Vector3.UP * bottom_cap_center_offset
	)
	var target_position: Vector3 = (
		landing_surface_point
		+ target_normal * clearance_radius
		- Vector3.UP * bottom_cap_center_offset
	)

	var candidate: MantleCandidate = MantleCandidate.new()
	candidate.source_candidate = refreshed_source
	candidate.target_top = target_top
	candidate.edge_point = refreshed_source.edge_point
	candidate.wall_normal = wall_normal
	candidate.ledge_axis = ledge_axis
	candidate.top_path_normal = top_path_normal
	candidate.source_arc_position = source_arc_position
	candidate.target_arc_position = target_arc_position
	candidate.target_position = target_position
	candidate.signed_arc_angle = signed_arc_angle
	candidate.valid = is_pose_valid(
		player,
		candidate,
		target_position
	)

	if not candidate.valid:
		return null

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
	target_lead_length = (
		candidate.target_arc_position.distance_to(
			candidate.target_position
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

	if not is_route_clear(player):
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
		var target_position: Vector3 = get_route_position(
			next_route_distance
		)
		var motion: Vector3 = (
			target_position
			- player.global_position
		)

		if not move_mantle_motion(
			player,
			motion
		):
			return false

		if not has_reached_position(
			player.global_position,
			target_position
		):
			return false

		route_distance = next_route_distance
		remaining_distance -= segment_distance

	if (
		total_route_length - route_distance
		<= 0.000001
	):
		route_distance = total_route_length
		completed = true

	return true


func is_route_clear(
	player: CharacterBody3D
) -> bool:
	if active_candidate == null:
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
		var target_position: Vector3 = get_route_position(
			next_distance
		)
		var motion: Vector3 = (
			target_position
			- simulated_transform.origin
		)
		var result: Dictionary = simulate_mantle_motion(
			player,
			simulated_transform,
			motion
		)

		if result.is_empty():
			return false

		var transform_value: Variant = result.get(
			"transform"
		)

		if not (transform_value is Transform3D):
			return false

		simulated_transform = transform_value

		if not has_reached_position(
			simulated_transform.origin,
			target_position
		):
			return false

		simulated_distance = next_distance

	return true


func simulate_mantle_motion(
	player: CharacterBody3D,
	from_transform: Transform3D,
	motion: Vector3
) -> Dictionary:
	var simulated_transform: Transform3D = from_transform
	var remaining_motion: Vector3 = motion

	for _iteration: int in range(
		PROBE_MAX_COLLISIONS
	):
		if (
			remaining_motion.length_squared()
			<= MOTION_EPSILON_SQUARED
		):
			return {
				"transform": simulated_transform
			}

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
			return {
				"transform": simulated_transform
			}

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
			if not is_expected_mantle_contact(
				collision,
				collision_index,
				active_candidate
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

	return {}


func move_mantle_motion(
	player: CharacterBody3D,
	motion: Vector3
) -> bool:
	var remaining_motion: Vector3 = motion

	for _iteration: int in range(
		PROBE_MAX_COLLISIONS
	):
		if (
			remaining_motion.length_squared()
			<= MOTION_EPSILON_SQUARED
		):
			return true

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
			return true

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
			if not is_expected_mantle_contact(
				collision,
				collision_index,
				active_candidate
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

	return false


func is_pose_valid(
	player: CharacterBody3D,
	candidate: MantleCandidate,
	position: Vector3
) -> bool:
	var pose_transform: Transform3D = player.global_transform
	pose_transform.origin = position

	var collision: KinematicCollision3D = (
		KinematicCollision3D.new()
	)
	var has_contact: bool = player.test_move(
		pose_transform,
		Vector3.ZERO,
		collision,
		PROBE_SAFE_MARGIN,
		true,
		PROBE_MAX_COLLISIONS
	)

	if not has_contact:
		return true

	var collision_count: int = (
		collision.get_collision_count()
	)

	if collision_count <= 0:
		return false

	for collision_index: int in range(
		collision_count
	):
		if not is_expected_mantle_contact(
			collision,
			collision_index,
			candidate
		):
			return false

	return true


func is_expected_mantle_contact(
	collision: KinematicCollision3D,
	collision_index: int,
	candidate: MantleCandidate
) -> bool:
	if candidate == null:
		return false

	if not matches_mantle_geometry(
		collision,
		collision_index,
		candidate
	):
		return false

	var collision_normal: Vector3 = collision.get_normal(
		collision_index
	)
	var planar_normal: Vector3 = collision_normal.slide(
		candidate.ledge_axis
	)

	if (
		planar_normal.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return false

	planar_normal = planar_normal.normalized()

	var total_angle: float = candidate.signed_arc_angle
	var contact_dot: float = clampf(
		candidate.wall_normal.dot(planar_normal),
		-1.0,
		1.0
	)
	var contact_cross: float = (
		candidate.wall_normal.cross(planar_normal).dot(
			candidate.ledge_axis
		)
	)
	var contact_angle: float = atan2(
		contact_cross,
		contact_dot
	)

	if absf(contact_angle) > absf(total_angle) + ANGLE_EPSILON:
		return false

	if (
		absf(contact_angle) > ANGLE_EPSILON
		and signf(contact_angle) != signf(total_angle)
	):
		return false

	return true


func matches_mantle_geometry(
	collision: KinematicCollision3D,
	collision_index: int,
	candidate: MantleCandidate
) -> bool:
	return (
		matches_candidate_wall(
			collision,
			collision_index,
			candidate.source_candidate
		)
		or matches_candidate_top(
			collision,
			collision_index,
			candidate.source_candidate
		)
		or matches_top_hit(
			collision,
			collision_index,
			candidate.target_top
		)
	)


func matches_candidate_wall(
	collision: KinematicCollision3D,
	collision_index: int,
	candidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	if candidate == null:
		return false

	return matches_geometry_identity(
		collision,
		collision_index,
		candidate.wall_collider_rid,
		candidate.wall_shape_index
	)


func matches_candidate_top(
	collision: KinematicCollision3D,
	collision_index: int,
	candidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	if candidate == null:
		return false

	return matches_geometry_identity(
		collision,
		collision_index,
		candidate.top_collider_rid,
		candidate.top_shape_index
	)


func matches_top_hit(
	collision: KinematicCollision3D,
	collision_index: int,
	top_hit: PlayerLedgeDetector.TopHit
) -> bool:
	if top_hit == null:
		return false

	return matches_geometry_identity(
		collision,
		collision_index,
		top_hit.collider_rid,
		top_hit.shape_index
	)


func matches_geometry_identity(
	collision: KinematicCollision3D,
	collision_index: int,
	collider_rid: RID,
	shape_index: int
) -> bool:
	if (
		collision.get_collider_rid(
			collision_index
		)
		!= collider_rid
	):
		return false

	var collider_shape_index: int = (
		collision.get_collider_shape_index(
			collision_index
		)
	)

	if (
		shape_index >= 0
		and collider_shape_index >= 0
		and collider_shape_index != shape_index
	):
		return false

	return true


func get_route_position(
	distance_along_route: float
) -> Vector3:
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
		var source_fraction: float = (
			clamped_distance
			/ source_lead_length
		)
		return start_position.lerp(
			active_candidate.source_arc_position,
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
			active_candidate.signed_arc_angle
			* arc_fraction
		)
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

	if target_lead_length <= 0.000001:
		return active_candidate.target_position

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
	return active_candidate.target_arc_position.lerp(
		active_candidate.target_position,
		target_fraction
	)


func has_reached_position(
	position: Vector3,
	target_position: Vector3
) -> bool:
	var arrival_tolerance: float = (
		PROBE_SAFE_MARGIN
		+ sqrt(MOTION_EPSILON_SQUARED)
	)
	return (
		position.distance_squared_to(target_position)
		<= arrival_tolerance * arrival_tolerance
	)


func get_clearance_radius() -> float:
	return (
		detector.get_capsule_radius()
		+ PROBE_SAFE_MARGIN
	)


func get_bottom_cap_center_offset() -> float:
	return (
		detector.get_capsule_bottom_offset()
		+ detector.get_capsule_radius()
	)


func get_maximum_segment_distance() -> float:
	return maxf(
		PROBE_SAFE_MARGIN,
		get_clearance_radius()
		* deg_to_rad(
			MAX_ROUTE_SEGMENT_ANGLE_DEGREES
		)
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
	target_lead_length = 0.0
	total_route_length = 0.0
	route_distance = 0.0
	completed = false
