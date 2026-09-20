extends RefCounted


const ApplicationScene = preload("res://application/Application.tscn")
const FLAT_PATH: String = "res://tests/movement/fixtures/sprint_jump.tscn"
const LEDGE_PATH: String = "res://tests/movement/fixtures/ledge_traversal.tscn"
const POSITION_TOLERANCE: float = 0.001
const VELOCITY_TOLERANCE: float = 0.001


func run(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	await _prove_direct_moving_restore(tree, assert_true)
	await _prove_direct_crouched_restore(tree, assert_true)
	await _prove_direct_airborne_restore(tree, assert_true)
	await _prove_normalized_traversal_restore(tree, assert_true, &"catching")
	await _prove_normalized_traversal_restore(tree, assert_true, &"hanging")
	await _prove_normalized_traversal_restore(tree, assert_true, &"cornering")
	await _prove_normalized_traversal_restore(tree, assert_true, &"mantling")


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
		and restored_movement.get("traversal", "") == "normal",
		"Phase 4.3 directly restores ordinary standing/moving player pose and momentum"
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


func _prove_direct_airborne_restore(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	var application: Node = await _launch_application(tree, FLAT_PATH)
	var player := application.get("current_player") as CharacterBody3D

	Input.action_press("jump")
	await _completed_physics_frame(tree)
	Input.action_release("jump")
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
		source_movement.get("support", "") == "airborne"
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


func _prove_normalized_traversal_restore(
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

	var source_position: Vector3 = player.global_position
	var snapshot: Dictionary = _capture_snapshot(
		application,
		4400 + _traversal_generation_offset(target_state)
	)
	var saved_player: Dictionary = snapshot.get(
		"session",
		{}
	).get("world_state", {}).get("player", {})
	var save_request: int = int(application.call("request_quicksave"))
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
		save_request > 0
		and saved_player.get("source_traversal", &"") == target_state
		and saved_player.get("restore_policy", &"") == &"normalize_airborne",
		"Phase 4.3 keeps %s saveable and records an explicit normalized-airborne restore policy"
		% target_state
	)
	assert_true.call(
		restored
		and _vectors_close(
			restored_player.global_position,
			source_position,
			POSITION_TOLERANCE
		)
		and restored_player.velocity.is_zero_approx()
		and immediate.get("support", "") == "airborne"
		and immediate.get("traversal", "") == "normal"
		and restored_controller != null
		and restored_controller.is_restore_reentry_blocked(),
		"Phase 4.3 normalizes %s to the same collision-safe pose as ordinary airborne state"
		% target_state
	)

	await _advance_frames(tree, 2)
	var after_two_frames: Dictionary = restored_player.call(
		"get_movement_semantic_state"
	)
	assert_true.call(
		after_two_frames.get("traversal", "") == "normal"
		and restored_player.global_position.y < source_position.y + 0.001,
		"Phase 4.3 normalized %s does not immediately recreate discarded traversal runtime state"
		% target_state
	)
	await _cleanup_application(tree, application)


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
