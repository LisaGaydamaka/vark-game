class_name VarkAnimatedLightmapSurface
extends Node

const AnimatedLightShader = preload(
	"res://gameplay/visibility/animated_lightmap_surface.gdshader"
)

var _mesh_instance: MeshInstance3D = null
var _data: VarkAnimatedLightmapData = null
var _weights: Dictionary = {}
var _materials: Array[ShaderMaterial] = []
var _composite_texture: ImageTexture = null
var _applied: bool = false
var _last_errors := PackedStringArray()

func configure(
	mesh_instance: MeshInstance3D,
	data: VarkAnimatedLightmapData,
	expected_source_map_path: String,
	expected_light_descriptors: Dictionary
) -> bool:
	_clear_runtime_state()
	if mesh_instance == null or data == null:
		_last_errors.append("animated-lightmap surface requires mesh and bake data")
		return false
	var geometry_fingerprint: String = (
		VarkAnimatedLightmapBaker.compute_geometry_fingerprint(mesh_instance)
	)
	_last_errors = data.get_validation_errors(
		expected_source_map_path,
		geometry_fingerprint,
		expected_light_descriptors
	)
	if not _last_errors.is_empty():
		return false
	_mesh_instance = mesh_instance
	_data = data
	for light_id: String in data.get_light_ids():
		_weights[light_id] = 0.0
	if not _install_materials():
		_clear_runtime_state()
		_last_errors.append("failed to install animated-lightmap materials")
		return false
	_applied = true
	_rebuild_composite()
	return true

func is_applied() -> bool:
	return _applied

func get_validation_errors() -> PackedStringArray:
	return _last_errors.duplicate()

func set_light_weight(light_id: String, weight: float) -> bool:
	if not _applied or not _weights.has(light_id):
		return false
	var clamped: float = clampf(weight, 0.0, 1.0)
	if is_equal_approx(float(_weights[light_id]), clamped):
		return false
	_weights[light_id] = clamped
	_rebuild_composite()
	return true

func get_light_weight(light_id: String) -> float:
	return float(_weights.get(light_id, 0.0))

func get_composite_image() -> Image:
	if _composite_texture == null:
		return null
	return _composite_texture.get_image()

func get_debug_state() -> Dictionary:
	return {
		"applied": _applied,
		"weights": _weights.duplicate(true),
		"texture_size": _data.texture_size if _data != null else Vector2i.ZERO,
		"errors": get_validation_errors(),
	}

func _install_materials() -> bool:
	if _mesh_instance == null or _mesh_instance.mesh == null:
		return false
	_materials.clear()
	for surface_index: int in _mesh_instance.mesh.get_surface_count():
		var authored: Material = _mesh_instance.mesh.surface_get_material(
			surface_index
		)
		var standard := authored as StandardMaterial3D
		var material := ShaderMaterial.new()
		material.shader = AnimatedLightShader
		material.set_shader_parameter(
			"base_albedo",
			standard.albedo_color if standard != null else Color.WHITE
		)
		material.set_shader_parameter(
			"base_roughness",
			standard.roughness if standard != null else 1.0
		)
		material.set_shader_parameter(
			"base_metallic",
			standard.metallic if standard != null else 0.0
		)
		_mesh_instance.set_surface_override_material(surface_index, material)
		_materials.append(material)
	return not _materials.is_empty()

func _rebuild_composite() -> void:
	if not _applied or _data == null:
		return
	var width: int = _data.texture_size.x
	var height: int = _data.texture_size.y
	var bytes := PackedByteArray()
	bytes.resize(width * height * 4)
	var layers: Dictionary = {}
	for light_id: String in _data.get_light_ids():
		layers[light_id] = _data.get_light_layer_bytes(light_id)
	for pixel_index: int in width * height:
		var byte_offset: int = pixel_index * 4
		var red: float = 0.0
		var green: float = 0.0
		var blue: float = 0.0
		for light_id: String in _data.get_light_ids():
			var weight: float = float(_weights.get(light_id, 0.0))
			if weight <= 0.0:
				continue
			var layer: PackedByteArray = layers.get(light_id, PackedByteArray())
			if layer.size() != bytes.size():
				continue
			red += float(layer[byte_offset]) * weight
			green += float(layer[byte_offset + 1]) * weight
			blue += float(layer[byte_offset + 2]) * weight
		bytes[byte_offset] = clampi(roundi(red), 0, 255)
		bytes[byte_offset + 1] = clampi(roundi(green), 0, 255)
		bytes[byte_offset + 2] = clampi(roundi(blue), 0, 255)
		bytes[byte_offset + 3] = 255
	var image := Image.create_from_data(
		width, height, false, Image.FORMAT_RGBA8, bytes
	)
	if _composite_texture == null:
		_composite_texture = ImageTexture.create_from_image(image)
	else:
		_composite_texture.update(image)
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter(
			"animated_direct_light",
			_composite_texture
		)

func _clear_runtime_state() -> void:
	if _mesh_instance != null and _mesh_instance.mesh != null:
		for surface_index: int in _mesh_instance.mesh.get_surface_count():
			_mesh_instance.set_surface_override_material(surface_index, null)
	_mesh_instance = null
	_data = null
	_weights.clear()
	_materials.clear()
	_composite_texture = null
	_applied = false
	_last_errors = PackedStringArray()
