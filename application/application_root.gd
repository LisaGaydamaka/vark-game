class_name VarkApplication
extends Node


signal quit_requested


const WORLD_SESSION_SCRIPT = preload("res://application/world_session.gd")
const MISSION_DEFINITION_SCRIPT = preload("res://missions/mission_definition.gd")
const DEFAULT_LOOK_SENSITIVITY: float = 0.007
const MIN_LOOK_SENSITIVITY: float = 0.002
const MAX_LOOK_SENSITIVITY: float = 0.014

const APPLICATION_HOTKEY_NONE: StringName = &""
const APPLICATION_HOTKEY_QUICKSAVE: StringName = &"quicksave"
const APPLICATION_HOTKEY_QUICKLOAD: StringName = &"quickload"
const APPLICATION_HOTKEY_RESTART: StringName = &"restart"


enum TopLevelOperation {
	NONE,
	LOAD,
	RESTART,
	MISSION_TRANSITION,
	EXIT,
	NEW_GAME,
	DEVELOPMENT_LAUNCH,
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
@export var development_launch_labels: PackedStringArray = PackedStringArray()
@export var development_launch_resource_paths: PackedStringArray = PackedStringArray()

@onready var input_boundary: ApplicationInputBoundary = $InputBoundary
@onready var save_coordinator: VarkSaveCoordinator = $SaveCoordinator
@onready var world_host: Node = $WorldHost
@onready var ui_root: CanvasLayer = $UIRoot
@onready var main_menu: Control = $UIRoot/MainMenu
@onready var menu_actions: VBoxContainer = $UIRoot/MainMenu/Center/Panel/Content/MenuActions
@onready var new_game_button: Button = $UIRoot/MainMenu/Center/Panel/Content/MenuActions/NewGameButton
@onready var development_launch_button: Button = $UIRoot/MainMenu/Center/Panel/Content/MenuActions/DevelopmentLaunchButton
@onready var settings_button: Button = $UIRoot/MainMenu/Center/Panel/Content/MenuActions/SettingsButton
@onready var quit_button: Button = $UIRoot/MainMenu/Center/Panel/Content/MenuActions/QuitButton
@onready var development_launch_panel: VBoxContainer = $UIRoot/MainMenu/Center/Panel/Content/DevelopmentLaunchPanel
@onready var development_target_selector: OptionButton = $UIRoot/MainMenu/Center/Panel/Content/DevelopmentLaunchPanel/TargetSelector
@onready var development_launch_start_button: Button = $UIRoot/MainMenu/Center/Panel/Content/DevelopmentLaunchPanel/LaunchButton
@onready var development_launch_back_button: Button = $UIRoot/MainMenu/Center/Panel/Content/DevelopmentLaunchPanel/BackButton
@onready var settings_panel: VBoxContainer = $UIRoot/MainMenu/Center/Panel/Content/SettingsPanel
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
var _pending_application_hotkey_operation: StringName = APPLICATION_HOTKEY_NONE
var _pending_application_hotkey_session_id: int = 0


func _ready() -> void:
	current_ui = ui_root
	save_coordinator.bind_application(self)
	input_boundary.application_input_received.connect(
		_on_application_input_received
	)
	_wire_menu_shell()
	_refresh_development_launch_targets()
	_show_main_menu()


func _on_application_input_received(event: InputEvent) -> void:
	var command: StringName = _classify_application_hotkey(event)
	if command == APPLICATION_HOTKEY_NONE:
		return
	if (
		current_session == null
		or control_mode != ControlMode.GAMEPLAY
		or get_current_session_state() != WORLD_SESSION_SCRIPT.State.PLAYING
	):
		return

	match command:
		APPLICATION_HOTKEY_QUICKSAVE:
			request_quicksave()
		APPLICATION_HOTKEY_QUICKLOAD, APPLICATION_HOTKEY_RESTART:
			if _pending_application_hotkey_operation != APPLICATION_HOTKEY_NONE:
				return
			_pending_application_hotkey_operation = command
			_pending_application_hotkey_session_id = get_current_session_id()
			call_deferred("_execute_deferred_application_hotkey")


func _execute_deferred_application_hotkey() -> void:
	var command: StringName = _pending_application_hotkey_operation
	var source_session_id: int = _pending_application_hotkey_session_id
	_pending_application_hotkey_operation = APPLICATION_HOTKEY_NONE
	_pending_application_hotkey_session_id = 0
	if (
		command == APPLICATION_HOTKEY_NONE
		or not is_current_session(source_session_id)
		or control_mode != ControlMode.GAMEPLAY
		or get_current_session_state() != WORLD_SESSION_SCRIPT.State.PLAYING
	):
		return
	match command:
		APPLICATION_HOTKEY_QUICKLOAD:
			quickload_latest()
		APPLICATION_HOTKEY_RESTART:
			restart_current_world()


func _classify_application_hotkey(event: InputEvent) -> StringName:
	var key_event := event as InputEventKey
	if (
		key_event == null
		or not key_event.pressed
		or key_event.echo
	):
		return APPLICATION_HOTKEY_NONE
	match key_event.keycode:
		KEY_F5:
			return APPLICATION_HOTKEY_QUICKSAVE
		KEY_F9:
			return APPLICATION_HOTKEY_QUICKLOAD
		KEY_F10:
			return APPLICATION_HOTKEY_RESTART
	return APPLICATION_HOTKEY_NONE


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


func request_quicksave() -> int:
	if has_active_top_level_operation():
		return 0
	return save_coordinator.request_save()


func get_latest_quicksave_snapshot() -> Dictionary:
	return save_coordinator.get_latest_committed_snapshot()


func get_last_save_error() -> String:
	return save_coordinator.get_last_error()


func quickload_latest() -> bool:
	var snapshot: Dictionary = get_latest_quicksave_snapshot()
	if snapshot.is_empty():
		return false
	return restore_snapshot(snapshot)


func restore_snapshot(snapshot: Dictionary) -> bool:
	if not save_coordinator.validate_snapshot(snapshot):
		return false
	if not try_begin_top_level_operation(TopLevelOperation.LOAD):
		return false

