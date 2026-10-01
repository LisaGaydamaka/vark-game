class_name VarkAnimatedLightmapBakeData
extends Resource

const CURRENT_FORMAT_VERSION: int = 1
const COMPRESSION_MODE: int = FileAccess.COMPRESSION_DEFLATE

@export var format_version: int = CURRENT_FORMAT_VERSION
@export_file("*.map") var source_map_path: String = ""
@export var source_sha256: String = ""
@export var layout_fingerprint: String = ""
@export var geometry_fingerprint: String = ""
@export var light_bake_fingerprint: String = ""
@export var storage_format: StringName = VarkAnimatedLightmapLayout.STORAGE_FORMAT
@export var page_size: int = VarkAnimatedLightmapLayout.DEFAULT_PAGE_SIZE
@export var supersample_grid: int = 4
@export var light_descriptors: Dictionary = {}
@export var tile_contributing_light_ids: Dictionary = {}
@export var layer_data_base64: Dictionary = {}


func get_layer_key(page_index: int, light_id: String) -> String:
	return "%d|%s" % [page_index, light_id]


func get_layer_bytes(page_index: int, light_id: String) -> PackedByteArray:
	var key: String = get_layer_key(page_index, light_id)
	var encoded: String = str(layer_data_base64.get(key, ""))
	if encoded.is_empty() or page_size <= 0:
		return PackedByteArray()
	var compressed: PackedByteArray = Marshalls.base64_to_raw(encoded)
	if compressed.is_empty():
		return PackedByteArray()
	return compressed.decompress(
		page_size * page_size * VarkAnimatedLightmapLayout.BYTES_PER_TEXEL,
		COMPRESSION_MODE
	)


func set_layer_bytes(
	page_index: int,
	light_id: String,
	bytes: PackedByteArray
) -> bool:
	if (
		page_index < 0
		or light_id.strip_edges().is_empty()
		or page_size <= 0
		or bytes.size()
			!= page_size * page_size * VarkAnimatedLightmapLayout.BYTES_PER_TEXEL
	):
		return false
	layer_data_base64[get_layer_key(page_index, light_id)] = (
		Marshalls.raw_to_base64(bytes.compress(COMPRESSION_MODE))
	)
	return true


func get_tile_light_ids(tile_id: String) -> PackedStringArray:
	var result := PackedStringArray()
	var value: Variant = tile_contributing_light_ids.get(tile_id, [])
	if value is PackedStringArray:
		result = (value as PackedStringArray).duplicate()
	elif value is Array:
		for item: Variant in value as Array:
			result.append(str(item))
	result.sort()
	return result


func get_layer_keys() -> PackedStringArray:
	var keys := PackedStringArray()
	for key: Variant in layer_data_base64.keys():
		keys.append(str(key))
	keys.sort()
	return keys


func get_contribution_at_face_texel(
	layout: VarkAnimatedLightmapLayout,
	face_id: String,
	face_texel: Vector2i,
	light_id: String
) -> float:
	if layout == null:
		return 0.0
	for tile: Dictionary in layout.tiles:
		if str(tile.get("face_id", "")) != face_id:
			continue
		var offset: Vector2i = tile.get("texel_offset", Vector2i.ZERO)
		var size: Vector2i = tile.get("useful_size", Vector2i.ZERO)
		if (
			face_texel.x < offset.x
			or face_texel.y < offset.y
			or face_texel.x >= offset.x + size.x
			or face_texel.y >= offset.y + size.y
		):
			continue
		if not get_tile_light_ids(str(tile.get("tile_id", ""))).has(light_id):
			return 0.0
		var page_index: int = int(tile.get("page_index", -1))
		var bytes: PackedByteArray = get_layer_bytes(page_index, light_id)
		if bytes.is_empty():
			return 0.0
		var image := Image.create_from_data(
			page_size,
			page_size,
			false,
			VarkAnimatedLightmapLayout.HDR_IMAGE_FORMAT,
			bytes
		)
		if image == null or image.is_empty():
			return 0.0
		var rect_position: Vector2i = tile.get(
			"rect_position", Vector2i.ZERO
		)
		var local: Vector2i = face_texel - offset
		var pixel: Vector2i = (
			rect_position
			+ Vector2i.ONE * layout.guard_texels
			+ local
		)
		return image.get_pixel(pixel.x, pixel.y).r
	return 0.0


