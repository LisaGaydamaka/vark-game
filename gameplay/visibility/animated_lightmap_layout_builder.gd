class_name VarkAnimatedLightmapLayoutBuilder
extends RefCounted

const PLANE_EPSILON: float = 0.0001
const ID_QUANTUM: float = 0.00001
const MAX_PAGE_SIZE: int = 16384

var _errors := PackedStringArray()


func get_errors() -> PackedStringArray:
	return _errors.duplicate()


func build_from_root(
	root: Node,
	light_descriptors: Dictionary,
	options: Dictionary = {}
) -> VarkAnimatedLightmapLayout:
	var meshes: Array[MeshInstance3D] = []
	if root != null:
		for candidate: Node in root.find_children(
			"*", "MeshInstance3D", true, false
		):
			var mesh_instance := candidate as MeshInstance3D
			if mesh_instance == null or mesh_instance.mesh == null:
				continue
			var owner: Node = mesh_instance.get_parent()
			if owner != null and owner.has_meta("func_godot_mesh_data"):
				meshes.append(mesh_instance)
	return build_from_mesh_instances(meshes, light_descriptors, options)


func build_from_mesh_instances(
	mesh_instances: Array[MeshInstance3D],
	light_descriptors: Dictionary,
	options: Dictionary = {}
) -> VarkAnimatedLightmapLayout:
	_errors = PackedStringArray()
	var texel_size: float = float(options.get(
		"texel_size_meters",
		VarkAnimatedLightmapLayout.DEFAULT_TEXEL_SIZE_METERS
	))
	var page_size: int = int(options.get(
		"page_size",
		VarkAnimatedLightmapLayout.DEFAULT_PAGE_SIZE
	))
	var guard_texels: int = int(options.get(
		"guard_texels",
		VarkAnimatedLightmapLayout.DEFAULT_GUARD_TEXELS
	))
	var max_light_slots: int = int(options.get(
		"max_light_slots",
		VarkAnimatedLightmapLayout.DEFAULT_MAX_LIGHT_SLOTS_PER_TILE
	))
	if texel_size <= 0.0:
		_errors.append("animated-lightmap texel size must be positive")
	if page_size <= 0 or page_size > MAX_PAGE_SIZE:
		_errors.append(
			"animated-lightmap page size %d is outside 1..%d"
			% [page_size, MAX_PAGE_SIZE]
		)
	if guard_texels < 1:
		_errors.append("animated-lightmap linear filtering requires at least one guard texel")
	if page_size <= guard_texels * 2:
		_errors.append("animated-lightmap page has no useful area after guards")
	if max_light_slots <= 0:
		_errors.append("animated-lightmap tile slot limit must be positive")
	if mesh_instances.is_empty():
		_errors.append("animated-lightmap layout requires generated static mesh instances")
	var light_ids: PackedStringArray = _validate_light_descriptors(
		light_descriptors
	)
	if not _errors.is_empty():
		return null

	var faces: Array[Dictionary] = []
	var coincident_keys: Dictionary = {}
	for mesh_instance: MeshInstance3D in mesh_instances:
		var extracted: Array[Dictionary] = _extract_mesh_faces(mesh_instance)
		for face: Dictionary in extracted:
			var coincident_key: String = str(face.get("coincident_key", ""))
			if coincident_keys.has(coincident_key):
				_errors.append(
					"duplicate/coincident rendered face '%s' conflicts with '%s'"
					% [
						str(face.get("face_id", "")),
						str(coincident_keys[coincident_key]),
					]
				)
			else:
				coincident_keys[coincident_key] = face.get("face_id", "")
			faces.append(face)
	if faces.is_empty() and _errors.is_empty():
		_errors.append("animated-lightmap layout found no rendered FuncGodot faces")
	if not _errors.is_empty():
		return null
	faces.sort_custom(_sort_face_records)

	var max_useful_axis: int = page_size - guard_texels * 2
	var tiles: Array[Dictionary] = []
	for face: Dictionary in faces:
		var extent: Vector2 = face.get("extent", Vector2.ZERO)
		var useful_size := Vector2i(
			maxi(1, ceili(extent.x / texel_size)),
			maxi(1, ceili(extent.y / texel_size))
		)
		face["useful_size"] = useful_size
		var tile_count_x: int = ceili(
			float(useful_size.x) / float(max_useful_axis)
		)
		var tile_count_y: int = ceili(
			float(useful_size.y) / float(max_useful_axis)
		)
		for tile_y: int in tile_count_y:
			for tile_x: int in tile_count_x:
				var offset := Vector2i(
					tile_x * max_useful_axis,
					tile_y * max_useful_axis
				)
				var remaining := useful_size - offset
				var tile_useful := Vector2i(
					mini(max_useful_axis, remaining.x),
					mini(max_useful_axis, remaining.y)
				)
				if tile_useful.x <= 0 or tile_useful.y <= 0:
					_errors.append(
						"face '%s' produced an invalid tile at %s"
						% [str(face.get("face_id", "")), str(offset)]
					)
					continue
				var tile_id: String = "%s/%03d_%03d" % [
					str(face.get("face_id", "")), tile_y, tile_x
				]
				var candidates: PackedStringArray = _candidate_lights_for_tile(
					face,
					offset,
					tile_useful,
					texel_size,
					light_descriptors,
					light_ids
				)
				if candidates.size() > max_light_slots:
					_errors.append(
						"tile '%s' needs %d animated lights but slot limit is %d: %s"
						% [
							tile_id,
							candidates.size(),
							max_light_slots,
							",".join(candidates),
						]
					)
				tiles.append({
					"tile_id": tile_id,
					"face_id": face.get("face_id", ""),
					"texel_offset": offset,
					"useful_size": tile_useful,
					"rect_size": tile_useful + Vector2i.ONE * guard_texels * 2,
					"rect_position": Vector2i.ZERO,
					"page_index": -1,
					"candidate_light_ids": candidates,
					"light_bindings": [],
				})
	if not _errors.is_empty():
		return null
	tiles.sort_custom(_sort_tile_records)

	var pages: Array[Dictionary] = _pack_tiles_by_light_affinity(
		tiles, page_size
	)
	if not _errors.is_empty():
		return null

	var weight_index_by_light: Dictionary = {}
	for light_index: int in light_ids.size():
		weight_index_by_light[light_ids[light_index]] = light_index
	var contribution_layer_count: int = 0
	for page: Dictionary in pages:
		var page_lights: PackedStringArray = page.get(
			"light_ids", PackedStringArray()
		)
		page["layer_base"] = contribution_layer_count
		page["layer_count"] = page_lights.size()
		var layer_by_light: Dictionary = {}
		for light_index: int in page_lights.size():
			layer_by_light[page_lights[light_index]] = (
				contribution_layer_count + light_index
			)
		page["layer_by_light"] = layer_by_light
		contribution_layer_count += page_lights.size()

	for tile: Dictionary in tiles:
		var page_index: int = int(tile.get("page_index", -1))
		if page_index < 0 or page_index >= pages.size():
			_errors.append(
				"tile '%s' has invalid page index %d"
				% [str(tile.get("tile_id", "")), page_index]
			)
			continue
		var page: Dictionary = pages[page_index]
		var layer_by_light: Dictionary = page.get("layer_by_light", {})
		var bindings: Array[Dictionary] = []
		var candidates: PackedStringArray = tile.get(
			"candidate_light_ids", PackedStringArray()
		)
		for slot: int in candidates.size():
			var light_id: String = candidates[slot]
			bindings.append({
				"light_id": light_id,
				"slot": slot,
				"layer_index": int(layer_by_light.get(light_id, -1)),
				"weight_index": int(weight_index_by_light.get(light_id, -1)),
			})
		tile["light_bindings"] = bindings
	if not _errors.is_empty():
		return null

	var layout := VarkAnimatedLightmapLayout.new()
	layout.texel_size_meters = texel_size
	layout.page_size = page_size
	layout.guard_texels = guard_texels
	layout.max_light_slots_per_tile = max_light_slots
	layout.light_ids = light_ids
	layout.faces = faces
	layout.tiles = tiles
	layout.pages = pages
	layout.contribution_layer_count = contribution_layer_count
	layout.geometry_fingerprint = _hash_text(
		_geometry_canonical_text(faces)
	)
	layout.light_influence_fingerprint = compute_light_influence_fingerprint(
		light_descriptors
	)
	layout.representation_fingerprint = _hash_text(
		layout.to_canonical_text()
	)
	return layout


