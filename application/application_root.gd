class_name VarkApplication
extends Node


signal quit_requested


const WORLD_SESSION_SCRIPT = preload("res://application/world_session.gd")
const DEFAULT_LOOK_SENSITIVITY: float = 0.007
const MIN_LOOK_SENSITIVITY: float = 0.002
const MAX_LOOK_SENSITIVITY: float = 0.014


enum TopLevelOperation {
	NONE,
	LOAD,
	RESTART,
	MISSION_TRANSITION,
	EXIT,
	NEW_GAME,
}


enum ControlMode {
	GAMEPLAY,
	PAUSE_MENU,
	INVENTORY,
	OBJECTIVES,
	MAP,
	CUTSCENE,
	MENU,
}


@export var default_world_scene: PackedScene

@onready var input_boundary: ApplicationInputBoundary = $InputBoundary
@onready var world_host: Node = $WorldHost
@onready var ui_root: CanvasLayer = $UIRoot
@onready var main_menu: Control = $UIRoot/MainMenu
@onready var menu_actions: VBoxContainer = $UIRoot/MainMenu/Center/Panel/Content/MenuActions
@onready var settings_panel: VBoxContainer = $UIRoot/MainMenu/Center/Panel/Content/SettingsPanel
@onready var new_game_button: Button = $UIRoot/MainMenu/Center/Panel/Content/MenuActions/NewGameButton
@onready var settings_button: Button = $UIRoot/MainMenu/Center/Panel/Content/MenuActions/SettingsButton
@onready var quit_button: Button = $UIRoot/MainMenu/Center/Panel/Content/MenuActions/QuitButton
@onready var look_sensitivity_slider: HSlider = $UIRoot/MainMenu/Center/Panel/Content/SettingsPanel/LookSensitivity
@onready var look_sensitivity_value: Label = $UIRoot/MainMenu/Center/Panel/Content/SettingsPanel/LookSensitivityValue
@onready var settings_back_button: Button = $UIRoot/MainMenu/Center/Panel/Content/SettingsPanel/BackButton

var current_session: Node = null
var current_world: Node = null
var current_player: Node = null
var current_ui: CanvasLayer = null
var active_top_level_operation: int = TopLevelOperation.NONE
var control_mode: int = ControlMode.MENU
var look_sensitivity: float = DEFAULT_LOOK_SENSITIVITY

var _last_session_id: int = 0


func _ready() -> void:
	current_ui = ui_root
	_wire_menu_shell()
	_show_main_menu()


func get_current_session_id() -> int:
	if current_session == null:
		return 0
	return int(current_session.get("session_id"))


func get_current_session_state() -> int:
	if current_session == null:
		return WORLD_SESSION_SCRIPT.State.EMPTY
	return int(current_session.get("state"))


func is_current_session(session_id: int) -> bool:
	return (
		session_id > 0
		and current_session != null
		and session_id == int(current_session.get("session_id"))
	)


func get_control_mode() -> int:
	return control_mode


func is_world_paused() -> bool:
	return (
		current_session != null
		and get_current_session_state() == WORLD_SESSION_SCRIPT.State.PAUSED
	)


func get_gameplay_time_seconds() -> float:
	if current_session == null:
		return 0.0
	return float(current_session.call("get_gameplay_time_seconds"))


func get_current_view_pose() -> Dictionary:
	return input_boundary.get_current_view_pose()


func get_look_sensitivity() -> float:
	return look_sensitivity


func set_look_sensitivity(value: float) -> void:
	look_sensitivity = clampf(
		value,
		MIN_LOOK_SENSITIVITY,
		MAX_LOOK_SENSITIVITY
	)
	_sync_look_sensitivity_ui()
	_apply_look_sensitivity_to_current_player()


func start_new_game() -> bool:
	if default_world_scene == null:
		return false
	if not try_begin_top_level_operation(TopLevelOperation.NEW_GAME):
		return false

	var succeeded: bool = _replace_world(default_world_scene)
	if succeeded:
		_hide_main_menu()
	else:
		_show_main_menu()

	var finished: bool = finish_top_level_operation(TopLevelOperation.NEW_GAME)
	assert(finished, "VarkApplication lost ownership of the new-game operation.")
	return succeeded


