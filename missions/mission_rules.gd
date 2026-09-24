class_name VarkMissionRules
extends RefCounted


const MissionFacts = preload("res://missions/mission_facts.gd")

const CONDITION_EVENT_PAYLOAD_EQUALS: StringName = &"event_payload_equals"
const CONDITION_FACT_EQUALS: StringName = &"fact_equals"

const ACTION_SET_FACT: StringName = &"set_fact"
const ACTION_EMIT_EVENT: StringName = &"emit_event"


var _session: Node = null
var _event_bus: RefCounted = null
var _mission_facts: RefCounted = null
var _rules_by_event: Dictionary = {}
var _subscriptions: Array[Dictionary] = []
var _rule_ids: Dictionary[String, bool] = {}
var _one_shot_rule_ids: Dictionary[String, bool] = {}
var _fired_one_shot_rule_ids: Dictionary[String, bool] = {}
var _rule_count: int = 0
var _match_count: int = 0
var _action_count: int = 0
var _last_rule_id: StringName = &""
var _last_event_name: StringName = &""
var _last_error: String = ""


static func validate_declarations(
	declarations: Array[Dictionary],
	fact_declarations: Array[Dictionary]
) -> PackedStringArray:
	var errors := PackedStringArray()
	var seen_rule_ids: Dictionary[String, bool] = {}
	var fact_types: Dictionary = _fact_type_lookup(fact_declarations)

	for rule_index: int in declarations.size():
		var rule: Dictionary = declarations[rule_index]
		var prefix: String = "mission_rule_declarations[%d]" % rule_index
		var has_repeat: bool = rule.has("repeat")
		if (
			(rule.size() != 4 and rule.size() != 5)
			or not rule.has("rule_id")
			or not rule.has("event_name")
			or not rule.has("conditions")
			or not rule.has("actions")
			or (rule.size() == 5 and not has_repeat)
		):
			errors.append(
				"%s must contain rule_id, event_name, conditions, actions, and optional repeat only."
				% prefix
			)
			continue
		if has_repeat and typeof(rule.get("repeat")) != TYPE_BOOL:
			errors.append("%s repeat must be bool." % prefix)

		var rule_id: String = str(rule.get("rule_id", "")).strip_edges()
		var event_name: String = str(rule.get("event_name", "")).strip_edges()
		if rule_id.is_empty():
			errors.append("%s rule_id must not be empty." % prefix)
		elif seen_rule_ids.has(rule_id):
			errors.append("%s duplicates rule_id '%s'." % [prefix, rule_id])
		else:
			seen_rule_ids[rule_id] = true
		if event_name.is_empty():
			errors.append("%s event_name must not be empty." % prefix)

		var conditions_value: Variant = rule.get("conditions", null)
		if typeof(conditions_value) != TYPE_ARRAY:
			errors.append("%s conditions must be an Array." % prefix)
		else:
			var conditions: Array = conditions_value
			for condition_index: int in conditions.size():
				_validate_condition(
					conditions[condition_index],
					"%s.conditions[%d]" % [prefix, condition_index],
					fact_types,
					errors
				)

		var actions_value: Variant = rule.get("actions", null)
		if typeof(actions_value) != TYPE_ARRAY:
			errors.append("%s actions must be an Array." % prefix)
		else:
			var actions: Array = actions_value
			if actions.is_empty():
				errors.append("%s actions must not be empty." % prefix)
			for action_index: int in actions.size():
				_validate_action(
					actions[action_index],
					"%s.actions[%d]" % [prefix, action_index],
					fact_types,
					errors
				)

	return errors