static func compute_light_influence_fingerprint(
	light_descriptors: Dictionary
) -> String:
	var ids := PackedStringArray()
	for key: Variant in light_descriptors.keys():
		ids.append(str(key))
	ids.sort()
	var lines := PackedStringArray()
	for light_id: String in ids:
		var descriptor: Dictionary = light_descriptors.get(light_id, {})
		var position: Vector3 = descriptor.get("position", Vector3.ZERO)
		lines.append(
			"%s|%.9f|%.9f|%.9f|%.9f"
			% [
				light_id,
				position.x,
				position.y,
				position.z,
				float(descriptor.get("range", 0.0)),
			]
		)
	return _hash_text("
".join(lines) + "
")


static func face_texel_center_world(
	face: Dictionary,
	texel: Vector2i,
	texel_size_meters: float
) -> Vector3:
	var origin: Vector3 = face.get("origin", Vector3.ZERO)
	var basis_u: Vector3 = face.get("basis_u", Vector3.RIGHT)
	var basis_v: Vector3 = face.get("basis_v", Vector3.UP)
	var projection_min: Vector2 = face.get("projection_min", Vector2.ZERO)
	var local := Vector2(
		(float(texel.x) + 0.5) * texel_size_meters,
		(float(texel.y) + 0.5) * texel_size_meters
	)
	return (
		origin
		+ basis_u * (projection_min.x + local.x)
		+ basis_v * (projection_min.y + local.y)
	)


static func world_to_face_texel(
	face: Dictionary,
	world_point: Vector3,
	texel_size_meters: float
) -> Vector2:
	var origin: Vector3 = face.get("origin", Vector3.ZERO)
	var basis_u: Vector3 = face.get("basis_u", Vector3.RIGHT)
	var basis_v: Vector3 = face.get("basis_v", Vector3.UP)
	var projection_min: Vector2 = face.get("projection_min", Vector2.ZERO)
	var offset: Vector3 = world_point - origin
	var local := Vector2(
		offset.dot(basis_u) - projection_min.x,
		offset.dot(basis_v) - projection_min.y
	)
	return local / texel_size_meters


static func is_face_texel_valid(
	face: Dictionary,
	texel: Vector2i,
	texel_size_meters: float
) -> bool:
	var useful_size: Vector2i = face.get("useful_size", Vector2i.ZERO)
	if (
		texel.x < 0
		or texel.y < 0
		or texel.x >= useful_size.x
		or texel.y >= useful_size.y
	):
		return false
	var sample := Vector2(
		(float(texel.x) + 0.5) * texel_size_meters,
		(float(texel.y) + 0.5) * texel_size_meters
	)
	var triangles: PackedVector2Array = face.get(
		"triangles_uv", PackedVector2Array()
	)
	for index: int in range(0, triangles.size(), 3):
		if index + 2 >= triangles.size():
			break
		if _point_in_triangle(
			sample,
			triangles[index],
			triangles[index + 1],
			triangles[index + 2]
		):
			return true
	return false


func _extract_mesh_faces(mesh_instance: MeshInstance3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if mesh_instance == null or mesh_instance.mesh == null:
		_errors.append("animated-lightmap extractor received an empty mesh instance")
		return result
	var surface_triangle_offset: int = 0
	for surface_index: int in mesh_instance.mesh.get_surface_count():
		var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface_index)
		var vertices_variant: Variant = arrays[Mesh.ARRAY_VERTEX]
		var indices_variant: Variant = arrays[Mesh.ARRAY_INDEX]
		if not (vertices_variant is PackedVector3Array):
			_errors.append("surface %d has no vertex array" % surface_index)
			continue
		if not (indices_variant is PackedInt32Array):
			_errors.append("surface %d has no indexed triangle array" % surface_index)
			continue
		var vertices: PackedVector3Array = vertices_variant as PackedVector3Array
		var indices: PackedInt32Array = indices_variant as PackedInt32Array
		if vertices.is_empty() or indices.is_empty() or indices.size() % 3 != 0:
			_errors.append(
				"surface %d does not contain indexed triangles" % surface_index
			)
			continue
		var material_id: String = mesh_instance.mesh.surface_get_name(surface_index)
		if material_id.is_empty():
			var material: Material = mesh_instance.mesh.surface_get_material(
				surface_index
			)
			material_id = (
				material.resource_path
				if material != null and not material.resource_path.is_empty()
				else (
					material.resource_name
					if material != null and not material.resource_name.is_empty()
					else "surface_%d" % surface_index
				)
			)
		var triangle_count: int = indices.size() / 3
		var vertex_to_triangles: Dictionary = {}
		for triangle_index: int in triangle_count:
			for corner: int in 3:
				var vertex_index: int = indices[triangle_index * 3 + corner]
				if vertex_index < 0 or vertex_index >= vertices.size():
					_errors.append(
						"surface %d triangle %d references invalid vertex %d"
						% [surface_index, triangle_index, vertex_index]
					)
					continue
				if not vertex_to_triangles.has(vertex_index):
					vertex_to_triangles[vertex_index] = PackedInt32Array()
				var attached: PackedInt32Array = vertex_to_triangles[vertex_index]
				attached.append(triangle_index)
				vertex_to_triangles[vertex_index] = attached
		var visited := PackedByteArray()
		visited.resize(triangle_count)
		for start_triangle: int in triangle_count:
			if visited[start_triangle] != 0:
				continue
			var queue := PackedInt32Array([start_triangle])
			var component := PackedInt32Array()
			visited[start_triangle] = 1
			var cursor: int = 0
			while cursor < queue.size():
				var triangle_index: int = queue[cursor]
				cursor += 1
				component.append(triangle_index)
				for corner: int in 3:
					var vertex_index: int = indices[triangle_index * 3 + corner]
					var neighbors: PackedInt32Array = vertex_to_triangles.get(
						vertex_index, PackedInt32Array()
					)
					for neighbor: int in neighbors:
						if visited[neighbor] == 0:
							visited[neighbor] = 1
							queue.append(neighbor)
			var face: Dictionary = _build_face_record(
				mesh_instance,
				surface_index,
				material_id,
				vertices,
				indices,
				component
			)
			if not face.is_empty():
				_corroborate_func_godot_metadata(
					mesh_instance,
					surface_triangle_offset,
					component,
					material_id,
					face
				)
				result.append(face)
		surface_triangle_offset += triangle_count
	return result


func _corroborate_func_godot_metadata(
	mesh_instance: MeshInstance3D,
	surface_triangle_offset: int,
	component: PackedInt32Array,
	material_id: String,
	face: Dictionary
) -> void:
	var owner: Node = mesh_instance.get_parent()
	if owner == null or not owner.has_meta("func_godot_mesh_data"):
		return
	var metadata_variant: Variant = owner.get_meta("func_godot_mesh_data")
	if not (metadata_variant is Dictionary):
		_errors.append(
			"FuncGodot owner '%s' exposes non-dictionary mesh metadata" % owner.name
		)
		return
	var metadata: Dictionary = metadata_variant as Dictionary
	var texture_names_variant: Variant = metadata.get("texture_names", [])
	var textures_variant: Variant = metadata.get("textures", PackedInt32Array())
	var normals_variant: Variant = metadata.get("normals", PackedVector3Array())
	var positions_variant: Variant = metadata.get("positions", PackedVector3Array())
	if (
		not (texture_names_variant is Array)
		or not (textures_variant is PackedInt32Array)
		or not (normals_variant is PackedVector3Array)
		or not (positions_variant is PackedVector3Array)
	):
		_errors.append(
			"FuncGodot owner '%s' is missing Vark face texture/normal/position metadata"
			% owner.name
		)
		return
	var texture_names: Array = texture_names_variant as Array
	var textures: PackedInt32Array = textures_variant as PackedInt32Array
	var normals: PackedVector3Array = normals_variant as PackedVector3Array
	var positions: PackedVector3Array = positions_variant as PackedVector3Array
	var face_normal: Vector3 = face.get("normal", Vector3.ZERO)
	var face_origin: Vector3 = face.get("origin", Vector3.ZERO)
	for triangle_index: int in component:
		var metadata_index: int = surface_triangle_offset + triangle_index
		if (
			metadata_index < 0
			or metadata_index >= textures.size()
			or metadata_index >= normals.size()
			or metadata_index >= positions.size()
		):
			_errors.append(
				"FuncGodot triangle metadata index %d is outside exported metadata arrays"
				% metadata_index
			)
			continue
		var texture_index: int = textures[metadata_index]
		if texture_index < 0 or texture_index >= texture_names.size():
			_errors.append(
				"FuncGodot triangle metadata index %d has invalid texture index %d"
				% [metadata_index, texture_index]
			)
			continue
		if str(texture_names[texture_index]) != material_id:
			_errors.append(
				"FuncGodot triangle metadata material '%s' disagrees with rendered surface '%s'"
				% [str(texture_names[texture_index]), material_id]
			)
		var metadata_normal: Vector3 = (
			mesh_instance.global_transform.basis * normals[metadata_index]
		).normalized()
		if absf(metadata_normal.dot(face_normal)) < 1.0 - PLANE_EPSILON:
			_errors.append(
				"FuncGodot triangle metadata normal disagrees with recovered rendered face"
			)
		var metadata_position: Vector3 = (
			mesh_instance.global_transform * positions[metadata_index]
		)
		if absf((metadata_position - face_origin).dot(face_normal)) > PLANE_EPSILON:
			_errors.append(
				"FuncGodot triangle metadata position is not on recovered rendered face"
			)


func _build_face_record(
	mesh_instance: MeshInstance3D,
	surface_index: int,
	material_id: String,
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	component: PackedInt32Array
) -> Dictionary:
	var vertex_set: Dictionary = {}
	for triangle_index: int in component:
		for corner: int in 3:
			vertex_set[indices[triangle_index * 3 + corner]] = true
	var vertex_indices: Array[int] = []
	for key: Variant in vertex_set.keys():
		vertex_indices.append(int(key))
	vertex_indices.sort()
	if vertex_indices.size() < 3:
		_errors.append("render-face component has fewer than three vertices")
		return {}
	if vertex_indices[vertex_indices.size() - 1] - vertex_indices[0] + 1 != vertex_indices.size():
		_errors.append(
			"surface %d render-face component is not a contiguous FuncGodot face-local vertex block"
			% surface_index
		)
		return {}

	var world_vertices_by_index: Dictionary = {}
	var sorted_world_vertices: Array[Vector3] = []
	for vertex_index: int in vertex_indices:
		var world_vertex: Vector3 = mesh_instance.global_transform * vertices[vertex_index]
		world_vertices_by_index[vertex_index] = world_vertex
		sorted_world_vertices.append(world_vertex)
	sorted_world_vertices.sort_custom(_sort_vector3)
	var origin: Vector3 = sorted_world_vertices[0]

	var first_triangle: int = component[0]
	var a: Vector3 = world_vertices_by_index[indices[first_triangle * 3]]
	var b: Vector3 = world_vertices_by_index[indices[first_triangle * 3 + 1]]
	var c: Vector3 = world_vertices_by_index[indices[first_triangle * 3 + 2]]
	var normal: Vector3 = (b - a).cross(c - a)
	if normal.length_squared() <= PLANE_EPSILON * PLANE_EPSILON:
		_errors.append("surface %d contains a degenerate rendered triangle" % surface_index)
		return {}
	normal = normal.normalized()
	for triangle_index: int in component:
		var ta: Vector3 = world_vertices_by_index[indices[triangle_index * 3]]
		var tb: Vector3 = world_vertices_by_index[indices[triangle_index * 3 + 1]]
		var tc: Vector3 = world_vertices_by_index[indices[triangle_index * 3 + 2]]
		var triangle_normal: Vector3 = (tb - ta).cross(tc - ta)
		if triangle_normal.length_squared() <= PLANE_EPSILON * PLANE_EPSILON:
			_errors.append("surface %d contains a degenerate rendered triangle" % surface_index)
			return {}
		triangle_normal = triangle_normal.normalized()
		if triangle_normal.dot(normal) < 1.0 - PLANE_EPSILON:
			_errors.append(
				"surface %d connected vertex block is not one planar rendered face"
				% surface_index
			)
			return {}
		for point: Vector3 in [ta, tb, tc]:
			if absf((point - origin).dot(normal)) > PLANE_EPSILON:
				_errors.append(
					"surface %d connected vertex block is not coplanar"
					% surface_index
				)
				return {}

	var reference: Vector3 = (
		Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	)
	var basis_u: Vector3 = reference.cross(normal).normalized()
	var basis_v: Vector3 = normal.cross(basis_u).normalized()
	var projection_min := Vector2(INF, INF)
	var projection_max := Vector2(-INF, -INF)
	for point: Vector3 in sorted_world_vertices:
		var offset: Vector3 = point - origin
		var projected := Vector2(offset.dot(basis_u), offset.dot(basis_v))
		projection_min = projection_min.min(projected)
		projection_max = projection_max.max(projected)
	var extent: Vector2 = projection_max - projection_min
	if extent.x <= PLANE_EPSILON or extent.y <= PLANE_EPSILON:
		_errors.append("surface %d rendered face has zero projected area" % surface_index)
		return {}

	var triangle_records: Array[Dictionary] = []
	for triangle_index: int in component:
		var triangle_uv := PackedVector2Array()
		var triangle_world: Array[Vector3] = []
		for corner: int in 3:
			var point: Vector3 = world_vertices_by_index[
				indices[triangle_index * 3 + corner]
			]
			triangle_world.append(point)
			var offset: Vector3 = point - origin
			triangle_uv.append(
				Vector2(offset.dot(basis_u), offset.dot(basis_v)) - projection_min
			)
		triangle_records.append({
			"key": _triangle_key(triangle_world),
			"uv": triangle_uv,
		})
	triangle_records.sort_custom(_sort_triangle_records)
	var triangles_uv := PackedVector2Array()
	for record: Dictionary in triangle_records:
		triangles_uv.append_array(record.get("uv", PackedVector2Array()))

	var vertex_parts := PackedStringArray()
	for point: Vector3 in sorted_world_vertices:
		vertex_parts.append(_vector3_key(point))
	var coincident_key: String = ";".join(vertex_parts)
	var face_id: String = _hash_text(
		"%s|n=%s|verts=%s"
		% [material_id, _vector3_key(normal), ";".join(vertex_parts)]
	)
	return {
		"face_id": face_id,
		"coincident_key": coincident_key,
		"material_id": material_id,
		"normal": normal,
		"origin": origin,
		"basis_u": basis_u,
		"basis_v": basis_v,
		"projection_min": projection_min,
		"extent": extent,
		"triangles_uv": triangles_uv,
		"runtime_surface_index": surface_index,
		"runtime_vertex_start": vertex_indices[0],
		"runtime_vertex_count": vertex_indices.size(),
	}


func _candidate_lights_for_tile(
	face: Dictionary,
	texel_offset: Vector2i,
	useful_size: Vector2i,
	texel_size: float,
	light_descriptors: Dictionary,
	light_ids: PackedStringArray
) -> PackedStringArray:
	var origin: Vector3 = face.get("origin", Vector3.ZERO)
	var basis_u: Vector3 = face.get("basis_u", Vector3.RIGHT)
	var basis_v: Vector3 = face.get("basis_v", Vector3.UP)
	var projection_min: Vector2 = face.get("projection_min", Vector2.ZERO)
	var local_min := Vector2(
		float(texel_offset.x) * texel_size,
		float(texel_offset.y) * texel_size
	)
	var local_max := Vector2(
		float(texel_offset.x + useful_size.x) * texel_size,
		float(texel_offset.y + useful_size.y) * texel_size
	)
	var world_points: Array[Vector3] = []
	for local: Vector2 in [
		Vector2(local_min.x, local_min.y),
		Vector2(local_max.x, local_min.y),
		Vector2(local_min.x, local_max.y),
		Vector2(local_max.x, local_max.y),
	]:
		world_points.append(
			origin
			+ basis_u * (projection_min.x + local.x)
			+ basis_v * (projection_min.y + local.y)
		)
	var aabb_min: Vector3 = world_points[0]
	var aabb_max: Vector3 = world_points[0]
	for point: Vector3 in world_points:
		aabb_min = aabb_min.min(point)
		aabb_max = aabb_max.max(point)
	var result := PackedStringArray()
	for light_id: String in light_ids:
		var descriptor: Dictionary = light_descriptors.get(light_id, {})
		var position: Vector3 = descriptor.get("position", Vector3.ZERO)
		var light_range: float = maxf(float(descriptor.get("range", 0.0)), 0.0)
		if _distance_to_aabb(position, aabb_min, aabb_max) <= light_range + PLANE_EPSILON:
			result.append(light_id)
	return result


func _pack_tiles_by_light_affinity(
	tiles: Array[Dictionary],
	page_size: int
) -> Array[Dictionary]:
	var groups: Dictionary = {}
	for tile: Dictionary in tiles:
		var candidates: PackedStringArray = tile.get(
			"candidate_light_ids", PackedStringArray()
		)
		var signature: String = ",".join(candidates)
		if not groups.has(signature):
			groups[signature] = []
		var grouped: Array = groups[signature]
		grouped.append(tile)
		groups[signature] = grouped
	var signatures := PackedStringArray()
	for key: Variant in groups.keys():
		signatures.append(str(key))
	signatures.sort()
	var pages: Array[Dictionary] = []
	for signature: String in signatures:
		var group: Array = groups.get(signature, [])
		group.sort_custom(_sort_tile_records)
		var page: Dictionary = {}
		var cursor_x: int = 0
		var cursor_y: int = 0
		var row_height: int = 0
		for tile_variant: Variant in group:
			var tile: Dictionary = tile_variant as Dictionary
			var rect_size: Vector2i = tile.get("rect_size", Vector2i.ZERO)
			if rect_size.x > page_size or rect_size.y > page_size:
				_errors.append(
					"tile '%s' guarded rectangle %s exceeds page size %d"
					% [str(tile.get("tile_id", "")), str(rect_size), page_size]
				)
				continue
			if page.is_empty():
				page = _new_page(pages.size(), signature)
			if cursor_x + rect_size.x > page_size:
				cursor_x = 0
				cursor_y += row_height
				row_height = 0
			if cursor_y + rect_size.y > page_size:
				pages.append(page)
				page = _new_page(pages.size(), signature)
				cursor_x = 0
				cursor_y = 0
				row_height = 0
			tile["page_index"] = int(page.get("page_index", -1))
			tile["rect_position"] = Vector2i(cursor_x, cursor_y)
			var tile_ids: PackedStringArray = page.get(
				"tile_ids", PackedStringArray()
			)
			tile_ids.append(str(tile.get("tile_id", "")))
			page["tile_ids"] = tile_ids
			cursor_x += rect_size.x
			row_height = maxi(row_height, rect_size.y)
		if not page.is_empty():
			pages.append(page)
	return pages


func _new_page(page_index: int, signature: String) -> Dictionary:
	var page_lights := PackedStringArray()
	if not signature.is_empty():
		for part: String in signature.split(",", false):
			page_lights.append(part)
	return {
		"page_index": page_index,
		"light_ids": page_lights,
		"tile_ids": PackedStringArray(),
		"layer_base": -1,
		"layer_count": 0,
		"layer_by_light": {},
	}


func _validate_light_descriptors(descriptors: Dictionary) -> PackedStringArray:
	var light_ids := PackedStringArray()
	for key: Variant in descriptors.keys():
		var light_id: String = str(key).strip_edges()
		if light_id.is_empty():
			_errors.append("animated-lightmap light identity cannot be blank")
			continue
		var descriptor_variant: Variant = descriptors.get(key, {})
		if not (descriptor_variant is Dictionary):
			_errors.append("light '%s' descriptor is not a dictionary" % light_id)
			continue
		var descriptor: Dictionary = descriptor_variant as Dictionary
		if not (descriptor.get("position", null) is Vector3):
			_errors.append("light '%s' descriptor has no Vector3 position" % light_id)
			continue
		var light_range: float = float(descriptor.get("range", 0.0))
		if not is_finite(light_range) or light_range <= 0.0:
			_errors.append("light '%s' descriptor range must be positive" % light_id)
			continue
		light_ids.append(light_id)
	light_ids.sort()
	return light_ids


static func _geometry_canonical_text(faces: Array[Dictionary]) -> String:
	var lines := PackedStringArray()
	for face: Dictionary in faces:
		lines.append(
			"%s|%s|%s|%s|%s|%s|%s"
			% [
				str(face.get("face_id", "")),
				str(face.get("material_id", "")),
				_vector3_key(face.get("normal", Vector3.ZERO)),
				_vector3_key(face.get("origin", Vector3.ZERO)),
				_vector3_key(face.get("basis_u", Vector3.ZERO)),
				_vector3_key(face.get("basis_v", Vector3.ZERO)),
				str(face.get("triangles_uv", PackedVector2Array())),
			]
		)
	return "
".join(lines) + "
"


static func _hash_text(value: String) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()


static func _vector3_key(value: Vector3) -> String:
	var snapped: Vector3 = value.snappedf(ID_QUANTUM)
	return "%.5f,%.5f,%.5f" % [snapped.x, snapped.y, snapped.z]


static func _triangle_key(points: Array[Vector3]) -> String:
	var keys := PackedStringArray()
	for point: Vector3 in points:
		keys.append(_vector3_key(point))
	keys.sort()
	return ";".join(keys)


static func _sort_face_records(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("face_id", "")) < str(b.get("face_id", ""))


static func _sort_tile_records(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("tile_id", "")) < str(b.get("tile_id", ""))


static func _sort_triangle_records(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("key", "")) < str(b.get("key", ""))


static func _sort_vector3(a: Vector3, b: Vector3) -> bool:
	return _vector3_key(a) < _vector3_key(b)


static func _distance_to_aabb(
	point: Vector3,
	minimum: Vector3,
	maximum: Vector3
) -> float:
	var closest := Vector3(
		clampf(point.x, minimum.x, maximum.x),
		clampf(point.y, minimum.y, maximum.y),
		clampf(point.z, minimum.z, maximum.z)
	)
	return point.distance_to(closest)


static func _point_in_triangle(
	point: Vector2,
	a: Vector2,
	b: Vector2,
	c: Vector2
) -> bool:
	var denominator: float = (
		(b.y - c.y) * (a.x - c.x)
		+ (c.x - b.x) * (a.y - c.y)
	)
	if absf(denominator) <= 0.0000001:
		return false
	var alpha: float = (
		(b.y - c.y) * (point.x - c.x)
		+ (c.x - b.x) * (point.y - c.y)
	) / denominator
	var beta: float = (
		(c.y - a.y) * (point.x - c.x)
		+ (a.x - c.x) * (point.y - c.y)
	) / denominator
	var gamma: float = 1.0 - alpha - beta
	return alpha >= -PLANE_EPSILON and beta >= -PLANE_EPSILON and gamma >= -PLANE_EPSILON
