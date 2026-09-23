class_name WorldSession
extends Node


const PLAYER_GROUP: StringName = &"vark_player"
const MISSION_DEFINITION_SCRIPT = preload("res://missions/mission_definition.gd")
const SaveFormat = preload("res://application/save_format.gd")
const MissionContentValidator = preload("res://missions/mission_content_validator.gd")
const WorldEntityRegistry = preload(
	"res://missions/persistence/world_entity_registry.gd"
)
const MissionRunState = preload("res://missions/mission_run_state.gd")
const SEMANTIC_EVENT_CASCADE_LIMIT: int = 256
const SEMANTIC_EVENT_TRACE_LIMIT: int = 24
const STABLE_BOUNDARY_PHYSICS_PRIORITY: int = 1000
const GAMEPLAY_SOUND_EVENT_NAME: StringName = &"gameplay.sound"
const PICKUP_COLLECTED_EVENT_NAME: StringName = &"pickup.collected"
const SEMANTIC_SAVE_ID_METHOD: StringName = &"get_semantic_save_id"
const CAPTURE_SEMANTIC_STATE_METHOD: StringName = &"capture_semantic_state"
const APPLY_SEMANTIC_STATE_METHOD: StringName = &"apply_semantic_state"
const RECONCILE_AFTER_RESTORE_METHOD: StringName = &"reconcile_after_restore"
const AFTER_RESTORE_METHOD: StringName = &"after_restore"


enum State {
	EMPTY,
	BUILDING,
	RESTORING,
	READY,
	PLAYING,
	PAUSED,
	STOPPED,
	TEARING_DOWN,
}


var session_id: int = 0
var world_scene: PackedScene = null
var mission_definition: Resource = null
var world: Node = null
var player: Node = null
var entity_registry: RefCounted = null
var mission_run_state: RefCounted = null
var state: int = State.EMPTY
var gameplay_time_seconds: float = 0.0

var _semantic_event_queue: Array[Dictionary] = []
var _semantic_event_handlers: Dictionary = {}
var _semantic_event_draining: bool = false
var _next_semantic_event_sequence: int = 1
var _stable_gameplay_boundary_serial: int = 0
var _last_semantic_event_error: String = ""
var _last_restore_error: String = ""
var _restore_state_applied: bool = false
var _authored_tombstones: Dictionary[String, bool] = {}


func _init() -> void:
	# Ordinary gameplay nodes use the default priority. The session drains semantic
	# consequences later in the same physics tick without claiming that unrelated
	# engine discoveries have a global order.
	process_physics_priority = STABLE_BOUNDARY_PHYSICS_PRIORITY


func _physics_process(delta: float) -> void:
	if state != State.PLAYING:
		return

	gameplay_time_seconds += delta
	if _drain_semantic_gameplay_events():
		_stable_gameplay_boundary_serial += 1


func get_gameplay_time_seconds() -> float:
	return gameplay_time_seconds


func capture_save_envelope() -> Dictionary:
	if (
		state != State.PLAYING
		or _semantic_event_draining
		or not _semantic_event_queue.is_empty()
		or world_scene == null
		or world_scene.resource_path.is_empty()
	):
		return {}

	var world_state: Dictionary = _capture_world_semantic_state()
	if world_state.is_empty():
		return {}

	return {
		"save_format_version": SaveFormat.CURRENT_VERSION,
		"mission_id": SaveFormat.mission_id_for(
			mission_definition,
			world_scene.resource_path
		),
		"mission_content_revision": SaveFormat.mission_revision_for(
			mission_definition
		),
		"source_session_id": session_id,
		"stable_boundary_serial": _stable_gameplay_boundary_serial,
		"gameplay_time_seconds": gameplay_time_seconds,
		"world_scene_path": world_scene.resource_path,
		"mission_definition_path": (
			mission_definition.resource_path
			if mission_definition != null
			else ""
		),
		"world_state": world_state,
	}


