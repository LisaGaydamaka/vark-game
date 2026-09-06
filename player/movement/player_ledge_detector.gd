class_name PlayerLedgeDetector
extends RefCounted


const PROBE_SAFE_MARGIN: float = 0.001
const PROBE_MAX_COLLISIONS: int = 8
const MOTION_EPSILON_SQUARED: float = 0.000001

const FORWARD_REACH_RADIUS_MULTIPLIER: float = 2.0
const HAND_REACH_HEIGHT_RATIO: float = 0.25
const HANG_EDGE_ABOVE_EYE_RADIUS_RATIO: float = 0.25
const TOP_PROBE_INSET_RADIUS_RATIO: float = 0.32
const MAX_CATCH_FALL_SPEED_JUMP_SPEED_MULTIPLIER: float = 2.0
const SHIMMY_MAX_WALL_TURN_DEGREES: float = 15.0
const SHIMMY_LEVEL_HEIGHT_RADIUS_RATIO: float = 0.05
const SHIMMY_ATTACHMENT_CORRECTION_RADIUS_RATIO: float = 0.1
const LEDGE_SPAN_HALF_WIDTH_RADIUS_RATIO: float = 0.75
const SUPPRESSION_VERTICAL_MARGIN_RADIUS_RATIO: float = 1.0
const EXPECTED_HANG_WALL_MIN_ALIGNMENT: float = 0.9


class LedgeCandidate:
	var wall_collider_rid: RID = RID()
	var wall_shape_index: int = -1
	var top_collider_rid: RID = RID()
	var top_shape_index: int = -1

	var edge_point: Vector3 = Vector3.ZERO
	var wall_normal: Vector3 = Vector3.ZERO
	var top_point: Vector3 = Vector3.ZERO
	var top_normal: Vector3 = Vector3.UP
	var ledge_direction: Vector3 = Vector3.ZERO
	var hang_position: Vector3 = Vector3.ZERO
	var hangable: bool = false


class WallHit:
	var point: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.ZERO
	var collider_rid: RID = RID()
	var shape_index: int = -1


class TopHit:
	var point: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.UP
	var collider_rid: RID = RID()
	var shape_index: int = -1


var jump_height: float
var gravity: float
var max_step_height: float
var eye_height: float
var max_wall_tilt_degrees: float
var max_approach_angle_degrees: float
var debug_logging: bool
var collision_shape: CollisionShape3D

var capsule_shape: CapsuleShape3D
var capsule_radius: float
var capsule_height: float
var capsule_bottom_offset: float
var capsule_top_offset: float
var forward_probe_distance: float
var max_horizontal_reach: float
var min_edge_height: float
var max_catch_height: float
var hand_reach_height: float
var hang_anchor_height: float
var hang_wall_distance: float
var top_probe_inset: float
var shimmy_level_tolerance: float
var shimmy_attachment_correction_limit: float
var ledge_span_half_width: float
var max_catch_fall_speed: float
var minimum_approach_alignment: float
var maximum_wall_normal_y: float
var minimum_shimmy_wall_alignment: float
var suppression_vertical_margin: float

var ray_query: PhysicsRayQueryParameters3D = null
var ray_query_player_rid: RID = RID()

var current_candidate: LedgeCandidate = null
var suppressed_candidate: LedgeCandidate = null


func _init(
	p_jump_height: float,
	p_gravity: float,
	p_max_step_height: float,
	p_eye_height: float,
	p_max_wall_tilt_degrees: float,
	p_max_approach_angle_degrees: float,
	p_debug_logging: bool,
	p_collision_shape: CollisionShape3D
) -> void:
	jump_height = p_jump_height
	gravity = p_gravity
	max_step_height = p_max_step_height
	eye_height = p_eye_height
	max_wall_tilt_degrees = p_max_wall_tilt_degrees
	max_approach_angle_degrees = p_max_approach_angle_degrees
	debug_logging = p_debug_logging
	collision_shape = p_collision_shape

	assert(
		jump_height >= 0.0,
		"PlayerLedgeDetector requires jump_height to be non-negative."
	)
	assert(
		gravity > 0.0,
		"PlayerLedgeDetector requires gravity to be greater than zero."
	)
	assert(
		max_step_height >= 0.0,
		"PlayerLedgeDetector requires max_step_height to be non-negative."
	)
	assert(
		eye_height >= 0.0,
		"PlayerLedgeDetector requires eye_height to be non-negative."
	)
	assert(
		max_wall_tilt_degrees >= 0.0,
		"PlayerLedgeDetector requires max_wall_tilt_degrees to be non-negative."
	)
	assert(
		max_approach_angle_degrees >= 0.0,
		"PlayerLedgeDetector requires max_approach_angle_degrees to be non-negative."
	)

	var shape: Shape3D = collision_shape.shape
	assert(
		shape is CapsuleShape3D,
		"PlayerLedgeDetector requires the player collision shape to be CapsuleShape3D."
	)
	capsule_shape = shape as CapsuleShape3D

	_cache_static_values()


