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
@export var step_up_acceleration: float = 32.0
@export var step_up_max_speed: float = 4.0
@export var step_debug_logging: bool = true
@export var step_debug_interval: float = 0.25


@export_category("Ledge Detection")
@export var ledge_max_wall_tilt_degrees: float = 15.0
@export var ledge_max_line_tilt_degrees: float = 70.0
@export var ledge_max_approach_angle_degrees: float = 65.0
@export var ledge_debug_logging: bool = false


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
var ledge_detector: PlayerLedgeDetector
var ledge_catch: PlayerLedgeCatch
var ledge_hang: PlayerLedgeHang
var ledge_corner: PlayerLedgeCorner
var ledge_mantle: PlayerMantle
var ledge_controller: PlayerLedgeController

var step_debug_elapsed: float = 0.0
var step_debug_was_active: bool = false


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

	movement = PlayerMovement.new(max_collision_iterations)

	step = PlayerStep.new(
		step_max_height,
		step_up_acceleration,
		step_up_max_speed,
		collision_shape
	)

	ledge_detector = PlayerLedgeDetector.new(
		jump_height,
		gravity,
		head.position.y,
		ledge_max_wall_tilt_degrees,
		ledge_max_line_tilt_degrees,
		ledge_max_approach_angle_degrees,
		false,
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
		gravity,
		false
	)


func _update_normal_movement(
	jump_pressed: bool,
	delta: float
) -> void:
	var input_direction: Vector3 = player_input.get_movement_direction(global_transform)

	# Step-up is the lowest-priority traversal behavior. Holding Space gives the
	# existing jump/mantle/ledge logic complete control instead.
	if player_input.is_jump_pressed():
		step.cancel()

	# While step-up owns vertical traversal, persistent Y must not accumulate
	# gravity or old vertical momentum behind the temporary assist. Clearing it
	# before the motor means that if step cancels later this frame, normal gravity
	# starts again from zero immediately instead of revealing stored fall speed.
	step.constrain_persistent_vertical_velocity(self)

	support.update(self)
	var grounded: bool = support.is_grounded()
	var view_forward: Vector3 = -head.global_transform.basis.z

	ledge_controller.update_transition_guards()

	# Ground mantle is a discrete request, but geometry alone may not consume it.
	# The real grounded move must physically contact the obstacle first.
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

	var ground_target_speed: float = max_speed
	if (
		grounded
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
		motor.apply_jump(
			self,
			jump_height
		)

	# Normal velocity is persistent. Step-up contributes only a disposable assist
	# used by PlayerMovement for this frame's displacement.
	var step_assist_velocity: Vector3 = Vector3.ZERO
	if not player_input.is_jump_pressed():
		step_assist_velocity = step.update_before_move(
			self,
			input_direction,
			delta
		)

	var airborne_detection_allowed: bool = not grounded
	ledge_detector.update(
		self,
		support,
		airborne_detection_allowed,
		input_direction,
		view_forward
	)
	if (
		airborne_detection_allowed
		and not player_input.is_jump_pressed()
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
		step_assist_velocity
	)

	# A contact can expose a ledge opportunity that was just outside the magnetic
	# discovery volume before movement. Held Space gives mantle first refusal on
	# real contact; if mantle is invalid, a hangable ledge still falls back to hang.
	if not collisions.is_empty() and not grounded:
		ledge_detector.update(
			self,
			support,
			true,
			contact_intent_direction,
			view_forward
		)
		if (
			player_input.is_jump_pressed()
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

	# Ground mantle is evaluated only after that same frame's real movement has
	# produced contact. A probe-visible gap can therefore never start mantle.
	if ground_mantle_requested and not collisions.is_empty():
		ledge_detector.update(
			self,
			support,
			true,
			input_direction,
			view_forward
		)
		if ledge_controller.try_enter_mantle_from_contacts(
			input_direction,
			collisions,
			true,
			false
		):
			step.cancel()
			return

	# If the discrete ground mantle request was not consumed by a real contact,
	# preserve the normal jump in the same physics frame. Horizontal/contact
	# movement has already run, so execute only the takeoff's vertical component.
	if ground_mantle_requested:
		motor.apply_jump(
			self,
			jump_height
		)
		movement.move_vertical_velocity(self, delta)

	# Step-up runs only after every higher-priority traversal path has had a
	# chance to consume the frame. It starts only from a real collision contact,
	# but once active it is allowed both on the ground and in the air.
	step.update_after_move(self)
	if (
		not step.is_active()
		and not player_input.is_jump_pressed()
	):
		step.try_start_from_contacts(
			self,
			support,
			input_direction,
			collisions
		)

	# Refresh support before logging so END lines describe the post-move landing
	# state rather than the grounded value captured before movement.
	support.update(self)
	_update_step_debug(
		input_direction,
		support.is_grounded(),
		step_assist_velocity,
		delta
	)


func _update_step_debug(
	input_direction: Vector3,
	grounded: bool,
	step_assist_velocity: Vector3,
	delta: float
) -> void:
	if not step_debug_logging:
		return

	# Debug output is intentionally silent with no WASD input, including step
	# cancellation caused by releasing movement input.
	if input_direction.is_zero_approx():
		step_debug_elapsed = 0.0
		step_debug_was_active = step.is_active()
		return

	var active_now: bool = step.is_active()
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var horizontal_speed: float = horizontal_velocity.length()

	if active_now and not step_debug_was_active:
		print(
			"[StepUp] START pos=", global_position,
			" input=", input_direction,
			" normal_vel=", velocity,
			" assist=", step_assist_velocity,
			" hspeed=", horizontal_speed,
			" grounded=", grounded,
			" accel=", step_up_acceleration,
			" max_step_speed=", step_up_max_speed
		)
		step_debug_elapsed = 0.0
	elif not active_now and step_debug_was_active:
		print(
			"[StepUp] END pos=", global_position,
			" input=", input_direction,
			" normal_vel=", velocity,
			" discarded_assist=", step_assist_velocity,
			" hspeed=", horizontal_speed,
			" grounded=", grounded
		)
		step_debug_elapsed = 0.0
	elif active_now:
		step_debug_elapsed += delta
		var interval: float = maxf(0.05, step_debug_interval)
		if step_debug_elapsed >= interval:
			print(
				"[StepUp] ACTIVE pos=", global_position,
				" input=", input_direction,
				" normal_vel=", velocity,
				" assist=", step_assist_velocity,
				" hspeed=", horizontal_speed,
				" normal_vspeed=", velocity.y,
				" grounded=", grounded,
				" accel=", step_up_acceleration,
				" max_step_speed=", step_up_max_speed
			)
			step_debug_elapsed = fmod(step_debug_elapsed, interval)
	else:
		step_debug_elapsed = 0.0

	step_debug_was_active = active_now
