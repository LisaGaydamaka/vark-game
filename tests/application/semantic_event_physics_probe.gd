extends Node


var session: Node = null
var source_session_id: int = 0
var event_name: StringName = &""
var payload: Dictionary = {}
var attempted: bool = false
var accepted: bool = false


func configure(
	new_session: Node,
	new_source_session_id: int,
	new_event_name: StringName,
	new_payload: Dictionary = {}
) -> void:
	session = new_session
	source_session_id = new_source_session_id
	event_name = new_event_name
	payload = new_payload.duplicate(true)


func _physics_process(_delta: float) -> void:
	if attempted or session == null:
		return
	attempted = true
	accepted = bool(session.call(
		"queue_semantic_gameplay_event",
		source_session_id,
		event_name,
		payload
	))
