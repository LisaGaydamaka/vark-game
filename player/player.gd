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
var traversal_sensor: PlayerTraversalSensor


func _ready() -> void:
	_create_components()
	player_look.capture_mouse()


func _physics_process(delta: float) -> void:
	var jump_pressed: bool = player_input.is_jump_just_pressed()
	var crouch_pressed: bool = player_input.is_crouch_just_pressed()

	if ledge_controller.is_active():
		step.cancel()
		ledge_controller.update(
			jump_pressed,
			crouch_pressed,
			delta
		)
		traversal_sensor.observe(
			self,
			step,
			ledge_mantle,
			ledge_controller.state
		)
		return

	_update_normal_movement(jump_pressed, crouch_pressed, delta)
	traversal_sensor.observe(
		self,
		step,
		ledge_mantle,
		ledge_controller.state
	)


func _unhandled_input(event: InputEvent) -> void:
	player_look.handle_input(event)


func _create_components() -> void:
	player_input = PlayerInput.new()
	player_look = PlayerLook.new(
		self,
		head,
		mouse_sensitivity
	)
	traversal_sensor = PlayerTraversalSensor.new()

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

	if not collisions.is_empty() and not grounded:
		if jump_held:
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
		motor.apply_jump(self, jump_height)
		movement.move_vertical_velocity(self, delta)

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
