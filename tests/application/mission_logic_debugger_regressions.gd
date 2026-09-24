extends RefCounted


const WorldSession = preload("res://application/world_session.gd")
const MissionDefinition = preload("res://missions/mission_definition.gd")
const MissionFacts = preload("res://missions/mission_facts.gd")
const MissionRules = preload("res://missions/mission_rules.gd")
const MissionLogicDebugger = preload("res://missions/mission_logic_debugger.gd")
const PLAYGROUND_DEFINITION: Resource = preload("res://missions/playground/mission.tres")


func run(tree: SceneTree, assert_true: Callable) -> void:
	var definition: Resource = _make_definition()
	var session: Node = WorldSession.new()
	session.name = "MissionLogicDebuggerWorldSession"
	tree.get_root().add_child(session)
	var source_session_id: int = 77001
	var built: bool = bool(session.call(
		"build",
		source_session_id,
		definition.get("world_scene"),
		definition
	))
	var debugger: RefCounted = (
		session.call("get_mission_logic_debugger") as RefCounted
		if built
		else null
	)
	var bus: RefCounted = (
		session.call("get_mission_event_bus") as RefCounted
		if built
		else null
	)
	var world := session.get("world") as Node
	var initial: Dictionary = (
		debugger.call("get_snapshot")
		if debugger != null
		else {}
	)
	var initial_facts: Array = initial.get("facts", [])
	var initial_rules: Array = initial.get("rules", [])
	assert_true.call(
		built
		and debugger != null
		and bool(debugger.call("is_active"))
		and bus != null
		and world != null
		and MissionLogicDebugger.resolve(world) == debugger
		and initial_facts.size() == 1
		and (initial_facts[0] as Dictionary).get("key", &"") == &"debug_gate"
		and (initial_facts[0] as Dictionary).get("value", null) == false
		and (initial_facts[0] as Dictionary).get("type", &"")
			== MissionFacts.VALUE_TYPE_BOOL
		and initial_rules.size() == 3
		and (initial.get("recent_events", []) as Array).is_empty()
		and (initial.get("recent_rule_evaluations", []) as Array).is_empty()
		and not debugger.has_method("emit")
		and not debugger.has_method("set_fact")
		and not debugger.has_method("queue_mission_fact_set"),
		"7.7 one world-lifetime debugger exposes detached fact/rule diagnostics without a mutation path"
	)
	if not built or debugger == null or bus == null:
		session.queue_free()
		await tree.process_frame
		return

	assert_true.call(
		not bool(debugger.call("inspect_rule", &"rule.missing").get("ok", true))
		and bool(session.call("begin_play")),
		"7.7 unknown rule inspection fails closed and debugger observation does not bypass normal lifecycle"
	)

	assert_true.call(
		bool(bus.call(
			"emit",
			&"mission.debug_probe",
			{"kind": "stop"}
		)),
		"7.7 diagnostic fixture queues a source event with two deliberate condition misses"
	)
	await _settle(tree)

	var first_snapshot: Dictionary = debugger.call("get_snapshot")
	var first_evaluations: Array = first_snapshot.get(
		"recent_rule_evaluations",
		[]
	)
	var payload_eval: Dictionary = _find_latest_evaluation(
		first_evaluations,
		&"rule.payload"
	)
	var fact_eval: Dictionary = _find_latest_evaluation(
		first_evaluations,
		&"rule.fact"
	)
	var once_eval: Dictionary = _find_latest_evaluation(
		first_evaluations,
		&"rule.once"
	)
	var fact_inspection: Dictionary = debugger.call(
		"inspect_rule",
		&"rule.fact"
	)
	assert_true.call(
		payload_eval.get("status", &"") == &"condition_failed"
		and payload_eval.get("reason", &"") == &"event_payload_mismatch"
		and payload_eval.get("key", &"") == &"kind"
		and payload_eval.get("expected", null) == "go"
		and payload_eval.get("actual", null) == "stop"
		and fact_eval.get("status", &"") == &"condition_failed"
		and fact_eval.get("reason", &"") == &"fact_mismatch"
		and fact_eval.get("key", &"") == &"debug_gate"
		and fact_eval.get("expected", null) == true
		and fact_eval.get("actual", null) == false
		and once_eval.get("status", &"") == &"matched"
		and int(once_eval.get("actions_queued", 0)) == 1
		and bool(fact_inspection.get("ok", false))
		and (fact_inspection.get("recent_evaluations", []) as Array).size() == 1
		and (fact_inspection.get("recent_source_events", []) as Array).size() == 1,
		"7.7 rule inspection explains payload/fact misses with trigger-time expected/actual values and records successful matches"
	)

	assert_true.call(
		bool(session.call("queue_mission_fact_set", &"debug_gate", true)),
		"7.7 fixture changes fact truth through the normal controlled mutation path"
	)
	await _settle(tree)

	var serial_before: int = int(session.call(
		"get_stable_gameplay_boundary_serial"
	))
	assert_true.call(
		bool(bus.call(
			"emit",
			&"mission.debug_probe",
			{"kind": "go"}
		)),
		"7.7 fixture queues a source event whose remaining repeating rules should match"
	)
	await _settle(tree)

	var second_snapshot: Dictionary = debugger.call("get_snapshot")
	var second_evaluations: Array = second_snapshot.get(
		"recent_rule_evaluations",
		[]
	)
	payload_eval = _find_latest_evaluation(second_evaluations, &"rule.payload")
	fact_eval = _find_latest_evaluation(second_evaluations, &"rule.fact")
	once_eval = _find_latest_evaluation(second_evaluations, &"rule.once")
	var latest_pass: int = int(session.call(
		"get_stable_gameplay_boundary_serial"
	))
	var latest_event_names: Array[StringName] = []
	for entry_value: Variant in second_snapshot.get("recent_events", []):
		var entry: Dictionary = entry_value
		if int(entry.get("consequence_pass_serial", 0)) == latest_pass:
			latest_event_names.append(entry.get("name", &""))
	assert_true.call(
		payload_eval.get("status", &"") == &"matched"
		and fact_eval.get("status", &"") == &"matched"
		and once_eval.get("status", &"") == &"skipped"
		and once_eval.get("reason", &"") == &"one_shot_already_fired"
		and int(payload_eval.get("event_sequence", 0))
			== int(fact_eval.get("event_sequence", -1))
		and int(fact_eval.get("event_sequence", 0))
			== int(once_eval.get("event_sequence", -1))
		and int(payload_eval.get("consequence_pass_serial", 0)) == latest_pass
		and latest_event_names == [
			&"mission.debug_probe",
			&"mission.debug.payload_matched",
			&"mission.debug.fact_matched",
		]
		and latest_pass == serial_before + 1,
		"7.7 debugger correlates same-source rule outcomes with the exact FIFO event cascade and stable consequence pass"
	)

	var inspected_once: Dictionary = debugger.call("inspect_rule", &"rule.once")
	var inspected_rule: Dictionary = inspected_once.get("rule", {})
	assert_true.call(
		bool(inspected_once.get("ok", false))
		and not bool(inspected_rule.get("repeat", true))
		and bool(inspected_rule.get("one_shot_fired", false))
		and (inspected_once.get("recent_evaluations", []) as Array).size() == 2,
		"7.7 direct rule inspection exposes declaration policy plus recent matched/skipped history"
	)

	for _index: int in 18:
		assert_true.call(
			bool(bus.call(
				"emit",
				&"mission.debug_probe",
				{"kind": "go"}
			)),
			"7.7 bounded-history fixture queues an additional diagnostic source event"
		)
	await _settle(tree)
	var bounded_snapshot: Dictionary = debugger.call("get_snapshot")
	assert_true.call(
		(bounded_snapshot.get("recent_rule_evaluations", []) as Array).size()
			== MissionRules.DEBUG_EVALUATION_LIMIT
		and (bounded_snapshot.get("recent_events", []) as Array).size()
			<= WorldSession.SEMANTIC_EVENT_TRACE_LIMIT,
		"7.7 rule and event diagnostic histories are bounded rather than unbounded gameplay state"
	)

	var envelope: Dictionary = session.call("capture_save_envelope")
	var world_state: Dictionary = envelope.get("world_state", {})
	assert_true.call(
		not envelope.is_empty()
		and not world_state.has("mission_logic_debugger")
		and not world_state.has("mission_logic_debugger_state"),
		"7.7 diagnostic history is not gameplay truth and adds no save-state section"
	)

	session.call("teardown")
	assert_true.call(
		session.call("get_mission_logic_debugger") == null
		and not bool(debugger.call("is_active"))
		and (debugger.call("get_snapshot") as Dictionary).is_empty()
		and (debugger.call("get_recent_events") as Array).is_empty(),
		"7.7 teardown invalidates retained debugger references with the old world"
	)

	var replacement_built: bool = bool(session.call(
		"build",
		source_session_id + 1,
		definition.get("world_scene"),
		definition
	))
	var replacement_debugger: RefCounted = (
		session.call("get_mission_logic_debugger") as RefCounted
		if replacement_built
		else null
	)
	var replacement_snapshot: Dictionary = (
		replacement_debugger.call("get_snapshot")
		if replacement_debugger != null
		else {}
	)
	var replacement_facts: Array = replacement_snapshot.get("facts", [])
	assert_true.call(
		replacement_built
		and replacement_debugger != null
		and replacement_debugger != debugger
		and bool(replacement_debugger.call("is_active"))
		and (replacement_snapshot.get("recent_events", []) as Array).is_empty()
		and (replacement_snapshot.get(
			"recent_rule_evaluations",
			[]
		) as Array).is_empty()
		and replacement_facts.size() == 1
		and (replacement_facts[0] as Dictionary).get("value", null) == false,
		"7.7 replacement world receives fresh diagnostic history over fresh semantic truth"
	)
	session.call("teardown")
	session.queue_free()
	await tree.process_frame


