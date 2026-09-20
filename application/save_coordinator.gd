class_name VarkSaveCoordinator
extends Node


const SaveFormat = preload("res://application/save_format.gd")
const MISSION_DEFINITION_SCRIPT = preload("res://missions/mission_definition.gd")
const DEFAULT_SLOT: StringName = &"quicksave"
const CAPTURE_PHYSICS_PRIORITY: int = 1100
const DEFAULT_DURABLE_SAVE_DIRECTORY: String = "user://vark/saves"
const DURABLE_SAVE_EXTENSION: String = ".varksave"
const DURABLE_TEMP_SUFFIX: String = ".new"

@export var durable_save_directory: String = DEFAULT_DURABLE_SAVE_DIRECTORY

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
	if not _is_safe_slot_name(slot):
		_last_error = "Save slot must be non-empty and may not contain path traversal characters."
		return 0

	_load_durable_slot_if_needed(slot)
	_last_error = ""

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
	_load_durable_slot_if_needed(slot)
	var committed: Dictionary = _committed_slots.get(slot, {})
	return int(committed.get("generation", 0))


func get_latest_committed_snapshot(
	slot: StringName = DEFAULT_SLOT
) -> Dictionary:
	_load_durable_slot_if_needed(slot)
	var committed: Dictionary = _committed_slots.get(slot, {})
	var snapshot: Dictionary = committed.get("snapshot", {})
	return snapshot.duplicate(true)


func get_durable_save_path(
	slot: StringName = DEFAULT_SLOT
) -> String:
	if not _is_safe_slot_name(slot):
		return ""
	var root: String = durable_save_directory.strip_edges().trim_suffix("/")
	if root.is_empty():
		return ""
	return root.path_join(str(slot) + DURABLE_SAVE_EXTENSION)


func get_last_error() -> String:
	return _last_error


func validate_snapshot(snapshot: Dictionary) -> bool:
	_last_error = ""
	if snapshot.is_empty() or not _is_detached_value(snapshot):
		return _fail_validation(
			"Save snapshot must be non-empty detached value data."
		)
	if (
		typeof(snapshot.get("generation", null)) != TYPE_INT
		or int(snapshot.get("generation", 0)) <= 0
	):
		return _fail_validation(
			"Save snapshot generation must be a positive integer."
		)
	if (
		typeof(snapshot.get("slot", null)) != TYPE_STRING_NAME
		or not _is_safe_slot_name(snapshot.get("slot", &""))
	):
		return _fail_validation(
			"Save snapshot slot is missing or unsafe."
		)

	var session_snapshot: Variant = snapshot.get("session", null)
	if typeof(session_snapshot) != TYPE_DICTIONARY:
		return _fail_validation(
			"Save snapshot is missing its session envelope."
		)
	if not _is_valid_session_envelope(session_snapshot as Dictionary):
		return false
	if not _validate_installed_compatibility(
		session_snapshot as Dictionary
	):
		return false

	var view_pose: Variant = snapshot.get("player_view_pose", null)
	if typeof(view_pose) != TYPE_DICTIONARY:
		return _fail_validation(
			"Save snapshot is missing its player view pose."
		)
	if not _is_valid_view_pose(view_pose as Dictionary):
		return _fail_validation(
			"Save snapshot player view pose is malformed."
		)
	return true


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
		request["error"] = (
			"Captured snapshot became invalid before commit: %s"
			% _last_error
		)
		_requests[generation] = request
		return

	if not _write_durable_snapshot(slot, snapshot):
		request["status"] = &"failed"
		request["error"] = _last_error
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
		return _fail_validation(
			"Save session envelope must be detached value data."
		)
	if (
		typeof(envelope.get("save_format_version", null)) != TYPE_INT
		or int(envelope.get("save_format_version", 0)) <= 0
		or typeof(envelope.get("mission_id", null)) != TYPE_STRING_NAME
		or str(envelope.get("mission_id", &"")).strip_edges().is_empty()
		or typeof(envelope.get("mission_content_revision", null)) != TYPE_INT
		or int(envelope.get("mission_content_revision", 0)) <= 0
	):
		return _fail_validation(
			"Save session envelope is missing valid compatibility metadata."
		)
	if (
		typeof(envelope.get("source_session_id", null)) != TYPE_INT
		or int(envelope.get("source_session_id", 0)) <= 0
		or typeof(envelope.get("stable_boundary_serial", null)) != TYPE_INT
		or int(envelope.get("stable_boundary_serial", 0)) <= 0
		or typeof(envelope.get("world_scene_path", null)) != TYPE_STRING
		or str(envelope.get("world_scene_path", "")).is_empty()
		or typeof(envelope.get("mission_definition_path", null)) != TYPE_STRING
	):
		return _fail_validation(
			"Save session envelope is missing required world identity fields."
		)
	var gameplay_time_value: Variant = envelope.get(
		"gameplay_time_seconds",
		null
	)
	if (
		typeof(gameplay_time_value) != TYPE_FLOAT
		and typeof(gameplay_time_value) != TYPE_INT
	):
		return _fail_validation(
			"Save session gameplay time is not numeric."
		)
	var gameplay_time: float = float(gameplay_time_value)
	if not is_finite(gameplay_time) or gameplay_time < 0.0:
		return _fail_validation(
			"Save session gameplay time is invalid."
		)
	var world_state: Variant = envelope.get("world_state", null)
	if typeof(world_state) != TYPE_DICTIONARY:
		return _fail_validation(
			"Save session envelope has no semantic world state."
		)
	if not _is_valid_world_state_structure(world_state as Dictionary):
		return _fail_validation(
			"Save semantic world state is malformed or unsupported."
		)
	return true


