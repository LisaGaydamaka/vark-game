extends CharacterBody3D


@onready var head: Node3D = $Head
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var player_mesh: MeshInstance3D = $MeshInstance3D


@export_category("Movement")
@export var max_speed: float = 4.0
@export var sprint_speed: float = 6.0
@export var acceleration: float = 28.0
@export var ground_deceleration: float = 15.0


@export_category("Crouch")
@export var crouch_height: float = 0.95
@export var crouch_speed: float = 2.0


@export_category("Jump")
@export var jump_height: float = 0.75


@export_category("Ledge Jump")
@export var ledge_jump_horizontal_speed: float = 2.5
@export var ledge_sprint_jump_horizontal_speed: float = 4.0


@export_category("Air")
@export var air_max_speed: float = 2.5
@export var air_acceleration: float = 20.0
@export var air_deceleration: float = 15.0


@export_category("Surface")
@export var max_walkable_slope: float = 45.0
@export var support_check_distance: float = 0.05
@export var static_friction_coefficient: float = 1.0
@export var kinetic_friction_coefficient: float = 0.4


@export_category("Gravity")
@export var gravity: float = 12.0


@export_category("Collision")
@export var max_collision_iterations: int = 8


@export_category("Step Up")
@export var step_max_height: float = 0.5
@export var step_up_acceleration: float = 100.0
@export var step_up_max_speed: float = 30.0


@export_category("Ledge Detection")
@export var ledge_max_wall_tilt_degrees: float = 15.0
@export var ledge_max_line_tilt_degrees: float = 70.0
@export var ledge_max_approach_angle_degrees: float = 65.0


@export_category("Ledge Corner")
@export var ledge_corner_turn_speed_degrees: float = 720.0


@export_category("Mantle")
@export var mantle_speed: float = 4.0


@export_category("Look")
@export var mouse_sensitivity: float = 0.007


var player_input: PlayerInput
var player_look: PlayerLook
var support: PlayerSupport
var motor: PlayerMotor
var movement: PlayerMovement
var step: PlayerStep
var crouch: PlayerCrouch
var ledge_detector: PlayerLedgeDetectorLazy
var ledge_catch: PlayerLedgeCatch
var ledge_hang: PlayerLedgeHang
var ledge_corner: PlayerLedgeCorner
var ledge_mantle: PlayerMantle
var ledge_controller: PlayerLedgeController

const STEP_JUMP_DEBUG_RECENT_STEP_FRAMES: int = 8
const STEP_JUMP_DEBUG_MAX_HOLD_FRAMES: int = 60

var step_jump_debug_last_step_frame: int = -1000000
var step_jump_debug_active: bool = false
var step_jump_debug_end_frame: int = -1
var step_jump_debug_state_initialized: bool = false
var step_jump_debug_previous_grounded: bool = false
var step_jump_debug_previous_step_active: bool = false
var step_jump_debug_previous_ledge_state: int = -1


func _ready() -> void:
	_create_components()
	player_look.capture_mouse()


func _physics_process(delta: float) -> void:
	var jump_pressed: bool = player_input.is_jump_just_pressed()
	var jump_held: bool = player_input.is_jump_pressed()
	var crouch_pressed: bool = player_input.is_crouch_just_pressed()

	_step_jump_debug_begin_frame(jump_pressed, jump_held)

	if ledge_controller.is_active():
		step.cancel()
		ledge_controller.update(
			jump_pressed,
			crouch_pressed,
			delta
		)
		_step_jump_debug_end_frame(jump_held)
		return

	_update_normal_movement(jump_pressed, crouch_pressed, delta)
	_step_jump_debug_end_frame(jump_held)


func _unhandled_input(event: InputEvent) -> void:
	player_look.handle_input(event)