func _find_latest_evaluation(
	evaluations: Array,
	rule_id: StringName
) -> Dictionary:
	for index: int in range(evaluations.size() - 1, -1, -1):
		var value: Variant = evaluations[index]
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = value
		if entry.get("rule_id", &"") == rule_id:
			return entry.duplicate(true)
	return {}


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
	var facts: Array[Dictionary] = [
		{
			"key": &"debug_gate",
			"type": MissionFacts.VALUE_TYPE_BOOL,
			"default": false,
			"scope": MissionFacts.SCOPE_MISSION,
		},
	]
	definition.set("mission_fact_declarations", facts)
	var rules: Array[Dictionary] = [
		{
			"rule_id": &"rule.payload",
			"event_name": &"mission.debug_probe",
			"repeat": true,
			"conditions": [
				{
					"kind": MissionRules.CONDITION_EVENT_PAYLOAD_EQUALS,
					"key": &"kind",
					"value": "go",
				},
			],
			"actions": [
				{
					"kind": MissionRules.ACTION_EMIT_EVENT,
					"event_name": &"mission.debug.payload_matched",
					"payload": {},
				},
			],
		},
		{
			"rule_id": &"rule.fact",
			"event_name": &"mission.debug_probe",
			"repeat": true,
			"conditions": [
				{
					"kind": MissionRules.CONDITION_FACT_EQUALS,
					"key": &"debug_gate",
					"value": true,
				},
			],
			"actions": [
				{
					"kind": MissionRules.ACTION_EMIT_EVENT,
					"event_name": &"mission.debug.fact_matched",
					"payload": {},
				},
			],
		},
		{
			"rule_id": &"rule.once",
			"event_name": &"mission.debug_probe",
			"repeat": false,
			"conditions": [],
			"actions": [
				{
					"kind": MissionRules.ACTION_EMIT_EVENT,
					"event_name": &"mission.debug.once",
					"payload": {},
				},
			],
		},
	]
	definition.set("mission_rule_declarations", rules)
	return definition


func _settle(tree: SceneTree) -> void:
	await tree.physics_frame
	await tree.process_frame
