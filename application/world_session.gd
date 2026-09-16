class_name WorldSession
extends Node


const PLAYER_GROUP: StringName = &"vark_player"
const MISSION_DEFINITION_SCRIPT = preload("res://missions/mission_definition.gd")
const WorldEntityRegistry = preload(
	"res://missions/persistence/world_entity_registry.gd"
)


enum State {
	EMPTY,
	BUILDING,
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


func _physics_process(delta: float) -> void:
	if state == State.PLAYING:
		gameplay_time_seconds += delta


func get_gameplay_time_seconds() -> float:
	return gameplay_time_seconds


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


func _registry_unavailable_result() -> Dictionary:
	return {
		"ok": false,
		"node": null,
		"error": "WorldSession has no active entity registry.",
	}


func _find_session_player(session_world: Node) -> Node:
	var found_player: Node = null
	if session_world.is_in_group(PLAYER_GROUP):
		found_player = session_world

	for node: Node in session_world.find_children("*", "", true, false):
		if not node.is_in_group(PLAYER_GROUP):
			continue
		assert(
			found_player == null,
			"A Vark world may expose only one node in the vark_player group."
		)
		found_player = node

	return found_player
