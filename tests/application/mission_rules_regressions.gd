extends RefCounted


const WorldSession = preload("res://application/world_session.gd")
const MissionDefinition = preload("res://missions/mission_definition.gd")
const MissionFacts = preload("res://missions/mission_facts.gd")
const MissionRules = preload("res://missions/mission_rules.gd")
const PLAYGROUND_DEFINITION: Resource = preload("res://missions/playground/mission.tres")


func run(tree: SceneTree, assert_true: Callable) -> void:
	await _run_phase_74_contract(tree, assert_true)
	await _run_phase_76_contract(tree, assert_true)


func _run_phase_74_contract(tree: SceneTree, assert_true: Callable) -> void:
	var definition: Resource = _make_phase_74_definition()
	var load_errors: PackedStringArray = definition.call("get_load_errors")
	assert_true.call(
		load_errors.is_empty(),
		"7.4 valid event/condition/action mission rules pass MissionDefinition validation"
	)

	var invalid_definition: Resource = _make_phase_74_definition()
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
	var invalid_text: String = "\n".join(invalid_errors)
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
		"7.4 WorldSession owns one active rule layer over the existing event bus and typed mission facts"
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
		bool(bus.call(
			"subscribe",
			&"mission.rule_fired",
			fired_handler
		))
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
		and (world_state.get("mission_rules", {}) as Dictionary)
			== {"fired_one_shot_rule_ids": []}
		and (world_state.get("mission_script_state", {}) as Dictionary).is_empty(),
		"7.6 legacy 7.4 rules default to repeating behavior and contribute only empty one-shot save state"
	)

	session.call("teardown")
	assert_true.call(
		session.call("get_mission_rules") == null
		and not bool(rules.call("is_active")),
		"7.4 teardown invalidates retained rule-layer references with the old WorldSession"
	)

	session.queue_free()
	await tree.process_frame


