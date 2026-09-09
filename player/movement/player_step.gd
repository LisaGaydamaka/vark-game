class_name PlayerStep
extends RefCounted


const PROBE_SAFE_MARGIN: float = 0.001
const PROBE_MAX_COLLISIONS: int = 8
const MOTION_EPSILON_SQUARED: float = 0.000001
const ROUTE_BLOCKING_DOT_EPSILON: float = 0.0001
const MIN_RISER_HORIZONTAL_COMPONENT: float = 0.05
const MIN_START_ALIGNMENT: float = 0.25
const MIN_CONTINUE_ALIGNMENT: float = 0.05
const RISER_PROBE_HEIGHT_MARGIN_MULTIPLIER: float = 4.0
const RISER_PROBE_FORWARD_MARGIN_MULTIPLIER: float = 4.0
const TOP_PROBE_INSET_RADIUS_RATIO: float = 0.05
const TOP_PROBE_VERTICAL_MARGIN_RADIUS_RATIO: float = 0.1
const CROSSING_CLEARANCE_MARGIN_MULTIPLIER: float = 4.0
const PLANE_INTERSECTION_MIN_SINE_SQUARED: float = 0.00000001


class StepCandidate:
	var edge_point: Vector3 = Vector3.ZERO
	var wall_normal: Vector3 = Vector3.ZERO
	var step_height: float = 0.0
	var crossing_distance: float = 0.0
	var approach_alignment: float = 0.0


var max_step_height: float
var step_acceleration: float
var max_step_speed: float

var capsule_bottom_offset: float
var capsule_radius: float
var riser_probe_height: float
var riser_probe_distance: float
var top_probe_inset: float
var top_probe_vertical_margin: float
var crossing_clearance_margin: float

var ray_query: PhysicsRayQueryParameters3D = null
var ray_query_player_rid: RID = RID()
var active_candidate: StepCandidate = null
var current_assist_speed: float = 0.0


func _init(
	p_max_step_height: float,
	p_step_acceleration: float,
	p_max_step_speed: float,
	collision_shape: CollisionShape3D
) -> void:
	max_step_height = p_max_step_height
	step_acceleration = p_step_acceleration
	max_step_speed = p_max_step_speed

	assert(
		max_step_height >= 0.0,
		"PlayerStep requires max_step_height to be non-negative."
	)
	assert(
		step_acceleration >= 0.0,
		"PlayerStep requires step_acceleration to be non-negative."
	)
	assert(
		max_step_speed >= 0.0,
		"PlayerStep requires max_step_speed to be non-negative."
	)
	assert(
		collision_shape != null,
		"PlayerStep requires a CollisionShape3D."
	)

	var shape: Shape3D = collision_shape.shape
	assert(
		shape is CapsuleShape3D,
		"PlayerStep requires the player collision shape to be CapsuleShape3D."
	)

	var capsule_shape := shape as CapsuleShape3D
	capsule_radius = capsule_shape.radius
	var capsule_height: float = capsule_shape.height
	capsule_bottom_offset = collision_shape.position.y - capsule_height * 0.5
	riser_probe_height = (
		PROBE_SAFE_MARGIN * RISER_PROBE_HEIGHT_MARGIN_MULTIPLIER
	)
	riser_probe_distance = (
		capsule_radius
		+ PROBE_SAFE_MARGIN * RISER_PROBE_FORWARD_MARGIN_MULTIPLIER
	)
	top_probe_inset = maxf(
		PROBE_SAFE_MARGIN * 4.0,
		capsule_radius * TOP_PROBE_INSET_RADIUS_RATIO
	)
	top_probe_vertical_margin = maxf(
		PROBE_SAFE_MARGIN * 4.0,
		capsule_radius * TOP_PROBE_VERTICAL_MARGIN_RADIUS_RATIO
	)
	crossing_clearance_margin = (
		PROBE_SAFE_MARGIN * CROSSING_CLEARANCE_MARGIN_MULTIPLIER
	)


func constrain_persistent_vertical_velocity(player: CharacterBody3D) -> void:
	if active_candidate != null:
		player.velocity.y = 0.0


