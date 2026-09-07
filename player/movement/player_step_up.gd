class_name PlayerStepUp
extends RefCounted


const PROBE_SAFE_MARGIN: float = 0.001
const STEP_VALIDATION_CROSS_MARGIN: float = 0.002
const PROBE_MAX_COLLISIONS: int = 8
const MOTION_EPSILON_SQUARED: float = 0.000001
const MAX_CLEARANCE_ITERATIONS: int = 8
const LANDING_PROBE_SAMPLE_COUNT: int = 8
const LANDING_PROBE_MIN_INSET: float = 0.004
const MIN_STEP_APPROACH_DOT: float = 0.1
const RISER_DEDUP_NORMAL_ALIGNMENT: float = 0.999
const RISER_DEDUP_PLANE_TOLERANCE: float = 0.005
const MOTION_BLOCKING_DOT: float = -0.0001
const DEBUG_STEP_UP: bool = true


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
	var surface_normal: Vector3 = Vector3.UP


var max_step_height: float
var max_riser_tilt_degrees: float
var step_up_acceleration: float
var max_step_up_speed: float
var collision_shape: CollisionShape3D

var active_plan: StepPlan = null
# Additive temporary upward correction. It never replaces the player's
# ballistic velocity and disappears as soon as the selected riser is released.
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
	_debug(
		"START riser=", plan.riser_point,
		" normal=", plan.riser_normal,
		" landing=", plan.landing_position,
		" player=", player.global_position
	)
	return true


func update_traversal(
	player: CharacterBody3D,
	input_direction: Vector3,
	delta: float
) -> void:
	if active_plan == null:
		return

	if has_crossed_riser(player.global_position, active_plan):
		_debug("COMPLETE crossed riser player=", player.global_position)
		cancel_traversal()
		return
	if input_direction.is_zero_approx():
		_debug("CANCEL input released")
		cancel_traversal()
		return

	var input_push: float = -input_direction.dot(active_plan.riser_normal)
	if input_push <= 0.0:
		_debug("CANCEL input no longer pushes into riser push=", input_push)
		cancel_traversal()
		return

	var target_y: float = active_plan.landing_position.y + PROBE_SAFE_MARGIN
	var remaining_height: float = maxf(0.0, target_y - player.global_position.y)
	var braking_speed: float = sqrt(
		2.0 * step_up_acceleration * remaining_height
	)
	var target_vertical_speed: float = minf(max_step_up_speed, braking_speed)

	# Step-up is an additive correction, not a replacement Y velocity. A fast
	# upward jump receives no boost, while a fall is countered progressively at
	# step_up_acceleration rather than being cancelled in one frame.
	var desired_correction: float = maxf(
		0.0,
		target_vertical_speed - player.velocity.y
	)
	vertical_assist_speed = move_toward(
		vertical_assist_speed,
		desired_correction,
		step_up_acceleration * delta
	)


func get_motion_velocity(base_velocity: Vector3) -> Vector3:
	if active_plan == null:
		return base_velocity
	var motion_velocity: Vector3 = base_velocity
	motion_velocity.y += vertical_assist_speed
	return motion_velocity


func refresh_after_move(player: CharacterBody3D) -> void:
	if active_plan == null:
		return
	if has_crossed_riser(player.global_position, active_plan):
		_debug("COMPLETE crossed riser after move player=", player.global_position)
		cancel_traversal()


func should_preserve_velocity(collision: KinematicCollision3D) -> bool:
	if active_plan == null or collision == null:
		return false

	for collision_index: int in range(collision.get_collision_count()):
		if collision.get_collider_rid(collision_index) != active_plan.riser_collider_rid:
			continue
		if collision.get_collider_shape_index(collision_index) != active_plan.riser_shape_index:
			continue
		var collision_normal: Vector3 = collision.get_normal(collision_index)
		if collision_normal.dot(active_plan.riser_normal) > 0.0:
			return true
	return false