func _run_phase_76_contract(tree: SceneTree, assert_true: Callable) -> void:
	var definition: Resource = _make_phase_76_definition()
	var load_errors: PackedStringArray = definition.call("get_load_errors")
	assert_true.call(
		load_errors.is_empty(),
		"7.6 repeat policy extends the small rule schema without changing its condition/action grammar"
	)

	var invalid_definition: Resource = _make_phase_76_definition()
	var invalid_rules: Array[Dictionary] = invalid_definition.get(
		"mission_rule_declarations"
	)
	invalid_rules[0]["repeat"] = "sometimes"
	invalid_definition.set("mission_rule_declarations", invalid_rules)
	var invalid_text: String = "\n".join(
		invalid_definition.call("get_load_errors")
	)
	assert_true.call(
		invalid_text.contains("repeat must be bool"),
		"7.6 repeat policy fails definition validation on non-bool values"
	)

	var session: Node = WorldSession.new()
	session.name = "MissionRules76WorldSession"
	tree.get_root().add_child(session)
	var source_session_id: int = 76001
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
	assert_true.call(
		built
		and rules != null
		and facts != null
		and bus != null
		and rules.call("capture_semantic_state")
			== {"fired_one_shot_rule_ids": []}
		and facts.call("get_value", &"order_gate", null) == false,
		"7.6 fresh rule state starts with no fired one-shots"
	)
	if not built or rules == null or facts == null or bus == null:
		session.queue_free()
		await tree.process_frame
		return

	var observed: Array[StringName] = []
	var observer: Callable = func(event: Dictionary) -> bool:
		observed.append(event.get("name", &""))
		return true
	for event_name: StringName in [
		&"mission.order.first",
		&"mission.order.second",
		&"mission.once",
		&"mission.repeat",
	]:
		assert_true.call(
			bool(bus.call("subscribe", event_name, observer)),
			"7.6 ordering observer subscribes through the existing event bus: %s"
			% event_name
		)

	assert_true.call(
		bool(session.call("begin_play")),
		"7.6 ordering/repeat proof enters PLAYING through normal lifecycle"
	)
	var serial_before: int = int(session.call(
		"get_stable_gameplay_boundary_serial"
	))
	assert_true.call(
		bool(bus.call("emit", &"mission.order_probe", {}))
		and observed.is_empty()
		and facts.call("get_value", &"order_gate", null) == false,
		"7.6 matching rules enqueue actions without mutating trigger-time fact truth immediately"
	)
	await _settle(tree)

	var trace_names: Array[StringName] = []
	for entry: Dictionary in bus.call("get_recent_trace"):
		trace_names.append(entry.get("name", &""))
	var first_summary: Dictionary = rules.call("get_debug_summary")
	assert_true.call(
		observed == [
			&"mission.order.first",
			&"mission.order.second",
			&"mission.once",
			&"mission.repeat",
		]
		and trace_names == [
			&"mission.order_probe",
			MissionFacts.FACT_SET_REQUESTED_EVENT_NAME,
			&"mission.order.first",
			&"mission.order.second",
			&"mission.once",
			&"mission.repeat",
			MissionFacts.FACT_CHANGED_EVENT_NAME,
		]
		and facts.call("get_value", &"order_gate", null) == true
		and first_summary.get("fired_one_shot_rule_ids", [])
			== ["rule.once"]
		and int(session.call("get_stable_gameplay_boundary_serial"))
			== serial_before + 1,
		"7.6 same-event rules evaluate in declaration order against trigger-time facts and append actions to the existing FIFO consequence queue"
	)

	var observed_before_second: int = observed.size()
	assert_true.call(
		bool(bus.call("emit", &"mission.order_probe", {})),
		"7.6 repeat/one-shot proof queues a second identical source event"
	)
	await _settle(tree)
	assert_true.call(
		observed.size() == observed_before_second + 2
		and observed[observed.size() - 2] == &"mission.order.first"
		and observed[observed.size() - 1] == &"mission.repeat"
		and rules.call("capture_semantic_state")
			== {"fired_one_shot_rule_ids": ["rule.once"]},
		"7.6 repeating rules fire again while the fired one-shot stays suppressed"
	)

	var envelope: Dictionary = session.call("capture_save_envelope")
	var saved_rule_state: Dictionary = envelope.get(
		"world_state",
		{}
	).get("mission_rules", {})
	assert_true.call(
		not envelope.is_empty()
		and saved_rule_state
			== {"fired_one_shot_rule_ids": ["rule.once"]}
		and not bool(rules.call(
			"validate_semantic_state",
			{"fired_one_shot_rule_ids": ["rule.unknown"]}
		)),
		"7.6 stable save state stores only configured fired one-shot IDs and rejects unknown saved rule identity"
	)

	session.call("teardown")
	var replacement_built: bool = bool(session.call(
		"build",
		source_session_id + 1,
		definition.get("world_scene"),
		definition
	))
	var replacement_rules: RefCounted = (
		session.call("get_mission_rules") as RefCounted
		if replacement_built
		else null
	)
	var replacement_facts: RefCounted = (
		session.call("get_mission_facts") as RefCounted
		if replacement_built
		else null
	)
	var replacement_bus: RefCounted = (
		session.call("get_mission_event_bus") as RefCounted
		if replacement_built
		else null
	)
	var restore_world_state: Dictionary = envelope.get("world_state", {})
	var restore_began: bool = (
		bool(session.call("begin_restore_from_envelope", envelope))
		if replacement_built
		else false
	)
	var restore_applied: bool = (
		bool(session.call("apply_restore_world_state", restore_world_state))
		if restore_began
		else false
	)
	var restore_completed: bool = (
		bool(session.call("complete_restore"))
		if restore_applied
		else false
	)
	assert_true.call(
		replacement_built
		and replacement_rules != null
		and replacement_facts != null
		and replacement_bus != null
		and restore_began
		and restore_applied
		and restore_completed
		and replacement_rules.call("capture_semantic_state")
			== {"fired_one_shot_rule_ids": ["rule.once"]}
		and replacement_facts.call("get_value", &"order_gate", null) == true
		and int(session.call("get_pending_semantic_event_count")) == 0
		and replacement_bus.call("get_recent_trace").is_empty(),
		"7.6 fresh restore reapplies one-shot rule state and mission facts without replaying rule consequences"
	)

	var restored_observed: Array[StringName] = []
	var restored_observer: Callable = func(event: Dictionary) -> bool:
		restored_observed.append(event.get("name", &""))
		return true
	for event_name: StringName in [
		&"mission.order.first",
		&"mission.order.second",
		&"mission.once",
		&"mission.repeat",
	]:
		replacement_bus.call("subscribe", event_name, restored_observer)
	assert_true.call(
		bool(session.call("begin_play"))
		and bool(replacement_bus.call("emit", &"mission.order_probe", {})),
		"7.6 restored rule state resumes through normal PLAYING dispatch"
	)
	await _settle(tree)
	assert_true.call(
		restored_observed == [
			&"mission.order.first",
			&"mission.repeat",
		]
		and replacement_rules.call("capture_semantic_state")
			== {"fired_one_shot_rule_ids": ["rule.once"]},
		"7.6 restored one-shot remains suppressed while repeating declarations continue normally"
	)

	session.call("teardown")
	session.queue_free()
	await tree.process_frame


