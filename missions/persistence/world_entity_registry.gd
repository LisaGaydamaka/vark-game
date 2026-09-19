class_name VarkWorldEntityRegistry
extends RefCounted


const PersistentIdentityValidator = preload(
	"res://missions/persistence/persistent_identity_validator.gd"
)
const MARKER_METHOD: StringName = &"is_vark_persistent_entity"
const ID_METHOD: StringName = &"get_persistent_id"
const CONTENT_ID_METHOD: StringName = &"get_content_id"

var _by_persistent_id: Dictionary[String, Node] = {}
var _by_content_id: Dictionary[String, Node] = {}


func build_from_subtree(root: Node) -> Dictionary:
	clear()
	var validation: Dictionary = PersistentIdentityValidator.validate_subtree(root)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"errors": validation.get("errors", PackedStringArray()),
			"persistent_count": 0,
			"content_count": 0,
		}

	var nodes: Array[Node] = [root]
	for child: Node in root.find_children("*", "", true, false):
		nodes.append(child)

	for node: Node in nodes:
		if not node.has_method(MARKER_METHOD):
			continue
		if not bool(node.call(MARKER_METHOD)):
			continue

		var persistent_id: String = str(node.call(ID_METHOD)).strip_edges()
		_by_persistent_id[persistent_id] = node

		var content_id: String = ""
		if node.has_method(CONTENT_ID_METHOD):
			content_id = str(node.call(CONTENT_ID_METHOD)).strip_edges()
		if not content_id.is_empty():
			_by_content_id[content_id] = node

	return {
		"ok": true,
		"errors": PackedStringArray(),
		"persistent_count": _by_persistent_id.size(),
		"content_count": _by_content_id.size(),
	}


func clear() -> void:
	_by_persistent_id.clear()
	_by_content_id.clear()


func persistent_count() -> int:
	return _by_persistent_id.size()


func content_count() -> int:
	return _by_content_id.size()


func get_persistent_entries() -> Array[Dictionary]:
	var ids: Array = _by_persistent_id.keys()
	ids.sort()
	var result: Array[Dictionary] = []
	for id_value: Variant in ids:
		var persistent_id: String = str(id_value)
		result.append({
			"persistent_id": persistent_id,
			"node": _by_persistent_id[persistent_id],
		})
	return result


func lookup_persistent_id(persistent_id: String) -> Dictionary:
	return _lookup(_by_persistent_id, persistent_id, "persistent_id")


func lookup_content_id(content_id: String) -> Dictionary:
	return _lookup(_by_content_id, content_id, "content_id")


func _lookup(registry: Dictionary[String, Node], raw_id: String, id_name: String) -> Dictionary:
	var lookup_id: String = raw_id.strip_edges()
	if lookup_id.is_empty():
		return {
			"ok": false,
			"node": null,
			"error": "Cannot look up %s with an empty value." % id_name,
		}
	if not registry.has(lookup_id):
		return {
			"ok": false,
			"node": null,
			"error": "No entity is registered for %s '%s'." % [id_name, lookup_id],
		}
	return {
		"ok": true,
		"node": registry[lookup_id],
		"error": "",
	}
