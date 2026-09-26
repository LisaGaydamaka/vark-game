class_name VarkMissionRunState
extends RefCounted


var _loot_count: int = 0
var _loot_value: int = 0
var _loot_available_count: int = 0
var _loot_available_value: int = 0
var _available_loot_configured: bool = false


func configure_available_loot(count: int, value: int) -> bool:
	if _available_loot_configured or count < 0 or value < 0:
		return false
	_loot_available_count = count
	_loot_available_value = value
	_available_loot_configured = true
	return true


func record_loot(value: int) -> bool:
	if value < 0:
		return false
	_loot_count += 1
	_loot_value += value
	return true


func get_summary() -> Dictionary:
	var result := {
		"loot_count": _loot_count,
		"loot_value": _loot_value,
	}
	if _available_loot_configured:
		result["loot_available_count"] = _loot_available_count
		result["loot_available_value"] = _loot_available_value
	return result


func capture_semantic_state() -> Dictionary:
	return get_summary()


func apply_semantic_state(snapshot: Dictionary) -> bool:
	if snapshot.size() != 2 and snapshot.size() != 4:
		return false
	if (
		typeof(snapshot.get("loot_count", null)) != TYPE_INT
		or typeof(snapshot.get("loot_value", null)) != TYPE_INT
	):
		return false
	var count: int = int(snapshot.get("loot_count", -1))
	var value: int = int(snapshot.get("loot_value", -1))
	if count < 0 or value < 0:
		return false

	if snapshot.size() == 4:
		if (
			typeof(snapshot.get("loot_available_count", null)) != TYPE_INT
			or typeof(snapshot.get("loot_available_value", null)) != TYPE_INT
		):
			return false
		var available_count: int = int(snapshot.get("loot_available_count", -1))
		var available_value: int = int(snapshot.get("loot_available_value", -1))
		if available_count < 0 or available_value < 0:
			return false
		if (
			_available_loot_configured
			and (
				available_count != _loot_available_count
				or available_value != _loot_available_value
			)
		):
			return false
		_loot_available_count = available_count
		_loot_available_value = available_value
		_available_loot_configured = true

	_loot_count = count
	_loot_value = value
	return true
