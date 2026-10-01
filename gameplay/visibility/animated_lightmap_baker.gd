class_name VarkAnimatedLightmapBaker
extends RefCounted

const WORLD_COLLISION_MASK: int = 1
const RAY_START_EPSILON: float = 0.012
const RAY_END_CLEARANCE: float = 0.42

static func find_single_bake_mesh(root: Node) -> MeshInstance3D:
	if root == null:
		return null
	var candidates: Array[MeshInstance3D] = []
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if (
			mesh_instance != null
			and mesh_instance.mesh != null
			and mesh_instance.gi_mode == GeometryInstance3D.GI_MODE_STATIC
			and has_complete_uv2(mesh_instance)
		):
			candidates.append(mesh_instance)
	return candidates[0] if candidates.size() == 1 else null

static func has_complete_uv2(mesh_instance: MeshInstance3D) -> bool:
	if mesh_instance == null or mesh_instance.mesh == null:
		return false
	for surface_index: int in mesh_instance.mesh.get_surface_count():
		var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface_index)
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var uv2 := arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array
		if vertices.is_empty() or uv2.size() != vertices.size():
			return false
	return mesh_instance.mesh.get_surface_count() > 0

static func compute_geometry_fingerprint(
	mesh_instance: MeshInstance3D
) -> String:
	if not has_complete_uv2(mesh_instance):
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(
		("surfaces=%d\n" % mesh_instance.mesh.get_surface_count()).to_utf8_buffer()
	)
	for surface_index: int in mesh_instance.mesh.get_surface_count():
		var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface_index)
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
		var uv2 := arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array
		var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		context.update(("surface=%d\n" % surface_index).to_utf8_buffer())
		for index: int in vertices.size():
			var world_vertex: Vector3 = (
				mesh_instance.global_transform * vertices[index]
			)
			var normal: Vector3 = (
				normals[index] if index < normals.size() else Vector3.ZERO
			)
			var world_normal: Vector3 = (
				mesh_instance.global_transform.basis * normal
			).normalized()
			var texel_uv: Vector2 = uv2[index]
			context.update(
				(
					"v=%.9f,%.9f,%.9f;n=%.9f,%.9f,%.9f;u=%.9f,%.9f\n"
					% [
						world_vertex.x, world_vertex.y, world_vertex.z,
						world_normal.x, world_normal.y, world_normal.z,
						texel_uv.x, texel_uv.y,
					]
				).to_utf8_buffer()
			)
		context.update(("i=%s\n" % str(indices)).to_utf8_buffer())
	return context.finish().hex_encode()

static func descriptor_from_gameplay_light(
	light: VarkGameplayLight
) -> Dictionary:
	if light == null:
		return {}
	return {
		"position": light.get_emitter_global_position(),
		"color": light.light_color,
		"energy": maxf(light.light_energy, 0.0),
		"range": maxf(light.omni_range, 0.001),
	}

static func bake_data(
	source_map_path: String,
	mesh_instance: MeshInstance3D,
	light_descriptors: Dictionary,
	space_state: PhysicsDirectSpaceState3D,
	texture_size: Vector2i
) -> VarkAnimatedLightmapData:
	if (
		mesh_instance == null
		or not has_complete_uv2(mesh_instance)
		or space_state == null
		or texture_size.x <= 0
		or texture_size.y <= 0
	):
		return null
	var result := VarkAnimatedLightmapData.new()
	result.source_map_path = source_map_path
	result.source_sha256 = VarkAnimatedLightmapData.compute_file_sha256(
		source_map_path
	)
	result.geometry_fingerprint = compute_geometry_fingerprint(mesh_instance)
	result.texture_size = texture_size
	result.light_descriptors = light_descriptors.duplicate(true)
	result.light_fingerprint = VarkAnimatedLightmapData.compute_light_fingerprint(
		light_descriptors
	)
	for key: Variant in light_descriptors.keys():
		var light_id: String = str(key)
		var bytes: PackedByteArray = bake_light_layer(
			mesh_instance,
			space_state,
			light_descriptors.get(light_id, {}),
			texture_size
		)
		if not result.set_light_layer_bytes(light_id, bytes):
			return null
	return result

static func bake_light_layer(
	mesh_instance: MeshInstance3D,
	space_state: PhysicsDirectSpaceState3D,
	descriptor: Dictionary,
	texture_size: Vector2i
) -> PackedByteArray:
	var output := PackedByteArray()
	output.resize(texture_size.x * texture_size.y * 4)
	for pixel_index: int in texture_size.x * texture_size.y:
		output[pixel_index * 4 + 3] = 255
	for surface_index: int in mesh_instance.mesh.get_surface_count():
		var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface_index)
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
		var uv2 := arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array
		var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		var triangle_count: int = (
			indices.size() / 3
			if not indices.is_empty()
			else vertices.size() / 3
		)
		for triangle_index: int in triangle_count:
			var vertex_indices := PackedInt32Array()
			for corner: int in 3:
				vertex_indices.append(
					indices[triangle_index * 3 + corner]
					if not indices.is_empty()
					else triangle_index * 3 + corner
				)
			_rasterize_triangle(
				output, texture_size, mesh_instance, vertices, normals, uv2,
				vertex_indices, space_state, descriptor
			)
	return output

