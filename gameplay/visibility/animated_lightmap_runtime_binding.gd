class_name VarkAnimatedLightRuntimeBinding
extends Node

const STATIC_BAKED_VISUAL_LAYER: int = 1 << 18

var _renderer: VarkAnimatedLightmapStaticRenderer = null
var _lights_by_id: Dictionary = {}
var _original_cull_mask_by_instance: Dictionary = {}
var _expected_light_ids := PackedStringArray()
var _last_errors := PackedStringArray()
var _configured: bool = false


func _exit_tree() -> void:
	dispose()


func configure(
	renderer: VarkAnimatedLightmapStaticRenderer,
	expected_light_ids: PackedStringArray,
	gameplay_lights: Array
) -> bool:
	dispose()
	_last_errors = PackedStringArray()
	if renderer == null or not renderer.is_applied():
		_last_errors.append("animated-light runtime binding requires an applied static renderer")
		return false
	if expected_light_ids.is_empty():
		_last_errors.append("animated-light runtime binding requires at least one expected gameplay-light ID")
		return false

	var expected: Dictionary = {}
	for light_id: String in expected_light_ids:
		var normalized: String = light_id.strip_edges()
		if normalized.is_empty() or expected.has(normalized):
			_last_errors.append("animated-light runtime binding has blank/duplicate expected light identity")
			continue
		expected[normalized] = true

	var resolved: Dictionary = {}
	for candidate: Variant in gameplay_lights:
		var light := candidate as VarkGameplayLight
		if light == null or not is_instance_valid(light):
			_last_errors.append("animated-light runtime binding received a non-gameplay-light candidate")
			continue
		var light_id: String = str(light.gameplay_light_id).strip_edges()
		if not expected.has(light_id):
			_last_errors.append("gameplay light '%s' is not present in the baked static-light layout" % light_id)
			continue
		if resolved.has(light_id):
			_last_errors.append("duplicate runtime gameplay light '%s'" % light_id)
			continue
		resolved[light_id] = light

	for key: Variant in expected.keys():
		var light_id: String = str(key)
		if not resolved.has(light_id):
			_last_errors.append("missing runtime gameplay light '%s' required by the baked layout" % light_id)
	if not _last_errors.is_empty():
		return false

	_renderer = renderer
	_expected_light_ids = expected_light_ids.duplicate()
	_assign_static_renderer_layer()
	for light_id: String in _expected_light_ids:
		var light: VarkGameplayLight = resolved[light_id]
		_lights_by_id[light_id] = light
		var callback := Callable(self, "_on_runtime_weight_changed")
		if not light.runtime_weight_changed.is_connected(callback):
			light.runtime_weight_changed.connect(callback)
		var emitter: Light3D = light.get_emitter()
		if emitter != null:
			_original_cull_mask_by_instance[light.get_instance_id()] = emitter.light_cull_mask
			emitter.light_cull_mask &= ~STATIC_BAKED_VISUAL_LAYER
		_renderer.set_light_weight(light_id, light.get_runtime_light_weight())
	_configured = true
	return true


func dispose() -> void:
	var callback := Callable(self, "_on_runtime_weight_changed")
	for light_id: String in _lights_by_id.keys():
		var light := _lights_by_id[light_id] as VarkGameplayLight
		if light == null or not is_instance_valid(light):
			continue
		if light.runtime_weight_changed.is_connected(callback):
			light.runtime_weight_changed.disconnect(callback)
		var emitter: Light3D = light.get_emitter()
		var instance_id: int = light.get_instance_id()
		if emitter != null and _original_cull_mask_by_instance.has(instance_id):
			emitter.light_cull_mask = int(_original_cull_mask_by_instance[instance_id])
	_lights_by_id.clear()
	_original_cull_mask_by_instance.clear()
	_expected_light_ids = PackedStringArray()
	_renderer = null
	_configured = false


func is_configured() -> bool:
	return _configured


func get_validation_errors() -> PackedStringArray:
	return _last_errors.duplicate()


func get_bound_light_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for light_id: String in _expected_light_ids:
		if _lights_by_id.has(light_id):
			result.append(light_id)
	return result


func get_debug_state() -> Dictionary:
	var static_mesh_count: int = 0
	var static_layer_correct_count: int = 0
	if _renderer != null and is_instance_valid(_renderer):
		for candidate: Node in _renderer.find_children("Page_*", "MeshInstance3D", true, false):
			var mesh_instance := candidate as MeshInstance3D
			if mesh_instance == null:
				continue
			static_mesh_count += 1
			if mesh_instance.layers == STATIC_BAKED_VISUAL_LAYER:
				static_layer_correct_count += 1
	var realtime_static_receiver_excluded: bool = true
	for light_id: String in _lights_by_id.keys():
		var light := _lights_by_id[light_id] as VarkGameplayLight
		var emitter: Light3D = light.get_emitter() if light != null else null
		if emitter == null or (emitter.light_cull_mask & STATIC_BAKED_VISUAL_LAYER) != 0:
			realtime_static_receiver_excluded = false
	return {
		"configured": _configured,
		"bound_light_ids": get_bound_light_ids(),
		"static_baked_visual_layer": STATIC_BAKED_VISUAL_LAYER,
		"static_page_mesh_count": static_mesh_count,
		"static_page_layer_correct_count": static_layer_correct_count,
		"realtime_static_receiver_excluded": realtime_static_receiver_excluded,
	}


func _assign_static_renderer_layer() -> void:
	if _renderer == null:
		return
	for candidate: Node in _renderer.find_children("Page_*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.layers = STATIC_BAKED_VISUAL_LAYER


func _on_runtime_weight_changed(light_id: String, weight: float) -> void:
	if not _configured or _renderer == null or not _lights_by_id.has(light_id):
		return
	_renderer.set_light_weight(light_id, weight)
