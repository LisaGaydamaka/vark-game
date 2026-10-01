class_name VarkAnimatedLightmapSurfaceBaker
extends RefCounted

const DEFAULT_SUPERSAMPLE_GRID: int = 4
const CONTRIBUTION_EPSILON: float = 0.00001
const PHYSICS_CROSSCHECK_STRIDE: int = 31
const WORLD_COLLISION_MASK: int = 1

var _diagnostics: Dictionary = {}


func get_diagnostics() -> Dictionary:
	return _diagnostics.duplicate(true)


func bake(
	source_map_path: String,
	layout: VarkAnimatedLightmapLayout,
	light_descriptors: Dictionary,
	supersample_grid: int = DEFAULT_SUPERSAMPLE_GRID,
	physics_space_state: PhysicsDirectSpaceState3D = null
) -> VarkAnimatedLightmapBakeData:
	_diagnostics = {
		"bvh_triangles": 0,
		"bvh_nodes": 0,
		"resolved_texels": 0,
		"supersamples": 0,
		"physics_checks": 0,
		"physics_visibility_mismatches": 0,
		"contributing_tile_light_pairs": 0,
		"resident_page_light_layers": 0,
		"elapsed_usec": 0,
	}
	if (
		layout == null
		or supersample_grid <= 0
		or source_map_path.strip_edges().is_empty()
	):
		return null
	var started_usec: int = Time.get_ticks_usec()
	var bake_scene := VarkAnimatedLightmapBakeScene.new()
	if not bake_scene.configure(layout):
		_diagnostics["errors"] = bake_scene.get_errors()
		return null
	_diagnostics["bvh_triangles"] = bake_scene.get_triangle_count()
	_diagnostics["bvh_nodes"] = bake_scene.get_node_count()
	_diagnostics["bvh_fingerprint"] = bake_scene.get_fingerprint()

	var result := VarkAnimatedLightmapBakeData.new()
	result.source_map_path = source_map_path
	result.source_sha256 = VarkAnimatedLightmapBakeData.compute_file_sha256(
		source_map_path
	)
	result.layout_fingerprint = layout.representation_fingerprint
	result.geometry_fingerprint = layout.geometry_fingerprint
	result.light_bake_fingerprint = (
		VarkAnimatedLightmapBakeData.compute_light_bake_fingerprint(
			light_descriptors
		)
	)
	result.storage_format = VarkAnimatedLightmapLayout.STORAGE_FORMAT
	result.page_size = layout.page_size
	result.supersample_grid = supersample_grid
	result.light_descriptors = light_descriptors.duplicate(true)

	var page_layers: Dictionary = {}
	var crosscheck_counter: int = 0
	for tile: Dictionary in layout.tiles:
		var tile_id: String = str(tile.get("tile_id", ""))
		var face: Dictionary = layout.get_face(str(tile.get("face_id", "")))
		if face.is_empty():
			return null
		var contributing: Array[String] = []
		var candidates: PackedStringArray = tile.get(
			"candidate_light_ids", PackedStringArray()
		)
		for light_id: String in candidates:
			var descriptor_variant: Variant = light_descriptors.get(light_id, {})
			if not (descriptor_variant is Dictionary):
				return null
			var descriptor: Dictionary = descriptor_variant as Dictionary
			var baked_tile: Dictionary = _bake_tile_light(
				layout,
				face,
				tile,
				descriptor,
				light_id,
				bake_scene,
				supersample_grid,
				physics_space_state,
				crosscheck_counter
			)
			crosscheck_counter = int(
				baked_tile.get("crosscheck_counter", crosscheck_counter)
			)
			if not bool(baked_tile.get("has_contribution", false)):
				continue
			var rect_values: PackedFloat32Array = baked_tile.get(
				"rect_values", PackedFloat32Array()
			)
			if rect_values.is_empty():
				return null
			var page_index: int = int(tile.get("page_index", -1))
			var layer_key: String = result.get_layer_key(page_index, light_id)
			var page_values: PackedFloat32Array = page_layers.get(
				layer_key, PackedFloat32Array()
			)
			if page_values.is_empty():
				page_values.resize(layout.page_size * layout.page_size)
				page_values.fill(0.0)
			_write_tile_rect_to_page(
				page_values,
				layout.page_size,
				tile.get("rect_position", Vector2i.ZERO),
				tile.get("rect_size", Vector2i.ZERO),
				rect_values
			)
			page_layers[layer_key] = page_values
			contributing.append(light_id)
			_diagnostics["contributing_tile_light_pairs"] = (
				int(_diagnostics["contributing_tile_light_pairs"]) + 1
			)
		if not contributing.is_empty():
			contributing.sort()
			result.tile_contributing_light_ids[tile_id] = contributing

	var layer_keys: Array[String] = []
	for key: Variant in page_layers.keys():
		layer_keys.append(str(key))
	layer_keys.sort()
	for layer_key: String in layer_keys:
		var separator: int = layer_key.find("|")
		if separator <= 0:
			return null
		var page_index: int = int(layer_key.substr(0, separator))
		var light_id: String = layer_key.substr(separator + 1)
		var page_values: PackedFloat32Array = page_layers[layer_key]
		var bytes: PackedByteArray = _encode_page(
			page_values, layout.page_size
		)
		if not result.set_layer_bytes(page_index, light_id, bytes):
			return null
	_diagnostics["resident_page_light_layers"] = layer_keys.size()
	_diagnostics["elapsed_usec"] = Time.get_ticks_usec() - started_usec

	var errors: PackedStringArray = result.get_validation_errors(
		source_map_path, layout, light_descriptors
	)
	if not errors.is_empty():
		_diagnostics["errors"] = errors
		return null
	return result


