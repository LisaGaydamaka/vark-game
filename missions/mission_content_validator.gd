class_name VarkMissionContentValidator
extends RefCounted


const PLAYER_START_GROUP: StringName = &"vark_player_start"
const MISSION_EXIT_GROUP: StringName = &"vark_mission_exit"
const PERSISTENT_MARKER_METHOD: StringName = &"is_vark_persistent_entity"


static func validate(
	definition: Resource,
	world_root: Node,
	entity_registry: RefCounted
) -> Dictionary:
	var errors := PackedStringArray()
	var exit_count: int = 0

	if definition == null:
		errors.append("Cannot validate mission content without a MissionDefinition.")
	if world_root == null:
		errors.append("Cannot validate mission content without a built world root.")
	if entity_registry == null:
		errors.append("Cannot validate mission content without the current-world entity registry.")
	if not errors.is_empty():
		return _result(errors, exit_count)

	var player_start_selector: String = str(
		definition.get("player_start_selector")
	).strip_edges()
	if player_start_selector.is_empty():
		errors.append("player_start_selector must not be empty.")
	else:
		var start_lookup: Dictionary = entity_registry.call(
			"lookup_content_id",
			player_start_selector
		)
		if not bool(start_lookup.get("ok", false)):
			errors.append(
				"player_start_selector '%s' does not resolve in the current mission: %s"
				% [
					player_start_selector,
					str(start_lookup.get("error", "lookup failed")),
				]
			)
		else:
			var selected_start: Node = start_lookup.get("node") as Node
			if (
				selected_start == null
				or not (selected_start is Node3D)
				or not selected_start.is_in_group(PLAYER_START_GROUP)
			):
				errors.append(
					"player_start_selector '%s' resolves to %s, not an authored vark_player_start."
					% [
						player_start_selector,
						_relative_path(world_root, selected_start),
					]
				)

	var exit_nodes: Array[Node] = []
	if world_root.is_in_group(MISSION_EXIT_GROUP):
		exit_nodes.append(world_root)
	for node: Node in world_root.find_children("*", "", true, false):
		if node.is_in_group(MISSION_EXIT_GROUP):
			exit_nodes.append(node)

	exit_count = exit_nodes.size()
	if exit_count == 0:
		errors.append(
			"Mission content requires at least one authored vark_exit endpoint."
		)
	else:
		for exit_node: Node in exit_nodes:
			if not (exit_node is Node3D):
				errors.append(
					"Mission exit at %s must build as Node3D."
					% _relative_path(world_root, exit_node)
				)
			if (
				not exit_node.has_method(PERSISTENT_MARKER_METHOD)
				or not bool(exit_node.call(PERSISTENT_MARKER_METHOD))
			):
				errors.append(
					"Mission exit at %s is not a Vark persistent authored entity."
					% _relative_path(world_root, exit_node)
				)

	return _result(errors, exit_count)


static func _result(errors: PackedStringArray, exit_count: int) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"exit_count": exit_count,
	}


static func _relative_path(world_root: Node, node: Node) -> String:
	if node == null:
		return "<null>"
	if node == world_root:
		return "."
	return str(world_root.get_path_to(node))
