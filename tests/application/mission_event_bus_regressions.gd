extends RefCounted


const WorldSession = preload("res://application/world_session.gd")
const MissionEventBus = preload("res://missions/mission_event_bus.gd")
const TEST_WORLD: PackedScene = preload("res://scenes/VarkTest.tscn")


func run(tree: SceneTree, assert_true: Callable) -> void:
	var session: Node = WorldSession.new()
	session.name = "MissionEventBusWorldSession"
	tree.get_root().add_child(session)
	var source_session_id: int = 71001
	var built: bool = bool(session.call("build", source_session_id, TEST_WORLD))
	var bus: RefCounted = (
		session.call("get_mission_event_bus") as RefCounted
		if built
		else null
	)
	assert_true.call(
		built
		and bus != null
		and bool(bus.call("is_active"))
		and int(session.get("state")) == WorldSession.State.READY,
		"7.1 WorldSession owns one active author-facing mission event bus for the current world lifetime"
	)
	if not built or bus == null:
		session.queue_free()
		await tree.process_frame
		return

	var known: PackedStringArray = bus.call("get_known_event_names")
	assert_true.call(
		known.has(str(MissionEventBus.GAMEPLAY_SOUND))
		and known.has(str(MissionEventBus.PICKUP_COLLECTED))
		and known.has(str(MissionEventBus.DOOR_STATE_CHANGED))
		and known.has(str(MissionEventBus.DOOR_ACCESS_DENIED))
		and known.has(str(MissionEventBus.LIGHT_STATE_CHANGED))
		and known.has(str(MissionEventBus.BREAKABLE_BROKEN))
		and known.has(str(MissionEventBus.NPC_ALARM_RAISED))
		and known.has(str(MissionEventBus.OBJECTIVE_COMPLETE_REQUESTED))
		and known.has(str(MissionEventBus.MISSION_COMPLETED)),
		"7.1 author-facing vocabulary exposes useful proven gameplay facts without private subsystem signals"
	)

	var observed: Array[Dictionary] = []
	var author_handler: Callable = func(event: Dictionary) -> bool:
		observed.append(event.duplicate(true))
		var payload: Dictionary = event.get("payload", {})
		var nested: Dictionary = payload.get("nested", {})
		nested["value"] = 999
		return true
	assert_true.call(
		bool(bus.call("subscribe", &"mission.author_probe", author_handler)),
		"7.1 authors can subscribe a synchronous handler before PLAYING begins"
	)
	assert_true.call(
		not bool(bus.call("emit", &"mission.author_probe", {"nested": {"value": 1}})),
		"7.1 author emission obeys existing lifecycle gating and cannot dispatch while the world is only READY"
	)
	assert_true.call(
		bool(session.call("begin_play")),
		"7.1 mission-event fixture enters PLAYING through normal WorldSession ownership"
	)

	var source_payload: Dictionary = {"nested": {"value": 7}, "label": "author"}
	var serial_before: int = int(session.call("get_stable_gameplay_boundary_serial"))
	assert_true.call(
		bool(bus.call("emit", &"mission.author_probe", source_payload))
		and observed.is_empty()
		and int(session.call("get_pending_semantic_event_count")) == 1
		and int(session.call("get_stable_gameplay_boundary_serial")) == serial_before,
		"7.1 author emission queues detached semantic work without immediate durable consequence dispatch"
	)
	(source_payload["nested"] as Dictionary)["value"] = 55
	await _settle(tree)

	var observed_payload: Dictionary = (
		observed[0].get("payload", {})
		if observed.size() == 1
		else {}
	)
	var observed_nested: Dictionary = observed_payload.get("nested", {})
	var trace: Array[Dictionary] = bus.call("get_recent_trace")
	var trace_entry: Dictionary = trace.back() if not trace.is_empty() else {}
	var trace_payload: Dictionary = trace_entry.get("payload", {})
	var trace_nested: Dictionary = trace_payload.get("nested", {})
	assert_true.call(
		observed.size() == 1
		and observed_nested.get("value", -1) == 7
		and int(session.call("get_stable_gameplay_boundary_serial")) == serial_before + 1
		and trace_entry.get("name", &"") == &"mission.author_probe"
		and int(trace_entry.get("handler_count", -1)) == 1
		and int(trace_entry.get("boundary_serial", 0)) == serial_before + 1
		and trace_nested.get("value", -1) == 7,
		"7.1 author-facing trace records detached payload, handler count, sequence scope, and the stable-boundary pass that processed the event"
	)

	var ordering: Array[String] = []
	var root_first: Callable = func(_event: Dictionary) -> bool:
		ordering.append("root:first")
		return bool(bus.call("emit", &"mission.child", {"step": 2}))
	var root_second: Callable = func(_event: Dictionary) -> bool:
		ordering.append("root:second")
		return true
	var child: Callable = func(_event: Dictionary) -> bool:
		ordering.append("child")
		return true
	assert_true.call(
		bool(bus.call("subscribe", &"mission.root", root_first))
		and bool(bus.call("subscribe", &"mission.root", root_second))
		and bool(bus.call("subscribe", &"mission.child", child))
		and bool(bus.call("emit", &"mission.root", {"step": 1})),
		"7.1 author-facing bus accepts mission-defined event names without inventing a second dispatcher"
	)
	await _settle(tree)
	assert_true.call(
		ordering == ["root:first", "root:second", "child"],
		"7.1 author-facing nested emission preserves existing FIFO/re-entrant append semantics"
	)
	assert_true.call(
		not bool(bus.call("emit", &"mission.invalid", {"node": session})),
		"7.1 author-facing payloads fail closed on live Object references"
	)

	var trace_before_teardown: Array[Dictionary] = bus.call("get_recent_trace")
	assert_true.call(
		not trace_before_teardown.is_empty()
		and trace_before_teardown.size() <= WorldSession.SEMANTIC_EVENT_TRACE_LIMIT,
		"7.1 bounded recent trace is available for mission-logic diagnostics without unbounded history growth"
	)

	session.call("teardown")
	assert_true.call(
		not bool(bus.call("is_active"))
		and not bool(bus.call("emit", &"mission.stale", {}))
		and not bool(bus.call("subscribe", &"mission.stale", author_handler))
		and (bus.call("get_recent_trace") as Array).is_empty(),
		"7.1 a retained old-world bus is invalid after teardown and cannot affect a replacement world"
	)

	var replacement_id: int = source_session_id + 1
	var replacement_built: bool = bool(session.call(
		"build",
		replacement_id,
		TEST_WORLD
	))
	var replacement_bus: RefCounted = (
		session.call("get_mission_event_bus") as RefCounted
		if replacement_built
		else null
	)
	var replacement_log: Array[String] = []
	var replacement_handler: Callable = func(_event: Dictionary) -> bool:
		replacement_log.append("replacement")
		return true
	assert_true.call(
		replacement_built
		and replacement_bus != null
		and replacement_bus != bus
		and bool(replacement_bus.call("is_active"))
		and bool(replacement_bus.call(
			"subscribe",
			&"mission.replacement",
			replacement_handler
		))
		and bool(session.call("begin_play"))
		and bool(replacement_bus.call(
			"emit",
			&"mission.replacement",
			{"world": "replacement"}
		)),
		"7.1 replacement WorldSession lifetime gets a fresh author-facing bus"
	)
	await _settle(tree)
	assert_true.call(
		replacement_log == ["replacement"]
		and not bool(bus.call("emit", &"mission.replacement", {})),
		"7.1 stale bus references cannot leak semantic work into the fresh replacement lifetime"
	)

	session.call("teardown")
	session.queue_free()
	await tree.process_frame


func _settle(tree: SceneTree) -> void:
	await tree.physics_frame
	await tree.process_frame
