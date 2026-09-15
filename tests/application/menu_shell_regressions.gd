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
	var settings_panel: VBoxContainer = application.get_node(
		"UIRoot/MainMenu/Center/Panel/Content/SettingsPanel"
	)
	var new_game_button: Button = application.get_node(
		"UIRoot/MainMenu/Center/Panel/Content/MenuActions/NewGameButton"
	)
	var settings_button: Button = application.get_node(
		"UIRoot/MainMenu/Center/Panel/Content/MenuActions/SettingsButton"
	)
	var quit_button: Button = application.get_node(
		"UIRoot/MainMenu/Center/Panel/Content/MenuActions/QuitButton"
	)
	var sensitivity_slider: HSlider = application.get_node(
		"UIRoot/MainMenu/Center/Panel/Content/SettingsPanel/LookSensitivity"
	)
	var sensitivity_value: Label = application.get_node(
		"UIRoot/MainMenu/Center/Panel/Content/SettingsPanel/LookSensitivityValue"
	)
	var back_button: Button = application.get_node(
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
		and not settings_panel.visible
		and not bool(boundary.get("gameplay_enabled"))
		and not bool(boundary.get("look_enabled")),
		"F5 application shell starts in menu ownership without constructing a gameplay world"
	)

	assert_true.call(
		new_game_button.get_signal_connection_list(&"pressed").size() == 1
		and settings_button.get_signal_connection_list(&"pressed").size() == 1
		and quit_button.get_signal_connection_list(&"pressed").size() == 1
		and application.get_signal_connection_list(&"quit_requested").size() == 1,
		"Main-menu New Game, Settings, and Quit controls are wired to application ownership"
	)

	settings_button.pressed.emit()
	await tree.process_frame
	assert_true.call(
		main_menu.visible
		and not menu_actions.visible
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

	back_button.pressed.emit()
	await tree.process_frame
	assert_true.call(
		menu_actions.visible and not settings_panel.visible,
		"Settings Back returns to the main menu actions"
	)

	new_game_button.pressed.emit()
	await tree.process_frame
	var first_player: Node = application.get("current_player") as Node
	var first_session_id: int = int(application.call("get_current_session_id"))
	assert_true.call(
		application.get("current_session") != null
		and int(application.call("get_current_session_state")) == WorldSession.State.PLAYING
		and int(application.call("get_control_mode")) == ApplicationRoot.ControlMode.GAMEPLAY
		and first_player != null
		and first_session_id > 0
		and not main_menu.visible
		and bool(boundary.get("gameplay_enabled"))
		and bool(boundary.get("look_enabled")),
		"New Game / Development Start installs the current world through the application lifecycle"
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
