class_name VarkAnimatedLightmapStaticRenderer
extends Node3D

const StaticLightShader = preload(
	"res://gameplay/visibility/animated_lightmap_static_renderer.gdshader"
)

var _layout: VarkAnimatedLightmapLayout = null
var _bake: VarkAnimatedLightmapBakeData = null
var _descriptors: Dictionary = {}
var _weight_state := VarkAnimatedLightmapWeightState.new()
var _contribution_texture: Texture2DArray = null
var _light_state_texture: ImageTexture = null
var _light_state_image: Image = null
var _tile_lookup_texture: ImageTexture = null
var _tile_lookup_image: Image = null
var _tile_lookup_row_by_id: Dictionary = {}
var _page_layer_base: Dictionary = {}
var _page_layer_count: Dictionary = {}
var _runtime_contribution_layer_count: int = 0
var _renderer_root: Node3D = null
var _page_materials: Dictionary = {}
var _applied: bool = false
var _last_errors := PackedStringArray()
var _contribution_texture_build_count: int = 0
var _light_state_texture_upload_count: int = 0


func configure(
	layout: VarkAnimatedLightmapLayout,
	bake: VarkAnimatedLightmapBakeData,
	expected_source_map_path: String,
	light_descriptors: Dictionary
) -> bool:
	_clear_runtime_state()
	if layout == null or bake == null:
		_last_errors.append("static surface renderer requires layout and bake data")
		return false
	_last_errors = layout.get_validation_errors(
		layout.geometry_fingerprint,
		VarkAnimatedLightmapLayoutBuilder.compute_light_influence_fingerprint(
			light_descriptors
		)
	)
	_last_errors.append_array(
		bake.get_validation_errors(
			expected_source_map_path,
			layout,
			light_descriptors
		)
	)
	if not _last_errors.is_empty():
		return false

	_layout = layout
	_bake = bake
	_descriptors = light_descriptors.duplicate(true)
	if not _weight_state.configure(layout):
		_last_errors.append("failed to configure static-light weight state")
		_clear_runtime_state(false)
		return false
	_build_runtime_slot_layout()
	if not _build_contribution_texture():
		_last_errors.append("failed to build page-local-slot contribution Texture2DArray")
		_clear_runtime_state(false)
		return false
	if not _build_light_state_texture():
		_last_errors.append("failed to build global animated-light state texture")
		_clear_runtime_state(false)
		return false
	if not _build_tile_lookup_texture():
		_last_errors.append("failed to build per-tile animated-light lookup texture")
		_clear_runtime_state(false)
		return false
	if not _build_page_geometry():
		_last_errors.append("failed to build static-light page render geometry")
		_clear_runtime_state(false)
		return false
	_applied = true
	return true


func is_applied() -> bool:
	return _applied


func dispose() -> void:
	_clear_runtime_state()


func get_validation_errors() -> PackedStringArray:
	return _last_errors.duplicate()


func set_light_weight(light_id: String, weight: float) -> bool:
	if not _applied or not _weight_state.set_light_weight(light_id, weight):
		return false
	_upload_light_state_texture()
	return true


func get_light_weight(light_id: String) -> float:
	return _weight_state.get_light_weight(light_id)


func get_weight_updates() -> Array[Dictionary]:
	return _weight_state.consume_dirty_updates()


func sample_weighted_direct_at_world_point(
	world_point: Vector3,
	plane_tolerance: float = 0.08
) -> Color:
	if not _applied or _layout == null or _bake == null:
		return Color(0, 0, 0, 1)
	var face: Dictionary = VarkAnimatedLightmapLayoutBuilder.find_face_at_world_point(
		_layout, world_point, plane_tolerance
	)
	if face.is_empty():
		return Color(0, 0, 0, 1)
	var continuous: Vector2 = VarkAnimatedLightmapLayoutBuilder.world_to_face_texel(
		face, world_point, _layout.texel_size_meters
	)
	var texel := Vector2i(floori(continuous.x), floori(continuous.y))
	var face_id: String = str(face.get("face_id", ""))
	var result := Color(0, 0, 0, 1)
	for light_id: String in _layout.light_ids:
		var weight: float = _weight_state.get_light_weight(light_id)
		if weight <= 0.0:
			continue
		var scalar: float = _bake.get_contribution_at_face_texel(
			_layout, face_id, texel, light_id
		)
		if scalar <= 0.0:
			continue
		var descriptor: Dictionary = _descriptors.get(light_id, {})
		var color: Color = descriptor.get("color", Color.WHITE)
		result.r += color.r * scalar * weight
		result.g += color.g * scalar * weight
		result.b += color.b * scalar * weight
	return result


