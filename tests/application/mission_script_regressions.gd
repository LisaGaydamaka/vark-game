extends RefCounted


signal command_probe


const WorldSession = preload("res://application/world_session.gd")
const MissionDefinition = preload("res://missions/mission_definition.gd")
const MissionFacts = preload("res://missions/mission_facts.gd")
const MissionScript = preload("res://missions/mission_script.gd")
const PLAYGROUND_DEFINITION: Resource = preload("res://missions/playground/mission.tres")
const OBJECTIVE_LAB: PackedScene = preload("res://scenes/ObjectiveLab.tscn")


class ProcessFactProbe:
	extends Node

	signal command_issued

	var api: RefCounted = null
	var queued: bool = false
	var immediate_value: Variant = null
	var fired: bool = false

	func configure(script_api: RefCounted) -> void:
		api = script_api

	func _process(_delta: float) -> void:
		if fired or api == null:
			return
		fired = true
		queued = bool(api.call("set_fact", &"script_flag", true))
		immediate_value = api.call("get_fact", &"script_flag", null)
		set_process(false)
		command_issued.emit()


func run(tree: SceneTree, assert_true: Callable) -> void:
	var definition: Resource = _make_definition()
	var session: Node = WorldSession.new()
	session.name = "MissionScriptWorldSession"
	tree.get_root().add_child(session)
	var source_session_id: int = 75001
	var built: bool = bool(session.call(
		"build",
		source_session_id,
		definition.get("world_scene"),
		definition
	))
	var api: RefCounted = (
		session.call("get_mission_script") as RefCounted
		if built
		else null
	)
	var bus: RefCounted = (
		api.call("get_event_bus") as RefCounted
		if api != null
		else null
	)
	var world := session.get("world") as Node
	var initial_fact: Dictionary = (
		api.call("query_fact", &"script_flag")
		if api != null
		else {}
	)
	assert_true.call(
		built
		and api != null
		and bool(api.call("is_active"))
		and bus != null
		and world != null
		and MissionScript.resolve(world) == api
		and bool(initial_fact.get("ok", false))
		and initial_fact.get("value", null) == false
		and initial_fact.get("type", &"") == MissionFacts.VALUE_TYPE_BOOL
		and initial_fact.get("scope", &"") == MissionFacts.SCOPE_MISSION
		and not bool(api.call("query_fact", &"missing").get("ok", true))
		and not api.has_method("lookup_content_entity")
		and not api.has_method("lookup_persistent_entity")
		and not api.has_method("get_world"),
		"7.5 one active world-lifetime VarkMissionScript exposes detached semantic queries without mutable Node/entity reach-through"
	)
	if not built or api == null or bus == null:
		session.queue_free()
		await tree.process_frame
		return

	assert_true.call(
		not bool(api.call("set_fact", &"script_flag", true))
		and not bool(api.call("emit_event", &"mission.script_probe", {}))
		and session.call("get_mission_fact", &"script_flag", null) == false,
		"7.5 mutation commands remain rejected while the world is READY"
	)

	var run_summary: Dictionary = api.call("get_run_summary")
	run_summary["loot_count"] = 99
	assert_true.call(
		int(api.call("get_run_summary").get("loot_count", -1)) == 0
		and is_zero_approx(float(api.call("get_gameplay_time_seconds"))),
		"7.5 run/time queries return value-owned semantic data without exposing application flow"
	)

	assert_true.call(
		bool(session.call("begin_play")),
		"7.5 mission script command proof enters PLAYING through normal WorldSession lifecycle"
	)

	var process_probe := ProcessFactProbe.new()
	process_probe.name = "MissionScriptProcessProbe"
	process_probe.configure(api)
	tree.get_root().add_child(process_probe)
	await process_probe.command_issued
	assert_true.call(
		process_probe.fired
		and process_probe.queued
		and process_probe.immediate_value == false
		and api.call("get_fact", &"script_flag", null) == false
		and int(session.call("get_pending_semantic_event_count")) == 1,
		"7.5 _process mutation queues semantic work and cannot change durable fact truth immediately"
	)
	await _settle(tree)
	assert_true.call(
		api.call("get_fact", &"script_flag", null) == true,
		"7.5 _process mutation becomes authoritative only at the later controlled consequence pass"
	)
	process_probe.queue_free()
	await tree.process_frame

	var signal_result: Dictionary = {
		"queued": false,
		"immediate": null,
	}
	var signal_handler: Callable = func() -> void:
		signal_result["queued"] = bool(api.call(
			"set_fact",
			&"script_stage",
			1
		))
		signal_result["immediate"] = api.call(
			"get_fact",
			&"script_stage",
			null
		)
	command_probe.connect(signal_handler, CONNECT_ONE_SHOT)
	emit_signal("command_probe")
	assert_true.call(
		bool(signal_result.get("queued", false))
		and int(signal_result.get("immediate", -1)) == 0
		and int(api.call("get_fact", &"script_stage", -1)) == 0,
		"7.5 arbitrary signal callbacks cannot bypass the controlled semantic mutation boundary"
	)
	await _settle(tree)
	assert_true.call(
		int(api.call("get_fact", &"script_stage", -1)) == 1,
		"7.5 signal-originated mutation applies through the normal consequence pass"
	)

	await tree.process_frame
	var async_queued: bool = bool(api.call("set_fact", &"script_stage", 2))
	assert_true.call(
		async_queued
		and int(api.call("get_fact", &"script_stage", -1)) == 1,
		"7.5 resumed async/out-of-pass code can only queue future semantic mutation"
	)
	await _settle(tree)
	assert_true.call(
		int(api.call("get_fact", &"script_stage", -1)) == 2,
		"7.5 async/out-of-pass queued mutation applies at the later controlled pass"
	)

	var received_events: Array[Dictionary] = []
	var custom_handler: Callable = func(event: Dictionary) -> bool:
		received_events.append(event.duplicate(true))
		return true
	assert_true.call(
		bool(bus.call("subscribe", &"mission.script_probe", custom_handler)),
		"7.5 script API reuses the existing author-facing event bus for observation"
	)
	var source_payload: Dictionary = {"nested": {"value": 1}}
	assert_true.call(
		bool(api.call("emit_event", &"mission.script_probe", source_payload))
		and received_events.is_empty(),
		"7.5 emitted script events queue through the existing semantic dispatcher"
	)
	(source_payload["nested"] as Dictionary)["value"] = 99
	await _settle(tree)
	var received_payload: Dictionary = (
		received_events[0].get("payload", {})
		if received_events.size() == 1
		else {}
	)
	assert_true.call(
		received_events.size() == 1
		and int((received_payload.get("nested", {}) as Dictionary).get("value", -1)) == 1,
		"7.5 script event payloads stay detached from later caller mutation"
	)

	var envelope: Dictionary = session.call("capture_save_envelope")
	var world_state: Dictionary = envelope.get("world_state", {})
	assert_true.call(
		not envelope.is_empty()
		and (world_state.get("mission_script_state", {}) as Dictionary).is_empty()
		and not world_state.has("mission_script"),
		"7.5 provisional script API adds no hidden continuation or independent save state"
	)

	session.call("teardown")
	assert_true.call(
		session.call("get_mission_script") == null
		and not bool(api.call("is_active"))
		and api.call("get_event_bus") == null
		and not bool(api.call("set_fact", &"script_flag", false)),
		"7.5 teardown invalidates retained mission-script API references with the old world"
	)

	var replacement_built: bool = bool(session.call(
		"build",
		source_session_id + 1,
		definition.get("world_scene"),
		definition
	))
	var replacement_api: RefCounted = (
		session.call("get_mission_script") as RefCounted
		if replacement_built
		else null
	)
	assert_true.call(
		replacement_built
		and replacement_api != null
		and replacement_api != api
		and bool(replacement_api.call("is_active")),
		"7.5 replacement creates a fresh isolated mission-script API instance"
	)
	session.call("teardown")
	session.queue_free()
	await tree.process_frame

	await _run_objective_surface(tree, assert_true)