static func sample_direct_light_at_point(
	point: Vector3,
	normal: Vector3,
	descriptor: Dictionary,
	space_state: PhysicsDirectSpaceState3D
) -> Color:
	if space_state == null:
		return Color(0, 0, 0, 1)
	var light_position: Vector3 = descriptor.get("position", Vector3.ZERO)
	var offset: Vector3 = light_position - point
	var distance: float = offset.length()
	var light_range: float = maxf(float(descriptor.get("range", 0.0)), 0.001)
	if distance <= 0.00001 or distance >= light_range:
		return Color(0, 0, 0, 1)
	var direction: Vector3 = offset / distance
	var ndotl: float = maxf(normal.normalized().dot(direction), 0.0)
	if ndotl <= 0.0:
		return Color(0, 0, 0, 1)
	var ray_length: float = maxf(distance - RAY_END_CLEARANCE, 0.0)
	if ray_length > RAY_START_EPSILON:
		var query := PhysicsRayQueryParameters3D.create(
			point + direction * RAY_START_EPSILON,
			point + direction * ray_length,
			WORLD_COLLISION_MASK
		)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		if not space_state.intersect_ray(query).is_empty():
			return Color(0, 0, 0, 1)
	var attenuation: float = 1.0 - distance / light_range
	attenuation *= attenuation
	var intensity: float = clampf(
		float(descriptor.get("energy", 0.0)) * attenuation * ndotl,
		0.0,
		1.0
	)
	var color: Color = descriptor.get("color", Color.WHITE)
	return Color(
		clampf(color.r * intensity, 0.0, 1.0),
		clampf(color.g * intensity, 0.0, 1.0),
		clampf(color.b * intensity, 0.0, 1.0),
		1.0
	)

static func _rasterize_triangle(
	output: PackedByteArray,
	texture_size: Vector2i,
	mesh_instance: MeshInstance3D,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uv2: PackedVector2Array,
	vertex_indices: PackedInt32Array,
	space_state: PhysicsDirectSpaceState3D,
	descriptor: Dictionary
) -> void:
	var a: int = vertex_indices[0]
	var b: int = vertex_indices[1]
	var c: int = vertex_indices[2]
	var ua: Vector2 = uv2[a]
	var ub: Vector2 = uv2[b]
	var uc: Vector2 = uv2[c]
	var min_x: int = clampi(
		floori(minf(ua.x, minf(ub.x, uc.x)) * texture_size.x),
		0, texture_size.x - 1
	)
	var max_x: int = clampi(
		ceili(maxf(ua.x, maxf(ub.x, uc.x)) * texture_size.x),
		0, texture_size.x - 1
	)
	var min_y: int = clampi(
		floori(minf(ua.y, minf(ub.y, uc.y)) * texture_size.y),
		0, texture_size.y - 1
	)
	var max_y: int = clampi(
		ceili(maxf(ua.y, maxf(ub.y, uc.y)) * texture_size.y),
		0, texture_size.y - 1
	)
	var denominator: float = (
		(ub.y - uc.y) * (ua.x - uc.x)
		+ (uc.x - ub.x) * (ua.y - uc.y)
	)
	if absf(denominator) <= 0.0000001:
		return
	var wa: Vector3 = mesh_instance.global_transform * vertices[a]
	var wb: Vector3 = mesh_instance.global_transform * vertices[b]
	var wc: Vector3 = mesh_instance.global_transform * vertices[c]
	var na: Vector3 = (
		mesh_instance.global_transform.basis
		* (normals[a] if a < normals.size() else Vector3.ZERO)
	)
	var nb: Vector3 = (
		mesh_instance.global_transform.basis
		* (normals[b] if b < normals.size() else Vector3.ZERO)
	)
	var nc: Vector3 = (
		mesh_instance.global_transform.basis
		* (normals[c] if c < normals.size() else Vector3.ZERO)
	)
	if na.length_squared() <= 0.000001:
		var face_normal: Vector3 = (wb - wa).cross(wc - wa).normalized()
		na = face_normal
		nb = face_normal
		nc = face_normal
	for y: int in range(min_y, max_y + 1):
		for x: int in range(min_x, max_x + 1):
			var sample_uv := Vector2(
				(float(x) + 0.5) / float(texture_size.x),
				(float(y) + 0.5) / float(texture_size.y)
			)
			var alpha: float = (
				(ub.y - uc.y) * (sample_uv.x - uc.x)
				+ (uc.x - ub.x) * (sample_uv.y - uc.y)
			) / denominator
			var beta: float = (
				(uc.y - ua.y) * (sample_uv.x - uc.x)
				+ (ua.x - uc.x) * (sample_uv.y - uc.y)
			) / denominator
			var gamma: float = 1.0 - alpha - beta
			if alpha < -0.0001 or beta < -0.0001 or gamma < -0.0001:
				continue
			var world_point: Vector3 = wa * alpha + wb * beta + wc * gamma
			var world_normal: Vector3 = (
				na * alpha + nb * beta + nc * gamma
			).normalized()
			var contribution: Color = sample_direct_light_at_point(
				world_point, world_normal, descriptor, space_state
			)
			var byte_offset: int = (y * texture_size.x + x) * 4
			output[byte_offset] = maxi(
				output[byte_offset], roundi(contribution.r * 255.0)
			)
			output[byte_offset + 1] = maxi(
				output[byte_offset + 1], roundi(contribution.g * 255.0)
			)
			output[byte_offset + 2] = maxi(
				output[byte_offset + 2], roundi(contribution.b * 255.0)
			)