func try_begin_top_level_operation(operation: int) -> bool:
	if operation == TopLevelOperation.NONE:
		return false
	if active_top_level_operation != TopLevelOperation.NONE:
		return false

	active_top_level_operation = operation
	return true


func finish_top_level_operation(operation: int) -> bool:
	if operation == TopLevelOperation.NONE:
		return false
	if active_top_level_operation != operation:
		return false

	active_top_level_operation = TopLevelOperation.NONE
	return true


func has_active_top_level_operation() -> bool:
	return active_top_level_operation != TopLevelOperation.NONE


func set_control_mode(mode: int) -> bool:
	if not _is_valid_control_mode(mode):
		return false
	if mode == ControlMode.GAMEPLAY:
		return _enter_gameplay_control()
	return _enter_application_control(mode)


func set_gameplay_input_enabled(enabled: bool) -> bool:
	if (
		enabled
		and (
			get_current_session_state() != WORLD_SESSION_SCRIPT.State.PLAYING
			or control_mode != ControlMode.GAMEPLAY
		)
	):
		return false
	input_boundary.set_gameplay_enabled(enabled)
	return true


func set_look_input_enabled(enabled: bool) -> bool:
	if (
		enabled
		and (
			get_current_session_state() != WORLD_SESSION_SCRIPT.State.PLAYING
			or control_mode != ControlMode.GAMEPLAY
		)
	):
		return false
	input_boundary.set_look_enabled(enabled)
	return true


func stop_current_world() -> bool:
	if current_session == null:
		return false

	var previous_mode: int = control_mode
	_set_world_input_domains(false)
	var stopped: bool = bool(current_session.call("stop_gameplay"))
	if stopped:
		control_mode = ControlMode.MENU
		return true

	if (
		previous_mode == ControlMode.GAMEPLAY
		and get_current_session_state() == WORLD_SESSION_SCRIPT.State.PLAYING
	):
		_set_world_input_domains(true)
	return false


func start_current_world() -> bool:
	if current_session == null:
		return false

	var started: bool = bool(current_session.call("begin_play"))
	if started:
		control_mode = ControlMode.GAMEPLAY
		_set_world_input_domains(true)
	return started


func restart_current_world() -> bool:
	if not try_begin_top_level_operation(TopLevelOperation.RESTART):
		return false

	var scene: PackedScene = default_world_scene
	if current_session != null:
		scene = current_session.get("world_scene") as PackedScene

	var succeeded: bool = _replace_world(scene)
	var finished: bool = finish_top_level_operation(TopLevelOperation.RESTART)
	assert(finished, "VarkApplication lost ownership of the restart operation.")
	return succeeded


func transition_to_world(scene: PackedScene) -> bool:
	if scene == null:
		return false
	if not try_begin_top_level_operation(TopLevelOperation.MISSION_TRANSITION):
		return false

	var succeeded: bool = _replace_world(scene)
	var finished: bool = finish_top_level_operation(TopLevelOperation.MISSION_TRANSITION)
	assert(finished, "VarkApplication lost ownership of the mission transition operation.")
	return succeeded


func exit_current_world() -> bool:
	if not try_begin_top_level_operation(TopLevelOperation.EXIT):
		return false

	_teardown_current_session()
	_show_main_menu()
	var finished: bool = finish_top_level_operation(TopLevelOperation.EXIT)
	assert(finished, "VarkApplication lost ownership of the exit operation.")
	return true


func _replace_world(scene: PackedScene) -> bool:
	if scene == null:
		return false

	_teardown_current_session()
	return _install_world(scene)


func _install_world(scene: PackedScene) -> bool:
	if scene == null or current_session != null:
		return false

	_last_session_id += 1
	var session: Node = WORLD_SESSION_SCRIPT.new()
	session.name = "WorldSession"
	world_host.add_child(session)

	if not bool(session.call("build", _last_session_id, scene)):
		world_host.remove_child(session)
		session.free()
		return false

	current_session = session
	_sync_current_references()
	_apply_look_sensitivity_to_current_player()
	input_boundary.bind_player(current_player)

	if not bool(current_session.call("begin_play")):
		_teardown_current_session()
		return false

	control_mode = ControlMode.GAMEPLAY
	_set_world_input_domains(true)
	return true


