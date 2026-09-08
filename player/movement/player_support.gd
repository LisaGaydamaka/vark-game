class_name PlayerSupport
extends RefCounted


const MOTION_EPSILON_SQUARED: float = 0.000001
const PROBE_START_MARGIN: float = 0.01
const FOOT_PROBE_RADIUS_RATIO: float = 0.55


var has_support: bool = false
var support_normal: Vector3 = Vector3.UP
var support_point: Vector3 = Vector3.ZERO
var walkable: bool = false

var max_walkable_slope: float
var support_check_distance: float
var capsule_bottom_offset: float
var maintenance_probe_offsets: Array[Vector3] = []

var ray_query: PhysicsRayQueryParameters3D = null
var ray_query_player_rid: RID = RID()


func _init(
	p_max_walkable_slope: float,
	p_support_check_distance: float,
	collision_shape: CollisionShape3D
) -> void:
	max_walkable_slope = p_max_walkable_slope
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
	capsule_bottom_offset = (
		collision_shape.position.y
		- capsule_shape.height * 0.5
	)

	var probe_radius: float = (
		capsule_shape.radius
		* FOOT_PROBE_RADIUS_RATIO
	)
	maintenance_probe_offsets = [
		Vector3(probe_radius, 0.0, 0.0),
		Vector3(-probe_radius, 0.0, 0.0),
		Vector3(0.0, 0.0, probe_radius),
		Vector3(0.0, 0.0, -probe_radius),
	]


func update(player: CharacterBody3D) -> void:
	var had_support: bool = has_support and walkable

	has_support = false
	support_normal = Vector3.UP
	support_point = player.global_position
	walkable = false

	# Acquiring a new floor and maintaining an existing floor are deliberately
	# different operations. New support must exist directly beneath the capsule
	# center. Peripheral probes may only preserve already-established support over
	# seams and edges; geometry in front of the capsule cannot become our floor.
	var center_hit: Dictionary = _probe_walkable_floor(
		player,
		Vector3.ZERO
	)
	if not center_hit.is_empty():
		_apply_hit(center_hit)
		return

	if not had_support:
		return

	var best_hit: Dictionary = {}
	var best_gap: float = INF
	for offset: Vector3 in maintenance_probe_offsets:
		var hit: Dictionary = _probe_walkable_floor(player, offset)
		if hit.is_empty():
			continue
		var gap_value: Variant = hit.get("gap")
		if not (gap_value is float):
			continue
		var gap: float = gap_value
		if gap >= best_gap:
			continue
		best_gap = gap
		best_hit = hit

	if not best_hit.is_empty():
		_apply_hit(best_hit)


func get_motion_floor_normal(
	player: CharacterBody3D,
	horizontal_velocity: Vector3,
	delta: float
) -> Vector3:
	# A new incline may affect this frame only when we are already supported and a
	# predictive center-foot query finds a walkable floor at the next horizontal
	# position. This authorizes continuous ramp transitions without allowing an
	# arbitrary collision normal to create upward motion.
	if not has_support or not walkable:
		return Vector3.ZERO

	var horizontal_motion := Vector3(
		horizontal_velocity.x,
		0.0,
		horizontal_velocity.z
	) * delta
	if horizontal_motion.length_squared() <= MOTION_EPSILON_SQUARED:
		return support_normal

	var capsule_bottom_y: float = (
		player.global_position.y
		+ capsule_bottom_offset
	)
	var maximum_slope_rise: float = (
		horizontal_motion.length()
		* tan(deg_to_rad(max_walkable_slope))
		+ PROBE_START_MARGIN
	)
	var ray_from: Vector3 = player.global_position + horizontal_motion
	ray_from.y = capsule_bottom_y + maximum_slope_rise
	var ray_to: Vector3 = ray_from
	ray_to.y = capsule_bottom_y - support_check_distance

	var hit: Dictionary = _raycast_walkable(player, ray_from, ray_to)
	if hit.is_empty():
		return support_normal

	var point_value: Variant = hit.get("point")
	var normal_value: Variant = hit.get("normal")
	if not (point_value is Vector3) or not (normal_value is Vector3):
		return support_normal

	var point: Vector3 = point_value
	if point.y > capsule_bottom_y + maximum_slope_rise + PROBE_START_MARGIN:
		return support_normal
	return normal_value


func _probe_walkable_floor(
	player: CharacterBody3D,
	offset: Vector3
) -> Dictionary:
	var capsule_bottom_y: float = (
		player.global_position.y
		+ capsule_bottom_offset
	)
	var ray_from: Vector3 = player.global_position + offset
	ray_from.y = capsule_bottom_y + PROBE_START_MARGIN
	var ray_to: Vector3 = ray_from
	ray_to.y = capsule_bottom_y - support_check_distance

	var hit: Dictionary = _raycast_walkable(player, ray_from, ray_to)
	if hit.is_empty():
		return {}

	var point_value: Variant = hit.get("point")
	if not (point_value is Vector3):
		return {}
	var point: Vector3 = point_value
	hit["gap"] = maxf(0.0, ray_from.y - point.y)
	return hit


func _raycast_walkable(
	player: CharacterBody3D,
	ray_from: Vector3,
	ray_to: Vector3
) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = _prepare_ray_query(
		player,
		ray_from,
		ray_to
	)
	var hit: Dictionary = (
		player.get_world_3d().direct_space_state.intersect_ray(query)
	)
	if hit.is_empty():
		return {}

	var point_value: Variant = hit.get("position")
	var normal_value: Variant = hit.get("normal")
	if not (point_value is Vector3) or not (normal_value is Vector3):
		return {}

	var normal: Vector3 = normal_value
	if normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return {}
	normal = normal.normalized()
	if not is_walkable_surface(normal):
		return {}

	return {
		"point": point_value,
		"normal": normal,
	}


func _apply_hit(hit: Dictionary) -> void:
	var point_value: Variant = hit.get("point")
	var normal_value: Variant = hit.get("normal")
	if not (point_value is Vector3) or not (normal_value is Vector3):
		return

	has_support = true
	walkable = true
	support_point = point_value
	support_normal = normal_value


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


func is_walkable_surface(normal: Vector3) -> bool:
	var minimum_normal_y: float = cos(
		deg_to_rad(
			max_walkable_slope
		)
	)

	return (
		normal.y
		>= minimum_normal_y - 0.00001
	)


func is_grounded() -> bool:
	return has_support and walkable
