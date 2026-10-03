class_name VarkAnimatedLightmapLayout
extends Resource

const CURRENT_FORMAT_VERSION: int = 2
const DEFAULT_TEXEL_SIZE_METERS: float = 0.0625
const DEFAULT_PAGE_SIZE: int = 256
const DEFAULT_GUARD_TEXELS: int = 2
const DEFAULT_MAX_LIGHT_SLOTS_PER_TILE: int = 8
const STORAGE_FORMAT: StringName = &"r16f_linear_irradiance"
const COMPOSITION_BACKEND: StringName = &"texture2darray_page_local_slots"
const HDR_IMAGE_FORMAT: Image.Format = Image.FORMAT_RH
const BYTES_PER_TEXEL: int = 2

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
@export var legacy_affinity_page_count: int = 0
@export var legacy_affinity_layer_count: int = 0


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


func ensure_local_slot_representation() -> void:
	if format_version != CURRENT_FORMAT_VERSION:
		return
	if composition_backend != COMPOSITION_BACKEND:
		return
	if _has_local_slot_pages():
		return
	if pages.size() > 0 and legacy_affinity_page_count <= 0:
		legacy_affinity_page_count = pages.size()
	if contribution_layer_count > 0 and legacy_affinity_layer_count <= 0:
		legacy_affinity_layer_count = contribution_layer_count

	var tile_index_by_id: Dictionary = {}
	var work: Array[Dictionary] = []
	for tile_index: int in tiles.size():
		var tile: Dictionary = tiles[tile_index]
		var tile_id: String = str(tile.get("tile_id", ""))
		tile_index_by_id[tile_id] = tile_index
		work.append({
			"tile_id": tile_id,
			"rect_size": tile.get("rect_size", Vector2i.ZERO),
			"candidate_count": (
				tile.get("candidate_light_ids", PackedStringArray()) as PackedStringArray
			).size(),
		})
	work.sort_custom(_sort_pack_records)

	var page_states: Array[Dictionary] = []
	for record: Dictionary in work:
		var tile_id: String = str(record.get("tile_id", ""))
		var rect_size: Vector2i = record.get("rect_size", Vector2i.ZERO)
		if rect_size.x <= 0 or rect_size.y <= 0:
			continue
		var page_index: int = -1
		var rect_position := Vector2i.ZERO
		for candidate_page: int in page_states.size():
			var placement: Dictionary = _try_place_in_page(
				page_states[candidate_page], rect_size
			)
			if not bool(placement.get("fits", false)):
				continue
			page_index = candidate_page
			rect_position = placement.get("position", Vector2i.ZERO)
			page_states[candidate_page] = placement.get("state", {})
			break
		if page_index < 0:
			page_index = page_states.size()
			page_states.append({
				"cursor_x": rect_size.x,
				"cursor_y": 0,
				"row_height": rect_size.y,
				"tile_ids": PackedStringArray(),
				"max_slot_count": 0,
			})
			rect_position = Vector2i.ZERO

		var state: Dictionary = page_states[page_index]
		var page_tile_ids: PackedStringArray = state.get(
			"tile_ids", PackedStringArray()
		)
		page_tile_ids.append(tile_id)
		state["tile_ids"] = page_tile_ids
		state["max_slot_count"] = maxi(
			int(state.get("max_slot_count", 0)),
			int(record.get("candidate_count", 0))
		)
		page_states[page_index] = state

		var target_index: int = int(tile_index_by_id.get(tile_id, -1))
		if target_index >= 0:
			var target: Dictionary = tiles[target_index]
			target["page_index"] = page_index
			target["rect_position"] = rect_position
			tiles[target_index] = target

	pages = []
	contribution_layer_count = 0
	for page_index: int in page_states.size():
		var state: Dictionary = page_states[page_index]
		var page_tile_ids: PackedStringArray = state.get(
			"tile_ids", PackedStringArray()
		)
		page_tile_ids.sort()
		var layer_count: int = mini(
			int(state.get("max_slot_count", 0)),
			max_light_slots_per_tile
		)
		pages.append({
			"page_index": page_index,
			"tile_ids": page_tile_ids,
			"layer_base": contribution_layer_count,
			"layer_count": layer_count,
			"local_slot_layout": true,
		})
		contribution_layer_count += layer_count

	var weight_index_by_light: Dictionary = {}
	for light_index: int in light_ids.size():
		weight_index_by_light[light_ids[light_index]] = light_index
	for tile_index: int in tiles.size():
		var tile: Dictionary = tiles[tile_index]
		var page_index: int = int(tile.get("page_index", -1))
		var page: Dictionary = (
			pages[page_index]
			if page_index >= 0 and page_index < pages.size()
			else {}
		)
		var layer_base: int = int(page.get("layer_base", -1))
		var candidates: PackedStringArray = tile.get(
			"candidate_light_ids", PackedStringArray()
		)
		var bindings: Array[Dictionary] = []
		for slot: int in candidates.size():
			var light_id: String = candidates[slot]
			bindings.append({
				"light_id": light_id,
				"slot": slot,
				"layer_index": layer_base + slot,
				"weight_index": int(weight_index_by_light.get(light_id, -1)),
			})
		tile["light_bindings"] = bindings
		tiles[tile_index] = tile


