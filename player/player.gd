extends CharacterBody3D


@onready var head: Node3D = $Head
@onready var collision_shape: CollisionShape3D = $CollisionShape3D


@export_category("Movement")
@export var max_speed: float = 4.0
@export var acceleration: float = 28.0


@export_category("Jump")
@export var jump_height: float = 1.0


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
@export var step_up_acceleration: float = 40.0
@export var max_step_up_speed: float = 2.0


@export_category("Ledge Detection")
@export var ledge_wall_check_distance: float = 0.45
@export var ledge_min_reach_height: float = 0.85
@export var ledge_max_reach_height: float = 1.75
@export var ledge_max_horizontal_reach: float = 0.75
@export var ledge_max_wall_tilt_degrees: float = 15.0
@export var ledge_max_approach_angle_degrees: float = 65.0
@export var ledge_max_fall_speed: float = 8.0
@export var ledge_hang_edge_height: float = 1.3
@export var ledge_hang_wall_gap: float = 0.03
@export var ledge_top_probe_inset: float = 0.08
@export var ledge_debug_logging: bool = true


@export_category("Look")
@export var mouse_sensitivity: float = 0.007


var player_input: PlayerInput
var support: PlayerSupport
var motor: PlayerMotor
var step_up: PlayerStepUp
var movement: PlayerMovement
var ledge_detector: PlayerLedgeDetector


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	player_input = PlayerInput.new()

	support = PlayerSupport.new(
		max_walkable_slope,
		support_check_distance
	)

	motor = PlayerMotor.new(
		max_speed,
		acceleration,
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
		ledge_wall_check_distance,
		ledge_min_reach_height,
		ledge_max_reach_height,
		ledge_max_horizontal_reach,
		ledge_max_wall_tilt_degrees,
		ledge_max_approach_angle_degrees,
		ledge_max_fall_speed,
		ledge_hang_edge_height,
		ledge_hang_wall_gap,
		ledge_top_probe_inset,
		ledge_debug_logging,
		collision_shape
	)


func _physics_process(
	delta: float
) -> void:
	var input_direction: Vector3 = (
		player_input.get_movement_direction(
			global_transform
		)
	)
	var jump_pressed: bool = (
		player_input.is_jump_just_pressed()
	)

	support.update(self)

	var jump_accepted: bool = (
		jump_pressed
		and support.has_support
		and support.walkable
	)

	if jump_accepted:
		step_up.cancel_traversal()

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
		use_air_control,
		delta
	)

	if jump_accepted:
		motor.apply_jump(
			self,
			jump_height
		)

	movement.move(
		self,
		support,
		input_direction,
		not jump_accepted,
		delta
	)

	support.update(self)

	ledge_detector.update(
		self,
		support,
		step_up.is_active()
	)


func _unhandled_input(
	event: InputEvent
) -> void:
	if event is InputEventMouseMotion:
		rotate_y(
			-event.relative.x
			* mouse_sensitivity
		)

		head.rotate_x(
			-event.relative.y
			* mouse_sensitivity
		)

		head.rotation.x = clamp(
			head.rotation.x,
			deg_to_rad(-89.0),
			deg_to_rad(89.0)
		)

	elif event is InputEventKey:
		if (
			event.pressed
			and event.keycode == KEY_ESCAPE
		):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
