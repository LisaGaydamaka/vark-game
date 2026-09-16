extends CharacterBody3D


@onready var head: Node3D = $Head
@onready var view_camera: Camera3D = $Head/Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var player_mesh: MeshInstance3D = $MeshInstance3D


@export_category("Settings")
@export var locomotion_settings: PlayerLocomotionSettings = PlayerLocomotionSettings.new()
@export var stance_settings: PlayerStanceSettings = PlayerStanceSettings.new()
@export var traversal_settings: PlayerTraversalSettings = PlayerTraversalSettings.new()


@export_category("Look")
@export var mouse_sensitivity: float = 0.007


@export_category("Interaction")
@export var interaction_range: float = 2.5


var gameplay_input_boundary: Node = null
var player_input: PlayerInput
var player_look: PlayerLook
var support: PlayerSupport
var motor: PlayerMotor
var velocity_state: PlayerVelocityState
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
var player_interaction: PlayerInteraction


func _ready() -> void:
	_create_components()


func _physics_process(delta: float) -> void:
	var command: PlayerCommand
	if gameplay_input_boundary != null and is_instance_valid(gameplay_input_boundary):
		command = gameplay_input_boundary.call("sample_locomotion_command") as PlayerCommand
	else:
		# Standalone Player.tscn/movement fixtures retain their direct sampler.
		# The production F5 path always binds the application-owned boundary before
		# the WorldSession enters PLAYING.
		command = player_input.sample()

	var interact_pressed: bool = false
	if gameplay_input_boundary != null and is_instance_valid(gameplay_input_boundary):
		interact_pressed = bool(gameplay_input_boundary.call("sample_interaction_pressed"))
	else:
		interact_pressed = Input.is_action_just_pressed("interact")

	player_input.current_command = command
	velocity_state.apply_to_body(self)

	if ledge_controller.is_active():
		step.cancel()
		ledge_controller.update(
			command.jump_pressed,
			command.crouch_pressed,
			delta
		)
		velocity_state.capture_body_as_controlled(self)
	else:
		locomotion_controller.update(command, delta)
		if ledge_controller.is_active():
			velocity_state.capture_body_as_controlled(self)

	if player_interaction != null:
		player_interaction.update(interact_pressed)


func _unhandled_input(event: InputEvent) -> void:
	# Production input is routed by the application boundary. Standalone scenes
	# keep the old event path so focused player fixtures remain useful.
	if gameplay_input_boundary != null and is_instance_valid(gameplay_input_boundary):
		return
	player_look.handle_input(event)


func bind_gameplay_input_boundary(boundary: Node) -> void:
	gameplay_input_boundary = boundary


func set_interaction_input_enabled(enabled: bool) -> void:
	if player_interaction != null:
		player_interaction.set_input_enabled(enabled)


func set_world_interaction_available(available: bool) -> void:
	if player_interaction != null:
		player_interaction.set_world_interaction_available(available)


func get_interaction_semantic_state() -> Dictionary:
	if player_interaction == null:
		return {
			"available": false,
			"has_target": false,
			"target_name": "",
		}
	return player_interaction.get_semantic_state()


func handle_look_input(event: InputEvent) -> void:
	player_look.handle_input(event)


func capture_look_mouse() -> void:
	player_look.capture_mouse()


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = value
	if player_look != null:
		player_look.mouse_sensitivity = value


func cancel_gameplay_input_gestures() -> void:
	player_input.current_command = PlayerCommand.new()
	if locomotion_controller != null:
		locomotion_controller.air_mantle_intent_active = false


func get_input_view_pose() -> Dictionary:
	return {
		"view_transform": head.global_transform,
		"body_yaw": rotation.y,
		"head_pitch": head.rotation.x,
		"head_yaw": head.rotation.y,
	}


func is_grounded() -> bool:
	return support != null and support.is_grounded()


## Read-only player-facing movement state used by regression traces.
##
## Tests intentionally consume this semantic boundary rather than reaching into
## the current controller/component graph, so later input/controller refactors
## can preserve behavior without preserving today's ownership structure.
func get_movement_semantic_state() -> Dictionary:
	var support_state: String = "airborne"
	if support != null and support.has_support:
		support_state = "grounded" if support.walkable else "steep"

	var stance_state: String = "uninitialized"
	if crouch != null:
		if crouch.is_fully_crouched():
			stance_state = "crouched"
		elif crouch.is_fully_standing():
			stance_state = "standing"
		else:
			stance_state = "transitioning"

	var traversal_state: String = "normal"
	if ledge_controller != null:
		match ledge_controller.state:
			PlayerLedgeController.State.CATCHING:
				traversal_state = "catching"
			PlayerLedgeController.State.HANGING:
				traversal_state = "hanging"
			PlayerLedgeController.State.CORNERING:
				traversal_state = "cornering"
			PlayerLedgeController.State.MANTLING:
				traversal_state = "mantling"

	return {
		"position": global_position,
		"velocity": velocity,
		"support": support_state,
		"stance": stance_state,
		"traversal": traversal_state,
	}


func _create_components() -> void:
	player_input = PlayerInput.new()
	velocity_state = PlayerVelocityState.new()
	player_look = PlayerLook.new(
		self,
		head,
		mouse_sensitivity
	)
	player_interaction = PlayerInteraction.new(
		self,
		view_camera,
		interaction_range
	)
	support = PlayerSupport.new(
		locomotion_settings.max_walkable_slope,
		locomotion_settings.support_check_distance,
		collision_shape
	)

	motor = PlayerMotor.new(
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
		velocity_state,
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