func begin_restore_from_envelope(envelope: Dictionary) -> bool:
	_last_restore_error = ""
	_restore_state_applied = false
	if state != State.READY or world == null:
		return _fail_restore("WorldSession restore requires a READY candidate world.")
	if not _is_detached_semantic_value(envelope):
		return _fail_restore("WorldSession restore envelope is not detached semantic data.")
	if (
		int(envelope.get("source_session_id", 0)) <= 0
		or int(envelope.get("stable_boundary_serial", 0)) <= 0
		or str(envelope.get("world_scene_path", ""))
			!= world_scene.resource_path
	):
		return _fail_restore("WorldSession restore envelope does not match the candidate world.")

	var expected_definition_path: String = (
		mission_definition.resource_path
		if mission_definition != null
		else ""
	)
	if (
		str(envelope.get("mission_definition_path", ""))
		!= expected_definition_path
	):
		return _fail_restore("WorldSession restore MissionDefinition path does not match the candidate.")

	var expected_mission_id: StringName = SaveFormat.mission_id_for(
		mission_definition,
		world_scene.resource_path
	)
	var expected_content_revision: int = SaveFormat.mission_revision_for(
		mission_definition
	)
	if int(envelope.get("save_format_version", 0)) != SaveFormat.CURRENT_VERSION:
		return _fail_restore(
			"Unsupported save format version %d; expected %d. No migration is available."
			% [
				int(envelope.get("save_format_version", 0)),
				SaveFormat.CURRENT_VERSION,
			]
		)
	if envelope.get("mission_id", &"") != expected_mission_id:
		return _fail_restore(
			"Save mission_id '%s' does not match candidate mission '%s'."
			% [
				str(envelope.get("mission_id", &"")),
				str(expected_mission_id),
			]
		)
	if int(envelope.get("mission_content_revision", 0)) != expected_content_revision:
		return _fail_restore(
			"Save mission content revision %d does not match candidate revision %d."
			% [
				int(envelope.get("mission_content_revision", 0)),
				expected_content_revision,
			]
		)

	var gameplay_time_value: Variant = envelope.get(
		"gameplay_time_seconds",
		null
	)
	if (
		typeof(gameplay_time_value) != TYPE_FLOAT
		and typeof(gameplay_time_value) != TYPE_INT
	):
		return _fail_restore("WorldSession restore gameplay time is invalid.")
	var restored_gameplay_time: float = float(gameplay_time_value)
	if not is_finite(restored_gameplay_time) or restored_gameplay_time < 0.0:
		return _fail_restore("WorldSession restore gameplay time is invalid.")

	var world_state_value: Variant = envelope.get("world_state", null)
	if typeof(world_state_value) != TYPE_DICTIONARY:
		return _fail_restore("WorldSession restore envelope has no semantic world state.")
	var world_state: Dictionary = world_state_value
	if not _validate_world_state_structure(world_state):
		return false

	state = State.RESTORING
	process_mode = Node.PROCESS_MODE_DISABLED
	gameplay_time_seconds = restored_gameplay_time
	return true


