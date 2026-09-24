extends RefCounted


const WorldSession = preload("res://application/world_session.gd")
const MissionDefinition = preload("res://missions/mission_definition.gd")
const MissionFacts = preload("res://missions/mission_facts.gd")
const MissionRules = preload("res://missions/mission_rules.gd")
const PLAYGROUND_DEFINITION: Resource = preload("res://missions/playground/mission.tres")


func run(tree: SceneTree, assert_true: Callable) -> void:
	var definition: Resource = _make_definition()
	var load_errors: PackedStringArray = definition.call("get_load_errors")
	assert_true.call(
		load_errors.is_empty(),
		"7.4 valid event/condition/action mission rules pass MissionDefinition validation"
	)

	var invalid_definition: Resource = _make_definition()
	var invalid_rules: Array[Dictionary] = [
		{
			"rule_id": &"bad.rule",
			"event_name": &"mission.bad",
			"conditions": [
				{
					"kind": MissionRules.CONDITION_FACT_EQUALS,
					"key": &"missing_fact",
					"value": true,
				},
			],
			"actions": [
				{
					"kind": &"call_arbitrary_code",
					"value": "forbidden",
				},
			],
		},
		{
			"rule_id": &"bad.rule",
			"event_name": &"mission.bad.two",
			"conditions": [],
			"actions": [
				{
					"kind": MissionRules.ACTION_SET_FACT,
					"key": &"rule_enabled",
					"value": "wrong_type",
				},
			],
		},
	]
	invalid_definition.set("mission_rule_declarations", invalid_rules)
	var invalid_errors: PackedStringArray = invalid_definition.call("get_load_errors")
	var invalid_text: String = "
