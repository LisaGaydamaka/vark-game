extends SceneTree


const ApplicationScene = preload("res://application/Application.tscn")
const WorldSession = preload("res://application/world_session.gd")
const GuardScript = preload("res://gameplay/npc/vark_guard.gd")

const GUARD_NAV_DEFINITION_PATH: String = "res://missions/guard_nav_lab/mission.tres"
const GUARD_PERSISTENT_ID: String = "vark_guard_nav_guard"
const GUARD_CONTENT_ID: String = "guard.nav_probe"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _assert_actor_life_state_compatibility()
	_print_summary()
	quit(1 if not failures.is_empty() else 0)


func _assert_actor_life_state_compatibility() -> void:
	var application: Node = ApplicationScene.instantiate()
	application.set(
		"development_launch_labels",
		PackedStringArray(["Guard/Nav Lab"])
	)
	application.set(
		"development_launch_resource_paths",
		PackedStringArray([GUARD_NAV_DEFINITION_PATH])
	)
	get_root().add_child(application)
	await process_frame

	var launched: bool = bool(application.call("launch_development_target", 0))
	var world := application.get("current_world") as Node3D
	var session := application.get("current_session") as Node
	var ready: bool = await _wait_for_navigation_ready(world, 240)
	var persistent_lookup: Dictionary = (
		session.call("lookup_persistent_entity", GUARD_PERSISTENT_ID)
		if session != null
		else {}
	)
	var content_lookup: Dictionary = (
		session.call("lookup_content_entity", GUARD_CONTENT_ID)
		if session != null
		else {}
	)
	var guard := persistent_lookup.get("node") as VarkGuard
	var content_guard := content_lookup.get("node") as VarkGuard
	var navigation_agent := (
		guard.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
		if guard != null
		else null
	)

	_assert_true(
		launched
		and ready
		and session != null
		and world != null
		and guard != null
		and guard.get_script() == GuardScript
		and content_guard == guard
		and guard.get_persistent_id() == GUARD_PERSISTENT_ID
		and guard.get_content_id() == GUARD_CONTENT_ID
		and guard.guard_id == GUARD_CONTENT_ID
		and navigation_agent != null,
		"3.11 uses the real Guard/Nav actor as one registry-addressable persistent actor root"
	)
	if (
		not ready
		or session == null
		or guard == null
		or navigation_agent == null
	):
		application.call("exit_current_world")
		application.queue_free()
		await process_frame
		return

	var initial_state: Dictionary = guard.query_actor_state()
	var initial_summary: Dictionary = guard.get_debug_summary()
	var guard_start_position: Vector3 = guard.global_position
	for _frame_index: int in 12:
		await physics_frame
		await process_frame
	var moving_position: Vector3 = guard.global_position
	_assert_true(
		initial_state.get("life_state", &"") == &"conscious"
		and bool(initial_state.get("conscious", false))
		and bool(initial_state.get("awareness_eligible", false))
		and bool(initial_state.get("navigation_owned", false))
		and bool(initial_state.get("navigation_active", false))
		and not bool(initial_state.get("body_state", true))
		and bool(initial_summary.get("configured", false))
		and guard_start_position.distance_to(moving_position) > 0.02,
		"Conscious actor keeps existing navigation ownership active before any life-state mutation"
	)

	var changed_events: Array[Dictionary] = []
	var changed_handler: Callable = func(event: Dictionary) -> bool:
		changed_events.append(event.duplicate(true))
		return true
	_assert_true(
		bool(session.call(
			"register_semantic_event_handler",
			&"actor.life_state_changed",
			changed_handler
		)),
		"Actor life-state changes are observable through the existing semantic event bus"
	)

	var conscious_snapshot: Dictionary = guard.capture_semantic_state()
	var illegal_playing_snapshot: Dictionary = conscious_snapshot.duplicate(true)
	illegal_playing_snapshot["life_state"] = &"dead"
	_assert_true(
		not guard.apply_semantic_state(illegal_playing_snapshot)
		and guard.get_life_state() == &"conscious",
		"Restore-style actor state application is rejected while ordinary gameplay is PLAYING"
	)

	var unconscious_requested: bool = guard.request_life_state(&"unconscious")
	var pre_unconscious: Dictionary = guard.query_actor_state()
	_assert_true(
		unconscious_requested
		and pre_unconscious.get("life_state", &"") == &"conscious"
		and changed_events.is_empty(),
		"Gameplay life-state request queues without mutating actor truth before the stable consequence pass"
	)
	await _completed_physics_frame()

	var unconscious_state: Dictionary = guard.query_actor_state()
	var unconscious_lookup: Dictionary = session.call(
		"lookup_persistent_entity",
		GUARD_PERSISTENT_ID
	)
	var unconscious_agent := guard.get_node("NavigationAgent3D") as NavigationAgent3D
	var unconscious_event_payload: Dictionary = (
		changed_events[0].get("payload", {})
		if changed_events.size() == 1
		else {}
	)
	_assert_true(
		unconscious_state.get("life_state", &"") == &"unconscious"
		and not bool(unconscious_state.get("conscious", true))
		and not bool(unconscious_state.get("awareness_eligible", true))
		and bool(unconscious_state.get("navigation_owned", false))
		and not bool(unconscious_state.get("navigation_active", true))
		and bool(unconscious_state.get("body_state", false))
		and unconscious_lookup.get("node") == guard
		and unconscious_agent == navigation_agent
		and changed_events.size() == 1
		and unconscious_event_payload.get("persistent_id", "") == GUARD_PERSISTENT_ID
		and unconscious_event_payload.get("actor_id", "") == GUARD_CONTENT_ID
		and unconscious_event_payload.get("from_state", &"") == &"conscious"
		and unconscious_event_payload.get("to_state", &"") == &"unconscious",
		"Unconscious state gates awareness/navigation activity while preserving actor identity, collision root, navigation owner, and semantic reference"
	)

	var unconscious_rest_position: Vector3 = guard.global_position
	for _frame_index: int in 20:
		await physics_frame
		await process_frame
	_assert_true(
		guard.global_position.distance_to(unconscious_rest_position) < 0.005
		and guard.velocity.length() < 0.001,
		"Unconscious actor stops patrol locomotion without destroying or reconfiguring its navigation owner"
	)

	var unconscious_snapshot: Dictionary = guard.capture_semantic_state()
	var restore_unconscious_snapshot: Dictionary = unconscious_snapshot.duplicate(true)
	unconscious_snapshot["life_state"] = &"conscious"
	_assert_true(
		guard.get_life_state() == &"unconscious"
		and restore_unconscious_snapshot.get("life_state", &"") == &"unconscious",
		"Captured actor life state is detached value data rather than shared mutable runtime state"
	)

	var externally_moved_position: Vector3 = guard.global_position + Vector3(0.45, 0.0, 0.0)
	guard.global_position = externally_moved_position
	for _frame_index: int in 3:
		await physics_frame
		await process_frame
	var moved_lookup: Dictionary = session.call(
		"lookup_persistent_entity",
		GUARD_PERSISTENT_ID
	)
	_assert_true(
		guard.global_position.distance_to(externally_moved_position) < 0.005
		and moved_lookup.get("node") == guard
		and guard.get_life_state() == &"unconscious",
		"Non-conscious body-compatible world movement does not create a corpse identity or lose the actor registry reference"
	)

	_assert_true(
		not guard.request_life_state(&"conscious")
		and guard.get_life_state() == &"unconscious",
		"Ordinary gameplay cannot wake or resurrect an actor through the monotonic Phase 3.11 life-state request seam"
	)

	var dead_requested: bool = guard.request_life_state(&"dead")
	var pre_dead: Dictionary = guard.query_actor_state()
	_assert_true(
		dead_requested
		and pre_dead.get("life_state", &"") == &"unconscious"
		and changed_events.size() == 1,
		"Dead transition also waits for the controlled semantic consequence pass"
	)
	await _completed_physics_frame()

	var dead_state: Dictionary = guard.query_actor_state()
	var dead_lookup: Dictionary = session.call(
		"lookup_content_entity",
		GUARD_CONTENT_ID
	)
	var dead_agent := guard.get_node("NavigationAgent3D") as NavigationAgent3D
	var dead_event_payload: Dictionary = (
		changed_events[1].get("payload", {})
		if changed_events.size() == 2
		else {}
	)
	_assert_true(
		dead_state.get("life_state", &"") == &"dead"
		and not bool(dead_state.get("awareness_eligible", true))
		and bool(dead_state.get("navigation_owned", false))
		and not bool(dead_state.get("navigation_active", true))
		and bool(dead_state.get("body_state", false))
		and dead_lookup.get("node") == guard
		and dead_agent == navigation_agent
		and changed_events.size() == 2
		and dead_event_payload.get("from_state", &"") == &"unconscious"
		and dead_event_payload.get("to_state", &"") == &"dead",
		"Dead state remains the same persistent semantic actor and preserves existing navigation/body ownership for future body behavior"
	)

	var dead_snapshot: Dictionary = guard.capture_semantic_state()
	var stopped: bool = bool(application.call("stop_current_world"))
	var event_count_before_restore: int = changed_events.size()
	var restored_unconscious: bool = guard.apply_semantic_state(
		restore_unconscious_snapshot
	)
	var restored_unconscious_state: Dictionary = guard.query_actor_state()
	var wrong_identity_snapshot: Dictionary = dead_snapshot.duplicate(true)
	wrong_identity_snapshot["persistent_id"] = "wrong-actor"
	var wrong_identity_rejected: bool = not guard.apply_semantic_state(
		wrong_identity_snapshot
	)
	var restored_dead: bool = guard.apply_semantic_state(dead_snapshot)
	var restored_dead_state: Dictionary = guard.query_actor_state()
	var restored_lookup: Dictionary = session.call(
		"lookup_persistent_entity",
		GUARD_PERSISTENT_ID
	)
	_assert_true(
		stopped
		and int(session.get("state")) == WorldSession.State.STOPPED
		and restored_unconscious
		and restored_unconscious_state.get("life_state", &"") == &"unconscious"
		and wrong_identity_rejected
		and restored_dead
		and restored_dead_state.get("life_state", &"") == &"dead"
		and restored_lookup.get("node") == guard
		and guard.get_node("NavigationAgent3D") == navigation_agent
		and changed_events.size() == event_count_before_restore,
		"Quiet non-playing restore application can reconstruct valid saved life state on the same actor without emitting gameplay consequences or accepting another actor's snapshot"
	)

	session.call(
		"unregister_semantic_event_handler",
		&"actor.life_state_changed",
		changed_handler
	)
	application.call("exit_current_world")
	application.queue_free()
	await process_frame


func _wait_for_navigation_ready(world: Node, max_frames: int) -> bool:
	if world == null:
		return false
	for _frame_index: int in max_frames:
		if bool(world.get("navigation_ready")):
			return true
		await physics_frame
		await process_frame
	return bool(world.get("navigation_ready"))


func _completed_physics_frame() -> void:
	await physics_frame
	await process_frame


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
		print("ALL ACTOR TESTS PASSED")
		return
	print("%d ACTOR TEST(S) FAILED" % failures.size())
	for failure: String in failures:
		print(" - ", failure)
