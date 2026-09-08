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
	var approach_direction: Vector3 = Vector3.ZERO
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
	locomotion_speed_budget: float,
	delta: float
) -> bool:
	if active_candidate == null:
		return false

	var horizontal_input := Vector3(
		input_direction.x,
		0.0,
		input_direction.z
	)
	var input_strength: float = minf(horizontal_input.length(), 1.0)
	if input_strength <= sqrt(MOTION_EPSILON_SQUARED):
		# Releasing WASD immediately returns ownership to normal physics. Step-up
		# does not restore, clear, or otherwise rewrite velocity on this path.
		cancel()
		return false

	var approach_direction: Vector3 = horizontal_input.normalized()
	var inward_direction: Vector3 = -active_candidate.wall_normal
	var approach_alignment: float = approach_direction.dot(inward_direction)
	if approach_alignment <= MIN_CONTINUE_ALIGNMENT:
		cancel()
		return false

	active_candidate.approach_direction = approach_direction
	active_candidate.approach_alignment = approach_alignment

	var capsule_bottom_y: float = get_capsule_bottom_y(player.global_position)
	var remaining_height: float = active_candidate.edge_point.y - capsule_bottom_y

	# Reaching the detected tread height completes the only job step-up owns:
	# vertical clearance. The normal motor has already run this frame, so release
	# immediately and leave its X/Z velocity untouched. Waiting for horizontal
	# edge-plane crossing can deadlock because the old step frame may suppress the
	# very forward component needed to cross that plane.
	if remaining_height <= PROBE_SAFE_MARGIN:
		cancel()
		return false

	if has_crossed_edge(player.global_position):
		finish_on_top(player)
		cancel()
		return false

	if remaining_height > max_step_height + crossing_clearance_margin:
		cancel()
		return false

	var traversal_normal: Vector3 = get_traversal_normal(player.global_position)
	if traversal_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		cancel()
		return false

	var traversal_tangent: Vector3 = get_traversal_tangent(traversal_normal)
	if traversal_tangent.length_squared() <= MOTION_EPSILON_SQUARED:
		cancel()
		return false

	var alignment_strength: float = clampf(approach_alignment, 0.0, 1.0)
	var control_strength: float = input_strength * alignment_strength

	# The step's horizontal budget comes from locomotion INTENT, not from current
	# collision-resolved velocity. A stair riser is expected to remove the actual
	# inward velocity; using that damaged value here creates a feedback loop that
	# makes step-up arbitrarily slow no matter how high the step tuning is.
	var intended_inward_speed: float = (
		maxf(0.0, locomotion_speed_budget)
		* input_strength
		* alignment_strength
	)

	# Preserve only the actual along-edge component. Step-up may redirect the
	# intended into-riser movement vertically, but it does not manufacture lateral
	# velocity parallel to the stair edge.
	var horizontal_velocity := Vector3(
		player.velocity.x,
		0.0,
		player.velocity.z
	)
	var ledge_axis: Vector3 = get_horizontal_ledge_axis()
	var lateral_velocity := Vector3.ZERO
	if ledge_axis.length_squared() > MOTION_EPSILON_SQUARED:
		lateral_velocity = (
			ledge_axis
			* horizontal_velocity.dot(ledge_axis)
		)

	var configured_path_speed: float = max_step_speed * control_strength
	var maximum_path_speed: float = configured_path_speed
	var tangent_horizontal := Vector3(
		traversal_tangent.x,
		0.0,
		traversal_tangent.z
	)
	var tangent_horizontal_factor: float = tangent_horizontal.length()

	# Near the vertical riser the tangent is almost purely upward, so the full
	# configured step speed is available. As it rotates toward horizontal, cap the
	# horizontal component against the MOTOR INTENT budget. This prevents a fast
	# climb from becoming a forward launch without letting the collision itself
	# throttle vertical clearance.
	if tangent_horizontal_factor > sqrt(MOTION_EPSILON_SQUARED):
		maximum_path_speed = minf(
			maximum_path_speed,
			intended_inward_speed / tangent_horizontal_factor
		)

	# Even extreme tuning must not move the capsule bottom above the detected top
	# in one physics frame. This bounds vertical clearance without moving or
	# snapping the body directly.
	if (
		delta > sqrt(MOTION_EPSILON_SQUARED)
		and traversal_tangent.y > sqrt(MOTION_EPSILON_SQUARED)
	):
		var maximum_vertical_speed: float = (
			maxf(0.0, remaining_height + PROBE_SAFE_MARGIN)
			/ delta
		)
		maximum_path_speed = minf(
			maximum_path_speed,
			maximum_vertical_speed / traversal_tangent.y
		)

	maximum_path_speed = maxf(0.0, maximum_path_speed)
	var current_path_speed: float = maxf(
		0.0,
		player.velocity.dot(traversal_tangent)
	)
	var controlled_path_speed: float = move_toward(
		current_path_speed,
		maximum_path_speed,
		step_acceleration * control_strength * delta
	)

	# The cap is a hard invariant. If the tangent rotates sharply between frames,
	# stale vertical path speed cannot become excess horizontal speed.
	controlled_path_speed = minf(
		maxf(0.0, controlled_path_speed),
		maximum_path_speed
	)

	player.velocity = (
		lateral_velocity
		+ traversal_tangent * controlled_path_speed
	)
	return true


