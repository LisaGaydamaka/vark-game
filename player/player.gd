extends CharacterBody3D


@onready var head: Node3D = $Head


@export_category("Movement")

@export var max_speed: float = 3.0
@export var acceleration: float = 28.0


@export_category("Surface")

@export var max_walkable_slope: float = 45.0

@export var support_check_distance: float = 0.05

@export var static_friction_coefficient: float = 1.0

@export var kinetic_friction_coefficient: float = 0.8


@export_category("Gravity")

@export var gravity: float = 12.0


@export_category("Collision")

@export var max_collision_iterations: int = 8


@export_category("Look")

@export var mouse_sensitivity: float = 0.002


@export_category("Step Up")

# How strongly the player must push into a surface
# before the collision can be considered for stepping.
@export var step_push_threshold: float = 0.1


# How much intended forward movement may remain before
# the player is considered blocked.
#
# 1.0 = full progress
# 0.0 = completely blocked
@export var step_progress_ratio_threshold: float = 0.25


# Maximum obstacle height that can receive step-up
# assistance.
@export var max_step_height: float = 0.5


# Small offset above max_step_height used by the
# height probe.
@export var step_height_epsilon: float = 0.01


# Must match the radius of the player's capsule collider.
@export var capsule_radius: float = 0.4


# Extra tolerance for determining whether a collision
# belongs to the lower capsule region.
@export var step_contact_epsilon: float = 0.02


# Upward acceleration supplied while a valid step
# is active.
@export var step_acceleration: float = 20.0


# Maximum upward velocity supplied by step assistance.
@export var step_max_speed: float = 3.0


var player_input: PlayerInput
var support: PlayerSupport
var motor: PlayerMotor
var step_up: PlayerStepUp
var movement: PlayerMovement


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
		kinetic_friction_coefficient
	)

	step_up = PlayerStepUp.new(
		step_push_threshold,
		max_step_height,
		step_height_epsilon,
		capsule_radius,
		step_contact_epsilon
	)

	step_up.upward_acceleration = step_acceleration
	step_up.max_upward_speed = step_max_speed

	movement = PlayerMovement.new(
		max_collision_iterations,
		step_push_threshold,
		step_progress_ratio_threshold,
		step_up
	)


func _physics_process(
	delta: float
) -> void:
	var input_direction: Vector3 = (
		player_input.get_movement_direction(
			global_transform
		)
	)

	# Update support before calculating movement.
	support.update(
		self
	)

	# Normal horizontal movement and gravity.
	motor.update(
		self,
		support,
		input_direction,
		delta
	)

	# Apply upward assistance from a step detected
	# during the previous movement frame.
	step_up.apply_acceleration(
		self,
		delta
	)

	# Move the player and detect a valid step for
	# the next frame.
	movement.move(
		self,
		input_direction,
		support,
		delta
	)

	# Refresh support after movement.
	support.update(
		self
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
			Input.mouse_mode = (
				Input.MOUSE_MODE_VISIBLE
			)
