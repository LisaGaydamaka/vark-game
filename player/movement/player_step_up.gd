class_name PlayerStepUp
extends RefCounted


var max_step_height: float
var clearance_epsilon: float
var max_walkable_slope_degrees: float
var push_threshold: float
var capsule_radius: float
var contact_epsilon: float

var debug_enabled: bool = false


func _init(
	p_max_step_height: float,
	p_clearance_epsilon: float,
	p_max_walkable_slope_degrees: float,
	p_push_threshold: float,
	p_capsule_radius: float,
	p_contact_epsilon: float
) -> void:
	max_step_height = p_max_step_height
	clearance_epsilon = p_clearance_epsilon
	max_walkable_slope_degrees = p_max_walkable_slope_degrees
	push_threshold = p_push_threshold
	capsule_radius = p_capsule_radius
	contact_epsilon = p_contact_epsilon


func try_step(
	player: CharacterBody3D,
	support: PlayerSupport,
	horizontal_motion: Vector3,
	input_direction: Vector3,
	blocking_collision: KinematicCollision3D
) -> bool:
	if not support.has_support:
		debug("REJECT: no support")
		return false

	if horizontal_motion.length_squared() <= 0.000001:
		return false

	var horizontal_direction: Vector3 = horizontal_motion.normalized()

	var horizontal_input: Vector3 = Vector3(
		input_direction.x,
		0.0,
		input_direction.z
	)

	if horizontal_input.length_squared() <= 0.000001:
		return false

	horizontal_input = horizontal_input.normalized()

	var collision_normal: Vector3 = blocking_collision.get_normal()
	var push_strength: float = -horizontal_input.dot(collision_normal)

	if push_strength < push_threshold:
		debug("REJECT: not pushing into obstacle")
		return false

	var max_contact_y: float = (
		support.support_point.y
		+ capsule_radius
		+ contact_epsilon
	)

	if blocking_collision.get_position().y > max_contact_y:
		debug("REJECT: contact too high")
		return false

	if is_walkable_normal(collision_normal):
		debug("REJECT: walkable slope")
		return false

	if is_height_blocked(
		player,
		support,
		horizontal_direction
	):
		debug("REJECT: height probe blocked")
		return false

	var start_transform: Transform3D = player.global_transform

	var up_motion: Vector3 = Vector3.UP * (
		max_step_height + clearance_epsilon
	)

	if player.test_move(
		start_transform,
		up_motion
	):
		debug("REJECT: upward path blocked")
		return false

	var raised_transform: Transform3D = (
		start_transform.translated(up_motion)
	)

	if player.test_move(
		raised_transform,
		horizontal_motion
	):
		debug("REJECT: forward path blocked while raised")
		return false

	var forward_transform: Transform3D = (
		raised_transform.translated(horizontal_motion)
	)

	var down_motion: Vector3 = Vector3.DOWN * (
		max_step_height
		+ clearance_epsilon * 2.0
	)

	var down_collision: KinematicCollision3D = (
		KinematicCollision3D.new()
	)

	var hit_ground: bool = player.test_move(
		forward_transform,
		down_motion,
		down_collision
	)

	if not hit_ground:
		debug("REJECT: no landing surface")
		return false

	var landing_normal: Vector3 = down_collision.get_normal()

	if not is_walkable_normal(landing_normal):
		debug("REJECT: landing surface is not walkable")
		return false

	var down_travel: Vector3 = down_collision.get_travel()
	var vertical_gain: float = up_motion.y + down_travel.y

	if vertical_gain <= clearance_epsilon:
		debug("REJECT: landing is not higher")
		return false

	if vertical_gain > max_step_height + clearance_epsilon:
		debug("REJECT: landing exceeds max step height")
		return false

	player.move_and_collide(up_motion)
	player.move_and_collide(horizontal_motion)
	player.move_and_collide(down_motion)

	debug("STEP SUCCESS")
	debug("  vertical gain: " + str(vertical_gain))

	return true


func is_walkable_normal(
	normal: Vector3
) -> bool:
	var minimum_normal_y: float = cos(
		deg_to_rad(max_walkable_slope_degrees)
	)

	return normal.y >= minimum_normal_y - 0.00001


func is_height_blocked(
	player: CharacterBody3D,
	support: PlayerSupport,
	horizontal_direction: Vector3
) -> bool:
	var probe_height: float = (
		support.support_point.y
		+ max_step_height
		+ clearance_epsilon
	)

	var probe_origin: Vector3 = Vector3(
		player.global_position.x,
		probe_height,
		player.global_position.z
	)

	var probe_distance: float = (
		capsule_radius
		+ clearance_epsilon
	)

	var probe_end: Vector3 = (
		probe_origin
		+ horizontal_direction * probe_distance
	)

	var query: PhysicsRayQueryParameters3D = (
		PhysicsRayQueryParameters3D.create(
			probe_origin,
			probe_end
		)
	)

	query.exclude = [
		player.get_rid()
	]

	var result: Dictionary = (
		player
		.get_world_3d()
		.direct_space_state
		.intersect_ray(query)
	)

	return not result.is_empty()


func debug(
	message: String
) -> void:
	if debug_enabled:
		print("STEP: ", message)
