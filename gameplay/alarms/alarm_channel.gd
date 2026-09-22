class_name VarkAlarmChannel
extends Node


const ALARM_EVENT_NAME: StringName = &"npc.alarm_raised"
const WORLD_SESSION_STATE_PLAYING: int = 4

@export var alarm_id: StringName = &""
@export var audience_faction_id: StringName = &""

var _world_session: Node = null
var _active: bool = false
var _evidence_position: Vector3 = Vector3.ZERO
var _source_actor_id: String = ""
var _raise_serial: int = 0
var _last_error: String = ""


func _ready() -> void:
	_world_session = _find_world_session()
	if alarm_id.is_empty() or audience_faction_id.is_empty():
		_last_error = "Alarm channel requires non-empty alarm and audience faction IDs."
		push_error(_last_error)
	elif _world_session == null:
		_last_error = "Alarm channel requires a WorldSession ancestor."
		push_error(_last_error)


func raise_alarm(
	evidence_position: Vector3,
	source_actor_id: String = ""
) -> bool:
	if not _is_playing_session() or not _is_finite_vector(evidence_position):
		return false
	if alarm_id.is_empty() or audience_faction_id.is_empty():
		return false
	var next_serial: int = _raise_serial + 1
	var payload := {
		"alarm_id": alarm_id,
		"audience_faction_id": audience_faction_id,
		"source_actor_id": source_actor_id.strip_edges(),
		"evidence_position": evidence_position,
		"serial": next_serial,
	}
	var queued: bool = bool(_world_session.call(
		"queue_semantic_gameplay_event",
		int(_world_session.get("session_id")),
		ALARM_EVENT_NAME,
		payload
	))
	if not queued:
		_last_error = "Alarm channel could not queue alarm propagation."
		return false
	_active = true
	_evidence_position = evidence_position
	_source_actor_id = source_actor_id.strip_edges()
	_raise_serial = next_serial
	return true


func clear_alarm() -> bool:
	if not _is_playing_session():
		return false
	_active = false
	_evidence_position = Vector3.ZERO
	_source_actor_id = ""
	return true


func get_semantic_save_id() -> String:
	if alarm_id.is_empty():
		return ""
	return "alarm_channel:%s" % str(alarm_id)


func capture_semantic_state() -> Dictionary:
	return {
		"alarm_id": alarm_id,
		"audience_faction_id": audience_faction_id,
		"active": _active,
		"evidence_position": _evidence_position,
		"source_actor_id": _source_actor_id,
		"raise_serial": _raise_serial,
	}


func apply_semantic_state(snapshot: Dictionary) -> bool:
	if _is_playing_session():
		return false
	if snapshot.size() != 6:
		return false
	if (
		snapshot.get("alarm_id", &"") != alarm_id
		or snapshot.get("audience_faction_id", &"") != audience_faction_id
		or typeof(snapshot.get("active", null)) != TYPE_BOOL
		or typeof(snapshot.get("evidence_position", null)) != TYPE_VECTOR3
		or typeof(snapshot.get("source_actor_id", null)) != TYPE_STRING
		or typeof(snapshot.get("raise_serial", null)) != TYPE_INT
	):
		return false
	var evidence_position: Vector3 = snapshot.get(
		"evidence_position",
		Vector3.ZERO
	)
	var serial: int = int(snapshot.get("raise_serial", -1))
	if not _is_finite_vector(evidence_position) or serial < 0:
		return false
	_active = bool(snapshot.get("active", false))
	_evidence_position = evidence_position
	_source_actor_id = str(snapshot.get("source_actor_id", "")).strip_edges()
	_raise_serial = serial
	return true


func reconcile_after_restore() -> bool:
	# Restoring an active alarm restores state only. It deliberately does not
	# re-emit the alarm event; loading a save must not become gameplay.
	return true


func get_debug_summary() -> Dictionary:
	return {
		"alarm_id": alarm_id,
		"audience_faction_id": audience_faction_id,
		"active": _active,
		"evidence_position": _evidence_position,
		"source_actor_id": _source_actor_id,
		"raise_serial": _raise_serial,
		"last_error": _last_error,
	}


func _is_playing_session() -> bool:
	return (
		_world_session != null
		and is_instance_valid(_world_session)
		and int(_world_session.get("state")) == WORLD_SESSION_STATE_PLAYING
	)


func _find_world_session() -> Node:
	var cursor: Node = get_parent()
	while cursor != null:
		if (
			cursor.has_method("queue_semantic_gameplay_event")
			and _has_property(cursor, &"session_id")
		):
			return cursor
		cursor = cursor.get_parent()
	return null


func _has_property(node: Object, property_name: StringName) -> bool:
	for property_info: Dictionary in node.get_property_list():
		if StringName(property_info.get("name", "")) == property_name:
			return true
	return false


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