func _cache_static_values() -> void:
	capsule_radius = capsule_shape.radius
	capsule_height = capsule_shape.height
	capsule_bottom_offset = (
		collision_shape.position.y
		- capsule_height * 0.5
	)
	capsule_top_offset = (
		collision_shape.position.y
		+ capsule_height * 0.5
	)

	forward_probe_distance = (
		capsule_radius
		* FORWARD_REACH_RADIUS_MULTIPLIER
	)
	max_horizontal_reach = (
		capsule_radius
		+ forward_probe_distance
	)
	hand_reach_height = (
		capsule_height
		* HAND_REACH_HEIGHT_RATIO
	)
	min_edge_height = (
		capsule_bottom_offset
		+ max_step_height
	)
	max_catch_height = (
		capsule_top_offset
		+ hand_reach_height
	)
	hang_anchor_height = (
		eye_height
		+ capsule_radius
		* HANG_EDGE_ABOVE_EYE_RADIUS_RATIO
	)
	hang_wall_distance = capsule_radius + PROBE_SAFE_MARGIN
	top_probe_inset = (
		capsule_radius
		* TOP_PROBE_INSET_RADIUS_RATIO
	)
	shimmy_level_tolerance = maxf(
		PROBE_SAFE_MARGIN,
		capsule_radius
		* SHIMMY_LEVEL_HEIGHT_RADIUS_RATIO
	)
	shimmy_attachment_correction_limit = maxf(
		PROBE_SAFE_MARGIN,
		capsule_radius
		* SHIMMY_ATTACHMENT_CORRECTION_RADIUS_RATIO
	)
	ledge_span_half_width = (
		capsule_radius
		* LEDGE_SPAN_HALF_WIDTH_RADIUS_RATIO
	)
	suppression_vertical_margin = (
		capsule_radius
		* SUPPRESSION_VERTICAL_MARGIN_RADIUS_RATIO
	)

	var jump_speed: float = sqrt(
		2.0
		* gravity
		* maxf(jump_height, 0.0)
	)
	max_catch_fall_speed = (
		jump_speed
		* MAX_CATCH_FALL_SPEED_JUMP_SPEED_MULTIPLIER
	)

	minimum_approach_alignment = cos(
		deg_to_rad(max_approach_angle_degrees)
	)
	maximum_wall_normal_y = sin(
		deg_to_rad(max_wall_tilt_degrees)
	)
	minimum_shimmy_wall_alignment = cos(
		deg_to_rad(SHIMMY_MAX_WALL_TURN_DEGREES)
	)


func update(
	player: CharacterBody3D,
	support: PlayerSupport,
	detection_allowed: bool,
	intent_direction: Vector3,
	view_forward: Vector3
) -> void:
	var previously_had_candidate: bool = (
		current_candidate != null
	)
	var next_candidate: LedgeCandidate = null

	update_suppression(player)

	if (
		detection_allowed
		and player.velocity.y >= -get_max_catch_fall_speed()
	):
		next_candidate = find_candidate(
			player,
			support,
			intent_direction,
			view_forward
		)

	current_candidate = next_candidate
	update_debug_logging(previously_had_candidate)


func has_candidate() -> bool:
	return current_candidate != null


func get_candidate() -> LedgeCandidate:
	return current_candidate


func clear_candidate() -> void:
	current_candidate = null


func suppress_candidate(
	candidate: LedgeCandidate
) -> void:
	suppressed_candidate = candidate
	current_candidate = null


