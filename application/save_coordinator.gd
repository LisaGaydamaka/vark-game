class_name VarkSaveCoordinator
extends Node


const DEFAULT_SLOT: StringName = &"quicksave"
const CAPTURE_PHYSICS_PRIORITY: int = 1100

var application: Node = null

var _next_generation: int = 1
var _requests: Dictionary = {}
var _pending_generations: Array[int] = []
var _captured_generations: Array[int] = []
var _latest_requested_generation_by_slot: Dictionary = {}
var _committed_slots: Dictionary = {}
var _last_error: String = ""


func _init() -> void:
	process_physics_priority = CAPTURE_PHYSICS_PRIORITY


func bind_application(owner: Node) -> void:
	application = owner


func request_save(slot: StringName = DEFAULT_SLOT) -> int:
	_last_error = ""
	if application == null or not is_instance_valid(application):
		_last_error = "Save coordinator has no valid application owner."
		return 0
	if str(slot).strip_edges().is_empty():
		_last_error = "Save slot must not be empty."
		return 0

	var session := application.get("current_session") as Node
	if session == null or not is_instance_valid(session):
		_last_error = "There is no current WorldSession to save."
		return 0
	var session_state: int = int(session.get("state"))
	if (
		session_state != WorldSession.State.PLAYING
		and session_state != WorldSession.State.PAUSED
	):
		_last_error = "Current WorldSession is not in a save-requestable gameplay state."
		return 0

	var generation: int = _next_generation
	_next_generation += 1
	var source_session_id: int = int(session.get("session_id"))
	var target_boundary: int = int(
		session.call("get_stable_gameplay_boundary_serial")
	) + 1
	_requests[generation] = {
		"generation": generation,
		"slot": slot,
		"source_session_id": source_session_id,
		"target_boundary": target_boundary,
		"status": &"pending",
		"session": session,
		"snapshot": {},
		"error": "",
	}
	_pending_generations.append(generation)
	_latest_requested_generation_by_slot[slot] = generation
	return generation


func cancel_pending_for_session(
	source_session_id: int,
	reason: String = "Source WorldSession stopped before save capture."
) -> int:
	if source_session_id <= 0:
		return 0
	var cancelled: int = 0
	var remaining: Array[int] = []
	for generation: int in _pending_generations:
		var request: Dictionary = _requests.get(generation, {})
		if (
			request.get("status", &"") == &"pending"
			and int(request.get("source_session_id", 0)) == source_session_id
		):
			request["status"] = &"cancelled"
			request["error"] = reason
			request.erase("session")
			_requests[generation] = request
			cancelled += 1
			continue
		remaining.append(generation)
	_pending_generations = remaining
	return cancelled


func get_request_status(generation: int) -> Dictionary:
	var request: Dictionary = _requests.get(generation, {})
	if request.is_empty():
		return {
			"generation": generation,
			"status": &"unknown",
			"error": "Unknown save generation.",
		}
	return {
		"generation": generation,
		"slot": request.get("slot", &""),
		"source_session_id": int(request.get("source_session_id", 0)),
		"target_boundary": int(request.get("target_boundary", 0)),
		"status": request.get("status", &""),
		"error": str(request.get("error", "")),
	}


func get_request_snapshot(generation: int) -> Dictionary:
	var request: Dictionary = _requests.get(generation, {})
	var snapshot: Dictionary = request.get("snapshot", {})
	return snapshot.duplicate(true)


func get_latest_committed_generation(
	slot: StringName = DEFAULT_SLOT
) -> int:
	var committed: Dictionary = _committed_slots.get(slot, {})
	return int(committed.get("generation", 0))


func get_latest_committed_snapshot(
	slot: StringName = DEFAULT_SLOT
) -> Dictionary:
	var committed: Dictionary = _committed_slots.get(slot, {})
	var snapshot: Dictionary = committed.get("snapshot", {})
	return snapshot.duplicate(true)


func get_last_error() -> String:
	return _last_error


func validate_snapshot(snapshot: Dictionary) -> bool:
	if snapshot.is_empty() or not _is_detached_value(snapshot):
		return false
	if (
		typeof(snapshot.get("generation", null)) != TYPE_INT
		or int(snapshot.get("generation", 0)) <= 0
		or typeof(snapshot.get("slot", null)) != TYPE_STRING_NAME
		or str(snapshot.get("slot", &"")).strip_edges().is_empty()
	):
		return false

	var session_snapshot: Dictionary = snapshot.get("session", {})
	if not _is_valid_session_envelope(session_snapshot):
		return false

	var view_pose: Dictionary = snapshot.get("player_view_pose", {})
	return _is_valid_view_pose(view_pose)


