class_name VarkSimpleObjectiveState
extends Node


const OBJECTIVE_ACTIVATE_REQUEST_EVENT: StringName = &"objective.activate_requested"
const OBJECTIVE_COMPLETE_REQUEST_EVENT: StringName = &"objective.complete_requested"
const OBJECTIVE_FAIL_REQUEST_EVENT: StringName = &"objective.fail_requested"
const OBJECTIVE_STATE_CHANGED_EVENT: StringName = &"objective.state_changed"
const EXIT_REQUEST_EVENT: StringName = &"mission.exit_requested"
const MISSION_COMPLETED_EVENT: StringName = &"mission.completed"

const OBJECTIVE_INACTIVE: StringName = &"inactive"
const OBJECTIVE_ACTIVE: StringName = &"active"
const OBJECTIVE_COMPLETE: StringName = &"complete"
const OBJECTIVE_FAILED: StringName = &"failed"


@export var objective_id: StringName = &"objective.route"
@export var exit_id: StringName = &"exit.route"
@export var objective_text: String = "Reach the objective marker."
@export var status_label_path: NodePath = NodePath("../StatusLabel")
@export var objective_declarations: Array[Dictionary] = []

var _world_session: Node = null
var _status_label: Label3D = null
var _objective_definitions: Dictionary = {}
var _objective_states: Dictionary = {}
var _objective_order: Array[StringName] = []
var _mission_complete: bool = false
var _objective_activation_count: int = 0
var _objective_completion_count: int = 0
var _objective_failure_count: int = 0
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
	if not _configure_objectives():
		push_error(
			"VarkSimpleObjectiveState has invalid objective declarations."
		)
		_refresh_status()
		return

	var registrations: Array[Dictionary] = [
		{
			"name": OBJECTIVE_ACTIVATE_REQUEST_EVENT,
			"handler": Callable(self, "_on_objective_activate_requested"),
		},
		{
			"name": OBJECTIVE_COMPLETE_REQUEST_EVENT,
			"handler": Callable(self, "_on_objective_complete_requested"),
		},
		{
			"name": OBJECTIVE_FAIL_REQUEST_EVENT,
			"handler": Callable(self, "_on_objective_fail_requested"),
		},
		{
			"name": EXIT_REQUEST_EVENT,
			"handler": Callable(self, "_on_exit_requested"),
		},
	]
	for registration: Dictionary in registrations:
		if not bool(_world_session.call(
			"register_semantic_event_handler",
			registration.get("name", &""),
			registration.get("handler", Callable())
		)):
			push_error(
				"VarkSimpleObjectiveState could not register semantic handlers."
			)
			break
	_refresh_status()


func _exit_tree() -> void:
	if _world_session == null or not is_instance_valid(_world_session):
		return
	for registration: Dictionary in [
		{
			"name": OBJECTIVE_ACTIVATE_REQUEST_EVENT,
			"handler": Callable(self, "_on_objective_activate_requested"),
		},
		{
			"name": OBJECTIVE_COMPLETE_REQUEST_EVENT,
			"handler": Callable(self, "_on_objective_complete_requested"),
		},
		{
			"name": OBJECTIVE_FAIL_REQUEST_EVENT,
			"handler": Callable(self, "_on_objective_fail_requested"),
		},
		{
			"name": EXIT_REQUEST_EVENT,
			"handler": Callable(self, "_on_exit_requested"),
		},
	]:
		_world_session.call(
			"unregister_semantic_event_handler",
			registration.get("name", &""),
			registration.get("handler", Callable())
		)


func query_objective(query_id: StringName) -> Dictionary:
	if not _objective_definitions.has(query_id):
		return {
			"ok": false,
			"objective_id": query_id,
			"error": "Unknown objective_id.",
		}
	var definition: Dictionary = _objective_definitions[query_id]
	var objective_state: StringName = _objective_states.get(
		query_id,
		OBJECTIVE_INACTIVE
	)
	return {
		"ok": true,
		"objective_id": query_id,
		"text": str(definition.get("text", "")),
		"optional": bool(definition.get("optional", false)),
		"state": objective_state,
		"active": objective_state == OBJECTIVE_ACTIVE,
		"complete": objective_state == OBJECTIVE_COMPLETE,
		"failed": objective_state == OBJECTIVE_FAILED,
	}


