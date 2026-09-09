class_name PlayerSupport
extends RefCounted


const MOTION_EPSILON_SQUARED: float = 0.000001
const SUPPORT_SEPARATION_EPSILON: float = 0.0001
const PROBE_START_MARGIN: float = 0.01
const FOOT_PROBE_RADIUS_RATIO: float = 0.55
const MINIMUM_NORMAL_Y: float = 0.0001
const MAXIMUM_STEEP_SUPPORT_SLOPE_DEGREES: float = 75.0


var has_support: bool = false
var support_normal: Vector3 = Vector3.UP
var support_point: Vector3 = Vector3.ZERO
var walkable: bool = false

var max_walkable_slope: float
var maximum_support_slope: float
var minimum_walkable_normal_y: float
var minimum_support_normal_y: float
var support_check_distance: float
var capsule_bottom_offset: float
var capsule_radius: float
var capsule_lower_sphere_center_offset: float
var maximum_probe_extra_distance: float
var probe_offsets: Array[Vector3] = []
var probe_surface_rises: Array[float] = []

var walkable_support_released: bool = false
var ray_query: PhysicsRayQueryParameters3D = null
var ray_query_player_rid: RID = RID()
var jump_debug_last_frame: int = -1


func _init(
	p_max_walkable_slope: float,
	p_support_check_distance: float,
	collision_shape: CollisionShape3D
) -> void:
	max_walkable_slope = p_max_walkable_slope
	maximum_support_slope = clampf(
		maxf(max_walkable_slope, MAXIMUM_STEEP_SUPPORT_SLOPE_DEGREES),
		0.0,
		89.0
	)
	minimum_walkable_normal_y = cos(deg_to_rad(max_walkable_slope))
	minimum_support_normal_y = cos(deg_to_rad(maximum_support_slope))
	support_check_distance = p_support_check_distance

	assert(
		collision_shape != null,
		"PlayerSupport requires a CollisionShape3D."
	)
	var shape: Shape3D = collision_shape.shape
	assert(
		shape is CapsuleShape3D,
		"PlayerSupport requires the player collision shape to be CapsuleShape3D."
	)

	var capsule_shape := shape as CapsuleShape3D
	capsule_radius = capsule_shape.radius
	capsule_bottom_offset = (
		collision_shape.position.y
		- capsule_shape.height * 0.5
	)
	capsule_lower_sphere_center_offset = capsule_bottom_offset + capsule_radius

	# Rays are only candidate discovery. They may search deeply enough to find a
	# steep plane beneath the curved capsule, but the hit is accepted only after
	# exact capsule-to-plane separation is measured below.
	maximum_probe_extra_distance = _get_vertical_discovery_allowance(
		minimum_support_normal_y
	)

	var probe_radius: float = capsule_radius * FOOT_PROBE_RADIUS_RATIO
	probe_offsets = [
		Vector3.ZERO,
		Vector3(probe_radius, 0.0, 0.0),
		Vector3(-probe_radius, 0.0, 0.0),
		Vector3(0.0, 0.0, probe_radius),
		Vector3(0.0, 0.0, -probe_radius),
	]
	probe_surface_rises.clear()
	for offset: Vector3 in probe_offsets:
		var horizontal_distance_squared: float = (
			offset.x * offset.x
			+ offset.z * offset.z
		)
		var lower_surface_radius_y: float = sqrt(maxf(
			0.0,
			capsule_radius * capsule_radius - horizontal_distance_squared
		))
		probe_surface_rises.append(
			capsule_radius - lower_surface_radius_y
		)