func get_gpu_contract() -> Dictionary:
	ensure_local_slot_representation()
	return {
		"backend": composition_backend,
		"storage_format": storage_format,
		"image_format": HDR_IMAGE_FORMAT,
		"page_size": page_size,
		"max_light_slots_per_tile": max_light_slots_per_tile,
		"contribution_layer_count": contribution_layer_count,
		"global_light_count": light_ids.size(),
		"binding_transport": &"vertex_custom0_custom1",
		"light_state_transport": &"rgba16f_1d_texture",
	}


func get_scale_report() -> Dictionary:
	ensure_local_slot_representation()
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
	var legacy_bytes: int = (
		legacy_affinity_layer_count * page_size * page_size * BYTES_PER_TEXEL
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
		"legacy_affinity_pages": legacy_affinity_page_count,
		"legacy_affinity_layers": legacy_affinity_layer_count,
		"legacy_affinity_runtime_vram_bytes": legacy_bytes,
		"page_reduction": legacy_affinity_page_count - pages.size(),
		"layer_reduction": legacy_affinity_layer_count - contribution_layer_count,
		"runtime_vram_savings_bytes": legacy_bytes - estimated_vram_bytes,
	}


func get_validation_errors(
	expected_geometry_fingerprint: String,
	expected_light_influence_fingerprint: String
) -> PackedStringArray:
	ensure_local_slot_representation()
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

	var expected_layer_count: int = 0
	for page: Dictionary in pages:
		if not bool(page.get("local_slot_layout", false)):
			errors.append("animated-lightmap page is not local-slot packed")
		var layer_count: int = int(page.get("layer_count", 0))
		if layer_count < 0 or layer_count > max_light_slots_per_tile:
			errors.append(
				"page %d has invalid local-slot layer count %d"
				% [int(page.get("page_index", -1)), layer_count]
			)
		if int(page.get("layer_base", -1)) != expected_layer_count:
			errors.append(
				"page %d has non-contiguous local-slot layer base"
				% int(page.get("page_index", -1))
			)
		expected_layer_count += layer_count
	if expected_layer_count != contribution_layer_count:
		errors.append(
			"animated-lightmap contribution layer count %d does not match local-slot pages %d"
			% [contribution_layer_count, expected_layer_count]
		)

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
		var page_index: int = int(tile.get("page_index", -1))
		if page_index < 0 or page_index >= pages.size():
			errors.append("tile '%s' has invalid page" % str(tile.get("tile_id", "")))
			continue
		var page: Dictionary = pages[page_index]
		var bindings: Array = tile.get("light_bindings", [])
		if bindings.size() != candidates.size():
			errors.append(
				"tile '%s' binding count does not match candidate-light count"
				% str(tile.get("tile_id", ""))
			)
		for slot: int in bindings.size():
			var binding: Dictionary = bindings[slot]
			if (
				int(binding.get("slot", -1)) != slot
				or str(binding.get("light_id", "")) != candidates[slot]
				or int(binding.get("layer_index", -1))
					!= int(page.get("layer_base", -1)) + slot
			):
				errors.append(
					"tile '%s' has invalid local-slot binding %d"
					% [str(tile.get("tile_id", "")), slot]
				)
	return errors


