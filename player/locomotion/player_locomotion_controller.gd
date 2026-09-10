class_name PlayerLocomotionController
extends RefCounted


var body: CharacterBody3D
var head: Node3D
var support: PlayerSupport
var motor: PlayerMotor
var velocity_state: PlayerVelocityState
var motion_solver: PlayerMotionSolver
var step: PlayerStep
var crouch: PlayerCrouch
var ledge_detector: PlayerLedgeDetectorLazy
var ledge_controller: PlayerLedgeController
var anomaly_sensor: PlayerLocomotionAnomalySensor = PlayerLocomotionAnomalySensor.new()

var max_speed: float
var sprint_speed: float
var crouch_speed: float
var jump_height: float

var air_mantle_intent_active: bool = false


func _init(
	player_body: CharacterBody3D,
	player_head: Node3D,
	player_support: PlayerSupport,
	player_motor: PlayerMotor,
	player_velocity_state: PlayerVelocityState,
	player_motion_solver: PlayerMotionSolver,
	player_step: PlayerStep,
	player_crouch: PlayerCrouch,
	player_ledge_detector: PlayerLedgeDetectorLazy,
	player_ledge_controller: PlayerLedgeController,
	configured_max_speed: float,
	configured_sprint_speed: float,
	configured_crouch_speed: float,
	configured_jump_height: float
) -> void:
	body = player_body
	head = player_head
	support = player_support
	motor = player_motor
	velocity_state = player_velocity_state
	motion_solver = player_motion_solver
	step = player_step
	crouch = player_crouch
	ledge_detector = player_ledge_detector
	ledge_controller = player_ledge_controller
	max_speed = configured_max_speed
	sprint_speed = configured_sprint_speed
	crouch_speed = configured_crouch_speed
	jump_height = configured_jump_height


