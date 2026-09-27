extends RefCounted


const ApplicationScene = preload("res://application/Application.tscn")
const FLAT_PATH: String = "res://tests/movement/fixtures/sprint_jump.tscn"
const LEDGE_PATH: String = "res://tests/movement/fixtures/ledge_traversal.tscn"
const STEP_PATH: String = "res://tests/movement/fixtures/normal_step.tscn"
const POSITION_TOLERANCE: float = 0.001
const VELOCITY_TOLERANCE: float = 0.001
const VIEW_TOLERANCE: float = 0.001


func run(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	await _prove_direct_moving_restore(tree, assert_true)
	await _prove_direct_crouched_restore(tree, assert_true)
	await _prove_stance_transition_restore(tree, assert_true)
	await _prove_direct_airborne_restore(tree, assert_true)
	await _prove_reconstructed_traversal_restore(tree, assert_true, &"catching")
	await _prove_reconstructed_traversal_restore(tree, assert_true, &"hanging")
	await _prove_reconstructed_traversal_restore(tree, assert_true, &"cornering")
	await _prove_reconstructed_traversal_restore(tree, assert_true, &"mantling")
	await _prove_legacy_airborne_normalization_restore(tree, assert_true)
	await _prove_hotkey_hanging_restore_resumes(tree, assert_true)
	await _prove_hotkey_step_restore_resumes(tree, assert_true)


func _prove_direct_moving_restore(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	var application: Node = await _launch_application(tree, FLAT_PATH)
	var player := application.get("current_player") as CharacterBody3D

	Input.action_press("move_forward")
	await _advance_frames(tree, 12)
	var source_movement: Dictionary = player.call(
		"get_movement_semantic_state"
	)
	var snapshot: Dictionary = _capture_snapshot(application, 4301)
	var saved_player: Dictionary = snapshot.get(
		"session",
		{}
	).get("world_state", {}).get("player", {})
	var saved_transform: Transform3D = saved_player.get(
		"transform",
		Transform3D.IDENTITY
	)
	var saved_velocity: Vector3 = saved_player.get(
		"velocity",
		Vector3.ZERO
	)
	var source_proxy_hidden: bool = not (
		player.get_node("MeshInstance3D") as MeshInstance3D
	).visible
	Input.action_release("move_forward")

	var restored: bool = bool(application.call("restore_snapshot", snapshot))
	var restored_player := application.get(
		"current_player"
	) as CharacterBody3D
	var restored_movement: Dictionary = restored_player.call(
		"get_movement_semantic_state"
	)
	assert_true.call(
		restored
		and source_movement.get("support", "") == "grounded"
		and source_movement.get("stance", "") == "standing"
		and source_movement.get("traversal", "") == "normal"
		and saved_player.get("restore_policy", &"") == &"direct"
		and saved_player.get("restore_stance", &"") == &"standing"
		and _vectors_close(
			restored_player.global_position,
			saved_transform.origin,
			POSITION_TOLERANCE
		)
		and _vectors_close(
			restored_player.velocity,
			saved_velocity,
			VELOCITY_TOLERANCE
		)
		and restored_movement.get("stance", "") == "standing"
		and restored_movement.get("traversal", "") == "normal"
		and source_proxy_hidden
		and not (
			restored_player.get_node("MeshInstance3D") as MeshInstance3D
		).visible,
		"Phase 4.3 directly restores ordinary standing/moving pose while the collision proxy stays hidden from first-person presentation"
	)
	await _cleanup_application(tree, application)


func _prove_direct_crouched_restore(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	var application: Node = await _launch_application(tree, FLAT_PATH)
	var player := application.get("current_player") as CharacterBody3D

	Input.action_press("crouch")
	await _completed_physics_frame(tree)
	Input.action_release("crouch")
	await _advance_frames(tree, 10)
	var source_movement: Dictionary = player.call(
		"get_movement_semantic_state"
	)
	var snapshot: Dictionary = _capture_snapshot(application, 4302)
	var saved_player: Dictionary = snapshot.get(
		"session",
		{}
	).get("world_state", {}).get("player", {})

	var restored: bool = bool(application.call("restore_snapshot", snapshot))
	var restored_player := application.get(
		"current_player"
	) as CharacterBody3D
	var restored_movement: Dictionary = restored_player.call(
		"get_movement_semantic_state"
	)
	var restored_crouch: PlayerCrouch = restored_player.get("crouch")
	assert_true.call(
		restored
		and source_movement.get("stance", "") == "crouched"
		and source_movement.get("traversal", "") == "normal"
		and saved_player.get("restore_policy", &"") == &"direct"
		and saved_player.get("source_stance", &"") == &"crouched"
		and saved_player.get("restore_stance", &"") == &"crouched"
		and restored_movement.get("stance", "") == "crouched"
		and restored_movement.get("traversal", "") == "normal"
		and restored_crouch != null
		and restored_crouch.is_fully_crouched(),
		"Phase 4.3 directly restores crouched semantic stance and live collider/head geometry"
	)
	await _cleanup_application(tree, application)


func _prove_stance_transition_restore(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	var application: Node = await _launch_application(tree, FLAT_PATH)
	var player := application.get("current_player") as CharacterBody3D

	var crouch: PlayerCrouch = player.get("crouch")
	crouch.request_stance(PlayerCrouch.Stance.CROUCHED)
	var down_mid_height: float = (
		crouch.get_height_for_stance(PlayerCrouch.Stance.STANDING)
		+ crouch.get_height_for_stance(PlayerCrouch.Stance.CROUCHED)
	) * 0.5
	crouch.call("_apply_height", down_mid_height)
	var down_snapshot: Dictionary = _capture_snapshot(application, 4304)
	var down_saved: Dictionary = down_snapshot.get(
		"session",
		{}
	).get("world_state", {}).get("player", {})
	var down_restored: bool = bool(
		application.call("restore_snapshot", down_snapshot)
	)
	var restored_player := application.get(
		"current_player"
	) as CharacterBody3D
	var restored_crouch: PlayerCrouch = restored_player.get("crouch")
	assert_true.call(
		crouch.get_height_for_stance(PlayerCrouch.Stance.STANDING)
		> crouch.get_height_for_stance(PlayerCrouch.Stance.CROUCHED)
		and down_saved.get("source_stance", &"") == &"transitioning"
		and down_saved.get("restore_stance", &"") == &"crouched",
		"Phase 4.3 captures a real mid-crouch transition and its requested crouched endpoint; saved=%s"
		% str(down_saved)
	)
	assert_true.call(
		down_restored
		and restored_crouch != null
		and restored_crouch.is_fully_crouched(),
		"Phase 4.3 restores the captured mid-crouch transition to crouched; restored=%s stance=%s"
		% [
			str(down_restored),
			(
				str(restored_player.call("get_movement_semantic_state"))
				if restored_player != null else "<missing player>"
			),
		]
	)

	# A new replacement session publishes its first stable save boundary on the
	# next live physics tick. Production F5 waits for that boundary; this direct
	# snapshot helper must do the same before exercising a second restore.
	await _completed_physics_frame(tree)

	restored_crouch.request_stance(PlayerCrouch.Stance.STANDING)
	var up_mid_height: float = (
		restored_crouch.get_height_for_stance(PlayerCrouch.Stance.STANDING)
		+ restored_crouch.get_height_for_stance(PlayerCrouch.Stance.CROUCHED)
	) * 0.5
	restored_crouch.call("_apply_height", up_mid_height)
	var up_snapshot: Dictionary = _capture_snapshot(application, 4305)
	var up_saved: Dictionary = up_snapshot.get(
		"session",
		{}
	).get("world_state", {}).get("player", {})
	var up_restored: bool = bool(
		application.call("restore_snapshot", up_snapshot)
	)
	restored_player = application.get("current_player") as CharacterBody3D
	restored_crouch = restored_player.get("crouch")
	assert_true.call(
		up_saved.get("source_stance", &"") == &"transitioning"
		and up_saved.get("restore_stance", &"") == &"standing",
		"Phase 4.3 captures a real mid-stand transition and its requested standing endpoint; saved=%s"
		% str(up_saved)
	)
	assert_true.call(
		up_restored
		and restored_crouch != null
		and restored_crouch.is_fully_standing(),
		"Phase 4.3 restores the captured mid-stand transition to standing; restored=%s stance=%s"
		% [
			str(up_restored),
			(
				str(restored_player.call("get_movement_semantic_state"))
				if restored_player != null else "<missing player>"
			),
		]
	)
	await _cleanup_application(tree, application)


func _prove_direct_airborne_restore(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	var application: Node = await _launch_application(tree, FLAT_PATH)
	var player := application.get("current_player") as CharacterBody3D
	var support: PlayerSupport = player.get("support")
	var velocity_state: PlayerVelocityState = player.get("velocity_state")

	# Jump behavior is already proven by the Movement suite. This restore-policy
	# regression establishes the resulting ordinary semantic condition directly:
	# unsupported body pose plus positive authoritative ballistic velocity.
	player.global_position += Vector3.UP * 1.5
	player.velocity = Vector3(0.8, 4.25, -0.6)
	support.release_walkable_support(player)
	velocity_state.capture_body_as_controlled(player)

	var source_movement: Dictionary = player.call(
		"get_movement_semantic_state"
	)
	var snapshot: Dictionary = _capture_snapshot(application, 4303)
	var saved_player: Dictionary = snapshot.get(
		"session",
		{}
	).get("world_state", {}).get("player", {})
	var saved_velocity: Vector3 = saved_player.get(
		"velocity",
		Vector3.ZERO
	)

	assert_true.call(
		support != null
		and velocity_state != null
		and source_movement.get("support", "") == "airborne"
		and source_movement.get("traversal", "") == "normal"
		and saved_player.get("restore_policy", &"") == &"direct"
		and saved_velocity.y > 0.0,
		"Phase 4.3 captures ordinary unsupported airborne state as directly restorable"
	)

	var restored: bool = bool(application.call("restore_snapshot", snapshot))
	var restored_player := application.get(
		"current_player"
	) as CharacterBody3D
	var restored_movement: Dictionary = restored_player.call(
		"get_movement_semantic_state"
	)
	assert_true.call(
		restored
		and restored_movement.get("support", "") == "airborne"
		and restored_movement.get("traversal", "") == "normal"
		and _vectors_close(
			restored_player.velocity,
			saved_velocity,
			VELOCITY_TOLERANCE
		),
		"Phase 4.3 directly restores unsupported airborne pose and ballistic velocity"
	)
	await _cleanup_application(tree, application)


func _prove_reconstructed_traversal_restore(
	tree: SceneTree,
	assert_true: Callable,
	target_state: StringName
) -> void:
	var application: Node = await _launch_application(tree, LEDGE_PATH)
	var player := application.get("current_player") as CharacterBody3D
	var reached: bool = await _reach_traversal_state(
		tree,
		player,
		target_state
	)
	if not reached:
		assert_true.call(
			false,
			"Phase 4.3 fixture reaches traversal source state %s"
			% target_state
		)
		await _cleanup_application(tree, application)
		return

	var snapshot: Dictionary = _capture_snapshot(
		application,
		4400 + _traversal_generation_offset(target_state)
	)
	var saved_player: Dictionary = snapshot.get(
		"session",
		{}
	).get("world_state", {}).get("player", {})
	var saved_transform: Transform3D = saved_player.get(
		"transform",
		Transform3D.IDENTITY
	)
	var anchor: Dictionary = saved_player.get("traversal_anchor", {})
	var restored: bool = bool(application.call("restore_snapshot", snapshot))
	var restored_player := application.get(
		"current_player"
	) as CharacterBody3D
	var immediate: Dictionary = restored_player.call(
		"get_movement_semantic_state"
	)
	var restored_controller: PlayerLedgeController = restored_player.get(
		"ledge_controller"
	)

	assert_true.call(
		saved_player.get("source_traversal", &"") == target_state
		and saved_player.get("restore_policy", &"") == &"reconstruct_hang"
		and anchor.size() == 4,
		"Phase 4.3 records %s as detached stable ledge-attachment reconstruction data"
		% target_state
	)
	if not restored or restored_player == null:
		assert_true.call(
			false,
			"Phase 4.3 replacement reconstructs traversal source %s successfully"
			% target_state
		)
		await _cleanup_application(tree, application)
		return
	assert_true.call(
		restored
		and restored_player != null
		and restored_player.velocity.is_zero_approx()
		and immediate.get("support", "") == "airborne"
		and immediate.get("traversal", "") == "hanging"
		and restored_controller != null
		and not restored_controller.is_restore_reentry_blocked()
		and restored_player.global_position.distance_to(
			saved_transform.origin
		) <= 0.02,
		"Phase 4.3 restores %s to a stable hang in the replacement world instead of dropping the player"
		% target_state
	)

	var stable_position: Vector3 = restored_player.global_position
	await _advance_frames(tree, 4)
	var after_frames: Dictionary = restored_player.call(
		"get_movement_semantic_state"
	)
	assert_true.call(
		after_frames.get("traversal", "") == "hanging"
		and restored_player.global_position.distance_to(stable_position)
		<= 0.025,
		"Phase 4.3 reconstructed %s remains stably attached after gameplay resumes"
		% target_state
	)
	await _cleanup_application(tree, application)


func _prove_legacy_airborne_normalization_restore(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	var application: Node = await _launch_application(tree, LEDGE_PATH)
	var player := application.get("current_player") as CharacterBody3D
	if not await _reach_traversal_state(tree, player, &"hanging"):
		assert_true.call(false, "Phase 4.3 legacy-save fixture reaches hanging")
		await _cleanup_application(tree, application)
		return

	var snapshot: Dictionary = _capture_snapshot(application, 4499)
	var session_snapshot: Dictionary = snapshot.get("session", {})
	var world_state: Dictionary = session_snapshot.get("world_state", {})
	var saved_player: Dictionary = world_state.get("player", {})
	# Saves made under the earlier policy have no anchor and explicitly say
	# normalize_airborne. Honor that meaning instead of bumping global format.
	saved_player.erase("traversal_anchor")
	saved_player["restore_policy"] = &"normalize_airborne"
	saved_player["velocity"] = Vector3.ZERO
	world_state["player"] = saved_player
	session_snapshot["world_state"] = world_state
	snapshot["session"] = session_snapshot

	var restored: bool = bool(application.call("restore_snapshot", snapshot))
	var restored_player := application.get(
		"current_player"
	) as CharacterBody3D
	var controller: PlayerLedgeController = restored_player.get(
		"ledge_controller"
	)
	assert_true.call(
		restored
		and restored_player.call("get_movement_semantic_state").get(
			"traversal",
			""
		) == "normal"
		and controller != null
		and controller.is_restore_reentry_blocked(),
		"Phase 4.3 retains backward compatibility with pre-correction normalized-airborne traversal saves"
	)
	await _cleanup_application(tree, application)


func _prove_hotkey_step_restore_resumes(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	const TEST_SAVE_DIRECTORY := "user://vark_tests/hotkey_step_restore"
	_cleanup_hotkey_restore_storage(TEST_SAVE_DIRECTORY)
	var application: Node = await _launch_application(tree, STEP_PATH)
	var player := application.get("current_player") as CharacterBody3D
	var step: PlayerStep = player.get("step")
	Input.action_press("move_forward")
	var reached_step: bool = false
	for _frame: int in 80:
		await _completed_physics_frame(tree)
		if step != null and step.is_active():
			reached_step = true
			break
	if not reached_step:
		Input.action_release("move_forward")
		assert_true.call(false, "Phase 4.3 hotkey restore fixture reaches active automatic step")
		await _cleanup_application(tree, application)
		_cleanup_hotkey_restore_storage(TEST_SAVE_DIRECTORY)
		return

	var source_position: Vector3 = player.global_position
	var expected_safe_transform: Transform3D = step.get_restore_safe_transform(
		player.global_transform
	)
	var source_snapshot: Dictionary = player.call("capture_semantic_state")
	var coordinator := application.get_node("SaveCoordinator") as Node
	coordinator.set("durable_save_directory", TEST_SAVE_DIRECTORY)
	var boundary := application.get_node("InputBoundary") as Node
	var save_event := InputEventKey.new()
	save_event.pressed = true
	save_event.keycode = KEY_F5
	boundary.call("route_input_event", save_event)
	var generation: int = int(coordinator.get("_next_generation")) - 1
	var snapshot: Dictionary = await _wait_for_hotkey_save(
		tree,
		coordinator,
		generation,
		180
	)
	var saved_player: Dictionary = snapshot.get(
		"session",
		{}
	).get("world_state", {}).get("player", {})
	var saved_transform: Transform3D = saved_player.get(
		"transform",
		Transform3D.IDENTITY
	)
	Input.action_release("move_forward")
	var old_session_id: int = int(application.call("get_current_session_id"))
	var load_event := InputEventKey.new()
	load_event.pressed = true
	load_event.keycode = KEY_F9
	boundary.call("route_input_event", load_event)
	var replaced: bool = false
	for _frame: int in 180:
		await tree.process_frame
		if int(application.call("get_current_session_id")) != old_session_id:
			replaced = true
			break

	var restored := application.get("current_player") as CharacterBody3D
	var restored_start: Vector3 = (
		restored.global_position if restored != null else Vector3.ZERO
	)
	Input.action_press("move_forward")
	await _advance_frames(tree, 45)
	Input.action_release("move_forward")
	var restored_end: Vector3 = (
		restored.global_position
		if restored != null and is_instance_valid(restored)
		else restored_start
	)
	assert_true.call(
		not snapshot.is_empty()
		and source_snapshot.get("source_traversal", &"") == &"stepping"
		and source_snapshot.get("restore_policy", &"") == &"normalize_step_source"
		and saved_player.get("source_traversal", &"") == &"stepping"
		and saved_player.get("restore_policy", &"") == &"normalize_step_source"
		and saved_transform.is_equal_approx(expected_safe_transform)
		and reached_step
		and replaced
		and restored != null
		and restored_start.distance_to(saved_transform.origin) <= 0.02
		and restored_start.y <= source_position.y + 0.001
		and not (restored.get("step") as PlayerStep).is_active()
		and restored.call("get_movement_semantic_state").get(
			"traversal",
			""
		) == "normal"
		and restored_end.z < restored_start.z - 0.25,
		"Phase 4.3 F5/F9 normalizes an active automatic step back to its collision-safe source pose, discards the transient route, and resumes forward locomotion"
	)
	await _cleanup_application(tree, application)
	_cleanup_hotkey_restore_storage(TEST_SAVE_DIRECTORY)


func _prove_hotkey_hanging_restore_resumes(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	const TEST_SAVE_DIRECTORY := "user://vark_tests/hotkey_hanging_restore"
	_cleanup_hotkey_restore_storage(TEST_SAVE_DIRECTORY)
	var application: Node = await _launch_application(tree, LEDGE_PATH)
	var player := application.get("current_player") as CharacterBody3D
	var reached: bool = await _reach_traversal_state(tree, player, &"hanging")
	if not reached:
		assert_true.call(false, "Phase 4.3 hotkey restore fixture reaches hanging")
		await _cleanup_application(tree, application)
		_cleanup_hotkey_restore_storage(TEST_SAVE_DIRECTORY)
		return

	var coordinator := application.get_node("SaveCoordinator") as Node
	coordinator.set("durable_save_directory", TEST_SAVE_DIRECTORY)
	var boundary := application.get_node("InputBoundary") as Node

	var look_event := InputEventMouseMotion.new()
	look_event.relative = Vector2(17.0, -6.0)
	boundary.call("route_input_event", look_event)
	var saved_view: Dictionary = application.call("get_current_view_pose")

	var save_event := InputEventKey.new()
	save_event.pressed = true
	save_event.keycode = KEY_F5
	boundary.call("route_input_event", save_event)
	var generation: int = int(coordinator.get("_next_generation")) - 1
	var snapshot: Dictionary = await _wait_for_hotkey_save(
		tree,
		coordinator,
		generation,
		180
	)
	var saved_player: Dictionary = snapshot.get(
		"session",
		{}
	).get("world_state", {}).get("player", {})
	var old_session_id: int = int(application.call("get_current_session_id"))
	var load_event := InputEventKey.new()
	load_event.pressed = true
	load_event.keycode = KEY_F9
	boundary.call("route_input_event", load_event)
	var replaced: bool = false
	for _frame: int in 180:
		await tree.process_frame
		if int(application.call("get_current_session_id")) != old_session_id:
			replaced = true
			break

	var restored_player := application.get("current_player") as CharacterBody3D
	if not replaced or restored_player == null:
		assert_true.call(
			false,
			"Phase 4.3 F5/F9 hanging replacement reconstructs a live player"
		)
		await _cleanup_application(tree, application)
		_cleanup_hotkey_restore_storage(TEST_SAVE_DIRECTORY)
		return
	var restored_view: Dictionary = application.call("get_current_view_pose")
	var stable_position: Vector3 = (
		restored_player.global_position
		if restored_player != null
		else Vector3.ZERO
	)
	await _advance_frames(tree, 4)
	var movement: Dictionary = (
		restored_player.call("get_movement_semantic_state")
		if restored_player != null else {}
	)
	var restored_look: PlayerLook = (
		restored_player.get("player_look")
		if restored_player != null else null
	)
	var proxy := (
		restored_player.get_node("MeshInstance3D") as MeshInstance3D
		if restored_player != null else null
	)
	assert_true.call(
		not snapshot.is_empty()
		and saved_player.get("restore_policy", &"") == &"reconstruct_hang"
		and replaced
		and restored_player != null
		and int(application.call("get_current_session_state")) == 4
		and bool(boundary.get("gameplay_enabled"))
		and movement.get("traversal", "") == "hanging"
		and restored_player.global_position.distance_to(stable_position) <= 0.025
		and restored_look != null
		and restored_look.ledge_view_active
		and proxy != null
		and not proxy.visible
		and absf(
			wrapf(
				float(restored_view.get("body_yaw", 0.0))
				- float(saved_view.get("body_yaw", 0.0)),
				-PI,
				PI
			)
		) <= VIEW_TOLERANCE
		and absf(
			float(restored_view.get("head_pitch", 0.0))
			- float(saved_view.get("head_pitch", 0.0))
		) <= VIEW_TOLERANCE,
		"Phase 4.3 F5/F9 restores a saved hang as a stable attachment with continuous ledge view and no visible collision capsule"
	)

	var yaw_before: float = float(
		application.call("get_current_view_pose").get("body_yaw", 0.0)
	)
	var followup_look := InputEventMouseMotion.new()
	followup_look.relative = Vector2(1.0, 0.0)
	boundary.call("route_input_event", followup_look)
	var yaw_after: float = float(
		application.call("get_current_view_pose").get("body_yaw", 0.0)
	)
	var yaw_delta: float = absf(wrapf(yaw_after - yaw_before, -PI, PI))

	var shimmy_start: Vector3 = restored_player.global_position
	Input.action_press("move_right")
	await _advance_frames(tree, 8)
	Input.action_release("move_right")
	var after_shimmy: Dictionary = restored_player.call(
		"get_movement_semantic_state"
	)
	assert_true.call(
		yaw_delta > 0.0001
		and yaw_delta < 0.05
		and after_shimmy.get("traversal", "") == "hanging"
		and restored_player.global_position.distance_to(shimmy_start) > 0.02,
		"Restored hanging state accepts fresh look and shimmy input without a view snap or stale traversal lock"
	)
	await _cleanup_application(tree, application)
	_cleanup_hotkey_restore_storage(TEST_SAVE_DIRECTORY)


func _wait_for_hotkey_save(
	tree: SceneTree,
	coordinator: Node,
	generation: int,
	max_frames: int
) -> Dictionary:
	for _frame: int in max_frames:
		var status: Dictionary = coordinator.call("get_request_status", generation)
		if status.get("status", &"") == &"committed":
			return coordinator.call("get_request_snapshot", generation)
		if status.get("status", &"") in [&"failed", &"cancelled", &"superseded"]:
			return {}
		await tree.physics_frame
		await tree.process_frame
	return {}


func _cleanup_hotkey_restore_storage(directory: String) -> void:
	var final_path: String = directory + "/quicksave.varksave"
	for path: String in [final_path, final_path + ".new", final_path + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var absolute_dir: String = ProjectSettings.globalize_path(directory)
	if DirAccess.dir_exists_absolute(absolute_dir):
		DirAccess.remove_absolute(absolute_dir)


func _reach_traversal_state(
	tree: SceneTree,
	player: CharacterBody3D,
	target_state: StringName
) -> bool:
	if target_state == &"catching":
		return await _wait_for_traversal_state(
			tree,
			player,
			"catching",
			90
		)
	if target_state == &"hanging":
		return await _wait_for_traversal_state(
			tree,
			player,
			"hanging",
			100
		)

	if not await _wait_for_traversal_state(
		tree,
		player,
		"hanging",
		100
	):
		return false

	if target_state == &"mantling":
		Input.action_press("jump")
		await _completed_physics_frame(tree)
		Input.action_release("jump")
		return (
			str(player.call(
				"get_movement_semantic_state"
			).get("traversal", "")) == "mantling"
		)

	if target_state == &"cornering":
		Input.action_press("move_right")
		await _advance_frames(tree, 60)
		Input.action_release("move_right")
		await _advance_frames(tree, 2)
		Input.action_press("move_right")
		var reached_corner: bool = await _wait_for_traversal_state(
			tree,
			player,
			"cornering",
			60
		)
		Input.action_release("move_right")
		return reached_corner

	return false


func _capture_snapshot(
	application: Node,
	generation: int
) -> Dictionary:
	var session := application.get("current_session") as Node
	var envelope: Dictionary = session.call("capture_save_envelope")
	var view_pose: Dictionary = application.call("get_current_view_pose")
	return {
		"generation": generation,
		"slot": &"phase43",
		"session": envelope.duplicate(true),
		"player_view_pose": view_pose.duplicate(true),
	}


func _launch_application(
	tree: SceneTree,
	scene_path: String
) -> Node:
	_release_actions()
	var application: Node = ApplicationScene.instantiate()
	application.set(
		"development_launch_labels",
		PackedStringArray(["Phase 4.3 Fixture"])
	)
	application.set(
		"development_launch_resource_paths",
		PackedStringArray([scene_path])
	)
	tree.get_root().add_child(application)
	await tree.process_frame
	var launched: bool = bool(
		application.call("launch_development_target", 0)
	)
	assert(
		launched,
		"Phase 4.3 fixture must launch through the production application path."
	)
	if scene_path == FLAT_PATH:
		await _advance_frames(tree, 3)
	return application


func _wait_for_traversal_state(
	tree: SceneTree,
	player: CharacterBody3D,
	target: String,
	max_frames: int
) -> bool:
	for _frame: int in max_frames:
		var state: Dictionary = player.call(
			"get_movement_semantic_state"
		)
		if str(state.get("traversal", "")) == target:
			return true
		await _completed_physics_frame(tree)
	return (
		str(player.call(
			"get_movement_semantic_state"
		).get("traversal", "")) == target
	)


func _advance_frames(tree: SceneTree, frame_count: int) -> void:
	for _frame: int in frame_count:
		await _completed_physics_frame(tree)


func _completed_physics_frame(tree: SceneTree) -> void:
	await tree.physics_frame
	await tree.process_frame


func _cleanup_application(
	tree: SceneTree,
	application: Node
) -> void:
	_release_actions()
	if application != null and is_instance_valid(application):
		application.call("exit_current_world")
		application.queue_free()
	await tree.process_frame


func _release_actions() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_forward")
	Input.action_release("move_backward")
	Input.action_release("jump")
	Input.action_release("crouch")
	Input.action_release("sprint")


func _vectors_close(
	a: Vector3,
	b: Vector3,
	tolerance: float
) -> bool:
	return a.distance_to(b) <= tolerance


func _traversal_generation_offset(state: StringName) -> int:
	match state:
		&"catching":
			return 1
		&"hanging":
			return 2
		&"cornering":
			return 3
		&"mantling":
			return 4
	return 9
