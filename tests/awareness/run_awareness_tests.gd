extends SceneTree


const ApplicationScene = preload("res://application/Application.tscn")
const AWARENESS_SCRIPT_PATH: String = "res://gameplay/npc/guard_awareness.gd"
const STATE_UNAWARE: StringName = &"unaware"
const STATE_SUSPICIOUS: StringName = &"suspicious"
const STATE_INVESTIGATING: StringName = &"investigating"
const STATE_SEARCHING: StringName = &"searching"
const STATE_ALERTED: StringName = &"alerted"
const STATE_RECOVERING: StringName = &"recovering"
const NAV_INVESTIGATE: StringName = &"investigate"
const NAV_SEARCH: StringName = &"search"
const NAV_PURSUIT: StringName = &"pursuit"
const SLICE_PATH: String = "res://missions/integrated_slice/world.tscn"
const TEST_SAVE_DIRECTORY: String = "user://vark_tests/phase54"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_cleanup_test_storage()
	if not _assert_awareness_script_compiles():
		_print_summary()
		quit(1)
		return
	await _assert_guard_awareness_state_machine()
	_print_summary()
	quit(1 if not failures.is_empty() else 0)


func _assert_awareness_script_compiles() -> bool:
	var source: String = FileAccess.get_file_as_string(AWARENESS_SCRIPT_PATH)
	var script := GDScript.new()
	script.source_code = source
	var error: Error = script.reload()
	_assert_true(
		error == OK,
		"Phase 5.4 reusable guard-awareness source compiles independently"
	)
	return error == OK


