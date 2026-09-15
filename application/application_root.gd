class_name VarkApplication
extends Node


const PLAYER_GROUP: StringName = &"vark_player"


enum TopLevelOperation {
	NONE,
	LOAD,
	RESTART,
	MISSION_TRANSITION,
	EXIT,
}


@export var default_world_scene: PackedScene

@onready var world_host: Node = $WorldHost
@onready var ui_root: CanvasLayer = $UIRoot

var current_world: Node = null
var current_player: Node = null
var current_ui: CanvasLayer = null
var current_session_id: int = 0
var active_top_level_operation: int = TopLevelOperation.NONE


func _ready() -> void:
	current_ui = ui_root
	_boot_default_world()


func get_current_session_id() -> int:
	return current_session_id


func is_current_session(session_id: int) -> bool:
	return session_id > 0 and session_id == current_session_id


func try_begin_top_level_operation(operation: int) -> bool:
	if operation == TopLevelOperation.NONE:
		return false
	if active_top_level_operation != TopLevelOperation.NONE:
		return false

	active_top_level_operation = operation
	return true


func finish_top_level_operation(operation: int) -> bool:
	if operation == TopLevelOperation.NONE:
		return false
	if active_top_level_operation != operation:
		return false

	active_top_level_operation = TopLevelOperation.NONE
	return true


func has_active_top_level_operation() -> bool:
	return active_top_level_operation != TopLevelOperation.NONE


func _boot_default_world() -> void:
	assert(
		default_world_scene != null,
		"VarkApplication requires a default world scene for initial development boot."
	)
	assert(
		current_world == null,
		"VarkApplication may install only one initial world during Phase 1.1."
	)

	current_session_id += 1
	current_world = default_world_scene.instantiate()
	world_host.add_child(current_world)
	current_player = _find_session_player(current_world)
	assert(
		current_player != null,
		"The current Vark world must expose exactly one node in the vark_player group."
	)


func _find_session_player(world: Node) -> Node:
	var found_player: Node = null
	if world.is_in_group(PLAYER_GROUP):
		found_player = world

	for node: Node in world.find_children("*", "", true, false):
		if not node.is_in_group(PLAYER_GROUP):
			continue
		assert(
			found_player == null,
			"A Vark world may expose only one node in the vark_player group."
		)
		found_player = node

	return found_player
