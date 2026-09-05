class_name PlayerStepUp
extends RefCounted


const PROBE_SAFE_MARGIN: float = 0.001
const PROBE_MAX_COLLISIONS: int = 8


class StepPlan:
	var riser_point: Vector3 = Vector3.ZERO
	var riser_normal: Vector3 = Vector3.ZERO
	var riser_collider_rid: RID = RID()
	var riser_shape_index: int = -1
	var landing_position: Vector3 = Vector3.ZERO
	var riser_cleared: bool = false


var max_step_height: float
var max_riser_tilt_degrees: float
var step_up_acceleration: float
var max_step_up_speed: float
var collision_shape: CollisionShape3D

var active_plan: StepPlan = null


func _init(
	p_max_step_height: float,
	p_max_riser_tilt_degrees: float,
	p_step_up_acceleration: float,
	p_max_step_up_speed: float,
	p_collision_shape: CollisionShape3D
) -> void:
	max_step_height = p_max_step_height
	max_riser_tilt_degrees = p_max_riser_tilt_degrees
	step_up_acceleration = p_step_up_acceleration
	max_step_up_speed = p_max_step_up_speed
	collision_shape = p_collision_shape

	assert(
		step_up_acceleration > 0.0,
		"PlayerStepUp requires step_up_acceleration to be greater than zero."
	)
	assert(
		max_step_up_speed > 0.0,
		"PlayerStepUp requires max_step_up_speed to be greater than zero."
	)

	get_capsule_radius()


func is_active() -> bool:
	return active_plan != null


func try_start_step(
	player: CharacterBody3D,
	horizontal_motion: Vector3,
	input_direction: Vector3,
	support: PlayerSupport
) -> void:
	if is_active():
		return

	if input_direction.is_zero_approx():
		return

	if horizontal_motion.length_squared() <= 0.000001:
		return

	if not support.walkable:
		return

	var plan: StepPlan = validate_step(
		player,
		horizontal_motion,
		support
	)

	if plan == null:
		return

	var input_push: float = -input_direction.dot(
		plan.riser_normal
	)

	if input_push <= 0.0:
		return

	active_plan = plan


func update_traversal(
	player: CharacterBody3D,
	input_direction: Vector3,
	support: PlayerSupport,
	delta: float
) -> void:
	if active_plan == null:
		return

	if not active_plan.riser_cleared:
		active_plan.riser_cleared = has_crossed_riser(
			player,
			active_plan
		)

	if active_plan.riser_cleared:
		if support.has_support and support.walkable:
			active_plan = null

		return

	if input_direction.is_zero_approx():
		cancel_traversal()
		return

	var input_push: float = -input_direction.dot(
		active_plan.riser_normal
	)

	if input_push <= 0.0:
		cancel_traversal()
		return

	var target_y: float = (
		active_plan.landing_position.y
		+ PROBE_SAFE_MARGIN
	)
	var remaining_height: float = maxf(
		0.0,
		target_y - player.global_position.y
	)
	var braking_speed: float = sqrt(
		2.0
		* step_up_acceleration
		* remaining_height
	)
	var target_vertical_speed: float = minf(
		max_step_up_speed,
		braking_speed
	)

	player.velocity.y = move_toward(
		player.velocity.y,
		target_vertical_speed,
		step_up_acceleration * delta
	)


func should_preserve_velocity(
	collision: KinematicCollision3D
) -> bool:
	if active_plan == null:
		return false

	if active_plan.riser_cleared:
		return false

	if (
		collision.get_collider_rid()
		!= active_plan.riser_collider_rid
	):
		return false

	if (
		collision.get_collider_shape_index()
		!= active_plan.riser_shape_index
	):
		return false

	var collision_normal: Vector3 = collision.get_normal()
	return (
		collision_normal.dot(active_plan.riser_normal)
		> 0.0
	)


