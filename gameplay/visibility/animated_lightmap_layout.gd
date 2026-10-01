class_name VarkAnimatedLightmapLayout
extends Resource

const CURRENT_FORMAT_VERSION: int = 1
const DEFAULT_TEXEL_SIZE_METERS: float = 0.0625
const DEFAULT_PAGE_SIZE: int = 1024
const DEFAULT_GUARD_TEXELS: int = 2
const DEFAULT_MAX_LIGHT_SLOTS_PER_TILE: int = 8
const STORAGE_FORMAT: StringName = &"rgba16f_linear"
const COMPOSITION_BACKEND: StringName = &"texture2darray_page_light_layers"
const HDR_IMAGE_FORMAT: Image.Format = Image.FORMAT_RGBAH
const BYTES_PER_TEXEL: int = 8

@export var format_version: int = CURRENT_FORMAT_VERSION
@export var texel_size_meters: float = DEFAULT_TEXEL_SIZE_METERS
@export var page_size: int = DEFAULT_PAGE_SIZE
@export var guard_texels: int = DEFAULT_GUARD_TEXELS
@export var max_light_slots_per_tile: int = DEFAULT_MAX_LIGHT_SLOTS_PER_TILE
@export var storage_format: StringName = STORAGE_FORMAT
@export var composition_backend: StringName = COMPOSITION_BACKEND
@export var geometry_fingerprint: String = ""
@export var light_influence_fingerprint: String = ""
@export var representation_fingerprint: String = ""
@export var light_ids: PackedStringArray = PackedStringArray()
@export var faces: Array[Dictionary] = []
@export var tiles: Array[Dictionary] = []
@export var pages: Array[Dictionary] = []
@export var contribution_layer_count: int = 0


func get_face(face_id: String) -> Dictionary:
	for face: Dictionary in faces:
		if str(face.get("face_id", "")) == face_id:
			return face
	return {}


func get_tile(tile_id: String) -> Dictionary:
	for tile: Dictionary in tiles:
		if str(tile.get("tile_id", "")) == tile_id:
			return tile
	return {}


func get_gpu_contract() -> Dictionary:
	return {
		"backend": composition_backend,
		"storage_format": storage_format,
		"image_format": HDR_IMAGE_FORMAT,
		"page_size": page_size,
		"max_light_slots_per_tile": max_light_slots_per_tile,
		"contribution_layer_count": contribution_layer_count,
		"global_light_count": light_ids.size(),
	}


func get_scale_report() -> Dictionary:
	var useful_texels: int = 0
	var guarded_texels: int = 0
	var candidate_relationships: int = 0
	var max_candidate_lights: int = 0
	for tile: Dictionary in tiles:
		var useful: Vector2i = tile.get("useful_size", Vector2i.ZERO)
		var rect: Vector2i = tile.get("rect_size", Vector2i.ZERO)
		useful_texels += useful.x * useful.y
		guarded_texels += rect.x * rect.y
		var candidates: PackedStringArray = tile.get(
			"candidate_light_ids", PackedStringArray()
		)
		candidate_relationships += candidates.size()
		max_candidate_lights = maxi(max_candidate_lights, candidates.size())
	var average_candidates: float = (
		float(candidate_relationships) / float(tiles.size())
		if not tiles.is_empty()
		else 0.0
	)
	var estimated_vram_bytes: int = (
		contribution_layer_count * page_size * page_size * BYTES_PER_TEXEL
	)
	return {
		"format_version": format_version,
		"texel_size_meters": texel_size_meters,
		"page_size": page_size,
		"guard_texels": guard_texels,
		"max_light_slots_per_tile": max_light_slots_per_tile,
		"logical_faces": faces.size(),
		"face_tiles": tiles.size(),
		"useful_texels": useful_texels,
		"guarded_texels": guarded_texels,
		"atlas_pages": pages.size(),
		"global_animated_lights": light_ids.size(),
		"candidate_relationships": candidate_relationships,
		"average_candidate_lights_per_tile": average_candidates,
		"max_candidate_lights_per_tile": max_candidate_lights,
		"contribution_layers": contribution_layer_count,
		"estimated_contribution_bytes": estimated_vram_bytes,
		"estimated_runtime_vram_bytes": estimated_vram_bytes,
		"estimated_draw_calls": pages.size(),
	}


func get_validation_errors(
	expected_geometry_fingerprint: String,
	expected_light_influence_fingerprint: String
) -> PackedStringArray:
	var errors := PackedStringArray()
	if format_version != CURRENT_FORMAT_VERSION:
		errors.append(
			"animated-lightmap layout format %d is unsupported; expected %d"
			% [format_version, CURRENT_FORMAT_VERSION]
		)
	if storage_format != STORAGE_FORMAT:
		errors.append(
			"animated-lightmap layout storage '%s' is unsupported; expected '%s'"
			% [storage_format, STORAGE_FORMAT]
		)
	if composition_backend != COMPOSITION_BACKEND:
		errors.append(
			"animated-lightmap composition backend '%s' is unsupported; expected '%s'"
			% [composition_backend, COMPOSITION_BACKEND]
		)
	if geometry_fingerprint != expected_geometry_fingerprint:
		errors.append(
			"surface geometry fingerprint mismatch: layout=%s runtime=%s"
			% [geometry_fingerprint, expected_geometry_fingerprint]
		)
	if light_influence_fingerprint != expected_light_influence_fingerprint:
		errors.append(
			"light influence fingerprint mismatch: layout=%s runtime=%s"
			% [light_influence_fingerprint, expected_light_influence_fingerprint]
		)
	if texel_size_meters <= 0.0:
		errors.append("animated-lightmap texel size must be positive")
	if page_size <= guard_texels * 2:
		errors.append("animated-lightmap page has no useful area after guards")
	if max_light_slots_per_tile <= 0:
		errors.append("animated-lightmap tile slot limit must be positive")
	for tile: Dictionary in tiles:
		var candidates: PackedStringArray = tile.get(
			"candidate_light_ids", PackedStringArray()
		)
		if candidates.size() > max_light_slots_per_tile:
			errors.append(
				"tile '%s' needs %d animated lights but layout supports %d"
				% [
					str(tile.get("tile_id", "")),
					candidates.size(),
					max_light_slots_per_tile,
				]
			)
	return errors