func get_debug_state() -> Dictionary:
	var legacy_layers: int = _layout.contribution_layer_count if _layout != null else 0
	return {
		"applied": _applied,
		"page_mesh_count": (
			_renderer_root.get_child_count()
			if _renderer_root != null else 0
		),
		"page_material_count": _page_materials.size(),
		"layout_page_count": _layout.pages.size() if _layout != null else 0,
		"layout_tile_count": _layout.tiles.size() if _layout != null else 0,
		"contribution_texture_layers": _runtime_contribution_layer_count,
		"offline_contribution_layers": legacy_layers,
		"runtime_layer_reduction": legacy_layers - _runtime_contribution_layer_count,
		"contribution_texture_build_count": _contribution_texture_build_count,
		"light_state_texture_upload_count": _light_state_texture_upload_count,
		"weight_texture_upload_count": _light_state_texture_upload_count,
		"weight_revision": _weight_state.get_revision(),
		"binding_transport": &"vertex_color_alpha_to_tile_lookup",
		"errors": get_validation_errors(),
	}


func get_contribution_texture_instance_id() -> int:
	return (
		_contribution_texture.get_instance_id()
		if _contribution_texture != null else 0
	)


func _build_runtime_slot_layout() -> void:
	_page_layer_base.clear()
	_page_layer_count.clear()
	_runtime_contribution_layer_count = 0
	if _layout == null:
		return
	for page: Dictionary in _layout.pages:
		var page_index: int = int(page.get("page_index", -1))
		var max_slots: int = 0
		for tile_id: String in page.get("tile_ids", PackedStringArray()):
			var tile: Dictionary = _layout.get_tile(tile_id)
			max_slots = maxi(
				max_slots,
				(tile.get("candidate_light_ids", PackedStringArray()) as PackedStringArray).size()
			)
		_page_layer_base[page_index] = _runtime_contribution_layer_count
		_page_layer_count[page_index] = max_slots
		_runtime_contribution_layer_count += max_slots


func _build_contribution_texture() -> bool:
	if _layout == null or _bake == null:
		return false
	var layer_count: int = maxi(_runtime_contribution_layer_count, 1)
	var images: Array[Image] = []
	for _index: int in layer_count:
		var image := Image.create_empty(
			_layout.page_size,
			_layout.page_size,
			false,
			VarkAnimatedLightmapLayout.HDR_IMAGE_FORMAT
		)
		image.fill(Color(0, 0, 0, 1))
		images.append(image)

	var source_images: Dictionary = {}
	for tile: Dictionary in _layout.tiles:
		var tile_id: String = str(tile.get("tile_id", ""))
		var page_index: int = int(tile.get("page_index", -1))
		var page_base: int = int(_page_layer_base.get(page_index, -1))
		if page_base < 0:
			return false
		var rect_position: Vector2i = tile.get("rect_position", Vector2i.ZERO)
		var rect_size: Vector2i = tile.get("rect_size", Vector2i.ZERO)
		var binding_by_light: Dictionary = {}
		for binding: Dictionary in tile.get("light_bindings", []):
			binding_by_light[str(binding.get("light_id", ""))] = binding
		for light_id: String in _bake.get_tile_light_ids(tile_id):
			var binding: Dictionary = binding_by_light.get(light_id, {})
			var slot: int = int(binding.get("slot", -1))
			if slot < 0 or slot >= int(_page_layer_count.get(page_index, 0)):
				return false
			var target_layer: int = page_base + slot
			var source_key: String = _bake.get_layer_key(page_index, light_id)
			var source: Image = source_images.get(source_key, null)
			if source == null:
				var bytes: PackedByteArray = _bake.get_layer_bytes(page_index, light_id)
				if bytes.is_empty():
					return false
				source = Image.create_from_data(
					_layout.page_size,
					_layout.page_size,
					false,
					VarkAnimatedLightmapLayout.HDR_IMAGE_FORMAT,
					bytes
				)
				if source == null or source.is_empty():
					return false
				source_images[source_key] = source
			images[target_layer].blit_rect(
				source,
				Rect2i(rect_position, rect_size),
				rect_position
			)

	_contribution_texture = Texture2DArray.new()
	var error: Error = _contribution_texture.create_from_images(images)
	if error != OK:
		_contribution_texture = null
		return false
	_contribution_texture_build_count += 1
	return true