func _make_phase_74_definition() -> Resource:
	var definition: Resource = _base_definition()
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

	# No repeat field is intentional: pre-7.6 declarations normalize to
	# repeat=true so existing authored 7.4 rules retain their semantics.
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


func _make_phase_76_definition() -> Resource:
	var definition: Resource = _base_definition()
	var fact_declarations: Array[Dictionary] = [
		{
			"key": &"order_gate",
			"type": MissionFacts.VALUE_TYPE_BOOL,
			"default": false,
			"scope": MissionFacts.SCOPE_MISSION,
		},
	]
	definition.set("mission_fact_declarations", fact_declarations)

	var rule_declarations: Array[Dictionary] = [
		{
			"rule_id": &"rule.order.first",
			"event_name": &"mission.order_probe",
			"repeat": true,
			"conditions": [],
			"actions": [
				{
					"kind": MissionRules.ACTION_SET_FACT,
					"key": &"order_gate",
					"value": true,
				},
				{
					"kind": MissionRules.ACTION_EMIT_EVENT,
					"event_name": &"mission.order.first",
					"payload": {},
				},
			],
		},
		{
			"rule_id": &"rule.order.second",
			"event_name": &"mission.order_probe",
			"repeat": true,
			"conditions": [
				{
					"kind": MissionRules.CONDITION_FACT_EQUALS,
					"key": &"order_gate",
					"value": false,
				},
			],
			"actions": [
				{
					"kind": MissionRules.ACTION_EMIT_EVENT,
					"event_name": &"mission.order.second",
					"payload": {},
				},
			],
		},
		{
			"rule_id": &"rule.once",
			"event_name": &"mission.order_probe",
			"repeat": false,
			"conditions": [],
			"actions": [
				{
					"kind": MissionRules.ACTION_EMIT_EVENT,
					"event_name": &"mission.once",
					"payload": {},
				},
			],
		},
		{
			"rule_id": &"rule.repeat",
			"event_name": &"mission.order_probe",
			"repeat": true,
			"conditions": [],
			"actions": [
				{
					"kind": MissionRules.ACTION_EMIT_EVENT,
					"event_name": &"mission.repeat",
					"payload": {},
				},
			],
		},
	]
	definition.set("mission_rule_declarations", rule_declarations)
	return definition


func _base_definition() -> Resource:
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
	return definition


func _settle(tree: SceneTree) -> void:
	await tree.physics_frame
	await tree.process_frame