func apply_restore_world_state(world_state: Dictionary) -> bool:
	if state != State.RESTORING or world == null:
		return _fail_restore("Semantic restore requires a RESTORING WorldSession.")
	if not _validate_world_state_structure(world_state):
		return false

	# Object existence is established before semantic state. Phase 6.3 supports
	# authored removals through stable persistent-ID tombstones. Runtime-created
	# persistent objects remain unsupported and still fail closed.
	var existence: Dictionary = world_state.get("object_existence", {})
	var tombstones: Array = existence.get("authored_tombstones", [])
	var runtime_entities: Array = existence.get("runtime_entities", [])
	if not runtime_entities.is_empty():
		return _fail_restore(
			"Current Phase 6.3 slice cannot restore runtime-persistent entities."
		)
	if not _apply_authored_tombstones(tombstones):
		return false

	var persistent_snapshots: Dictionary = world_state.get(
		"persistent_entities",
		{}
	)
	for persistent_id: String in _authored_tombstones.keys():
		if persistent_snapshots.has(persistent_id):
			return _fail_restore(
				"Tombstoned authored entity '%s' also has a persistent snapshot."
				% persistent_id
			)
	var persistent_ids: Array = persistent_snapshots.keys()
	persistent_ids.sort()
	for id_value: Variant in persistent_ids:
		var persistent_id: String = str(id_value).strip_edges()
		var lookup: Dictionary = lookup_persistent_entity(persistent_id)
		var owner := lookup.get("node") as Node
		if not bool(lookup.get("ok", false)) or owner == null:
			return _fail_restore(
				"Restore could not resolve persistent entity '%s'." % persistent_id
			)
		if not _apply_owner_snapshot(
			owner,
			persistent_snapshots[persistent_id],
			"persistent entity '%s'" % persistent_id
		):
			return false

	if (
		player == null
		or not player.has_method(APPLY_SEMANTIC_STATE_METHOD)
		or not _apply_owner_snapshot(
			player,
			world_state.get("player", {}),
			"player"
		)
	):
		return _fail_restore("Restore could not apply player semantic state.")

	var semantic_owners: Dictionary = _collect_semantic_save_owners()
	if semantic_owners.is_empty() and not (
		world_state.get("semantic_owners", {}) as Dictionary
	).is_empty():
		return false
	var semantic_snapshots: Dictionary = world_state.get(
		"semantic_owners",
		{}
	)
	var semantic_ids: Array = semantic_snapshots.keys()
	semantic_ids.sort()
	for id_value: Variant in semantic_ids:
		var save_id: String = str(id_value)
		var owner := semantic_owners.get(save_id) as Node
		if owner == null:
			return _fail_restore(
				"Restore could not resolve semantic save owner '%s'." % save_id
			)
		if not _apply_owner_snapshot(
			owner,
			semantic_snapshots[save_id],
			"semantic owner '%s'" % save_id
		):
			return false

	var mission_script_state: Dictionary = world_state.get(
		"mission_script_state",
		{}
	)
	if not mission_script_state.is_empty():
		return _fail_restore(
			"Current slice has no mission-script semantic state owner."
		)
	var run_state_snapshot: Dictionary = world_state.get(
		"mission_run_state",
		{
			"loot_count": 0,
			"loot_value": 0,
		}
	)
	if (
		mission_run_state == null
		or not bool(mission_run_state.call(
			"apply_semantic_state",
			run_state_snapshot
		))
	):
		return _fail_restore("Restore could not apply MissionRunState.")

	for id_value: Variant in persistent_ids:
		var persistent_id: String = str(id_value).strip_edges()
		var lookup: Dictionary = lookup_persistent_entity(persistent_id)
		var owner := lookup.get("node") as Node
		if owner != null and not _reconcile_owner(
			owner,
			"persistent entity '%s'" % persistent_id
		):
			return false
	if not _reconcile_owner(player, "player"):
		return false
	for id_value: Variant in semantic_ids:
		var save_id: String = str(id_value)
		var owner := semantic_owners.get(save_id) as Node
		if owner != null and not _reconcile_owner(
			owner,
			"semantic owner '%s'" % save_id
		):
			return false

	for id_value: Variant in persistent_ids:
		var persistent_id: String = str(id_value).strip_edges()
		var lookup: Dictionary = lookup_persistent_entity(persistent_id)
		var owner := lookup.get("node") as Node
		if owner != null and not _after_restore_owner(
			owner,
			"persistent entity '%s'" % persistent_id
		):
			return false
	if not _after_restore_owner(player, "player"):
		return false
	for id_value: Variant in semantic_ids:
		var save_id: String = str(id_value)
		var owner := semantic_owners.get(save_id) as Node
		if owner != null and not _after_restore_owner(
			owner,
			"semantic owner '%s'" % save_id
		):
			return false

	var restored_state: Dictionary = _capture_world_semantic_state()
	if restored_state.is_empty():
		return _fail_restore(
			"Restored semantic world state could not be recaptured for validation."
		)

	var captured_player_state: Dictionary = world_state.get("player", {})
	var restored_player_state: Dictionary = restored_state.get("player", {})
	if (
		player == null
		or not player.has_method("validate_restored_semantic_state")
		or not bool(player.call(
			"validate_restored_semantic_state",
			captured_player_state
		))
	):
		return _fail_restore(
			"Restored player semantic state does not satisfy its declared restore policy."
		)

	var comparable_expected: Dictionary = world_state.duplicate(true)
	# Player traversal policy may intentionally normalize a transient source
	# state. The player validates that policy above; every other semantic owner
	# must still recapture exactly.
	comparable_expected["player"] = restored_player_state.duplicate(true)
	# Pre-6.3 saves have no MissionRunState section. Their meaning is an empty
	# run-stat owner, so compare against the explicit default after restore.
	if not comparable_expected.has("mission_run_state"):
		comparable_expected["mission_run_state"] = (
			restored_state.get("mission_run_state", {}) as Dictionary
		).duplicate(true)
	if restored_state != comparable_expected:
		return _fail_restore(
			"Restored non-player semantic world state did not validate against the captured snapshot."
		)

	_restore_state_applied = true
	return true


func complete_restore() -> bool:
	if state != State.RESTORING or world == null or not _restore_state_applied:
		return false
	state = State.READY
	process_mode = Node.PROCESS_MODE_DISABLED
	return true


func get_last_restore_error() -> String:
	return _last_restore_error


