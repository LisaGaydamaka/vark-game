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


func _on_body_entered(body: Node) -> void:
	queue_for_body(body)


func _find_world_session() -> Node:
	var cursor: Node = get_parent()
	while cursor != null:
		if cursor.has_method("queue_semantic_gameplay_event"):
			return cursor
		cursor = cursor.get_parent()
	return null