func update_before_move(
	player: CharacterBody3D,
	input_direction: Vector3,
	delta: float
) -> Vector3:
	if active_candidate == null:
		current_assist_speed = 0.0
		return Vector3.ZERO

	var horizontal_input := Vector3(
		input_direction.x,
		0.0,
		input_direction.z
	)
	var input_strength: float = minf(horizontal_input.length(), 1.0)
	if input_strength <= sqrt(MOTION_EPSILON_SQUARED):
		_cancel_for_lost_intent(player)
		return Vector3.ZERO

	var approach_direction: Vector3 = horizontal_input.normalized()
	var inward_direction: Vector3 = -active_candidate.wall_normal
	var approach_alignment: float = approach_direction.dot(inward_direction)
	if approach_alignment <= MIN_CONTINUE_ALIGNMENT:
		_cancel_for_lost_intent(player)
		return Vector3.ZERO

	var remaining_height: float = get_remaining_height(player.global_position)
	if remaining_height <= PROBE_SAFE_MARGIN:
		cancel()
		return Vector3.ZERO
	if has_crossed_edge(player.global_position):
		cancel()
		return Vector3.ZERO
	if remaining_height > max_step_height + crossing_clearance_margin:
		cancel()
		return Vector3.ZERO

	# Step-up owns vertical motion while active. Normal horizontal locomotion and
	# collision response remain persistent; the upward assist exists only for the
	# current movement frame.
	player.velocity.y = 0.0

	var control_strength: float = (
		input_strength * clampf(approach_alignment, 0.0, 1.0)
	)
	var target_assist_speed: float = max_step_speed * control_strength

	if delta > sqrt(MOTION_EPSILON_SQUARED):
		var maximum_upward_speed: float = (
			maxf(0.0, remaining_height + PROBE_SAFE_MARGIN) / delta
		)
		target_assist_speed = minf(
			target_assist_speed,
			maximum_upward_speed
		)

	current_assist_speed = move_toward(
		current_assist_speed,
		target_assist_speed,
		step_acceleration * control_strength * delta
	)
	current_assist_speed = minf(
		maxf(0.0, current_assist_speed),
		maxf(0.0, target_assist_speed)
	)

	return Vector3.UP * current_assist_speed


func update_after_move(player: CharacterBody3D) -> void:
	if active_candidate == null:
		return
	if get_remaining_height(player.global_position) <= PROBE_SAFE_MARGIN:
		cancel()
		return
	if has_crossed_edge(player.global_position):
		cancel()


func try_start_from_contacts(
	player: CharacterBody3D,
	support: PlayerSupport,
	input_direction: Vector3,
	collisions: Array[KinematicCollision3D]
) -> bool:
	if active_candidate != null or collisions.is_empty():
		return false

	var horizontal_input := Vector3(
		input_direction.x,
		0.0,
		input_direction.z
	)
	if horizontal_input.length_squared() <= MOTION_EPSILON_SQUARED:
		return false
	var approach_direction: Vector3 = horizontal_input.normalized()

	var best_candidate: StepCandidate = null
	for collision: KinematicCollision3D in collisions:
		if collision == null:
			continue
		for collision_index: int in range(collision.get_collision_count()):
			var candidate: StepCandidate = build_candidate_from_contact(
				player,
				support,
				approach_direction,
				collision,
				collision_index
			)
			if candidate == null:
				continue
			if (
				best_candidate == null
				or candidate.approach_alignment > best_candidate.approach_alignment
			):
				best_candidate = candidate

	if best_candidate == null:
		return false

	active_candidate = best_candidate
	current_assist_speed = 0.0
	return true


