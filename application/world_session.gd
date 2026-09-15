class_name WorldSession
extends Node


const PLAYER_GROUP: StringName = &"vark_player"


enum State {
	EMPTY,
	BUILDING,
	READY,
	PLAYING,
	STOPPED,
	TEARING_DOWN,
}


var session_id: int = 0
var world_scene: PackedScene = null
var world: Node = null
var player: Node = null
var state: int = State.EMPTY


func build(new_session_id: int, scene: PackedScene) -> bool:
	if state != State.EMPTY or new_session_id <= 0 or scene == null:
		return false

	session_id = new_session_id
	world_scene = scene
	state = State.BUILDING
	process_mode = Node.PROCESS_MODE_DISABLED

	world = world_scene.instantiate()
	add_child(world)
	player = _find_session_player(world)
	if player == null:
		teardown()
		return false

	state = State.READY
	return true


func begin_play() -> bool:
	if state != State.READY and state != State.STOPPED:
		return false
	if world == null:
		return false

	process_mode = Node.PROCESS_MODE_INHERIT
	state = State.PLAYING
	return true


func stop_gameplay() -> bool:
	if state != State.PLAYING or world == null:
		return false

	process_mode = Node.PROCESS_MODE_DISABLED
	state = State.STOPPED
	return true


func teardown() -> void:
	if state == State.EMPTY:
		return

	state = State.TEARING_DOWN
	process_mode = Node.PROCESS_MODE_DISABLED

	if world != null:
		if world.get_parent() == self:
			remove_child(world)
		world.free()

	world = null
	player = null
	world_scene = null
	session_id = 0
	state = State.EMPTY


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
