class_name VarkSimpleObjectiveState
extends Node


const OBJECTIVE_COMPLETE_REQUEST_EVENT: StringName = &"objective.complete_requested"
const EXIT_REQUEST_EVENT: StringName = &"mission.exit_requested"
const MISSION_COMPLETED_EVENT: StringName = &"mission.completed"

const OBJECTIVE_ACTIVE: StringName = &"active"
const OBJECTIVE_COMPLETE: StringName = &"complete"


@export var objective_id: StringName = &"objective.route"
@export var exit_id: StringName = &"exit.route"
@export var objective_text: String = "Reach the objective marker."
@export var status_label_path: NodePath = NodePath("../StatusLabel")

var _world_session: Node = null
var _status_label: Label3D = null
var _objective_complete: bool = false
var _mission_complete: bool = false
var _objective_completion_count: int = 0
var _exit_attempt_count: int = 0
var _blocked_exit_count: int = 0
var _mission_completion_count: int = 0


func _ready() -> void:
	_world_session = _find_world_session()
	_status_label = get_node_or_null(status_label_path) as Label3D
	if _world_session == null:
		push_error("VarkSimpleObjectiveState requires a WorldSession ancestor.")
		_refresh_status()
		return
	if objective_id.is_empty() or exit_id.is_empty():
		push_error("VarkSimpleObjectiveState requires non-empty objective_id and exit_id.")
		_refresh_status()
		return

	var objective_registered: bool = bool(_world_session.call(
		"register_semantic_event_handler",
		OBJECTIVE_COMPLETE_REQUEST_EVENT,
		Callable(self, "_on_objective_complete_requested")
	))
	var exit_registered: bool = bool(_world_session.call(
		"register_semantic_event_handler",
		EXIT_REQUEST_EVENT,
		Callable(self, "_on_exit_requested")
	))
	if not objective_registered or not exit_registered:
		push_error("VarkSimpleObjectiveState could not register semantic handlers.")
	_refresh_status()


func _exit_tree() -> void:
	if _world_session == null or not is_instance_valid(_world_session):
		return
	_world_session.call(
		"unregister_semantic_event_handler",
		OBJECTIVE_COMPLETE_REQUEST_EVENT,
		Callable(self, "_on_objective_complete_requested")
	)
	_world_session.call(
		"unregister_semantic_event_handler",
		EXIT_REQUEST_EVENT,
		Callable(self, "_on_exit_requested")
	)


func query_objective(query_id: StringName) -> Dictionary:
	if query_id != objective_id:
		return {
			"ok": false,
			"objective_id": query_id,
			"error": "Unknown objective_id.",
		}
	return {
		"ok": true,
		"objective_id": objective_id,
		"text": objective_text,
		"state": OBJECTIVE_COMPLETE if _objective_complete else OBJECTIVE_ACTIVE,
		"complete": _objective_complete,
	}


func query_exit(query_id: StringName) -> Dictionary:
	if query_id != exit_id:
		return {
			"ok": false,
			"exit_id": query_id,
			"error": "Unknown exit_id.",
		}
	return {
		"ok": true,
		"exit_id": exit_id,
		"unlocked": _objective_complete,
		"mission_complete": _mission_complete,
		"attempt_count": _exit_attempt_count,
		"blocked_attempt_count": _blocked_exit_count,
	}


func get_debug_summary() -> Dictionary:
	return {
		"objective": query_objective(objective_id),
		"exit": query_exit(exit_id),
		"objective_completion_count": _objective_completion_count,
		"mission_completion_count": _mission_completion_count,
	}


func _on_objective_complete_requested(event: Dictionary) -> bool:
	var payload: Dictionary = event.get("payload", {})
	if payload.get("objective_id", &"") != objective_id:
		return true
	if _mission_complete:
		return true
	if not _objective_complete:
		_objective_complete = true
		_objective_completion_count += 1
	_refresh_status()
	return true


func _on_exit_requested(event: Dictionary) -> bool:
	var payload: Dictionary = event.get("payload", {})
	if payload.get("exit_id", &"") != exit_id:
		return true

	_exit_attempt_count += 1
	if not _objective_complete:
		_blocked_exit_count += 1
		_refresh_status()
		return true
	if _mission_complete:
		_refresh_status()
		return true

	_mission_complete = true
	_mission_completion_count += 1
	var completion_queued: bool = bool(_world_session.call(
		"queue_semantic_gameplay_event",
		int(_world_session.get("session_id")),
		MISSION_COMPLETED_EVENT,
		{
			"objective_id": objective_id,
			"exit_id": exit_id,
		}
	))
	if not completion_queued:
		_mission_complete = false
		_mission_completion_count -= 1
		return false

	_refresh_status()
	return true


func _refresh_status() -> void:
	if _status_label == null:
		return
	if _mission_complete:
		_status_label.text = "ROUTE COMPLETE\nmission.completed emitted once"
		return
	if _objective_complete:
		_status_label.text = "OBJECTIVE COMPLETE\nEXIT UNLOCKED — walk to EXIT"
		return
	_status_label.text = "OBJECTIVE ACTIVE\n%s\nEXIT LOCKED" % objective_text


func _find_world_session() -> Node:
	var cursor: Node = get_parent()
	while cursor != null:
		if (
			cursor.has_method("queue_semantic_gameplay_event")
			and cursor.has_method("register_semantic_event_handler")
		):
			return cursor
		cursor = cursor.get_parent()
	return null