func configure(
	session: Node,
	event_bus: RefCounted,
	mission_facts: RefCounted,
	declarations: Array[Dictionary]
) -> bool:
	_last_error = ""
	if (
		session == null
		or not is_instance_valid(session)
		or event_bus == null
		or mission_facts == null
	):
		_last_error = "Mission rules require session, event bus, and mission facts."
		return false

	shutdown()
	_session = session
	_event_bus = event_bus
	_mission_facts = mission_facts
	_rules_by_event.clear()
	_rule_ids.clear()
	_one_shot_rule_ids.clear()
	_fired_one_shot_rule_ids.clear()
	_rule_count = declarations.size()
	_match_count = 0
	_action_count = 0
	_last_rule_id = &""
	_last_event_name = &""

	for declaration: Dictionary in declarations:
		var rule: Dictionary = declaration.duplicate(true)
		var rule_id: String = str(rule.get("rule_id", "")).strip_edges()
		var repeats: bool = bool(rule.get("repeat", true))
		rule["repeat"] = repeats
		_rule_ids[rule_id] = true
		if not repeats:
			_one_shot_rule_ids[rule_id] = true
		var event_name := StringName(
			str(rule.get("event_name", "")).strip_edges()
		)
		if not _rules_by_event.has(event_name):
			_rules_by_event[event_name] = []
		# Per-event arrays retain MissionDefinition declaration order. This is
		# the deterministic cross-rule order; no separate priority system exists.
		(_rules_by_event[event_name] as Array).append(rule)

	var event_names: Array = _rules_by_event.keys()
	event_names.sort_custom(
		func(a: Variant, b: Variant) -> bool:
			return str(a) < str(b)
	)
	for event_name_value: Variant in event_names:
		var event_name := StringName(str(event_name_value))
		var handler: Callable = Callable(self, "_on_event").bind(event_name)
		if not bool(_event_bus.call("subscribe", event_name, handler)):
			_last_error = "Could not subscribe mission rules to '%s'." % event_name
			shutdown()
			return false
		_subscriptions.append({
			"event_name": event_name,
			"handler": handler,
		})

	return true


func shutdown() -> void:
	if _event_bus != null:
		for subscription: Dictionary in _subscriptions:
			var event_name: StringName = subscription.get("event_name", &"")
			var handler: Callable = subscription.get("handler", Callable())
			if handler.is_valid():
				_event_bus.call("unsubscribe", event_name, handler)
	_subscriptions.clear()
	_rules_by_event.clear()
	_rule_ids.clear()
	_one_shot_rule_ids.clear()
	_fired_one_shot_rule_ids.clear()
	_session = null
	_event_bus = null
	_mission_facts = null


func is_active() -> bool:
	return (
		_session != null
		and is_instance_valid(_session)
		and _event_bus != null
		and bool(_event_bus.call("is_active"))
	)


func get_last_error() -> String:
	return _last_error


func get_debug_summary() -> Dictionary:
	return {
		"active": is_active(),
		"rule_count": _rule_count,
		"subscribed_event_count": _subscriptions.size(),
		"match_count": _match_count,
		"action_count": _action_count,
		"last_rule_id": _last_rule_id,
		"last_event_name": _last_event_name,
		"fired_one_shot_rule_ids": _get_fired_one_shot_rule_ids(),
		"last_error": _last_error,
	}


func capture_semantic_state() -> Dictionary:
	return {
		"fired_one_shot_rule_ids": _get_fired_one_shot_rule_ids(),
	}


func get_default_semantic_state() -> Dictionary:
	return {
		"fired_one_shot_rule_ids": [],
	}


func validate_semantic_state(snapshot: Dictionary) -> bool:
	_last_error = ""
	if (
		snapshot.size() != 1
		or not snapshot.has("fired_one_shot_rule_ids")
		or typeof(snapshot.get("fired_one_shot_rule_ids")) != TYPE_ARRAY
	):
		_last_error = (
			"Mission rule state must contain exactly fired_one_shot_rule_ids."
		)
		return false

	var seen: Dictionary[String, bool] = {}
	for value: Variant in snapshot.get("fired_one_shot_rule_ids", []):
		if typeof(value) != TYPE_STRING:
			_last_error = "Fired one-shot rule IDs must be strings."
			return false
		var rule_id: String = str(value).strip_edges()
		if rule_id.is_empty() or seen.has(rule_id):
			_last_error = "Fired one-shot rule IDs must be non-empty and unique."
			return false
		if not _one_shot_rule_ids.has(rule_id):
			_last_error = (
				"Saved one-shot rule ID '%s' is not a configured one-shot rule."
				% rule_id
			)
			return false
		seen[rule_id] = true
	return true


func apply_semantic_state(snapshot: Dictionary) -> bool:
	if not validate_semantic_state(snapshot):
		return false
	_fired_one_shot_rule_ids.clear()
	for value: Variant in snapshot.get("fired_one_shot_rule_ids", []):
		_fired_one_shot_rule_ids[str(value)] = true
	return true


