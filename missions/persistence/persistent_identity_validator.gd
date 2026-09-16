class_name VarkPersistentIdentityValidator
extends RefCounted


const MARKER_METHOD: StringName = &"is_vark_persistent_entity"
const ID_METHOD: StringName = &"get_persistent_id"
const CONTENT_ID_METHOD: StringName = &"get_content_id"


static func validate_subtree(root: Node) -> Dictionary:
	var errors := PackedStringArray()
	var seen_persistent_ids: Dictionary[String, String] = {}
	var seen_content_ids: Dictionary[String, String] = {}
	var identity_count: int = 0
	var content_id_count: int = 0

	if root == null:
		errors.append("Cannot validate persistent identity for a null world root.")
		return {
			"ok": false,
			"errors": errors,
			"identity_count": identity_count,
			"content_id_count": content_id_count,
		}

	var nodes: Array[Node] = [root]
	for child: Node in root.find_children("*", "", true, false):
		nodes.append(child)

	for node: Node in nodes:
		if not node.has_method(MARKER_METHOD):
			continue
		if not bool(node.call(MARKER_METHOD)):
			continue
		identity_count += 1

		var node_path: String = str(root.get_path_to(node))
		var persistent_id: String = ""
		if node.has_method(ID_METHOD):
			persistent_id = str(node.call(ID_METHOD)).strip_edges()

		if persistent_id.is_empty():
			errors.append(
				"Missing persistent_id on authored persistent entity at %s."
				% node_path
			)
		elif seen_persistent_ids.has(persistent_id):
			errors.append(
				"Duplicate persistent_id '%s' at %s; first authored owner is %s."
				% [persistent_id, node_path, seen_persistent_ids[persistent_id]]
			)
		else:
			seen_persistent_ids[persistent_id] = node_path

		var content_id: String = ""
		if node.has_method(CONTENT_ID_METHOD):
			content_id = str(node.call(CONTENT_ID_METHOD)).strip_edges()
		if content_id.is_empty():
			continue

		content_id_count += 1
		if seen_content_ids.has(content_id):
			errors.append(
				"Duplicate content_id '%s' at %s; first authored owner is %s."
				% [content_id, node_path, seen_content_ids[content_id]]
			)
			continue
		seen_content_ids[content_id] = node_path

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"identity_count": identity_count,
		"content_id_count": content_id_count,
	}