func update(
	command: PlayerCommand,
	delta: float
) -> void:
	velocity_state.apply_to_body(body)

	var jump_pressed: bool = command.jump_pressed
	var jump_held: bool = command.jump_held
	var crouch_pressed: bool = command.crouch_pressed
	var input_direction: Vector3 = command.get_movement_direction(body.global_transform)

	# Crouch changes the live capsule shape, but it does not cancel an active
	# step. A blocked step route may therefore become valid naturally as the
	# capsule shrinks, without a cancel/reacquire cycle.
	if crouch_pressed:
		crouch.toggle()
	crouch.update(body, delta)

	# A jump press arms mantle intent for that airborne attempt. Keeping Space
	# held preserves the intent until release or landing, but never owns or gates
	# grounded step-up. This gives jump->hold->mantle buffering without making
	# held Space a persistent grounded traversal command.
	#
	# Support reports floor-like contact separately from whether that contact is
	# walkable, so steep slopes can use slope physics without becoming grounded.
	support.update(body)
	var grounded: bool = support.is_grounded()
	if jump_pressed:
		air_mantle_intent_active = true
	if not jump_held or (grounded and not jump_pressed):
		air_mantle_intent_active = false
	var airborne_mantle_intent: bool = (
		jump_held
		and air_mantle_intent_active
	)
	var view_forward: Vector3 = -head.global_transform.basis.z

	ledge_controller.update_transition_guards()

	var ground_mantle_requested: bool = (
		jump_pressed
		and grounded
		and not input_direction.is_zero_approx()
	)
	var jump_accepted_before_move: bool = (
		jump_pressed
		and grounded
		and not ground_mantle_requested
	)

	# A fresh jump/mantle press supersedes step traversal. Held Space on later
	# frames never cancels or gates step-up.
	if jump_pressed:
		step.cancel()

	var ground_target_speed: float = crouch.get_movement_speed(
		max_speed,
		crouch_speed
	)
	if (
		grounded
		and crouch.is_fully_standing()
		and not input_direction.is_zero_approx()
		and command.sprint_held
	):
		ground_target_speed = sprint_speed

	# PlayerMotor owns only the controlled channel. Support/platform and external
	# velocity are additive state that the motor must not accidentally steer or
	# clamp. Recompose the full body velocity immediately after motor policy runs.
	velocity_state.apply_controlled_to_body(body)
	if step.is_active():
		motor.update_step_horizontal(
			body,
			support,
			input_direction,
			ground_target_speed,
			delta
		)
	else:
		var use_air_control: bool = not support.has_support
		motor.update(
			body,
			support,
			input_direction,
			ground_target_speed,
			use_air_control,
			delta
		)
	velocity_state.capture_controlled_from_body(body)
	velocity_state.apply_to_body(body)

	if jump_accepted_before_move:
		step.cancel()
		support.release_walkable_support(body)
		_apply_controlled_jump()

	var step_plan: PlayerStep.StepPlan = step.prepare_plan(
		body,
		input_direction,
		delta
	)

	var step_traversal_active: bool = step_plan != null
	var airborne_detection_allowed: bool = (
		not grounded and not step_traversal_active
	)
	var ledge_detection_allowed: bool = (
		airborne_detection_allowed
		or ground_mantle_requested
	)
	# Discover once from the pre-move pose. Post-move collision handling reuses
	# these candidates and only filters/expands them against the actual contacts,
	# avoiding a second full wall/top discovery pass in the same physics frame.
	ledge_detector.update(
		body,
		support,
		ledge_detection_allowed,
		input_direction,
		view_forward
	)
	if airborne_detection_allowed and not airborne_mantle_intent:
		if ledge_controller.try_enter_hang_from_normal(delta):
			step.cancel()
			return
		if (
			ledge_detector.expand_current_candidates()
			and ledge_controller.try_enter_hang_from_normal(delta)
		):
			step.cancel()
			return

	var contact_intent_direction: Vector3 = input_direction
	if contact_intent_direction.is_zero_approx():
		var horizontal_velocity := Vector3(
			body.velocity.x,
			0.0,
			body.velocity.z
		)
		if horizontal_velocity.length_squared() > 0.000001:
			contact_intent_direction = horizontal_velocity.normalized()

	var movement_sample_start: Vector3 = body.global_position
	var movement_requested_velocity: Vector3 = body.velocity
	var movement_grounded_before_move: bool = support.is_grounded()
	var collisions: Array[KinematicCollision3D] = motion_solver.move(
		body,
		delta,
		support,
		step_plan
	)
	velocity_state.capture_controlled_from_composed_body(body)
	velocity_state.apply_to_body(body)
	anomaly_sensor.observe(
		body,
		support,
		velocity_state,
		input_direction,
		movement_sample_start,
		movement_requested_velocity,
		delta,
		collisions,
		movement_grounded_before_move,
		step_traversal_active
	)

	# PlayerMotionSolver refreshes support when downward motion lands. Consume the
	# airborne mantle intent immediately on landing so held Space cannot turn a
	# grounded step contact into a mantle/hang request in the landing frame.
	var grounded_after_move: bool = support.is_grounded()
	if grounded_after_move and not ground_mantle_requested:
		air_mantle_intent_active = false
	var air_mantle_requested: bool = (
		not grounded_after_move
		and jump_held
		and air_mantle_intent_active
	)

	if (
		not collisions.is_empty()
		and not grounded_after_move
		and not step_traversal_active
	):
		if air_mantle_requested:
			if ledge_controller.try_enter_mantle_from_contacts(
				contact_intent_direction,
				collisions,
				false,
				true
			):
				step.cancel()
				return
			if (
				ledge_detector.expand_current_candidates()
				and ledge_controller.try_enter_mantle_from_contacts(
					contact_intent_direction,
					collisions,
					false,
					true
				)
			):
				step.cancel()
				return

		if ledge_controller.try_enter_hang_from_normal(delta):
			step.cancel()
			return
		if (
			ledge_detector.expand_current_candidates()
			and ledge_controller.try_enter_hang_from_normal(delta)
		):
			step.cancel()
			return

	if ground_mantle_requested and not collisions.is_empty():
		if ledge_controller.try_enter_mantle_from_contacts(
			input_direction,
			collisions,
			true,
			false
		):
			step.cancel()
			return
		if (
			ledge_detector.expand_current_candidates()
			and ledge_controller.try_enter_mantle_from_contacts(
				input_direction,
				collisions,
				true,
				false
			)
		):
			step.cancel()
			return

	if ground_mantle_requested:
		step.cancel()
		support.release_walkable_support(body)
		_apply_controlled_jump()
		motion_solver.move_vertical_velocity(body, delta)
		velocity_state.capture_controlled_from_composed_body(body)
		velocity_state.apply_to_body(body)

	step.update_after_move(body)
	if not step.is_active():
		step.try_start_from_contacts(
			body,
			support,
			input_direction,
			collisions
		)


func _apply_controlled_jump() -> void:
	velocity_state.apply_controlled_to_body(body)
	motor.apply_jump(body, jump_height)
	velocity_state.capture_controlled_from_body(body)
	velocity_state.apply_to_body(body)
