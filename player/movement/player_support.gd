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
var probe_offsets: Array[Vector3] = []

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
	probe_offsets = [
		Vector3.ZERO,
		Vector3(probe_radius, 0.0, 0.0),
		Vector3(-probe_radius, 0.0, 0.0),
		Vector3(0.0, 0.0, probe_radius),
		Vector3(0.0, 0.0, -probe_radius),
	]


func update(player: CharacterBody3D) -> void:
	has_support = false
	support_normal = Vector3.UP
	support_point = player.global_position
	walkable = false

	# Support is a floor sensor, not capsule collision recovery. Vertical foot
	# probes sample the actual world surface underneath the capsule footprint, so
	# a rounded capsule touching a stair edge cannot manufacture a fake slope.
	var capsule_bottom_y: float = (
		player.global_position.y
		+ capsule_bottom_offset
	)
	var best_gap: float = INF
	var best_point: Vector3 = Vector3.ZERO
	var best_normal: Vector3 = Vector3.UP

	for offset: Vector3 in probe_offsets:
		var ray_from: Vector3 = player.global_position + offset
		ray_from.y = capsule_bottom_y + PROBE_START_MARGIN
		var ray_to: Vector3 = ray_from
		ray_to.y = capsule_bottom_y - support_check_distance

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
		if not is_walkable_surface(normal):
			continue

		var point: Vector3 = point_value
		var gap: float = maxf(0.0, ray_from.y - point.y)
		if gap >= best_gap:
			continue

		best_gap = gap
		best_point = point
		best_normal = normal

	if best_gap == INF:
		return

	has_support = true
	walkable = true
	support_point = best_point
	support_normal = best_normal


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