func _build_light_state_texture() -> bool:
	if _layout == null:
		return false
	var width: int = maxi(_layout.light_ids.size(), 1)
	_light_state_image = Image.create_empty(width, 1, false, Image.FORMAT_RGBAH)
	_light_state_image.fill(Color(0, 0, 0, 0))
	for index: int in _layout.light_ids.size():
		var light_id: String = _layout.light_ids[index]
		var descriptor: Dictionary = _descriptors.get(light_id, {})
		var color: Color = descriptor.get("color", Color.WHITE)
		_light_state_image.set_pixel(index, 0, Color(color.r, color.g, color.b, 0.0))
	_light_state_texture = ImageTexture.create_from_image(_light_state_image)
	_light_state_texture_upload_count += 1
	return _light_state_texture != null


func _upload_light_state_texture() -> void:
	if _light_state_image == null or _light_state_texture == null or _layout == null:
		return
	var weights: PackedFloat32Array = _weight_state.get_weight_buffer()
	for index: int in _layout.light_ids.size():
		var light_id: String = _layout.light_ids[index]
		var descriptor: Dictionary = _descriptors.get(light_id, {})
		var color: Color = descriptor.get("color", Color.WHITE)
		var weight: float = weights[index] if index < weights.size() else 0.0
		_light_state_image.set_pixel(index, 0, Color(color.r, color.g, color.b, weight))
	_light_state_texture.update(_light_state_image)
	_light_state_texture_upload_count += 1


func _build_tile_lookup_texture() -> bool:
	if _layout == null:
		return false
	_tile_lookup_row_by_id.clear()
	var height: int = maxi(_layout.tiles.size(), 1)
	_tile_lookup_image = Image.create_empty(2, height, false, Image.FORMAT_RGBAH)
	_tile_lookup_image.fill(Color(-1, -1, -1, -1))
	var light_count: int = maxi(_layout.light_ids.size(), 1)
	for tile_index: int in _layout.tiles.size():
		var tile: Dictionary = _layout.tiles[tile_index]
		var tile_id: String = str(tile.get("tile_id", ""))
		_tile_lookup_row_by_id[tile_id] = tile_index
		var first := Color(-1, -1, -1, -1)
		var second := Color(-1, -1, -1, -1)
		for binding: Dictionary in tile.get("light_bindings", []):
			var slot: int = int(binding.get("slot", -1))
			var weight_index: int = int(binding.get("weight_index", -1))
			if slot < 0 or slot >= 8 or weight_index < 0:
				continue
			var state_u: float = (float(weight_index) + 0.5) / float(light_count)
			if slot < 4:
				first = _with_color_channel(first, slot, state_u)
			else:
				second = _with_color_channel(second, slot - 4, state_u)
		_tile_lookup_image.set_pixel(0, tile_index, first)
		_tile_lookup_image.set_pixel(1, tile_index, second)
	_tile_lookup_texture = ImageTexture.create_from_image(_tile_lookup_image)
	return _tile_lookup_texture != null


func _with_color_channel(color: Color, channel: int, value: float) -> Color:
	match channel:
		0:
			color.r = value
		1:
			color.g = value
		2:
			color.b = value
		3:
			color.a = value
	return color


