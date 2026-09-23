class_name VarkMissionRunState
extends RefCounted


var _loot_count: int = 0
var _loot_value: int = 0


func record_loot(value: int) -> bool:
	if value < 0:
		return false
	_loot_count += 1
	_loot_value += value
	return true


func get_summary() -> Dictionary:
	return {
		"loot_count": _loot_count,
		"loot_value": _loot_value,
	}


func capture_semantic_state() -> Dictionary:
	return get_summary()


func apply_semantic_state(snapshot: Dictionary) -> bool:
	if (
		snapshot.size() != 2
		or typeof(snapshot.get("loot_count", null)) != TYPE_INT
		or typeof(snapshot.get("loot_value", null)) != TYPE_INT
	):
		return false
	var count: int = int(snapshot.get("loot_count", -1))
	var value: int = int(snapshot.get("loot_value", -1))
	if count < 0 or value < 0:
		return false
	_loot_count = count
	_loot_value = value
	return true
