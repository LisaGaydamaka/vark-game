extends CharacterBody3D


@onready var head: Node3D = $Head
@onready var collision_shape: CollisionShape3D = $CollisionShape3D


@export_category("Movement")
@export var max_speed: float = 4.0
@export var sprint_speed: float = 6.0
@export var acceleration: float = 28.0
@export var ground_deceleration: float = 15.0


@export_category("Jump")
@export var jump_height: float = 0.75


@export_category("Ledge Jump")
@export var ledge_jump_horizontal_speed: float = 2.5
@export var ledge_sprint_jump_horizontal_speed: float = 4.0


@export_category("Air")
@export var air_max_speed: float = 2.5
@export var air_acceleration: float = 8.0
@export var air_deceleration: float = 6.0


@export_category("Surface")
@export var max_walkable_slope: float = 45.0
@export var support_check_distance: float = 0.05
@export var static_friction_coefficient: float = 1.0
@export var kinetic_friction_coefficient: float = 0.8


@export_category("Gravity")
@export var gravity: float = 12.0


@export_category("Collision")
@export var max_collision_iterations: int = 8


@export_category("Step Up")
@export var max_step_height: float = 0.5
@export var max_riser_tilt_degrees: float = 5.0
@export var step_up_acceleration: float = 80.0
@export var max_step_up_speed: float = 5.0


@export_category("Ledge Detection")
@export var ledge_max_wall_tilt_degrees: float = 15.0
@export var ledge_max_approach_angle_degrees: float = 65.0
@export var ledge_debug_logging: bool = true


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
var step_up: PlayerStepUp
var movement: PlayerMovement
var ledge_detector: PlayerLedgeDetector
var ledge_catch: PlayerLedgeCatch
var ledge_hang: PlayerLedgeHang
var ledge_corner: PlayerLedgeCorner
var ledge_mantle: PlayerMantle
var ledge_controller: PlayerLedgeController


func _ready() -> void:
	_create_components()
	player_look.capture_mouse()


func _physics_process(delta: float) -> void:
	var jump_pressed: bool = player_input.is_jump_just_pressed()
	var crouch_pressed: bool = player_input.is_crouch_just_pressed()

	if ledge_controller.is_active():
		ledge_controller.update(
			jump_pressed,
			crouch_pressed,
			delta
		)
		return

	_update_normal_movement(
		jump_pressed,
		delta
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

	support = PlayerSupport.new(
		max_walkable_slope,
		support_check_distance
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

	step_up = PlayerStepUp.new(
		max_step_height,
		max_riser_tilt_degrees,
		step_up_acceleration,
		max_step_up_speed,
		collision_shape
	)

	movement = PlayerMovement.new(
		max_collision_iterations,
		step_up
	)

	ledge_detector = PlayerLedgeDetector.new(
		jump_height,
		gravity,
		max_step_height,
		head.position.y,
		ledge_max_wall_tilt_degrees,
		ledge_max_approach_angle_degrees,
		ledge_debug_logging,
		collision_shape
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
		step_up,
		ledge_detector,
		ledge_catch,
		ledge_hang,
		ledge_corner,
		ledge_mantle,
		player_look,
		jump_height,
		max_step_height,
		max_speed,
		ledge_jump_horizontal_speed,
		ledge_sprint_jump_horizontal_speed,
		ledge_max_approach_angle_degrees,
		gravity,
		ledge_debug_logging
	)


func _update_normal_movement(
	jump_pressed: bool,
	delta: float
) -> void:
	var input_direction: Vector3 = player_input.get_movement_direction(global_transform)

	support.update(self)

	var jump_accepted: bool = (
		jump_pressed
		and support.has_support
		and support.walkable
	)

	if jump_accepted:
		step_up.cancel_traversal()

	var ground_target_speed: float = max_speed

	if (
		support.has_support
		and support.walkable
		and not input_direction.is_zero_approx()
		and player_input.is_sprint_pressed()
	):
		ground_target_speed = sprint_speed

	var use_air_control: bool = (
		not (
			support.has_support
			and support.walkable
		)
		and not step_up.is_active()
	)

	motor.update(
		self,
		support,
		input_direction,
		ground_target_speed,
		use_air_control,
		delta
	)

	if jump_accepted:
		motor.apply_jump(
			self,
			jump_height
		)

	ledge_controller.update_transition_guards()

	var ledge_detection_allowed: bool = (
		not support.has_support
		and not step_up.is_active()
	)
	var view_forward: Vector3 = -head.global_transform.basis.z

	ledge_detector.update(
		self,
		support,
		ledge_detection_allowed,
		input_direction,
		view_forward
	)

	if ledge_controller.try_enter_from_normal(
		input_direction,
		delta
	):
		return

	movement.move(
		self,
		support,
		input_direction,
		not jump_accepted,
		delta
	)

	support.update(self)
