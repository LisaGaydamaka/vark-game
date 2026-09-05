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
	step_up_active: bool
) -> void:
	var previously_had_candidate: bool = (
		current_candidate != null
	)
	var next_candidate: LedgeCandidate = null

	if (
		not (
			support.has_support
			and support.walkable
		)
		and not step_up_active
		and player.velocity.y >= -get_max_catch_fall_speed()
	):
		next_candidate = find_candidate(
			player,
			support
		)

	current_candidate = next_candidate
	update_debug_logging(previously_had_candidate)


func has_candidate() -> bool:
	return current_candidate != null


func get_candidate() -> LedgeCandidate:
	return current_candidate


func clear_candidate() -> void:
	current_candidate = null


func find_candidate(
	player: CharacterBody3D,
	support: PlayerSupport
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

	var hang_position: Vector3 = get_hang_position(
		edge_point,
		wall_hit.normal
	)
	var hangable: bool = is_hang_position_clear(
		player,
		hang_position
	)
	var ledge_direction: Vector3 = (
		Vector3.UP.cross(wall_hit.normal)
	)

	if (
		ledge_direction.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return null

	ledge_direction = ledge_direction.normalized()

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
	proposed_hang_position: Vector3
) -> LedgeCandidate:
	if reference_candidate == null:
		return null

	var expected_edge_point: Vector3 = (
		proposed_hang_position
		- reference_candidate.wall_normal
		* get_hang_wall_distance()
	)
	expected_edge_point.y = (
		proposed_hang_position.y
		+ get_hang_anchor_height()
	)

	var wall_hit: WallHit = find_wall_for_hang(
		player,
		reference_candidate,
		expected_edge_point
	)

	if wall_hit == null:
		return null

	var minimum_normal_alignment: float = cos(
		deg_to_rad(SHIMMY_MAX_WALL_TURN_DEGREES)
	)
	var normal_alignment: float = wall_hit.normal.dot(
		reference_candidate.wall_normal
	)

	if normal_alignment < minimum_normal_alignment:
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
		> get_top_probe_inset() + PROBE_SAFE_MARGIN
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


func find_wall_for_hang(
	player: CharacterBody3D,
	reference_candidate: LedgeCandidate,
	expected_edge_point: Vector3
) -> WallHit:
	var ray_from: Vector3 = (
		expected_edge_point
		+ reference_candidate.wall_normal
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
		- reference_candidate.wall_normal
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
