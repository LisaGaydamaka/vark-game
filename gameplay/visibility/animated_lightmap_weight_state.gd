class_name VarkAnimatedLightmapWeightState
extends RefCounted

var _light_ids := PackedStringArray()
var _weight_index_by_light: Dictionary = {}
var _weights := PackedFloat32Array()
var _dirty_indices: Dictionary = {}
var _revision: int = 0


func configure(layout: VarkAnimatedLightmapLayout) -> bool:
	_light_ids = PackedStringArray()
	_weight_index_by_light.clear()
	_weights = PackedFloat32Array()
	_dirty_indices.clear()
	_revision = 0
	if layout == null:
		return false
	_light_ids = layout.light_ids.duplicate()
	_weights.resize(_light_ids.size())
	_weights.fill(0.0)
	for index: int in _light_ids.size():
		_weight_index_by_light[_light_ids[index]] = index
	return true


func set_light_weight(light_id: String, weight: float) -> bool:
	if not _weight_index_by_light.has(light_id):
		return false
	var index: int = int(_weight_index_by_light[light_id])
	var clamped: float = clampf(weight, 0.0, 1.0)
	if is_equal_approx(_weights[index], clamped):
		return false
	_weights[index] = clamped
	_dirty_indices[index] = true
	_revision += 1
	return true


func get_light_weight(light_id: String) -> float:
	if not _weight_index_by_light.has(light_id):
		return 0.0
	return _weights[int(_weight_index_by_light[light_id])]


func get_weight_buffer() -> PackedFloat32Array:
	return _weights.duplicate()


func get_revision() -> int:
	return _revision


func consume_dirty_updates() -> Array[Dictionary]:
	var indices: Array[int] = []
	for key: Variant in _dirty_indices.keys():
		indices.append(int(key))
	indices.sort()
	var updates: Array[Dictionary] = []
	for index: int in indices:
		updates.append({
			"weight_index": index,
			"light_id": _light_ids[index],
			"weight": _weights[index],
		})
	_dirty_indices.clear()
	return updates
