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
@export var kinetic_friction_coefficient: float = 0.1


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
var motion_solver: PlayerMotionSolver
var step: PlayerStep
var crouch: PlayerCrouch
var ledge_detector: PlayerLedgeDetectorLazy
var ledge_catch: PlayerLedgeCatch
var ledge_hang: PlayerLedgeHang
var ledge_corner: PlayerLedgeCorner
var ledge_mantle: PlayerMantle
var ledge_controller: PlayerLedgeController
var locomotion_controller: PlayerLocomotionController


func _ready() -> void:
	_create_components()
	player_look.capture_mouse()


func _physics_process(delta: float) -> void:
	var command: PlayerCommand = player_input.sample()

	if ledge_controller.is_active():
		step.cancel()
		ledge_controller.update(
			command.jump_pressed,
			command.crouch_pressed,
			delta
		)
	else:
		locomotion_controller.update(command, delta)


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

	motion_solver = PlayerMotionSolver.new(max_collision_iterations)

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
		ledge_detector,
		crouch
	)

	ledge_controller = PlayerLedgeController.new(
		self,
		head,
		player_input,
		support,
		motor,
		motion_solver,
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

	locomotion_controller = PlayerLocomotionController.new(
		self,
		head,
		support,
		motor,
		motion_solver,
		step,
		crouch,
		ledge_detector,
		ledge_controller,
		max_speed,
		sprint_speed,
		crouch_speed,
		jump_height
	)