func update_suppression(
	player: CharacterBody3D
) -> void:
	if suppressed_candidate == null:
		return

	var horizontal_velocity: Vector3 = Vector3(
		player.velocity.x,
		0.0,
		player.velocity.z
	)
	var toward_wall: Vector3 = -suppressed_candidate.wall_normal
	var approach_speed: float = horizontal_velocity.dot(
		toward_wall
	)

	if approach_speed <= 0.0:
		suppressed_candidate = null
		return

	var edge_offset: Vector3 = (
		suppressed_candidate.edge_point
		- player.global_position
	)
	var horizontal_edge_offset: Vector3 = Vector3(
		edge_offset.x,
		0.0,
		edge_offset.z
	)
	var horizontal_limit: float = (
		get_max_horizontal_reach()
		+ get_capsule_radius()
	)

	if (
		horizontal_edge_offset.length_squared()
		> horizontal_limit * horizontal_limit
	):
		suppressed_candidate = null
		return

	if (
		edge_offset.y
		< get_min_edge_height() - suppression_vertical_margin
		or edge_offset.y
		> get_max_catch_height() + suppression_vertical_margin
	):
		suppressed_candidate = null


func find_candidate(
	player: CharacterBody3D,
	support: PlayerSupport,
	intent_direction: Vector3,
	view_forward: Vector3
) -> LedgeCandidate:
	var horizontal_intent: Vector3 = Vector3(
		intent_direction.x,
		0.0,
		intent_direction.z
	)
	var approach_direction: Vector3 = Vector3.ZERO

	if (
		horizontal_intent.length_squared()
		> MOTION_EPSILON_SQUARED
	):
		approach_direction = horizontal_intent.normalized()
	else:
		var horizontal_velocity: Vector3 = Vector3(
			player.velocity.x,
			0.0,
			player.velocity.z
		)

		if (
			horizontal_velocity.length_squared()
			<= MOTION_EPSILON_SQUARED
		):
			return null

		approach_direction = horizontal_velocity.normalized()

	var wall_hit: WallHit = find_wall(
		player,
		approach_direction
	)

	if wall_hit == null:
		return null

	if is_suppressed_wall(wall_hit):
		return null

	if not has_catch_intent(
		wall_hit.normal,
		intent_direction,
		view_forward
	):
		return null

	var top_hit: TopHit = find_top(
		player,
		support,
		wall_hit
	)

	if top_hit == null:
		return null

	var edge_point: Vector3 = Vector3(
		wall_hit.point.x,
		top_hit.point.y,
		wall_hit.point.z
	)
	var near_edge_wall: WallHit = find_wall_near_edge(
		player,
		wall_hit.normal,
		edge_point
	)

	if (
		near_edge_wall == null
		or not is_wall_continuous(
			near_edge_wall,
			wall_hit.normal,
			edge_point
		)
	):
		return null

	edge_point = Vector3(
		near_edge_wall.point.x,
		top_hit.point.y,
		near_edge_wall.point.z
	)

	var edge_offset: Vector3 = (
		edge_point - player.global_position
	)
	var horizontal_edge_offset: Vector3 = Vector3(
		edge_offset.x,
		0.0,
		edge_offset.z
	)
	var horizontal_reach_limit: float = (
		get_max_horizontal_reach()
		+ PROBE_SAFE_MARGIN
	)

	if (
		horizontal_edge_offset.length_squared()
		> horizontal_reach_limit * horizontal_reach_limit
	):
		return null

	var relative_height: float = (
		top_hit.point.y
		- player.global_position.y
	)

	if (
		relative_height
		< get_min_edge_height() - PROBE_SAFE_MARGIN
	):
		return null

	if (
		relative_height
		> get_max_catch_height() + PROBE_SAFE_MARGIN
	):
		return null

	var ledge_direction: Vector3 = (
		Vector3.UP.cross(near_edge_wall.normal)
	)

	if (
		ledge_direction.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return null

	ledge_direction = ledge_direction.normalized()

	var hang_span_valid: bool = has_usable_ledge_span(
		player,
		support,
		edge_point,
		near_edge_wall.normal,
		top_hit.point.y,
		ledge_direction
	)

	var hang_position: Vector3 = get_hang_position(
		edge_point,
		near_edge_wall.normal
	)

	var candidate: LedgeCandidate = LedgeCandidate.new()
	candidate.wall_collider_rid = near_edge_wall.collider_rid
	candidate.wall_shape_index = near_edge_wall.shape_index
	candidate.top_collider_rid = top_hit.collider_rid
	candidate.top_shape_index = top_hit.shape_index
	candidate.edge_point = edge_point
	candidate.wall_normal = near_edge_wall.normal
	candidate.top_point = top_hit.point
	candidate.top_normal = top_hit.normal
	candidate.ledge_direction = ledge_direction
	candidate.hang_position = hang_position

	if hang_span_valid:
		candidate.hangable = is_hang_pose_valid(
			player,
			candidate,
			hang_position
		)

	return candidate


func find_hang_candidate_at_position(
	player: CharacterBody3D,
	support: PlayerSupport,
	reference_candidate: LedgeCandidate,
	segment_wall_normal: Vector3,
	proposed_hang_position: Vector3
) -> LedgeCandidate:
	if reference_candidate == null:
		return null

	var fixed_wall_normal: Vector3 = segment_wall_normal

	if (
		fixed_wall_normal.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return null

	fixed_wall_normal = fixed_wall_normal.normalized()

	var expected_edge_point: Vector3 = (
		proposed_hang_position
		- fixed_wall_normal
		* get_hang_wall_distance()
	)
	expected_edge_point.y = (
		proposed_hang_position.y
		+ get_hang_anchor_height()
	)

	var wall_hit: WallHit = find_wall_near_edge(
		player,
		fixed_wall_normal,
		expected_edge_point
	)

	if (
		wall_hit == null
		or not is_wall_continuous(
			wall_hit,
			fixed_wall_normal,
			expected_edge_point
		)
	):
		return null

	var top_hit: TopHit = find_top_for_hang(
		player,
		support,
		wall_hit,
		expected_edge_point.y
	)

	if top_hit == null:
		return null

	var edge_point: Vector3 = Vector3(
		wall_hit.point.x,
		top_hit.point.y,
		wall_hit.point.z
	)
	var hang_position: Vector3 = get_hang_position(
		edge_point,
		wall_hit.normal
	)

	if (
		absf(
			hang_position.y
			- proposed_hang_position.y
		)
		> get_shimmy_level_tolerance()
	):
		return null

	var horizontal_correction: Vector3 = Vector3(
		hang_position.x - proposed_hang_position.x,
		0.0,
		hang_position.z - proposed_hang_position.z
	)
	var correction_limit: float = (
		get_shimmy_attachment_correction_limit()
	)

	if (
		horizontal_correction.length_squared()
		> correction_limit * correction_limit
	):
		return null

	var ledge_direction: Vector3 = (
		Vector3.UP.cross(wall_hit.normal)
	)

	if (
		ledge_direction.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return null

	ledge_direction = ledge_direction.normalized()
	var reference_ledge_direction: Vector3 = (
		Vector3.UP.cross(fixed_wall_normal).normalized()
	)

	if not has_usable_ledge_span(
		player,
		support,
		edge_point,
		fixed_wall_normal,
		top_hit.point.y,
		reference_ledge_direction
	):
		return null

	var candidate: LedgeCandidate = LedgeCandidate.new()
	candidate.wall_collider_rid = wall_hit.collider_rid
	candidate.wall_shape_index = wall_hit.shape_index
	candidate.top_collider_rid = top_hit.collider_rid
	candidate.top_shape_index = top_hit.shape_index
	candidate.edge_point = edge_point
	candidate.wall_normal = wall_hit.normal
	candidate.top_point = top_hit.point
	candidate.top_normal = top_hit.normal
	candidate.ledge_direction = ledge_direction
	candidate.hang_position = hang_position
	candidate.hangable = is_hang_pose_valid(
		player,
		candidate,
		hang_position
	)

	if not candidate.hangable:
		return null

	return candidate


func find_wall(
	player: CharacterBody3D,
	approach_direction: Vector3
) -> WallHit:
	var collision: KinematicCollision3D = KinematicCollision3D.new()
	var blocked: bool = player.test_move(
		player.global_transform,
		approach_direction * get_forward_probe_distance(),
		collision,
		PROBE_SAFE_MARGIN,
		false,
		PROBE_MAX_COLLISIONS
	)

	if not blocked:
		return null

	var best_push_strength: float = minimum_approach_alignment
	var best_collision_index: int = -1
	var collision_count: int = collision.get_collision_count()

	for collision_index: int in range(collision_count):
		var collision_normal: Vector3 = collision.get_normal(
			collision_index
		)

		if not is_wall_surface(collision_normal):
			continue

		var horizontal_normal: Vector3 = Vector3(
			collision_normal.x,
			0.0,
			collision_normal.z
		)

		if (
			horizontal_normal.length_squared()
			<= MOTION_EPSILON_SQUARED
		):
			continue

		horizontal_normal = horizontal_normal.normalized()

		var push_strength: float = -approach_direction.dot(
			horizontal_normal
		)

		if push_strength < best_push_strength:
			continue

		best_push_strength = push_strength
		best_collision_index = collision_index

	if best_collision_index < 0:
		return null

	var best_normal: Vector3 = collision.get_normal(
		best_collision_index
	)
	best_normal.y = 0.0
	best_normal = best_normal.normalized()

	var best_hit: WallHit = WallHit.new()
	best_hit.point = collision.get_position(
		best_collision_index
	)
	best_hit.normal = best_normal
	best_hit.collider_rid = collision.get_collider_rid(
		best_collision_index
	)
	best_hit.shape_index = collision.get_collider_shape_index(
		best_collision_index
	)
	return best_hit


func find_wall_near_edge(
	player: CharacterBody3D,
	expected_wall_normal: Vector3,
	expected_edge_point: Vector3
) -> WallHit:
	var ray_from: Vector3 = (
		expected_edge_point
		+ expected_wall_normal
		* (
			get_hang_wall_distance()
			+ get_top_probe_inset()
		)
	)
	ray_from.y = (
		expected_edge_point.y
		- get_capsule_radius() * 0.5
	)

	var ray_to: Vector3 = (
		expected_edge_point
		- expected_wall_normal
		* get_top_probe_inset()
	)
	ray_to.y = ray_from.y

	var query: PhysicsRayQueryParameters3D = _prepare_ray_query(
		player,
		ray_from,
		ray_to
	)
	var space_state: PhysicsDirectSpaceState3D = (
		player.get_world_3d().direct_space_state
	)
	var hit: Dictionary = space_state.intersect_ray(query)

	if hit.is_empty():
		return null

	var position_value: Variant = hit.get("position")
	var normal_value: Variant = hit.get("normal")
	var rid_value: Variant = hit.get("rid")
	var shape_value: Variant = hit.get("shape")

	if not (position_value is Vector3):
		return null

	if not (normal_value is Vector3):
		return null

	var collision_normal: Vector3 = normal_value

	if not is_wall_surface(collision_normal):
		return null

	var horizontal_normal: Vector3 = Vector3(
		collision_normal.x,
		0.0,
		collision_normal.z
	)

	if (
		horizontal_normal.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return null

	horizontal_normal = horizontal_normal.normalized()

	var wall_hit: WallHit = WallHit.new()
	wall_hit.point = position_value
	wall_hit.normal = horizontal_normal

	if rid_value is RID:
		wall_hit.collider_rid = rid_value

	if shape_value is int:
		wall_hit.shape_index = shape_value

	return wall_hit


func find_top(
	player: CharacterBody3D,
	support: PlayerSupport,
	wall_hit: WallHit
) -> TopHit:
	var ray_from: Vector3 = (
		wall_hit.point
		- wall_hit.normal * get_top_probe_inset()
	)
	ray_from.y = (
		player.global_position.y
		+ get_max_catch_height()
		+ PROBE_SAFE_MARGIN
	)

	var ray_to: Vector3 = ray_from
	ray_to.y = (
		player.global_position.y
		+ get_min_edge_height()
		- PROBE_SAFE_MARGIN
	)

	return raycast_top(
		player,
		support,
		ray_from,
		ray_to
	)


func find_top_for_hang(
	player: CharacterBody3D,
	support: PlayerSupport,
	wall_hit: WallHit,
	expected_edge_height: float
) -> TopHit:
	var probe_center: Vector3 = (
		wall_hit.point
		- wall_hit.normal * get_top_probe_inset()
	)
	probe_center.y = expected_edge_height

	var ray_from: Vector3 = (
		probe_center
		+ Vector3.UP * get_capsule_radius()
	)
	var ray_to: Vector3 = (
		probe_center
		- Vector3.UP * get_capsule_radius()
	)

	return raycast_top(
		player,
		support,
		ray_from,
		ray_to
	)


func raycast_top(
	player: CharacterBody3D,
	support: PlayerSupport,
	ray_from: Vector3,
	ray_to: Vector3
) -> TopHit:
	var query: PhysicsRayQueryParameters3D = _prepare_ray_query(
		player,
		ray_from,
		ray_to
	)
	var space_state: PhysicsDirectSpaceState3D = (
		player.get_world_3d().direct_space_state
	)
	var hit: Dictionary = space_state.intersect_ray(query)

	if hit.is_empty():
		return null

	var position_value: Variant = hit.get("position")
	var normal_value: Variant = hit.get("normal")
	var rid_value: Variant = hit.get("rid")
	var shape_value: Variant = hit.get("shape")

	if not (position_value is Vector3):
		return null

	if not (normal_value is Vector3):
		return null

	var point: Vector3 = position_value
	var normal: Vector3 = normal_value

	if not support.is_walkable_surface(normal):
		return null

	var top_hit: TopHit = TopHit.new()
	top_hit.point = point
	top_hit.normal = normal

	if rid_value is RID:
		top_hit.collider_rid = rid_value

	if shape_value is int:
		top_hit.shape_index = shape_value

	return top_hit


func _prepare_ray_query(
	player: CharacterBody3D,
	ray_from: Vector3,
	ray_to: Vector3
) -> PhysicsRayQueryParameters3D:
	var player_rid: RID = player.get_rid()

	if ray_query == null or ray_query_player_rid != player_rid:
		ray_query_player_rid = player_rid
		ray_query = PhysicsRayQueryParameters3D.create(
			ray_from,
			ray_to,
			player.collision_mask,
			[player_rid]
		)
		ray_query.collide_with_areas = false
		ray_query.collide_with_bodies = true
		ray_query.hit_back_faces = false
		ray_query.hit_from_inside = false
		return ray_query

	ray_query.from = ray_from
	ray_query.to = ray_to
	ray_query.collision_mask = player.collision_mask
	return ray_query


func has_catch_intent(
	wall_normal: Vector3,
	intent_direction: Vector3,
	view_forward: Vector3
) -> bool:
	var toward_wall: Vector3 = -wall_normal
	var horizontal_intent: Vector3 = Vector3(
		intent_direction.x,
		0.0,
		intent_direction.z
	)

	if (
		horizontal_intent.length_squared()
		> MOTION_EPSILON_SQUARED
	):
		horizontal_intent = horizontal_intent.normalized()

		if (
			horizontal_intent.dot(toward_wall)
			>= minimum_approach_alignment
		):
			return true

	var horizontal_view: Vector3 = Vector3(
		view_forward.x,
		0.0,
		view_forward.z
	)

	if (
		horizontal_view.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return false

	horizontal_view = horizontal_view.normalized()
	return (
		horizontal_view.dot(toward_wall)
		>= minimum_approach_alignment
	)


func has_usable_ledge_span(
	player: CharacterBody3D,
	support: PlayerSupport,
	edge_point: Vector3,
	wall_normal: Vector3,
	edge_height: float,
	ledge_direction: Vector3
) -> bool:
	var half_width: float = get_ledge_span_half_width()

	if not _is_ledge_span_sample_valid(
		player,
		support,
		edge_point,
		wall_normal,
		edge_height,
		ledge_direction,
		half_width,
		-1.0
	):
		return false

	return _is_ledge_span_sample_valid(
		player,
		support,
		edge_point,
		wall_normal,
		edge_height,
		ledge_direction,
		half_width,
		1.0
	)


func _is_ledge_span_sample_valid(
	player: CharacterBody3D,
	support: PlayerSupport,
	edge_point: Vector3,
	wall_normal: Vector3,
	edge_height: float,
	ledge_direction: Vector3,
	half_width: float,
	direction_sign: float
) -> bool:
	var sample_edge_point: Vector3 = (
		edge_point
		+ ledge_direction
		* half_width
		* direction_sign
	)
	var wall_hit: WallHit = find_wall_near_edge(
		player,
		wall_normal,
		sample_edge_point
	)

	if (
		wall_hit == null
		or not is_wall_continuous(
			wall_hit,
			wall_normal,
			sample_edge_point
		)
	):
		return false

	var top_hit: TopHit = find_top_for_hang(
		player,
		support,
		wall_hit,
		edge_height
	)

	if top_hit == null:
		return false

	return (
		absf(top_hit.point.y - edge_height)
		<= get_shimmy_level_tolerance()
	)


func is_wall_continuous(
	wall_hit: WallHit,
	expected_wall_normal: Vector3,
	expected_edge_point: Vector3
) -> bool:
	if (
		wall_hit.normal.dot(expected_wall_normal)
		< minimum_shimmy_wall_alignment
	):
		return false

	var plane_distance: float = absf(
		(
			wall_hit.point
			- expected_edge_point
		).dot(expected_wall_normal)
	)

	return (
		plane_distance
		<= get_top_probe_inset() + PROBE_SAFE_MARGIN
	)


func is_suppressed_wall(
	wall_hit: WallHit
) -> bool:
	if suppressed_candidate == null:
		return false

	if (
		wall_hit.collider_rid
		!= suppressed_candidate.wall_collider_rid
	):
		return false

	if (
		suppressed_candidate.wall_shape_index >= 0
		and wall_hit.shape_index >= 0
		and wall_hit.shape_index
		!= suppressed_candidate.wall_shape_index
	):
		return false

	return true


func is_wall_surface(
	normal: Vector3
) -> bool:
	return absf(normal.y) <= maximum_wall_normal_y


func get_hang_position(
	edge_point: Vector3,
	wall_normal: Vector3
) -> Vector3:
	var hang_position: Vector3 = (
		edge_point
		+ wall_normal * get_hang_wall_distance()
	)
	hang_position.y = (
		edge_point.y
		- get_hang_anchor_height()
	)

	return hang_position


func is_hang_pose_valid(
	player: CharacterBody3D,
	candidate: LedgeCandidate,
	hang_position: Vector3
) -> bool:
	if candidate == null:
		return false

	var hang_transform: Transform3D = player.global_transform
	hang_transform.origin = hang_position

	var collision: KinematicCollision3D = (
		KinematicCollision3D.new()
	)
	var has_contact: bool = player.test_move(
		hang_transform,
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
		if not is_expected_hang_wall_contact(
			collision,
			collision_index,
			candidate
		):
			return false

	return true


func is_expected_hang_wall_contact(
	collision: KinematicCollision3D,
	collision_index: int,
	candidate: LedgeCandidate
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

	var collision_normal: Vector3 = (
		collision.get_normal(
			collision_index
		)
	)

	if (
		collision_normal.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return false

	collision_normal = collision_normal.normalized()

	var expected_wall_normal: Vector3 = (
		candidate.wall_normal
	)

	if (
		expected_wall_normal.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return false

	expected_wall_normal = (
		expected_wall_normal.normalized()
	)

	return (
		collision_normal.dot(
			expected_wall_normal
		)
		>= EXPECTED_HANG_WALL_MIN_ALIGNMENT
	)


func get_forward_probe_distance() -> float:
	return forward_probe_distance


func get_max_horizontal_reach() -> float:
	return max_horizontal_reach


func get_min_edge_height() -> float:
	return min_edge_height


func get_max_catch_height() -> float:
	return max_catch_height


func get_hand_reach_height() -> float:
	return hand_reach_height


func get_hang_anchor_height() -> float:
	return hang_anchor_height


func get_hang_wall_distance() -> float:
	return hang_wall_distance


func get_top_probe_inset() -> float:
	return top_probe_inset


func get_shimmy_level_tolerance() -> float:
	return shimmy_level_tolerance


func get_shimmy_attachment_correction_limit() -> float:
	return shimmy_attachment_correction_limit


func get_ledge_span_half_width() -> float:
	return ledge_span_half_width


func get_max_catch_fall_speed() -> float:
	return max_catch_fall_speed


func get_capsule_bottom_offset() -> float:
	return capsule_bottom_offset


func get_capsule_top_offset() -> float:
	return capsule_top_offset


func get_capsule_radius() -> float:
	return capsule_radius


func get_capsule_height() -> float:
	return capsule_height


func get_capsule_shape() -> CapsuleShape3D:
	return capsule_shape


func update_debug_logging(
	previously_had_candidate: bool
) -> void:
	if not debug_logging:
		return

	var has_candidate_now: bool = current_candidate != null

	if has_candidate_now and not previously_had_candidate:
		print(
			"Ledge candidate acquired: edge=",
			current_candidate.edge_point,
			" wall_normal=",
			current_candidate.wall_normal,
			" hangable=",
			current_candidate.hangable,
			" hang_position=",
			current_candidate.hang_position,
			" min_edge_height=",
			get_min_edge_height(),
			" max_catch_height=",
			get_max_catch_height(),
			" hang_anchor_height=",
			get_hang_anchor_height()
		)
	elif previously_had_candidate and not has_candidate_now:
		print("Ledge candidate lost")