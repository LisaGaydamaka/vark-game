extends RefCounted


const ApplicationRoot = preload("res://application/application_root.gd")
const WorldSession = preload("res://application/world_session.gd")
const SessionWorkProbe = preload("res://tests/application/session_work_probe.gd")


func run(
	tree: SceneTree,
	application: Node,
	assert_true: Callable
) -> void:
	await _test_application_control_and_gameplay_time(
		tree,
		application,
		assert_true
	)


func _test_application_control_and_gameplay_time(
	tree: SceneTree,
	application: Node,
	assert_true: Callable
) -> void:
	_release_actions()

	var boundary: Node = application.get_node("InputBoundary")
	var session: Node = application.get("current_session") as Node
	var world: Node = application.get("current_world") as Node
	var player: CharacterBody3D = application.get("current_player") as CharacterBody3D
	var ui_root: CanvasLayer = application.get("current_ui") as CanvasLayer

	assert_true.call(
		int(application.call("get_control_mode")) == ApplicationRoot.ControlMode.GAMEPLAY
		and int(application.call("get_current_session_state")) == WorldSession.State.PLAYING
		and bool(boundary.get("gameplay_enabled"))
		and bool(boundary.get("look_enabled")),
		"Application starts with gameplay owning the live world input domains"
	)

	var time_before_running: float = float(application.call("get_gameplay_time_seconds"))
	await _advance_completed_physics_frames(tree, 2)
	var running_time: float = float(application.call("get_gameplay_time_seconds"))
	assert_true.call(
		running_time > time_before_running,
		"World-session gameplay time advances only while ordinary gameplay simulates"
	)

	var session_timer_hits: Array[String] = []
	var ui_timer_hits: Array[String] = []
	var application_input_hits: Array[String] = []
	var session_probe: Node = SessionWorkProbe.new()
	var ui_probe: Node = SessionWorkProbe.new()
	session.add_child(session_probe)
	ui_root.add_child(ui_probe)
	session_probe.call("arm_timer", func(): session_timer_hits.append("world"))
	ui_probe.call("arm_timer", func(): ui_timer_hits.append("ui"))

	var application_input_callback: Callable = func(_event: InputEvent):
		application_input_hits.append("input")
	boundary.connect(&"application_input_received", application_input_callback)

	var locomotion_controller: RefCounted = player.get("locomotion_controller") as RefCounted
	locomotion_controller.set("air_mantle_intent_active", true)
	Input.action_press("jump")
	var position_before_pause: Vector3 = player.global_position

	var exclusive_modes: Array[int] = [
		ApplicationRoot.ControlMode.PAUSE_MENU,
		ApplicationRoot.ControlMode.INVENTORY,
		ApplicationRoot.ControlMode.OBJECTIVES,
		ApplicationRoot.ControlMode.MAP,
		ApplicationRoot.ControlMode.CUTSCENE,
		ApplicationRoot.ControlMode.MENU,
	]
	for mode: int in exclusive_modes:
		var accepted: bool = bool(application.call("set_control_mode", mode))
		assert_true.call(
			accepted
			and int(application.call("get_control_mode")) == mode
			and int(application.call("get_current_session_state")) == WorldSession.State.PAUSED
			and bool(application.call("is_world_paused"))
			and not world.can_process()
			and not bool(boundary.get("gameplay_enabled"))
			and not bool(boundary.get("look_enabled")),
			"Exclusive application control mode %d freezes world gameplay and owns input" % mode
		)

	assert_true.call(
		not bool(locomotion_controller.get("air_mantle_intent_active")),
		"Application control takeover cancels incomplete edge-dependent gameplay gestures"
	)
	assert_true.call(
		not bool(application.call("set_gameplay_input_enabled", true))
		and not bool(application.call("set_look_input_enabled", true)),
		"Paused application ownership rejects attempts to re-enable world input domains"
	)

	var application_event := InputEventKey.new()
	application_event.pressed = true
	application_event.keycode = KEY_I
	boundary.call("route_input_event", application_event)
	assert_true.call(
		application_input_hits == ["input"],
		"Application/UI input remains available while world gameplay is paused"
	)

	var paused_time: float = float(application.call("get_gameplay_time_seconds"))
	await _advance_completed_physics_frames(tree, 3)
	var time_after_pause_frames: float = float(application.call("get_gameplay_time_seconds"))
	assert_true.call(
		is_equal_approx(time_after_pause_frames, paused_time)
		and player.global_position.distance_to(position_before_pause) <= 0.00001
		and session_timer_hits.is_empty(),
		"Pause freezes world processing, session-owned work, and gameplay time coherently"
	)
	assert_true.call(
		ui_timer_hits == ["ui"],
		"Persistent application/UI work continues while the mission world is paused"
	)

	var resumed: bool = bool(application.call(
		"set_control_mode",
		ApplicationRoot.ControlMode.GAMEPLAY
	))
	assert_true.call(
		resumed
		and int(application.call("get_current_session_state")) == WorldSession.State.PLAYING
		and not bool(application.call("is_world_paused"))
		and world.can_process()
		and bool(boundary.get("gameplay_enabled"))
		and bool(boundary.get("look_enabled")),
		"Returning gameplay ownership resumes world processing and gameplay/look domains together"
	)

	await _advance_completed_physics_frames(tree, 2)
	var resumed_command: PlayerCommand = boundary.call("sample_locomotion_command") as PlayerCommand
	var resumed_time: float = float(application.call("get_gameplay_time_seconds"))
	assert_true.call(
		not resumed_command.jump_pressed
		and not resumed_command.jump_held,
		"A jump held across pause does not replay or remain armed when gameplay resumes"
	)
	assert_true.call(
		resumed_time > paused_time
		and session_timer_hits == ["world"],
		"Gameplay time and paused session-owned work continue normally after resume"
	)

	Input.action_release("jump")
	await _advance_completed_physics_frames(tree, 1)
	_release_actions()

	if boundary.is_connected(&"application_input_received", application_input_callback):
		boundary.disconnect(&"application_input_received", application_input_callback)
	session_probe.queue_free()
	ui_probe.queue_free()
	await tree.process_frame


func _advance_completed_physics_frames(
	tree: SceneTree,
	frame_count: int
) -> void:
	for _frame: int in range(frame_count):
		await tree.physics_frame
		await tree.process_frame


func _release_actions() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_forward")
	Input.action_release("move_backward")
	Input.action_release("jump")
	Input.action_release("crouch")
	Input.action_release("sprint")