func _capture_world_semantic_state() -> Dictionary:
	if (
		player == null
		or entity_registry == null
		or not player.has_method(CAPTURE_SEMANTIC_STATE_METHOD)
	):
		return {}

	var player_snapshot: Variant = player.call(CAPTURE_SEMANTIC_STATE_METHOD)
	if (
		typeof(player_snapshot) != TYPE_DICTIONARY
		or not _is_detached_semantic_value(player_snapshot)
	):
		push_error("Player semantic snapshot is invalid or retains live state.")
		return {}

	var persistent_snapshots: Dictionary = {}
	var entries: Array[Dictionary] = entity_registry.call(
		"get_persistent_entries"
	)
	for entry: Dictionary in entries:
		var owner := entry.get("node") as Node
		if owner == null or not owner.has_method(CAPTURE_SEMANTIC_STATE_METHOD):
			continue
		var persistent_id: String = str(
			entry.get("persistent_id", "")
		).strip_edges()
		var snapshot: Variant = owner.call(CAPTURE_SEMANTIC_STATE_METHOD)
		if (
			persistent_id.is_empty()
			or typeof(snapshot) != TYPE_DICTIONARY
			or not _is_detached_semantic_value(snapshot)
		):
			push_error(
				"Persistent entity '%s' produced invalid semantic save state."
				% persistent_id
			)
			return {}
		persistent_snapshots[persistent_id] = (
			snapshot as Dictionary
		).duplicate(true)

	var semantic_owners: Dictionary = _collect_semantic_save_owners()
	if _last_restore_error != "":
		return {}
	var semantic_snapshots: Dictionary = {}
	var semantic_ids: Array = semantic_owners.keys()
	semantic_ids.sort()
	for id_value: Variant in semantic_ids:
		var save_id: String = str(id_value)
		var owner := semantic_owners[save_id] as Node
		if owner == null or not owner.has_method(CAPTURE_SEMANTIC_STATE_METHOD):
			push_error(
				"Semantic save owner '%s' has no capture_semantic_state()."
				% save_id
			)
			return {}
		var snapshot: Variant = owner.call(CAPTURE_SEMANTIC_STATE_METHOD)
		if (
			typeof(snapshot) != TYPE_DICTIONARY
			or not _is_detached_semantic_value(snapshot)
		):
			push_error(
				"Semantic save owner '%s' produced invalid detached state."
				% save_id
			)
			return {}
		semantic_snapshots[save_id] = (
			snapshot as Dictionary
		).duplicate(true)

	var tombstones: Array[String] = get_authored_tombstones()
	var run_state_snapshot: Dictionary = {}
	if mission_run_state != null:
		run_state_snapshot = mission_run_state.call("capture_semantic_state")
	return {
		"object_existence": {
			"authored_tombstones": tombstones,
			"runtime_entities": [],
		},
		"persistent_entities": persistent_snapshots,
		"player": (player_snapshot as Dictionary).duplicate(true),
		"semantic_owners": semantic_snapshots,
		"mission_run_state": run_state_snapshot.duplicate(true),
		"mission_script_state": {},
	}


func _collect_semantic_save_owners() -> Dictionary:
	_last_restore_error = ""
	var result: Dictionary = {}
	if world == null:
		_fail_restore("Cannot collect semantic save owners without a world.")
		return result
	var nodes: Array[Node] = [world]
	nodes.append_array(world.find_children("*", "", true, false))
	for owner: Node in nodes:
		if not owner.has_method(SEMANTIC_SAVE_ID_METHOD):
			continue
		var save_id: String = str(
			owner.call(SEMANTIC_SAVE_ID_METHOD)
		).strip_edges()
		if save_id.is_empty():
			_fail_restore("A semantic save owner returned an empty save ID.")
			return {}
		if result.has(save_id):
			_fail_restore(
				"Duplicate semantic save owner ID '%s'." % save_id
			)
			return {}
		result[save_id] = owner
	return result


func _validate_world_state_structure(world_state: Dictionary) -> bool:
	if not _is_detached_semantic_value(world_state):
		return _fail_restore("Semantic world state is not detached value data.")
	if (
		typeof(world_state.get("object_existence", null)) != TYPE_DICTIONARY
		or typeof(world_state.get("persistent_entities", null)) != TYPE_DICTIONARY
		or typeof(world_state.get("player", null)) != TYPE_DICTIONARY
		or typeof(world_state.get("semantic_owners", null)) != TYPE_DICTIONARY
		or typeof(world_state.get("mission_script_state", null)) != TYPE_DICTIONARY
	):
		return _fail_restore("Semantic world state is missing required ownership sections.")
	var existence: Dictionary = world_state.get("object_existence", {})
	if (
		typeof(existence.get("authored_tombstones", null)) != TYPE_ARRAY
		or typeof(existence.get("runtime_entities", null)) != TYPE_ARRAY
	):
		return _fail_restore("Semantic object-existence state is malformed.")
	var tombstone_ids: Dictionary[String, bool] = {}
	for value: Variant in existence.get("authored_tombstones", []):
		if typeof(value) != TYPE_STRING:
			return _fail_restore("Authored tombstone IDs must be strings.")
		var persistent_id: String = str(value).strip_edges()
		if persistent_id.is_empty() or tombstone_ids.has(persistent_id):
			return _fail_restore("Authored tombstone IDs must be non-empty and unique.")
		tombstone_ids[persistent_id] = true
	if world_state.has("mission_run_state"):
		var run_state_value: Variant = world_state.get("mission_run_state")
		if (
			typeof(run_state_value) != TYPE_DICTIONARY
			or mission_run_state == null
			or not bool(MissionRunState.new().call(
				"apply_semantic_state",
				run_state_value
			))
		):
			return _fail_restore("Semantic MissionRunState is malformed.")
	return true