func _create_components() -> void:
	player_input = PlayerInput.new()
	player_look = PlayerLook.new(
		self,
		head,
		mouse_sensitivity
	)
	support = PlayerSupport.new(
		max_walkable_slope,
		support_check_distance,
		collision_shape
	)

	motor = PlayerMotor.new(
		max_speed,
		acceleration,
		ground_deceleration,
		gravity,
		static_friction_coefficient,
		kinetic_friction_coefficient,
		air_max_speed,
		air_acceleration,
		air_deceleration
	)

	movement = PlayerMovement.new(max_collision_iterations)

	step = PlayerStep.new(
		step_max_height,
		step_up_acceleration,
		step_up_max_speed,
		collision_shape
	)

	ledge_detector = PlayerLedgeDetectorLazy.new(
		jump_height,
		gravity,
		head.position.y,
		ledge_max_wall_tilt_degrees,
		ledge_max_line_tilt_degrees,
		ledge_max_approach_angle_degrees,
		collision_shape
	)

	crouch = PlayerCrouch.new(
		collision_shape,
		head,
		player_mesh,
		crouch_height,
		ledge_detector
	)

	ledge_catch = PlayerLedgeCatch.new(
		jump_height,
		gravity,
		ledge_detector,
		collision_shape
	)

	ledge_hang = PlayerLedgeHang.new(
		max_speed,
		acceleration,
		ledge_detector
	)

	ledge_corner = PlayerLedgeCorner.new(
		ledge_corner_turn_speed_degrees,
		ledge_detector
	)

	ledge_mantle = PlayerMantle.new(
		mantle_speed,
		ledge_detector
	)

	ledge_controller = PlayerLedgeController.new(
		self,
		head,
		player_input,
		support,
		motor,
		movement,
		ledge_detector,
		ledge_catch,
		ledge_hang,
		ledge_corner,
		ledge_mantle,
		player_look,
		jump_height,
		max_speed,
		ledge_jump_horizontal_speed,
		ledge_sprint_jump_horizontal_speed,
		ledge_max_approach_angle_degrees,
		gravity
	)


func _update_normal_movement(
	jump_pressed: bool,
	crouch_pressed: bool,
	delta: float
) -> void:
	var input_direction: Vector3 = player_input.get_movement_direction(global_transform)
	var jump_held: bool = player_input.is_jump_pressed()

	# Step-up owns persistent Y while active. Clear that temporary vertical state
	# before cancelling so another action hands control back to normal movement
	# without carrying any step-up momentum into it.
	step.constrain_persistent_vertical_velocity(self)
	if crouch_pressed:
		step.cancel()
		crouch.toggle()
	crouch.update(self)
	if jump_held:
		if step.is_active():
			_step_jump_debug_event(
				"STEP_CANCELLED_BY_HELD_JUMP",
				""
			)
		step.cancel()

	# Support reports floor-like contact separately from whether that contact is
	# walkable, so steep slopes can use slope physics without becoming grounded.
	support.update(self)
	var grounded: bool = support.is_grounded()
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
	if jump_pressed:
		_step_jump_debug_event(
			"JUMP_CLASSIFIED",
			"grounded=%s support=%s ground_mantle=%s normal_jump=%s input=%s"
			% [
				str(grounded),
				str(support.has_support),
				str(ground_mantle_requested),
				str(jump_accepted_before_move),
				str(input_direction),
			]
		)

	var ground_target_speed: float = crouch.get_movement_speed(
		max_speed,
		crouch_speed
	)
	if (
		grounded
		and crouch.is_fully_standing()
		and not input_direction.is_zero_approx()
		and player_input.is_sprint_pressed()
	):
		ground_target_speed = sprint_speed

	var use_air_control: bool = not support.has_support
	motor.update(
		self,
		support,
		input_direction,
		ground_target_speed,
		use_air_control,
		delta
	)

	if jump_accepted_before_move:
		motor.apply_jump(self, jump_height)
		_step_jump_debug_event("NORMAL_JUMP_APPLIED", "")

	var step_assist_velocity: Vector3 = Vector3.ZERO
	if not jump_held:
		step_assist_velocity = step.update_before_move(
			self,
			input_direction,
			delta
		)

	var airborne_detection_allowed: bool = not grounded
	var ledge_detection_allowed: bool = (
		airborne_detection_allowed
		or ground_mantle_requested
	)
	# Discover once from the pre-move pose. Post-move collision handling reuses
	# these candidates and only filters/expands them against the actual contacts,
	# avoiding a second full wall/top discovery pass in the same physics frame.
	ledge_detector.update(
		self,
		support,
		ledge_detection_allowed,
		input_direction,
		view_forward
	)
	if airborne_detection_allowed and not jump_held:
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
		var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
		if horizontal_velocity.length_squared() > 0.000001:
			contact_intent_direction = horizontal_velocity.normalized()

	var collisions: Array[KinematicCollision3D] = movement.move(
		self,
		delta,
		step_assist_velocity,
		support
	)
	_step_jump_debug_collisions(collisions)

	if not collisions.is_empty() and not grounded:
		if jump_held:
			if ledge_controller.try_enter_mantle_from_contacts(
				contact_intent_direction,
				collisions,
				false,
				true
			):
				_step_jump_debug_event(
					"AIR_MANTLE_STARTED_WHILE_HELD",
					"expanded=false"
				)
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
				_step_jump_debug_event(
					"AIR_MANTLE_STARTED_WHILE_HELD",
					"expanded=true"
				)
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
			_step_jump_debug_event(
				"GROUND_MANTLE_STARTED",
				"expanded=false"
			)
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
			_step_jump_debug_event(
				"GROUND_MANTLE_STARTED",
				"expanded=true"
			)
			step.cancel()
			return

	if ground_mantle_requested:
		motor.apply_jump(self, jump_height)
		movement.move_vertical_velocity(self, delta)
		_step_jump_debug_event(
			"GROUND_MANTLE_FALLBACK_JUMP_APPLIED",
			""
		)

	step.update_after_move(self)
	if (
		not step.is_active()
		and not jump_held
	):
		if step.try_start_from_contacts(
			self,
			support,
			input_direction,
			collisions
		):
			# A step owns vertical traversal from the instant it is classified. X/Z
			# requires no restoration because collision resolution never erased it.
			step.constrain_persistent_vertical_velocity(self)