".join(invalid_errors)
	assert_true.call(
		invalid_text.contains("unknown mission fact 'missing_fact'")
		and invalid_text.contains("action kind 'call_arbitrary_code' is unsupported")
		and invalid_text.contains("duplicates rule_id 'bad.rule'")
		and invalid_text.contains("does not match mission fact 'rule_enabled' type 'bool'"),
		"7.4 rule declarations fail closed on unknown facts, arbitrary action kinds, duplicate IDs, and typed-literal mismatches"
	)

	var session: Node = WorldSession.new()
	session.name = "MissionRulesWorldSession"
	tree.get_root().add_child(session)
	var source_session_id: int = 74001
	var built: bool = bool(session.call(
		"build",
		source_session_id,
		definition.get("world_scene"),
		definition
	))
	var rules: RefCounted = (
		session.call("get_mission_rules") as RefCounted
		if built
		else null
	)
	var facts: RefCounted = (
		session.call("get_mission_facts") as RefCounted
		if built
		else null
	)
	var bus: RefCounted = (
		session.call("get_mission_event_bus") as RefCounted
		if built
		else null
	)
	var summary: Dictionary = (
		rules.call("get_debug_summary")
		if rules != null
		else {}
	)
	assert_true.call(
		built
		and rules != null
		and facts != null
		and bus != null
		and bool(summary.get("active", false))
		and int(summary.get("rule_count", 0)) == 1
		and int(summary.get("subscribed_event_count", 0)) == 1
		and facts.call("get_value", &"rule_enabled", null) == false
		and str(facts.call("get_value", &"rule_result", "")) == "none",
		"7.4 WorldSession owns one active stateless rule layer over the existing event bus and typed mission facts"
	)
	if not built or rules == null or facts == null or bus == null:
		session.queue_free()
		await tree.process_frame
		return

	var fired_events: Array[Dictionary] = []
	var fired_handler: Callable = func(event: Dictionary) -> bool:
		fired_events.append(event.duplicate(true))
		var payload: Dictionary = event.get("payload", {})
		payload["source"] = "handler-mutated-copy"
		return true
	assert_true.call(
		bool(bus.call("subscribe", &"mission.rule_fired", fired_handler))
		and bool(session.call("begin_play")),
		"7.4 rule result observation uses the existing author-facing semantic event bus"
	)

	assert_true.call(
		bool(bus.call(
			"emit",
			&"mission.rule_probe",
			{"kind": "go", "noise": 1}
		)),
		"7.4 matching source events enter the normal semantic queue"
	)
	await _settle(tree)
	assert_true.call(
		str(facts.call("get_value", &"rule_result", "")) == "none"
		and fired_events.is_empty()
		and int(rules.call("get_debug_summary").get("match_count", -1)) == 0,
		"7.4 fact conditions prevent a rule from firing when typed mission truth does not match"
	)

	assert_true.call(
		bool(session.call(
			"queue_mission_fact_set",
			&"rule_enabled",
			true
		)),
		"7.4 test enables the declared rule gate through the existing controlled fact mutation path"
	)
	await _settle(tree)

	assert_true.call(
		bool(bus.call(
			"emit",
			&"mission.rule_probe",
			{"kind": "stop"}
		)),
		"7.4 event-payload condition proof queues a nonmatching source event"
	)
	await _settle(tree)
	assert_true.call(
		str(facts.call("get_value", &"rule_result", "")) == "none"
		and fired_events.is_empty()
		and int(rules.call("get_debug_summary").get("match_count", -1)) == 0,
		"7.4 event-payload literal conditions fail without side effects"
	)

	var serial_before: int = int(session.call(
		"get_stable_gameplay_boundary_serial"
	))
	assert_true.call(
		bool(bus.call(
			"emit",
			&"mission.rule_probe",
			{"kind": "go"}
		))
		and str(facts.call("get_value", &"rule_result", "")) == "none"
		and fired_events.is_empty(),
		"7.4 matched rule events do not mutate facts or emit actions before the controlled consequence pass"
	)
	await _settle(tree)

	var fired_payload: Dictionary = (
		fired_events[0].get("payload", {})
		if fired_events.size() == 1
		else {}
	)
	summary = rules.call("get_debug_summary")
	assert_true.call(
		str(facts.call("get_value", &"rule_result", "")) == "matched"
		and fired_events.size() == 1
		and str(fired_payload.get("source", "")) == "rule.probe"
		and int(summary.get("match_count", 0)) == 1
		and int(summary.get("action_count", 0)) == 2
		and summary.get("last_rule_id", &"") == &"rule.probe.match"
		and summary.get("last_event_name", &"") == &"mission.rule_probe"
		and int(session.call("get_stable_gameplay_boundary_serial"))
			== serial_before + 1,
		"7.4 one matched declarative rule queues typed set_fact plus detached emit_event actions through the existing semantic cascade"
	)

	var authored_rules: Array[Dictionary] = definition.get(
		"mission_rule_declarations"
	)
	var authored_actions: Array = authored_rules[0].get("actions", [])
	var authored_emit_payload: Dictionary = authored_actions[1].get(
		"payload",
		{}
	)
	assert_true.call(
		str(authored_emit_payload.get("source", "")) == "rule.probe",
		"7.4 handler-local payload mutation cannot rewrite authored rule data"
	)

	var envelope: Dictionary = session.call("capture_save_envelope")
	var world_state: Dictionary = envelope.get("world_state", {})
	assert_true.call(
		not envelope.is_empty()
		and not world_state.has("mission_rules")
		and (world_state.get("mission_script_state", {}) as Dictionary).is_empty(),
		"7.4 stateless immediate rules add no hidden continuation or independent save owner before Phase 7.6"
	)

	session.call("teardown")
	assert_true.call(
		session.call("get_mission_rules") == null
		and not bool(rules.call("is_active")),
		"7.4 teardown invalidates retained rule-layer references with the old WorldSession"
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
			"key": &"rule_enabled",
			"type": MissionFacts.VALUE_TYPE_BOOL,
			"default": false,
			"scope": MissionFacts.SCOPE_MISSION,
		},
		{
			"key": &"rule_result",
			"type": MissionFacts.VALUE_TYPE_STRING,
			"default": "none",
			"scope": MissionFacts.SCOPE_MISSION,
		},
	]
	definition.set("mission_fact_declarations", fact_declarations)

	var rule_declarations: Array[Dictionary] = [
		{
			"rule_id": &"rule.probe.match",
			"event_name": &"mission.rule_probe",
			"conditions": [
				{
					"kind": MissionRules.CONDITION_EVENT_PAYLOAD_EQUALS,
					"key": &"kind",
					"value": "go",
				},
				{
					"kind": MissionRules.CONDITION_FACT_EQUALS,
					"key": &"rule_enabled",
					"value": true,
				},
			],
			"actions": [
				{
					"kind": MissionRules.ACTION_SET_FACT,
					"key": &"rule_result",
					"value": "matched",
				},
				{
					"kind": MissionRules.ACTION_EMIT_EVENT,
					"event_name": &"mission.rule_fired",
					"payload": {"source": "rule.probe"},
				},
			],
		},
	]
	definition.set("mission_rule_declarations", rule_declarations)
	return definition


func _settle(tree: SceneTree) -> void:
	await tree.physics_frame
	await tree.process_frame