func is_vertical_assist_blocked(
	collision: KinematicCollision3D,
	_base_velocity: Vector3
) -> bool:
	if active_plan == null or collision == null:
		return false
	if vertical_assist_speed <= 0.000001:
		return false

	for collision_index: int in range(collision.get_collision_count()):
		var normal: Vector3 = collision.get_normal(collision_index)
		if normal.y < -0.05:
			_debug(
				"CANCEL live vertical assist blocked normal=", normal,
				" assist=", vertical_assist_speed
			)
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

	_debug(
		"OBSTRUCTION motion=", horizontal_motion,
		" player=", player.global_position,
		" contacts=", collision.get_collision_count()
	)

	var best_plan: StepPlan = null
	var best_push_strength: float = 0.0
	var best_rise: float = INF
	var tested_riser_points: Array[Vector3] = []
	var tested_riser_normals: Array[Vector3] = []

	for collision_index: int in range(collision.get_collision_count()):
		var collision_normal: Vector3 = collision.get_normal(collision_index)
		var collision_point: Vector3 = collision.get_position(collision_index)
		_debug(
			"CONTACT index=", collision_index,
			" point=", collision_point,
			" normal=", collision_normal
		)
		if support.is_walkable_surface(collision_normal):
			_debug("REJECT contact walkable")
			continue
		if not is_step_riser(collision_normal):
			_debug("REJECT contact not riser")
			continue

		var horizontal_normal := Vector3(
			collision_normal.x,
			0.0,
			collision_normal.z
		)
		if horizontal_normal.length_squared() <= MOTION_EPSILON_SQUARED:
			_debug("REJECT contact has no horizontal normal")
			continue
		horizontal_normal = horizontal_normal.normalized()

		var push_strength: float = -horizontal_direction.dot(horizontal_normal)
		if push_strength < MIN_STEP_APPROACH_DOT:
			_debug(
				"REJECT shallow approach push=", push_strength,
				" minimum=", MIN_STEP_APPROACH_DOT
			)
			continue
		var input_push: float = -input_direction.dot(horizontal_normal)
		if input_push <= 0.0:
			_debug("REJECT input not into riser input_push=", input_push)
			continue
		if is_duplicate_riser(
			collision_point,
			horizontal_normal,
			tested_riser_points,
			tested_riser_normals
		):
			_debug("REJECT duplicate riser contact")
			continue
		tested_riser_points.append(collision_point)
		tested_riser_normals.append(horizontal_normal)

		_debug(
			"RISER candidate point=", collision_point,
			" normal=", horizontal_normal,
			" push=", push_strength
		)
		var plan: StepPlan = build_step_plan(
			player,
			support,
			horizontal_direction,
			push_strength,
			collision_point,
			horizontal_normal,
			collision.get_collider_rid(collision_index),
			collision.get_collider_shape_index(collision_index)
		)
		if plan == null:
			_debug("REJECT riser plan validation failed")
			continue

		var rise: float = plan.landing_position.y - player.global_position.y
		_debug("VALID riser rise=", rise, " landing=", plan.landing_position)
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

	if best_plan == null:
		_debug("NO VALID STEP PLAN")
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
	var landing: LandingResult = find_landing_surface_from_above(
		player,
		support,
		horizontal_direction,
		push_strength,
		riser_point,
		riser_normal
	)
	if landing == null:
		_debug("FAIL landing surface discovery riser=", riser_point)
		return null

	var rise: float = landing.transform.origin.y - player.global_position.y
	_debug(
		"LANDING found contact=", landing.contact_point,
		" normal=", landing.surface_normal,
		" pose=", landing.transform.origin,
		" rise=", rise
	)
	if rise <= PROBE_SAFE_MARGIN:
		_debug("FAIL landing not above capsule rise=", rise)
		return null
	if rise > max_step_height + PROBE_SAFE_MARGIN:
		_debug("FAIL landing too high rise=", rise, " max=", max_step_height)
		return null

	# Surface probes discover where the top is. The full capsule now proves only
	# the motion it must actually perform: rise to that surface, then clear the
	# selected riser while ordinary collision sliding handles side constraints.
	var target_y: float = landing.transform.origin.y + PROBE_SAFE_MARGIN
	var required_up_distance: float = maxf(0.0, target_y - player.global_position.y)
	var raised: MotionResolution = resolve_motion(
		player,
		player.global_transform,
		Vector3.UP * required_up_distance
	)
	if raised.transform.origin.y < target_y - PROBE_SAFE_MARGIN:
		_debug(
			"FAIL UP clearance required=", required_up_distance,
			" target_y=", target_y,
			" reached_y=", raised.transform.origin.y,
			" start_y=", player.global_position.y
		)
		return null

	var across_motion: Vector3 = get_validation_across_motion(
		player.global_position,
		horizontal_direction,
		riser_point,
		riser_normal,
		push_strength
	)
	var crossed: MotionResolution = resolve_motion(
		player,
		raised.transform,
		across_motion
	)
	if not has_transform_cleared_riser_for_validation(
		crossed.transform,
		riser_point,
		riser_normal
	):
		_debug(
			"FAIL ACROSS clearance requested=", across_motion,
			" raised=", raised.transform.origin,
			" reached=", crossed.transform.origin,
			" plane_distance=",
			(crossed.transform.origin - riser_point).dot(riser_normal)
		)
		return null

	var plan := StepPlan.new()
	plan.riser_point = riser_point
	plan.riser_normal = riser_normal
	plan.riser_collider_rid = riser_collider_rid
	plan.riser_shape_index = riser_shape_index
	plan.landing_position = landing.transform.origin
	return plan


