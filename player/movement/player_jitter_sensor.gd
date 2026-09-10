class_name PlayerJitterSensor
extends RefCounted


const MOTION_EPSILON_SQUARED: float = 0.00000001
const POSITION_ERROR_THRESHOLD: float = 0.002
const VERTICAL_ERROR_THRESHOLD: float = 0.001
const VERTICAL_OSCILLATION_THRESHOLD: float = 0.0005
const HEAD_CHANGE_THRESHOLD: float = 0.0001
const RENDER_DT_SPREAD_THRESHOLD: float = 0.002
const PHYSICS_DT_MULTIPLIER_WARNING: float = 1.25
const MAX_CONTACT_LINES: int = 12


var enabled: bool
var body: CharacterBody3D
var head: Node3D
var camera: Camera3D
var collision_shape: CollisionShape3D
var player_input: PlayerInput
var support: PlayerSupport
var step: PlayerStep
var crouch: PlayerCrouch
var ledge_detector: PlayerLedgeDetector
var ledge_controller: PlayerLedgeController

var render_frames_since_physics: int = 0
var render_delta_sum: float = 0.0
var render_delta_min: float = INF
var render_delta_max: float = 0.0

var frame_render_count: int = 0
var frame_render_delta_average: float = 0.0
var frame_render_delta_min: float = 0.0
var frame_render_delta_max: float = 0.0

var physics_delta: float = 0.0
var start_position: Vector3 = Vector3.ZERO
var start_velocity: Vector3 = Vector3.ZERO
var start_head_local_position: Vector3 = Vector3.ZERO
var start_grounded: bool = false
var start_has_support: bool = false
var start_walkable: bool = false
var start_step_active: bool = false
var start_ledge_state: int = PlayerLedgeController.State.NONE
var jump_pressed: bool = false
var jump_held: bool = false
var crouch_pressed: bool = false

var motion_plan_valid: bool = false
var planned_persistent_velocity: Vector3 = Vector3.ZERO
var planned_assist_velocity: Vector3 = Vector3.ZERO
var planned_support_walkable: bool = false
var planned_support_normal: Vector3 = Vector3.UP

var contact_lines: PackedStringArray = PackedStringArray()
var contact_count: int = 0
var previous_vertical_displacement: float = 0.0
var previous_grounded: bool = false
var has_previous_physics_sample: bool = false


func _init(
	p_enabled: bool,
	player_body: CharacterBody3D,
	player_head: Node3D,
	player_camera: Camera3D,
	player_collision_shape: CollisionShape3D,
	input_source: PlayerInput,
	player_support: PlayerSupport,
	player_step: PlayerStep,
	player_crouch: PlayerCrouch,
	detector: PlayerLedgeDetector,
	controller: PlayerLedgeController
) -> void:
	enabled = p_enabled
	body = player_body
	head = player_head
	camera = player_camera
	collision_shape = player_collision_shape
	player_input = input_source
	support = player_support
	step = player_step
	crouch = player_crouch
	ledge_detector = detector
	ledge_controller = controller


func capture_render_frame(delta: float) -> void:
	if not enabled:
		return
	render_frames_since_physics += 1
	render_delta_sum += delta
	render_delta_min = minf(render_delta_min, delta)
	render_delta_max = maxf(render_delta_max, delta)


func begin_physics_frame(
	delta: float,
	p_jump_pressed: bool,
	p_jump_held: bool,
	p_crouch_pressed: bool
) -> void:
	if not enabled:
		return

	frame_render_count = render_frames_since_physics
	if frame_render_count > 0:
		frame_render_delta_average = render_delta_sum / float(frame_render_count)
		frame_render_delta_min = render_delta_min
		frame_render_delta_max = render_delta_max
	else:
		frame_render_delta_average = 0.0
		frame_render_delta_min = 0.0
		frame_render_delta_max = 0.0

	render_frames_since_physics = 0
	render_delta_sum = 0.0
	render_delta_min = INF
	render_delta_max = 0.0

	physics_delta = delta
	start_position = body.global_position
	start_velocity = body.velocity
	start_head_local_position = head.position
	start_grounded = support.is_grounded()
	start_has_support = support.has_support
	start_walkable = support.walkable
	start_step_active = step.is_active()
	start_ledge_state = ledge_controller.state
	jump_pressed = p_jump_pressed
	jump_held = p_jump_held
	crouch_pressed = p_crouch_pressed

	motion_plan_valid = false
	planned_persistent_velocity = Vector3.ZERO
	planned_assist_velocity = Vector3.ZERO
	planned_support_walkable = false
	planned_support_normal = Vector3.UP
	contact_lines.clear()
	contact_count = 0