func query_objectives() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for query_id: StringName in _objective_order:
		result.append(query_objective(query_id))
	return result


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
		"unlocked": _required_objectives_complete(),
		"required_failed": _required_objective_failed(),
		"mission_complete": _mission_complete,
		"attempt_count": _exit_attempt_count,
		"blocked_attempt_count": _blocked_exit_count,
	}


func get_debug_summary() -> Dictionary:
	return {
		"objectives": query_objectives(),
		"objective": query_objective(objective_id),
		"exit": query_exit(exit_id),
		"objective_activation_count": _objective_activation_count,
		"objective_completion_count": _objective_completion_count,
		"objective_failure_count": _objective_failure_count,
		"mission_completion_count": _mission_completion_count,
	}


func get_semantic_save_id() -> String:
	return "objective_state:%s:%s" % [objective_id, exit_id]


func capture_semantic_state() -> Dictionary:
	return {
		"objective_id": objective_id,
		"exit_id": exit_id,
		"objective_complete": _objective_is_complete(objective_id),
		"mission_complete": _mission_complete,
		"objective_completion_count": _objective_completion_count,
		"exit_attempt_count": _exit_attempt_count,
		"blocked_exit_count": _blocked_exit_count,
		"mission_completion_count": _mission_completion_count,
		"objective_states": _capture_objective_states(),
		"objective_activation_count": _objective_activation_count,
		"objective_failure_count": _objective_failure_count,
	}


func apply_semantic_state(snapshot: Dictionary) -> bool:
	if (
		_world_session != null
		and is_instance_valid(_world_session)
		and int(_world_session.get("state")) == WorldSession.State.PLAYING
	):
		return false
	if (
		snapshot.get("objective_id", &"") != objective_id
		or snapshot.get("exit_id", &"") != exit_id
	):
		return false
	for key: String in [
		"objective_complete",
		"mission_complete",
	]:
		if typeof(snapshot.get(key, null)) != TYPE_BOOL:
			return false
	for key: String in [
		"objective_completion_count",
		"exit_attempt_count",
		"blocked_exit_count",
		"mission_completion_count",
	]:
		if typeof(snapshot.get(key, null)) != TYPE_INT or int(snapshot[key]) < 0:
			return false

	var restored_states: Dictionary = {}
	var restored_activation_count: int = 0
	var restored_failure_count: int = 0
	if snapshot.size() == 8:
		restored_states = _initial_objective_states()
		restored_states[String(objective_id)] = (
			OBJECTIVE_COMPLETE
			if bool(snapshot.get("objective_complete", false))
			else OBJECTIVE_ACTIVE
		)
	elif snapshot.size() == 11:
		if (
			typeof(snapshot.get("objective_states", null)) != TYPE_DICTIONARY
			or typeof(snapshot.get("objective_activation_count", null)) != TYPE_INT
			or typeof(snapshot.get("objective_failure_count", null)) != TYPE_INT
			or int(snapshot.get("objective_activation_count", -1)) < 0
			or int(snapshot.get("objective_failure_count", -1)) < 0
		):
			return false
		restored_states = (
			snapshot.get("objective_states", {}) as Dictionary
		).duplicate(true)
		if not _validate_objective_state_snapshot(restored_states):
			return false
		restored_activation_count = int(snapshot["objective_activation_count"])
		restored_failure_count = int(snapshot["objective_failure_count"])
	else:
		return false

	var restored_mission_complete: bool = bool(snapshot["mission_complete"])
	if (
		restored_mission_complete
		and not _required_objectives_complete_for(restored_states)
	):
		return false
	if (
		bool(snapshot.get("objective_complete", false))
		!= (
			restored_states.get(String(objective_id), OBJECTIVE_INACTIVE)
			== OBJECTIVE_COMPLETE
		)
	):
		return false

	_apply_objective_state_snapshot(restored_states)
	_mission_complete = restored_mission_complete
	_objective_activation_count = restored_activation_count
	_objective_completion_count = int(snapshot["objective_completion_count"])
	_objective_failure_count = restored_failure_count
	_exit_attempt_count = int(snapshot["exit_attempt_count"])
	_blocked_exit_count = int(snapshot["blocked_exit_count"])
	_mission_completion_count = int(snapshot["mission_completion_count"])
	return true


