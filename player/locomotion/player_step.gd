class_name PlayerStep
extends RefCounted


const PROBE_SAFE_MARGIN: float = 0.001
const PROBE_MAX_COLLISIONS: int = 8
const MOTION_EPSILON_SQUARED: float = 0.000001
const VERTICAL_NORMAL_EPSILON: float = 0.0001
const MIN_RISER_HORIZONTAL_COMPONENT: float = 0.05
const MIN_INWARD_ALIGNMENT: float = 0.02
const TOP_PROBE_INSET_RADIUS_RATIO: float = 0.05
const TOP_PROBE_VERTICAL_MARGIN_RADIUS_RATIO: float = 0.1
const CROSSING_CLEARANCE_MARGIN_MULTIPLIER: float = 4.0
const PLANE_INTERSECTION_MIN_SINE_SQUARED: float = 0.00000001


class StepCandidate:
	var edge_point: Vector3 = Vector3.ZERO
	var wall_normal: Vector3 = Vector3.ZERO
	var step_height: float = 0.0
	var approach_alignment: float = 0.0
	var source_support_point: Vector3 = Vector3.ZERO
	var source_support_normal: Vector3 = Vector3.UP
	var source_support_height: float = 0.0


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
	# body actually crosses the classified blocker plane so PlayerMotionSolver can
	# keep validating the local crossing envelope every frame.
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
	if support == null:
		return false

	# A step is a transition from a real walkable source support. Refresh at the
	# contact pose so an airborne wall seam can never enter the step system.
	# Once a legitimate step owns traversal, temporary support loss during its
	# kinematic lift is expected and does not cancel it.
	support.update(player)
	if not support.is_grounded():
		return false

	var source_support_normal: Vector3 = support.support_normal
	if source_support_normal.y <= VERTICAL_NORMAL_EPSILON:
		return false
	var source_support_point: Vector3 = support.support_point

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
				collision_index,
				source_support_point,
				source_support_normal
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
	collision_index: int,
	source_support_point: Vector3,
	source_support_normal: Vector3
) -> StepCandidate:
	# The movement collision is the authoritative proof that locomotion was
	# blocked. Do not demand a second hit near the source floor: doing so wrongly
	# defines a step as a solid riser that reaches the ground and rejects valid
	# undercut/floating obstacles. The contact supplies the blocker plane; the
	# top probe independently proves a reachable walkable destination surface.
	var contact_point: Vector3 = collision.get_position(collision_index)
	var contact_normal: Vector3 = collision.get_normal(collision_index)
	var blocker: Dictionary = _classify_blocking_contact(
		approach_direction,
		contact_point,
		contact_normal
	)
	if blocker.is_empty():
		return null

	var blocker_point_value: Variant = blocker.get("point")
	var wall_normal_value: Variant = blocker.get("wall_normal")
	if not (blocker_point_value is Vector3) or not (wall_normal_value is Vector3):
		return null

	var blocker_point: Vector3 = blocker_point_value
	var wall_normal: Vector3 = wall_normal_value
	var approach_alignment: float = approach_direction.dot(-wall_normal)
	if approach_alignment <= MIN_INWARD_ALIGNMENT:
		return null

	# Evaluate the source support plane at the blocker, not at the player's
	# center. This keeps the maximum step band geometrically correct on slopes.
	var source_height_at_blocker: float = _get_support_height_at_position(
		source_support_point,
		source_support_normal,
		blocker_point
	)
	var top_hit: Dictionary = find_top(
		player,
		support,
		blocker_point,
		wall_normal,
		source_height_at_blocker
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

	# Reconstruct the physical blocker/top edge from their two planes. The
	# blocker may be undercut or floating; only its actual blocking plane and the
	# destination top matter for step geometry.
	var wall_plane_distance: float = (
		(top_point - blocker_point).dot(wall_normal)
	)
	var edge_point: Vector3 = (
		top_point
		- (wall_plane_distance / intersection_sine_squared)
		* (wall_normal - top_normal * normal_dot)
	)

	# Measure the rise between support planes at the actual edge X/Z. This avoids
	# both airborne seam false positives and slope-dependent height errors.
	var source_height_at_edge: float = _get_support_height_at_position(
		source_support_point,
		source_support_normal,
		edge_point
	)
	var step_height: float = edge_point.y - source_height_at_edge
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
	candidate.source_support_point = source_support_point
	candidate.source_support_normal = source_support_normal
	candidate.source_support_height = source_height_at_edge
	return candidate


func _classify_blocking_contact(
	approach_direction: Vector3,
	contact_point: Vector3,
	contact_normal: Vector3
) -> Dictionary:
	if contact_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return {}

	var normalized_contact: Vector3 = contact_normal.normalized()
	var horizontal_normal := Vector3(
		normalized_contact.x,
		0.0,
		normalized_contact.z
	)
	var horizontal_length: float = horizontal_normal.length()
	if horizontal_length < MIN_RISER_HORIZONTAL_COMPONENT:
		return {}

	# Capsule contacts near an edge can have a Y component even when the
	# macroscopic blocker is a vertical face. Step crossing is defined in X/Z,
	# so canonicalize the actual blocking contact to its horizontal wall plane.
	var wall_normal: Vector3 = horizontal_normal / horizontal_length
	var alignment: float = approach_direction.dot(-wall_normal)
	if alignment <= MIN_INWARD_ALIGNMENT:
		return {}

	return {
		"point": contact_point,
		"normal": normalized_contact,
		"wall_normal": wall_normal,
	}


func find_top(
	player: CharacterBody3D,
	support: PlayerSupport,
	blocker_point: Vector3,
	wall_normal: Vector3,
	source_support_height_at_blocker: float
) -> Dictionary:
	# Probe just inward from the actual blocking plane. The vertical search band
	# is defined from the validated source support to max_step_height; it makes no
	# assumption about whether solid geometry exists beneath the destination top.
	var probe_center: Vector3 = blocker_point - wall_normal * top_probe_inset
	var ray_from: Vector3 = probe_center
	ray_from.y = (
		source_support_height_at_blocker
		+ max_step_height
		+ top_probe_vertical_margin
	)
	var ray_to: Vector3 = probe_center
	ray_to.y = source_support_height_at_blocker - top_probe_vertical_margin

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


func _get_support_height_at_position(
	support_point: Vector3,
	support_normal: Vector3,
	position: Vector3
) -> float:
	# Evaluate the validated support plane at arbitrary X/Z. Step geometry is
	# therefore anchored to the source surface itself rather than body pose or
	# capsule separation/safe-margin artifacts.
	return support_point.y - (
		support_normal.x * (position.x - support_point.x)
		+ support_normal.z * (position.z - support_point.z)
	) / support_normal.y


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