func _get_fired_one_shot_rule_ids() -> Array[String]:
	var result: Array[String] = []
	for rule_id: String in _fired_one_shot_rule_ids.keys():
		result.append(rule_id)
	result.sort()
	return result


func _on_event(event: Dictionary, subscribed_event_name: StringName) -> bool:
	if not is_active():
		return false
	var event_name: StringName = event.get("name", &"")
	if event_name != subscribed_event_name:
		_last_error = (
			"Mission rule subscription '%s' received mismatched event '%s'."
			% [subscribed_event_name, event_name]
		)
		return false

	var rules: Array = _rules_by_event.get(event_name, [])
	for rule_value: Variant in rules:
		var rule: Dictionary = rule_value
		var rule_id: String = str(rule.get("rule_id", "")).strip_edges()
		var repeats: bool = bool(rule.get("repeat", true))
		if not repeats and _fired_one_shot_rule_ids.has(rule_id):
			continue
		# Every same-source rule sees trigger-time fact state. Earlier rules may
		# enqueue fact changes, but those changes remain later FIFO events and do
		# not alter conditions for later declarations in this handler.
		if not _conditions_match(rule, event):
			continue
		if not _execute_actions(rule):
			return false
		_match_count += 1
		_last_rule_id = StringName(rule_id)
		_last_event_name = event_name
		if not repeats:
			_fired_one_shot_rule_ids[rule_id] = true
	return true


func _conditions_match(rule: Dictionary, event: Dictionary) -> bool:
	var conditions: Array = rule.get("conditions", [])
	var payload: Dictionary = event.get("payload", {})
	for condition_value: Variant in conditions:
		var condition: Dictionary = condition_value
		var kind := StringName(str(condition.get("kind", "")))
		var key := StringName(str(condition.get("key", "")).strip_edges())
		var expected: Variant = condition.get("value")
		match kind:
			CONDITION_EVENT_PAYLOAD_EQUALS:
				if (
					not payload.has(String(key))
					and not payload.has(key)
				):
					return false
				var actual: Variant = (
					payload[key]
					if payload.has(key)
					else payload[String(key)]
				)
				if actual != expected:
					return false
			CONDITION_FACT_EQUALS:
				if (
					_mission_facts == null
					or not bool(_mission_facts.call("has_fact", key))
					or _mission_facts.call("get_value", key, null) != expected
				):
					return false
			_:
				_last_error = "Unsupported mission-rule condition '%s'." % kind
				return false
	return true


func _execute_actions(rule: Dictionary) -> bool:
	var actions: Array = rule.get("actions", [])
	for action_value: Variant in actions:
		var action: Dictionary = action_value
		var kind := StringName(str(action.get("kind", "")))
		match kind:
			ACTION_SET_FACT:
				var key := StringName(
					str(action.get("key", "")).strip_edges()
				)
				if not bool(_session.call(
					"queue_mission_fact_set",
					key,
					action.get("value")
				)):
					_last_error = (
						"Mission rule '%s' could not queue set_fact '%s'."
						% [str(rule.get("rule_id", "")), key]
					)
					return false
			ACTION_EMIT_EVENT:
				var event_name := StringName(
					str(action.get("event_name", "")).strip_edges()
				)
				var payload: Dictionary = (
					action.get("payload", {}) as Dictionary
				)
				if not bool(_event_bus.call(
					"emit",
					event_name,
					payload.duplicate(true)
				)):
					_last_error = (
						"Mission rule '%s' could not emit '%s'."
						% [str(rule.get("rule_id", "")), event_name]
					)
					return false
			_:
				_last_error = "Unsupported mission-rule action '%s'." % kind
				return false
		_action_count += 1
	return true