func _bake_tile_light(
	layout: VarkAnimatedLightmapLayout,
	face: Dictionary,
	tile: Dictionary,
	descriptor: Dictionary,
	light_id: String,
	bake_scene: VarkAnimatedLightmapBakeScene,
	supersample_grid: int,
	physics_space_state: PhysicsDirectSpaceState3D,
	crosscheck_counter: int
) -> Dictionary:
	var useful_size: Vector2i = tile.get("useful_size", Vector2i.ZERO)
	var texel_offset: Vector2i = tile.get("texel_offset", Vector2i.ZERO)
	var useful_values := PackedFloat32Array()
	useful_values.resize(useful_size.x * useful_size.y)
	useful_values.fill(0.0)
	var useful_mask := PackedByteArray()
	useful_mask.resize(useful_size.x * useful_size.y)
	var normal: Vector3 = face.get(
		"lighting_normal", face.get("normal", Vector3.ZERO)
	).normalized()
	var face_id: String = str(face.get("face_id", ""))
	var any_nonzero: bool = false
	var sub_count: int = supersample_grid * supersample_grid
	for y: int in useful_size.y:
		for x: int in useful_size.x:
			var accumulated: float = 0.0
			var coverage_count: int = 0
			for sub_y: int in supersample_grid:
				for sub_x: int in supersample_grid:
					var local_point := Vector2(
						(
							float(texel_offset.x + x)
							+ (float(sub_x) + 0.5) / float(supersample_grid)
						) * layout.texel_size_meters,
						(
							float(texel_offset.y + y)
							+ (float(sub_y) + 0.5) / float(supersample_grid)
						) * layout.texel_size_meters
					)
					if not VarkAnimatedLightmapLayoutBuilder.is_face_local_point_valid(
						face, local_point
					):
						continue
					coverage_count += 1
					var world_point: Vector3 = (
						VarkAnimatedLightmapLayoutBuilder.face_local_point_world(
							face, local_point
						)
					)
					accumulated += bake_scene.sample_direct_irradiance(
						world_point, normal, descriptor, face_id
					)
					_diagnostics["supersamples"] = (
						int(_diagnostics["supersamples"]) + 1
					)
			var index: int = y * useful_size.x + x
			if coverage_count <= 0:
				continue
			useful_mask[index] = 1
			var resolved: float = accumulated / float(coverage_count)
			useful_values[index] = resolved
			_diagnostics["resolved_texels"] = (
				int(_diagnostics["resolved_texels"]) + 1
			)
			if resolved > CONTRIBUTION_EPSILON:
				any_nonzero = true

			if (
				physics_space_state != null
				and crosscheck_counter % PHYSICS_CROSSCHECK_STRIDE == 0
			):
				var center_local := Vector2(
					(float(texel_offset.x + x) + 0.5)
						* layout.texel_size_meters,
					(float(texel_offset.y + y) + 0.5)
						* layout.texel_size_meters
				)
				if VarkAnimatedLightmapLayoutBuilder.is_face_local_point_valid(
					face, center_local
				):
					var center_world: Vector3 = (
						VarkAnimatedLightmapLayoutBuilder.face_local_point_world(
							face, center_local
						)
					)
					var bvh_value: float = bake_scene.sample_direct_irradiance(
						center_world, normal, descriptor, face_id
					)
					var physics_value: float = _sample_physics_direct_irradiance(
						center_world,
						normal,
						descriptor,
						physics_space_state
					)
					_diagnostics["physics_checks"] = (
						int(_diagnostics["physics_checks"]) + 1
					)
					if (
						(bvh_value > CONTRIBUTION_EPSILON)
						!= (physics_value > CONTRIBUTION_EPSILON)
					):
						_diagnostics["physics_visibility_mismatches"] = (
							int(_diagnostics["physics_visibility_mismatches"]) + 1
						)
			crosscheck_counter += 1

	if not any_nonzero:
		return {
			"has_contribution": false,
			"crosscheck_counter": crosscheck_counter,
		}
	var rect_values: PackedFloat32Array = _dilate_tile_values(
		useful_values,
		useful_mask,
		useful_size,
		layout.guard_texels
	)
	return {
		"has_contribution": true,
		"rect_values": rect_values,
		"light_id": light_id,
		"crosscheck_counter": crosscheck_counter,
		"subsamples_per_texel": sub_count,
	}