	var succeeded: bool = _restore_world_from_snapshot(snapshot)
	var finished: bool = finish_top_level_operation(TopLevelOperation.LOAD)
	assert(finished, "VarkApplication lost ownership of the load operation.")
	return succeeded


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


func launch_development_target(target_index: int) -> bool:
	if current_session != null or control_mode != ControlMode.MENU:
		return false
	if (
		target_index < 0
		or target_index >= development_launch_labels.size()
		or target_index >= development_launch_resource_paths.size()
	):
		return false

	var resource_path: String = development_launch_resource_paths[target_index].strip_edges()
	if resource_path.is_empty():
		return false
	if not try_begin_top_level_operation(TopLevelOperation.DEVELOPMENT_LAUNCH):
		return false

	var target_resource: Resource = ResourceLoader.load(resource_path)
	var succeeded: bool = false
	if _is_mission_definition(target_resource):
		var load_errors: PackedStringArray = target_resource.call("get_load_errors")
		if load_errors.is_empty():
			var mission_world: PackedScene = target_resource.get("world_scene") as PackedScene
			succeeded = _replace_world(mission_world, target_resource)
		else:
			for load_error: String in load_errors:
				push_error(
					"Development mission '%s' is invalid: %s"
					% [resource_path, load_error]
				)
	elif target_resource is PackedScene:
		succeeded = _replace_world(target_resource as PackedScene)
	else:
		push_error(
			"Development launch target '%s' is not a MissionDefinition or PackedScene: %s"
			% [development_launch_labels[target_index], resource_path]
		)

	if succeeded:
		_hide_main_menu()
	else:
		_show_main_menu()

	var finished: bool = finish_top_level_operation(
		TopLevelOperation.DEVELOPMENT_LAUNCH
	)
	assert(finished, "VarkApplication lost ownership of the development-launch operation.")
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
	var mission_definition: Resource = null
	if current_session != null:
		scene = current_session.get("world_scene") as PackedScene
		mission_definition = current_session.get("mission_definition") as Resource

	var succeeded: bool = _replace_world(scene, mission_definition)
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


func _replace_world(
	scene: PackedScene,
	mission_definition: Resource = null
) -> bool:
	if scene == null:
		return false

	_teardown_current_session()
	return _install_world(scene, mission_definition)


func _restore_world_from_snapshot(snapshot: Dictionary) -> bool:
	var session_snapshot: Dictionary = snapshot.get("session", {})
	var view_pose: Dictionary = snapshot.get("player_view_pose", {})
	var world_scene_path: String = str(
		session_snapshot.get("world_scene_path", "")
	)
	var definition_path: String = str(
		session_snapshot.get("mission_definition_path", "")
	)

	if world_scene_path.is_empty() or not ResourceLoader.exists(world_scene_path):
		return false
	var world_resource: Resource = ResourceLoader.load(world_scene_path)
	if not (world_resource is PackedScene):
		return false
	var scene := world_resource as PackedScene

	var definition: Resource = null
	if not definition_path.is_empty():
		if not ResourceLoader.exists(definition_path):
			return false
		definition = ResourceLoader.load(definition_path)
		if not _is_mission_definition(definition):
			return false
		var definition_errors: PackedStringArray = definition.call(
			"get_load_errors"
		)
		if not definition_errors.is_empty():
			return false
		var definition_world: PackedScene = definition.get(
			"world_scene"
		) as PackedScene
		if (
			definition_world == null
			or definition_world.resource_path != world_scene_path
		):
			return false

	_teardown_current_session()
	var candidate: Node = _create_ready_session(scene, definition)
	if candidate == null:
		_show_main_menu()
		return false
	if not bool(candidate.call(
		"begin_restore_from_envelope",
		session_snapshot
	)):
		_discard_session_candidate(candidate)
		_show_main_menu()
		return false
	if not bool(candidate.call(
		"apply_restore_world_state",
		session_snapshot.get("world_state", {})
	)):
		_discard_session_candidate(candidate)
		_show_main_menu()
		return false

