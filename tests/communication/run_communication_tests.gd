extends SceneTree


const ApplicationScene = preload("res://application/Application.tscn")
const WorldSession = preload("res://application/world_session.gd")
const COMMUNICATION_LAB_PATH: String = "res://missions/communication_lab/world.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _assert_local_warning_and_alarm_knowledge()
	_print_summary()
	quit(1 if not failures.is_empty() else 0)


func _assert_local_warning_and_alarm_knowledge() -> void:
	var application: Node = ApplicationScene.instantiate()
	application.set(
		"development_launch_labels",
		PackedStringArray(["Communication Lab"])
	)
	application.set(
		"development_launch_resource_paths",
		PackedStringArray([COMMUNICATION_LAB_PATH])
	)
	get_root().add_child(application)
	await process_frame

	var launched: bool = bool(application.call("launch_development_target", 0))
	var world := application.get("current_world") as Node3D
	var session := application.get("current_session") as Node
	var ready: bool = await _wait_for_lab_ready(world, 480)
	var reporter := world.get_node_or_null("Guard") as VarkGuard if world != null else null
	var receiver := world.get_node_or_null("ReceiverGuard") as VarkGuard if world != null else null
	var reporter_reaction: Node = (
		world.get_node_or_null("Guard/Reaction") if world != null else null
	)
	var receiver_reaction: Node = (
		world.get_node_or_null("ReceiverGuard/Reaction") if world != null else null
	)
	var reporter_comm := (
		world.get_node_or_null("ReporterCommunication") as VarkGuardCommunication
		if world != null else null
	)
	var receiver_comm := (
		world.get_node_or_null("ReceiverCommunication") as VarkGuardCommunication
		if world != null else null
	)
	var alarm := (
		world.get_node_or_null("BuildingAlarm") as VarkAlarmChannel
		if world != null else null
	)
	var door := (
		world.get_node_or_null("OrdinaryDoor") as VarkOrdinaryDoor
		if world != null else null
	)
	var player := application.get("current_player") as CharacterBody3D

	_assert_true(
		launched
		and ready
		and session != null
		and reporter != null
		and receiver != null
		and reporter_reaction != null
		and receiver_reaction != null
		and reporter_comm != null
		and receiver_comm != null
		and alarm != null
		and door != null
		and player != null
		and bool(reporter_comm.get_debug_summary().get("configured", false))
		and bool(receiver_comm.get_debug_summary().get("configured", false)),
		"5.6 Communication Lab launches two real configured guards, acoustic warning owners, and an explicit alarm channel"
	)
	if (
		not ready
		or session == null
		or reporter == null
		or receiver == null
		or reporter_reaction == null
		or receiver_reaction == null
		or reporter_comm == null
		or receiver_comm == null
		or alarm == null
		or player == null
	):
		await _cleanup(application)
		return

	# Keep the proof about communication rather than incidental live perception.
	reporter.set_physics_process(false)
	receiver.set_physics_process(false)
	reporter_reaction.set_physics_process(false)
	receiver_reaction.set_physics_process(false)

	var observed_warnings: Array[Dictionary] = []
	var warning_observer: Callable = func(event: Dictionary) -> bool:
		observed_warnings.append(event.duplicate(true))
		return true
	_assert_true(
		bool(session.call(
			"register_semantic_event_handler",
			VarkGuardCommunication.LOCAL_WARNING_EVENT_NAME,
			warning_observer
		)),
		"5.6 test observer registers through the real semantic event boundary"
	)

	var evidence := Vector3(1.4, 0.0, 1.2)
	receiver.global_position = Vector3(-2.6, 0.0, -4.8)
	reporter_reaction.call("reset_reaction")
	receiver_reaction.call("reset_reaction")
	reporter_reaction.call("_advance_visual_suspicion", 1.0, 1.0, evidence)
	await _completed_physics_frame()
	var blocked_summary: Dictionary = receiver_reaction.call("get_debug_summary")
	var blocked_comm: Dictionary = receiver_comm.get_debug_summary()
	var first_warning_payload: Dictionary = (
		observed_warnings[0].get("payload", {})
		if observed_warnings.size() >= 1
		else {}
	)
	_assert_true(
		observed_warnings.size() == 1
		and first_warning_payload.size() == 5
		and first_warning_payload.get("reporter_actor_id", "") == "guard.slice"
		and first_warning_payload.get("faction_id", &"") == &"guards"
		and first_warning_payload.get("evidence_position", Vector3.ZERO) == evidence
		and not first_warning_payload.has("player_position")
		and blocked_summary.get("awareness_state", &"") == &"unaware"
		and bool(blocked_comm.get("last_warning_route_found", false))
		and float(blocked_comm.get("last_warning_propagated_strength", 1.0)) < 0.16,
		"5.6 confirmed local sight emits one explicit evidence report, but a closed-door acoustically weak warning does not grant the other guard knowledge"
	)

	# Continued confirmed sight must not spam warning reports every vision sample.
	reporter_reaction.call("_advance_visual_suspicion", 1.0, 1.0, evidence)
	await _completed_physics_frame()
	_assert_true(
		observed_warnings.size() == 1
		and int(reporter_comm.get_debug_summary().get("warnings_sent", 0)) == 1,
		"5.6 one confirmed-alert transition sends one local warning instead of rebroadcasting every visible frame"
	)

	# A nearby wrong-faction guard receives the semantic event but must ignore it.
	reporter_reaction.call("reset_reaction")
	receiver_reaction.call("reset_reaction")
	receiver.global_position = reporter.global_position + Vector3(-1.0, 0.0, 0.0)
	receiver_comm.faction_id = &"other"
	reporter_reaction.call("_advance_visual_suspicion", 1.0, 1.0, evidence)
	await _completed_physics_frame()
	_assert_true(
		receiver_reaction.call("get_debug_summary").get(
			"awareness_state",
			&""
		) == &"unaware",
		"5.6 local warnings do not cross explicit faction relevance"
	)

	# Same faction + physically audible warning transfers only the reported point.
	reporter_reaction.call("reset_reaction")
	receiver_reaction.call("reset_reaction")
	receiver_comm.faction_id = &"guards"
	var warned_evidence := Vector3(0.9, 0.0, 0.7)
	reporter_reaction.call(
		"_advance_visual_suspicion",
		1.0,
		1.0,
		warned_evidence
	)
	await _completed_physics_frame()
	var warned_summary: Dictionary = receiver_reaction.call("get_debug_summary")
	var warned_comm: Dictionary = receiver_comm.get_debug_summary()
	player.global_position = Vector3(-3.5, 0.0, 6.0)
	await _completed_physics_frame()
	var after_player_move: Dictionary = receiver_reaction.call("get_debug_summary")
	_assert_true(
		warned_summary.get("awareness_state", &"") == &"investigating"
		and warned_summary.get("investigation_target", Vector3.ZERO) == warned_evidence
		and int(warned_comm.get("warnings_received", 0)) == 1
		and warned_comm.get("last_report_kind", &"") == &"warning"
		and warned_comm.get("last_report_source_actor_id", "") == "guard.slice"
		and after_player_move.get("investigation_target", Vector3.ZERO)
			== warned_evidence,
		"5.6 an acoustically audible same-faction warning creates second-hand investigation at the reported evidence position, not hidden current-player tracking"
	)

	# Alarm propagation is explicit and subscription-scoped rather than automatic.
	receiver_reaction.call("reset_reaction")
	receiver.global_position = Vector3(-2.6, 0.0, -4.8)
	receiver_comm.alarm_channels = PackedStringArray()
	var ignored_alarm_evidence := Vector3(2.0, 0.0, -2.0)
	var ignored_alarm_queued: bool = alarm.raise_alarm(
		ignored_alarm_evidence,
		"guard.slice"
	)
	await _completed_physics_frame()
	_assert_true(
		ignored_alarm_queued
		and receiver_reaction.call("get_debug_summary").get(
			"awareness_state",
			&""
		) == &"unaware",
		"5.6 an explicit alarm reaches only guards subscribed to its authored channel"
	)

	receiver_comm.alarm_channels = PackedStringArray(["building.main"])
	var alarm_evidence := Vector3(2.4, 0.0, -3.1)
	var alarm_queued: bool = alarm.raise_alarm(alarm_evidence, "guard.slice")
	await _completed_physics_frame()
	var alarm_summary: Dictionary = receiver_reaction.call("get_debug_summary")
	var alarm_comm: Dictionary = receiver_comm.get_debug_summary()
	var alarm_state: Dictionary = alarm.get_debug_summary()
	_assert_true(
		alarm_queued
		and alarm_summary.get("awareness_state", &"") == &"searching"
		and alarm_summary.get("search_anchor", Vector3.ZERO) == alarm_evidence
		and int(alarm_comm.get("alarms_received", 0)) == 1
		and alarm_comm.get("last_report_kind", &"") == &"alarm"
		and bool(alarm_state.get("active", false))
		and alarm_state.get("evidence_position", Vector3.ZERO) == alarm_evidence
		and int(alarm_state.get("raise_serial", 0)) == 2,
		"5.6 an authored alarm deliberately widens knowledge to subscribed guards but still carries only an explicit last-known evidence position"
	)

	# Save/load must preserve resulting knowledge and active alarm state without
	# replaying either warning or alarm as a new gameplay consequence.
	var coordinator: Node = application.get_node("SaveCoordinator")
	var generation: int = int(application.call("request_quicksave"))
	var committed: bool = await _wait_for_save_status(
		coordinator,
		generation,
		&"committed",
		60
	)
	var old_world_instance_id: int = world.get_instance_id()
	var loaded: bool = bool(application.call("quickload_latest"))
	var replacement_ready: bool = await _wait_for_replacement_world(
		application,
		old_world_instance_id,
		240
	)
	var restored_world := application.get("current_world") as Node3D
	var restored_session := application.get("current_session") as Node
	var restored_alarm := (
		restored_world.get_node_or_null("BuildingAlarm") as VarkAlarmChannel
		if restored_world != null else null
	)
	var restored_reaction: Node = (
		restored_world.get_node_or_null("ReceiverGuard/Reaction")
		if restored_world != null else null
	)
	var restored_comm := (
		restored_world.get_node_or_null(
			"ReceiverCommunication"
		) as VarkGuardCommunication
		if restored_world != null else null
	)
	if restored_reaction != null:
		restored_reaction.set_physics_process(false)
	await _completed_physics_frame()
	var restored_alarm_summary: Dictionary = (
		restored_alarm.get_debug_summary() if restored_alarm != null else {}
	)
	var restored_awareness_summary: Dictionary = (
		restored_reaction.call("get_debug_summary")
		if restored_reaction != null else {}
	)
	var restored_comm_summary: Dictionary = (
		restored_comm.get_debug_summary() if restored_comm != null else {}
	)
	_assert_true(
		committed
		and loaded
		and replacement_ready
		and restored_world != null
		and restored_world.get_instance_id() != old_world_instance_id
		and restored_session != null
		and restored_alarm != null
		and restored_reaction != null
		and restored_comm != null
		and bool(restored_alarm_summary.get("active", false))
		and restored_alarm_summary.get("evidence_position", Vector3.ZERO)
			== alarm_evidence
		and int(restored_alarm_summary.get("raise_serial", 0)) == 2
		and restored_awareness_summary.get("awareness_state", &"")
			== &"searching"
		and restored_awareness_summary.get("search_anchor", Vector3.ZERO)
			== alarm_evidence
		and int(restored_comm_summary.get("warnings_received", -1)) == 0
		and int(restored_comm_summary.get("alarms_received", -1)) == 0
		and int(restored_session.call("get_pending_semantic_event_count")) == 0,
		"5.6 save/load restores active alarm plus second-hand search knowledge without replaying communication consequences"
	)

	await _cleanup(application)