func _assert_guard_awareness_state_machine() -> void:
	var application: Node = await _launch_slice()
	if application == null:
		return

	var coordinator: Node = application.get_node("SaveCoordinator")
	coordinator.set("durable_save_directory", TEST_SAVE_DIRECTORY)
	var world := application.get("current_world") as Node3D
	var session := application.get("current_session") as Node
	var player := application.get("current_player") as CharacterBody3D
	var guard := world.get_node("Guard") as VarkGuard
	var reaction := world.get_node("Guard/Reaction") as Node
	var light := world.get_node(
		"NorthGameplayLight"
	) as VarkGameplayLight
	var exposure := world.get_node(
		"GameplayExposure"
	) as VarkGameplayExposure

	_configure_short_durations(reaction)
	guard.movement_speed = 0.0
	guard.velocity = Vector3.ZERO
	guard.set_physics_process(false)
	light.gameplay_enabled = false
	light.visible = false
	exposure.sample_now()

	var weak_queued: bool = bool(session.call(
		"queue_gameplay_sound",
		int(session.get("session_id")),
		&"footstep.test",
		guard.global_position,
		0.10
	))
	await _completed_physics_frame()
	var weak_summary: Dictionary = reaction.get_debug_summary()
	var weak_nav: Dictionary = guard.get_awareness_navigation_state()
	_assert_true(
		weak_queued
		and weak_summary.get("awareness_state", &"")
			== STATE_SUSPICIOUS
		and weak_summary.get("state", &"") == &"heard_noise"
		and int(weak_summary.get("heard_count", 0)) == 1
		and not bool(weak_nav.get("active", true)),
		"Phase 5.4 weak local hearing evidence creates mild suspicion without manufacturing an investigation route"
	)

	var returned_unaware: bool = await _wait_for_awareness_state(
		reaction,
		STATE_UNAWARE,
		30
	)
	_assert_true(
		returned_unaware
		and not bool(
			guard.get_awareness_navigation_state().get(
				"active",
				true
			)
		),
		"Phase 5.4 suspicion decays by WorldSession gameplay time and returns to unaware patrol ownership"
	)

	var strong_origin: Vector3 = (
		guard.global_position + Vector3(0.35, 0.0, 0.15)
	)
	var strong_queued: bool = bool(session.call(
		"queue_gameplay_sound",
		int(session.get("session_id")),
		&"prop.impact",
		strong_origin,
		0.60
	))
	await _completed_physics_frame()
	var investigate_summary: Dictionary = reaction.get_debug_summary()
	var investigate_nav: Dictionary = guard.get_awareness_navigation_state()
	_assert_true(
		strong_queued
		and investigate_summary.get("awareness_state", &"")
			== STATE_INVESTIGATING
		and bool(investigate_nav.get("active", false))
		and investigate_nav.get("reason", &"")
			== NAV_INVESTIGATE
		and _dict_vector(
			investigate_nav,
			"target_position"
		).distance_to(strong_origin) <= 0.001,
		"Phase 5.4 strong heard evidence becomes an explicit investigation target owned by the local guard"
	)

	var reached_search: bool = await _wait_for_awareness_state(
		reaction,
		STATE_SEARCHING,
		30
	)
	var search_summary: Dictionary = reaction.get_debug_summary()
	var search_nav: Dictionary = guard.get_awareness_navigation_state()
	var resolved_search_target: Vector3 = search_summary.get(
		"investigation_target",
		Vector3.ZERO
	)
	_assert_true(
		reached_search
		and bool(search_nav.get("active", false))
		and search_nav.get("reason", &"")
			== NAV_SEARCH
		and resolved_search_target.distance_to(
			strong_origin
		) <= 0.001,
		"Phase 5.4 investigation deterministically advances to search while preserving the already-resolved evidence position"
	)

	var generation: int = int(
		application.call("request_quicksave")
	)
	var committed: bool = await _wait_for_save_status(
		coordinator,
		generation,
		&"committed",
		30
	)
	var saved_snapshot: Dictionary = coordinator.call(
		"get_request_snapshot",
		generation
	)
	var awareness_id: String = reaction.get_semantic_save_id()
	var saved_awareness: Dictionary = (
		saved_snapshot.get("session", {})
		.get("world_state", {})
		.get("semantic_owners", {})
		.get(awareness_id, {})
	)
	_assert_true(
		committed
		and saved_awareness.get("state", &"")
			== STATE_SEARCHING
		and bool(saved_awareness.get(
			"has_investigation_target",
			false
		))
		and _dict_vector(
			saved_awareness,
			"investigation_target"
		).distance_to(resolved_search_target) <= 0.001
		and float(saved_awareness.get(
			"state_remaining_seconds",
			0.0
		)) > 0.0,
		"Phase 5.4 search stage, resolved target, and remaining gameplay-time duration are ordinary detached save truth"
	)

	var mutated_to_unaware: bool = await _wait_for_awareness_state(
		reaction,
		STATE_UNAWARE,
		60
	)
	var loaded: bool = bool(
		application.call("quickload_latest")
	)
	world = application.get("current_world") as Node3D
	session = application.get("current_session") as Node
	player = application.get("current_player") as CharacterBody3D
	guard = world.get_node("Guard") as VarkGuard
	reaction = world.get_node("Guard/Reaction") as Node
	light = world.get_node(
		"NorthGameplayLight"
	) as VarkGameplayLight
	exposure = world.get_node(
		"GameplayExposure"
	) as VarkGameplayExposure
	_configure_short_durations(reaction)
	guard.movement_speed = 0.0
	guard.velocity = Vector3.ZERO
	guard.set_physics_process(false)

	var restored_search: Dictionary = reaction.get_debug_summary()
	var restored_nav: Dictionary = guard.get_awareness_navigation_state()
	_assert_true(
		mutated_to_unaware
		and loaded
		and restored_search.get("awareness_state", &"")
			== STATE_SEARCHING
		and _dict_vector(
			restored_search,
			"investigation_target"
		).distance_to(resolved_search_target) <= 0.001
		and is_equal_approx(
			float(restored_search.get(
				"state_remaining_seconds",
				-1.0
			)),
			float(saved_awareness.get(
				"state_remaining_seconds",
				-2.0
			))
		)
		and bool(restored_nav.get("active", false))
		and restored_nav.get("reason", &"")
			== NAV_SEARCH
		and int(session.call(
			"get_pending_semantic_event_count"
		)) == 0,
		"Phase 5.4 quickload restores the resolved search choice and remaining simulation-time stage without replaying hearing"
	)

	reaction.reset_reaction()
	light.gameplay_enabled = true
	light.visible = true
	player.global_position = Vector3(0.0, 0.0, -2.4)
	player.velocity = Vector3.ZERO
	guard.global_position = Vector3(0.0, 0.0, -5.6)
	guard.velocity = Vector3.ZERO
	guard.look_at(player.global_position, Vector3.UP, true)
	await _settle_frames(2)
	exposure.sample_now()
	var confirmed: bool = reaction.sample_vision_now()
	var alert_summary: Dictionary = reaction.get_debug_summary()
	var alert_nav: Dictionary = guard.get_awareness_navigation_state()
	var last_seen: Vector3 = alert_summary.get(
		"last_seen_position",
		Vector3.ZERO
	)
	_assert_true(
		confirmed
		and alert_summary.get("awareness_state", &"")
			== STATE_ALERTED
		and alert_summary.get("state", &"") == &"saw_player"
		and int(alert_summary.get("seen_count", 0)) >= 1
		and bool(alert_nav.get("active", false))
		and alert_nav.get("reason", &"")
			== NAV_PURSUIT
		and _dict_vector(
			alert_nav,
			"target_position"
		).distance_to(last_seen) <= 0.001,
		"Phase 5.4 confirmed local vision enters alert/pursuit and continuously owns a last-seen navigation target"
	)

	light.gameplay_enabled = false
	light.visible = false
	exposure.sample_now()
	var lost_now: bool = not reaction.sample_vision_now()
	var loss_summary: Dictionary = reaction.get_debug_summary()
	_assert_true(
		lost_now
		and loss_summary.get("awareness_state", &"")
			== STATE_ALERTED
		and bool(loss_summary.get(
			"has_alert_loss_timer",
			false
		))
		and float(loss_summary.get(
			"alert_loss_remaining_seconds",
			0.0
		)) > 0.0
		and loss_summary.get("state", &"") != &"saw_player",
		"Phase 5.4 losing sight starts a gameplay-time alert-loss grace instead of instantly forgetting confirmed knowledge"
	)

	var lost_to_search: bool = await _wait_for_awareness_state(
		reaction,
		STATE_SEARCHING,
		30
	)
	var lost_search_nav: Dictionary = guard.get_awareness_navigation_state()
	_assert_true(
		lost_to_search
		and bool(lost_search_nav.get("active", false))
		and lost_search_nav.get("reason", &"")
			== NAV_SEARCH
		and _dict_vector(
			lost_search_nav,
			"target_position"
		).distance_to(last_seen) <= 0.001,
		"Phase 5.4 confirmed-alert loss transitions into search at the resolved last-seen position rather than global player knowledge"
	)

	var recovering: bool = await _wait_for_awareness_state(
		reaction,
		STATE_RECOVERING,
		40
	)
	var recovery_nav: Dictionary = guard.get_awareness_navigation_state()
	var final_unaware: bool = await _wait_for_awareness_state(
		reaction,
		STATE_UNAWARE,
		40
	)
	_assert_true(
		recovering
		and not bool(recovery_nav.get("active", true))
		and final_unaware
		and not bool(
			guard.get_awareness_navigation_state().get(
				"active",
				true
			)
		),
		"Phase 5.4 search exhausts into recovery and finally returns navigation ownership to patrol using only simulation time"
	)

	application.call("exit_current_world")
	application.queue_free()
	await process_frame
	_cleanup_test_storage()