	var restored_player := candidate.get("player") as Node
	if (
		restored_player == null
		or not restored_player.has_method("apply_input_view_pose")
		or not bool(restored_player.call("apply_input_view_pose", view_pose))
	):
		_discard_session_candidate(candidate)
		_show_main_menu()
		return false
	if not bool(candidate.call("complete_restore")):
		_discard_session_candidate(candidate)
		_show_main_menu()
		return false

	current_session = candidate
	_sync_current_references()
	_apply_look_sensitivity_to_current_player()
	input_boundary.bind_player(current_player)
	if not bool(current_session.call("begin_play")):
		_teardown_current_session()
		_show_main_menu()
		return false

	control_mode = ControlMode.GAMEPLAY
	_set_world_input_domains(true)
	_hide_main_menu()
	return true


func _install_world(
	scene: PackedScene,
	mission_definition: Resource = null
) -> bool:
	if scene == null or current_session != null:
		return false

	var session: Node = _create_ready_session(scene, mission_definition)
	if session == null:
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


func _create_ready_session(
	scene: PackedScene,
	mission_definition: Resource = null
) -> Node:
	if scene == null:
		return null

	_last_session_id += 1
	var session: Node = WORLD_SESSION_SCRIPT.new()
	session.name = "WorldSession"
	world_host.add_child(session)
	if not bool(session.call(
		"build",
		_last_session_id,
		scene,
		mission_definition
	)):
		world_host.remove_child(session)
		session.free()
		return null
	return session


func _discard_session_candidate(session: Node) -> void:
	if session == null or not is_instance_valid(session):
		return
	session.call("teardown")
	if session.get_parent() == world_host:
		world_host.remove_child(session)
	session.free()


func _teardown_current_session() -> void:
	_set_world_input_domains(false)
	input_boundary.bind_player(null)

	if current_session != null and save_coordinator != null:
		save_coordinator.cancel_pending_for_session(
			int(current_session.get("session_id"))
		)

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


func _is_mission_definition(resource: Resource) -> bool:
	return resource != null and resource.get_script() == MISSION_DEFINITION_SCRIPT


func _set_world_input_domains(enabled: bool) -> void:
	input_boundary.set_gameplay_enabled(enabled)
	input_boundary.set_look_enabled(enabled)


func _wire_menu_shell() -> void:
	new_game_button.pressed.connect(_on_new_game_pressed)
	development_launch_button.pressed.connect(_on_development_launch_pressed)
	development_launch_start_button.pressed.connect(
		_on_development_launch_start_pressed
	)
	development_launch_back_button.pressed.connect(
		_on_development_launch_back_pressed
	)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	settings_back_button.pressed.connect(_on_settings_back_pressed)
	look_sensitivity_slider.value_changed.connect(_on_look_sensitivity_changed)
	quit_requested.connect(_quit_application)
	_sync_look_sensitivity_ui()


func _refresh_development_launch_targets() -> void:
	assert(
		development_launch_labels.size() == development_launch_resource_paths.size(),
		"Development launch labels and resource paths must have matching sizes."
	)

	development_target_selector.clear()
	for target_index: int in range(development_launch_labels.size()):
		var label: String = development_launch_labels[target_index].strip_edges()
		var resource_path: String = development_launch_resource_paths[target_index].strip_edges()
		if label.is_empty() or resource_path.is_empty():
			push_error(
				"Development launch target %d requires a non-empty label and resource path."
				% target_index
			)
			continue

		development_target_selector.add_item(label)
		var selector_index: int = development_target_selector.get_item_count() - 1
		development_target_selector.set_item_metadata(selector_index, target_index)

	var has_targets: bool = development_target_selector.get_item_count() > 0
	development_launch_button.disabled = not has_targets
	development_launch_start_button.disabled = not has_targets
	if has_targets:
		development_target_selector.select(0)


func _show_main_menu() -> void:
	control_mode = ControlMode.MENU
	_set_world_input_domains(false)
	main_menu.visible = true
	menu_actions.visible = true
	development_launch_panel.visible = false
	settings_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _hide_main_menu() -> void:
	main_menu.visible = false
	menu_actions.visible = true
	development_launch_panel.visible = false
	settings_panel.visible = false


func _show_development_launch() -> void:
	_refresh_development_launch_targets()
	menu_actions.visible = false
	development_launch_panel.visible = true
	settings_panel.visible = false


func _show_settings() -> void:
	menu_actions.visible = false
	development_launch_panel.visible = false
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


func _on_development_launch_pressed() -> void:
	_show_development_launch()


func _on_development_launch_start_pressed() -> void:
	var selector_index: int = development_target_selector.selected
	if selector_index < 0:
		return
	var target_index: int = int(
		development_target_selector.get_item_metadata(selector_index)
	)
	launch_development_target(target_index)


func _on_development_launch_back_pressed() -> void:
	menu_actions.visible = true
	development_launch_panel.visible = false


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
