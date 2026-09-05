extends CharacterBody3D


enum LocomotionState {
	NORMAL,
	LEDGE_CATCH,
	LEDGE_HANG,
}


const HANG_LOOK_YAW_LIMIT_DEGREES: float = 179.0
const LOOK_DIRECTION_EPSILON_SQUARED: float = 0.000001


@onready var head: Node3D = $Head
@onready var collision_shape: CollisionShape3D = $CollisionShape3D


@export_category("Movement")
@export var max_speed: float = 4.0
@export var acceleration: float = 28.0


@export_category("Jump")
@export var jump_height: float = 0.75


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
@export var ledge_max_wall_tilt_degrees: float = 15.0
@export var ledge_max_approach_angle_degrees: float = 65.0
@export var ledge_debug_logging: bool = true


@export_category("Look")
@export var mouse_sensitivity: float = 0.007


var player_input: PlayerInput
var support: PlayerSupport
var motor: PlayerMotor
var step_up: PlayerStepUp
var movement: PlayerMovement
var ledge_detector: PlayerLedgeDetector
var ledge_catch: PlayerLedgeCatch
var ledge_hang: PlayerLedgeHang

var locomotion_state: int = LocomotionState.NORMAL


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
		jump_height,
		gravity,
		max_step_height,
		ledge_max_wall_tilt_degrees,
		ledge_max_approach_angle_degrees,
		ledge_debug_logging,
		collision_shape
	)

	ledge_catch = PlayerLedgeCatch.new(
		jump_height,
		gravity,
		collision_shape
	)

	ledge_hang = PlayerLedgeHang.new(
		max_speed,
		air_max_speed,
		jump_height,
		gravity,
		ledge_detector
	)


func _physics_process(
	delta: float
) -> void:
	var jump_pressed: bool = (
		player_input.is_jump_just_pressed()
	)
	var crouch_pressed: bool = (
		player_input.is_crouch_just_pressed()
	)

	if locomotion_state == LocomotionState.LEDGE_CATCH:
		update_ledge_catch(delta)
		return

	if locomotion_state == LocomotionState.LEDGE_HANG:
		update_ledge_hang(
			jump_pressed,
			crouch_pressed,
			delta
		)
		return

	update_normal_movement(
		jump_pressed,
		delta
	)


func update_normal_movement(
	jump_pressed: bool,
	delta: float
) -> void:
	var input_direction: Vector3 = (
		player_input.get_movement_direction(
			global_transform
		)
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

	ledge_detector.update(
		self,
		support,
		step_up.is_active()
	)

	var candidate: PlayerLedgeDetector.LedgeCandidate = (
		ledge_detector.get_candidate()
	)

	if (
		candidate != null
		and candidate.hangable
		and ledge_catch.try_start(
			self,
			candidate
		)
	):
		step_up.cancel_traversal()
		enter_ledge_view(candidate.wall_normal)
		locomotion_state = LocomotionState.LEDGE_CATCH
		ledge_catch.update(self, delta)
		finish_ledge_catch_if_ready()
		return

	movement.move(
		self,
		support,
		input_direction,
		not jump_accepted,
		delta
	)

	support.update(self)


func update_ledge_catch(
	delta: float
) -> void:
	ledge_catch.update(self, delta)
	finish_ledge_catch_if_ready()


func finish_ledge_catch_if_ready() -> void:
	if ledge_catch.has_completed():
		var candidate: PlayerLedgeDetector.LedgeCandidate = (
			ledge_catch.take_completed_candidate()
		)

		if candidate != null:
			ledge_hang.start(candidate)
			locomotion_state = LocomotionState.LEDGE_HANG
			velocity = Vector3.ZERO

			if ledge_debug_logging:
				print("Ledge hang entered")

			return

	if not ledge_catch.is_active():
		exit_ledge_view()
		locomotion_state = LocomotionState.NORMAL

		if ledge_debug_logging:
			print("Ledge catch failed")


func update_ledge_hang(
	jump_pressed: bool,
	crouch_pressed: bool,
	delta: float
) -> void:
	var input_direction: Vector3 = (
		player_input.get_movement_direction(
			head.global_transform
		)
	)
	var action: int = ledge_hang.update(
		self,
		support,
		input_direction,
		jump_pressed,
		crouch_pressed,
		delta
	)

	if action == PlayerLedgeHang.Action.DROP:
		ledge_hang.cancel()
		exit_ledge_view()
		locomotion_state = LocomotionState.NORMAL
		velocity = Vector3.DOWN * gravity * delta
		movement.move(
			self,
			support,
			input_direction,
			false,
			delta
		)
		support.update(self)
		return

	if (
		action == PlayerLedgeHang.Action.JUMP
		or action == PlayerLedgeHang.Action.MANTLE
	):
		if (
			action == PlayerLedgeHang.Action.MANTLE
			and ledge_debug_logging
		):
			print(
				"Mantle intent detected; ",
				"mantle traversal is Step 3, ",
				"so this falls back to hang jump"
			)

		ledge_hang.apply_jump_away(self)
		exit_ledge_view()
		locomotion_state = LocomotionState.NORMAL
		movement.move(
			self,
			support,
			input_direction,
			false,
			delta
		)
		support.update(self)


func enter_ledge_view(
	wall_normal: Vector3
) -> void:
	var view_forward: Vector3 = (
		-head.global_transform.basis.z
	)
	view_forward.y = 0.0

	if (
		view_forward.length_squared()
		<= LOOK_DIRECTION_EPSILON_SQUARED
	):
		view_forward = -global_transform.basis.z
		view_forward.y = 0.0

	view_forward = view_forward.normalized()

	var look_target: Vector3 = (
		global_position
		- wall_normal
	)
	look_target.y = global_position.y
	look_at(
		look_target,
		Vector3.UP,
		false
	)

	var body_forward: Vector3 = (
		-global_transform.basis.z
	)
	var body_right: Vector3 = (
		global_transform.basis.x
	)
	body_forward.y = 0.0
	body_right.y = 0.0
	body_forward = body_forward.normalized()
	body_right = body_right.normalized()

	var yaw_offset: float = atan2(
		-view_forward.dot(body_right),
		view_forward.dot(body_forward)
	)
	var yaw_limit: float = deg_to_rad(
		HANG_LOOK_YAW_LIMIT_DEGREES
	)
	head.rotation.y = clampf(
		yaw_offset,
		-yaw_limit,
		yaw_limit
	)


func exit_ledge_view() -> void:
	rotate_y(head.rotation.y)
	head.rotation.y = 0.0


func is_ledge_view_active() -> bool:
	return (
		locomotion_state == LocomotionState.LEDGE_CATCH
		or locomotion_state == LocomotionState.LEDGE_HANG
	)


func _unhandled_input(
	event: InputEvent
) -> void:
	if event is InputEventMouseMotion:
		var yaw_motion: float = (
			-event.relative.x
			* mouse_sensitivity
		)

		if is_ledge_view_active():
			head.rotate_y(yaw_motion)

			var yaw_limit: float = deg_to_rad(
				HANG_LOOK_YAW_LIMIT_DEGREES
			)
			head.rotation.y = clampf(
				head.rotation.y,
				-yaw_limit,
				yaw_limit
			)
		else:
			rotate_y(yaw_motion)

		head.rotate_x(
			-event.relative.y
			* mouse_sensitivity
		)

		head.rotation.x = clampf(
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