func get_contribution_at_world_point(
	layout: VarkAnimatedLightmapLayout,
	world_point: Vector3,
	light_id: String,
	plane_tolerance: float = 0.08
) -> float:
	var face: Dictionary = VarkAnimatedLightmapLayoutBuilder.find_face_at_world_point(
		layout, world_point, plane_tolerance
	)
	if face.is_empty():
		return 0.0
	var continuous: Vector2 = VarkAnimatedLightmapLayoutBuilder.world_to_face_texel(
		face, world_point, layout.texel_size_meters
	)
	var texel := Vector2i(floori(continuous.x), floori(continuous.y))
	return get_contribution_at_face_texel(
		layout,
		str(face.get("face_id", "")),
		texel,
		light_id
	)


func get_validation_errors(
	expected_source_map_path: String,
	layout: VarkAnimatedLightmapLayout,
	expected_light_descriptors: Dictionary
) -> PackedStringArray:
	var errors := PackedStringArray()
	if format_version != CURRENT_FORMAT_VERSION:
		errors.append(
			"surface-light bake format %d is unsupported; expected %d"
			% [format_version, CURRENT_FORMAT_VERSION]
		)
	if layout == null:
		errors.append("surface-light bake requires a runtime layout")
		return errors
	if source_map_path != expected_source_map_path:
		errors.append(
			"source map mismatch: bake='%s' runtime='%s'"
			% [source_map_path, expected_source_map_path]
		)
	var current_sha: String = compute_file_sha256(expected_source_map_path)
	if current_sha.is_empty():
		errors.append("source map cannot be hashed: %s" % expected_source_map_path)
	elif source_sha256 != current_sha:
		errors.append(
			"source map hash mismatch: bake=%s runtime=%s"
			% [source_sha256, current_sha]
		)
	if layout_fingerprint != layout.representation_fingerprint:
		errors.append(
			"surface layout fingerprint mismatch: bake=%s runtime=%s"
			% [layout_fingerprint, layout.representation_fingerprint]
		)
	if geometry_fingerprint != layout.geometry_fingerprint:
		errors.append(
			"surface geometry fingerprint mismatch: bake=%s runtime=%s"
			% [geometry_fingerprint, layout.geometry_fingerprint]
		)
	var expected_light_fingerprint: String = compute_light_bake_fingerprint(
		expected_light_descriptors
	)
	if light_bake_fingerprint != expected_light_fingerprint:
		errors.append(
			"light bake fingerprint mismatch: bake=%s runtime=%s"
			% [light_bake_fingerprint, expected_light_fingerprint]
		)
	if storage_format != VarkAnimatedLightmapLayout.STORAGE_FORMAT:
		errors.append(
			"surface-light storage '%s' is unsupported; expected '%s'"
			% [storage_format, VarkAnimatedLightmapLayout.STORAGE_FORMAT]
		)
	if page_size != layout.page_size:
		errors.append(
			"surface-light page size mismatch: bake=%d runtime=%d"
			% [page_size, layout.page_size]
		)
	if supersample_grid <= 0:
		errors.append("surface-light supersample grid must be positive")

	var referenced_layers: Dictionary = {}
	for key: Variant in tile_contributing_light_ids.keys():
		var tile_id: String = str(key)
		var tile: Dictionary = layout.get_tile(tile_id)
		if tile.is_empty():
			errors.append("bake contains unknown tile '%s'" % tile_id)
			continue
		var candidate_ids: PackedStringArray = tile.get(
			"candidate_light_ids", PackedStringArray()
		)
		for light_id: String in get_tile_light_ids(tile_id):
			if not expected_light_descriptors.has(light_id):
				errors.append(
					"tile '%s' references unknown light '%s'"
					% [tile_id, light_id]
				)
				continue
			if not candidate_ids.has(light_id):
				errors.append(
					"tile '%s' contribution '%s' is outside accepted A influence mapping"
					% [tile_id, light_id]
				)
				continue
			var page_index: int = int(tile.get("page_index", -1))
			var layer_key: String = get_layer_key(page_index, light_id)
			referenced_layers[layer_key] = true
			var bytes: PackedByteArray = get_layer_bytes(page_index, light_id)
			if (
				bytes.size()
				!= page_size * page_size * VarkAnimatedLightmapLayout.BYTES_PER_TEXEL
			):
				errors.append(
					"missing/invalid contribution layer '%s' required by tile '%s'"
					% [layer_key, tile_id]
				)
	for layer_key: String in get_layer_keys():
		if not referenced_layers.has(layer_key):
			errors.append(
				"bake contains unreferenced contribution layer '%s'" % layer_key
			)
	return errors