func _step_jump_debug_begin_frame(
	jump_pressed: bool,
	jump_held: bool
) -> void:
	var frame: int = Engine.get_physics_frames()
	if step != null and step.is_active():
		step_jump_debug_last_step_frame = frame

	if not jump_pressed or not jump_held:
		return

	var frames_since_step: int = frame - step_jump_debug_last_step_frame
	if (
		frames_since_step < 0
		or frames_since_step > STEP_JUMP_DEBUG_RECENT_STEP_FRAMES
	):
		return

	step_jump_debug_active = true
	step_jump_debug_end_frame = frame + STEP_JUMP_DEBUG_MAX_HOLD_FRAMES
	step_jump_debug_state_initialized = false
	_step_jump_debug_event(
		"JUMP_PRESS_AFTER_STEP",
		"frames_since_step=%d step_active=%s"
		% [
			frames_since_step,
			str(step != null and step.is_active()),
		]
	)


func _step_jump_debug_end_frame(jump_held: bool) -> void:
	var frame: int = Engine.get_physics_frames()
	var step_active: bool = step != null and step.is_active()
	if step_active:
		step_jump_debug_last_step_frame = frame

	if not step_jump_debug_active:
		return

	var grounded: bool = support != null and support.is_grounded()
	var ledge_state: int = (
		ledge_controller.state
		if ledge_controller != null
		else PlayerLedgeController.State.NONE
	)

	if (
		not step_jump_debug_state_initialized
		or grounded != step_jump_debug_previous_grounded
		or step_active != step_jump_debug_previous_step_active
		or ledge_state != step_jump_debug_previous_ledge_state
	):
		_step_jump_debug_event(
			"HELD_STATE_CHANGED",
			"jump_held=%s grounded=%s support=%s step=%s ledge_state=%d"
			% [
				str(jump_held),
				str(grounded),
				str(support != null and support.has_support),
				str(step_active),
				ledge_state,
			]
		)
		step_jump_debug_state_initialized = true
		step_jump_debug_previous_grounded = grounded
		step_jump_debug_previous_step_active = step_active
		step_jump_debug_previous_ledge_state = ledge_state

	if not jump_held:
		_step_jump_debug_event("JUMP_RELEASED", "")
		step_jump_debug_active = false
		return

	if frame >= step_jump_debug_end_frame:
		_step_jump_debug_event("TRACE_TIMEOUT_WHILE_HELD", "")
		step_jump_debug_active = false


func _step_jump_debug_collisions(
	collisions: Array[KinematicCollision3D]
) -> void:
	if not step_jump_debug_active or collisions.is_empty():
		return

	var normals := PackedStringArray()
	var contact_count: int = 0
	for collision: KinematicCollision3D in collisions:
		if collision == null:
			continue
		for collision_index: int in range(collision.get_collision_count()):
			contact_count += 1
			normals.append(str(collision.get_normal(collision_index)))

	_step_jump_debug_event(
		"MOVE_COLLISIONS",
		"collisions=%d contacts=%d normals=[%s]"
		% [
			collisions.size(),
			contact_count,
			", ".join(normals),
		]
	)


func _step_jump_debug_event(
	event_name: String,
	details: String
) -> void:
	if not step_jump_debug_active:
		return

	var line: String = (
		"[STEP_JUMP] frame=%d event=%s pos=%s vel=%s"
		% [
			Engine.get_physics_frames(),
			event_name,
			str(global_position),
			str(velocity),
		]
	)
	if not details.is_empty():
		line += " " + details
	print(line)