func _apply_authored_tombstones(tombstones: Array) -> bool:
	_authored_tombstones.clear()
	for value: Variant in tombstones:
		var persistent_id: String = str(value).strip_edges()
		if persistent_id.is_empty() or _authored_tombstones.has(persistent_id):
			return _fail_restore("Restore contains an invalid authored tombstone ID.")
		var lookup: Dictionary = lookup_persistent_entity(persistent_id)
		var owner := lookup.get("node") as Node
		if not bool(lookup.get("ok", false)) or owner == null:
			return _fail_restore(
				"Restore tombstone could not resolve authored persistent entity '%s'."
				% persistent_id
			)
		if owner == player:
			return _fail_restore("Player cannot be removed through an authored tombstone.")
		if not bool(entity_registry.call(
			"unregister_persistent_id",
			persistent_id,
			owner
		)):
			return _fail_restore(
				"Restore could not unregister tombstoned authored entity '%s'."
				% persistent_id
			)
		_authored_tombstones[persistent_id] = true
		var parent: Node = owner.get_parent()
		if parent != null:
			parent.remove_child(owner)
		owner.free()
	return true


func _apply_owner_snapshot(
	owner: Node,
	snapshot_value: Variant,
	label: String
) -> bool:
	if (
		owner == null
		or not owner.has_method(APPLY_SEMANTIC_STATE_METHOD)
		or typeof(snapshot_value) != TYPE_DICTIONARY
		or not _is_detached_semantic_value(snapshot_value)
	):
		return _fail_restore("Cannot apply semantic state for %s." % label)
	var result: Variant = owner.call(
		APPLY_SEMANTIC_STATE_METHOD,
		(snapshot_value as Dictionary).duplicate(true)
	)
	if typeof(result) != TYPE_BOOL or not bool(result):
		return _fail_restore("Semantic state application failed for %s." % label)
	return true


func _reconcile_owner(owner: Node, label: String) -> bool:
	if owner == null or not owner.has_method(RECONCILE_AFTER_RESTORE_METHOD):
		return true
	var result: Variant = owner.call(RECONCILE_AFTER_RESTORE_METHOD)
	if typeof(result) == TYPE_BOOL and not bool(result):
		return _fail_restore("Restore reconciliation failed for %s." % label)
	return true


func _after_restore_owner(owner: Node, label: String) -> bool:
	if owner == null or not owner.has_method(AFTER_RESTORE_METHOD):
		return true
	var result: Variant = owner.call(AFTER_RESTORE_METHOD)
	if typeof(result) == TYPE_BOOL and not bool(result):
		return _fail_restore("after_restore failed for %s." % label)
	return true


func _fail_restore(message: String) -> bool:
	_last_restore_error = message
	push_error(message)
	return false


func get_stable_gameplay_boundary_serial() -> int:
	return _stable_gameplay_boundary_serial


func get_pending_semantic_event_count() -> int:
	return _semantic_event_queue.size()


func is_semantic_event_drain_active() -> bool:
	return _semantic_event_draining


func get_last_semantic_event_error() -> String:
	return _last_semantic_event_error


func register_semantic_event_handler(
	event_name: StringName,
	handler: Callable
) -> bool:
	if state == State.EMPTY or state == State.TEARING_DOWN:
		return false
	if event_name.is_empty() or not handler.is_valid():
		return false

	var handlers: Array = _semantic_event_handlers.get(event_name, [])
	if handlers.has(handler):
		return true
	handlers.append(handler)
	_semantic_event_handlers[event_name] = handlers
	return true


func unregister_semantic_event_handler(
	event_name: StringName,
	handler: Callable
) -> bool:
	if not _semantic_event_handlers.has(event_name):
		return false

	var handlers: Array = _semantic_event_handlers[event_name]
	var index: int = handlers.find(handler)
	if index < 0:
		return false
	handlers.remove_at(index)
	if handlers.is_empty():
		_semantic_event_handlers.erase(event_name)
	else:
		_semantic_event_handlers[event_name] = handlers
	return true


