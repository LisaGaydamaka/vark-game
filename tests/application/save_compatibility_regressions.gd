extends RefCounted


const ApplicationScene = preload("res://application/Application.tscn")
const SaveFormat = preload("res://application/save_format.gd")
const WorldSession = preload("res://application/world_session.gd")
const PLAYGROUND_MISSION_PATH: String = "res://missions/playground/mission.tres"
const TEST_SAVE_DIRECTORY: String = "user://vark_tests/phase46"
const POSITION_TOLERANCE: float = 0.001


func run(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	_cleanup_test_storage()

	var application: Node = await _launch_playground(tree)
	var coordinator: Node = application.get_node("SaveCoordinator")
	coordinator.set("durable_save_directory", TEST_SAVE_DIRECTORY)
	var session := application.get("current_session") as Node
	var player := application.get("current_player") as CharacterBody3D
	var definition := session.get("mission_definition") as Resource

	player.global_position += Vector3(0.45, 0.0, -0.20)
	player.velocity = Vector3.ZERO
	var first_saved_position: Vector3 = player.global_position
	var first_generation: int = int(
		application.call("request_quicksave")
	)
	var first_committed: bool = await _wait_for_save_status(
		tree,
		coordinator,
		first_generation,
		&"committed",
		30
	)
	var first_snapshot: Dictionary = coordinator.call(
		"get_request_snapshot",
		first_generation
	)
	var first_envelope: Dictionary = first_snapshot.get(
		"session",
		{}
	)
	var durable_path: String = str(coordinator.call(
		"get_durable_save_path"
	))

	assert_true.call(
		first_committed
		and first_generation > 0
		and int(first_envelope.get(
			"save_format_version",
			0
		)) == SaveFormat.CURRENT_VERSION
		and first_envelope.get("mission_id", &"")
			== &"playground"
		and int(first_envelope.get(
			"mission_content_revision",
			0
		)) == 1
		and definition != null
		and definition.get("mission_id") == &"playground"
		and int(definition.get(
			"mission_content_revision"
		)) == int(first_envelope.get(
			"mission_content_revision",
			0
		)),
		"Phase 4.6 save envelope records global format, mission identity, and MissionDefinition-owned content revision separately"
	)
	assert_true.call(
		not durable_path.is_empty()
		and FileAccess.file_exists(durable_path)
		and not FileAccess.file_exists(
			durable_path + ".new"
		)
		and not FileAccess.file_exists(
			durable_path + ".bak"
		),
		"Phase 4.6 committed quicksave has one validated durable slot file with no leftover replacement artifacts"
	)

	var source_session: Node = session
	var bad_format: Dictionary = first_snapshot.duplicate(true)
	var bad_format_envelope: Dictionary = bad_format.get(
		"session",
		{}
	)
	bad_format_envelope["save_format_version"] = (
		SaveFormat.CURRENT_VERSION + 1
	)
	bad_format["session"] = bad_format_envelope
	var rejected_format: bool = not bool(
		application.call("restore_snapshot", bad_format)
	)
	var format_error: String = str(
		application.call("get_last_save_error")
	)
	assert_true.call(
		rejected_format
		and application.get("current_session")
			== source_session
		and format_error.contains(
			"Unsupported save format version"
		)
		and format_error.contains(
			"No migration is available"
		),
		"Phase 4.6 unsupported global save format fails closed before replacement with a clear no-migration error"
	)

	var bad_revision: Dictionary = first_snapshot.duplicate(true)
	var bad_revision_envelope: Dictionary = bad_revision.get(
		"session",
		{}
	)
	bad_revision_envelope[
		"mission_content_revision"
	] = int(first_envelope.get(
		"mission_content_revision",
		0
	)) + 1
	bad_revision["session"] = bad_revision_envelope
	var rejected_revision: bool = not bool(
		application.call("restore_snapshot", bad_revision)
	)
	var revision_error: String = str(
		application.call("get_last_save_error")
	)
	assert_true.call(
		rejected_revision
		and application.get("current_session")
			== source_session
		and revision_error.contains(
			"Unsupported mission content revision"
		)
		and revision_error.contains("playground")
		and revision_error.contains(
			"No migration is available"
		),
		"Phase 4.6 incompatible MissionDefinition content revision fails closed with an explicit revision error"
	)

	var bad_mission: Dictionary = first_snapshot.duplicate(true)
	var bad_mission_envelope: Dictionary = bad_mission.get(
		"session",
		{}
	)
	bad_mission_envelope["mission_id"] = &"playground.other"
	bad_mission["session"] = bad_mission_envelope
	var rejected_mission: bool = not bool(
		application.call("restore_snapshot", bad_mission)
	)
	var mission_error: String = str(
		application.call("get_last_save_error")
	)
	assert_true.call(
		rejected_mission
		and application.get("current_session")
			== source_session
		and mission_error.contains(
			"Unsupported save mission_id"
		)
		and mission_error.contains("playground"),
		"Phase 4.6 incompatible mission identity fails closed before destructive replacement"
	)

	player.global_position = first_saved_position + Vector3(
		0.75,
		0.0,
		0.35
	)
	player.velocity = Vector3.ZERO
	var second_saved_position: Vector3 = player.global_position
	var second_generation: int = int(
		application.call("request_quicksave")
	)
	var second_committed: bool = await _wait_for_save_status(
		tree,
		coordinator,
		second_generation,
		&"committed",
		30
	)
	var second_snapshot: Dictionary = coordinator.call(
		"get_request_snapshot",
		second_generation
	)
	var second_saved_transform: Transform3D = second_snapshot.get(
		"session",
		{}
	).get("world_state", {}).get(
		"player",
		{}
	).get(
		"transform",
		Transform3D.IDENTITY
	)
	assert_true.call(
		second_committed
		and second_generation > first_generation
		and second_saved_transform.origin.distance_to(
			second_saved_position
		) <= POSITION_TOLERANCE
		and FileAccess.file_exists(durable_path)
		and not FileAccess.file_exists(
			durable_path + ".new"
		)
		and not FileAccess.file_exists(
			durable_path + ".bak"
		),
		"Phase 4.6 newer validated snapshot replaces the previous durable slot only after successful capture/validation"
	)

	# Simulate an interrupted future write leaving only a corrupt temporary file
	# beside the last known-good durable slot. A fresh coordinator must prefer
	# the valid final slot and discard the uncommitted temporary artifact.
	var corrupt_temp := FileAccess.open(
		durable_path + ".new",
		FileAccess.WRITE
	)
	if corrupt_temp != null:
		corrupt_temp.store_string(
			"not a Vark snapshot"
		)
		corrupt_temp.close()

	application.queue_free()
	await tree.process_frame

	var reloaded_application: Node = ApplicationScene.instantiate()
	tree.get_root().add_child(reloaded_application)
	await tree.process_frame
	var reloaded_coordinator: Node = reloaded_application.get_node(
		"SaveCoordinator"
	)
	reloaded_coordinator.set(
		"durable_save_directory",
		TEST_SAVE_DIRECTORY
	)
	var durable_loaded: bool = bool(
		reloaded_application.call("quickload_latest")
	)
	var restored_session := reloaded_application.get(
		"current_session"
	) as Node
	var restored_player := reloaded_application.get(
		"current_player"
	) as CharacterBody3D
	var restored_definition: Resource = (
		restored_session.get("mission_definition")
		if restored_session != null
		else null
	)
	var disk_snapshot: Dictionary = reloaded_application.call(
		"get_latest_quicksave_snapshot"
	)

	assert_true.call(
		durable_loaded
		and restored_session != null
		and int(reloaded_application.call(
			"get_current_session_state"
		)) == WorldSession.State.PLAYING
		and restored_definition != null
		and restored_definition.resource_path
			== PLAYGROUND_MISSION_PATH
		and int(disk_snapshot.get(
			"generation",
			0
		)) == second_generation
		and restored_player != null
		and restored_player.global_position.distance_to(
			second_saved_position
		) <= POSITION_TOLERANCE
		and not FileAccess.file_exists(
			durable_path + ".new"
		)
		and not FileAccess.file_exists(
			durable_path + ".bak"
		),
		"Phase 4.6 a fresh Application process-owner quickloads the latest durable mission snapshot and ignores an uncommitted corrupt temp artifact"
	)

	if reloaded_application.get("current_session") != null:
		reloaded_application.call("exit_current_world")
	reloaded_application.queue_free()
	await tree.process_frame
	_cleanup_test_storage()


func _launch_playground(tree: SceneTree) -> Node:
	var application: Node = ApplicationScene.instantiate()
	application.set(
		"development_launch_labels",
		PackedStringArray(["Playground"])
	)
	application.set(
		"development_launch_resource_paths",
		PackedStringArray([PLAYGROUND_MISSION_PATH])
	)
	tree.get_root().add_child(application)
	await tree.process_frame
	var coordinator: Node = application.get_node(
		"SaveCoordinator"
	)
	coordinator.set(
		"durable_save_directory",
		TEST_SAVE_DIRECTORY
	)
	var launched: bool = bool(
		application.call("launch_development_target", 0)
	)
	assert(
		launched,
		"Phase 4.6 requires the authored Playground MissionDefinition."
	)
	await tree.physics_frame
	await tree.process_frame
	return application


func _wait_for_save_status(
	tree: SceneTree,
	coordinator: Node,
	generation: int,
	expected: StringName,
	max_frames: int
) -> bool:
	for _frame: int in max_frames:
		var status: Dictionary = coordinator.call(
			"get_request_status",
			generation
		)
		if status.get("status", &"") == expected:
			return true
		await tree.physics_frame
		await tree.process_frame
	return (
		coordinator.call(
			"get_request_status",
			generation
		).get("status", &"") == expected
	)


func _cleanup_test_storage() -> void:
	var final_path: String = (
		TEST_SAVE_DIRECTORY
		+ "/quicksave.varksave"
	)
	for path: String in [
		final_path,
		final_path + ".new",
		final_path + ".bak",
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(
				ProjectSettings.globalize_path(path)
			)
	var absolute_dir: String = ProjectSettings.globalize_path(
		TEST_SAVE_DIRECTORY
	)
	if DirAccess.dir_exists_absolute(absolute_dir):
		DirAccess.remove_absolute(absolute_dir)
