class_name VarkAnimatedLightmapData
extends Resource

const CURRENT_FORMAT_VERSION: int = 1
const COMPRESSION_MODE: int = FileAccess.COMPRESSION_DEFLATE

@export var format_version: int = CURRENT_FORMAT_VERSION
@export_file("*.map") var source_map_path: String = ""
@export var source_sha256: String = ""
@export var geometry_fingerprint: String = ""
@export var texture_size: Vector2i = Vector2i.ZERO
@export var light_descriptors: Dictionary = {}
@export var light_fingerprint: String = ""
@export var light_layers_base64: Dictionary = {}

func get_light_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for key: Variant in light_layers_base64.keys():
		ids.append(str(key))
	ids.sort()
	return ids

func get_light_layer_bytes(light_id: String) -> PackedByteArray:
	var encoded: String = str(light_layers_base64.get(light_id, ""))
	if encoded.is_empty() or texture_size.x <= 0 or texture_size.y <= 0:
		return PackedByteArray()
	var compressed: PackedByteArray = Marshalls.base64_to_raw(encoded)
	if compressed.is_empty():
		return PackedByteArray()
	return compressed.decompress(
		texture_size.x * texture_size.y * 4,
		COMPRESSION_MODE
	)

func set_light_layer_bytes(light_id: String, bytes: PackedByteArray) -> bool:
	if (
		light_id.strip_edges().is_empty()
		or texture_size.x <= 0
		or texture_size.y <= 0
		or bytes.size() != texture_size.x * texture_size.y * 4
	):
		return false
	light_layers_base64[light_id] = Marshalls.raw_to_base64(
		bytes.compress(COMPRESSION_MODE)
	)
	return true

func get_validation_errors(
	expected_source_map_path: String,
	expected_geometry_fingerprint: String,
	expected_light_descriptors: Dictionary
) -> PackedStringArray:
	var errors := PackedStringArray()
	if format_version != CURRENT_FORMAT_VERSION:
		errors.append(
			"animated-lightmap format %d is unsupported; expected %d"
			% [format_version, CURRENT_FORMAT_VERSION]
		)
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
	if geometry_fingerprint != expected_geometry_fingerprint:
		errors.append(
			"UV2/geometry fingerprint mismatch: bake=%s runtime=%s"
			% [geometry_fingerprint, expected_geometry_fingerprint]
		)
	var expected_fingerprint: String = compute_light_fingerprint(
		expected_light_descriptors
	)
	if light_fingerprint != expected_fingerprint:
		errors.append(
			"light identity/configuration fingerprint mismatch: bake=%s runtime=%s"
			% [light_fingerprint, expected_fingerprint]
		)
	if texture_size.x <= 0 or texture_size.y <= 0:
		errors.append("animated-lightmap texture size must be positive")
	for light_id: String in _sorted_keys(expected_light_descriptors):
		if not light_layers_base64.has(light_id):
			errors.append("missing baked contribution for light '%s'" % light_id)
			continue
		var bytes: PackedByteArray = get_light_layer_bytes(light_id)
		if bytes.size() != texture_size.x * texture_size.y * 4:
			errors.append(
				"baked contribution '%s' has %d bytes; expected %d"
				% [
					light_id,
					bytes.size(),
					texture_size.x * texture_size.y * 4,
				]
			)
	for baked_id: String in get_light_ids():
		if not expected_light_descriptors.has(baked_id):
			errors.append("bake contains unknown light '%s'" % baked_id)
	return errors

func content_equals(other: VarkAnimatedLightmapData) -> bool:
	if other == null:
		return false
	return (
		format_version == other.format_version
		and source_map_path == other.source_map_path
		and source_sha256 == other.source_sha256
		and geometry_fingerprint == other.geometry_fingerprint
		and texture_size == other.texture_size
		and light_fingerprint == other.light_fingerprint
		and light_descriptors == other.light_descriptors
		and light_layers_base64 == other.light_layers_base64
	)

func to_resource_text() -> String:
	var descriptor_lines: PackedStringArray = []
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
	var layer_lines: PackedStringArray = []
	for light_id: String in get_light_ids():
		layer_lines.append(
			"\"%s\": \"%s\""
			% [light_id, str(light_layers_base64[light_id])]
		)
	return """[gd_resource type="Resource" script_class="VarkAnimatedLightmapData" load_steps=2 format=3]

[ext_resource type="Script" path="res://gameplay/visibility/animated_lightmap_data.gd" id="1_data"]

[resource]
script = ExtResource("1_data")
format_version = %d
source_map_path = "%s"
source_sha256 = "%s"
geometry_fingerprint = "%s"
texture_size = Vector2i(%d, %d)
light_descriptors = {
%s
}
light_fingerprint = "%s"
light_layers_base64 = {
%s
}
""" % [
		format_version, source_map_path, source_sha256, geometry_fingerprint,
		texture_size.x, texture_size.y, ",\n".join(descriptor_lines),
		light_fingerprint, ",\n".join(layer_lines),
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

static func compute_light_fingerprint(descriptors: Dictionary) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	for light_id: String in _sorted_keys(descriptors):
		var descriptor: Dictionary = descriptors.get(light_id, {})
		var position: Vector3 = descriptor.get("position", Vector3.ZERO)
		var color: Color = descriptor.get("color", Color.WHITE)
		var line: String = (
			"%s|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f\n"
			% [
				light_id,
				position.x, position.y, position.z,
				color.r, color.g, color.b, color.a,
				float(descriptor.get("energy", 0.0)),
				float(descriptor.get("range", 0.0)),
			]
		)
		context.update(line.to_utf8_buffer())
	return context.finish().hex_encode()

static func _sorted_keys(dictionary: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in dictionary.keys():
		result.append(str(key))
	result.sort()
	return result
