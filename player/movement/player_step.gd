class_name PlayerStep
extends RefCounted


const PROBE_SAFE_MARGIN: float = 0.001
const PROBE_MAX_COLLISIONS: int = 8
const MOTION_EPSILON_SQUARED: float = 0.000001
const MIN_HORIZONTAL_CONTACT_COMPONENT: float = 0.05
const MIN_START_ALIGNMENT: float = 0.25
const MIN_CONTINUE_ALIGNMENT: float = 0.05
const TOP_PROBE_INSET_RADIUS_RATIO: float = 0.05
const TOP_PROBE_VERTICAL_MARGIN_RADIUS_RATIO: float = 0.1
const CROSSING_CLEARANCE_MARGIN_MULTIPLIER: float = 4.0
const PLANE_INTERSECTION_MIN_SINE_SQUARED: float = 0.00000001


class StepCandidate:
	var edge_point: Vector3 = Vector3.ZERO
	var top_point: Vector3 = Vector3.ZERO
	var top_normal: Vector3 = Vector3.UP
	var wall_normal: Vector3 = Vector3.ZERO
	var step_height: float = 0.0
	var approach_alignment: float = 0.0


var max_step_height: float
var step_acceleration: float
var max_step_speed: float
var collision_shape: CollisionShape3D

var capsule_radius: float
var capsule_height: float
var capsule_bottom_offset: float
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
	p_collision_shape: CollisionShape3D
) -> void:
	max_step_height = p_max_step_height
	step_acceleration = p_step_acceleration
	max_step_speed = p_max_step_speed
	collision_shape = p_collision_shape

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
	var capsule_shape: CapsuleShape3D = shape as CapsuleShape3D
	capsule_radius = capsule_shape.radius
	capsule_height = capsule_shape.height
	capsule_bottom_offset = (
		collision_shape.position.y
		- capsule_height * 0.5
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
		PROBE_SAFE_MARGIN
		* CROSSING_CLEARANCE_MARGIN_MULTIPLIER
	)


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
		cancel()
		return Vector3.ZERO

	var approach_direction: Vector3 = horizontal_input.normalized()
	var inward_direction: Vector3 = -active_candidate.wall_normal
	var approach_alignment: float = approach_direction.dot(inward_direction)
	if approach_alignment <= MIN_CONTINUE_ALIGNMENT:
		cancel()
		return Vector3.ZERO

	active_candidate.approach_alignment = approach_alignment

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

	var control_strength: float = (
		input_strength
		* clampf(approach_alignment, 0.0, 1.0)
	)
	var target_assist_speed: float = (
		max_step_speed
		* control_strength
	)

	# Step-up owns only a disposable upward correction. Normal WASD, gravity,
	# jumping, and collision response remain in player.velocity. The assist is
	# added only to this frame's displacement by PlayerMovement and never stored
	# as persistent momentum.
	if delta > sqrt(MOTION_EPSILON_SQUARED):
		var maximum_total_upward_speed: float = (
			maxf(0.0, remaining_height + PROBE_SAFE_MARGIN)
			/ delta
		)

		# If normal physics already has upward velocity, step-up supplies only the
		# additional amount needed. If normal physics is falling, assist may first
		# cancel that downward motion and then provide the requested climb speed.
		var maximum_assist_speed: float = maxf(
			0.0,
			maximum_total_upward_speed - player.velocity.y
		)
		target_assist_speed = minf(
			target_assist_speed,
			maximum_assist_speed
		)

	current_assist_speed = move_toward(
		current_assist_speed,
		target_assist_speed,
		step_acceleration * control_strength * delta
	)

	# The remaining-height limit is hard. A high previous assist value cannot
	# survive into a frame where less vertical clearance remains.
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
	var contact_normal: Vector3 = collision.get_normal(collision_index)
	if contact_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return null
	contact_normal = contact_normal.normalized()

	# The capsule's rounded lower cap can contact a sharp stair edge with a
	# diagonal normal, so only the horizontal component identifies the riser.
	var horizontal_normal := Vector3(
		contact_normal.x,
		0.0,
		contact_normal.z
	)
	if horizontal_normal.length() < MIN_HORIZONTAL_CONTACT_COMPONENT:
		return null
	var wall_normal: Vector3 = horizontal_normal.normalized()
	var approach_alignment: float = approach_direction.dot(-wall_normal)
	if approach_alignment < MIN_START_ALIGNMENT:
		return null

	var contact_point: Vector3 = collision.get_position(collision_index)
	var capsule_bottom_y: float = get_capsule_bottom_y(player.global_position)
	var top_hit: Dictionary = find_top(
		player,
		support,
		contact_point,
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

	# Reconstruct the wall/top plane intersection. The capsule contact point is
	# not the step height when its rounded bottom is touching the corner.
	var wall_plane_distance: float = (
		(top_point - contact_point).dot(wall_normal)
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
	candidate.top_point = top_point
	candidate.top_normal = top_normal
	candidate.wall_normal = wall_normal
	candidate.step_height = step_height
	candidate.approach_alignment = approach_alignment

	if not has_crossing_clearance(
		player,
		candidate,
		outward_distance
	):
		return null

	return candidate


func find_top(
	player: CharacterBody3D,
	support: PlayerSupport,
	contact_point: Vector3,
	wall_normal: Vector3,
	capsule_bottom_y: float
) -> Dictionary:
	var probe_center: Vector3 = contact_point - wall_normal * top_probe_inset
	var ray_from: Vector3 = probe_center
	ray_from.y = (
		capsule_bottom_y
		+ max_step_height
		+ top_probe_vertical_margin
	)
	var ray_to: Vector3 = probe_center
	ray_to.y = capsule_bottom_y - top_probe_vertical_margin

	var query: PhysicsRayQueryParameters3D = prepare_ray_query(
		player,
		ray_from,
		ray_to
	)
	var hit: Dictionary = (
		player.get_world_3d()
		.direct_space_state
		.intersect_ray(query)
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


func has_crossing_clearance(
	player: CharacterBody3D,
	candidate: StepCandidate,
	outward_distance: float
) -> bool:
	var crossing_transform: Transform3D = player.global_transform
	crossing_transform.origin += (
		-candidate.wall_normal
		* (outward_distance + crossing_clearance_margin)
	)
	crossing_transform.origin.y += (
		candidate.step_height
		+ crossing_clearance_margin
	)

	var collision := KinematicCollision3D.new()
	return not player.test_move(
		crossing_transform,
		Vector3.ZERO,
		collision,
		PROBE_SAFE_MARGIN,
		true,
		PROBE_MAX_COLLISIONS
	)


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


func get_assist_velocity() -> Vector3:
	return Vector3.UP * current_assist_speed


func is_active() -> bool:
	return active_candidate != null


func cancel() -> void:
	active_candidate = null
	current_assist_speed = 0.0