func record_motion_plan(
	persistent_velocity: Vector3,
	assist_velocity: Vector3
) -> void:
	if not enabled:
		return
	motion_plan_valid = true
	planned_persistent_velocity = persistent_velocity
	planned_assist_velocity = assist_velocity
	planned_support_walkable = support.has_support and support.walkable
	planned_support_normal = support.support_normal


func record_collisions(
	collisions: Array[KinematicCollision3D]
) -> void:
	if not enabled:
		return

	contact_lines.clear()
	contact_count = 0
	for move_index: int in range(collisions.size()):
		var collision: KinematicCollision3D = collisions[move_index]
		if collision == null:
			continue

		var collision_count: int = collision.get_collision_count()
		if collision_count <= 0:
			contact_count += 1
			_append_contact_line(
				"move=%d contact=0 normal=%s point=%s travel=%s remainder=%s"
				% [
					move_index,
					str(collision.get_normal()),
					str(collision.get_position()),
					str(collision.get_travel()),
					str(collision.get_remainder()),
				]
			)
			continue

		for collision_index: int in range(collision_count):
			contact_count += 1
			_append_contact_line(
				"move=%d contact=%d normal=%s point=%s travel=%s remainder=%s"
				% [
					move_index,
					collision_index,
					str(collision.get_normal(collision_index)),
					str(collision.get_position(collision_index)),
					str(collision.get_travel()),
					str(collision.get_remainder()),
				]
			)


