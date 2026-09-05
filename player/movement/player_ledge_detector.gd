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

	get_capsule_shape()


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
	var vertical_margin: float = (
		get_capsule_radius()
		* SUPPRESSION_VERTICAL_MARGIN_RADIUS_RATIO
	)

	if (
		horizontal_edge_offset.length()
		> get_max_horizontal_reach() + get_capsule_radius()
	):
		suppressed_candidate = null
		return

	if (
		edge_offset.y
		< get_min_edge_height() - vertical_margin
		or edge_offset.y
		> get_max_catch_height() + vertical_margin
	):
		suppressed_candidate = null


func find_candidate(
	player: CharacterBody3D,
	support: PlayerSupport,
	intent_direction: Vector3,
	view_forward: Vector3
) -> LedgeCandidate:
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

	var approach_direction: Vector3 = (
		horizontal_velocity.normalized()
	)
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

	var edge_offset: Vector3 = (
		edge_point - player.global_position
	)
	var horizontal_edge_offset: Vector3 = Vector3(
		edge_offset.x,
		0.0,
		edge_offset.z
	)

	if (
		horizontal_edge_offset.length()
		> get_max_horizontal_reach() + PROBE_SAFE_MARGIN
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
		Vector3.UP.cross(wall_hit.normal)
	)

	if (
		ledge_direction.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return null

	ledge_direction = ledge_direction.normalized()

	if not has_usable_ledge_span(
		player,
		support,
		edge_point,
		wall_hit.normal,
		top_hit.point.y,
		ledge_direction
	):
		return null

	var hang_position: Vector3 = get_hang_position(
		edge_point,
		wall_hit.normal
	)
	var hangable: bool = is_hang_position_clear(
		player,
		hang_position
	)

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
	candidate.hangable = hangable

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

	if (
		horizontal_correction.length()
		> get_shimmy_attachment_correction_limit()
	):
		return null

	if not is_hang_position_clear(
		player,
		hang_position
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

	if not has_usable_ledge_span(
		player,
		support,
		edge_point,
		fixed_wall_normal,
		top_hit.point.y,
		Vector3.UP.cross(fixed_wall_normal).normalized()
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
	candidate.hangable = true

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

	var minimum_push_strength: float = cos(
		deg_to_rad(max_approach_angle_degrees)
	)
	var best_push_strength: float = minimum_push_strength
	var best_hit: WallHit = null
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
		best_hit = WallHit.new()
		best_hit.point = collision.get_position(
			collision_index
		)
		best_hit.normal = horizontal_normal
		best_hit.collider_rid = collision.get_collider_rid(
			collision_index
		)
		best_hit.shape_index = (
			collision.get_collider_shape_index(
				collision_index
			)
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

	var exclusions: Array[RID] = [player.get_rid()]
	var query: PhysicsRayQueryParameters3D = (
		PhysicsRayQueryParameters3D.create(
			ray_from,
			ray_to,
			player.collision_mask,
			exclusions
		)
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_back_faces = false
	query.hit_from_inside = false

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
	var exclusions: Array[RID] = [player.get_rid()]
	var query: PhysicsRayQueryParameters3D = (
		PhysicsRayQueryParameters3D.create(
			ray_from,
			ray_to,
			player.collision_mask,
			exclusions
		)
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_back_faces = false
	query.hit_from_inside = false

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


func has_catch_intent(
	wall_normal: Vector3,
	intent_direction: Vector3,
	view_forward: Vector3
) -> bool:
	var toward_wall: Vector3 = -wall_normal
	var minimum_alignment: float = cos(
		deg_to_rad(max_approach_angle_degrees)
	)
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
			>= minimum_alignment
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
		>= minimum_alignment
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

	for direction_sign: float in [-1.0, 1.0]:
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

		if (
			absf(top_hit.point.y - edge_height)
			> get_shimmy_level_tolerance()
		):
			return false

	return true


func is_wall_continuous(
	wall_hit: WallHit,
	expected_wall_normal: Vector3,
	expected_edge_point: Vector3
) -> bool:
	var minimum_alignment: float = cos(
		deg_to_rad(SHIMMY_MAX_WALL_TURN_DEGREES)
	)

	if (
		wall_hit.normal.dot(expected_wall_normal)
		< minimum_alignment
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
	var maximum_normal_y: float = sin(
		deg_to_rad(max_wall_tilt_degrees)
	)

	return absf(normal.y) <= maximum_normal_y


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


func is_hang_position_clear(
	player: CharacterBody3D,
	hang_position: Vector3
) -> bool:
	var hang_transform: Transform3D = player.global_transform
	hang_transform.origin = hang_position

	return not player.test_move(
		hang_transform,
		Vector3.ZERO,
		null,
		PROBE_SAFE_MARGIN,
		true,
		PROBE_MAX_COLLISIONS
	)


func get_forward_probe_distance() -> float:
	return (
		get_capsule_radius()
		* FORWARD_REACH_RADIUS_MULTIPLIER
	)


func get_max_horizontal_reach() -> float:
	return (
		get_capsule_radius()
		+ get_forward_probe_distance()
	)


func get_min_edge_height() -> float:
	return (
		get_capsule_bottom_offset()
		+ max_step_height
	)


func get_max_catch_height() -> float:
	return (
		get_capsule_top_offset()
		+ get_hand_reach_height()
	)


func get_hand_reach_height() -> float:
	return (
		get_capsule_height()
		* HAND_REACH_HEIGHT_RATIO
	)


func get_hang_anchor_height() -> float:
	return (
		eye_height
		+ get_capsule_radius()
		* HANG_EDGE_ABOVE_EYE_RADIUS_RATIO
	)


func get_hang_wall_distance() -> float:
	return get_capsule_radius() + PROBE_SAFE_MARGIN


func get_top_probe_inset() -> float:
	return (
		get_capsule_radius()
		* TOP_PROBE_INSET_RADIUS_RATIO
	)


func get_shimmy_level_tolerance() -> float:
	return maxf(
		PROBE_SAFE_MARGIN,
		get_capsule_radius()
		* SHIMMY_LEVEL_HEIGHT_RADIUS_RATIO
	)


func get_shimmy_attachment_correction_limit() -> float:
	return maxf(
		PROBE_SAFE_MARGIN,
		get_capsule_radius()
		* SHIMMY_ATTACHMENT_CORRECTION_RADIUS_RATIO
	)


func get_ledge_span_half_width() -> float:
	return (
		get_capsule_radius()
		* LEDGE_SPAN_HALF_WIDTH_RADIUS_RATIO
	)


func get_max_catch_fall_speed() -> float:
	var jump_speed: float = sqrt(
		2.0
		* gravity
		* maxf(jump_height, 0.0)
	)

	return (
		jump_speed
		* MAX_CATCH_FALL_SPEED_JUMP_SPEED_MULTIPLIER
	)


func get_capsule_bottom_offset() -> float:
	return (
		collision_shape.position.y
		- get_capsule_height() * 0.5
	)


func get_capsule_top_offset() -> float:
	return (
		collision_shape.position.y
		+ get_capsule_height() * 0.5
	)


func get_capsule_radius() -> float:
	return get_capsule_shape().radius


func get_capsule_height() -> float:
	return get_capsule_shape().height


func get_capsule_shape() -> CapsuleShape3D:
	var shape: Shape3D = collision_shape.shape
	assert(
		shape is CapsuleShape3D,
		"PlayerLedgeDetector requires the player collision shape to be CapsuleShape3D."
	)

	return shape as CapsuleShape3D


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
