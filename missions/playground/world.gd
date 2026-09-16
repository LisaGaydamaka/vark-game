extends Node3D


const PLAYER_START_GROUP: StringName = &"vark_player_start"

@onready var player: Node3D = $Player
@onready var func_map: Node = $FuncGodotMap

var mission_definition: Resource = null
var selected_player_start: Node3D = null


func configure_mission_definition(definition: Resource) -> bool:
	if is_inside_tree() or definition == null:
		return false
	mission_definition = definition
	return true


func _ready() -> void:
	assert(
		mission_definition != null,
		"The Playground must be instantiated through its MissionDefinition."
	)

	func_map.set("local_map_file", str(mission_definition.get("map_source_path")))
	func_map.call("build")
	_apply_authored_player_start()


func _apply_authored_player_start() -> void:
	var selector: String = str(
		mission_definition.get("player_start_selector")
	).strip_edges()
	var matching_starts: Array[Node] = []

	for node: Node in func_map.find_children("*", "", true, false):
		if not node.is_in_group(PLAYER_START_GROUP):
			continue
		if not node.has_method("get_content_id"):
			continue
		if str(node.call("get_content_id")).strip_edges() != selector:
			continue
		matching_starts.append(node)

	if matching_starts.size() != 1:
		push_error(
			"Playground player_start_selector '%s' resolved to %d authored Vark player starts; expected exactly one."
			% [selector, matching_starts.size()]
		)
		return

	var start := matching_starts[0] as Node3D
	if start == null:
		push_error(
			"Playground player_start_selector '%s' resolved to a non-Node3D entity."
			% selector
		)
		return

	selected_player_start = start
	player.global_transform = start.global_transform