func queue_semantic_gameplay_event(
	source_session_id: int,
	event_name: StringName,
	payload: Dictionary = {}
) -> bool:
	# Only the authoritative PLAYING session accepts normal semantic gameplay work.
	# Calls from arbitrary engine callbacks are allowed while PLAYING, but they only
	# enqueue work; dispatch still happens at the controlled physics consequence pass.
	if state != State.PLAYING:
		return false
	if source_session_id <= 0 or source_session_id != session_id:
		return false
	if event_name.is_empty():
		return false
	if (
		event_name == GAMEPLAY_SOUND_EVENT_NAME
		and not _is_valid_gameplay_sound_payload(payload)
	):
		return false
	if not _is_detached_semantic_value(payload):
		return false

	_semantic_event_queue.append({
		"name": event_name,
		"payload": payload.duplicate(true),
		"session_id": session_id,
		"sequence": _next_semantic_event_sequence,
	})
	_next_semantic_event_sequence += 1
	return true


func queue_gameplay_sound(
	source_session_id: int,
	sound_kind: StringName,
	origin: Vector3,
	strength: float
) -> bool:
	# Gameplay sound is semantic hearing input, not presentation audio. Keep
	# streams, buses, volume/pitch, and AudioStreamPlayer ownership elsewhere.
	return queue_semantic_gameplay_event(
		source_session_id,
		GAMEPLAY_SOUND_EVENT_NAME,
		{
			"kind": sound_kind,
			"origin": origin,
			"strength": strength,
		}
	)


func build(
	new_session_id: int,
	scene: PackedScene,
	definition: Resource = null
) -> bool:
	if state != State.EMPTY or new_session_id <= 0 or scene == null:
		return false
	if definition != null:
		if definition.get_script() != MISSION_DEFINITION_SCRIPT:
			push_error("WorldSession received a non-MissionDefinition resource.")
			return false
		var definition_errors: PackedStringArray = definition.call("get_load_errors")
		if not definition_errors.is_empty():
			for error_message: String in definition_errors:
				push_error(
					"WorldSession mission definition validation failed: %s"
					% error_message
				)
			return false
		var definition_world: PackedScene = definition.get("world_scene") as PackedScene
		if (
			definition_world == null
			or definition_world.resource_path != scene.resource_path
		):
			push_error(
				"WorldSession mission definition does not own the requested world scene."
			)
			return false

	session_id = new_session_id
	world_scene = scene
	mission_definition = definition
	state = State.BUILDING
	gameplay_time_seconds = 0.0
	_last_restore_error = ""
	_restore_state_applied = false
	_reset_semantic_event_state()
	process_mode = Node.PROCESS_MODE_DISABLED

	world = world_scene.instantiate()
	if mission_definition != null:
		if not world.has_method("configure_mission_definition"):
			push_error(
				"A MissionDefinition world must accept configure_mission_definition()."
			)
			teardown()
			return false
		if not bool(world.call("configure_mission_definition", mission_definition)):
			push_error("MissionDefinition world rejected its authored configuration.")
			teardown()
			return false

	add_child(world)
	mission_run_state = MissionRunState.new()
	_authored_tombstones.clear()
	entity_registry = WorldEntityRegistry.new()
	var registry_result: Dictionary = entity_registry.call("build_from_subtree", world)
	if not bool(registry_result.get("ok", false)):
		var registry_errors: PackedStringArray = registry_result.get(
			"errors",
			PackedStringArray()
		)
		for error_message: String in registry_errors:
			push_error(
				"WorldSession entity registry build failed: %s"
				% error_message
			)
		teardown()
		return false

	if mission_definition != null:
		var content_validation: Dictionary = MissionContentValidator.validate(
			mission_definition,
			world,
			entity_registry
		)
		if not bool(content_validation.get("ok", false)):
			var content_errors: PackedStringArray = content_validation.get(
				"errors",
				PackedStringArray()
			)
			for error_message: String in content_errors:
				push_error(
					"WorldSession mission content validation failed: %s"
					% error_message
				)
			teardown()
			return false

	player = _find_session_player(world)
	if player == null:
		teardown()
		return false

	state = State.READY
	return true


func lookup_persistent_entity(persistent_id: String) -> Dictionary:
	if entity_registry == null:
		return _registry_unavailable_result()
	return entity_registry.call("lookup_persistent_id", persistent_id)


func lookup_content_entity(content_id: String) -> Dictionary:
	if entity_registry == null:
		return _registry_unavailable_result()
	return entity_registry.call("lookup_content_id", content_id)