func _dict_vector(
	source: Dictionary,
	key: String
) -> Vector3:
	var value: Variant = source.get(key, Vector3.ZERO)
	return value if typeof(value) == TYPE_VECTOR3 else Vector3.ZERO


func _configure_short_durations(
	reaction: Node
) -> void:
	reaction.hearing_investigate_strength = 0.20
	reaction.suspicion_seconds = 0.08
	reaction.investigation_seconds = 0.10
	reaction.search_seconds = 0.14
	reaction.alert_loss_seconds = 0.08
	reaction.recovery_seconds = 0.08


func _launch_slice() -> Node:
	var application: Node = ApplicationScene.instantiate()
	application.set(
		"development_launch_labels",
		PackedStringArray(["Integrated Slice"])
	)
	application.set(
		"development_launch_resource_paths",
		PackedStringArray([SLICE_PATH])
	)
	get_root().add_child(application)
	await process_frame
	var launched: bool = bool(
		application.call("launch_development_target", 0)
	)
	var ready: bool = await _wait_for_navigation_ready(
		application.get("current_world") as Node,
		240
	)
	_assert_true(
		launched and ready,
		"Phase 5.4 awareness fixture launches the real Integrated Slice with navigation ready"
	)
	if not launched or not ready:
		application.queue_free()
		await process_frame
		return null
	return application


func _wait_for_awareness_state(
	reaction: Node,
	expected: StringName,
	max_frames: int
) -> bool:
	for _frame: int in max_frames:
		if (
			reaction.get_debug_summary().get(
				"awareness_state",
				&""
			) == expected
		):
			return true
		await _completed_physics_frame()
	return (
		reaction.get_debug_summary().get(
			"awareness_state",
			&""
		) == expected
	)


func _wait_for_save_status(
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
		await _completed_physics_frame()
	return (
		coordinator.call(
			"get_request_status",
			generation
		).get("status", &"") == expected
	)


func _wait_for_navigation_ready(
	world: Node,
	max_frames: int
) -> bool:
	if world == null:
		return false
	for _frame: int in max_frames:
		if bool(world.get("navigation_ready")):
			return true
		await _completed_physics_frame()
	return bool(world.get("navigation_ready"))


func _settle_frames(frame_count: int) -> void:
	for _frame: int in frame_count:
		await _completed_physics_frame()


func _completed_physics_frame() -> void:
	await physics_frame
	await process_frame


func _cleanup_test_storage() -> void:
	var final_path: String = (
		TEST_SAVE_DIRECTORY
		+ "/quicksave.varksave"
	)
	for path: String in [
		final_path,
		final_path + ".new",
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


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
		return
	failures.append(message)
	push_error("FAIL: " + message)


func _print_summary() -> void:
	print("")
	print("==============================")
	if failures.is_empty():
		print("ALL AWARENESS TESTS PASSED")
		return
	print("%d AWARENESS TEST(S) FAILED" % failures.size())
	for failure: String in failures:
		print(" - ", failure)
