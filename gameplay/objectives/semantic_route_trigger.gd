class_name VarkSemanticRouteTrigger
extends Area3D


@export var event_name: StringName = &""
@export var payload_key: StringName = &""
@export var payload_id: StringName = &""
@export var one_shot_on_queue: bool = false

var _world_session: Node = null
var _armed: bool = true
var _queued_count: int = 0


func _ready() -> void:
	_world_session = _find_world_session()
	body_entered.connect(_on_body_entered)
	if event_name.is_empty() or payload_key.is_empty() or payload_id.is_empty():
		push_error("VarkSemanticRouteTrigger requires event_name, payload_key, and payload_id.")


func queue_for_body(body: Node) -> bool:
	if not _armed:
		return false
	if body == null or not body.is_in_group(&"vark_player"):
		return false
	if _world_session == null or not is_instance_valid(_world_session):
		return false

	var payload: Dictionary = {}
	payload[String(payload_key)] = payload_id
	var queued: bool = bool(_world_session.call(
		"queue_semantic_gameplay_event",
		int(_world_session.get("session_id")),
		event_name,
		payload
	))
	if not queued:
		return false

	_queued_count += 1
	if one_shot_on_queue:
		_armed = false
	return true


func get_debug_summary() -> Dictionary:
	return {
		"event_name": event_name,
		"payload_key": payload_key,
		"payload_id": payload_id,
		"one_shot_on_queue": one_shot_on_queue,
		"armed": _armed,
		"queued_count": _queued_count,
	}


func get_semantic_save_id() -> String:
	return "route_trigger:%s:%s:%s" % [
		event_name,
		payload_key,
		payload_id,
	]


func capture_semantic_state() -> Dictionary:
	return {
		"event_name": event_name,
		"payload_key": payload_key,
		"payload_id": payload_id,
		"one_shot_on_queue": one_shot_on_queue,
		"armed": _armed,
		"queued_count": _queued_count,
	}


func apply_semantic_state(snapshot: Dictionary) -> bool:
	if (
		_world_session != null
		and is_instance_valid(_world_session)
		and int(_world_session.get("state")) == WorldSession.State.PLAYING
	):
		return false
	if snapshot.size() != 6:
		return false
	if (
		snapshot.get("event_name", &"") != event_name
		or snapshot.get("payload_key", &"") != payload_key
		or snapshot.get("payload_id", &"") != payload_id
		or snapshot.get("one_shot_on_queue", false) != one_shot_on_queue
		or typeof(snapshot.get("armed", null)) != TYPE_BOOL
		or typeof(snapshot.get("queued_count", null)) != TYPE_INT
		or int(snapshot.get("queued_count", -1)) < 0
	):
		return false
	_armed = bool(snapshot["armed"])
	_queued_count = int(snapshot["queued_count"])
	return true


func reconcile_after_restore() -> bool:
	return true


func after_restore() -> bool:
	return true


func _on_body_entered(body: Node) -> void:
	queue_for_body(body)


func _find_world_session() -> Node:
	var cursor: Node = get_parent()
	while cursor != null:
		if cursor.has_method("queue_semantic_gameplay_event"):
			return cursor
		cursor = cursor.get_parent()
	return null
