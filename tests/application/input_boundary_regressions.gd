extends RefCounted


const InputBoundary = preload(
	"res://application/application_input_boundary.gd"
)


func run(
	tree: SceneTree,
	application: Node,
	assert_true: Callable
) -> void:
	var boundary: Node = application.get_node("InputBoundary")
	var player: Node = application.get("current_player") as Node

	assert_true.call(
		boundary.get("current_player") == player
		and bool(boundary.get("gameplay_enabled"))
		and bool(boundary.get("look_enabled"))
		and player.get("gameplay_input_boundary") == boundary,
		"Application owns the production gameplay/look input boundary"
	)

	_test_application_hotkey_mapping(application, assert_true)
	await _test_quicksave_quickload_hotkey_route(
		tree,
		application,
		boundary,
		assert_true
	)
	player = application.get("current_player") as Node

	# Keep the live application player neutral while the standalone boundary
	# probe manipulates global Input actions to verify frame semantics.
	assert_true.call(
		bool(application.call("set_gameplay_input_enabled", false)),
		"Application can suppress gameplay intent independently of look input"
	)
	await _test_gameplay_frame_lifetime(tree, assert_true)
	assert_true.call(
		bool(application.call("set_gameplay_input_enabled", true)),
		"Application can restore gameplay intent for the active PLAYING session"
	)

	await _test_domain_loss_cancels_gesture(application, player, assert_true)
	_test_event_cadence_look_and_view_pose(application, boundary, assert_true)


func _test_application_hotkey_mapping(
	application: Node,
	assert_true: Callable
) -> void:
	var quicksave := InputEventKey.new()
	quicksave.pressed = true
	quicksave.keycode = KEY_F5
	var quickload := InputEventKey.new()
	quickload.pressed = true
	quickload.keycode = KEY_F9
	var restart := InputEventKey.new()
	restart.pressed = true
	restart.keycode = KEY_F10
	var released := InputEventKey.new()
	released.pressed = false
	released.keycode = KEY_F5
	var echoed := InputEventKey.new()
	echoed.pressed = true
	echoed.echo = true
	echoed.keycode = KEY_F5

	assert_true.call(
		application.call("_classify_application_hotkey", quicksave) == &"quicksave"
		and application.call("_classify_application_hotkey", quickload) == &"quickload"
		and application.call("_classify_application_hotkey", restart) == &"restart"
		and application.call("_classify_application_hotkey", released) == &""
		and application.call("_classify_application_hotkey", echoed) == &"",
		"Application maps one fresh F5/F9/F10 edge to quicksave/quickload/restart without held-key repeat"
	)


func _test_quicksave_quickload_hotkey_route(
	tree: SceneTree,
	application: Node,
	boundary: Node,
	assert_true: Callable
) -> void:
	const TEST_SAVE_DIRECTORY: String = "user://vark_tests/application_hotkeys"
	_cleanup_hotkey_test_storage(TEST_SAVE_DIRECTORY)
	var save_coordinator := application.get_node("SaveCoordinator") as Node
	save_coordinator.set("durable_save_directory", TEST_SAVE_DIRECTORY)
	save_coordinator.call("get_latest_committed_generation")
	var before_generation: int = int(save_coordinator.get("_next_generation"))
	var save_event := InputEventKey.new()
	save_event.pressed = true
	save_event.keycode = KEY_F5
	boundary.call("route_input_event", save_event)
	var generation: int = before_generation
	var snapshot: Dictionary = await _wait_for_save_commit(
		tree,
		save_coordinator,
		generation,
		120
	)
	assert_true.call(
		not snapshot.is_empty()
		and int(save_coordinator.get("_next_generation")) == generation + 1,
		"F5 routes through the application input boundary into a committed quicksave"
	)

	var old_session_id: int = int(application.call("get_current_session_id"))
	var load_event := InputEventKey.new()
	load_event.pressed = true
	load_event.keycode = KEY_F9
	boundary.call("route_input_event", load_event)
	assert_true.call(
		int(application.call("get_current_session_id")) == old_session_id
		and application.get("_pending_application_hotkey_operation") == &"quickload",
		"F9 queues world replacement until after the input-dispatch stack unwinds"
	)

	var replaced: bool = false
	for _index: int in 120:
		await tree.process_frame
		if int(application.call("get_current_session_id")) != old_session_id:
			replaced = true
			break
	var restored_player := application.get("current_player") as Node
	var restored_world := application.get("current_world") as Node
	assert_true.call(
		replaced
		and restored_player != null
		and restored_world != null
		and restored_world.can_process()
		and int(application.call("get_current_session_state")) == 4
		and bool(boundary.get("gameplay_enabled"))
		and bool(boundary.get("look_enabled"))
		and boundary.get("current_player") == restored_player,
		"Deferred F9 quickload replaces the session and returns to live gameplay/input instead of freezing the input callback"
	)

	save_coordinator.set(
		"durable_save_directory",
		VarkSaveCoordinator.DEFAULT_DURABLE_SAVE_DIRECTORY
	)
	_cleanup_hotkey_test_storage(TEST_SAVE_DIRECTORY)


