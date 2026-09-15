extends RefCounted


const ApplicationRoot = preload("res://application/application_root.gd")
const WorldSession = preload("res://application/world_session.gd")


func run(
	tree: SceneTree,
	application: Node,
	assert_true: Callable
) -> void:
	var world_host: Node = application.get_node("WorldHost")
	var boundary: Node = application.get_node("InputBoundary")
	var main_menu: Control = application.get_node("UIRoot/MainMenu")
	var menu_actions: VBoxContainer = application.get_node(
		"UIRoot/MainMenu/Center/Panel/Content/MenuActions"
	)
	var new_game_button: Button = application.get_node(
		"UIRoot/MainMenu/Center/Panel/Content/MenuActions/NewGameButton"
	)
	var development_launch_button: Button = application.get_node(
		"UIRoot/MainMenu/Center/Panel/Content/MenuActions/DevelopmentLaunchButton"
	)
	var settings_button: Button = application.get_node(
		"UIRoot/MainMenu/Center/Panel/Content/MenuActions/SettingsButton"
	)
	var quit_button: Button = application.get_node(
		"UIRoot/MainMenu/Center/Panel/Content/MenuActions/QuitButton"
	)
	var development_launch_panel: VBoxContainer = application.get_node(
		"UIRoot/MainMenu/Center/Panel/Content/DevelopmentLaunchPanel"
	)
	var development_target_selector: OptionButton = application.get_node(
		"UIRoot/MainMenu/Center/Panel/Content/DevelopmentLaunchPanel/TargetSelector"
	)
	var development_launch_start_button: Button = application.get_node(
		"UIRoot/MainMenu/Center/Panel/Content/DevelopmentLaunchPanel/LaunchButton"
	)
	var development_launch_back_button: Button = application.get_node(
		"UIRoot/MainMenu/Center/Panel/Content/DevelopmentLaunchPanel/BackButton"
	)
	var settings_panel: VBoxContainer = application.get_node(
		"UIRoot/MainMenu/Center/Panel/Content/SettingsPanel"
	)
	var sensitivity_slider: HSlider = application.get_node(
		"UIRoot/MainMenu/Center/Panel/Content/SettingsPanel/LookSensitivity"
	)
	var sensitivity_value: Label = application.get_node(
		"UIRoot/MainMenu/Center/Panel/Content/SettingsPanel/LookSensitivityValue"
	)
	var settings_back_button: Button = application.get_node(
		"UIRoot/MainMenu/Center/Panel/Content/SettingsPanel/BackButton"
	)

	assert_true.call(
		application.get("current_session") == null
		and application.get("current_world") == null
		and application.get("current_player") == null
		and world_host.get_child_count() == 0
		and int(application.call("get_control_mode")) == ApplicationRoot.ControlMode.MENU
		and main_menu.visible
		and menu_actions.visible
		and not development_launch_panel.visible
		and not settings_panel.visible
		and not bool(boundary.get("gameplay_enabled"))
		and not bool(boundary.get("look_enabled")),
		"F5 application shell starts in menu ownership without constructing a gameplay world"
	)

	assert_true.call(
		new_game_button.get_signal_connection_list(&"pressed").size() == 1
		and development_launch_button.get_signal_connection_list(&"pressed").size() == 1
		and development_launch_start_button.get_signal_connection_list(&"pressed").size() == 1
		and development_launch_back_button.get_signal_connection_list(&"pressed").size() == 1
		and settings_button.get_signal_connection_list(&"pressed").size() == 1
		and quit_button.get_signal_connection_list(&"pressed").size() == 1
		and application.get_signal_connection_list(&"quit_requested").size() == 1,
		"Main-menu New Game, Development Launch, Settings, and Quit controls are wired to application ownership"
	)

	development_launch_button.pressed.emit()
	await tree.process_frame
	assert_true.call(
		main_menu.visible
		and not menu_actions.visible
		and development_launch_panel.visible
		and not settings_panel.visible
		and development_target_selector.get_item_count() == 3
		and development_target_selector.get_item_text(0) == "VarkTest"
		and development_target_selector.get_item_text(1) == "Playground"
		and development_target_selector.get_item_text(2) == "Alternate Fixture",
		"Development Launch exposes curated production and test targets inside persistent application UI"
	)

	assert_true.call(
		not bool(application.call("launch_development_target", 99))
		and application.get("current_session") == null,
		"Development Launch rejects an invalid target without creating a world session"
	)

	var began_blocking_operation: bool = bool(application.call(
		"try_begin_top_level_operation",
		ApplicationRoot.TopLevelOperation.LOAD
	))
	var blocked_launch: bool = bool(application.call("launch_development_target", 0))
	var finished_blocking_operation: bool = bool(application.call(
		"finish_top_level_operation",
		ApplicationRoot.TopLevelOperation.LOAD
	))
	assert_true.call(
		began_blocking_operation
		and not blocked_launch
		and finished_blocking_operation
		and application.get("current_session") == null,
		"Development Launch obeys the existing exclusive top-level operation guard"
	)

	development_target_selector.select(1)
	development_launch_start_button.pressed.emit()
	await tree.process_frame
	var playground_session: Node = application.get("current_session") as Node
	var playground_world: Node = application.get("current_world") as Node
	var playground_player: Node = application.get("current_player") as Node
	var playground_scene: PackedScene = null
	var playground_definition: Resource = null
	var playground_map: Node = null
	if playground_session != null:
		playground_scene = playground_session.get("world_scene") as PackedScene
		playground_definition = playground_session.get("mission_definition") as Resource
	if playground_world != null:
		playground_map = playground_world.get_node_or_null("FuncGodotMap")
	assert_true.call(
		playground_session != null
		and playground_world != null
		and playground_world.name == &"Playground"
		and playground_scene != null
		and playground_scene.resource_path == "res://missions/playground/world.tscn"
		and playground_player != null
		and playground_player.is_in_group(&"vark_player")
		and boundary.get("current_player") == playground_player
		and int(application.call("get_current_session_state")) == WorldSession.State.PLAYING
		and int(application.call("get_control_mode")) == ApplicationRoot.ControlMode.GAMEPLAY
		and not main_menu.visible
		and bool(boundary.get("gameplay_enabled"))
		and bool(boundary.get("look_enabled")),
		"Mission-package Playground launches through the normal world-session/input path"
	)
	assert_true.call(
		playground_definition != null
		and playground_definition.resource_path
		== "res://missions/playground/mission.tres"
		and playground_definition.get("mission_id") == &"playground"
		and playground_definition.get("world_scene") == playground_scene
		and str(playground_definition.get("map_source_path"))
		== "res://missions/playground/mission.map"
		and playground_definition.get("player_start_selector") == &"default"
		and int(playground_definition.get("mission_content_revision")) == 1
		and playground_world.get("mission_definition") == playground_definition,
		"Playground session receives one authored MissionDefinition with minimal mission metadata"
	)
	assert_true.call(
		playground_map != null
		and str(playground_map.get("local_map_file"))
		== str(playground_definition.get("map_source_path"))
		and playground_map.get_node_or_null("entity_0_worldspawn") != null,
		"MissionDefinition owns the package-local map source used to build Playground"
	)

	var playground_session_id: int = int(application.call("get_current_session_id"))
	var restarted_playground: bool = bool(application.call("restart_current_world"))
	var replacement_playground_session: Node = application.get("current_session") as Node
	var replacement_playground_world: Node = application.get("current_world") as Node
	var replacement_definition: Resource = null
	if replacement_playground_session != null:
		replacement_definition = replacement_playground_session.get("mission_definition") as Resource
	assert_true.call(
		restarted_playground
		and replacement_playground_session != null
		and replacement_playground_session != playground_session
		and int(application.call("get_current_session_id")) > playground_session_id
		and replacement_definition == playground_definition
		and replacement_playground_world != null
		and replacement_playground_world.get("mission_definition") == playground_definition,
		"Restart preserves authored MissionDefinition configuration while replacing session runtime state"
	)

	var exited_playground: bool = bool(application.call("exit_current_world"))
	await tree.process_frame
	assert_true.call(
		exited_playground
		and application.get("current_session") == null
		and application.get("current_world") == null
		and application.get("current_player") == null
		and main_menu.visible
		and menu_actions.visible
		and not development_launch_panel.visible,
		"Exiting the Playground returns to the same application-owned main menu"
	)

	development_launch_button.pressed.emit()
	await tree.process_frame
	development_target_selector.select(2)
	development_launch_start_button.pressed.emit()
	await tree.process_frame
	var development_session: Node = application.get("current_session") as Node
	var development_world: Node = application.get("current_world") as Node
	var development_scene: PackedScene = null
	if development_session != null:
		development_scene = development_session.get("world_scene") as PackedScene
	assert_true.call(
		development_session != null
		and development_world != null
		and development_world.name == &"DevelopmentAlternate"
		and development_scene != null
		and development_scene.resource_path
		== "res://tests/application/fixtures/development_alternate_world.tscn"
		and development_session.get("mission_definition") == null
		and int(application.call("get_current_session_state")) == WorldSession.State.PLAYING
		and int(application.call("get_control_mode")) == ApplicationRoot.ControlMode.GAMEPLAY,
		"Development Launch still starts exact raw-scene targets without inventing mission metadata"
	)

	var exited_development_target: bool = bool(application.call("exit_current_world"))
	await tree.process_frame
	assert_true.call(
		exited_development_target
		and application.get("current_session") == null
		and application.get("current_world") == null
		and application.get("current_player") == null
		and main_menu.visible
		and menu_actions.visible
		and not development_launch_panel.visible,
		"Exiting a development target returns to the same application-owned main menu"
	)

	development_launch_button.pressed.emit()
	await tree.process_frame
	development_launch_back_button.pressed.emit()
	await tree.process_frame
	assert_true.call(
		menu_actions.visible and not development_launch_panel.visible,
		"Development Launch Back returns to the main menu actions"
	)

	settings_button.pressed.emit()
	await tree.process_frame
	assert_true.call(
		main_menu.visible
		and not menu_actions.visible
		and not development_launch_panel.visible
		and settings_panel.visible,
		"Settings opens inside the persistent application menu shell"
	)

	const TEST_SENSITIVITY: float = 0.010
	sensitivity_slider.value = TEST_SENSITIVITY
	await tree.process_frame
	assert_true.call(
		is_equal_approx(
			float(application.call("get_look_sensitivity")),
			TEST_SENSITIVITY
		)
		and sensitivity_value.text == "0.010",
		"Look sensitivity is a real application setting rather than a placeholder control"
	)

	settings_back_button.pressed.emit()
	await tree.process_frame
	assert_true.call(
		menu_actions.visible and not settings_panel.visible,
		"Settings Back returns to the main menu actions"
	)

	new_game_button.pressed.emit()
	await tree.process_frame
	var first_player: Node = application.get("current_player") as Node
	var first_session_id: int = int(application.call("get_current_session_id"))
	var new_game_world: Node = application.get("current_world") as Node
	assert_true.call(
		application.get("current_session") != null
		and new_game_world != null
		and new_game_world.name == &"VarkTest"
		and int(application.call("get_current_session_state")) == WorldSession.State.PLAYING
		and int(application.call("get_control_mode")) == ApplicationRoot.ControlMode.GAMEPLAY
		and first_player != null
		and first_session_id > 0
		and not main_menu.visible
		and bool(boundary.get("gameplay_enabled"))
		and bool(boundary.get("look_enabled")),
		"New Game remains the default application start path after development launch is separated"
	)
	assert_true.call(
		is_equal_approx(float(first_player.get("mouse_sensitivity")), TEST_SENSITIVITY)
		and is_equal_approx(
			float((first_player.get("player_look") as RefCounted).get("mouse_sensitivity")),
			TEST_SENSITIVITY
		),
		"Configured look sensitivity is applied to the live player and event-cadence look owner"
	)

	var restarted: bool = bool(application.call("restart_current_world"))
	var replacement_player: Node = application.get("current_player") as Node
	assert_true.call(
		restarted
		and replacement_player != null
		and replacement_player != first_player
		and int(application.call("get_current_session_id")) > first_session_id
		and is_equal_approx(
			float(replacement_player.get("mouse_sensitivity")),
			TEST_SENSITIVITY
		)
		and is_equal_approx(
			float((replacement_player.get("player_look") as RefCounted).get("mouse_sensitivity")),
			TEST_SENSITIVITY
		),
		"Application look sensitivity survives world replacement without mutable world-state leakage"
	)
