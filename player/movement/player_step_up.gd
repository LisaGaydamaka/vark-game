class_name PlayerStepUp
extends RefCounted


const PROBE_SAFE_MARGIN: float = 0.001
const PROBE_MAX_COLLISIONS: int = 8


var max_step_height: float
var clearance_epsilon: float
var max_walkable_slope_degrees: float
var push_threshold: float
var capsule_radius: float
var contact_epsilon: float

var debug_enabled: bool = true


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
	input_direction: Vector3
) -> bool:
	if not support.has_support:
		return false

	if player.velocity.y > 0.0:
		return false

	if horizontal_motion.length_squared() <= 0.000001:
		return false

	var horizontal_input: Vector3 = Vector3(
		input_direction.x,
		0.0,
		input_direction.z
	)

	if horizontal_input.length_squared() <= 0.000001:
		return false

	horizontal_input = horizontal_input.normalized()

	var start_transform: Transform3D = player.global_transform
	var probe_collision: KinematicCollision3D = KinematicCollision3D.new()

	var probe_hit: bool = player.test_move(
		start_transform,
		horizontal_motion,
		probe_collision,
		PROBE_SAFE_MARGIN,
		false,
		PROBE_MAX_COLLISIONS
	)

	if not probe_hit:
		return false

	var collision_count: int = probe_collision.get_collision_count()

	debug("--- horizontal probe blocked ---")
	debug("player position: " + str(player.global_position))
	debug("horizontal motion: " + str(horizontal_motion))
	debug("collision count: " + str(collision_count))
	debug("support point: " + str(support.support_point))

	var max_contact_y: float = (
		support.support_point.y
		+ capsule_radius
		+ contact_epsilon
	)

	var candidate_index: int = -1
	var candidate_push_strength: float = push_threshold

	for collision_index: int in range(collision_count):
		var collision_normal: Vector3 = (
			probe_collision.get_normal(collision_index)
		)

		var collision_position: Vector3 = (
			probe_collision.get_position(collision_index)
		)

		var push_strength: float = (
			-horizontal_input.dot(collision_normal)
		)

		var walkable: bool = is_walkable_normal(collision_normal)
		var contact_is_low: bool = collision_position.y <= max_contact_y

		debug(
			"contact "
			+ str(collision_index)
			+ ": position="
			+ str(collision_position)
			+ " normal="
			+ str(collision_normal)
			+ " push="
			+ str(push_strength)
			+ " walkable="
			+ str(walkable)
			+ " low="
			+ str(contact_is_low)
		)

		if walkable:
			continue

		if push_strength < push_threshold:
			continue

		if not contact_is_low:
			continue

		if (
			candidate_index == -1
			or push_strength > candidate_push_strength
		):
			candidate_index = collision_index
			candidate_push_strength = push_strength

	if candidate_index == -1:
		debug("REJECT: horizontal probe has no valid step contact")
		return false

	var candidate_normal: Vector3 = (
		probe_collision.get_normal(candidate_index)
	)

	var candidate_position: Vector3 = (
		probe_collision.get_position(candidate_index)
	)

	debug("selected contact: " + str(candidate_index))
	debug("selected position: " + str(candidate_position))
	debug("selected normal: " + str(candidate_normal))
	debug("selected push: " + str(candidate_push_strength))
	debug("max contact y: " + str(max_contact_y))

	var horizontal_direction: Vector3 = horizontal_motion.normalized()

	if is_height_blocked(
		player,
		support,
		horizontal_direction
	):
		debug("REJECT: height probe blocked")
		return false

	var up_motion: Vector3 = Vector3.UP * (
		max_step_height + clearance_epsilon
	)

	debug("TEST UP: " + str(up_motion))

	if player.test_move(
		start_transform,
		up_motion,
		null,
		PROBE_SAFE_MARGIN,
		false,
		1
	):
		debug("REJECT: upward path blocked")
		return false

	debug("UP CLEAR")

	var raised_transform: Transform3D = (
		start_transform.translated(up_motion)
	)

	debug("TEST FORWARD: " + str(horizontal_motion))

	if player.test_move(
		raised_transform,
		horizontal_motion,
		null,
		PROBE_SAFE_MARGIN,
		false,
		1
	):
		debug("REJECT: forward path blocked while raised")
		return false

	debug("FORWARD CLEAR")

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

	debug("TEST DOWN: " + str(down_motion))

	var hit_ground: bool = player.test_move(
		forward_transform,
		down_motion,
		down_collision,
		PROBE_SAFE_MARGIN,
		false,
		PROBE_MAX_COLLISIONS
	)

	if not hit_ground:
		debug("REJECT: no landing surface")
		return false

	var down_collision_count: int = (
		down_collision.get_collision_count()
	)

	var landing_is_walkable: bool = false
	var landing_normal: Vector3 = Vector3.ZERO

	for collision_index: int in range(down_collision_count):
		var test_normal: Vector3 = (
			down_collision.get_normal(collision_index)
		)

		debug(
			"landing contact "
			+ str(collision_index)
			+ ": position="
			+ str(down_collision.get_position(collision_index))
			+ " normal="
			+ str(test_normal)
		)

		if is_walkable_normal(test_normal):
			landing_is_walkable = true
			landing_normal = test_normal
			break

	if not landing_is_walkable:
		debug("REJECT: landing surface is not walkable")
		return false

	var down_travel: Vector3 = down_collision.get_travel()
	var vertical_gain: float = up_motion.y + down_travel.y

	debug("landing normal: " + str(landing_normal))
	debug("down travel: " + str(down_travel))
	debug("vertical gain: " + str(vertical_gain))

	if vertical_gain <= clearance_epsilon:
		debug("REJECT: landing is not higher")
		return false

	if vertical_gain > max_step_height + clearance_epsilon:
		debug("REJECT: landing exceeds max step height")
		return false

	player.move_and_collide(
		up_motion,
		false,
		PROBE_SAFE_MARGIN,
		false,
		1
	)

	player.move_and_collide(
		horizontal_motion,
		false,
		PROBE_SAFE_MARGIN,
		false,
		1
	)

	player.move_and_collide(
		down_motion,
		false,
		PROBE_SAFE_MARGIN,
		false,
		PROBE_MAX_COLLISIONS
	)

	debug("STEP COMMITTED")
	debug("final player position: " + str(player.global_position))

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

	debug("height probe origin: " + str(probe_origin))
	debug("height probe end: " + str(probe_end))

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

	if result.is_empty():
		debug("HEIGHT CLEAR")
		return false

	debug(
		"HEIGHT BLOCKED at: "
		+ str(result.get("position", Vector3.ZERO))
	)

	return true


func debug(
	message: String
) -> void:
	if debug_enabled:
		print("STEP: ", message)
