class_name VarkMissionLogicDebugger
extends RefCounted


var _session: Node = null
var _session_id: int = 0
var _event_bus: RefCounted = null
var _mission_facts: RefCounted = null
var _mission_rules: RefCounted = null


static func resolve(node: Node) -> RefCounted:
	var cursor: Node = node
	while cursor != null:
		if cursor.has_method("get_mission_logic_debugger"):
			var value: Variant = cursor.call("get_mission_logic_debugger")
			if value is RefCounted:
				var debugger := value as RefCounted
				if (
					debugger != null
					and debugger.has_method("is_active")
					and bool(debugger.call("is_active"))
				):
					return debugger
		cursor = cursor.get_parent()
	return null


func bind_to_session(
	session: Node,
	session_id: int,
	event_bus: RefCounted,
	mission_facts: RefCounted,
	mission_rules: RefCounted
) -> bool:
	invalidate()
	if (
		session == null
		or not is_instance_valid(session)
		or session_id <= 0
		or event_bus == null
		or mission_facts == null
		or mission_rules == null
		or not event_bus.has_method("is_active")
		or not event_bus.has_method("get_recent_trace")
		or not mission_facts.has_method("get_declarations")
		or not mission_facts.has_method("get_value")
		or not mission_rules.has_method("is_active")
		or not mission_rules.has_method("get_debug_rules")
		or not mission_rules.has_method("get_recent_evaluations")
		or not session.has_method("get_stable_gameplay_boundary_serial")
		or not session.has_method("get_pending_semantic_event_count")
		or not session.has_method("get_last_semantic_event_error")
	):
		return false
	_session = session
	_session_id = session_id
	_event_bus = event_bus
	_mission_facts = mission_facts
	_mission_rules = mission_rules
	return true


func invalidate() -> void:
	_session = null
	_session_id = 0
	_event_bus = null
	_mission_facts = null
	_mission_rules = null


func is_active() -> bool:
	return (
		_session != null
		and is_instance_valid(_session)
		and _session_id > 0
		and int(_session.get("session_id")) == _session_id
		and _event_bus != null
		and bool(_event_bus.call("is_active"))
		and _mission_rules != null
		and bool(_mission_rules.call("is_active"))
	)


func get_facts() -> Array[Dictionary]:
	if not is_active():
		return []
	var declarations_value: Variant = _mission_facts.call("get_declarations")
	if typeof(declarations_value) != TYPE_ARRAY:
		return []
	var result: Array[Dictionary] = []
	for declaration_value: Variant in declarations_value:
		if typeof(declaration_value) != TYPE_DICTIONARY:
			return []
		var declaration: Dictionary = declaration_value
		var key := StringName(str(declaration.get("key", "")))
		result.append({
			"key": key,
			"type": declaration.get("type", &""),
			"scope": declaration.get("scope", &""),
			"default": declaration.get("default"),
			"value": _mission_facts.call("get_value", key, null),
		})
	return result


func get_rules() -> Array[Dictionary]:
	if not is_active():
		return []
	var value: Variant = _mission_rules.call("get_debug_rules")
	if typeof(value) != TYPE_ARRAY:
		return []
	var result: Array[Dictionary] = []
	for entry: Variant in value:
		if typeof(entry) != TYPE_DICTIONARY:
			return []
		result.append((entry as Dictionary).duplicate(true))
	return result


func get_recent_rule_evaluations() -> Array[Dictionary]:
	if not is_active():
		return []
	var value: Variant = _mission_rules.call("get_recent_evaluations")
	if typeof(value) != TYPE_ARRAY:
		return []
	var result: Array[Dictionary] = []
	for entry: Variant in value:
		if typeof(entry) != TYPE_DICTIONARY:
			return []
		result.append((entry as Dictionary).duplicate(true))
	return result


func get_recent_events() -> Array[Dictionary]:
	if not is_active():
		return []
	var value: Variant = _event_bus.call("get_recent_trace")
	if typeof(value) != TYPE_ARRAY:
		return []
	var result: Array[Dictionary] = []
	for entry: Variant in value:
		if typeof(entry) != TYPE_DICTIONARY:
			return []
		result.append((entry as Dictionary).duplicate(true))
	return result


func get_snapshot() -> Dictionary:
	if not is_active():
		return {}
	return {
		"session_id": _session_id,
		"session_state": int(_session.get("state")),
		"stable_boundary_serial": int(_session.call(
			"get_stable_gameplay_boundary_serial"
		)),
		"pending_event_count": int(_session.call(
			"get_pending_semantic_event_count"
		)),
		"last_event_error": str(_session.call(
			"get_last_semantic_event_error"
		)),
		"facts": get_facts(),
		"rules": get_rules(),
		"recent_rule_evaluations": get_recent_rule_evaluations(),
		"recent_events": get_recent_events(),
	}


func inspect_rule(rule_id: StringName) -> Dictionary:
	if not is_active():
		return {
			"ok": false,
			"rule_id": rule_id,
			"error": "Mission logic debugger is inactive.",
		}

	var selected: Dictionary = {}
	for rule: Dictionary in get_rules():
		if rule.get("rule_id", &"") == rule_id:
			selected = rule.duplicate(true)
			break
	if selected.is_empty():
		return {
			"ok": false,
			"rule_id": rule_id,
			"error": "Unknown mission rule.",
		}

	var evaluations: Array[Dictionary] = []
	for entry: Dictionary in get_recent_rule_evaluations():
		if entry.get("rule_id", &"") == rule_id:
			evaluations.append(entry.duplicate(true))

	var source_events: Array[Dictionary] = []
	var source_event_name: StringName = selected.get("event_name", &"")
	for entry: Dictionary in get_recent_events():
		if entry.get("name", &"") == source_event_name:
			source_events.append(entry.duplicate(true))

	return {
		"ok": true,
		"rule_id": rule_id,
		"rule": selected,
		"facts": get_facts(),
		"recent_evaluations": evaluations,
		"recent_source_events": source_events,
	}
