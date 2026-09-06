extends CharacterBody3D


enum LocomotionState {
	NORMAL,
	LEDGE_CATCH,
	LEDGE_HANG,
	LEDGE_CORNER,
	LEDGE_MANTLE,
}


const HANG_LOOK_YAW_LIMIT_DEGREES: float = 179.0
const LOOK_DIRECTION_EPSILON_SQUARED: float = 0.000001
const LEDGE_LOCAL_MATCH_MAX_WALL_ANGLE_DEGREES: float = 15.0


@onready var head: Node3D = $Head
@onready var collision_shape: CollisionShape3D = $CollisionShape3D


@export_category("Movement")
@export var max_speed: float = 4.0
@export var sprint_speed: float = 6.0
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


@export_category("Mantle")
@export var mantle_speed: float = 4.0


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
var ledge_mantle: PlayerMantle

var locomotion_state: int = LocomotionState.NORMAL
var ledge_view_center_yaw: float = 0.0
var ledge_view_yaw_offset: float = 0.0

var jump_regrab_candidates: Array[PlayerLedgeDetector.LedgeCandidate] = []
var corner_release_suppression_candidates: Array[PlayerLedgeDetector.LedgeCandidate] = []


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

	if locomotion_state == LocomotionState.LEDGE_MANTLE:
		update_ledge_mantle(
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

	update_jump_regrab_guard()
	update_corner_release_suppression()

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
	var candidate_transition_blocked: bool = (
		candidate != null
		and (
			is_jump_regrab_blocked(candidate)
			or is_corner_release_suppressed(candidate)
		)
	)

	if (
		candidate != null
		and not candidate.hangable
		and not candidate_transition_blocked
		and should_attempt_air_mantle(
			candidate,
			input_direction
		)
	):
		var mantle_candidate: PlayerMantle.MantleCandidate = (
			ledge_mantle.find_air_candidate(
				self,
				support,
				candidate
			)
		)

		if (
			mantle_candidate != null
			and ledge_mantle.try_start(
				self,
				mantle_candidate
			)
		):
			step_up.cancel_traversal()
			ledge_detector.clear_candidate()
			enter_ledge_view(candidate.wall_normal)
			locomotion_state = LocomotionState.LEDGE_MANTLE
			velocity = Vector3.ZERO

			if ledge_debug_logging:
				print("Air mantle entered")

			return

	if (
		candidate != null
		and candidate.hangable
		and not candidate_transition_blocked
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


func should_attempt_air_mantle(
	candidate: PlayerLedgeDetector.LedgeCandidate,
	input_direction: Vector3
) -> bool:
	if candidate == null:
		return false

	if candidate.hangable:
		return false

	if support.has_support or step_up.is_active():
		return false

	var feet_height: float = (
		global_position.y
		+ ledge_detector.get_capsule_bottom_offset()
	)
	var obstacle_height: float = (
		candidate.edge_point.y
		- feet_height
	)

	if obstacle_height <= max_step_height:
		return false

	var horizontal_input: Vector3 = Vector3(
		input_direction.x,
		0.0,
		input_direction.z
	)

	if (
		horizontal_input.length_squared()
		<= LOOK_DIRECTION_EPSILON_SQUARED
	):
		return false

	var toward_wall: Vector3 = -candidate.wall_normal
	toward_wall.y = 0.0

	if (
		toward_wall.length_squared()
		<= LOOK_DIRECTION_EPSILON_SQUARED
	):
		return false

	horizontal_input = horizontal_input.normalized()
	toward_wall = toward_wall.normalized()

	var maximum_approach_angle: float = clampf(
		ledge_max_approach_angle_degrees,
		0.0,
		89.0
	)
	var minimum_alignment: float = cos(
		deg_to_rad(maximum_approach_angle)
	)

	return (
		horizontal_input.dot(toward_wall)
		>= minimum_alignment
	)


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
		var mantle_source: PlayerLedgeDetector.LedgeCandidate = (
			ledge_hang.get_candidate()
		)
		var mantle_candidate: PlayerMantle.MantleCandidate = (
			ledge_mantle.find_candidate(
				self,
				support,
				mantle_source
			)
		)

		if (
			mantle_candidate != null
			and ledge_mantle.try_start(
				self,
				mantle_candidate
			)
		):
			ledge_hang.cancel()
			locomotion_state = LocomotionState.LEDGE_MANTLE
			velocity = Vector3.ZERO

			if ledge_debug_logging:
				print("Ledge mantle entered")

			return

		perform_no_input_hang_jump(
			mantle_source,
			delta
		)

		if ledge_debug_logging:
			print(
				"Mantle invalid; performed hang jump"
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
			ledge_hang.cancel()
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

		arm_jump_regrab_candidate(
			released_candidate
		)

		motor.apply_directional_jump(
			self,
			input_direction,
			jump_height
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
			arm_jump_regrab_guard(
				ledge_corner.get_release_candidates()
			)

			motor.apply_directional_jump(
				self,
				input_direction,
				jump_height
			)
			ledge_corner.cancel()
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

		arm_jump_regrab_guard(
			ledge_corner.get_release_candidates()
		)
		velocity = Vector3.ZERO
		motor.apply_jump(
			self,
			jump_height
		)
		ledge_corner.cancel()
		exit_ledge_view()
		locomotion_state = LocomotionState.NORMAL
		movement.move(
			self,
			support,
			Vector3.ZERO,
			false,
			delta
		)
		support.update(self)

		if ledge_debug_logging:
			print(
				"Mantle unavailable during corner; ",
				"performed hang jump"
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
		var target_reference: PlayerLedgeDetector.LedgeCandidate = (
			ledge_corner.get_target_candidate()
		)
		var target_wall_normal: Vector3 = (
			ledge_corner.get_target_wall_normal()
		)
		var completed_candidate: PlayerLedgeDetector.LedgeCandidate = (
			ledge_detector.find_hang_candidate_at_position(
				self,
				support,
				target_reference,
				target_wall_normal,
				global_position
			)
		)

		if (
			completed_candidate == null
			or not ledge_detector.is_hang_pose_valid(
				self,
				completed_candidate,
				global_position
			)
		):
			release_corner_to_air(
				input_direction,
				delta
			)

			if ledge_debug_logging:
				print(
					"Ledge corner final hang validation failed"
				)
			return

		ledge_corner.cancel()
		ledge_hang.start(completed_candidate)
		velocity = Vector3.ZERO
		locomotion_state = LocomotionState.LEDGE_HANG
		update_ledge_view_center(
			completed_candidate.wall_normal
		)

		if ledge_debug_logging:
			print("Ledge corner completed")


func update_ledge_mantle(
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
		release_mantle_to_air(
			input_direction,
			delta
		)
		return

	if (
		jump_pressed
		and input_direction.length_squared()
		> LOOK_DIRECTION_EPSILON_SQUARED
	):
		arm_jump_regrab_candidate(
			ledge_mantle.get_release_candidate()
		)
		motor.apply_directional_jump(
			self,
			input_direction,
			jump_height
		)
		ledge_mantle.cancel()
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

	if not ledge_mantle.update(self, delta):
		release_mantle_to_air(
			input_direction,
			delta
		)

		if ledge_debug_logging:
			print("Ledge mantle lost valid traversal")

		return

	if not ledge_mantle.has_completed():
		return

	velocity = Vector3.ZERO
	support.update(self)

	if not (
		support.has_support
		and support.walkable
	):
		release_mantle_to_air(
			input_direction,
			delta
		)

		if ledge_debug_logging:
			print("Ledge mantle final support validation failed")

		return

	ledge_mantle.cancel()
	exit_ledge_view()
	locomotion_state = LocomotionState.NORMAL
	velocity = Vector3.ZERO

	if ledge_debug_logging:
		print("Ledge mantle completed")


func perform_no_input_hang_jump(
	released_candidate: PlayerLedgeDetector.LedgeCandidate,
	delta: float
) -> void:
	arm_jump_regrab_candidate(released_candidate)
	velocity = Vector3.ZERO
	motor.apply_jump(
		self,
		jump_height
	)
	ledge_hang.cancel()
	exit_ledge_view()
	locomotion_state = LocomotionState.NORMAL
	movement.move(
		self,
		support,
		Vector3.ZERO,
		false,
		delta
	)
	support.update(self)


func release_mantle_to_air(
	input_direction: Vector3,
	delta: float
) -> void:
	var released_candidate: PlayerLedgeDetector.LedgeCandidate = (
		ledge_mantle.get_release_candidate()
	)

	if released_candidate != null:
		ledge_detector.suppress_candidate(
			released_candidate
		)

	ledge_mantle.cancel()
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
	arm_corner_release_suppression(
		ledge_corner.get_release_candidates()
	)

	ledge_corner.cancel()
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


func arm_jump_regrab_candidate(
	candidate: PlayerLedgeDetector.LedgeCandidate
) -> void:
	jump_regrab_candidates.clear()

	if candidate != null:
		jump_regrab_candidates.append(candidate)


func arm_jump_regrab_guard(
	candidates: Array[PlayerLedgeDetector.LedgeCandidate]
) -> void:
	jump_regrab_candidates.clear()

	for candidate: PlayerLedgeDetector.LedgeCandidate in candidates:
		if candidate != null:
			jump_regrab_candidates.append(candidate)


func update_jump_regrab_guard() -> void:
	if jump_regrab_candidates.is_empty():
		return

	if velocity.y <= 0.0:
		jump_regrab_candidates.clear()
		return

	for candidate_index: int in range(
		jump_regrab_candidates.size() - 1,
		-1,
		-1
	):
		var candidate: PlayerLedgeDetector.LedgeCandidate = (
			jump_regrab_candidates[candidate_index]
		)

		if not is_in_jump_regrab_region(candidate):
			jump_regrab_candidates.remove_at(
				candidate_index
			)


func is_in_jump_regrab_region(
	candidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	if candidate == null:
		return false

	var edge_offset: Vector3 = (
		candidate.edge_point
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
		return false

	return (
		edge_offset.y
		>= ledge_detector.get_min_edge_height()
		and edge_offset.y
		<= ledge_detector.get_max_catch_height()
	)


func is_jump_regrab_blocked(
	candidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	if candidate == null:
		return false

	for guarded_candidate: PlayerLedgeDetector.LedgeCandidate in jump_regrab_candidates:
		if is_same_local_ledge(
			candidate,
			guarded_candidate
		):
			return true

	return false


func arm_corner_release_suppression(
	candidates: Array[PlayerLedgeDetector.LedgeCandidate]
) -> void:
	corner_release_suppression_candidates.clear()

	for candidate: PlayerLedgeDetector.LedgeCandidate in candidates:
		if candidate != null:
			corner_release_suppression_candidates.append(
				candidate
			)


func update_corner_release_suppression() -> void:
	if corner_release_suppression_candidates.is_empty():
		return

	for candidate_index: int in range(
		corner_release_suppression_candidates.size() - 1,
		-1,
		-1
	):
		var candidate: PlayerLedgeDetector.LedgeCandidate = (
			corner_release_suppression_candidates[
				candidate_index
			]
		)

		if not should_keep_corner_release_suppression(
			candidate
		):
			corner_release_suppression_candidates.remove_at(
				candidate_index
			)


func should_keep_corner_release_suppression(
	candidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	if candidate == null:
		return false

	var horizontal_velocity: Vector3 = Vector3(
		velocity.x,
		0.0,
		velocity.z
	)
	var toward_wall: Vector3 = -candidate.wall_normal
	var approach_speed: float = horizontal_velocity.dot(
		toward_wall
	)

	if approach_speed <= 0.0:
		return false

	var edge_offset: Vector3 = (
		candidate.edge_point
		- global_position
	)
	var horizontal_edge_offset: Vector3 = Vector3(
		edge_offset.x,
		0.0,
		edge_offset.z
	)
	var capsule_radius: float = (
		ledge_detector.get_capsule_radius()
	)

	if (
		horizontal_edge_offset.length()
		> (
			ledge_detector.get_max_horizontal_reach()
			+ capsule_radius
		)
	):
		return false

	return (
		edge_offset.y
		>= (
			ledge_detector.get_min_edge_height()
			- capsule_radius
		)
		and edge_offset.y
		<= (
			ledge_detector.get_max_catch_height()
			+ capsule_radius
		)
	)


func is_corner_release_suppressed(
	candidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	if candidate == null:
		return false

	for suppressed_candidate: PlayerLedgeDetector.LedgeCandidate in corner_release_suppression_candidates:
		if is_same_local_ledge(
			candidate,
			suppressed_candidate
		):
			return true

	return false


func is_same_local_ledge(
	first: PlayerLedgeDetector.LedgeCandidate,
	second: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	if first == null or second == null:
		return false

	if (
		first.wall_collider_rid
		!= second.wall_collider_rid
	):
		return false

	if (
		first.wall_shape_index >= 0
		and second.wall_shape_index >= 0
		and first.wall_shape_index
		!= second.wall_shape_index
	):
		return false

	var first_normal: Vector3 = first.wall_normal
	first_normal.y = 0.0

	var second_normal: Vector3 = second.wall_normal
	second_normal.y = 0.0

	if (
		first_normal.length_squared()
		<= LOOK_DIRECTION_EPSILON_SQUARED
		or second_normal.length_squared()
		<= LOOK_DIRECTION_EPSILON_SQUARED
	):
		return false

	first_normal = first_normal.normalized()
	second_normal = second_normal.normalized()

	if (
		first_normal.dot(second_normal)
		< cos(
			deg_to_rad(
				LEDGE_LOCAL_MATCH_MAX_WALL_ANGLE_DEGREES
			)
		)
	):
		return false

	if (
		absf(
			first.edge_point.y
			- second.edge_point.y
		)
		> ledge_detector.get_shimmy_level_tolerance()
	):
		return false

	var edge_delta: Vector3 = (
		first.edge_point
		- second.edge_point
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
		or locomotion_state == LocomotionState.LEDGE_MANTLE
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