func update_after_move(player: CharacterBody3D) -> void:
	if active_candidate == null:
		return
	if has_crossed_edge(player.global_position):
		finish_on_top(player)
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
	candidate.approach_direction = approach_direction
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


func get_traversal_normal(position: Vector3) -> Vector3:
	if active_candidate == null:
		return Vector3.ZERO

	var bottom_cap_center: Vector3 = get_bottom_cap_center_position(position)
	var edge_axis: Vector3 = get_edge_axis()
	if edge_axis.length_squared() <= MOTION_EPSILON_SQUARED:
		return active_candidate.wall_normal

	var local_edge_point: Vector3 = (
		active_candidate.edge_point
		+ edge_axis
		* (bottom_cap_center - active_candidate.edge_point).dot(edge_axis)
	)
	var radial: Vector3 = bottom_cap_center - local_edge_point
	if radial.length_squared() <= MOTION_EPSILON_SQUARED:
		return active_candidate.wall_normal

	# Below the edge the closest feature is the vertical riser. Once the lower
	# cap center reaches the top side, the closest feature becomes the edge and
	# the normal rotates around it toward the top surface normal.
	var top_side_distance: float = radial.dot(active_candidate.top_normal)
	if top_side_distance < 0.0:
		return active_candidate.wall_normal

	return radial.normalized()


func get_traversal_tangent(
	traversal_normal: Vector3
) -> Vector3:
	if active_candidate == null:
		return Vector3.ZERO
	if traversal_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO

	var ledge_axis: Vector3 = get_horizontal_ledge_axis()
	if ledge_axis.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO

	var plane_normal: Vector3 = (
		traversal_normal
		- ledge_axis * traversal_normal.dot(ledge_axis)
	)
	if plane_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO
	plane_normal = plane_normal.normalized()

	var tangent: Vector3 = plane_normal.cross(ledge_axis)
	if tangent.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO
	tangent = tangent.normalized()

	var inward_direction: Vector3 = -active_candidate.wall_normal
	var orientation_score: float = (
		tangent.dot(inward_direction)
		+ tangent.dot(Vector3.UP)
	)
	if orientation_score < 0.0:
		tangent = -tangent
	return tangent


func get_edge_axis() -> Vector3:
	if active_candidate == null:
		return Vector3.ZERO
	var edge_axis: Vector3 = (
		active_candidate.top_normal.cross(active_candidate.wall_normal)
	)
	if edge_axis.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO
	return edge_axis.normalized()


func get_horizontal_ledge_axis() -> Vector3:
	if active_candidate == null:
		return Vector3.ZERO
	var inward_direction: Vector3 = -active_candidate.wall_normal
	var ledge_axis: Vector3 = inward_direction.cross(Vector3.UP)
	if ledge_axis.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO
	return ledge_axis.normalized()


func finish_on_top(player: CharacterBody3D) -> void:
	if active_candidate == null:
		return

	# Completion must never convert step-generated vertical speed into horizontal
	# speed. Preserve X/Z exactly as produced by the normal locomotion budget and
	# only choose the Y component needed to follow the detected top plane.
	var horizontal_velocity := Vector3(
		player.velocity.x,
		0.0,
		player.velocity.z
	)
	var top_normal: Vector3 = active_candidate.top_normal
	if top_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		player.velocity = horizontal_velocity
		return
	top_normal = top_normal.normalized()

	var surface_follow_y: float = 0.0
	if absf(top_normal.y) > sqrt(MOTION_EPSILON_SQUARED):
		surface_follow_y = -(
			horizontal_velocity.x * top_normal.x
			+ horizontal_velocity.z * top_normal.z
		) / top_normal.y

	player.velocity = Vector3(
		horizontal_velocity.x,
		surface_follow_y,
		horizontal_velocity.z
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


func get_bottom_cap_center_position(position: Vector3) -> Vector3:
	return (
		position
		+ Vector3.UP
		* (capsule_bottom_offset + capsule_radius)
	)


func get_capsule_bottom_y(position: Vector3) -> float:
	return position.y + capsule_bottom_offset


func is_active() -> bool:
	return active_candidate != null


func cancel() -> void:
	active_candidate = null