func build_candidate_from_contact(
	player: CharacterBody3D,
	support: PlayerSupport,
	approach_direction: Vector3,
	collision: KinematicCollision3D,
	collision_index: int
) -> StepCandidate:
	# The capsule contact is only evidence that locomotion was blocked. It is not
	# used as the stair face because the rounded capsule can report a diagonal
	# normal on both real risers and ordinary ramps. Prove a separate low blocker.
	var expected_collider_rid: RID = collision.get_collider_rid(collision_index)
	var riser_hit: Dictionary = find_riser(
		player,
		support,
		approach_direction,
		expected_collider_rid
	)
	if riser_hit.is_empty():
		return null

	var riser_point_value: Variant = riser_hit.get("point")
	var wall_normal_value: Variant = riser_hit.get("wall_normal")
	if not (riser_point_value is Vector3) or not (wall_normal_value is Vector3):
		return null

	var riser_point: Vector3 = riser_point_value
	var wall_normal: Vector3 = wall_normal_value
	var approach_alignment: float = approach_direction.dot(-wall_normal)
	if approach_alignment < MIN_START_ALIGNMENT:
		return null

	var capsule_bottom_y: float = get_capsule_bottom_y(player.global_position)
	var top_hit: Dictionary = find_top(
		player,
		support,
		riser_point,
		wall_normal,
		capsule_bottom_y
	)
	if top_hit.is_empty():
		return null

	var top_point_value: Variant = top_hit.get("point")
	var top_normal_value: Variant = top_hit.get("normal")
	if not (top_point_value is Vector3) or not (top_normal_value is Vector3):
		return null

	var top_point: Vector3 = top_point_value
	var top_normal: Vector3 = top_normal_value
	var normal_dot: float = clampf(wall_normal.dot(top_normal), -1.0, 1.0)
	var intersection_sine_squared: float = 1.0 - normal_dot * normal_dot
	if intersection_sine_squared <= PLANE_INTERSECTION_MIN_SINE_SQUARED:
		return null

	# Reconstruct the actual riser/tread edge from their two planes. The riser
	# point now comes from the dedicated blocker probe, not the rounded capsule.
	var wall_plane_distance: float = (
		(top_point - riser_point).dot(wall_normal)
	)
	var edge_point: Vector3 = (
		top_point
		- (wall_plane_distance / intersection_sine_squared)
		* (wall_normal - top_normal * normal_dot)
	)
	var step_height: float = edge_point.y - capsule_bottom_y
	if step_height <= PROBE_SAFE_MARGIN:
		return null
	if step_height > max_step_height + PROBE_SAFE_MARGIN:
		return null

	var outward_distance: float = (
		(player.global_position - edge_point).dot(wall_normal)
	)
	if outward_distance <= PROBE_SAFE_MARGIN:
		return null

	var candidate := StepCandidate.new()
	candidate.edge_point = edge_point
	candidate.wall_normal = wall_normal
	candidate.step_height = step_height
	candidate.crossing_distance = outward_distance + crossing_clearance_margin
	candidate.approach_alignment = approach_alignment

	if not has_route_clearance(player, candidate):
		return null

	return candidate


func find_riser(
	player: CharacterBody3D,
	support: PlayerSupport,
	approach_direction: Vector3,
	expected_collider_rid: RID
) -> Dictionary:
	var capsule_bottom_y: float = get_capsule_bottom_y(player.global_position)
	var ray_from: Vector3 = player.global_position
	ray_from.y = capsule_bottom_y + riser_probe_height
	var ray_to: Vector3 = (
		ray_from + approach_direction * riser_probe_distance
	)

	var query: PhysicsRayQueryParameters3D = prepare_ray_query(
		player,
		ray_from,
		ray_to
	)
	var hit: Dictionary = (
		player.get_world_3d().direct_space_state.intersect_ray(query)
	)
	if hit.is_empty():
		return {}

	var position_value: Variant = hit.get("position")
	var normal_value: Variant = hit.get("normal")
	if not (position_value is Vector3) or not (normal_value is Vector3):
		return {}

	var hit_rid_value: Variant = hit.get("rid")
	if expected_collider_rid.is_valid() and hit_rid_value is RID:
		var hit_rid: RID = hit_rid_value
		if hit_rid.is_valid() and hit_rid != expected_collider_rid:
			return {}

	var riser_normal: Vector3 = normal_value
	if riser_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return {}
	riser_normal = riser_normal.normalized()

	# A walkable face is a ramp/floor, not a stair riser. This is the fundamental
	# distinction that the rounded capsule contact could not provide reliably.
	if support.is_walkable_surface(riser_normal):
		return {}

	var horizontal_normal := Vector3(
		riser_normal.x,
		0.0,
		riser_normal.z
	)
	if horizontal_normal.length() < MIN_RISER_HORIZONTAL_COMPONENT:
		return {}

	var wall_normal: Vector3 = horizontal_normal.normalized()
	var alignment: float = approach_direction.dot(-wall_normal)
	if alignment < MIN_START_ALIGNMENT:
		return {}

	return {
		"point": position_value,
		"normal": riser_normal,
		"wall_normal": wall_normal,
	}