func update(player: CharacterBody3D) -> void:
	_clear_support(player)

	# Jumping explicitly releases walkable support. It can be reacquired only
	# after ballistic ascent has ended. This makes grounded -> airborne a real
	# state transition instead of something a nearby floor ray can undo.
	if walkable_support_released and player.velocity.y <= SUPPORT_SEPARATION_EPSILON:
		walkable_support_released = false

	var capsule_bottom_y: float = player.global_position.y + capsule_bottom_offset
	var best_separation: float = INF
	var best_point: Vector3 = Vector3.ZERO
	var best_normal: Vector3 = Vector3.UP
	var maximum_probe_distance: float = (
		support_check_distance
		+ maximum_probe_extra_distance
	)

	for probe_index: int in range(probe_offsets.size()):
		var offset: Vector3 = probe_offsets[probe_index]
		var probe_surface_y: float = (
			capsule_bottom_y
			+ probe_surface_rises[probe_index]
		)
		var ray_from: Vector3 = player.global_position + offset
		ray_from.y = probe_surface_y + PROBE_START_MARGIN
		var ray_to: Vector3 = ray_from
		ray_to.y = probe_surface_y - maximum_probe_distance

		var query: PhysicsRayQueryParameters3D = _prepare_ray_query(
			player,
			ray_from,
			ray_to
		)
		var hit: Dictionary = (
			player.get_world_3d().direct_space_state.intersect_ray(query)
		)
		if hit.is_empty():
			continue

		var point_value: Variant = hit.get("position")
		var normal_value: Variant = hit.get("normal")
		if not (point_value is Vector3) or not (normal_value is Vector3):
			continue

		var normal: Vector3 = normal_value
		if normal.length_squared() <= MOTION_EPSILON_SQUARED:
			continue
		normal = normal.normalized()
		if not is_support_surface(normal):
			continue

		var point: Vector3 = point_value
		var separation: float = _get_capsule_plane_separation(
			player,
			point,
			normal
		)
		if separation > support_check_distance + SUPPORT_SEPARATION_EPSILON:
			continue

		var candidate_walkable: bool = is_walkable_surface(normal)
		if candidate_walkable:
			# Persistent Y is ballistic in this controller. A walkable plane cannot
			# reacquire support while that ballistic state is moving upward, even if
			# the plane remains inside snap/proximity distance for a frame or two.
			if (
				walkable_support_released
				or player.velocity.y > SUPPORT_SEPARATION_EPSILON
			):
				continue
		else:
			# Steep support uses full 3D surface velocity. If that velocity is moving
			# away from the candidate plane, the unilateral contact is released.
			var normal_velocity: float = player.velocity.dot(normal)
			if normal_velocity > SUPPORT_SEPARATION_EPSILON:
				continue

		var ranking_separation: float = maxf(0.0, separation)
		if ranking_separation >= best_separation:
			continue

		best_separation = ranking_separation
		best_point = point
		best_normal = normal

	if best_separation == INF:
		_debug_jump_gate(player)
		return

	has_support = true
	walkable = is_walkable_surface(best_normal)
	support_point = best_point
	support_normal = best_normal
	_debug_jump_gate(player)


func release_walkable_support(player: CharacterBody3D) -> void:
	walkable_support_released = true
	_clear_support(player)


func _clear_support(player: CharacterBody3D) -> void:
	has_support = false
	support_normal = Vector3.UP
	support_point = player.global_position
	walkable = false


func _get_capsule_plane_separation(
	player: CharacterBody3D,
	plane_point: Vector3,
	plane_normal: Vector3
) -> float:
	var lower_sphere_center: Vector3 = player.global_position
	lower_sphere_center.y += capsule_lower_sphere_center_offset
	return (
		plane_normal.dot(lower_sphere_center - plane_point)
		- capsule_radius
	)


func _debug_jump_gate(player: CharacterBody3D) -> void:
	if not Input.is_action_just_pressed("jump"):
		return

	var frame: int = Engine.get_physics_frames()
	if frame == jump_debug_last_frame:
		return
	jump_debug_last_frame = frame

	var grounded: bool = has_support and walkable
	var movement_input: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)
	var reason: String = ""
	if grounded:
		if movement_input.is_zero_approx():
			reason = "eligible_normal_jump"
		else:
			reason = "eligible_but_routed_through_ground_mantle_first"
	elif has_support and not walkable:
		reason = "blocked_sliding_on_non_walkable_support"
	else:
		reason = "blocked_no_ground_support"

	print(
		"[JUMP_DEBUG] frame=%d event=GROUND_GATE reason=%s raw_space=%s action_held=%s grounded=%s has_support=%s walkable=%s normal=%s normal_y=%.4f min_walkable_y=%.4f point=%s pos=%s vel=%s move=%s support_released=%s"
		% [
			frame,
			reason,
			str(Input.is_physical_key_pressed(KEY_SPACE)),
			str(Input.is_action_pressed("jump")),
			str(grounded),
			str(has_support),
			str(walkable),
			str(support_normal),
			support_normal.y,
			minimum_walkable_normal_y,
			str(support_point),
			str(player.global_position),
			str(player.velocity),
			str(movement_input),
			str(walkable_support_released),
		]
	)


func _get_vertical_discovery_allowance(normal_y: float) -> float:
	var safe_normal_y: float = clampf(normal_y, MINIMUM_NORMAL_Y, 1.0)
	return capsule_radius * (1.0 / safe_normal_y - 1.0)


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


func is_support_surface(normal: Vector3) -> bool:
	return normal.y >= minimum_support_normal_y - 0.00001


func is_walkable_surface(normal: Vector3) -> bool:
	return normal.y >= minimum_walkable_normal_y - 0.00001


func is_grounded() -> bool:
	return has_support and walkable
