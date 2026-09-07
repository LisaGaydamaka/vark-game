class_name PlayerStepUp
extends RefCounted


const PROBE_SAFE_MARGIN: float = 0.001
const PROBE_MAX_COLLISIONS: int = 8
const MOTION_EPSILON_SQUARED: float = 0.000001
const MAX_CLEARANCE_ITERATIONS: int = 8
const LANDING_HEIGHT_SAMPLE_COUNT: int = 12
const MIN_STEP_APPROACH_DOT: float = 0.1


class StepPlan:
	var riser_point: Vector3 = Vector3.ZERO
	var riser_normal: Vector3 = Vector3.ZERO
	var riser_collider_rid: RID = RID()
	var riser_shape_index: int = -1
	var landing_position: Vector3 = Vector3.ZERO


class MotionResolution:
	var transform: Transform3D = Transform3D.IDENTITY


class LandingResult:
	var transform: Transform3D = Transform3D.IDENTITY
	var contact_point: Vector3 = Vector3.ZERO


var max_step_height: float
var max_riser_tilt_degrees: float
var step_up_acceleration: float
var max_step_up_speed: float
var collision_shape: CollisionShape3D

var active_plan: StepPlan = null
var vertical_assist_speed: float = 0.0


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


func is_active() -> bool:
	return active_plan != null


func try_start_step(
	player: CharacterBody3D,
	horizontal_motion: Vector3,
	input_direction: Vector3,
	support: PlayerSupport
) -> bool:
	if is_active():
		return false

	if input_direction.is_zero_approx():
		return false

	if horizontal_motion.length_squared() <= MOTION_EPSILON_SQUARED:
		return false

	var plan: StepPlan = find_best_step_plan(
		player,
		horizontal_motion,
		input_direction,
		support
	)
	if plan == null:
		return false

	active_plan = plan
	vertical_assist_speed = 0.0
	return true


func update_traversal(
	player: CharacterBody3D,
	input_direction: Vector3,
	delta: float
) -> void:
	if active_plan == null:
		return

	if has_crossed_riser(player.global_position, active_plan):
		cancel_traversal()
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

	vertical_assist_speed = move_toward(
		vertical_assist_speed,
		target_vertical_speed,
		step_up_acceleration * delta
	)


func get_motion_velocity(base_velocity: Vector3) -> Vector3:
	if active_plan == null:
		return base_velocity

	var motion_velocity: Vector3 = base_velocity
	motion_velocity.y = maxf(
		base_velocity.y,
		vertical_assist_speed
	)
	return motion_velocity


func refresh_after_move(player: CharacterBody3D) -> void:
	if active_plan == null:
		return
	if has_crossed_riser(player.global_position, active_plan):
		cancel_traversal()


func should_preserve_velocity(
	collision: KinematicCollision3D
) -> bool:
	if active_plan == null or collision == null:
		return false

	for collision_index: int in range(collision.get_collision_count()):
		if (
			collision.get_collider_rid(collision_index)
			!= active_plan.riser_collider_rid
		):
			continue
		if (
			collision.get_collider_shape_index(collision_index)
			!= active_plan.riser_shape_index
		):
			continue

		var collision_normal: Vector3 = collision.get_normal(collision_index)
		if collision_normal.dot(active_plan.riser_normal) > 0.0:
			return true
	return false


func is_vertical_assist_blocked(
	collision: KinematicCollision3D,
	base_velocity: Vector3
) -> bool:
	if active_plan == null or collision == null:
		return false
	if vertical_assist_speed <= base_velocity.y + 0.000001:
		return false

	for collision_index: int in range(collision.get_collision_count()):
		var normal: Vector3 = collision.get_normal(collision_index)
		if normal.y < -0.05:
			return true
	return false


func find_best_step_plan(
	player: CharacterBody3D,
	horizontal_motion: Vector3,
	input_direction: Vector3,
	support: PlayerSupport
) -> StepPlan:
	var horizontal_direction: Vector3 = horizontal_motion.normalized()
	var collision := KinematicCollision3D.new()
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

	var best_plan: StepPlan = null
	var best_push_strength: float = 0.0
	var best_rise: float = INF
	var collision_count: int = collision.get_collision_count()

	for collision_index: int in range(collision_count):
		var collision_normal: Vector3 = collision.get_normal(collision_index)
		if support.is_walkable_surface(collision_normal):
			continue
		if not is_step_riser(collision_normal):
			continue

		var horizontal_normal := Vector3(
			collision_normal.x,
			0.0,
			collision_normal.z
		)
		if horizontal_normal.length_squared() <= MOTION_EPSILON_SQUARED:
			continue
		horizontal_normal = horizontal_normal.normalized()

		var push_strength: float = -horizontal_direction.dot(horizontal_normal)
		if push_strength < MIN_STEP_APPROACH_DOT:
			continue
		if -input_direction.dot(horizontal_normal) <= 0.0:
			continue

		var plan: StepPlan = build_step_plan(
			player,
			support,
			horizontal_direction,
			push_strength,
			collision.get_position(collision_index),
			horizontal_normal,
			collision.get_collider_rid(collision_index),
			collision.get_collider_shape_index(collision_index)
		)
		if plan == null:
			continue

		var rise: float = get_capsule_bottom_y_from_position(plan.landing_position.y) - get_capsule_bottom_y(player.global_transform)
		if (
			best_plan == null
			or push_strength > best_push_strength + 0.000001
			or (
				absf(push_strength - best_push_strength) <= 0.000001
				and rise < best_rise
			)
		):
			best_plan = plan
			best_push_strength = push_strength
			best_rise = rise

	return best_plan