func get_mission_run_summary() -> Dictionary:
	if mission_run_state == null:
		return {
			"loot_count": 0,
			"loot_value": 0,
		}
	return mission_run_state.call("get_summary")


func get_authored_tombstones() -> Array[String]:
	var result: Array[String] = []
	for persistent_id: String in _authored_tombstones.keys():
		result.append(persistent_id)
	result.sort()
	return result


func collect_authored_pickup(collector: Node, pickup: Node) -> bool:
	if (
		state != State.PLAYING
		or collector == null
		or collector != player
		or pickup == null
		or not is_instance_valid(pickup)
		or entity_registry == null
		or mission_run_state == null
		or not pickup.has_method("get_collection_payload")
		or not pickup.has_method("mark_collected_for_tombstone")
		or not pickup.has_method("is_collected")
		or bool(pickup.call("is_collected"))
	):
		return false

	var payload_value: Variant = pickup.call("get_collection_payload")
	if typeof(payload_value) != TYPE_DICTIONARY:
		return false
	var payload: Dictionary = payload_value
	if (
		payload.size() != 4
		or typeof(payload.get("persistent_id", null)) != TYPE_STRING
		or typeof(payload.get("content_id", null)) != TYPE_STRING
		or typeof(payload.get("kind", null)) != TYPE_STRING_NAME
		or typeof(payload.get("loot_value", null)) != TYPE_INT
	):
		return false

	var persistent_id: String = str(payload.get("persistent_id", "")).strip_edges()
	var content_id: String = str(payload.get("content_id", "")).strip_edges()
	var kind: StringName = payload.get("kind", &"")
	var loot_value: int = int(payload.get("loot_value", -1))
	if (
		persistent_id.is_empty()
		or _authored_tombstones.has(persistent_id)
		or loot_value < 0
	):
		return false
	var lookup: Dictionary = lookup_persistent_entity(persistent_id)
	if (
		not bool(lookup.get("ok", false))
		or lookup.get("node") != pickup
	):
		return false
	if kind == &"loot":
		pass
	elif kind == &"key" or kind == &"mission_item":
		if (
			content_id.is_empty()
			or not collector.has_method("grant_semantic_possession")
		):
			return false
	else:
		return false

	if not bool(entity_registry.call(
		"unregister_persistent_id",
		persistent_id,
		pickup
	)):
		return false

	if kind == &"loot":
		if not bool(mission_run_state.call("record_loot", loot_value)):
			return false
	else:
		if not bool(collector.call(
			"grant_semantic_possession",
			StringName(content_id)
		)):
			return false

	_authored_tombstones[persistent_id] = true
	if not bool(pickup.call("mark_collected_for_tombstone")):
		return false

	queue_semantic_gameplay_event(
		session_id,
		PICKUP_COLLECTED_EVENT_NAME,
		{
			"persistent_id": persistent_id,
			"content_id": content_id,
			"kind": kind,
			"loot_value": loot_value,
		}
	)
	return true


func begin_play() -> bool:
	if state != State.READY and state != State.STOPPED:
		return false
	if world == null:
		return false

	process_mode = Node.PROCESS_MODE_INHERIT
	state = State.PLAYING
	return true


func pause_gameplay() -> bool:
	if state != State.PLAYING or world == null:
		return false

	state = State.PAUSED
	process_mode = Node.PROCESS_MODE_DISABLED
	return true


func resume_gameplay() -> bool:
	if state != State.PAUSED or world == null:
		return false

	process_mode = Node.PROCESS_MODE_INHERIT
	state = State.PLAYING
	return true


func stop_gameplay() -> bool:
	if (state != State.PLAYING and state != State.PAUSED) or world == null:
		return false

	process_mode = Node.PROCESS_MODE_DISABLED
	state = State.STOPPED
	return true


func teardown() -> void:
	if state == State.EMPTY:
		return

	state = State.TEARING_DOWN
	process_mode = Node.PROCESS_MODE_DISABLED
	_reset_semantic_event_state()

	if entity_registry != null:
		entity_registry.call("clear")
		entity_registry = null
	mission_run_state = null
	_authored_tombstones.clear()

	if world != null:
		if world.get_parent() == self:
			remove_child(world)
		world.free()

	world = null
	player = null
	mission_definition = null
	world_scene = null
	session_id = 0
	gameplay_time_seconds = 0.0
	_last_restore_error = ""
	_restore_state_applied = false
	state = State.EMPTY