func _teardown_current_session() -> void:
	_set_world_input_domains(false)
	input_boundary.bind_player(null)

	if current_session == null:
		current_world = null
		current_player = null
		control_mode = ControlMode.MENU
		return

	var session_state: int = int(current_session.get("state"))
	if (
		session_state == WORLD_SESSION_SCRIPT.State.PLAYING
		or session_state == WORLD_SESSION_SCRIPT.State.PAUSED
	):
		current_session.call("stop_gameplay")

	current_session.call("teardown")
	if current_session.get_parent() == world_host:
		world_host.remove_child(current_session)
	current_session.free()

	current_session = null
	current_world = null
	current_player = null
	control_mode = ControlMode.MENU


func _sync_current_references() -> void:
	if current_session == null:
		current_world = null
		current_player = null
		return

	current_world = current_session.get("world") as Node
	current_player = current_session.get("player") as Node
	assert(
		current_world != null and current_player != null,
		"A built Vark world session must expose its world and player."
	)


func _enter_gameplay_control() -> bool:
	if current_session == null:
		return false

	var session_state: int = get_current_session_state()
	if session_state == WORLD_SESSION_SCRIPT.State.PAUSED:
		if not bool(current_session.call("resume_gameplay")):
			return false
	elif session_state != WORLD_SESSION_SCRIPT.State.PLAYING:
		return false

	control_mode = ControlMode.GAMEPLAY
	_set_world_input_domains(true)
	return true


func _enter_application_control(mode: int) -> bool:
	if mode == ControlMode.GAMEPLAY:
		return false

	if current_session == null:
		if mode != ControlMode.MENU:
			return false
		control_mode = mode
		_set_world_input_domains(false)
		return true

	var session_state: int = get_current_session_state()
	if session_state == WORLD_SESSION_SCRIPT.State.PLAYING:
		_set_world_input_domains(false)
		if not bool(current_session.call("pause_gameplay")):
			if control_mode == ControlMode.GAMEPLAY:
				_set_world_input_domains(true)
			return false
	elif session_state == WORLD_SESSION_SCRIPT.State.PAUSED:
		_set_world_input_domains(false)
	elif session_state == WORLD_SESSION_SCRIPT.State.STOPPED:
		if mode != ControlMode.MENU:
			return false
		_set_world_input_domains(false)
	else:
		return false

	control_mode = mode
	return true


func _is_valid_control_mode(mode: int) -> bool:
	return mode >= ControlMode.GAMEPLAY and mode <= ControlMode.MENU


func _set_world_input_domains(enabled: bool) -> void:
	input_boundary.set_gameplay_enabled(enabled)
	input_boundary.set_look_enabled(enabled)


func _wire_menu_shell() -> void:
	new_game_button.pressed.connect(_on_new_game_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	settings_back_button.pressed.connect(_on_settings_back_pressed)
	look_sensitivity_slider.value_changed.connect(_on_look_sensitivity_changed)
	quit_requested.connect(_quit_application)
	_sync_look_sensitivity_ui()


func _show_main_menu() -> void:
	control_mode = ControlMode.MENU
	_set_world_input_domains(false)
	main_menu.visible = true
	menu_actions.visible = true
	settings_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _hide_main_menu() -> void:
	main_menu.visible = false
	menu_actions.visible = true
	settings_panel.visible = false


func _show_settings() -> void:
	menu_actions.visible = false
	settings_panel.visible = true


func _sync_look_sensitivity_ui() -> void:
	if look_sensitivity_slider != null:
		look_sensitivity_slider.value = look_sensitivity
	if look_sensitivity_value != null:
		look_sensitivity_value.text = "%.3f" % look_sensitivity


func _apply_look_sensitivity_to_current_player() -> void:
	if current_player == null or not is_instance_valid(current_player):
		return
	current_player.call("set_mouse_sensitivity", look_sensitivity)


func _on_new_game_pressed() -> void:
	start_new_game()


func _on_settings_pressed() -> void:
	_show_settings()


func _on_settings_back_pressed() -> void:
	menu_actions.visible = true
	settings_panel.visible = false


func _on_look_sensitivity_changed(value: float) -> void:
	set_look_sensitivity(value)


func _on_quit_pressed() -> void:
	quit_requested.emit()


func _quit_application() -> void:
	get_tree().quit()
