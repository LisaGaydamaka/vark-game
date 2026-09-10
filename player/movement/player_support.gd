class_name PlayerSupport
extends RefCounted


const MOTION_EPSILON_SQUARED: float = 0.000001
const SUPPORT_SEPARATION_EPSILON: float = 0.0001
const SUPPORT_CONTACT_SAFE_MARGIN: float = 0.001
const SUPPORT_CONTACT_MAX_COLLISIONS: int = 8
const PROBE_START_MARGIN: float = 0.01
const FOOT_PROBE_RADIUS_RATIO: float = 0.55
const MINIMUM_NORMAL_Y: float = 0.0001
const MAXIMUM_STEEP_SUPPORT_SLOPE_DEGREES: float = 75.0


class SupportCandidate:
	var valid: bool = false
	var separation: float = INF
	var point: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.UP


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

	# Footprint probes identify the stable support surface beneath the capsule.
	# Capsule contacts are fallback support for narrow/tangent geometry that the
	# footprint cannot sample. This distinction prevents an obstacle edge touched
	# during locomotion from replacing the floor that actually supports the body.
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
	# state transition instead of something a nearby contact/probe can undo.
	if walkable_support_released and player.velocity.y <= SUPPORT_SEPARATION_EPSILON:
		walkable_support_released = false

	# Stable footprint support has semantic priority over incidental capsule
	# contacts. In particular, touching a stair edge must not replace the source
	# floor used to measure a support-to-support step transition. If the footprint
	# has no valid support, fall back to the live capsule contact manifold so
	# narrow rails/edges can still bear the player.
	var best := SupportCandidate.new()
	_find_ray_support(player, best)
	if not best.valid:
		_find_capsule_contact_support(player, best)

	if not best.valid:
		return

	has_support = true
	walkable = is_walkable_surface(best.normal)
	support_point = best.point
	support_normal = best.normal


func _find_capsule_contact_support(
	player: CharacterBody3D,
	best: SupportCandidate
) -> void:
	# test_move() uses the body's live collider and reports both the short
	# downward sweep and recovery/touching contacts without changing the body.
	# This makes exact edge tangency a real support candidate instead of relying
	# on whether one of the foot rays happens to land on a narrow top face.
	var collision := KinematicCollision3D.new()
	var probe_distance: float = maxf(
		support_check_distance + SUPPORT_SEPARATION_EPSILON,
		SUPPORT_SEPARATION_EPSILON
	)
	var blocked: bool = player.test_move(
		player.global_transform,
		Vector3.DOWN * probe_distance,
		collision,
		SUPPORT_CONTACT_SAFE_MARGIN,
		true,
		SUPPORT_CONTACT_MAX_COLLISIONS
	)
	if not blocked:
		return

	for collision_index: int in range(collision.get_collision_count()):
		_consider_support_candidate(
			player,
			collision.get_position(collision_index),
			collision.get_normal(collision_index),
			best
		)


func _find_ray_support(
	player: CharacterBody3D,
	best: SupportCandidate
) -> void:
	var capsule_bottom_y: float = player.global_position.y + capsule_bottom_offset
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
		var point: Vector3 = point_value
		var normal: Vector3 = normal_value

		_consider_support_candidate(
			player,
			point,
			normal,
			best
		)


func _consider_support_candidate(
	player: CharacterBody3D,
	point: Vector3,
	normal: Vector3,
	best: SupportCandidate
) -> void:
	if normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return
	normal = normal.normalized()
	if not is_support_surface(normal):
		return

	var separation: float = _get_capsule_plane_separation(
		player,
		point,
		normal
	)
	if separation > support_check_distance + SUPPORT_SEPARATION_EPSILON:
		return

	var candidate_walkable: bool = is_walkable_surface(normal)
	if candidate_walkable:
		# Persistent Y is ballistic in this controller. A walkable plane cannot
		# reacquire support while that ballistic state is moving upward, even if
		# the plane remains inside snap/proximity distance for a frame or two.
		if (
			walkable_support_released
			or player.velocity.y > SUPPORT_SEPARATION_EPSILON
		):
			return
	else:
		# Steep support uses full 3D surface velocity. If that velocity is moving
		# away from the candidate plane, the unilateral contact is released.
		var normal_velocity: float = player.velocity.dot(normal)
		if normal_velocity > SUPPORT_SEPARATION_EPSILON:
			return

	var ranking_separation: float = maxf(0.0, separation)
	if best.valid and ranking_separation >= best.separation:
		return

	best.valid = true
	best.separation = ranking_separation
	best.point = point
	best.normal = normal


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