func end_physics_frame(mantle_intent_active: bool) -> void:
	if not enabled:
		return

	var end_position: Vector3 = body.global_position
	var displacement: Vector3 = end_position - start_position
	var observed_velocity: Vector3 = Vector3.ZERO
	if physics_delta > 0.000001:
		observed_velocity = displacement / physics_delta

	var grounded: bool = support.is_grounded()
	var has_support: bool = support.has_support
	var walkable: bool = support.walkable
	var step_active: bool = step.is_active()
	var ledge_state: int = ledge_controller.state
	var input_vector: Vector2 = player_input.get_movement_vector()

	var expected_displacement: Vector3 = Vector3.ZERO
	var movement_error: Vector3 = Vector3.ZERO
	if motion_plan_valid:
		expected_displacement = _get_expected_displacement()
		movement_error = displacement - expected_displacement

	var flags := PackedStringArray()
	var nominal_physics_delta: float = (
		1.0 / float(Engine.physics_ticks_per_second)
	)
	if physics_delta > nominal_physics_delta * PHYSICS_DT_MULTIPLIER_WARNING:
		flags.append("PHYSICS_DT_HIGH")
	if (
		frame_render_count > 1
		and frame_render_delta_max - frame_render_delta_min
		> RENDER_DT_SPREAD_THRESHOLD
	):
		flags.append("RENDER_DT_VARIANCE")
	if start_grounded != grounded:
		flags.append("GROUND_FLIP")
	if start_has_support != has_support:
		flags.append("SUPPORT_FLIP")
	if start_walkable != walkable:
		flags.append("WALKABLE_FLIP")
	if start_step_active != step_active:
		flags.append("STEP_FLIP")
	if start_ledge_state != ledge_state:
		flags.append("LEDGE_FLIP")
	if contact_count > 0:
		flags.append("CONTACT")
	if motion_plan_valid and movement_error.length() > POSITION_ERROR_THRESHOLD:
		flags.append(
			"COLLISION_MOTION_ERROR"
			if contact_count > 0
			else "UNEXPLAINED_MOTION_ERROR"
		)
	if motion_plan_valid and absf(movement_error.y) > VERTICAL_ERROR_THRESHOLD:
		flags.append("VERTICAL_CORRECTION")
	if (
		has_previous_physics_sample
		and previous_grounded
		and grounded
		and not start_step_active
		and not step_active
		and absf(previous_vertical_displacement) > VERTICAL_OSCILLATION_THRESHOLD
		and absf(displacement.y) > VERTICAL_OSCILLATION_THRESHOLD
		and previous_vertical_displacement * displacement.y < 0.0
	):
		flags.append("GROUNDED_VERTICAL_OSCILLATION")
	if head.position.distance_to(start_head_local_position) > HEAD_CHANGE_THRESHOLD:
		flags.append("HEAD_LOCAL_MOVED")

	var should_print: bool = (
		displacement.length_squared() > MOTION_EPSILON_SQUARED
		or body.velocity.length_squared() > MOTION_EPSILON_SQUARED
		or not input_vector.is_zero_approx()
		or jump_pressed
		or jump_held
		or crouch_pressed
		or contact_count > 0
		or start_grounded != grounded
		or start_step_active != step_active
		or start_ledge_state != ledge_state
	)
	if should_print:
		var capsule_height: float = 0.0
		if collision_shape.shape is CapsuleShape3D:
			var capsule_shape := collision_shape.shape as CapsuleShape3D
			capsule_height = capsule_shape.height

		var step_remaining: float = 0.0
		var step_edge: Vector3 = Vector3.ZERO
		var step_wall_normal: Vector3 = Vector3.ZERO
		var step_height: float = 0.0
		if step.active_candidate != null:
			step_remaining = step.get_remaining_height(body.global_position)
			step_edge = step.active_candidate.edge_point
			step_wall_normal = step.active_candidate.wall_normal
			step_height = step.active_candidate.step_height

		var planned_velocity: Vector3 = (
			planned_persistent_velocity + planned_assist_velocity
		)
		var flag_text: String = "none" if flags.is_empty() else "|".join(flags)
		print(
			"[JITTER] pf=%d rf=%d dt=%.6f renders=%d render_dt_avg=%.6f render_dt_min=%.6f render_dt_max=%.6f interp=%.4f pos0=%s pos1=%s dpos=%s observed_vel=%s vel0=%s planned_vel=%s assist=%s vel1=%s expected_dpos=%s motion_error=%s input=%s jump_press=%s jump_hold=%s crouch_press=%s sprint=%s ground=%s->%s support=%s->%s walkable=%s->%s support_normal=%s support_point=%s step=%s->%s step_assist=%.4f step_remaining=%.4f step_height=%.4f step_edge=%s step_wall=%s ledge=%s->%s candidates=%d mantle_intent=%s capsule_h=%.4f head_local=%s head_global=%s camera_global=%s body_rot=%s head_rot=%s contacts=%d flags=%s"
			% [
				Engine.get_physics_frames(),
				Engine.get_process_frames(),
				physics_delta,
				frame_render_count,
				frame_render_delta_average,
				frame_render_delta_min,
				frame_render_delta_max,
				Engine.get_physics_interpolation_fraction(),
				str(start_position),
				str(end_position),
				str(displacement),
				str(observed_velocity),
				str(start_velocity),
				str(planned_velocity),
				str(planned_assist_velocity),
				str(body.velocity),
				str(expected_displacement),
				str(movement_error),
				str(input_vector),
				str(jump_pressed),
				str(jump_held),
				str(crouch_pressed),
				str(player_input.is_sprint_pressed()),
				str(start_grounded),
				str(grounded),
				str(start_has_support),
				str(has_support),
				str(start_walkable),
				str(walkable),
				str(support.support_normal),
				str(support.support_point),
				str(start_step_active),
				str(step_active),
				step.current_assist_speed,
				step_remaining,
				step_height,
				str(step_edge),
				str(step_wall_normal),
				_ledge_state_name(start_ledge_state),
				_ledge_state_name(ledge_state),
				ledge_detector.get_candidates().size(),
				str(mantle_intent_active),
				capsule_height,
				str(head.position),
				str(head.global_position),
				str(camera.global_position),
				str(body.rotation),
				str(head.rotation),
				contact_count,
				flag_text,
			]
		)

		for contact_line: String in contact_lines:
			print(
				"[JITTER_CONTACT] pf=%d %s"
				% [Engine.get_physics_frames(), contact_line]
			)

	previous_vertical_displacement = displacement.y
	previous_grounded = grounded
	has_previous_physics_sample = true


func _get_expected_displacement() -> Vector3:
	var persistent_motion: Vector3 = planned_persistent_velocity * physics_delta
	if (
		planned_support_walkable
		and absf(planned_persistent_velocity.y) <= 0.000001
		and planned_assist_velocity.length_squared() <= MOTION_EPSILON_SQUARED
	):
		var normal: Vector3 = planned_support_normal
		if normal.length_squared() > MOTION_EPSILON_SQUARED:
			normal = normal.normalized()
			if normal.y > 0.0001:
				persistent_motion.y = -(
					normal.x * persistent_motion.x
					+ normal.z * persistent_motion.z
				) / normal.y
	return persistent_motion + planned_assist_velocity * physics_delta


func _append_contact_line(line: String) -> void:
	if contact_lines.size() >= MAX_CONTACT_LINES:
		return
	contact_lines.append(line)


func _ledge_state_name(state_value: int) -> String:
	match state_value:
		PlayerLedgeController.State.NONE:
			return "NONE"
		PlayerLedgeController.State.CATCHING:
			return "CATCHING"
		PlayerLedgeController.State.HANGING:
			return "HANGING"
		PlayerLedgeController.State.CORNERING:
			return "CORNERING"
		PlayerLedgeController.State.MANTLING:
			return "MANTLING"
	return "UNKNOWN_%d" % state_value
