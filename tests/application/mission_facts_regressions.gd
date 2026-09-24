extends RefCounted


const WorldSession = preload("res://application/world_session.gd")
const MissionDefinition = preload("res://missions/mission_definition.gd")
const MissionFacts = preload("res://missions/mission_facts.gd")
const PLAYGROUND_DEFINITION: Resource = preload("res://missions/playground/mission.tres")


func run(tree: SceneTree, assert_true: Callable) -> void:
	var definition: Resource = _make_definition()
	var declaration_errors: PackedStringArray = definition.call("get_load_errors")
	assert_true.call(
		declaration_errors.is_empty(),
		"7.2 valid typed mission-fact declarations pass MissionDefinition validation"
	)

	var invalid_definition: Resource = _make_definition()
	invalid_definition.set("mission_fact_declarations", [
		{
			"key": &"duplicate",
			"type": &"bool",
			"default": false,
			"scope": &"mission",
		},
		{
			"key": &"duplicate",
			"type": &"int",
			"default": 0,
			"scope": &"runtime",
		},
		{
			"key": &"campaign_leak",
			"type": &"string",
			"default": "forbidden",
			"scope": &"campaign",
		},
		{
			"key": &"wrong_default",
			"type": &"float",
			"default": 1,
			"scope": &"mission",
		},
	])
	var invalid_errors: PackedStringArray = invalid_definition.call("get_load_errors")
	assert_true.call(
		invalid_errors.size() >= 3
		and "\n".join(invalid_errors).contains("duplicates fact key")
		and "\n".join(invalid_errors).contains("scope 'campaign' is unsupported")
		and "\n".join(invalid_errors).contains("does not match declared type 'float'"),
		"7.2 declarations fail closed on duplicate keys, campaign scope, and mismatched defaults"
	)

	var session: Node = WorldSession.new()
	session.name = "MissionFactsWorldSession"
	tree.get_root().add_child(session)
	var source_session_id: int = 72001
	var built: bool = bool(session.call(
		"build",
		source_session_id,
		definition.get("world_scene"),
		definition
	))
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
		and facts != null
		and bus != null
		and facts.call("get_declarations").size() == 4
		and facts.call("get_value", &"route_discovered", null) == false
		and int(facts.call("get_value", &"ritual_stage", -1)) == 0
		and str(facts.call("get_value", &"alarm_label", "")) == "quiet"
		and is_equal_approx(
			float(facts.call("get_value", &"search_scale", 0.0)),
			1.0
		),
		"7.2 WorldSession builds mission/runtime facts from typed declarations and declared defaults"
	)
	if not built or facts == null or bus == null:
		session.queue_free()
		await tree.process_frame
		return

	assert_true.call(
		not bool(session.call("queue_mission_fact_set", &"unknown_fact", true))
		and not bool(session.call(
			"queue_mission_fact_set",
			&"ritual_stage",
			"three"
		))
		and int(session.call("get_pending_semantic_event_count")) == 0,
		"7.2 unknown and wrong-type assignments are rejected before entering the semantic queue"
	)
	assert_true.call(
		not bool(session.call(
			"queue_mission_fact_set",
			&"route_discovered",
			true
		)),
		"7.2 fact mutation cannot enter ordinary dispatch while the session is only READY"
	)

	var changes: Array[Dictionary] = []
	var changed_handler: Callable = func(event: Dictionary) -> bool:
		changes.append(event.duplicate(true))
		return true
	assert_true.call(
		bool(bus.call(
			"subscribe",
			MissionFacts.FACT_CHANGED_EVENT_NAME,
			changed_handler
		))
		and bool(session.call("begin_play")),
		"7.2 fact-change observation subscribes before PLAYING through the existing mission event bus"
	)

	var serial_before: int = int(session.call("get_stable_gameplay_boundary_serial"))
	assert_true.call(
		bool(session.call(
			"queue_mission_fact_set",
			&"route_discovered",
			true
		))
		and bool(session.call(
			"queue_mission_fact_set",
			&"ritual_stage",
			3
		))
		and bool(session.call(
			"queue_mission_fact_set",
			&"alarm_label",
			"alert"
		))
		and bool(session.call(
			"queue_mission_fact_set",
			&"search_scale",
			0.5
		))
		and facts.call("get_value", &"route_discovered", null) == false
		and int(facts.call("get_value", &"ritual_stage", -1)) == 0
		and changes.is_empty(),
		"7.2 valid assignments queue semantic requests instead of mutating durable fact truth immediately"
	)

	await _settle(tree)

	var changed_keys: Array[String] = []
	for event: Dictionary in changes:
		var payload: Dictionary = event.get("payload", {})
		changed_keys.append(str(payload.get("key", &"")))
	assert_true.call(
		facts.call("get_value", &"route_discovered", null) == true
		and int(facts.call("get_value", &"ritual_stage", -1)) == 3
		and str(facts.call("get_value", &"alarm_label", "")) == "alert"
		and is_equal_approx(
			float(facts.call("get_value", &"search_scale", 0.0)),
			0.5
		)
		and changed_keys == [
			"route_discovered",
			"ritual_stage",
			"alarm_label",
			"search_scale",
		]
		and int(session.call("get_stable_gameplay_boundary_serial"))
			== serial_before + 1,
		"7.2 controlled consequence pass applies typed assignments in request order and emits detached mission.fact_changed facts"
	)

	var change_count_before: int = changes.size()
	assert_true.call(
		bool(session.call(
			"queue_mission_fact_set",
			&"ritual_stage",
			3
		)),
		"7.2 assigning the existing typed value is accepted as an idempotent request"
	)
	await _settle(tree)
	assert_true.call(
		changes.size() == change_count_before,
		"7.2 idempotent fact assignment does not emit a false change event"
	)

	var envelope: Dictionary = session.call("capture_save_envelope")
	var world_state: Dictionary = envelope.get("world_state", {})
	var saved_facts: Dictionary = world_state.get("mission_facts", {})
	assert_true.call(
		not envelope.is_empty()
		and saved_facts == {
			"ritual_stage": 3,
			"route_discovered": true,
		}
		and not saved_facts.has("alarm_label")
		and not saved_facts.has("search_scale"),
		"7.2 save capture persists mission-scope facts only; runtime-scope facts stay world-lifetime state"
	)

	session.call("teardown")
	assert_true.call(
		session.call("get_mission_facts") == null,
		"7.2 teardown discards mission facts with the old world lifetime"
	)

	var replacement_session_id: int = source_session_id + 1
	var replacement_built: bool = bool(session.call(
		"build",
		replacement_session_id,
		definition.get("world_scene"),
		definition
	))
	var replacement_facts: RefCounted = (
		session.call("get_mission_facts") as RefCounted
		if replacement_built
		else null
	)
	assert_true.call(
		replacement_built
		and replacement_facts != null
		and replacement_facts.call("get_value", &"route_discovered", null) == false
		and int(replacement_facts.call("get_value", &"ritual_stage", -1)) == 0
		and str(replacement_facts.call("get_value", &"alarm_label", "")) == "quiet"
		and is_equal_approx(
			float(replacement_facts.call("get_value", &"search_scale", 0.0)),
			1.0
		),
		"7.2 fresh replacement world starts all declared facts from defaults before restore"
	)

	var restore_world_state: Dictionary = envelope.get("world_state", {})
	var restore_began: bool = bool(session.call(
		"begin_restore_from_envelope",
		envelope
	))
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
		restore_began
		and restore_applied
		and restore_completed
		and replacement_facts.call("get_value", &"route_discovered", null) == true
		and int(replacement_facts.call("get_value", &"ritual_stage", -1)) == 3
		and str(replacement_facts.call("get_value", &"alarm_label", "")) == "quiet"
		and is_equal_approx(
			float(replacement_facts.call("get_value", &"search_scale", 0.0)),
			1.0
		)
		and int(session.call("get_pending_semantic_event_count")) == 0,
		"7.2 restore reapplies mission-scope truth while runtime-scope facts reset to declared defaults with no consequence replay"
	)

	assert_true.call(
		not bool(replacement_facts.call(
			"validate_semantic_state",
			{
				"route_discovered": true,
				"ritual_stage": "wrong",
			}
		))
		and not bool(replacement_facts.call(
			"validate_semantic_state",
			{
				"route_discovered": true,
				"ritual_stage": 3,
				"unknown": 1,
			}
		)),
		"7.2 saved mission-fact snapshots reject type mismatch and unknown keys"
	)

	session.call("teardown")
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
	var declarations: Array[Dictionary] = [
		{
			"key": &"route_discovered",
			"type": MissionFacts.VALUE_TYPE_BOOL,
			"default": false,
			"scope": MissionFacts.SCOPE_MISSION,
		},
		{
			"key": &"ritual_stage",
			"type": MissionFacts.VALUE_TYPE_INT,
			"default": 0,
			"scope": MissionFacts.SCOPE_MISSION,
		},
		{
			"key": &"alarm_label",
			"type": MissionFacts.VALUE_TYPE_STRING,
			"default": "quiet",
			"scope": MissionFacts.SCOPE_RUNTIME,
		},
		{
			"key": &"search_scale",
			"type": MissionFacts.VALUE_TYPE_FLOAT,
			"default": 1.0,
			"scope": MissionFacts.SCOPE_RUNTIME,
		},
	]
	definition.set("mission_fact_declarations", declarations)
	return definition


func _settle(tree: SceneTree) -> void:
	await tree.physics_frame
	await tree.process_frame