func _validate_installed_compatibility(
	envelope: Dictionary
) -> bool:
	var saved_format: int = int(
		envelope.get("save_format_version", 0)
	)
	if saved_format != SaveFormat.CURRENT_VERSION:
		return _fail_validation(
			"Unsupported save format version %d; expected %d. No migration is available."
			% [saved_format, SaveFormat.CURRENT_VERSION]
		)

	var world_scene_path: String = str(
		envelope.get("world_scene_path", "")
	)
	if (
		world_scene_path.is_empty()
		or not ResourceLoader.exists(world_scene_path)
	):
		return _fail_validation(
			"Saved world scene is unavailable: %s"
			% world_scene_path
		)

	var definition_path: String = str(
		envelope.get("mission_definition_path", "")
	)
	var expected_mission_id: StringName
	var expected_revision: int
	if definition_path.is_empty():
		expected_mission_id = SaveFormat.mission_id_for(
			null,
			world_scene_path
		)
		expected_revision = SaveFormat.mission_revision_for(null)
	else:
		if not ResourceLoader.exists(definition_path):
			return _fail_validation(
				"Saved MissionDefinition is unavailable: %s"
				% definition_path
			)
		var definition: Resource = ResourceLoader.load(
			definition_path
		)
		if (
			definition == null
			or definition.get_script()
				!= MISSION_DEFINITION_SCRIPT
		):
			return _fail_validation(
				"Saved MissionDefinition is not loadable: %s"
				% definition_path
			)
		var definition_errors: PackedStringArray = definition.call(
			"get_load_errors"
		)
		if not definition_errors.is_empty():
			return _fail_validation(
				"Saved MissionDefinition is invalid: %s"
				% "; ".join(definition_errors)
			)
		var definition_world := definition.get(
			"world_scene"
		) as PackedScene
		if (
			definition_world == null
			or definition_world.resource_path
				!= world_scene_path
		):
			return _fail_validation(
				"Saved MissionDefinition no longer owns world scene '%s'."
				% world_scene_path
			)
		expected_mission_id = SaveFormat.mission_id_for(
			definition,
			world_scene_path
		)
		expected_revision = SaveFormat.mission_revision_for(
			definition
		)

	var saved_mission_id: StringName = envelope.get(
		"mission_id",
		&""
	)
	if saved_mission_id != expected_mission_id:
		return _fail_validation(
			"Unsupported save mission_id '%s'; installed content expects '%s'."
			% [
				str(saved_mission_id),
				str(expected_mission_id),
			]
		)
	var saved_revision: int = int(
		envelope.get("mission_content_revision", 0)
	)
	if saved_revision != expected_revision:
		return _fail_validation(
			"Unsupported mission content revision %d for '%s'; installed revision is %d. No migration is available."
			% [
				saved_revision,
				str(expected_mission_id),
				expected_revision,
			]
		)
	return true


func _load_durable_slot_if_needed(slot: StringName) -> void:
	if _committed_slots.has(slot) or not _is_safe_slot_name(slot):
		return
	_recover_interrupted_durable_write(slot)
	var snapshot: Dictionary = _read_durable_snapshot_file(
		get_durable_save_path(slot)
	)
	if snapshot.is_empty():
		return
	var generation: int = int(snapshot.get("generation", 0))
	_committed_slots[slot] = {
		"generation": generation,
		"snapshot": snapshot.duplicate(true),
	}
	_next_generation = maxi(_next_generation, generation + 1)