func reconcile_after_restore() -> bool:
	_refresh_status()
	return true


func after_restore() -> bool:
	_refresh_status()
	return true


func _configure_objectives() -> bool:
	_objective_definitions.clear()
	_objective_states.clear()
	_objective_order.clear()

	var declarations: Array[Dictionary] = objective_declarations.duplicate(true)
	if declarations.is_empty():
		declarations.append({
			"objective_id": objective_id,
			"text": objective_text,
			"optional": false,
			"initial_state": OBJECTIVE_ACTIVE,
		})

	for declaration: Dictionary in declarations:
		if (
			declaration.size() != 4
			or not declaration.has("objective_id")
			or not declaration.has("text")
			or not declaration.has("optional")
			or not declaration.has("initial_state")
		):
			return false
		var configured_id := StringName(
			str(declaration.get("objective_id", "")).strip_edges()
		)
		var configured_text: String = str(declaration.get("text", "")).strip_edges()
		var optional_value: Variant = declaration.get("optional")
		var initial_state := StringName(
			str(declaration.get("initial_state", "")).strip_edges()
		)
		if (
			configured_id.is_empty()
			or configured_text.is_empty()
			or typeof(optional_value) != TYPE_BOOL
			or (
				initial_state != OBJECTIVE_INACTIVE
				and initial_state != OBJECTIVE_ACTIVE
			)
			or _objective_definitions.has(configured_id)
		):
			return false
		var normalized: Dictionary = {
			"objective_id": configured_id,
			"text": configured_text,
			"optional": bool(optional_value),
			"initial_state": initial_state,
		}
		_objective_definitions[configured_id] = normalized
		_objective_states[configured_id] = initial_state
		_objective_order.append(configured_id)

	if not _objective_definitions.has(objective_id):
		return false
	return true


func _initial_objective_states() -> Dictionary:
	var result: Dictionary = {}
	for query_id: StringName in _objective_order:
		var definition: Dictionary = _objective_definitions[query_id]
		result[String(query_id)] = definition.get(
			"initial_state",
			OBJECTIVE_INACTIVE
		)
	return result


func _capture_objective_states() -> Dictionary:
	var result: Dictionary = {}
	for query_id: StringName in _objective_order:
		result[String(query_id)] = _objective_states.get(
			query_id,
			OBJECTIVE_INACTIVE
		)
	return result


func _validate_objective_state_snapshot(states: Dictionary) -> bool:
	if states.size() != _objective_order.size():
		return false
	for query_id: StringName in _objective_order:
		var key: String = String(query_id)
		if not states.has(key):
			return false
		var state_value := StringName(str(states[key]))
		if not _is_valid_objective_state(state_value):
			return false
	for key_value: Variant in states.keys():
		if not _objective_definitions.has(StringName(str(key_value))):
			return false
	return true


func _apply_objective_state_snapshot(states: Dictionary) -> void:
	for query_id: StringName in _objective_order:
		_objective_states[query_id] = StringName(
			str(states.get(String(query_id), OBJECTIVE_INACTIVE))
		)


func _on_objective_activate_requested(event: Dictionary) -> bool:
	return _transition_from_event(event, OBJECTIVE_ACTIVE)


func _on_objective_complete_requested(event: Dictionary) -> bool:
	return _transition_from_event(event, OBJECTIVE_COMPLETE)


func _on_objective_fail_requested(event: Dictionary) -> bool:
	return _transition_from_event(event, OBJECTIVE_FAILED)


func _transition_from_event(event: Dictionary, target_state: StringName) -> bool:
	var payload: Dictionary = event.get("payload", {})
	var requested_id := StringName(
		str(payload.get("objective_id", "")).strip_edges()
	)
	if not _objective_definitions.has(requested_id):
		return true
	if _mission_complete:
		return true
	return _transition_objective(requested_id, target_state)


