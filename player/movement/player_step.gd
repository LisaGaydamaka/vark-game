class_name PlayerStep
extends RefCounted


const PROBE_SAFE_MARGIN: float = 0.001
const PROBE_MAX_COLLISIONS: int = 8
const MOTION_EPSILON_SQUARED: float = 0.000001
const MIN_RISER_HORIZONTAL_COMPONENT: float = 0.05
const MIN_INWARD_ALIGNMENT: float = 0.02
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
	var approach_alignment: float = 0.0


class StepPlan:
	var candidate: StepCandidate = null
	var rise_distance: float = 0.0
	var validation_lift_distance: float = 0.0
	var crossing_motion: Vector3 = Vector3.ZERO
	var valid: bool = false


var max_step_height: float
var step_acceleration: float
var max_step_speed: float

var capsule_bottom_offset: float
var capsule_radius: float
var riser_probe_height: float
var riser_probe_distance: float
var riser_probe_forward_margin: float
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
	riser_probe_forward_margin = (
		PROBE_SAFE_MARGIN * RISER_PROBE_FORWARD_MARGIN_MULTIPLIER
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


func prepare_plan(
	player: CharacterBody3D,
	input_direction: Vector3,
	delta: float
) -> StepPlan:
	if active_candidate == null:
		current_assist_speed = 0.0
		return null

	var horizontal_input := Vector3(
		input_direction.x,
		0.0,
		input_direction.z
	)
	var input_strength: float = minf(horizontal_input.length(), 1.0)
	if input_strength <= sqrt(MOTION_EPSILON_SQUARED):
		cancel()
		return null

	var approach_direction: Vector3 = horizontal_input.normalized()
	var inward_direction: Vector3 = -active_candidate.wall_normal
	var approach_alignment: float = approach_direction.dot(inward_direction)
	if approach_alignment <= MIN_INWARD_ALIGNMENT:
		cancel()
		return null

	if has_crossed_edge(player.global_position):
		cancel()
		return null

	var remaining_height: float = get_remaining_height(player.global_position)
	if remaining_height > max_step_height + crossing_clearance_margin:
		cancel()
		return null

	# Step speed controls only how much of an already-proven route may be
	# committed this frame. It is not velocity and is never added to the body's
	# persistent velocity state.
	var target_step_speed: float = max_step_speed * input_strength
	var maximum_rise_distance: float = maxf(
		0.0,
		remaining_height + PROBE_SAFE_MARGIN
	)
	if delta > sqrt(MOTION_EPSILON_SQUARED):
		target_step_speed = minf(
			target_step_speed,
			maximum_rise_distance / delta
		)

	current_assist_speed = move_toward(
		current_assist_speed,
		target_step_speed,
		step_acceleration * input_strength * delta
	)
	current_assist_speed = minf(
		maxf(0.0, current_assist_speed),
		maxf(0.0, target_step_speed)
	)

	var outward_distance: float = maxf(
		0.0,
		(player.global_position - active_candidate.edge_point).dot(
			active_candidate.wall_normal
		)
	)

	var plan := StepPlan.new()
	plan.candidate = active_candidate
	plan.rise_distance = minf(
		maximum_rise_distance,
		current_assist_speed * delta
	)
	plan.validation_lift_distance = maxf(
		0.0,
		remaining_height + crossing_clearance_margin
	)
	plan.crossing_motion = (
		inward_direction
		* (outward_distance + crossing_clearance_margin)
	)
	plan.valid = true
	return plan


func update_after_move(player: CharacterBody3D) -> void:
	if active_candidate == null:
		return

	# Height completion alone does not finish a step. Keep ownership until the
	# body actually crosses the classified riser plane so PlayerMovement can keep
	# validating the local crossing envelope every frame.
	if has_crossed_edge(player.global_position):
		cancel()
		return

	if get_remaining_height(player.global_position) > (
		max_step_height + crossing_clearance_margin
	):
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
	# The contact point tells us where locomotion was physically blocked. Probe
	# the low geometry locally around that point instead of casting from the
	# capsule center, which can miss a riser that touches the capsule off-center
	# during a diagonal or sideways approach.
	var contact_point: Vector3 = collision.get_position(collision_index)
	var contact_normal: Vector3 = collision.get_normal(collision_index)
	var riser_hit: Dictionary = find_riser(
		player,
		support,
		approach_direction,
		contact_point,
		contact_normal
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
	if approach_alignment <= MIN_INWARD_ALIGNMENT:
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

	# Reconstruct the actual riser/tread edge from their two planes.
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
	candidate.approach_alignment = approach_alignment
	return candidate


func find_riser(
	player: CharacterBody3D,
	support: PlayerSupport,
	approach_direction: Vector3,
	contact_point: Vector3,
	contact_normal: Vector3
) -> Dictionary:
	var hit: Dictionary = _probe_riser_from_contact(
		player,
		support,
		approach_direction,
		contact_point,
		approach_direction
	)
	if not hit.is_empty():
		return hit

	# Rounded capsule contacts can give a diagonal normal. It is still useful as
	# a fallback probe axis, but the raycast hit itself supplies the riser normal
	# used for classification.
	var horizontal_contact_normal := Vector3(
		contact_normal.x,
		0.0,
		contact_normal.z
	)
	if horizontal_contact_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return {}

	var inward_probe_direction: Vector3 = -horizontal_contact_normal.normalized()
	if inward_probe_direction.dot(approach_direction) < 0.0:
		inward_probe_direction = -inward_probe_direction

	return _probe_riser_from_contact(
		player,
		support,
		approach_direction,
		contact_point,
		inward_probe_direction
	)


func _probe_riser_from_contact(
	player: CharacterBody3D,
	support: PlayerSupport,
	approach_direction: Vector3,
	contact_point: Vector3,
	probe_direction: Vector3
) -> Dictionary:
	var horizontal_probe := Vector3(
		probe_direction.x,
		0.0,
		probe_direction.z
	)
	if horizontal_probe.length_squared() <= MOTION_EPSILON_SQUARED:
		return {}
	horizontal_probe = horizontal_probe.normalized()

	var capsule_bottom_y: float = get_capsule_bottom_y(player.global_position)
	var probe_anchor: Vector3 = contact_point
	probe_anchor.y = capsule_bottom_y + riser_probe_height

	var ray_from: Vector3 = (
		probe_anchor - horizontal_probe * riser_probe_distance
	)
	var ray_to: Vector3 = (
		probe_anchor + horizontal_probe * riser_probe_forward_margin
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

	var riser_normal: Vector3 = normal_value
	if riser_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return {}
	riser_normal = riser_normal.normalized()

	# A walkable face is a ramp/floor, not a stair riser.
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
	if alignment <= MIN_INWARD_ALIGNMENT:
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
	# Probe just behind the proven low blocker. This proves that the obstacle is
	# a step with walkable tread rather than an ordinary wall or continuous ramp.
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


func cancel() -> void:
	active_candidate = null
	current_assist_speed = 0.0
