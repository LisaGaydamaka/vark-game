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
const TEST_SAVE_DIRECTORY: String = "user://vark_tests/phase55"

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
	await _assert_advanced_local_search_behavior()
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
		0.18
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
		(
			"Phase 5.4 weak local hearing evidence creates mild suspicion without manufacturing an investigation route "
			+ "(summary=%s nav=%s perception=%s)"
			% [
				str(weak_summary),
				str(weak_nav),
				str(
					(world.get_node("Guard/Hearing") as VarkAcousticListener)
					.get_last_perception()
				),
			]
		)
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
	var search_points: Array = search_summary.get("search_points", [])
	var search_index: int = int(search_summary.get("search_index", 0))
	var current_search_point: Vector3 = (
		search_points[search_index]
		if search_index >= 0 and search_index < search_points.size()
		else Vector3.ZERO
	)
	_assert_true(
		reached_search
		and bool(search_nav.get("active", false))
		and search_nav.get("reason", &"")
			== NAV_SEARCH
		and resolved_search_target.distance_to(
			strong_origin
		) <= 0.001
		and _dict_vector(search_summary, "search_anchor").distance_to(
			strong_origin
		) <= 0.001
		and search_points.size() >= 2
		and _dict_vector(
			search_nav,
			"target_position"
		).distance_to(current_search_point) <= 0.001,
		"Phase 5.5 investigation advances into a resolved multi-point local search rooted only at the evidence position"
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
		)) > 0.0
		and (saved_awareness.get("search_points", []) as Array).size() >= 2
		and int(saved_awareness.get("search_index", -1)) >= 0,
		"Phase 5.5 search stage, resolved multi-point plan/progress, target, and remaining gameplay-time duration are detached save truth"
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
		and _vector_arrays_equal(
			restored_search.get("search_points", []),
			saved_awareness.get("search_points", [])
		)
		and int(restored_search.get("search_index", -1))
			== int(saved_awareness.get("search_index", -2))
		and is_equal_approx(
			float(restored_search.get(
				"search_scan_remaining_seconds",
				-1.0
			)),
			float(saved_awareness.get(
				"search_scan_remaining_seconds",
				-2.0
			))
		)
		and int(session.call(
			"get_pending_semantic_event_count"
		)) == 0,
		(
			"Phase 5.4 quickload restores the resolved search choice and remaining simulation-time stage without replaying hearing "
			+ "(mutated=%s loaded=%s state=%s remaining=%.6f/%.6f nav=%s pending=%d)"
			% [
				str(mutated_to_unaware),
				str(loaded),
				str(restored_search.get("awareness_state", &"")),
				float(restored_search.get("state_remaining_seconds", -1.0)),
				float(saved_awareness.get("state_remaining_seconds", -2.0)),
				str(restored_nav),
				int(session.call("get_pending_semantic_event_count")),
			]
		)
	)

	reaction.reset_reaction()
	light.gameplay_enabled = false
	light.visible = false
	player.global_position = Vector3(0.0, 0.0, -4.2)
	player.velocity = Vector3.ZERO
	guard.global_position = Vector3(0.0, 0.0, -5.2)
	guard.velocity = Vector3.ZERO
	guard.look_at(player.global_position, Vector3.UP, true)
	await _settle_frames(2)
	var dark_exposure_summary: Dictionary = exposure.sample_now()
	var dark_exposure: float = float(
		dark_exposure_summary.get("exposure", 1.0)
	)
	var dark_close_confirmed: bool = reaction.sample_vision_now()
	var dark_close_summary: Dictionary = reaction.get_debug_summary()
	_assert_true(
		dark_exposure <= 0.02
		and dark_close_confirmed
		and dark_close_summary.get("awareness_state", &"")
			== STATE_ALERTED
		and bool(dark_close_summary.get(
			"last_vision_darkness_override",
			false
		))
		and float(dark_close_summary.get(
			"last_vision_distance",
			INF
		)) <= float(dark_close_summary.get(
			"vision_darkness_confirm_distance",
			0.0
		))
		and float(dark_close_summary.get(
			"last_vision_facing_dot",
			-1.0
		)) >= float(dark_close_summary.get(
			"vision_darkness_confirm_facing_dot",
			1.0
		)),
		"Phase 5.4 complete darkness remains protective at range but cannot make a point-blank directly-facing player magically invisible"
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
	var lost_search_summary: Dictionary = reaction.get_debug_summary()
	var lost_search_nav: Dictionary = guard.get_awareness_navigation_state()
	var lost_points: Array = lost_search_summary.get("search_points", [])
	var lost_index: int = int(lost_search_summary.get("search_index", 0))
	var lost_current: Vector3 = (
		lost_points[lost_index]
		if lost_index >= 0 and lost_index < lost_points.size()
		else Vector3.ZERO
	)
	_assert_true(
		lost_to_search
		and bool(lost_search_nav.get("active", false))
		and lost_search_nav.get("reason", &"")
			== NAV_SEARCH
		and _dict_vector(
			lost_search_summary,
			"search_anchor"
		).distance_to(last_seen) <= 0.001
		and lost_points.size() >= 2
		and _dict_vector(
			lost_search_nav,
			"target_position"
		).distance_to(lost_current) <= 0.001,
		"Phase 5.5 confirmed-alert loss builds local search around the resolved last-seen position rather than global player knowledge"
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


func _assert_advanced_local_search_behavior() -> void:
	var application: Node = await _launch_slice()
	if application == null:
		return
	var world := application.get("current_world") as Node3D
	var session := application.get("current_session") as Node
	var player := application.get("current_player") as CharacterBody3D
	var guard := world.get_node("Guard") as VarkGuard
	var reaction := world.get_node("Guard/Reaction") as Node
	var light := world.get_node("NorthGameplayLight") as VarkGameplayLight
	var exposure := world.get_node("GameplayExposure") as VarkGameplayExposure

	reaction.hearing_investigate_strength = 0.20
	reaction.investigation_seconds = 0.06
	reaction.search_seconds = 2.00
	reaction.search_point_count = 3
	reaction.search_radius = 1.00
	reaction.search_arrival_distance = 0.30
	reaction.search_scan_seconds = 0.08
	reaction.search_scan_degrees = 55.0
	reaction.recovery_seconds = 0.08
	guard.movement_speed = 5.0
	light.gameplay_enabled = false
	light.visible = false
	player.global_position = Vector3(-4.0, 0.0, 6.0)
	player.velocity = Vector3.ZERO
	exposure.sample_now()
	reaction.reset_reaction()

	var first_origin: Vector3 = guard.global_position + Vector3(0.45, 0.0, 0.20)
	var first_queued: bool = bool(session.call(
		"queue_gameplay_sound",
		int(session.get("session_id")),
		&"prop.impact",
		first_origin,
		0.70
	))
	await _completed_physics_frame()
	var first_search: bool = await _wait_for_awareness_state(
		reaction,
		STATE_SEARCHING,
		45
	)
	var first_summary: Dictionary = reaction.get_debug_summary()
	var first_points: Array = first_summary.get("search_points", [])
	var all_reachable: bool = first_points.size() >= 2
	for point_value: Variant in first_points:
		if (
			typeof(point_value) != TYPE_VECTOR3
			or not guard.is_navigation_position_reachable(point_value)
		):
			all_reachable = false
			break
	_assert_true(
		first_queued
		and first_search
		and first_points.size() >= 2
		and all_reachable
		and _dict_vector(first_summary, "search_anchor").distance_to(
			first_origin
		) <= 0.001,
		"Phase 5.5 real Integrated Slice search resolves multiple reachable local points around evidence"
	)

	var plan_before_hidden_move: Array = (
		first_summary.get("search_points", []) as Array
	).duplicate(true)
	player.global_position = Vector3(4.0, 0.0, 6.0)
	player.velocity = Vector3.ZERO
	await _settle_frames(3)
	var after_hidden_move: Dictionary = reaction.get_debug_summary()
	_assert_true(
		after_hidden_move.get("awareness_state", &"") == STATE_SEARCHING
		and _vector_arrays_equal(
			plan_before_hidden_move,
			after_hidden_move.get("search_points", [])
		),
		"Phase 5.5 moving the hidden player cannot rewrite an already-resolved search plan"
	)

	var visited_first: bool = await _wait_for_search_visited(
		reaction,
		1,
		120
	)
	var second_origin: Vector3 = guard.global_position + Vector3(-0.35, 0.0, 0.40)
	var reseed_queued: bool = bool(session.call(
		"queue_gameplay_sound",
		int(session.get("session_id")),
		&"footstep.stone",
		second_origin,
		0.70
	))
	await _completed_physics_frame()
	var reseed_summary: Dictionary = reaction.get_debug_summary()
	var reseed_investigating: bool = (
		reseed_summary.get("awareness_state", &"") == STATE_INVESTIGATING
		and int(reseed_summary.get("search_reseed_count", 0)) >= 1
	)
	var second_search: bool = await _wait_for_awareness_state(
		reaction,
		STATE_SEARCHING,
		45
	)
	var second_summary: Dictionary = reaction.get_debug_summary()
	_assert_true(
		visited_first
		and reseed_queued
		and reseed_investigating
		and second_search
		and _dict_vector(second_summary, "search_anchor").distance_to(
			second_origin
		) <= 0.001
		and not _vector_arrays_equal(
			plan_before_hidden_move,
			second_summary.get("search_points", [])
		),
		"Phase 5.5 newly heard local evidence interrupts and reseeds search without global player knowledge"
	)

	var visited_multiple: bool = await _wait_for_search_visited(
		reaction,
		2,
		180
	)
	var reached_recovery: bool = await _wait_for_awareness_state(
		reaction,
		STATE_RECOVERING,
		180
	)
	var returned_unaware: bool = await _wait_for_awareness_state(
		reaction,
		STATE_UNAWARE,
		60
	)
	_assert_true(
		visited_multiple
		and reached_recovery
		and returned_unaware
		and not bool(
			guard.get_awareness_navigation_state().get("active", true)
		),
		"Phase 5.5 guard visits multiple local search stops, exhausts the bounded plan, recovers, and returns navigation ownership to patrol"
	)

	application.call("exit_current_world")
	application.queue_free()
	await process_frame


func _wait_for_search_visited(
	reaction: Node,
	minimum_visited: int,
	max_frames: int
) -> bool:
	for _frame: int in max_frames:
		if int(reaction.get_debug_summary().get(
			"search_points_visited",
			0
		)) >= minimum_visited:
			return true
		await _completed_physics_frame()
	return int(reaction.get_debug_summary().get(
		"search_points_visited",
		0
	)) >= minimum_visited


func _vector_arrays_equal(left_value: Variant, right_value: Variant) -> bool:
	if typeof(left_value) != TYPE_ARRAY or typeof(right_value) != TYPE_ARRAY:
		return false
	var left: Array = left_value
	var right: Array = right_value
	if left.size() != right.size():
		return false
	for index: int in left.size():
		if (
			typeof(left[index]) != TYPE_VECTOR3
			or typeof(right[index]) != TYPE_VECTOR3
			or (left[index] as Vector3).distance_to(
				right[index] as Vector3
			) > 0.001
		):
			return false
	return true


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
	reaction.search_seconds = 0.60
	reaction.search_point_count = 3
	reaction.search_radius = 0.80
	reaction.search_arrival_distance = 0.30
	reaction.search_scan_seconds = 0.05
	reaction.search_scan_degrees = 45.0
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