func build_step_plan(
	player: CharacterBody3D,
	support: PlayerSupport,
	horizontal_direction: Vector3,
	push_strength: float,
	riser_point: Vector3,
	riser_normal: Vector3,
	riser_collider_rid: RID,
	riser_shape_index: int
) -> StepPlan:
	var across_motion: Vector3 = get_across_motion(
		horizontal_direction,
		push_strength
	)
	var landing: LandingResult = find_landing_from_above(
		player,
		support,
		riser_point,
		riser_normal,
		across_motion
	)
	if landing == null:
		return null

	var current_bottom_y: float = get_capsule_bottom_y(player.global_transform)
	var landing_bottom_y: float = get_capsule_bottom_y(landing.transform)
	var rise: float = landing_bottom_y - current_bottom_y
	if rise <= PROBE_SAFE_MARGIN:
		return null
	if rise > max_step_height + PROBE_SAFE_MARGIN:
		return null

	# The search ceiling only discovers the landing. The live route is validated
	# against the exact height that landing actually requires.
	var target_y: float = landing.transform.origin.y + PROBE_SAFE_MARGIN
	var required_up_distance: float = maxf(
		0.0,
		target_y - player.global_position.y
	)
	var raised: MotionResolution = resolve_motion(
		player,
		player.global_transform,
		Vector3.UP * required_up_distance
	)
	if raised.transform.origin.y < target_y - PROBE_SAFE_MARGIN:
		return null

	var crossed: MotionResolution = resolve_motion(
		player,
		raised.transform,
		across_motion
	)
	if not has_transform_crossed_riser(
		crossed.transform,
		riser_point,
		riser_normal
	):
		return null

	var plan := StepPlan.new()
	plan.riser_point = riser_point
	plan.riser_normal = riser_normal
	plan.riser_collider_rid = riser_collider_rid
	plan.riser_shape_index = riser_shape_index
	plan.landing_position = landing.transform.origin
	return plan


func find_landing_from_above(
	player: CharacterBody3D,
	support: PlayerSupport,
	riser_point: Vector3,
	riser_normal: Vector3,
	across_motion: Vector3
) -> LandingResult:
	var current_bottom_y: float = get_capsule_bottom_y(player.global_transform)

	# Search from the capsule-relative maximum downward. These sampled transforms
	# discover geometry only; they do not imply that traversal must rise this far.
	for sample_index: int in range(LANDING_HEIGHT_SAMPLE_COUNT):
		var sample_fraction: float = float(
			LANDING_HEIGHT_SAMPLE_COUNT - sample_index
		) / float(LANDING_HEIGHT_SAMPLE_COUNT)
		var sample_height: float = (
			max_step_height * sample_fraction
			+ PROBE_SAFE_MARGIN
		)
		var raised_transform: Transform3D = player.global_transform.translated(
			Vector3.UP * sample_height
		)
		var across: MotionResolution = resolve_motion(
			player,
			raised_transform,
			across_motion
		)
		if not has_transform_crossed_riser(
			across.transform,
			riser_point,
			riser_normal
		):
			continue

		var landing: LandingResult = probe_down_for_landing(
			player,
			support,
			across.transform,
			sample_height + PROBE_SAFE_MARGIN,
			riser_point,
			riser_normal
		)
		if landing == null:
			continue

		var rise: float = get_capsule_bottom_y(landing.transform) - current_bottom_y
		if rise <= PROBE_SAFE_MARGIN:
			continue
		if rise > max_step_height + PROBE_SAFE_MARGIN:
			continue
		return landing

	return null


