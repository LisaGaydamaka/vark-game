class_name VarkMissionEventBus
extends RefCounted


const GAMEPLAY_SOUND: StringName = &"gameplay.sound"
const PICKUP_COLLECTED: StringName = &"pickup.collected"
const CONTAINER_STATE_CHANGED: StringName = &"container.state_changed"
const DOOR_STATE_CHANGED: StringName = &"door.state_changed"
const DOOR_RESTRICTION_CHANGED: StringName = &"door.restriction_changed"
const DOOR_ACCESS_DENIED: StringName = &"door.access_denied"
const LIGHT_STATE_CHANGED: StringName = &"light.state_changed"
const SWITCH_USED: StringName = &"switch.used"
const BREAKABLE_BROKEN: StringName = &"breakable.broken"
const NPC_LOCAL_WARNING: StringName = &"npc.local_warning"
const NPC_ALARM_RAISED: StringName = &"npc.alarm_raised"
const OBJECTIVE_COMPLETE_REQUESTED: StringName = &"objective.complete_requested"
const MISSION_EXIT_REQUESTED: StringName = &"mission.exit_requested"
const MISSION_COMPLETED: StringName = &"mission.completed"
const MISSION_FACT_CHANGED: StringName = &"mission.fact_changed"


var _session: Node = null
var _session_id: int = 0


func bind_to_session(session: Node, session_id: int) -> bool:
	if (
		session == null
		or not is_instance_valid(session)
		or session_id <= 0
		or not session.has_method("queue_semantic_gameplay_event")
		or not session.has_method("register_semantic_event_handler")
		or not session.has_method("unregister_semantic_event_handler")
		or not session.has_method("get_recent_semantic_event_trace")
	):
		return false
	_session = session
	_session_id = session_id
	return true


func invalidate() -> void:
	_session = null
	_session_id = 0


func is_active() -> bool:
	return (
		_session != null
		and is_instance_valid(_session)
		and _session_id > 0
		and int(_session.get("session_id")) == _session_id
	)


func subscribe(event_name: StringName, handler: Callable) -> bool:
	if not is_active() or event_name.is_empty() or not handler.is_valid():
		return false
	return bool(_session.call(
		"register_semantic_event_handler",
		event_name,
		handler
	))


func unsubscribe(event_name: StringName, handler: Callable) -> bool:
	if not is_active() or event_name.is_empty() or not handler.is_valid():
		return false
	return bool(_session.call(
		"unregister_semantic_event_handler",
		event_name,
		handler
	))


func emit(event_name: StringName, payload: Dictionary = {}) -> bool:
	if not is_active() or event_name.is_empty():
		return false
	return bool(_session.call(
		"queue_semantic_gameplay_event",
		_session_id,
		event_name,
		payload
	))


func get_recent_trace() -> Array[Dictionary]:
	if not is_active():
		return []
	var trace: Variant = _session.call("get_recent_semantic_event_trace")
	if typeof(trace) != TYPE_ARRAY:
		return []
	var result: Array[Dictionary] = []
	for entry: Variant in trace:
		if typeof(entry) == TYPE_DICTIONARY:
			result.append((entry as Dictionary).duplicate(true))
	return result


func get_known_event_names() -> PackedStringArray:
	return PackedStringArray([
		str(GAMEPLAY_SOUND),
		str(PICKUP_COLLECTED),
		str(CONTAINER_STATE_CHANGED),
		str(DOOR_STATE_CHANGED),
		str(DOOR_RESTRICTION_CHANGED),
		str(DOOR_ACCESS_DENIED),
		str(LIGHT_STATE_CHANGED),
		str(SWITCH_USED),
		str(BREAKABLE_BROKEN),
		str(NPC_LOCAL_WARNING),
		str(NPC_ALARM_RAISED),
		str(OBJECTIVE_COMPLETE_REQUESTED),
		str(MISSION_EXIT_REQUESTED),
		str(MISSION_COMPLETED),
		str(MISSION_FACT_CHANGED),
	])
