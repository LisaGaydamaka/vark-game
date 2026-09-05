extends CharacterBody3D


enum LocomotionState {
	NORMAL,
	LEDGE_CATCH,
	LEDGE_HANG,
	LEDGE_CORNER,
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


@export_category("Ledge Corner")
@export var ledge_corner_turn_speed_degrees: float = 720.0


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
var ledge_corner: PlayerLedgeCorner

var locomotion_state: int = LocomotionState.NORMAL
var ledge_view_center_yaw: float = 0.0
var ledge_view_yaw_offset: float = 0.0
var jump_regrab_candidate: PlayerLedgeDetector.LedgeCandidate = null


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
		jump_height,
		gravity,
		ledge_detector
	)

	ledge_corner = PlayerLedgeCorner.new(
		ledge_corner_turn_speed_degrees,
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

	if locomotion_state == LocomotionState.LEDGE_CORNER:
		update_ledge_corner(
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

	var ledge_detection_allowed: bool = (
		not support.has_support
		and not step_up.is_active()
	)
	var view_forward: Vector3 = (
		-head.global_transform.basis.z
	)

	ledge_detector.update(
		self,
		support,
		ledge_detection_allowed,
		input_direction,
		view_forward
	)

	var candidate: PlayerLedgeDetector.LedgeCandidate = (
		ledge_detector.get_candidate()
	)

	update_jump_regrab_guard()

	if (
		candidate != null
		and candidate.hangable
		and not is_jump_regrab_blocked(candidate)
		and ledge_catch.try_start(
			self,
			candidate
		)
	):
		step_up.cancel_traversal()
		ledge_detector.clear_candidate()
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

	if ledge_catch.has_failed():
		var failed_candidate: PlayerLedgeDetector.LedgeCandidate = (
			ledge_catch.get_failed_candidate()
		)

		if failed_candidate != null:
			ledge_detector.suppress_candidate(
				failed_candidate
			)

		var failure_description: String = (
			ledge_catch.take_failure_description()
		)
		exit_ledge_view()
		locomotion_state = LocomotionState.NORMAL

		if ledge_debug_logging:
			print(
				"Ledge catch failed: ",
				failure_description
			)

		return

	if not ledge_catch.is_active():
		exit_ledge_view()
		locomotion_state = LocomotionState.NORMAL


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
		release_ledge_to_air(
			input_direction,
			delta
		)
		return

	if action == PlayerLedgeHang.Action.LOST_LEDGE:
		release_ledge_to_air(
			input_direction,
			delta
		)

		if ledge_debug_logging:
			print("Ledge hang lost valid geometry")

		return

	if action == PlayerLedgeHang.Action.MANTLE_REQUEST:
		if ledge_debug_logging:
			print(
				"Mantle requested; ",
				"mantle traversal is not implemented yet"
			)
		return

	if action == PlayerLedgeHang.Action.SHIMMY_BLOCKED:
		var shimmy_direction: Vector3 = (
			ledge_hang.take_blocked_shimmy_direction()
		)
		var corner_candidate: PlayerLedgeCorner.CornerCandidate = (
			ledge_corner.find_candidate(
				self,
				support,
				ledge_hang.get_candidate(),
				ledge_hang.get_segment_wall_normal(),
				shimmy_direction
			)
		)

		if (
			corner_candidate != null
			and ledge_corner.try_start(
				self,
				corner_candidate
			)
		):
			locomotion_state = LocomotionState.LEDGE_CORNER
			update_ledge_view_center(
				ledge_corner.get_current_wall_normal()
			)

			if ledge_debug_logging:
				print("Ledge corner entered")

		return

	if action == PlayerLedgeHang.Action.DIRECTIONAL_JUMP:
		var released_candidate: PlayerLedgeDetector.LedgeCandidate = (
			ledge_hang.get_candidate()
		)

		if released_candidate != null:
			jump_regrab_candidate = released_candidate

		ledge_hang.apply_directional_jump(
			self,
			input_direction
		)
		ledge_hang.cancel()
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


func update_ledge_corner(
	jump_pressed: bool,
	crouch_pressed: bool,
	delta: float
) -> void:
	var input_direction: Vector3 = (
		player_input.get_movement_direction(
			head.global_transform
		)
	)

	if crouch_pressed:
		release_corner_to_air(
			input_direction,
			delta
		)
		return

	if jump_pressed:
		if (
			input_direction.length_squared()
			> LOOK_DIRECTION_EPSILON_SQUARED
		):
			var released_candidate: PlayerLedgeDetector.LedgeCandidate = (
				ledge_corner.get_release_candidate()
			)

			if released_candidate != null:
				jump_regrab_candidate = released_candidate

			ledge_hang.apply_directional_jump(
				self,
				input_direction
			)
			ledge_corner.cancel()
			ledge_hang.cancel()
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
			return

		if ledge_debug_logging:
			print(
				"Mantle requested during ledge corner; ",
				"mantle traversal is not implemented yet"
			)
		return

	if not ledge_corner.update(self, delta):
		release_corner_to_air(
			input_direction,
			delta
		)

		if ledge_debug_logging:
			print("Ledge corner lost valid traversal")

		return

	update_ledge_view_center(
		ledge_corner.get_current_wall_normal()
	)

	if ledge_corner.has_completed():
		var completed_candidate: PlayerLedgeDetector.LedgeCandidate = (
			ledge_corner.take_completed_candidate()
		)

		if completed_candidate == null:
			release_corner_to_air(
				input_direction,
				delta
			)
			return

		ledge_hang.start(completed_candidate)
		velocity = Vector3.ZERO
		locomotion_state = LocomotionState.LEDGE_HANG
		update_ledge_view_center(
			completed_candidate.wall_normal
		)

		if ledge_debug_logging:
			print("Ledge corner completed")


func release_ledge_to_air(
	input_direction: Vector3,
	delta: float
) -> void:
	var released_candidate: PlayerLedgeDetector.LedgeCandidate = (
		ledge_hang.get_candidate()
	)

	if released_candidate != null:
		ledge_detector.suppress_candidate(
			released_candidate
		)

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


func release_corner_to_air(
	input_direction: Vector3,
	delta: float
) -> void:
	var released_candidate: PlayerLedgeDetector.LedgeCandidate = (
		ledge_corner.get_release_candidate()
	)

	if released_candidate != null:
		ledge_detector.suppress_candidate(
			released_candidate
		)

	ledge_corner.cancel()
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


func update_jump_regrab_guard() -> void:
	if jump_regrab_candidate == null:
		return

	if velocity.y <= 0.0:
		jump_regrab_candidate = null
		return

	var edge_offset: Vector3 = (
		jump_regrab_candidate.edge_point
		- global_position
	)
	var horizontal_edge_offset: Vector3 = Vector3(
		edge_offset.x,
		0.0,
		edge_offset.z
	)

	if (
		horizontal_edge_offset.length()
		> ledge_detector.get_max_horizontal_reach()
	):
		jump_regrab_candidate = null
		return

	if (
		edge_offset.y
		< ledge_detector.get_min_edge_height()
		or edge_offset.y
		> ledge_detector.get_max_catch_height()
	):
		jump_regrab_candidate = null


func is_jump_regrab_blocked(
	candidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	if (
		jump_regrab_candidate == null
		or candidate == null
	):
		return false

	if (
		candidate.wall_collider_rid
		!= jump_regrab_candidate.wall_collider_rid
	):
		return false

	if (
		candidate.wall_shape_index >= 0
		and jump_regrab_candidate.wall_shape_index >= 0
		and candidate.wall_shape_index
		!= jump_regrab_candidate.wall_shape_index
	):
		return false

	if (
		absf(
			candidate.edge_point.y
			- jump_regrab_candidate.edge_point.y
		)
		> ledge_detector.get_shimmy_level_tolerance()
	):
		return false

	var edge_delta: Vector3 = (
		candidate.edge_point
		- jump_regrab_candidate.edge_point
	)
	var horizontal_edge_delta: Vector3 = Vector3(
		edge_delta.x,
		0.0,
		edge_delta.z
	)

	return (
		horizontal_edge_delta.length()
		<= ledge_detector.get_max_horizontal_reach()
	)


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

	var toward_wall: Vector3 = -wall_normal
	toward_wall.y = 0.0

	if (
		toward_wall.length_squared()
		<= LOOK_DIRECTION_EPSILON_SQUARED
	):
		ledge_view_center_yaw = rotation.y
		ledge_view_yaw_offset = 0.0
		head.rotation.y = 0.0
		return

	toward_wall = toward_wall.normalized()
	ledge_view_center_yaw = atan2(
		-toward_wall.x,
		-toward_wall.z
	)

	var view_yaw: float = atan2(
		-view_forward.x,
		-view_forward.z
	)
	var yaw_limit: float = deg_to_rad(
		HANG_LOOK_YAW_LIMIT_DEGREES
	)
	ledge_view_yaw_offset = clampf(
		wrapf(
			view_yaw - ledge_view_center_yaw,
			-PI,
			PI
		),
		-yaw_limit,
		yaw_limit
	)

	rotation.y = wrapf(
		ledge_view_center_yaw
		+ ledge_view_yaw_offset,
		-PI,
		PI
	)
	head.rotation.y = 0.0


func update_ledge_view_center(
	wall_normal: Vector3
) -> void:
	var toward_wall: Vector3 = -wall_normal
	toward_wall.y = 0.0

	if (
		toward_wall.length_squared()
		<= LOOK_DIRECTION_EPSILON_SQUARED
	):
		return

	toward_wall = toward_wall.normalized()
	ledge_view_center_yaw = atan2(
		-toward_wall.x,
		-toward_wall.z
	)
	var yaw_limit: float = deg_to_rad(
		HANG_LOOK_YAW_LIMIT_DEGREES
	)
	ledge_view_yaw_offset = clampf(
		ledge_view_yaw_offset,
		-yaw_limit,
		yaw_limit
	)
	rotation.y = wrapf(
		ledge_view_center_yaw
		+ ledge_view_yaw_offset,
		-PI,
		PI
	)
	head.rotation.y = 0.0


func exit_ledge_view() -> void:
	head.rotation.y = 0.0
	ledge_view_center_yaw = rotation.y
	ledge_view_yaw_offset = 0.0


func is_ledge_view_active() -> bool:
	return (
		locomotion_state == LocomotionState.LEDGE_CATCH
		or locomotion_state == LocomotionState.LEDGE_HANG
		or locomotion_state == LocomotionState.LEDGE_CORNER
	)


func apply_ledge_yaw_motion(
	yaw_motion: float
) -> void:
	var yaw_limit: float = deg_to_rad(
		HANG_LOOK_YAW_LIMIT_DEGREES
	)
	ledge_view_yaw_offset = clampf(
		ledge_view_yaw_offset + yaw_motion,
		-yaw_limit,
		yaw_limit
	)
	rotation.y = wrapf(
		ledge_view_center_yaw
		+ ledge_view_yaw_offset,
		-PI,
		PI
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
			apply_ledge_yaw_motion(yaw_motion)
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
