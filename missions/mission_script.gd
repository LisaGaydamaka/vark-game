class_name VarkMissionScript
extends RefCounted


const OBJECTIVE_ACTIVATE_REQUESTED: StringName = &"objective.activate_requested"
const OBJECTIVE_COMPLETE_REQUESTED: StringName = &"objective.complete_requested"
const OBJECTIVE_FAIL_REQUESTED: StringName = &"objective.fail_requested"


var _session: Node = null
var _event_bus: RefCounted = null
var _session_id: int = 0


static func resolve(node: Node) -> RefCounted:
	var cursor: Node = node
	while cursor != null:
		if cursor.has_method("get_mission_script"):
			var value: Variant = cursor.call("get_mission_script")
			if value is RefCounted:
				var api := value as RefCounted
				if (
					api != null
					and api.has_method("is_active")
					and bool(api.call("is_active"))
				):
					return api
		cursor = cursor.get_parent()
	return null


func bind_to_session(
	session: Node,
	session_id: int,
	event_bus: RefCounted
) -> bool:
	invalidate()
	if (
		session == null
		or not is_instance_valid(session)
		or session_id <= 0
		or event_bus == null
		or not event_bus.has_method("is_active")
		or not event_bus.has_method("emit")
		or not session.has_method("get_gameplay_time_seconds")
		or not session.has_method("get_mission_run_summary")
		or not session.has_method("query_mission_fact")
		or not session.has_method("query_mission_objective")
		or not session.has_method("query_mission_objectives")
		or not session.has_method("query_mission_exit")
		or not session.has_method("queue_mission_fact_set")
	):
		return false
	_session = session
	_session_id = session_id
	_event_bus = event_bus
	return true


func invalidate() -> void:
	_session = null
	_event_bus = null
	_session_id = 0


func is_active() -> bool:
	return (
		_session != null
		and is_instance_valid(_session)
		and _session_id > 0
		and int(_session.get("session_id")) == _session_id
		and _event_bus != null
		and bool(_event_bus.call("is_active"))
	)


func get_event_bus() -> RefCounted:
	if not is_active():
		return null
	return _event_bus


func get_gameplay_time_seconds() -> float:
	if not is_active():
		return 0.0
	return float(_session.call("get_gameplay_time_seconds"))


func get_run_summary() -> Dictionary:
	if not is_active():
		return {}
	var value: Variant = _session.call("get_mission_run_summary")
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return (value as Dictionary).duplicate(true)


func query_fact(key: StringName) -> Dictionary:
	if not is_active():
		return {
			"ok": false,
			"key": key,
			"error": "Mission script API is inactive.",
		}
	var value: Variant = _session.call("query_mission_fact", key)
	if typeof(value) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"key": key,
			"error": "Mission fact query returned invalid data.",
		}
	return (value as Dictionary).duplicate(true)


func get_fact(key: StringName, fallback: Variant = null) -> Variant:
	var result: Dictionary = query_fact(key)
	if not bool(result.get("ok", false)):
		return fallback
	return result.get("value", fallback)


func query_objective(objective_id: StringName) -> Dictionary:
	if not is_active():
		return {
			"ok": false,
			"objective_id": objective_id,
			"error": "Mission script API is inactive.",
		}
	var value: Variant = _session.call("query_mission_objective", objective_id)
	if typeof(value) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"objective_id": objective_id,
			"error": "Mission objective query returned invalid data.",
		}
	return (value as Dictionary).duplicate(true)


func query_objectives() -> Array[Dictionary]:
	if not is_active():
		return []
	var value: Variant = _session.call("query_mission_objectives")
	if typeof(value) != TYPE_ARRAY:
		return []
	var result: Array[Dictionary] = []
	for entry: Variant in value:
		if typeof(entry) != TYPE_DICTIONARY:
			return []
		result.append((entry as Dictionary).duplicate(true))
	return result


func query_exit(exit_id: StringName) -> Dictionary:
	if not is_active():
		return {
			"ok": false,
			"exit_id": exit_id,
			"error": "Mission script API is inactive.",
		}
	var value: Variant = _session.call("query_mission_exit", exit_id)
	if typeof(value) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"exit_id": exit_id,
			"error": "Mission exit query returned invalid data.",
		}
	return (value as Dictionary).duplicate(true)


func set_fact(key: StringName, value: Variant) -> bool:
	if not is_active():
		return false
	return bool(_session.call("queue_mission_fact_set", key, value))


func emit_event(event_name: StringName, payload: Dictionary = {}) -> bool:
	if not is_active() or event_name.is_empty():
		return false
	return bool(_event_bus.call("emit", event_name, payload))


func activate_objective(objective_id: StringName) -> bool:
	return _request_objective(OBJECTIVE_ACTIVATE_REQUESTED, objective_id)


func complete_objective(objective_id: StringName) -> bool:
	return _request_objective(OBJECTIVE_COMPLETE_REQUESTED, objective_id)


func fail_objective(objective_id: StringName) -> bool:
	return _request_objective(OBJECTIVE_FAIL_REQUESTED, objective_id)


func _request_objective(
	event_name: StringName,
	objective_id: StringName
) -> bool:
	if objective_id.is_empty():
		return false
	var current: Dictionary = query_objective(objective_id)
	if not bool(current.get("ok", false)):
		return false
	return emit_event(event_name, {"objective_id": objective_id})