func find_top(
	player: CharacterBody3D,
	support: PlayerSupport,
	riser_point: Vector3,
	wall_normal: Vector3,
	capsule_bottom_y: float
) -> Dictionary:
	# Probe behind a proven blocking riser. A continuous ramp cannot reach this
	# stage because its low face is walkable and is rejected by find_riser().
	var probe_center: Vector3 = riser_point - wall_normal * top_probe_inset
	var ray_from: Vector3 = probe_center
	ray_from.y = (
		capsule_bottom_y + max_step_height + top_probe_vertical_margin
	)
	var ray_to: Vector3 = probe_center
	ray_to.y = capsule_bottom_y - top_probe_vertical_margin

	var query: PhysicsRayQueryParameters3D = prepare_ray_query(
		player,
		ray_from,
		ray_to
	)
	var hit: Dictionary = (
		player.get_world_3d().direct_space_state.intersect_ray(query)
	)
	if hit.is_empty():
		return {}

	var position_value: Variant = hit.get("position")
	var normal_value: Variant = hit.get("normal")
	if not (position_value is Vector3) or not (normal_value is Vector3):
		return {}

	var top_normal: Vector3 = normal_value
	if top_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return {}
	top_normal = top_normal.normalized()
	if not support.is_walkable_surface(top_normal):
		return {}

	return {
		"point": position_value,
		"normal": top_normal,
	}


func prepare_ray_query(
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


func has_route_clearance(
	player: CharacterBody3D,
	candidate: StepCandidate
) -> bool:
	if not is_vertical_route_clear(player, candidate):
		return false
	return is_forward_route_clear(player, candidate)


func is_vertical_route_clear(
	player: CharacterBody3D,
	candidate: StepCandidate
) -> bool:
	var lift_motion: Vector3 = Vector3.UP * (
		candidate.step_height + crossing_clearance_margin
	)
	return _can_travel_route_segment(
		player,
		player.global_transform,
		lift_motion
	)


func is_forward_route_clear(
	player: CharacterBody3D,
	candidate: StepCandidate
) -> bool:
	var lifted_transform: Transform3D = player.global_transform
	lifted_transform.origin.y += (
		candidate.step_height + crossing_clearance_margin
	)
	var crossing_motion: Vector3 = (
		-candidate.wall_normal * candidate.crossing_distance
	)
	return _can_travel_route_segment(
		player,
		lifted_transform,
		crossing_motion
	)


func _can_travel_route_segment(
	player: CharacterBody3D,
	from_transform: Transform3D,
	motion: Vector3
) -> bool:
	var required_distance: float = motion.length()
	if required_distance <= sqrt(MOTION_EPSILON_SQUARED):
		return true

	var collision := KinematicCollision3D.new()
	var blocked: bool = player.test_move(
		from_transform,
		motion,
		collision,
		PROBE_SAFE_MARGIN,
		false,
		PROBE_MAX_COLLISIONS
	)
	if not blocked:
		return true

	var route_direction: Vector3 = motion / required_distance
	var traveled_distance: float = maxf(
		0.0,
		collision.get_travel().dot(route_direction)
	)
	if (
		traveled_distance
		>= required_distance - get_route_progress_tolerance()
	):
		return true

	# Jolt can still report geometry that is already tangent to the capsule.
	# Tangential side contacts do not obstruct this segment; only a contact whose
	# normal actually opposes the requested route makes the segment invalid.
	for collision_index: int in range(collision.get_collision_count()):
		var normal: Vector3 = collision.get_normal(collision_index)
		if normal.dot(route_direction) < -ROUTE_BLOCKING_DOT_EPSILON:
			return false
	return true


func get_route_progress_tolerance() -> float:
	return PROBE_SAFE_MARGIN + crossing_clearance_margin


func has_crossed_edge(position: Vector3) -> bool:
	if active_candidate == null:
		return false
	return (
		(position - active_candidate.edge_point).dot(
			active_candidate.wall_normal
		)
		<= 0.0
	)


func get_remaining_height(position: Vector3) -> float:
	if active_candidate == null:
		return 0.0
	return active_candidate.edge_point.y - get_capsule_bottom_y(position)


func get_capsule_bottom_y(position: Vector3) -> float:
	return position.y + capsule_bottom_offset


func is_active() -> bool:
	return active_candidate != null


func _cancel_for_lost_intent(player: CharacterBody3D) -> void:
	if active_candidate != null:
		var inward_direction: Vector3 = -active_candidate.wall_normal
		var inward_speed: float = player.velocity.dot(inward_direction)
		if inward_speed > 0.0:
			player.velocity -= inward_direction * inward_speed
	cancel()


func cancel() -> void:
	active_candidate = null
	current_assist_speed = 0.0