func find_landing_surface_from_above(
	player: CharacterBody3D,
	support: PlayerSupport,
	horizontal_direction: Vector3,
	push_strength: float,
	riser_point: Vector3,
	riser_normal: Vector3
) -> LandingResult:
	var crossing_point: Vector3 = get_riser_crossing_point(
		player.global_position,
		horizontal_direction,
		riser_point,
		riser_normal,
		push_strength
	)
	var current_bottom_y: float = get_capsule_bottom_y(player.global_transform)
	var probe_top_y: float = current_bottom_y + max_step_height + PROBE_SAFE_MARGIN
	var probe_bottom_y: float = current_bottom_y + PROBE_SAFE_MARGIN
	var maximum_probe_depth: float = maxf(get_capsule_radius(), LANDING_PROBE_MIN_INSET)

	# Search nearest-to-farthest behind the selected riser. Bias samples toward
	# the edge so shallow stair treads are found before a farther platform or the
	# next stair can steal the candidate.
	for sample_index: int in range(LANDING_PROBE_SAMPLE_COUNT):
		var fraction: float = 0.0
		if LANDING_PROBE_SAMPLE_COUNT > 1:
			fraction = float(sample_index) / float(LANDING_PROBE_SAMPLE_COUNT - 1)
		var biased_fraction: float = fraction * fraction
		var probe_depth: float = lerpf(
			LANDING_PROBE_MIN_INSET,
			maximum_probe_depth,
			biased_fraction
		)
		var probe_position: Vector3 = crossing_point - riser_normal * probe_depth
		var ray_from := Vector3(probe_position.x, probe_top_y, probe_position.z)
		var ray_to := Vector3(probe_position.x, probe_bottom_y, probe_position.z)
		var landing: LandingResult = raycast_landing_surface(
			player,
			support,
			ray_from,
			ray_to,
			probe_position
		)
		if landing == null:
			continue

		var rise: float = landing.transform.origin.y - player.global_position.y
		_debug(
			"LANDING probe depth=", probe_depth,
			" contact=", landing.contact_point,
			" normal=", landing.surface_normal,
			" rise=", rise
		)
		return landing

	return null