func _run_objective_surface(tree: SceneTree, assert_true: Callable) -> void:
	var session: Node = WorldSession.new()
	session.name = "MissionScriptObjectiveWorldSession"
	tree.get_root().add_child(session)
	var built: bool = bool(session.call("build", 75021, OBJECTIVE_LAB))
	var api: RefCounted = (
		session.call("get_mission_script") as RefCounted
		if built
		else null
	)
	var initial_bonus: Dictionary = (
		api.call("query_objective", &"objective.bonus")
		if api != null
		else {}
	)
	var initial_exit: Dictionary = (
		api.call("query_exit", &"exit.route")
		if api != null
		else {}
	)
	assert_true.call(
		built
		and api != null
		and bool(initial_bonus.get("ok", false))
		and initial_bonus.get("state", &"") == &"inactive"
		and bool(initial_exit.get("ok", false))
		and not bool(initial_exit.get("unlocked", true))
		and not bool(api.call("query_objective", &"objective.missing").get("ok", true))
		and not bool(api.call("activate_objective", &"objective.missing")),
		"7.5 objective/exit queries use stable semantic IDs and unknown IDs fail closed before queueing"
	)
	if not built or api == null:
		session.queue_free()
		await tree.process_frame
		return

	assert_true.call(
		bool(session.call("begin_play"))
		and bool(api.call("activate_objective", &"objective.bonus"))
		and api.call("query_objective", &"objective.bonus").get("state", &"")
			== &"inactive",
		"7.5 objective commands queue existing semantic request events instead of mutating the objective owner directly"
	)
	await _settle(tree)
	assert_true.call(
		api.call("query_objective", &"objective.bonus").get("state", &"")
			== &"active",
		"7.5 queued objective command becomes authoritative through the controlled consequence pass"
	)

	var objectives: Array[Dictionary] = api.call("query_objectives")
	if not objectives.is_empty():
		objectives[0]["state"] = &"corrupted_copy"
	var fresh_objectives: Array[Dictionary] = api.call("query_objectives")
	var detached_ok: bool = true
	for objective: Dictionary in fresh_objectives:
		if objective.get("state", &"") == &"corrupted_copy":
			detached_ok = false
	assert_true.call(
		fresh_objectives.size() >= 3 and detached_ok,
		"7.5 objective query collections are detached value data rather than mutable owner state"
	)

	session.call("teardown")
	assert_true.call(
		not bool(api.call("is_active")),
		"7.5 objective-surface API is invalidated with its WorldSession"
	)
	session.queue_free()
	await tree.process_frame


func _make_definition() -> Resource:
	var definition: Resource = MissionDefinition.new()
	definition.set("mission_id", PLAYGROUND_DEFINITION.get("mission_id"))
	definition.set("world_scene", PLAYGROUND_DEFINITION.get("world_scene"))
	definition.set("map_source_path", PLAYGROUND_DEFINITION.get("map_source_path"))
	definition.set(
		"player_start_selector",
		PLAYGROUND_DEFINITION.get("player_start_selector")
	)
	definition.set(
		"mission_content_revision",
		PLAYGROUND_DEFINITION.get("mission_content_revision")
	)
	var fact_declarations: Array[Dictionary] = [
		{
			"key": &"script_flag",
			"type": MissionFacts.VALUE_TYPE_BOOL,
			"default": false,
			"scope": MissionFacts.SCOPE_MISSION,
		},
		{
			"key": &"script_stage",
			"type": MissionFacts.VALUE_TYPE_INT,
			"default": 0,
			"scope": MissionFacts.SCOPE_RUNTIME,
		},
	]
	definition.set("mission_fact_declarations", fact_declarations)
	return definition


func _settle(tree: SceneTree) -> void:
	await tree.physics_frame
	await tree.process_frame