func validate_step(
	player: CharacterBody3D,
	horizontal_motion: Vector3,
	support: PlayerSupport
) -> StepPlan:
	var horizontal_direction: Vector3 = horizontal_motion.normalized()
	var collision: KinematicCollision3D = KinematicCollision3D.new()
	var blocked: bool = player.test_move(
		player.global_transform,
		horizontal_motion,
		collision,
		PROBE_SAFE_MARGIN,
		false,
		PROBE_MAX_COLLISIONS
	)

	if not blocked:
		return null

	var candidate_riser_point: Vector3 = Vector3.ZERO
	var candidate_riser_normal: Vector3 = Vector3.ZERO
	var candidate_riser_collider_rid: RID = RID()
	var candidate_riser_shape_index: int = -1
	var candidate_push_strength: float = 0.0
	var collision_count: int = collision.get_collision_count()

	for collision_index: int in range(collision_count):
		var collision_normal: Vector3 = collision.get_normal(
			collision_index
		)

		if support.is_walkable_surface(collision_normal):
			continue

		if not is_step_riser(collision_normal):
			continue

		var horizontal_normal: Vector3 = Vector3(
			collision_normal.x,
			0.0,
			collision_normal.z
		)

		if horizontal_normal.length_squared() <= 0.000001:
			continue

		horizontal_normal = horizontal_normal.normalized()

		var push_strength: float = -horizontal_direction.dot(
			horizontal_normal
		)

		if push_strength <= candidate_push_strength:
			continue

		candidate_push_strength = push_strength
		candidate_riser_point = collision.get_position(
			collision_index
		)
		candidate_riser_normal = horizontal_normal
		candidate_riser_collider_rid = collision.get_collider_rid(
			collision_index
		)
		candidate_riser_shape_index = (
			collision.get_collider_shape_index(
				collision_index
			)
		)

	if candidate_push_strength <= 0.0:
		return null

	var up_motion: Vector3 = get_up_motion()

	if not test_up_clearance(player, up_motion):
		return null

	var raised_transform: Transform3D = (
		player.global_transform.translated(up_motion)
	)
	var across_motion: Vector3 = get_across_motion(
		horizontal_direction,
		candidate_push_strength
	)

	if not test_across_clearance(
		player,
		raised_transform,
		across_motion
	):
		return null

	var across_transform: Transform3D = (
		raised_transform.translated(across_motion)
	)
	var down_collision: KinematicCollision3D = (
		find_valid_down_landing(
			player,
			support,
			across_transform
		)
	)

	if down_collision == null:
		return null

	var landing_transform: Transform3D = (
		across_transform.translated(
			down_collision.get_travel()
		)
	)

	var plan: StepPlan = StepPlan.new()
	plan.riser_point = candidate_riser_point
	plan.riser_normal = candidate_riser_normal
	plan.riser_collider_rid = candidate_riser_collider_rid
	plan.riser_shape_index = candidate_riser_shape_index
	plan.landing_position = landing_transform.origin

	return plan


func test_up_clearance(
	player: CharacterBody3D,
	up_motion: Vector3
) -> bool:
	return not player.test_move(
		player.global_transform,
		up_motion,
		null,
		PROBE_SAFE_MARGIN,
		false,
		1
	)


func test_across_clearance(
	player: CharacterBody3D,
	raised_transform: Transform3D,
	across_motion: Vector3
) -> bool:
	return not player.test_move(
		raised_transform,
		across_motion,
		null,
		PROBE_SAFE_MARGIN,
		false,
		1
	)


func find_valid_down_landing(
	player: CharacterBody3D,
	support: PlayerSupport,
	across_transform: Transform3D
) -> KinematicCollision3D:
	var down_motion: Vector3 = Vector3.DOWN * (
		get_up_motion().y + PROBE_SAFE_MARGIN
	)
	var collision: KinematicCollision3D = KinematicCollision3D.new()
	var blocked: bool = player.test_move(
		across_transform,
		down_motion,
		collision,
		PROBE_SAFE_MARGIN,
		false,
		PROBE_MAX_COLLISIONS
	)

	if not blocked:
		return null

	var has_walkable_landing: bool = false
	var collision_count: int = collision.get_collision_count()

	for collision_index: int in range(collision_count):
		var collision_normal: Vector3 = collision.get_normal(
			collision_index
		)

		if support.is_walkable_surface(collision_normal):
			has_walkable_landing = true
			break

	if not has_walkable_landing:
		return null

	var landing_transform: Transform3D = (
		across_transform.translated(
			collision.get_travel()
		)
	)
	var rise: float = (
		landing_transform.origin.y
		- player.global_transform.origin.y
	)

	if rise <= PROBE_SAFE_MARGIN:
		return null

	if rise > max_step_height + PROBE_SAFE_MARGIN:
		return null

	return collision


func has_crossed_riser(
	player: CharacterBody3D,
	plan: StepPlan
) -> bool:
	var plane_distance: float = (
		(player.global_position - plan.riser_point).dot(
			plan.riser_normal
		)
	)

	return plane_distance <= -PROBE_SAFE_MARGIN


func cancel_traversal() -> void:
	active_plan = null


func get_up_motion() -> Vector3:
	return Vector3.UP * (
		max_step_height + PROBE_SAFE_MARGIN
	)


func get_across_motion(
	horizontal_direction: Vector3,
	push_strength: float
) -> Vector3:
	var across_distance: float = (
		get_capsule_radius() + PROBE_SAFE_MARGIN
	) / push_strength

	return horizontal_direction * across_distance


func is_step_riser(
	normal: Vector3
) -> bool:
	var maximum_normal_y: float = sin(
		deg_to_rad(max_riser_tilt_degrees)
	)

	return absf(normal.y) <= maximum_normal_y


func get_capsule_radius() -> float:
	var shape: Shape3D = collision_shape.shape
	assert(
		shape is CapsuleShape3D,
		"PlayerStepUp requires the player collision shape to be CapsuleShape3D."
	)

	var capsule_shape: CapsuleShape3D = shape as CapsuleShape3D
	return capsule_shape.radius
