class_name WorldSession
extends Node


const PLAYER_GROUP: StringName = &"vark_player"
const MISSION_DEFINITION_SCRIPT = preload("res://missions/mission_definition.gd")
const MissionContentValidator = preload("res://missions/mission_content_validator.gd")
const WorldEntityRegistry = preload(
	"res://missions/persistence/world_entity_registry.gd"
)
const SEMANTIC_EVENT_CASCADE_LIMIT: int = 256
const SEMANTIC_EVENT_TRACE_LIMIT: int = 24
const STABLE_BOUNDARY_PHYSICS_PRIORITY: int = 1000


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
var state: int = State.EMPTY
var gameplay_time_seconds: float = 0.0

var _semantic_event_queue: Array[Dictionary] = []
var _semantic_event_handlers: Dictionary = {}
var _semantic_event_draining: bool = false
var _next_semantic_event_sequence: int = 1
var _stable_gameplay_boundary_serial: int = 0
var _last_semantic_event_error: String = ""


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
