class_name PlayerStepUp
extends RefCounted


var max_step_height: float
var clearance_epsilon: float
var floor_max_angle: float
var push_threshold: float

var debug_enabled: bool = false


func _init(
	p_max_step_height: float,
	p_clearance_epsilon: float,
	p_floor_max_angle: float,
	p_push_threshold: float
) -> void:
	max_step_height = p_max_step_height
	clearance_epsilon = p_clearance_epsilon
	floor_max_angle = p_floor_max_angle
	push_threshold = p_push_threshold


func try_step(
	player: CharacterBody3D,
	start_transform: Transform3D,
	horizontal_motion: Vector3,
	input_direction: Vector3,
	blocking_collision: KinematicCollision3D
) -> Vector3:
	if horizontal_motion.length_squared() <= 0.000001:
		return Vector3.ZERO

	var horizontal_direction: Vector3 = horizontal_motion.normalized()

	# --------------------------------------------------
	# 1. Validate that we are actually pushing into the
	#    blocking surface.
	# --------------------------------------------------

	var collision_normal: Vector3 = blocking_collision.get_normal()

	var push_strength: float = (
		-horizontal_direction.dot(collision_normal)
	)

	if push_strength < push_threshold:
		debug("REJECT: not pushing into obstacle")
		return Vector3.ZERO

	# --------------------------------------------------
	# 2. Do not step onto walkable slopes.
	#
	#    Walkable slopes are handled by normal movement.
	# --------------------------------------------------

	if is_walkable_normal(collision_normal):
		debug("REJECT: walkable slope")
		return Vector3.ZERO

	# --------------------------------------------------
	# 3. Your 0.5 + epsilon clearance check.
	#
	#    The important point here is that this is only a
	#    candidate filter. The actual UP movement below
	#    is still collision tested.
	# --------------------------------------------------

	if is_height_blocked(
		player,
		start_transform,
		horizontal_direction
	):
		debug("REJECT: height probe blocked")
		return Vector3.ZERO

	# --------------------------------------------------
	# 4. TEST UP
	# --------------------------------------------------

	var up_motion: Vector3 = Vector3.UP * (
		max_step_height + clearance_epsilon
	)

	if player.test_move(
		start_transform,
		up_motion
	):
		debug("REJECT: upward movement blocked")
		return Vector3.ZERO

	var raised_transform: Transform3D = (
		start_transform.translated(up_motion)
	)

	# --------------------------------------------------
	# 5. TEST FORWARD
	# --------------------------------------------------

	if player.test_move(
		raised_transform,
		horizontal_motion
	):
		debug("REJECT: forward movement blocked")
		return Vector3.ZERO

	var forward_transform: Transform3D = (
		raised_transform.translated(horizontal_motion)
	)

	# --------------------------------------------------
	# 6. TEST DOWN
	#
	#    We descend max step height plus epsilon.
	#
	#    We need an actual collision here because the
	#    resulting collision normal tells us whether the
	#    surface is walkable.
	# --------------------------------------------------

	var down_motion: Vector3 = Vector3.DOWN * (
		max_step_height
		+ clearance_epsilon * 2.0
	)

	var down_collision: KinematicCollision3D = (
		KinematicCollision3D.new()
	)

	var hit_down: bool = player.test_move(
		forward_transform,
		down_motion,
		down_collision
	)

	if not hit_down:
		debug("REJECT: no ground below step")
		return Vector3.ZERO

	var landing_normal: Vector3 = (
		down_collision.get_normal()
	)

	if not is_walkable_normal(landing_normal):
		debug("REJECT: landing surface not walkable")
		return Vector3.ZERO

	# --------------------------------------------------
	# SUCCESS
	#
	# Calculate the exact motion that reaches the
	# collision point returned by the downward test.
	#
	# The upward and forward motion are fully known.
	# For DOWN we use travel rather than the entire
	# requested downward motion.
	# --------------------------------------------------

	var down_travel: Vector3 = (
		down_collision.get_travel()
	)

	var total_motion: Vector3 = (
		up_motion
		+ horizontal_motion
		+ down_travel
	)

	debug("STEP SUCCESS")
	debug("  up: " + str(up_motion))
	debug("  forward: " + str(horizontal_motion))
	debug("  down: " + str(down_travel))
	debug("  total: " + str(total_motion))

	return total_motion


func is_walkable_normal(
	normal: Vector3
) -> bool:
	var minimum_floor_y: float = (
		cos(floor_max_angle)
	)

	return normal.y >= minimum_floor_y


func is_height_blocked(
	player: CharacterBody3D,
	start_transform: Transform3D,
	horizontal_direction: Vector3
) -> bool:
	var probe_height: float = (
		max_step_height
		+ clearance_epsilon
	)

	var probe_origin: Vector3 = (
		start_transform.origin
		+ Vector3.UP * probe_height
	)

	var probe_distance: float = (
		get_capsule_radius(player)
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


func get_capsule_radius(
	player: CharacterBody3D
) -> float:
	# Replace this if your radius is already stored in
	# Player.gd and passed into this class.
	#
	# For now this assumes the first CollisionShape3D
	# child contains a CapsuleShape3D.

	for child in player.get_children():
		if child is CollisionShape3D:
			var shape: Shape3D = child.shape

			if shape is CapsuleShape3D:
				return shape.radius

	return 0.0


func debug(
	message: String
) -> void:
	if debug_enabled:
		print("STEP: ", message)