func _drain_semantic_gameplay_events() -> bool:
	if state != State.PLAYING:
		return false
	if _semantic_event_draining:
		return _fail_semantic_event_drain(
			"Semantic gameplay event drain attempted to recurse."
		)

	_semantic_event_draining = true
	_last_semantic_event_error = ""
	var queue_index: int = 0
	var processed_count: int = 0
	var trace := PackedStringArray()

	while queue_index < _semantic_event_queue.size():
		if processed_count >= SEMANTIC_EVENT_CASCADE_LIMIT:
			return _fail_semantic_event_drain(
				"Semantic gameplay event cascade exceeded the development limit of %d. "
				% SEMANTIC_EVENT_CASCADE_LIMIT
				+ "Recent trace: %s" % " -> ".join(trace)
			)

		var event: Dictionary = _semantic_event_queue[queue_index]
		queue_index += 1
		processed_count += 1

		var event_name: StringName = event.get("name", &"")
		var sequence: int = int(event.get("sequence", 0))
		trace.append("%s#%d" % [event_name, sequence])
		if trace.size() > SEMANTIC_EVENT_TRACE_LIMIT:
			trace.remove_at(0)

		var handlers: Array = _semantic_event_handlers.get(event_name, []).duplicate()
		for handler_value: Variant in handlers:
			var handler: Callable = handler_value
			if not handler.is_valid():
				return _fail_semantic_event_drain(
					"Semantic gameplay event '%s' has an invalid handler."
					% event_name
				)

			# A participating handler must finish now and return true. In Godot 4,
			# requesting a coroutine/await result without awaiting is an error, so this
			# immediate acknowledgement makes await-based handlers incompatible with
			# the current drain by construction.
			var handler_result: Variant = handler.call(event.duplicate(true))
			if typeof(handler_result) != TYPE_BOOL or not bool(handler_result):
				return _fail_semantic_event_drain(
					"Semantic gameplay event handler for '%s' must return true synchronously."
					% event_name
				)

	_semantic_event_queue.clear()
	_semantic_event_draining = false
	return true


func _fail_semantic_event_drain(message: String) -> bool:
	_last_semantic_event_error = message
	_semantic_event_queue.clear()
	_semantic_event_draining = false
	push_error(message)
	return false


func _reset_semantic_event_state() -> void:
	_semantic_event_queue.clear()
	_semantic_event_handlers.clear()
	_semantic_event_draining = false
	_next_semantic_event_sequence = 1
	_stable_gameplay_boundary_serial = 0
	_last_semantic_event_error = ""


func _is_detached_semantic_value(value: Variant, depth: int = 0) -> bool:
	if depth > 32:
		return false

	match typeof(value):
		TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return false
		TYPE_ARRAY:
			for item: Variant in value:
				if not _is_detached_semantic_value(item, depth + 1):
					return false
		TYPE_DICTIONARY:
			for key: Variant in value.keys():
				if not _is_detached_semantic_value(key, depth + 1):
					return false
				if not _is_detached_semantic_value(value[key], depth + 1):
					return false

	return true


func _is_valid_gameplay_sound_payload(payload: Dictionary) -> bool:
	# This is intentionally a tiny source fact, not an acoustic result. 3.6
	# remains free to choose attenuation, portals/zones, and hearing semantics.
	if payload.size() != 3:
		return false
	if (
		not payload.has("kind")
		or not payload.has("origin")
		or not payload.has("strength")
	):
		return false
	if typeof(payload["kind"]) != TYPE_STRING_NAME:
		return false
	var sound_kind: StringName = payload["kind"]
	if sound_kind.is_empty():
		return false
	if typeof(payload["origin"]) != TYPE_VECTOR3:
		return false
	var strength_value: Variant = payload["strength"]
	if typeof(strength_value) != TYPE_FLOAT and typeof(strength_value) != TYPE_INT:
		return false
	var strength: float = float(strength_value)
	return is_finite(strength) and strength > 0.0


func _registry_unavailable_result() -> Dictionary:
	return {
		"ok": false,
		"node": null,
		"error": "WorldSession has no active entity registry.",
	}


func _find_session_player(session_world: Node) -> Node:
	var found_players: Array[Node] = []
	if session_world.is_in_group(PLAYER_GROUP):
		found_players.append(session_world)

	for node: Node in session_world.find_children("*", "", true, false):
		if node.is_in_group(PLAYER_GROUP):
			found_players.append(node)

	if found_players.size() == 1:
		return found_players[0]

	var player_paths := PackedStringArray()
	for found_player: Node in found_players:
		player_paths.append(str(session_world.get_path_to(found_player)))
	push_error(
		"WorldSession requires exactly one node in the vark_player group; found %d%s."
		% [
			found_players.size(),
			"" if player_paths.is_empty() else " at " + ", ".join(player_paths),
		]
	)
	return null