func _wait_for_save_commit(
	tree: SceneTree,
	save_coordinator: Node,
	generation: int,
	max_frames: int
) -> Dictionary:
	for _index: int in max_frames:
		var status: Dictionary = save_coordinator.call(
			"get_request_status",
			generation
		)
		if status.get("status", &"") == &"committed":
			return save_coordinator.call("get_request_snapshot", generation)
		if status.get("status", &"") in [
			&"failed",
			&"cancelled",
			&"superseded",
		]:
			return {}
		await tree.physics_frame
		await tree.process_frame
	return {}


func _cleanup_hotkey_test_storage(directory: String) -> void:
	var final_path: String = directory + "/quicksave.varksave"
	for path: String in [
		final_path,
		final_path + ".new",
		final_path + ".bak",
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var absolute_dir: String = ProjectSettings.globalize_path(directory)
	if DirAccess.dir_exists_absolute(absolute_dir):
		DirAccess.remove_absolute(absolute_dir)


func _test_gameplay_frame_lifetime(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	_release_actions()
	var probe: Node = InputBoundary.new()
	probe.call("set_gameplay_enabled", true)

	Input.action_press("move_forward")
	Input.action_press("sprint")
	Input.action_press("jump")
	Input.action_press("interact")
	Input.action_press("attack")
	var first: PlayerCommand = await _sample_on_next_physics_frame(tree, probe)
	var first_interact: bool = bool(probe.call("sample_interaction_pressed"))
	var first_attack: bool = bool(probe.call("sample_attack_pressed"))
	assert_true.call(
		first.movement_vector.y < -0.9
		and first.sprint_held
		and first.jump_pressed
		and first.jump_held,
		"Gameplay intent frame samples held state and a fresh press together"
	)
	assert_true.call(
		first_interact and first_attack,
		"Interaction and crude hostile attack use separate fresh one-frame gameplay edges"
	)

	var same_frame: PlayerCommand = probe.call("sample_locomotion_command") as PlayerCommand
	var same_frame_interact: bool = bool(probe.call("sample_interaction_pressed"))
	var same_frame_attack: bool = bool(probe.call("sample_attack_pressed"))
	assert_true.call(
		same_frame == first
		and same_frame.jump_pressed
		and same_frame_interact
		and same_frame_attack,
		"Gameplay input edges are sampled only once for one physics frame"
	)

	var held_next_frame: PlayerCommand = await _sample_on_next_physics_frame(tree, probe)
	var held_interact: bool = bool(probe.call("sample_interaction_pressed"))
	var held_attack: bool = bool(probe.call("sample_attack_pressed"))
	assert_true.call(
		held_next_frame.movement_vector.y < -0.9
		and held_next_frame.sprint_held
		and held_next_frame.jump_held
		and not held_next_frame.jump_pressed
		and not held_interact
		and not held_attack,
		"Held gameplay state persists while pressed edges expire after one gameplay frame"
	)

	probe.call("set_gameplay_enabled", false)
	var disabled: PlayerCommand = probe.call("sample_locomotion_command") as PlayerCommand
	var disabled_interact: bool = bool(probe.call("sample_interaction_pressed"))
	var disabled_attack: bool = bool(probe.call("sample_attack_pressed"))
	assert_true.call(
		disabled.movement_vector == Vector2.ZERO
		and not disabled.sprint_held
		and not disabled.jump_pressed
		and not disabled.jump_held
		and not disabled_interact
		and not disabled_attack,
		"Disabled gameplay domain produces neutral locomotion and interaction intent"
	)

	probe.call("set_gameplay_enabled", true)
	var resumed_while_held: PlayerCommand = probe.call("sample_locomotion_command") as PlayerCommand
	var resumed_interact: bool = bool(probe.call("sample_interaction_pressed"))
	var resumed_attack: bool = bool(probe.call("sample_attack_pressed"))
	assert_true.call(
		resumed_while_held.movement_vector.y < -0.9
		and resumed_while_held.sprint_held
		and not resumed_while_held.jump_pressed
		and not resumed_while_held.jump_held
		and not resumed_interact
		and not resumed_attack,
		"Domain resume restores continuous intent but does not replay held edge-dependent actions"
	)

	Input.action_release("jump")
	Input.action_release("interact")
	Input.action_release("attack")
	var released: PlayerCommand = await _sample_on_next_physics_frame(tree, probe)
	var released_interact: bool = bool(probe.call("sample_interaction_pressed"))
	var released_attack: bool = bool(probe.call("sample_attack_pressed"))
	assert_true.call(
		not released.jump_pressed
		and not released.jump_held
		and not released_interact
		and not released_attack,
		"Releasing after domain loss clears blocked edge-dependent actions"
	)

	Input.action_press("jump")
	Input.action_press("interact")
	Input.action_press("attack")
	var fresh_press: PlayerCommand = await _sample_on_next_physics_frame(tree, probe)
	var fresh_interact: bool = bool(probe.call("sample_interaction_pressed"))
	var fresh_attack: bool = bool(probe.call("sample_attack_pressed"))
	assert_true.call(
		fresh_press.jump_pressed
		and fresh_press.jump_held
		and fresh_interact
		and fresh_attack,
		"Fresh post-resume presses create new locomotion and interaction edges"
	)

	var edge_expired: PlayerCommand = await _sample_on_next_physics_frame(tree, probe)
	var interaction_edge_expired: bool = bool(probe.call("sample_interaction_pressed"))
	var attack_edge_expired: bool = bool(probe.call("sample_attack_pressed"))
	assert_true.call(
		not edge_expired.jump_pressed
		and edge_expired.jump_held
		and not interaction_edge_expired
		and not attack_edge_expired,
		"Fresh gameplay press edges expire after one physics frame"
	)

	_release_actions()
	probe.free()


func _test_domain_loss_cancels_gesture(
	application: Node,
	player: Node,
	assert_true: Callable
) -> void:
	var locomotion_controller: RefCounted = player.get("locomotion_controller") as RefCounted
	locomotion_controller.set("air_mantle_intent_active", true)

	var disabled: bool = bool(application.call("set_gameplay_input_enabled", false))
	assert_true.call(
		disabled
		and not bool(locomotion_controller.get("air_mantle_intent_active")),
		"Application domain loss cancels incomplete edge-dependent locomotion gesture state"
	)

	assert_true.call(
		bool(application.call("set_gameplay_input_enabled", true)),
		"Application can restore gameplay input only for the active PLAYING session"
	)


func _test_event_cadence_look_and_view_pose(
	application: Node,
	boundary: Node,
	assert_true: Callable
) -> void:
	var before: Dictionary = application.call("get_current_view_pose")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(9.0, -4.0)
	boundary.call("route_input_event", motion)
	var after: Dictionary = application.call("get_current_view_pose")

	assert_true.call(
		absf(float(after.get("body_yaw", 0.0)) - float(before.get("body_yaw", 0.0))) > 0.0001
		and absf(float(after.get("head_pitch", 0.0)) - float(before.get("head_pitch", 0.0))) > 0.0001,
		"Look input updates the input-owned view pose immediately without waiting for a physics tick"
	)

	var detached: Dictionary = after
	detached["body_yaw"] = 123.0
	var resampled: Dictionary = application.call("get_current_view_pose")
	assert_true.call(
		absf(float(resampled.get("body_yaw", 0.0)) - 123.0) > 1.0,
		"Application view-pose sampling returns detached value-owned data"
	)

	var inverse_motion := InputEventMouseMotion.new()
	inverse_motion.relative = -motion.relative
	boundary.call("route_input_event", inverse_motion)

	assert_true.call(
		bool(application.call("set_look_input_enabled", false)),
		"Application can disable the look domain independently of gameplay"
	)
	var disabled_before: Dictionary = application.call("get_current_view_pose")
	boundary.call("route_input_event", motion)
	var disabled_after: Dictionary = application.call("get_current_view_pose")
	assert_true.call(
		is_equal_approx(
			float(disabled_before.get("body_yaw", 0.0)),
			float(disabled_after.get("body_yaw", 0.0))
		)
		and is_equal_approx(
			float(disabled_before.get("head_pitch", 0.0)),
			float(disabled_after.get("head_pitch", 0.0))
		),
		"Disabled look domain does not mutate the current view pose"
	)
	assert_true.call(
		bool(application.call("set_look_input_enabled", true)),
		"Application can restore event-cadence look for the active PLAYING session"
	)


func _sample_on_next_physics_frame(
	tree: SceneTree,
	boundary: Node
) -> PlayerCommand:
	await tree.physics_frame
	return boundary.call("sample_locomotion_command") as PlayerCommand


func _release_actions() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_forward")
	Input.action_release("move_backward")
	Input.action_release("jump")
	Input.action_release("crouch")
	Input.action_release("sprint")
	Input.action_release("interact")
	Input.action_release("attack")
