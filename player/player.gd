extends CharacterBody3D


@onready var head: Node3D = $Head
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var player_mesh: MeshInstance3D = $MeshInstance3D


@export_category("Settings")
@export var locomotion_settings: PlayerLocomotionSettings = PlayerLocomotionSettings.new()
@export var stance_settings: PlayerStanceSettings = PlayerStanceSettings.new()
@export var traversal_settings: PlayerTraversalSettings = PlayerTraversalSettings.new()


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
		locomotion_settings.max_walkable_slope,
		locomotion_settings.support_check_distance,
		collision_shape
	)

	motor = PlayerMotor.new(
		locomotion_settings.max_speed,
		locomotion_settings.acceleration,
		locomotion_settings.ground_deceleration,
		locomotion_settings.gravity,
		locomotion_settings.static_friction_coefficient,
		locomotion_settings.kinetic_friction_coefficient,
		locomotion_settings.air_max_speed,
		locomotion_settings.air_acceleration,
		locomotion_settings.air_deceleration
	)

	motion_solver = PlayerMotionSolver.new(
		locomotion_settings.max_collision_iterations
	)

	step = PlayerStep.new(
		locomotion_settings.step_max_height,
		locomotion_settings.step_up_acceleration,
		locomotion_settings.step_up_max_speed,
		collision_shape
	)

	ledge_detector = PlayerLedgeDetectorLazy.new(
		locomotion_settings.jump_height,
		locomotion_settings.gravity,
		head.position.y,
		traversal_settings.ledge_max_wall_tilt_degrees,
		traversal_settings.ledge_max_line_tilt_degrees,
		traversal_settings.ledge_max_approach_angle_degrees,
		collision_shape
	)

	crouch = PlayerCrouch.new(
		collision_shape,
		head,
		player_mesh,
		stance_settings.crouch_height,
		ledge_detector
	)

	ledge_catch = PlayerLedgeCatch.new(
		locomotion_settings.jump_height,
		locomotion_settings.gravity,
		ledge_detector,
		collision_shape
	)

	ledge_hang = PlayerLedgeHang.new(
		locomotion_settings.max_speed,
		locomotion_settings.acceleration,
		ledge_detector
	)

	ledge_corner = PlayerLedgeCorner.new(
		traversal_settings.ledge_corner_turn_speed_degrees,
		ledge_detector
	)

	ledge_mantle = PlayerMantle.new(
		traversal_settings.mantle_speed,
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
		locomotion_settings.jump_height,
		locomotion_settings.max_speed,
		traversal_settings.ledge_jump_horizontal_speed,
		traversal_settings.ledge_sprint_jump_horizontal_speed,
		traversal_settings.ledge_max_approach_angle_degrees,
		locomotion_settings.gravity
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
		locomotion_settings.max_speed,
		locomotion_settings.sprint_speed,
		stance_settings.crouch_speed,
		locomotion_settings.jump_height
	)