static func _validate_condition(
	condition_value: Variant,
	prefix: String,
	fact_types: Dictionary,
	errors: PackedStringArray
) -> void:
	if typeof(condition_value) != TYPE_DICTIONARY:
		errors.append("%s must be a Dictionary." % prefix)
		return
	var condition: Dictionary = condition_value
	var kind := StringName(str(condition.get("kind", "")).strip_edges())
	match kind:
		CONDITION_EVENT_PAYLOAD_EQUALS:
			if (
				condition.size() != 3
				or not condition.has("key")
				or not condition.has("value")
			):
				errors.append(
					"%s event_payload_equals requires exactly kind, key, and value."
					% prefix
				)
				return
			if str(condition.get("key", "")).strip_edges().is_empty():
				errors.append("%s key must not be empty." % prefix)
			if not _is_detached_rule_value(condition.get("value")):
				errors.append("%s value must be detached rule data." % prefix)
		CONDITION_FACT_EQUALS:
			_validate_fact_literal(
				condition,
				prefix,
				fact_types,
				errors,
				"fact_equals"
			)
		_:
			errors.append(
				"%s condition kind '%s' is unsupported."
				% [prefix, kind]
			)


static func _validate_action(
	action_value: Variant,
	prefix: String,
	fact_types: Dictionary,
	errors: PackedStringArray
) -> void:
	if typeof(action_value) != TYPE_DICTIONARY:
		errors.append("%s must be a Dictionary." % prefix)
		return
	var action: Dictionary = action_value
	var kind := StringName(str(action.get("kind", "")).strip_edges())
	match kind:
		ACTION_SET_FACT:
			_validate_fact_literal(
				action,
				prefix,
				fact_types,
				errors,
				"set_fact"
			)
		ACTION_EMIT_EVENT:
			if (
				action.size() != 3
				or not action.has("event_name")
				or not action.has("payload")
			):
				errors.append(
					"%s emit_event requires exactly kind, event_name, and payload."
					% prefix
				)
				return
			if str(action.get("event_name", "")).strip_edges().is_empty():
				errors.append("%s event_name must not be empty." % prefix)
			var payload_value: Variant = action.get("payload")
			if (
				typeof(payload_value) != TYPE_DICTIONARY
				or not _is_detached_rule_value(payload_value)
			):
				errors.append("%s payload must be a detached Dictionary." % prefix)
		_:
			errors.append(
				"%s action kind '%s' is unsupported."
				% [prefix, kind]
			)


static func _validate_fact_literal(
	entry: Dictionary,
	prefix: String,
	fact_types: Dictionary,
	errors: PackedStringArray,
	kind_label: String
) -> void:
	if (
		entry.size() != 3
		or not entry.has("key")
		or not entry.has("value")
	):
		errors.append(
			"%s %s requires exactly kind, key, and value."
			% [prefix, kind_label]
		)
		return
	var key: String = str(entry.get("key", "")).strip_edges()
	if key.is_empty():
		errors.append("%s key must not be empty." % prefix)
		return
	if not fact_types.has(key):
		errors.append("%s references unknown mission fact '%s'." % [prefix, key])
		return
	var fact_type := StringName(str(fact_types[key]))
	if not _value_matches_fact_type(entry.get("value"), fact_type):
		errors.append(
			"%s value does not match mission fact '%s' type '%s'."
			% [prefix, key, fact_type]
		)


static func _fact_type_lookup(
	fact_declarations: Array[Dictionary]
) -> Dictionary:
	var result: Dictionary = {}
	for declaration: Dictionary in fact_declarations:
		var key: String = str(declaration.get("key", "")).strip_edges()
		if key.is_empty():
			continue
		result[key] = StringName(
			str(declaration.get("type", "")).strip_edges()
		)
	return result


static func _value_matches_fact_type(
	value: Variant,
	fact_type: StringName
) -> bool:
	match fact_type:
		MissionFacts.VALUE_TYPE_BOOL:
			return typeof(value) == TYPE_BOOL
		MissionFacts.VALUE_TYPE_INT:
			return typeof(value) == TYPE_INT
		MissionFacts.VALUE_TYPE_FLOAT:
			return typeof(value) == TYPE_FLOAT
		MissionFacts.VALUE_TYPE_STRING:
			return typeof(value) == TYPE_STRING
	return false


static func _is_detached_rule_value(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_COLOR:
			return true
		TYPE_ARRAY:
			for child: Variant in value:
				if not _is_detached_rule_value(child):
					return false
			return true
		TYPE_DICTIONARY:
			for key_value: Variant in value.keys():
				if (
					typeof(key_value) != TYPE_STRING
					and typeof(key_value) != TYPE_STRING_NAME
				):
					return false
				if not _is_detached_rule_value(value[key_value]):
					return false
			return true
	return false