func probe_down_for_landing(
	player: CharacterBody3D,
	support: PlayerSupport,
	from_transform: Transform3D,
	max_drop_distance: float,
	riser_point: Vector3,
	riser_normal: Vector3
) -> LandingResult:
	var current_transform: Transform3D = from_transform
	var remaining_motion: Vector3 = Vector3.DOWN * max_drop_distance

	for _iteration: int in range(MAX_CLEARANCE_ITERATIONS):
		if remaining_motion.length_squared() <= MOTION_EPSILON_SQUARED:
			return null

		var collision := KinematicCollision3D.new()
		var blocked: bool = player.test_move(
			current_transform,
			remaining_motion,
			collision,
			PROBE_SAFE_MARGIN,
			false,
			PROBE_MAX_COLLISIONS
		)
		if not blocked:
			return null

		var travel: Vector3 = collision.get_travel()
		current_transform = current_transform.translated(travel)

		for collision_index: int in range(collision.get_collision_count()):
			var normal: Vector3 = collision.get_normal(collision_index)
			if not support.is_walkable_surface(normal):
				continue
			var contact_point: Vector3 = collision.get_position(collision_index)
			if not is_landing_local_to_riser(
				contact_point,
				riser_point,
				riser_normal
			):
				continue

			var landing := LandingResult.new()
			landing.transform = current_transform
			landing.contact_point = contact_point
			return landing

		var next_motion: Vector3 = slide_motion_against_contacts(
			collision.get_remainder(),
			collision
		)
		if (
			travel.length_squared() <= MOTION_EPSILON_SQUARED
			and (next_motion - remaining_motion).length_squared() <= MOTION_EPSILON_SQUARED
		):
			return null
		remaining_motion = next_motion

	return null


func resolve_motion(
	player: CharacterBody3D,
	from_transform: Transform3D,
	requested_motion: Vector3
) -> MotionResolution:
	var result := MotionResolution.new()
	result.transform = from_transform
	var remaining_motion: Vector3 = requested_motion

	for _iteration: int in range(MAX_CLEARANCE_ITERATIONS):
		if remaining_motion.length_squared() <= MOTION_EPSILON_SQUARED:
			return result

		var collision := KinematicCollision3D.new()
		var blocked: bool = player.test_move(
			result.transform,
			remaining_motion,
			collision,
			PROBE_SAFE_MARGIN,
			false,
			PROBE_MAX_COLLISIONS
		)
		if not blocked:
			result.transform = result.transform.translated(remaining_motion)
			return result

		var travel: Vector3 = collision.get_travel()
		result.transform = result.transform.translated(travel)
		var next_motion: Vector3 = slide_motion_against_contacts(
			collision.get_remainder(),
			collision
		)
		if (
			travel.length_squared() <= MOTION_EPSILON_SQUARED
			and (next_motion - remaining_motion).length_squared() <= MOTION_EPSILON_SQUARED
		):
			return result
		remaining_motion = next_motion

	return result


func slide_motion_against_contacts(
	motion: Vector3,
	collision: KinematicCollision3D
) -> Vector3:
	var resolved_motion: Vector3 = motion
	for collision_index: int in range(collision.get_collision_count()):
		var normal: Vector3 = collision.get_normal(collision_index)
		if resolved_motion.dot(normal) < 0.0:
			resolved_motion = resolved_motion.slide(normal)
	return resolved_motion


func is_landing_local_to_riser(
	contact_point: Vector3,
	riser_point: Vector3,
	riser_normal: Vector3
) -> bool:
	return (
		(contact_point - riser_point).dot(riser_normal)
		<= PROBE_SAFE_MARGIN
	)


func has_crossed_riser(
	position: Vector3,
	plan: StepPlan
) -> bool:
	return (
		(position - plan.riser_point).dot(plan.riser_normal)
		<= -PROBE_SAFE_MARGIN
	)


func has_transform_crossed_riser(
	transform: Transform3D,
	riser_point: Vector3,
	riser_normal: Vector3
) -> bool:
	return (
		(transform.origin - riser_point).dot(riser_normal)
		<= -PROBE_SAFE_MARGIN
	)


func cancel_traversal() -> void:
	active_plan = null
	vertical_assist_speed = 0.0


func get_across_motion(
	horizontal_direction: Vector3,
	push_strength: float
) -> Vector3:
	var safe_push_strength: float = maxf(
		push_strength,
		MIN_STEP_APPROACH_DOT
	)
	var across_distance: float = (
		get_capsule_radius() + PROBE_SAFE_MARGIN
	) / safe_push_strength
	return horizontal_direction * across_distance


func is_step_riser(normal: Vector3) -> bool:
	var maximum_normal_y: float = sin(
		deg_to_rad(max_riser_tilt_degrees)
	)
	return absf(normal.y) <= maximum_normal_y


func get_capsule_bottom_y(transform: Transform3D) -> float:
	return get_capsule_bottom_y_from_position(transform.origin.y)


func get_capsule_bottom_y_from_position(position_y: float) -> float:
	return position_y + get_capsule_bottom_offset()


func get_capsule_bottom_offset() -> float:
	var shape: Shape3D = collision_shape.shape
	assert(
		shape is CapsuleShape3D,
		"PlayerStepUp requires the player collision shape to be CapsuleShape3D."
	)
	var capsule_shape: CapsuleShape3D = shape as CapsuleShape3D
	return collision_shape.position.y - capsule_shape.height * 0.5


func get_capsule_radius() -> float:
	var shape: Shape3D = collision_shape.shape
	assert(
		shape is CapsuleShape3D,
		"PlayerStepUp requires the player collision shape to be CapsuleShape3D."
	)
	var capsule_shape: CapsuleShape3D = shape as CapsuleShape3D
	return capsule_shape.radius