func to_canonical_text() -> String:
	var lines := PackedStringArray()
	lines.append("format=%d" % format_version)
	lines.append("texel=%.9f" % texel_size_meters)
	lines.append("page=%d" % page_size)
	lines.append("guard=%d" % guard_texels)
	lines.append("slots=%d" % max_light_slots_per_tile)
	lines.append("storage=%s" % storage_format)
	lines.append("backend=%s" % composition_backend)
	lines.append("geometry=%s" % geometry_fingerprint)
	lines.append("influence=%s" % light_influence_fingerprint)
	lines.append("lights=%s" % ",".join(light_ids))
	for face: Dictionary in faces:
		var normal: Vector3 = face.get("normal", Vector3.ZERO)
		var origin: Vector3 = face.get("origin", Vector3.ZERO)
		var basis_u: Vector3 = face.get("basis_u", Vector3.ZERO)
		var basis_v: Vector3 = face.get("basis_v", Vector3.ZERO)
		var projection_min: Vector2 = face.get("projection_min", Vector2.ZERO)
		var extent: Vector2 = face.get("extent", Vector2.ZERO)
		var useful_size: Vector2i = face.get("useful_size", Vector2i.ZERO)
		lines.append(
			"face|%s|%s|n=%s|o=%s|u=%s|v=%s|min=%s|extent=%s|texels=%dx%d|triangles=%s"
			% [
				str(face.get("face_id", "")),
				str(face.get("material_id", "")),
				_vector3_text(normal),
				_vector3_text(origin),
				_vector3_text(basis_u),
				_vector3_text(basis_v),
				_vector2_text(projection_min),
				_vector2_text(extent),
				useful_size.x,
				useful_size.y,
				_packed_vector2_text(
					face.get("triangles_uv", PackedVector2Array())
				),
			]
		)
	for tile: Dictionary in tiles:
		var offset: Vector2i = tile.get("texel_offset", Vector2i.ZERO)
		var useful: Vector2i = tile.get("useful_size", Vector2i.ZERO)
		var rect_pos: Vector2i = tile.get("rect_position", Vector2i.ZERO)
		var rect_size: Vector2i = tile.get("rect_size", Vector2i.ZERO)
		var candidates: PackedStringArray = tile.get(
			"candidate_light_ids", PackedStringArray()
		)
		var binding_parts := PackedStringArray()
		for binding: Dictionary in tile.get("light_bindings", []):
			binding_parts.append(
				"%s:%d:%d:%d"
				% [
					str(binding.get("light_id", "")),
					int(binding.get("slot", -1)),
					int(binding.get("layer_index", -1)),
					int(binding.get("weight_index", -1)),
				]
			)
		lines.append(
			"tile|%s|face=%s|offset=%d,%d|size=%d,%d|page=%d|rect=%d,%d,%d,%d|candidates=%s|bindings=%s"
			% [
				str(tile.get("tile_id", "")),
				str(tile.get("face_id", "")),
				offset.x,
				offset.y,
				useful.x,
				useful.y,
				int(tile.get("page_index", -1)),
				rect_pos.x,
				rect_pos.y,
				rect_size.x,
				rect_size.y,
				",".join(candidates),
				",".join(binding_parts),
			]
		)
	for page: Dictionary in pages:
		var page_lights: PackedStringArray = page.get(
			"light_ids", PackedStringArray()
		)
		var tile_ids: PackedStringArray = page.get(
			"tile_ids", PackedStringArray()
		)
		lines.append(
			"page|%d|lights=%s|layer_base=%d|layer_count=%d|tiles=%s"
			% [
				int(page.get("page_index", -1)),
				",".join(page_lights),
				int(page.get("layer_base", -1)),
				int(page.get("layer_count", 0)),
				",".join(tile_ids),
			]
		)
	lines.append("layers=%d" % contribution_layer_count)
	return "
".join(lines) + "
"


static func encode_hdr_colors(colors: Array[Color]) -> PackedByteArray:
	if colors.is_empty():
		return PackedByteArray()
	var image := Image.create_empty(colors.size(), 1, false, HDR_IMAGE_FORMAT)
	for index: int in colors.size():
		image.set_pixel(index, 0, colors[index])
	return image.get_data()


static func decode_hdr_colors(data: PackedByteArray, count: int) -> Array[Color]:
	var result: Array[Color] = []
	if count <= 0 or data.size() != count * BYTES_PER_TEXEL:
		return result
	var image := Image.create_from_data(
		count, 1, false, HDR_IMAGE_FORMAT, data
	)
	if image == null or image.is_empty():
		return result
	for index: int in count:
		result.append(image.get_pixel(index, 0))
	return result


static func _vector3_text(value: Vector3) -> String:
	return "%.9f,%.9f,%.9f" % [value.x, value.y, value.z]


static func _vector2_text(value: Vector2) -> String:
	return "%.9f,%.9f" % [value.x, value.y]


static func _packed_vector2_text(values: PackedVector2Array) -> String:
	var parts := PackedStringArray()
	for value: Vector2 in values:
		parts.append(_vector2_text(value))
	return ";".join(parts)