func _dilate_tile_values(
	useful_values: PackedFloat32Array,
	useful_mask: PackedByteArray,
	useful_size: Vector2i,
	guard_texels: int
) -> PackedFloat32Array:
	var rect_size: Vector2i = (
		useful_size + Vector2i.ONE * guard_texels * 2
	)
	var rect_values := PackedFloat32Array()
	rect_values.resize(rect_size.x * rect_size.y)
	rect_values.fill(0.0)
	var assigned := PackedByteArray()
	assigned.resize(rect_values.size())
	var queue: Array[int] = []
	for y: int in useful_size.y:
		for x: int in useful_size.x:
			var source_index: int = y * useful_size.x + x
			if useful_mask[source_index] == 0:
				continue
			var rx: int = x + guard_texels
			var ry: int = y + guard_texels
			var rect_index: int = ry * rect_size.x + rx
			rect_values[rect_index] = useful_values[source_index]
			assigned[rect_index] = 1
			queue.append(rect_index)
	if queue.is_empty():
		return PackedFloat32Array()

	var cursor: int = 0
	var neighbor_offsets := [
		Vector2i(0, -1),
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
	]
	while cursor < queue.size():
		var current: int = queue[cursor]
		cursor += 1
		var cx: int = current % rect_size.x
		var cy: int = current / rect_size.x
		for offset: Vector2i in neighbor_offsets:
			var nx: int = cx + offset.x
			var ny: int = cy + offset.y
			if nx < 0 or ny < 0 or nx >= rect_size.x or ny >= rect_size.y:
				continue
			var neighbor: int = ny * rect_size.x + nx
			if assigned[neighbor] != 0:
				continue
			assigned[neighbor] = 1
			rect_values[neighbor] = rect_values[current]
			queue.append(neighbor)
	return rect_values


func _write_tile_rect_to_page(
	page_values: PackedFloat32Array,
	page_size: int,
	rect_position: Vector2i,
	rect_size: Vector2i,
	rect_values: PackedFloat32Array
) -> void:
	if rect_values.size() != rect_size.x * rect_size.y:
		return
	for y: int in rect_size.y:
		var target_start: int = (
			(rect_position.y + y) * page_size + rect_position.x
		)
		var source_start: int = y * rect_size.x
		for x: int in rect_size.x:
			page_values[target_start + x] = rect_values[source_start + x]


func _encode_page(
	values: PackedFloat32Array,
	page_size: int
) -> PackedByteArray:
	if values.size() != page_size * page_size:
		return PackedByteArray()
	var image := Image.create_empty(
		page_size,
		page_size,
		false,
		VarkAnimatedLightmapLayout.HDR_IMAGE_FORMAT
	)
	for y: int in page_size:
		for x: int in page_size:
			image.set_pixel(
				x,
				y,
				Color(values[y * page_size + x], 0.0, 0.0, 1.0)
			)
	return image.get_data()


func _sample_physics_direct_irradiance(
	point: Vector3,
	normal: Vector3,
	descriptor: Dictionary,
	space_state: PhysicsDirectSpaceState3D
) -> float:
	if space_state == null:
		return 0.0
	var light_position: Vector3 = descriptor.get("position", Vector3.ZERO)
	var to_light: Vector3 = light_position - point
	var distance: float = to_light.length()
	var light_range: float = maxf(float(descriptor.get("range", 0.0)), 0.0)
	if (
		distance <= VarkAnimatedLightmapBakeScene.SURFACE_EPSILON
		or light_range <= 0.0
		or distance >= light_range
	):
		return 0.0
	var direction: Vector3 = to_light / distance
	var ndotl: float = normal.normalized().dot(direction)
	if ndotl <= 0.0:
		return 0.0
	var from: Vector3 = (
		point
		+ normal.normalized() * VarkAnimatedLightmapBakeScene.SURFACE_EPSILON
	)
	var to: Vector3 = (
		light_position
		- direction * VarkAnimatedLightmapBakeScene.SURFACE_EPSILON
	)
	var query := PhysicsRayQueryParameters3D.create(
		from, to, WORLD_COLLISION_MASK
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if not space_state.intersect_ray(query).is_empty():
		return 0.0
	var attenuation: float = 1.0 - distance / light_range
	attenuation *= attenuation
	return (
		maxf(float(descriptor.get("energy", 0.0)), 0.0)
		* attenuation
		* ndotl
	)