func to_canonical_text() -> String:
	ensure_local_slot_representation()
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
		var tile_ids: PackedStringArray = page.get(
			"tile_ids", PackedStringArray()
		)
		lines.append(
			"page|%d|local_slots=%d|layer_base=%d|tiles=%s"
			% [
				int(page.get("page_index", -1)),
				int(page.get("layer_count", 0)),
				int(page.get("layer_base", -1)),
				",".join(tile_ids),
			]
		)
	lines.append("layers=%d" % contribution_layer_count)
	return "\n".join(lines) + "\n"


static func encode_hdr_scalars(values: PackedFloat32Array) -> PackedByteArray:
	if values.is_empty():
		return PackedByteArray()
	var image := Image.create_empty(values.size(), 1, false, HDR_IMAGE_FORMAT)
	for index: int in values.size():
		image.set_pixel(index, 0, Color(values[index], 0.0, 0.0, 1.0))
	return image.get_data()


static func decode_hdr_scalars(
	data: PackedByteArray,
	count: int
) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	if count <= 0 or data.size() != count * BYTES_PER_TEXEL:
		return result
	var image := Image.create_from_data(
		count, 1, false, HDR_IMAGE_FORMAT, data
	)
	if image == null or image.is_empty():
		return result
	result.resize(count)
	for index: int in count:
		result[index] = image.get_pixel(index, 0).r
	return result


func _has_local_slot_pages() -> bool:
	if pages.is_empty():
		return tiles.is_empty()
	for page: Dictionary in pages:
		if not bool(page.get("local_slot_layout", false)):
			return false
	return true


func _try_place_in_page(state: Dictionary, rect_size: Vector2i) -> Dictionary:
	var cursor_x: int = int(state.get("cursor_x", 0))
	var cursor_y: int = int(state.get("cursor_y", 0))
	var row_height: int = int(state.get("row_height", 0))
	if cursor_x + rect_size.x <= page_size and cursor_y + rect_size.y <= page_size:
		var next_state: Dictionary = state.duplicate(true)
		next_state["cursor_x"] = cursor_x + rect_size.x
		next_state["row_height"] = maxi(row_height, rect_size.y)
		return {
			"fits": true,
			"position": Vector2i(cursor_x, cursor_y),
			"state": next_state,
		}
	var next_y: int = cursor_y + row_height
	if rect_size.x <= page_size and next_y + rect_size.y <= page_size:
		var next_state: Dictionary = state.duplicate(true)
		next_state["cursor_x"] = rect_size.x
		next_state["cursor_y"] = next_y
		next_state["row_height"] = rect_size.y
		return {
			"fits": true,
			"position": Vector2i(0, next_y),
			"state": next_state,
		}
	return {"fits": false}


static func _sort_pack_records(a: Dictionary, b: Dictionary) -> bool:
	var a_size: Vector2i = a.get("rect_size", Vector2i.ZERO)
	var b_size: Vector2i = b.get("rect_size", Vector2i.ZERO)
	if a_size.y != b_size.y:
		return a_size.y > b_size.y
	if a_size.x != b_size.x:
		return a_size.x > b_size.x
	return str(a.get("tile_id", "")) < str(b.get("tile_id", ""))


static func _vector3_text(value: Vector3) -> String:
	return "%.9f,%.9f,%.9f" % [value.x, value.y, value.z]


static func _vector2_text(value: Vector2) -> String:
	return "%.9f,%.9f" % [value.x, value.y]


static func _packed_vector2_text(values: PackedVector2Array) -> String:
	var parts := PackedStringArray()
	for value: Vector2 in values:
		parts.append(_vector2_text(value))
	return ";".join(parts)