func _physics_process(_delta: float) -> void:
	if _pending_generations.is_empty():
		return

	var remaining: Array[int] = []
	for generation: int in _pending_generations:
		var request: Dictionary = _requests.get(generation, {})
		if request.get("status", &"") != &"pending":
			continue

		var session := request.get("session") as Node
		if session == null or not is_instance_valid(session):
			_cancel_request(
				generation,
				"Source WorldSession disappeared before save capture."
			)
			continue
		if int(session.get("session_id")) != int(
			request.get("source_session_id", 0)
		):
			_cancel_request(
				generation,
				"Save request no longer belongs to its source WorldSession."
			)
			continue

		var session_state: int = int(session.get("state"))
		if session_state == WorldSession.State.PAUSED:
			remaining.append(generation)
			continue
		if session_state != WorldSession.State.PLAYING:
			_cancel_request(
				generation,
				"Source WorldSession stopped before save capture."
			)
			continue

		var current_boundary: int = int(
			session.call("get_stable_gameplay_boundary_serial")
		)
		if current_boundary < int(request.get("target_boundary", 0)):
			remaining.append(generation)
			continue

		var session_snapshot: Dictionary = session.call(
			"capture_save_envelope"
		)
		var view_pose: Dictionary = application.call(
			"get_current_view_pose"
		)
		var snapshot := {
			"generation": generation,
			"slot": request.get("slot", DEFAULT_SLOT),
			"session": session_snapshot.duplicate(true),
			"player_view_pose": view_pose.duplicate(true),
		}
		if not validate_snapshot(snapshot):
			_cancel_request(
				generation,
				"Stable-boundary snapshot capture produced invalid detached data."
			)
			continue

		request["snapshot"] = snapshot.duplicate(true)
		request["status"] = &"captured"
		request["error"] = ""
		request.erase("session")
		_requests[generation] = request
		_captured_generations.append(generation)

	_pending_generations = remaining


func _process(_delta: float) -> void:
	if _captured_generations.is_empty():
		return

	var captured_now: Array[int] = _captured_generations
	_captured_generations = []
	for generation: int in captured_now:
		_commit_captured_generation(generation)


func _commit_captured_generation(generation: int) -> void:
	var request: Dictionary = _requests.get(generation, {})
	if request.get("status", &"") != &"captured":
		return

	var slot: StringName = request.get("slot", DEFAULT_SLOT)
	var latest_requested: int = int(
		_latest_requested_generation_by_slot.get(slot, 0)
	)
	if generation != latest_requested:
		request["status"] = &"superseded"
		request["error"] = (
			"Save generation %d was superseded by newer generation %d."
			% [generation, latest_requested]
		)
		_requests[generation] = request
		return

	var snapshot: Dictionary = request.get("snapshot", {})
	if not validate_snapshot(snapshot):
		request["status"] = &"failed"
		request["error"] = "Captured snapshot became invalid before commit."
		_requests[generation] = request
		return

	_committed_slots[slot] = {
		"generation": generation,
		"snapshot": snapshot.duplicate(true),
	}
	request["status"] = &"committed"
	request["error"] = ""
	_requests[generation] = request


func _cancel_request(generation: int, reason: String) -> void:
	var request: Dictionary = _requests.get(generation, {})
	if request.is_empty() or request.get("status", &"") != &"pending":
		return
	request["status"] = &"cancelled"
	request["error"] = reason
	request.erase("session")
	_requests[generation] = request


func _is_valid_session_envelope(envelope: Dictionary) -> bool:
	if envelope.is_empty() or not _is_detached_value(envelope):
		return false
	if (
		typeof(envelope.get("source_session_id", null)) != TYPE_INT
		or int(envelope.get("source_session_id", 0)) <= 0
		or typeof(envelope.get("stable_boundary_serial", null)) != TYPE_INT
		or int(envelope.get("stable_boundary_serial", 0)) <= 0
		or typeof(envelope.get("world_scene_path", null)) != TYPE_STRING
		or str(envelope.get("world_scene_path", "")).is_empty()
		or typeof(envelope.get("mission_definition_path", null)) != TYPE_STRING
	):
		return false
	var gameplay_time_value: Variant = envelope.get(
		"gameplay_time_seconds",
		null
	)
	if (
		typeof(gameplay_time_value) != TYPE_FLOAT
		and typeof(gameplay_time_value) != TYPE_INT
	):
		return false
	var gameplay_time: float = float(gameplay_time_value)
	return is_finite(gameplay_time) and gameplay_time >= 0.0


func _is_valid_view_pose(view_pose: Dictionary) -> bool:
	if view_pose.is_empty() or not _is_detached_value(view_pose):
		return false
	if typeof(view_pose.get("view_transform", null)) != TYPE_TRANSFORM3D:
		return false
	for key: String in ["body_yaw", "head_pitch", "head_yaw"]:
		var value: Variant = view_pose.get(key, null)
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return false
		if not is_finite(float(value)):
			return false
	return true


func _is_detached_value(value: Variant, depth: int = 0) -> bool:
	if depth > 32:
		return false
	match typeof(value):
		TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return false
		TYPE_ARRAY:
			for item: Variant in value:
				if not _is_detached_value(item, depth + 1):
					return false
		TYPE_DICTIONARY:
			for key: Variant in value.keys():
				if not _is_detached_value(key, depth + 1):
					return false
				if not _is_detached_value(value[key], depth + 1):
					return false
	return true
