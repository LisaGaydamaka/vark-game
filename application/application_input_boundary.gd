class_name ApplicationInputBoundary
extends Node


signal application_input_received(event: InputEvent)


var current_player: Node = null
var gameplay_enabled: bool = false
var look_enabled: bool = false

var _last_sampled_physics_frame: int = -1
var _last_locomotion_command: PlayerCommand = PlayerCommand.new()
var _jump_blocked_until_release: bool = false
var _crouch_blocked_until_release: bool = false
var _interact_blocked_until_release: bool = false
var _last_interaction_sampled_physics_frame: int = -1
var _last_interaction_pressed: bool = false


func bind_player(player: Node) -> void:
	if current_player == player:
		return

	if current_player != null and is_instance_valid(current_player):
		current_player.call("set_interaction_input_enabled", false)
		current_player.call("bind_gameplay_input_boundary", null)

	current_player = player
	_last_sampled_physics_frame = -1
	_last_locomotion_command = PlayerCommand.new()
	_last_interaction_sampled_physics_frame = -1
	_last_interaction_pressed = false

	if current_player != null:
		current_player.call("bind_gameplay_input_boundary", self)
		current_player.call("set_interaction_input_enabled", gameplay_enabled)
		if look_enabled:
			current_player.call("capture_look_mouse")


func set_gameplay_enabled(enabled: bool) -> void:
	if gameplay_enabled == enabled:
		return

	gameplay_enabled = enabled
	_last_sampled_physics_frame = -1
	_last_locomotion_command = PlayerCommand.new()
	_last_interaction_sampled_physics_frame = -1
	_last_interaction_pressed = false
	if current_player != null and is_instance_valid(current_player):
		current_player.call("set_interaction_input_enabled", enabled)

	if enabled:
		# A press that began while the domain was disabled is not a fresh gameplay
		# edge. Edge-dependent actions remain blocked until release.
		_jump_blocked_until_release = (
			Input.is_action_pressed("jump")
			or Input.is_action_just_pressed("jump")
		)
		_crouch_blocked_until_release = (
			Input.is_action_pressed("crouch")
			or Input.is_action_just_pressed("crouch")
		)
		_interact_blocked_until_release = (
			Input.is_action_pressed("interact")
			or Input.is_action_just_pressed("interact")
		)
		return

	_jump_blocked_until_release = Input.is_action_pressed("jump")
	_crouch_blocked_until_release = Input.is_action_pressed("crouch")
	_interact_blocked_until_release = Input.is_action_pressed("interact")
	if current_player != null and is_instance_valid(current_player):
		current_player.call("cancel_gameplay_input_gestures")


func set_look_enabled(enabled: bool) -> void:
	if look_enabled == enabled:
		return

	look_enabled = enabled
	if enabled:
		if current_player != null and is_instance_valid(current_player):
			current_player.call("capture_look_mouse")
		return

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func sample_locomotion_command() -> PlayerCommand:
	var physics_frame: int = Engine.get_physics_frames()
	if physics_frame == _last_sampled_physics_frame:
		return _last_locomotion_command

	_last_sampled_physics_frame = physics_frame
	var command := PlayerCommand.new()
	if not gameplay_enabled:
		_last_locomotion_command = command
		return _last_locomotion_command

	command.movement_vector = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)
	command.sprint_held = Input.is_action_pressed("sprint")

	var jump_held: bool = Input.is_action_pressed("jump")
	if _jump_blocked_until_release:
		if not jump_held:
			_jump_blocked_until_release = false
	else:
		command.jump_pressed = Input.is_action_just_pressed("jump")
		command.jump_held = jump_held

	var crouch_held: bool = Input.is_action_pressed("crouch")
	if _crouch_blocked_until_release:
		if not crouch_held:
			_crouch_blocked_until_release = false
	else:
		command.crouch_pressed = Input.is_action_just_pressed("crouch")

	_last_locomotion_command = command
	return _last_locomotion_command


func sample_interaction_pressed() -> bool:
	var physics_frame: int = Engine.get_physics_frames()
	if physics_frame == _last_interaction_sampled_physics_frame:
		return _last_interaction_pressed

	_last_interaction_sampled_physics_frame = physics_frame
	_last_interaction_pressed = false
	if not gameplay_enabled:
		return false

	var interact_held: bool = Input.is_action_pressed("interact")
	if _interact_blocked_until_release:
		if not interact_held:
			_interact_blocked_until_release = false
		return false

	_last_interaction_pressed = Input.is_action_just_pressed("interact")
	return _last_interaction_pressed


func route_input_event(event: InputEvent) -> void:
	# Application/UI input remains live independently of world gameplay
	# simulation. Concrete UI decides whether a delivered event is relevant.
	application_input_received.emit(event)

	# Escape remains application input. It is available even when world gameplay
	# or look input is disabled, and preserves the accepted mouse-release action.
	if (
		event is InputEventKey
		and event.pressed
		and event.keycode == KEY_ESCAPE
	):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if not look_enabled:
		return
	if current_player == null or not is_instance_valid(current_player):
		return

	current_player.call("handle_look_input", event)


func get_current_view_pose() -> Dictionary:
	if current_player == null or not is_instance_valid(current_player):
		return {}

	var pose: Dictionary = current_player.call("get_input_view_pose")
	return pose.duplicate(true)


func _unhandled_input(event: InputEvent) -> void:
	route_input_event(event)