func _write_durable_snapshot(
	slot: StringName,
	snapshot: Dictionary
) -> bool:
	var final_path: String = get_durable_save_path(slot)
	if final_path.is_empty():
		return _fail_validation(
			"Durable save path is invalid."
		)
	if not _ensure_durable_save_directory():
		return false

	_recover_interrupted_durable_write(slot)
	var temp_path: String = final_path + DURABLE_TEMP_SUFFIX
	_remove_file_if_exists(temp_path)

	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _fail_validation(
			"Could not open temporary save file '%s' for writing (error %d)."
			% [temp_path, FileAccess.get_open_error()]
		)
	var stored: bool = file.store_var(snapshot, false)
	file.flush()
	file.close()
	if not stored:
		_remove_file_if_exists(temp_path)
		return _fail_validation(
			"Temporary save file could not serialize the detached snapshot; previous durable save was preserved."
		)

	var verified_temp: Dictionary = _read_durable_snapshot_file(
		temp_path
	)
	if verified_temp.is_empty() or verified_temp != snapshot:
		_remove_file_if_exists(temp_path)
		return _fail_validation(
			"Temporary save file failed round-trip validation; previous durable save was preserved."
		)

	# Godot's same-filesystem rename overwrites the destination. Promotion is
	# therefore one replacement operation performed only after the new file has
	# round-trip validated; a promotion error leaves the previous slot untouched.
	var promote_error: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path),
		ProjectSettings.globalize_path(final_path)
	)
	if promote_error != OK:
		_remove_file_if_exists(temp_path)
		return _fail_validation(
			"Could not atomically promote validated temporary save into place (error %d); previous durable save was preserved."
			% promote_error
		)

	var verified_final: Dictionary = _read_durable_snapshot_file(
		final_path
	)
	if verified_final.is_empty() or verified_final != snapshot:
		return _fail_validation(
			"Promoted durable save failed validation."
		)

	_last_error = ""
	return true


func _recover_interrupted_durable_write(
	slot: StringName
) -> void:
	var final_path: String = get_durable_save_path(slot)
	if final_path.is_empty():
		return
	var temp_path: String = final_path + DURABLE_TEMP_SUFFIX
	var final_exists: bool = FileAccess.file_exists(final_path)
	if final_exists:
		_remove_file_if_exists(temp_path)
		return
	if FileAccess.file_exists(temp_path):
		var recovered: Dictionary = _read_durable_snapshot_file(
			temp_path
		)
		if not recovered.is_empty():
			DirAccess.rename_absolute(
				ProjectSettings.globalize_path(temp_path),
				ProjectSettings.globalize_path(final_path)
			)
		else:
			_remove_file_if_exists(temp_path)


func _read_durable_snapshot_file(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail_validation(
			"Could not open durable save file '%s' (error %d)."
			% [path, FileAccess.get_open_error()]
		)
		return {}
	var value: Variant = file.get_var(false)
	file.close()
	if typeof(value) != TYPE_DICTIONARY:
		_fail_validation(
			"Durable save file '%s' does not contain a snapshot dictionary."
			% path
		)
		return {}
	var snapshot: Dictionary = value
	if not validate_snapshot(snapshot):
		var validation_error: String = _last_error
		_last_error = (
			"Durable save file '%s' is incompatible or corrupt: %s"
			% [path, validation_error]
		)
		return {}
	return snapshot.duplicate(true)


func _ensure_durable_save_directory() -> bool:
	var root: String = durable_save_directory.strip_edges().trim_suffix("/")
	if root.is_empty():
		return _fail_validation(
			"Durable save directory must not be empty."
		)
	var absolute_root: String = ProjectSettings.globalize_path(
		root
	)
	if DirAccess.dir_exists_absolute(absolute_root):
		return true
	var error: Error = DirAccess.make_dir_recursive_absolute(
		absolute_root
	)
	if error != OK:
		return _fail_validation(
			"Could not create durable save directory '%s' (error %d)."
			% [root, error]
		)
	return true


func _remove_file_if_exists(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(path)
	)


func _is_safe_slot_name(slot: StringName) -> bool:
	var value: String = str(slot).strip_edges()
	return (
		not value.is_empty()
		and not value.contains("/")
		and not value.contains("\\")
		and not value.contains(":")
		and not value.contains("..")
	)


func _fail_validation(message: String) -> bool:
	_last_error = message
	return false


func _is_valid_world_state_structure(world_state: Dictionary) -> bool:
	if not _is_detached_value(world_state):
		return false
	if (
		typeof(world_state.get("object_existence", null)) != TYPE_DICTIONARY
		or typeof(world_state.get("persistent_entities", null)) != TYPE_DICTIONARY
		or typeof(world_state.get("player", null)) != TYPE_DICTIONARY
		or typeof(world_state.get("semantic_owners", null)) != TYPE_DICTIONARY
		or typeof(world_state.get("mission_script_state", null)) != TYPE_DICTIONARY
	):
		return false
	var existence: Dictionary = world_state.get("object_existence", {})
	if (
		typeof(existence.get("authored_tombstones", null)) != TYPE_ARRAY
		or typeof(existence.get("runtime_entities", null)) != TYPE_ARRAY
	):
		return false
	# The current slice contains neither permanent authored removals nor
	# runtime-created persistent objects. Reject unsupported non-empty sections
	# before destructive replacement; later roadmap items extend these sections.
	return (
		(existence.get("authored_tombstones", []) as Array).is_empty()
		and (existence.get("runtime_entities", []) as Array).is_empty()
		and (world_state.get("mission_script_state", {}) as Dictionary).is_empty()
	)


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
