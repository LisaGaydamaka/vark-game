extends SceneTree


const ApplicationScene = preload("res://application/Application.tscn")
const ObjectiveStateScript = preload(
	"res://gameplay/objectives/simple_objective_state.gd"
)
const RouteTriggerScript = preload(
	"res://gameplay/objectives/semantic_route_trigger.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _assert_objective_lab()
	_print_summary()
	quit(1 if not failures.is_empty() else 0)


func _assert_objective_lab() -> void:
	var default_application: Node = ApplicationScene.instantiate()
	var default_labels: PackedStringArray = default_application.get(
		"development_launch_labels"
	)
	var default_paths: PackedStringArray = default_application.get(
		"development_launch_resource_paths"
	)
	_assert_true(
		default_labels.has("Objective Lab")
		and default_paths.has("res://scenes/ObjectiveLab.tscn"),
		"Application Development Launch exposes the 3.10 Objective Lab"
	)
	default_application.free()

	var application: Node = ApplicationScene.instantiate()
	application.set(
		"development_launch_labels",
		PackedStringArray(["Objective Lab"])
	)
	application.set(
		"development_launch_resource_paths",
		PackedStringArray(["res://scenes/ObjectiveLab.tscn"])
	)
	get_root().add_child(application)
	await process_frame
	var launched: bool = bool(application.call("launch_development_target", 0))
	await process_frame
	await _completed_physics_frame()

	var world := application.get("current_world") as Node3D
	var player := application.get("current_player") as CharacterBody3D
	var session := application.get("current_session") as Node
	var objective_state := (
		world.get_node_or_null("ObjectiveState") as VarkSimpleObjectiveState
		if world != null
		else null
	)
	var objective_trigger := (
		world.get_node_or_null("ObjectiveTrigger") as VarkSemanticRouteTrigger
		if world != null
		else null
	)
	var exit_trigger := (
		world.get_node_or_null("ExitTrigger") as VarkSemanticRouteTrigger
		if world != null
		else null
	)
	var bonus_activate_trigger := (
		world.get_node_or_null("BonusActivateTrigger") as VarkSemanticRouteTrigger
		if world != null
		else null
	)
	var bonus_complete_trigger := (
		world.get_node_or_null("BonusCompleteTrigger") as VarkSemanticRouteTrigger
		if world != null
		else null
	)
	var status_label := (
		world.get_node_or_null("StatusLabel") as Label3D
		if world != null
		else null
	)
	_assert_true(
		launched
		and world != null
		and world.name == &"ObjectiveLab"
		and player != null
		and session != null
		and objective_state != null
		and objective_state.get_script() == ObjectiveStateScript
		and objective_trigger != null
		and objective_trigger.get_script() == RouteTriggerScript
		and exit_trigger != null
		and exit_trigger.get_script() == RouteTriggerScript
		and bonus_activate_trigger != null
		and bonus_activate_trigger.get_script() == RouteTriggerScript
		and bonus_complete_trigger != null
		and bonus_complete_trigger.get_script() == RouteTriggerScript
		and status_label != null,
		"Objective Lab launches through the production Application → WorldSession → Player path"
	)
	if (
		world == null
		or player == null
		or session == null
		or objective_state == null
		or objective_trigger == null
		or exit_trigger == null
		or bonus_activate_trigger == null
		or bonus_complete_trigger == null
		or status_label == null
	):
		application.call("exit_current_world")
		application.queue_free()
		await process_frame
		return

	var mission_completed_events: Array[Dictionary] = []
	var mission_completed_handler: Callable = func(event: Dictionary) -> bool:
		mission_completed_events.append(event.duplicate(true))
		return true
	var objective_state_events: Array[Dictionary] = []
	var objective_state_handler: Callable = func(event: Dictionary) -> bool:
		objective_state_events.append(event.duplicate(true))
		return true
	_assert_true(
		bool(session.call(
			"register_semantic_event_handler",
			&"mission.completed",
			mission_completed_handler
		)),
		"Objective proof observes mission completion through the existing semantic event bus"
	)
	_assert_true(
		bool(session.call(
			"register_semantic_event_handler",
			&"objective.state_changed",
			objective_state_handler
		)),
		"Objective proof observes active/complete/failed lifecycle changes through the existing semantic event bus"
	)

	var initial_objective: Dictionary = objective_state.query_objective(
		&"objective.route"
	)
	var initial_exit: Dictionary = objective_state.query_exit(&"exit.route")
	var initial_bonus: Dictionary = objective_state.query_objective(
		&"objective.bonus"
	)
	var initial_no_alarm: Dictionary = objective_state.query_objective(
		&"objective.no_alarm"
	)
	_assert_true(
		bool(initial_objective.get("ok", false))
		and initial_objective.get("state", &"") == &"active"
		and not bool(initial_objective.get("complete", true))
		and bool(initial_exit.get("ok", false))
		and not bool(initial_exit.get("unlocked", true))
		and not bool(initial_exit.get("mission_complete", true))
		and bool(initial_bonus.get("ok", false))
		and bool(initial_bonus.get("optional", false))
		and initial_bonus.get("state", &"") == &"inactive"
		and bool(initial_no_alarm.get("optional", false))
		and initial_no_alarm.get("state", &"") == &"active"
		and status_label.text.contains("OBJECTIVE ACTIVE")
		and status_label.text.contains("EXIT LOCKED"),
		"Objective owner exposes one active beginning state and a locked exit through public semantic queries"
	)
	_assert_true(
		not bool(objective_state.query_objective(&"objective.unknown").get("ok", true))
		and not bool(objective_state.query_exit(&"exit.unknown").get("ok", true)),
		"Objective queries fail closed for unknown semantic IDs"
	)

	var objective_trigger_summary: Dictionary = objective_trigger.get_debug_summary()
	var exit_trigger_summary: Dictionary = exit_trigger.get_debug_summary()
	var bonus_activate_summary: Dictionary = bonus_activate_trigger.get_debug_summary()
	var bonus_complete_summary: Dictionary = bonus_complete_trigger.get_debug_summary()
	_assert_true(
		objective_trigger_summary.get("event_name", &"")
			== &"objective.complete_requested"
		and objective_trigger_summary.get("payload_key", &"")
			== &"objective_id"
		and objective_trigger_summary.get("payload_id", &"")
			== &"objective.route"
		and bool(objective_trigger_summary.get("one_shot_on_queue", false))
		and exit_trigger_summary.get("event_name", &"")
			== &"mission.exit_requested"
		and exit_trigger_summary.get("payload_key", &"") == &"exit_id"
		and exit_trigger_summary.get("payload_id", &"") == &"exit.route"
		and not bool(exit_trigger_summary.get("one_shot_on_queue", true))
		and bonus_activate_summary.get("event_name", &"")
			== &"objective.activate_requested"
		and bonus_activate_summary.get("payload_id", &"")
			== &"objective.bonus"
		and bool(bonus_activate_summary.get("one_shot_on_queue", false))
		and bonus_complete_summary.get("event_name", &"")
			== &"objective.complete_requested"
		and bonus_complete_summary.get("payload_id", &"")
			== &"objective.bonus",
		"Objective/exit world triggers carry only semantic event IDs and do not read private objective, door, or NPC state"
	)

	await _move_player_to_node(player, world.get_node("ExitTrigger") as Node3D)
	var blocked_exit: Dictionary = objective_state.query_exit(&"exit.route")
	_assert_true(
		int(exit_trigger.get_debug_summary().get("queued_count", 0)) == 1
		and int(blocked_exit.get("attempt_count", 0)) == 1
		and int(blocked_exit.get("blocked_attempt_count", 0)) == 1
		and not bool(blocked_exit.get("unlocked", true))
		and not bool(blocked_exit.get("mission_complete", true))
		and mission_completed_events.is_empty()
		and status_label.text.contains("EXIT LOCKED"),
		"Trying the exit before the objective emits a semantic attempt but cannot complete the route"
	)

	var source_session_id: int = int(session.get("session_id"))
	var optional_requests_queued: bool = (
		bool(session.call(
			"queue_semantic_gameplay_event",
			source_session_id,
			&"objective.activate_requested",
			{"objective_id": &"objective.bonus"}
		))
		and bool(session.call(
			"queue_semantic_gameplay_event",
			source_session_id,
			&"objective.fail_requested",
			{"objective_id": &"objective.no_alarm"}
		))
		and bool(session.call(
			"queue_semantic_gameplay_event",
			source_session_id,
			&"objective.complete_requested",
			{"objective_id": &"objective.bonus"}
		))
	)
	var bonus_before_drain: Dictionary = objective_state.query_objective(
		&"objective.bonus"
	)
	_assert_true(
		optional_requests_queued
		and bonus_before_drain.get("state", &"") == &"inactive"
		and objective_state_events.is_empty(),
		"Dynamic/optional objective requests queue without immediate objective-state mutation"
	)
	await _completed_physics_frame()
	var bonus_after_drain: Dictionary = objective_state.query_objective(
		&"objective.bonus"
	)
	var no_alarm_after_drain: Dictionary = objective_state.query_objective(
		&"objective.no_alarm"
	)
	var optional_exit: Dictionary = objective_state.query_exit(&"exit.route")
	var state_transitions: Array[String] = []
	for state_event: Dictionary in objective_state_events:
		var state_payload: Dictionary = state_event.get("payload", {})
		state_transitions.append(
			"%s:%s>%s"
			% [
				str(state_payload.get("objective_id", &"")),
				str(state_payload.get("from_state", &"")),
				str(state_payload.get("to_state", &"")),
			]
		)
	_assert_true(
		bonus_after_drain.get("state", &"") == &"complete"
		and bool(bonus_after_drain.get("optional", false))
		and no_alarm_after_drain.get("state", &"") == &"failed"
		and bool(no_alarm_after_drain.get("optional", false))
		and not bool(optional_exit.get("unlocked", true))
		and not bool(optional_exit.get("required_failed", true))
		and state_transitions == [
			"objective.bonus:inactive>active",
			"objective.no_alarm:active>failed",
			"objective.bonus:active>complete",
		],
		"Inactive optional objectives can activate dynamically, optional objectives can complete/fail, ordered state-changed events are detached, and optional failure does not become a required-route failure"
	)

	await _move_player_to_position(player, Vector3(0.0, 0.0, -2.5))
	var objective_node := world.get_node("ObjectiveTrigger") as Node3D
	player.global_position = Vector3(
		objective_node.global_position.x,
		0.0,
		objective_node.global_position.z
	)
	player.velocity = Vector3.ZERO
	var pre_drain_objective: Dictionary = objective_state.query_objective(
		&"objective.route"
	)
	var pre_drain_trigger_count: int = int(
		objective_trigger.get_debug_summary().get("queued_count", 0)
	)
	for _frame_index: int in 3:
		await physics_frame
		await process_frame
	var completed_objective: Dictionary = objective_state.query_objective(
		&"objective.route"
	)
	var unlocked_exit: Dictionary = objective_state.query_exit(&"exit.route")
	_assert_true(
		pre_drain_trigger_count == 0
		and pre_drain_objective.get("state", &"") == &"active"
		and not bool(pre_drain_objective.get("complete", true))
		and int(objective_trigger.get_debug_summary().get("queued_count", 0)) == 1
		and not bool(objective_trigger.get_debug_summary().get("armed", true))
		and bool(completed_objective.get("complete", false))
		and completed_objective.get("state", &"") == &"complete"
		and bool(unlocked_exit.get("unlocked", false))
		and not bool(unlocked_exit.get("mission_complete", true))
		and status_label.text.contains("OBJECTIVE COMPLETE")
		and status_label.text.contains("EXIT UNLOCKED"),
		"Crossing the objective marker changes authoritative objective truth only after its semantic event drains"
	)

	await _move_player_to_position(player, Vector3(0.0, 0.0, -2.5))
	await _move_player_to_node(player, world.get_node("ExitTrigger") as Node3D)
	var finished_exit: Dictionary = objective_state.query_exit(&"exit.route")
	var finished_summary: Dictionary = objective_state.get_debug_summary()
	var completion_payload: Dictionary = {}
	if mission_completed_events.size() == 1:
		completion_payload = mission_completed_events[0].get("payload", {})
	_assert_true(
		int(exit_trigger.get_debug_summary().get("queued_count", 0)) == 2
		and int(finished_exit.get("attempt_count", 0)) == 2
		and int(finished_exit.get("blocked_attempt_count", 0)) == 1
		and bool(finished_exit.get("unlocked", false))
		and bool(finished_exit.get("mission_complete", false))
		and int(finished_summary.get("objective_completion_count", 0)) == 1
		and int(finished_summary.get("mission_completion_count", 0)) == 1
		and mission_completed_events.size() == 1
		and completion_payload.get("objective_id", &"") == &"objective.route"
		and completion_payload.get("exit_id", &"") == &"exit.route"
		and status_label.text.contains("ROUTE COMPLETE"),
		"Completing the objective then entering the exit ends the route and emits exactly one detached mission.completed semantic fact"
	)

	await _move_player_to_position(player, Vector3(0.0, 0.0, -2.5))
	await _move_player_to_node(player, world.get_node("ExitTrigger") as Node3D)
	var repeated_exit: Dictionary = objective_state.query_exit(&"exit.route")
	_assert_true(
		int(exit_trigger.get_debug_summary().get("queued_count", 0)) == 3
		and int(repeated_exit.get("attempt_count", 0)) == 3
		and bool(repeated_exit.get("mission_complete", false))
		and mission_completed_events.size() == 1
		and int(objective_state.get_debug_summary().get(
			"mission_completion_count",
			0
		)) == 1,
		"Repeated exit attempts after completion are idempotent and do not duplicate mission completion"
	)

	session.call(
		"unregister_semantic_event_handler",
		&"mission.completed",
		mission_completed_handler
	)
	session.call(
		"unregister_semantic_event_handler",
		&"objective.state_changed",
		objective_state_handler
	)
	application.call("exit_current_world")
	application.queue_free()
	await process_frame


func _move_player_to_node(
	player: CharacterBody3D,
	target: Node3D
) -> void:
	await _move_player_to_position(
		player,
		Vector3(target.global_position.x, 0.0, target.global_position.z)
	)


func _move_player_to_position(
	player: CharacterBody3D,
	position: Vector3
) -> void:
	player.global_position = position
	player.velocity = Vector3.ZERO
	for _frame_index: int in 3:
		await physics_frame
		await process_frame


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
		print("ALL OBJECTIVE TESTS PASSED")
		return
	print("%d OBJECTIVE TEST(S) FAILED" % failures.size())
	for failure: String in failures:
		print(" - ", failure)