func _wait_for_lab_ready(world: Node3D, max_frames: int) -> bool:
	if world == null:
		return false
	for _index: int in max_frames:
		var receiver := world.get_node_or_null("ReceiverGuard") as VarkGuard
		if (
			bool(world.get("navigation_ready"))
			and receiver != null
			and bool(receiver.get_debug_summary().get("configured", false))
		):
			return true
		await physics_frame
		await process_frame
	return false


func _wait_for_save_status(
	coordinator: Node,
	generation: int,
	target_status: StringName,
	max_frames: int
) -> bool:
	for _index: int in max_frames:
		var status: Dictionary = coordinator.call(
			"get_request_status",
			generation
		)
		if status.get("status", &"") == target_status:
			return true
		if status.get("status", &"") in [
			&"cancelled",
			&"failed",
			&"superseded",
		]:
			return false
		await physics_frame
		await process_frame
	return false


func _wait_for_replacement_world(
	application: Node,
	old_world_instance_id: int,
	max_frames: int
) -> bool:
	for _index: int in max_frames:
		var world: Node = application.get("current_world")
		var session: Node = application.get("current_session")
		if (
			world != null
			and world.get_instance_id() != old_world_instance_id
			and session != null
			and int(session.get("state")) == WorldSession.State.PLAYING
			and bool(world.get("navigation_ready"))
		):
			var receiver := world.get_node_or_null("ReceiverGuard") as VarkGuard
			if (
				receiver != null
				and bool(receiver.get_debug_summary().get("configured", false))
			):
				return true
		await physics_frame
		await process_frame
	return false


func _completed_physics_frame() -> void:
	await physics_frame
	await process_frame


func _cleanup(application: Node) -> void:
	if application == null or not is_instance_valid(application):
		return
	application.call("exit_current_world")
	application.queue_free()
	await process_frame


func _assert_true(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
		return
	failures.append(label)
	push_error("FAIL: %s" % label)


func _print_summary() -> void:
	print("")
	print("==============================")
	if failures.is_empty():
		print("ALL COMMUNICATION TESTS PASSED")
		return
	print("%d COMMUNICATION TEST(S) FAILED" % failures.size())
	for failure: String in failures:
		print(" - ", failure)