func _build_page_geometry() -> bool:
	if _layout == null or _bake == null:
		return false
	_renderer_root = Node3D.new()
	_renderer_root.name = "StaticSurfacePages"
	add_child(_renderer_root)
	for page: Dictionary in _layout.pages:
		var mesh: ArrayMesh = _build_page_mesh(page)
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var page_index: int = int(page.get("page_index", -1))
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Page_%03d" % page_index
		mesh_instance.mesh = mesh
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material: ShaderMaterial = _build_page_material(page)
		if material == null:
			return false
		mesh_instance.set_surface_override_material(0, material)
		_renderer_root.add_child(mesh_instance)
		_page_materials[str(page_index)] = material
	return (
		_renderer_root.get_child_count() > 0
		and _renderer_root.get_child_count() == _layout.pages.size()
	)


func _build_page_material(page: Dictionary) -> ShaderMaterial:
	var page_index: int = int(page.get("page_index", -1))
	var material := ShaderMaterial.new()
	material.shader = StaticLightShader
	material.set_shader_parameter("direct_layers", _contribution_texture)
	material.set_shader_parameter("tile_light_lookup", _tile_lookup_texture)
	material.set_shader_parameter("light_states", _light_state_texture)
	material.set_shader_parameter("page_layer_base", int(_page_layer_base.get(page_index, 0)))
	material.set_shader_parameter("page_layer_count", int(_page_layer_count.get(page_index, 0)))
	return material


func _build_page_mesh(page: Dictionary) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var material_params := PackedVector2Array()
	var indices := PackedInt32Array()
	var tile_ids: PackedStringArray = page.get("tile_ids", PackedStringArray())
	for tile_id: String in tile_ids:
		var tile: Dictionary = _layout.get_tile(tile_id)
		if tile.is_empty():
			return null
		var face: Dictionary = _layout.get_face(str(tile.get("face_id", "")))
		if face.is_empty():
			return null
		var geometry: Dictionary = _build_tile_geometry_arrays(face, tile)
		var tile_vertices: PackedVector3Array = geometry.get("vertices", PackedVector3Array())
		if tile_vertices.is_empty():
			continue
		var base: int = vertices.size()
		vertices.append_array(tile_vertices)
		normals.append_array(geometry.get("normals", PackedVector3Array()))
		uvs.append_array(geometry.get("uvs", PackedVector2Array()))
		colors.append_array(geometry.get("colors", PackedColorArray()))
		material_params.append_array(geometry.get("material_params", PackedVector2Array()))
		var tile_indices: PackedInt32Array = geometry.get("indices", PackedInt32Array())
		for tile_index: int in tile_indices:
			indices.append(base + tile_index)
	if vertices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV2] = material_params
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_tile_geometry_arrays(face: Dictionary, tile: Dictionary) -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var material_params := PackedVector2Array()
	var indices := PackedInt32Array()
	var authored: StandardMaterial3D = _load_authored_material(str(face.get("material_id", "")))
	var albedo: Color = authored.albedo_color if authored != null else Color.WHITE
	var roughness: float = authored.roughness if authored != null else 1.0
	var metallic: float = authored.metallic if authored != null else 0.0
	var tile_id: String = str(tile.get("tile_id", ""))
	var row_index: int = int(_tile_lookup_row_by_id.get(tile_id, 0))
	var row_count: int = maxi(_layout.tiles.size(), 1)
	var lookup_v: float = (float(row_index) + 0.5) / float(row_count)
	var triangles: PackedVector2Array = face.get("triangles_uv", PackedVector2Array())
	var offset: Vector2i = tile.get("texel_offset", Vector2i.ZERO)
	var useful: Vector2i = tile.get("useful_size", Vector2i.ZERO)
	var local_min := Vector2(
		float(offset.x) * _layout.texel_size_meters,
		float(offset.y) * _layout.texel_size_meters
	)
	var local_max := Vector2(
		float(offset.x + useful.x) * _layout.texel_size_meters,
		float(offset.y + useful.y) * _layout.texel_size_meters
	)
	for triangle_index: int in range(0, triangles.size(), 3):
		if triangle_index + 2 >= triangles.size():
			break
		var polygon: Array[Vector2] = [
			triangles[triangle_index],
			triangles[triangle_index + 1],
			triangles[triangle_index + 2],
		]
		polygon = _clip_polygon(polygon, local_min, local_max)
		if polygon.size() < 3:
			continue
		for fan_index: int in range(1, polygon.size() - 1):
			var triangle_points: Array[Vector2] = [
				polygon[0], polygon[fan_index], polygon[fan_index + 1],
			]
			var base: int = vertices.size()
			for local_point: Vector2 in triangle_points:
				vertices.append(
					VarkAnimatedLightmapLayoutBuilder.face_local_point_world(face, local_point)
				)
				normals.append(face.get("lighting_normal", face.get("normal", Vector3.UP)))
				uvs.append(_atlas_uv_for_local_point(tile, local_point))
				colors.append(Color(albedo.r, albedo.g, albedo.b, lookup_v))
				material_params.append(Vector2(roughness, metallic))
			indices.append_array(PackedInt32Array([base, base + 1, base + 2]))
	return {
		"vertices": vertices,
		"normals": normals,
		"uvs": uvs,
		"colors": colors,
		"material_params": material_params,
		"indices": indices,
	}