func _transition_objective(
	requested_id: StringName,
	target_state: StringName
) -> bool:
	var from_state: StringName = _objective_states.get(
		requested_id,
		OBJECTIVE_INACTIVE
	)
	if from_state == target_state:
		return true

	var valid: bool = (
		target_state == OBJECTIVE_ACTIVE
		and from_state == OBJECTIVE_INACTIVE
	) or (
		(target_state == OBJECTIVE_COMPLETE or target_state == OBJECTIVE_FAILED)
		and from_state == OBJECTIVE_ACTIVE
	)
	if not valid:
		return true

	_objective_states[requested_id] = target_state
	match target_state:
		OBJECTIVE_ACTIVE:
			_objective_activation_count += 1
		OBJECTIVE_COMPLETE:
			_objective_completion_count += 1
		OBJECTIVE_FAILED:
			_objective_failure_count += 1

	var definition: Dictionary = _objective_definitions[requested_id]
	var state_changed_queued: bool = bool(_world_session.call(
		"queue_semantic_gameplay_event",
		int(_world_session.get("session_id")),
		OBJECTIVE_STATE_CHANGED_EVENT,
		{
			"objective_id": requested_id,
			"from_state": from_state,
			"to_state": target_state,
			"optional": bool(definition.get("optional", false)),
		}
	))
	if not state_changed_queued:
		_objective_states[requested_id] = from_state
		match target_state:
			OBJECTIVE_ACTIVE:
				_objective_activation_count -= 1
			OBJECTIVE_COMPLETE:
				_objective_completion_count -= 1
			OBJECTIVE_FAILED:
				_objective_failure_count -= 1
		return false

	_refresh_status()
	return true


func _on_exit_requested(event: Dictionary) -> bool:
	var payload: Dictionary = event.get("payload", {})
	if payload.get("exit_id", &"") != exit_id:
		return true

	_exit_attempt_count += 1
	if not _required_objectives_complete():
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


func _required_objectives_complete() -> bool:
	return _required_objectives_complete_for(_capture_objective_states())


func _required_objectives_complete_for(states: Dictionary) -> bool:
	for query_id: StringName in _objective_order:
		var definition: Dictionary = _objective_definitions[query_id]
		if bool(definition.get("optional", false)):
			continue
		if (
			StringName(str(states.get(String(query_id), OBJECTIVE_INACTIVE)))
			!= OBJECTIVE_COMPLETE
		):
			return false
	return true


func _required_objective_failed() -> bool:
	for query_id: StringName in _objective_order:
		var definition: Dictionary = _objective_definitions[query_id]
		if bool(definition.get("optional", false)):
			continue
		if _objective_states.get(query_id, OBJECTIVE_INACTIVE) == OBJECTIVE_FAILED:
			return true
	return false


func _objective_is_complete(query_id: StringName) -> bool:
	return _objective_states.get(query_id, OBJECTIVE_INACTIVE) == OBJECTIVE_COMPLETE


func _is_valid_objective_state(state_value: StringName) -> bool:
	return (
		state_value == OBJECTIVE_INACTIVE
		or state_value == OBJECTIVE_ACTIVE
		or state_value == OBJECTIVE_COMPLETE
		or state_value == OBJECTIVE_FAILED
	)


func _refresh_status() -> void:
	if _status_label == null:
		return

	var primary: Dictionary = query_objective(objective_id)
	var primary_state: StringName = primary.get("state", OBJECTIVE_INACTIVE)
	var lines: PackedStringArray = PackedStringArray()
	if _mission_complete:
		lines.append("ROUTE COMPLETE")
		lines.append("mission.completed emitted once")
	else:
		match primary_state:
			OBJECTIVE_COMPLETE:
				lines.append("OBJECTIVE COMPLETE")
			OBJECTIVE_FAILED:
				lines.append("OBJECTIVE FAILED")
			OBJECTIVE_INACTIVE:
				lines.append("OBJECTIVE INACTIVE")
			_:
				lines.append("OBJECTIVE ACTIVE")
		lines.append(str(primary.get("text", objective_text)))
		lines.append(
			"EXIT UNLOCKED"
			if _required_objectives_complete()
			else "EXIT LOCKED"
		)

	for query_id: StringName in _objective_order:
		if query_id == objective_id:
			continue
		var objective: Dictionary = query_objective(query_id)
		lines.append(
			"%s%s — %s"
			% [
				"OPTIONAL " if bool(objective.get("optional", false)) else "",
				str(objective.get("text", query_id)),
				str(objective.get("state", OBJECTIVE_INACTIVE)).to_upper(),
			]
		)
	_status_label.text = "\n".join(lines)


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