func content_equals(other: VarkAnimatedLightmapBakeData) -> bool:
	if other == null:
		return false
	return (
		format_version == other.format_version
		and source_map_path == other.source_map_path
		and source_sha256 == other.source_sha256
		and layout_fingerprint == other.layout_fingerprint
		and geometry_fingerprint == other.geometry_fingerprint
		and light_bake_fingerprint == other.light_bake_fingerprint
		and storage_format == other.storage_format
		and page_size == other.page_size
		and supersample_grid == other.supersample_grid
		and light_descriptors == other.light_descriptors
		and tile_contributing_light_ids == other.tile_contributing_light_ids
		and layer_data_base64 == other.layer_data_base64
	)


func to_resource_text() -> String:
	var descriptor_lines := PackedStringArray()
	for light_id: String in _sorted_keys(light_descriptors):
		var descriptor: Dictionary = light_descriptors.get(light_id, {})
		var position: Vector3 = descriptor.get("position", Vector3.ZERO)
		var color: Color = descriptor.get("color", Color.WHITE)
		descriptor_lines.append(
			"\"%s\": {\"position\": Vector3(%.9f, %.9f, %.9f), \"color\": Color(%.9f, %.9f, %.9f, %.9f), \"energy\": %.9f, \"range\": %.9f}"
			% [
				light_id,
				position.x, position.y, position.z,
				color.r, color.g, color.b, color.a,
				float(descriptor.get("energy", 0.0)),
				float(descriptor.get("range", 0.0)),
			]
		)
	var tile_lines := PackedStringArray()
	for tile_id: String in _sorted_keys(tile_contributing_light_ids):
		var quoted := PackedStringArray()
		for light_id: String in get_tile_light_ids(tile_id):
			quoted.append("\"%s\"" % light_id)
		tile_lines.append(
			"\"%s\": [%s]" % [tile_id, ", ".join(quoted)]
		)
	var layer_lines := PackedStringArray()
	for layer_key: String in get_layer_keys():
		layer_lines.append(
			"\"%s\": \"%s\""
			% [layer_key, str(layer_data_base64[layer_key])]
		)
	return """[gd_resource type="Resource" script_class="VarkAnimatedLightmapBakeData" load_steps=2 format=3]

[ext_resource type="Script" path="res://gameplay/visibility/animated_lightmap_bake_data.gd" id="1_bake"]

[resource]
script = ExtResource("1_bake")
format_version = %d
source_map_path = "%s"
source_sha256 = "%s"
layout_fingerprint = "%s"
geometry_fingerprint = "%s"
light_bake_fingerprint = "%s"
storage_format = &"%s"
page_size = %d
supersample_grid = %d
light_descriptors = {
%s
}
tile_contributing_light_ids = {
%s
}
layer_data_base64 = {
%s
}
""" % [
		format_version,
		source_map_path,
		source_sha256,
		layout_fingerprint,
		geometry_fingerprint,
		light_bake_fingerprint,
		storage_format,
		page_size,
		supersample_grid,
		",\n".join(descriptor_lines),
		",\n".join(tile_lines),
		",\n".join(layer_lines),
	]


static func compute_file_sha256(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	while file.get_position() < file.get_length():
		var remaining: int = file.get_length() - file.get_position()
		context.update(file.get_buffer(mini(65536, remaining)))
	return context.finish().hex_encode()


static func compute_light_bake_fingerprint(descriptors: Dictionary) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	for light_id: String in _sorted_keys(descriptors):
		var descriptor: Dictionary = descriptors.get(light_id, {})
		var position: Vector3 = descriptor.get("position", Vector3.ZERO)
		var color: Color = descriptor.get("color", Color.WHITE)
		context.update(
			(
				"%s|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f\n"
				% [
					light_id,
					position.x, position.y, position.z,
					color.r, color.g, color.b, color.a,
					float(descriptor.get("energy", 0.0)),
					float(descriptor.get("range", 0.0)),
				]
			).to_utf8_buffer()
		)
	return context.finish().hex_encode()


static func _sorted_keys(dictionary: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in dictionary.keys():
		result.append(str(key))
	result.sort()
	return result