func _atlas_uv_for_local_point(tile: Dictionary, local_point: Vector2) -> Vector2:
	var offset: Vector2i = tile.get("texel_offset", Vector2i.ZERO)
	var rect_position: Vector2i = tile.get("rect_position", Vector2i.ZERO)
	var face_texel: Vector2 = local_point / _layout.texel_size_meters
	var tile_texel: Vector2 = face_texel - Vector2(offset)
	var atlas_pixel: Vector2 = (
		Vector2(rect_position)
		+ Vector2.ONE * float(_layout.guard_texels)
		+ tile_texel
	)
	return atlas_pixel / float(_layout.page_size)


func _clip_polygon(
	polygon: Array[Vector2],
	minimum: Vector2,
	maximum: Vector2
) -> Array[Vector2]:
	var result: Array[Vector2] = polygon
	result = _clip_axis(result, 0, minimum.x, true)
	result = _clip_axis(result, 0, maximum.x, false)
	result = _clip_axis(result, 1, minimum.y, true)
	result = _clip_axis(result, 1, maximum.y, false)
	return result


func _clip_axis(
	polygon: Array[Vector2],
	axis: int,
	boundary: float,
	keep_greater: bool
) -> Array[Vector2]:
	var output: Array[Vector2] = []
	if polygon.is_empty():
		return output
	var previous: Vector2 = polygon[polygon.size() - 1]
	var previous_inside: bool = _inside_boundary(previous[axis], boundary, keep_greater)
	for current: Vector2 in polygon:
		var current_inside: bool = _inside_boundary(current[axis], boundary, keep_greater)
		if current_inside != previous_inside:
			var denominator: float = current[axis] - previous[axis]
			if absf(denominator) > 0.0000001:
				var t: float = (boundary - previous[axis]) / denominator
				output.append(previous.lerp(current, clampf(t, 0.0, 1.0)))
		if current_inside:
			output.append(current)
		previous = current
		previous_inside = current_inside
	return output


func _inside_boundary(value: float, boundary: float, keep_greater: bool) -> bool:
	return value >= boundary - 0.000001 if keep_greater else value <= boundary + 0.000001


func _load_authored_material(material_id: String) -> StandardMaterial3D:
	var path: String = "res://textures/%s.tres" % material_id
	if not ResourceLoader.exists(path):
		return null
	return load(path) as StandardMaterial3D


func _clear_runtime_state(clear_errors: bool = true) -> void:
	if _renderer_root != null and is_instance_valid(_renderer_root):
		if _renderer_root.get_parent() == self:
			remove_child(_renderer_root)
		_renderer_root.free()
	_renderer_root = null
	_layout = null
	_bake = null
	_descriptors.clear()
	_weight_state = VarkAnimatedLightmapWeightState.new()
	_contribution_texture = null
	_light_state_texture = null
	_light_state_image = null
	_tile_lookup_texture = null
	_tile_lookup_image = null
	_tile_lookup_row_by_id.clear()
	_page_layer_base.clear()
	_page_layer_count.clear()
	_runtime_contribution_layer_count = 0
	_page_materials.clear()
	_applied = false
	_contribution_texture_build_count = 0
	_light_state_texture_upload_count = 0
	if clear_errors:
		_last_errors = PackedStringArray()