func raycast_landing_surface(
	player: CharacterBody3D,
	support: PlayerSupport,
	ray_from: Vector3,
	ray_to: Vector3,
	probe_position: Vector3
) -> LandingResult:
	var query := PhysicsRayQueryParameters3D.create(
		ray_from,
		ray_to,
		player.collision_mask,
		[player.get_rid()]
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_back_faces = false
	query.hit_from_inside = false

	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var position_value: Variant = hit.get("position")
	var normal_value: Variant = hit.get("normal")
	if not (position_value is Vector3) or not (normal_value is Vector3):
		return null

	var contact_point: Vector3 = position_value
	var surface_normal: Vector3 = normal_value
	if not support.is_walkable_surface(surface_normal):
		_debug(
			"REJECT landing ray non-walkable contact=", contact_point,
			" normal=", surface_normal
		)
		return null
	surface_normal = surface_normal.normalized()

	var target_root_y: float = get_capsule_root_y_for_surface(
		contact_point,
		surface_normal
	)
	if not is_finite(target_root_y):
		return null
	var rise: float = target_root_y - player.global_position.y
	if rise <= PROBE_SAFE_MARGIN or rise > max_step_height + PROBE_SAFE_MARGIN:
		_debug(
			"REJECT landing ray height contact=", contact_point,
			" rise=", rise,
			" max=", max_step_height
		)
		return null

	var landing := LandingResult.new()
	landing.transform = player.global_transform
	landing.transform.origin = Vector3(
		probe_position.x,
		target_root_y,
		probe_position.z
	)
	landing.contact_point = contact_point
	landing.surface_normal = surface_normal
	return landing


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
			# Recovery/tangent contacts can report a collision even though they do
			# not oppose this requested phase. Treat only into-normal contacts as
			# blockers so a side wall cannot veto a vertical or parallel sweep.
			if not collision_opposes_motion(collision, remaining_motion):
				result.transform = result.transform.translated(remaining_motion)
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


func collision_opposes_motion(
	collision: KinematicCollision3D,
	motion: Vector3
) -> bool:
	if collision == null or motion.length_squared() <= MOTION_EPSILON_SQUARED:
		return false
	var direction: Vector3 = motion.normalized()
	for collision_index: int in range(collision.get_collision_count()):
		var normal: Vector3 = collision.get_normal(collision_index)
		if direction.dot(normal) < MOTION_BLOCKING_DOT:
			return true
	return false


func is_duplicate_riser(
	riser_point: Vector3,
	riser_normal: Vector3,
	tested_points: Array[Vector3],
	tested_normals: Array[Vector3]
) -> bool:
	for candidate_index: int in range(tested_points.size()):
		var tested_normal: Vector3 = tested_normals[candidate_index]
		if tested_normal.dot(riser_normal) < RISER_DEDUP_NORMAL_ALIGNMENT:
			continue
		var plane_delta: float = absf(
			(riser_point - tested_points[candidate_index]).dot(riser_normal)
		)
		if plane_delta <= RISER_DEDUP_PLANE_TOLERANCE:
			return true
	return false


func get_riser_crossing_point(
	start_position: Vector3,
	horizontal_direction: Vector3,
	riser_point: Vector3,
	riser_normal: Vector3,
	push_strength: float
) -> Vector3:
	var plane_distance: float = (start_position - riser_point).dot(riser_normal)
	var safe_push_strength: float = maxf(push_strength, MIN_STEP_APPROACH_DOT)
	var distance_to_plane: float = maxf(0.0, plane_distance) / safe_push_strength
	return start_position + horizontal_direction * distance_to_plane


func has_crossed_riser(position: Vector3, plan: StepPlan) -> bool:
	return (position - plan.riser_point).dot(plan.riser_normal) <= 0.0


func has_transform_cleared_riser_for_validation(
	transform: Transform3D,
	riser_point: Vector3,
	riser_normal: Vector3
) -> bool:
	return (
		(transform.origin - riser_point).dot(riser_normal)
		<= -STEP_VALIDATION_CROSS_MARGIN
	)


func cancel_traversal() -> void:
	active_plan = null
	vertical_assist_speed = 0.0


func get_validation_across_motion(
	start_position: Vector3,
	horizontal_direction: Vector3,
	riser_point: Vector3,
	riser_normal: Vector3,
	push_strength: float
) -> Vector3:
	var safe_push_strength: float = maxf(push_strength, MIN_STEP_APPROACH_DOT)
	var plane_distance: float = (start_position - riser_point).dot(riser_normal)
	var required_normal_distance: float = maxf(
		0.0,
		plane_distance + STEP_VALIDATION_CROSS_MARGIN
	)
	var across_distance: float = required_normal_distance / safe_push_strength
	_debug(
		"VALIDATION across plane_distance=", plane_distance,
		" required_normal=", required_normal_distance,
		" across_distance=", across_distance
	)
	return horizontal_direction * across_distance


func is_step_riser(normal: Vector3) -> bool:
	var maximum_normal_y: float = sin(deg_to_rad(max_riser_tilt_degrees))
	return absf(normal.y) <= maximum_normal_y


func get_capsule_root_y_for_surface(
	surface_point: Vector3,
	surface_normal: Vector3
) -> float:
	if surface_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return INF
	var normal: Vector3 = surface_normal.normalized()
	if normal.y <= 0.000001:
		return INF

	var capsule_shape: CapsuleShape3D = get_capsule_shape()
	var half_segment: float = maxf(
		0.0,
		capsule_shape.height * 0.5 - capsule_shape.radius
	)
	# For an upright capsule whose root XZ is the ray sample XZ, solve the plane
	# contact height of the lower capsule support point. Flat ground reduces to
	# surface_y - capsule_bottom_offset; slopes include the spherical normal
	# offset rather than treating the ray's Y as the body pose directly.
	return (
		surface_point.y
		- collision_shape.position.y
		+ half_segment
		+ capsule_shape.radius / normal.y
	)


func get_capsule_bottom_y(transform: Transform3D) -> float:
	return get_capsule_bottom_y_from_position(transform.origin.y)


func get_capsule_bottom_y_from_position(position_y: float) -> float:
	return position_y + get_capsule_bottom_offset()


func get_capsule_bottom_offset() -> float:
	var capsule_shape: CapsuleShape3D = get_capsule_shape()
	return collision_shape.position.y - capsule_shape.height * 0.5


func get_capsule_radius() -> float:
	return get_capsule_shape().radius


func get_capsule_shape() -> CapsuleShape3D:
	var shape: Shape3D = collision_shape.shape
	assert(
		shape is CapsuleShape3D,
		"PlayerStepUp requires the player collision shape to be CapsuleShape3D."
	)
	return shape as CapsuleShape3D


func _debug(...args: Array) -> void:
	if not DEBUG_STEP_UP:
		return
	print("[StepUp] ", "".join(args.map(func(value: Variant) -> String: return str(value))))
