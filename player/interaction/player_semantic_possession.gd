class_name PlayerSemanticPossession
extends RefCounted


var _owned: Dictionary[String, bool] = {}


func has(possession_id: StringName) -> bool:
	var normalized: String = str(possession_id).strip_edges()
	return not normalized.is_empty() and _owned.has(normalized)


func grant(possession_id: StringName) -> bool:
	var normalized: String = str(possession_id).strip_edges()
	if normalized.is_empty():
		return false
	_owned[normalized] = true
	return true


func clear() -> void:
	_owned.clear()


func get_ids() -> Array[String]:
	var ids: Array[String] = []
	for id_value: String in _owned.keys():
		ids.append(id_value)
	ids.sort()
	return ids


func capture_semantic_state() -> Dictionary:
	return {
		"ids": get_ids(),
	}


func apply_semantic_state(snapshot: Dictionary) -> bool:
	if snapshot.size() != 1 or typeof(snapshot.get("ids", null)) != TYPE_ARRAY:
		return false
	var restored: Dictionary[String, bool] = {}
	for value: Variant in snapshot.get("ids", []):
		if typeof(value) != TYPE_STRING:
			return false
		var normalized: String = str(value).strip_edges()
		if normalized.is_empty() or restored.has(normalized):
			return false
		restored[normalized] = true
	_owned = restored
	return true


func get_debug_summary() -> Dictionary:
	return {
		"count": _owned.size(),
		"ids": get_ids(),
	}
