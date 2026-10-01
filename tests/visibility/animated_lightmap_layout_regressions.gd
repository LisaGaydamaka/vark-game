extends RefCounted

const LAB_MAP_PATH: String = (
	"res://scenes/animated_lightmap_lab/animated_lightmap_lab.map"
)
const LEDGE_MAP_PATH: String = (
	"res://missions/representative_stealth_ledge_city/mission.map"
)
const MAP_SETTINGS_PATH: String = "res://authoring/vark_map_settings.tres"


func run(tree: SceneTree, assert_true: Callable) -> void:
	_test_exact_face_boundaries_and_stable_identity(assert_true)
	_test_mapping_tiling_guards_and_refusal(assert_true)
	_test_hdr_and_sparse_weight_abi(assert_true)
	await _test_real_func_godot_face_recovery(tree, assert_true)
	await _test_ledge_city_scale_and_slot_budget(tree, assert_true)


func _test_exact_face_boundaries_and_stable_identity(
	assert_true: Callable
) -> void:
	var descriptors := {
		"light.a": {
			"position": Vector3(0.5, 0.5, 1.0),
			"range": 2.0,
		},
		"light.b": {
			"position": Vector3(1.5, 0.5, 1.0),
			"range": 2.0,
		},
	}
	var options := {
		"texel_size_meters": 0.25,
		"page_size": 32,
		"guard_texels": 1,
		"max_light_slots": 8,
	}
	var first_mesh: MeshInstance3D = _two_adjacent_square_mesh(false)
	var second_mesh: MeshInstance3D = _two_adjacent_square_mesh(true)
	var first_builder := VarkAnimatedLightmapLayoutBuilder.new()
	var second_builder := VarkAnimatedLightmapLayoutBuilder.new()
	var first: VarkAnimatedLightmapLayout = first_builder.build_from_mesh_instances(
		[first_mesh], descriptors, options
	)
	var second: VarkAnimatedLightmapLayout = second_builder.build_from_mesh_instances(
		[second_mesh], descriptors, options
	)
	assert_true.call(
		first != null
		and second != null
		and first.faces.size() == 2
		and second.faces.size() == 2
		and first.geometry_fingerprint == second.geometry_fingerprint
		and first.representation_fingerprint == second.representation_fingerprint
		and first.to_canonical_text() == second.to_canonical_text(),
		"8.4.1A preserves two adjacent coplanar same-material FuncGodot-style face-local vertex blocks as two stable logical faces independent of source/triangle block order"
	)

	var changed_geometry_builder := VarkAnimatedLightmapLayoutBuilder.new()
	var changed_geometry: VarkAnimatedLightmapLayout = (
		changed_geometry_builder.build_from_mesh_instances(
			[_two_adjacent_square_mesh(false, 0.125)],
			descriptors,
			options
		)
	)
	var changed_material_builder := VarkAnimatedLightmapLayoutBuilder.new()
	var changed_material: VarkAnimatedLightmapLayout = (
		changed_material_builder.build_from_mesh_instances(
			[_two_adjacent_square_mesh(false, 0.0, "vark_surfaces/tile")],
			descriptors,
			options
		)
	)
	assert_true.call(
		changed_geometry != null
		and changed_material != null
		and changed_geometry.geometry_fingerprint != first.geometry_fingerprint
		and changed_material.geometry_fingerprint != first.geometry_fingerprint,
		"8.4.1A canonical face identity invalidates when rendered geometry or material identity changes"
	)

	var duplicate_builder := VarkAnimatedLightmapLayoutBuilder.new()
	var duplicate: VarkAnimatedLightmapLayout = (
		duplicate_builder.build_from_mesh_instances(
			[_duplicate_square_mesh()], {}, options
		)
	)
	assert_true.call(
		duplicate == null
		and _contains_error(
			duplicate_builder.get_errors(), "duplicate/coincident rendered face"
		),
		"8.4.1A rejects duplicate/coincident canonical rendered faces instead of assigning ambiguous bake identity"
	)


func _test_mapping_tiling_guards_and_refusal(assert_true: Callable) -> void:
	var triangle_builder := VarkAnimatedLightmapLayoutBuilder.new()
	var triangle_layout: VarkAnimatedLightmapLayout = (
		triangle_builder.build_from_mesh_instances(
			[_triangle_mesh()],
			{},
			{
				"texel_size_meters": 0.25,
				"page_size": 16,
				"guard_texels": 1,
				"max_light_slots": 8,
			}
		)
	)
	var triangle_face: Dictionary = (
		triangle_layout.faces[0] if triangle_layout != null else {}
	)
	var texel_center: Vector3 = (
		VarkAnimatedLightmapLayoutBuilder.face_texel_center_world(
			triangle_face, Vector2i.ZERO, 0.25
		)
		if triangle_layout != null else Vector3.ZERO
	)
	var texel_round_trip: Vector2 = (
		VarkAnimatedLightmapLayoutBuilder.world_to_face_texel(
			triangle_face, texel_center, 0.25
		)
		if triangle_layout != null else Vector2.ZERO
	)
	assert_true.call(
		triangle_layout != null
		and triangle_face.get("useful_size", Vector2i.ZERO) == Vector2i(4, 4)
		and VarkAnimatedLightmapLayoutBuilder.is_face_texel_valid(
			triangle_face, Vector2i(0, 0), 0.25
		)
		and not VarkAnimatedLightmapLayoutBuilder.is_face_texel_valid(
			triangle_face, Vector2i(3, 3), 0.25
		)
		and texel_round_trip.distance_to(Vector2(0.5, 0.5)) <= 0.0001,
		"8.4.1A derives physical face texel dimensions, masks polygon-exterior cells, and round-trips texel centers through exact face-local/world mapping"
	)

	var tiled_builder := VarkAnimatedLightmapLayoutBuilder.new()
	var tiled_layout: VarkAnimatedLightmapLayout = (
		tiled_builder.build_from_mesh_instances(
			[_rectangle_mesh(4.0, 1.0)],
			{},
			{
				"texel_size_meters": 0.25,
				"page_size": 8,
				"guard_texels": 1,
				"max_light_slots": 8,
			}
		)
	)
	var same_logical_face: bool = tiled_layout != null and tiled_layout.tiles.size() == 3
	if same_logical_face:
		var face_id: String = str(tiled_layout.tiles[0].get("face_id", ""))
		for tile: Dictionary in tiled_layout.tiles:
			var rect_size: Vector2i = tile.get("rect_size", Vector2i.ZERO)
			same_logical_face = (
				same_logical_face
				and str(tile.get("face_id", "")) == face_id
				and rect_size.x <= tiled_layout.page_size
				and rect_size.y <= tiled_layout.page_size
			)
	assert_true.call(
		same_logical_face,
		"8.4.1A deterministically tiles an oversized logical face without changing its face identity or downscaling its physical texel density"
	)

	var guard_layout_builder := VarkAnimatedLightmapLayoutBuilder.new()
	var guard_layout: VarkAnimatedLightmapLayout = (
		guard_layout_builder.build_from_mesh_instances(
			[_two_adjacent_square_mesh(false)],
			{},
			{
				"texel_size_meters": 0.25,
				"page_size": 16,
				"guard_texels": 1,
				"max_light_slots": 8,
			}
		)
	)
	var guard_isolated: bool = _guarded_tiles_are_linearly_isolated(guard_layout)
	assert_true.call(
		guard_isolated,
		"8.4.1A guarded atlas rectangles keep bright/dark neighboring faces isolated under the declared linear-filter sampling footprint"
	)

	var impossible_builder := VarkAnimatedLightmapLayoutBuilder.new()
	var impossible: VarkAnimatedLightmapLayout = (
		impossible_builder.build_from_mesh_instances(
			[_triangle_mesh()],
			{},
			{
				"texel_size_meters": 0.25,
				"page_size": 2,
				"guard_texels": 1,
				"max_light_slots": 8,
			}
		)
	)
	assert_true.call(
		impossible == null
		and _contains_error(
			impossible_builder.get_errors(), "no useful area after guards"
		),
		"8.4.1A fails closed when guarded atlas allocation is impossible even after deterministic face tiling"
	)


func _test_hdr_and_sparse_weight_abi(assert_true: Callable) -> void:
	var source_color := Color(3.5, 1.25, 0.5, 1.0)
	var hdr_colors: Array[Color] = [source_color]
	var encoded: PackedByteArray = VarkAnimatedLightmapLayout.encode_hdr_colors(
		hdr_colors
	)
	var decoded: Array[Color] = VarkAnimatedLightmapLayout.decode_hdr_colors(
		encoded, 1
	)
	assert_true.call(
		encoded.size() == VarkAnimatedLightmapLayout.BYTES_PER_TEXEL
		and decoded.size() == 1
		and decoded[0].r > 3.0
		and absf(decoded[0].r - source_color.r) < 0.01
		and absf(decoded[0].g - source_color.g) < 0.01,
		"8.4.1A uses linear RGBA16F contribution storage that preserves HDR values above 1.0 instead of clamping individual light layers to RGBA8"
	)

	var descriptors: Dictionary = {}
	for index: int in 9:
		descriptors["light.%d" % index] = {
			"position": Vector3(0.5, 0.5, 1.0),
			"range": 10.0,
		}
	var overflow_builder := VarkAnimatedLightmapLayoutBuilder.new()
	var overflow: VarkAnimatedLightmapLayout = (
		overflow_builder.build_from_mesh_instances(
			[_triangle_mesh()],
			descriptors,
			{
				"texel_size_meters": 0.25,
				"page_size": 16,
				"guard_texels": 1,
				"max_light_slots": 8,
			}
		)
	)
	assert_true.call(
		overflow == null
		and _contains_error(overflow_builder.get_errors(), "needs 9 animated lights"),
		"8.4.1A sparse composition refuses per-tile light-slot overflow instead of silently truncating animated-light influence"
	)

	var two_lights := {
		"light.a": {"position": Vector3(0.2, 0.2, 1.0), "range": 3.0},
		"light.b": {"position": Vector3(0.8, 0.8, 1.0), "range": 3.0},
	}
	var builder := VarkAnimatedLightmapLayoutBuilder.new()
	var layout: VarkAnimatedLightmapLayout = builder.build_from_mesh_instances(
		[_triangle_mesh()],
		two_lights,
		{
			"texel_size_meters": 0.25,
			"page_size": 16,
			"guard_texels": 1,
			"max_light_slots": 8,
		}
	)
	var canonical_before: String = (
		layout.to_canonical_text() if layout != null else ""
	)
	var weights := VarkAnimatedLightmapWeightState.new()
	var configured: bool = weights.configure(layout)
	var changed: bool = weights.set_light_weight("light.a", 0.5)
	var updates: Array[Dictionary] = weights.consume_dirty_updates()
	var tile_bindings: Array = (
		layout.tiles[0].get("light_bindings", [])
		if layout != null and not layout.tiles.is_empty()
		else []
	)
	assert_true.call(
		layout != null
		and configured
		and changed
		and updates.size() == 1
		and updates[0].get("light_id", "") == "light.a"
		and is_equal_approx(float(updates[0].get("weight", -1.0)), 0.5)
		and tile_bindings.size() == 2
		and tile_bindings.size() <= layout.max_light_slots_per_tile
		and layout.get_gpu_contract().get("backend", &"")
			== VarkAnimatedLightmapLayout.COMPOSITION_BACKEND
		and layout.to_canonical_text() == canonical_before,
		"8.4.1A fixes the GPU ABI to sparse per-tile Texture2DArray page/light layers plus a small weight buffer, so a fade changes only one weight entry and never rewrites atlas pixels"
	)

	var affinity_descriptors := {
		"light.left": {"position": Vector3(0.25, 0.5, 0.2), "range": 0.4},
		"light.right": {"position": Vector3(1.75, 0.5, 0.2), "range": 0.4},
	}
	var affinity_builder := VarkAnimatedLightmapLayoutBuilder.new()
	var affinity_layout: VarkAnimatedLightmapLayout = (
		affinity_builder.build_from_mesh_instances(
			[_two_adjacent_square_mesh(false)],
			affinity_descriptors,
			{
				"texel_size_meters": 0.25,
				"page_size": 16,
				"guard_texels": 1,
				"max_light_slots": 8,
			}
		)
	)
	var affinity_isolated: bool = affinity_layout != null and affinity_layout.pages.size() == 2
	if affinity_isolated:
		for page: Dictionary in affinity_layout.pages:
			var page_lights: PackedStringArray = page.get(
				"light_ids", PackedStringArray()
			)
			affinity_isolated = affinity_isolated and page_lights.size() == 1
	assert_true.call(
		affinity_isolated,
		"8.4.1A deterministic atlas packing groups tiles by animated-light affinity so unrelated page occupants do not force dense page/light sampling"
	)

	var stale_errors: PackedStringArray = layout.get_validation_errors(
		"stale-geometry", layout.light_influence_fingerprint
	)
	assert_true.call(
		_contains_error(stale_errors, "surface geometry fingerprint mismatch"),
		"8.4.1A serialized surface/page layouts fail closed when authoritative rendered geometry no longer matches"
	)


func _test_real_func_godot_face_recovery(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	var first: FuncGodotMap = await _build_func_map(tree, LAB_MAP_PATH, "LayoutLabA")
	var second: FuncGodotMap = await _build_func_map(tree, LAB_MAP_PATH, "LayoutLabB")
	var first_descriptors: Dictionary = _collect_light_descriptors(first)
	var second_descriptors: Dictionary = _collect_light_descriptors(second)
	var first_builder := VarkAnimatedLightmapLayoutBuilder.new()
	var second_builder := VarkAnimatedLightmapLayoutBuilder.new()
	var first_layout: VarkAnimatedLightmapLayout = first_builder.build_from_root(
		first, first_descriptors
	)
	var second_layout: VarkAnimatedLightmapLayout = second_builder.build_from_root(
		second, second_descriptors
	)
	var first_mesh: MeshInstance3D = _first_func_godot_mesh(first)
	var has_uv2: bool = _mesh_has_any_uv2(first_mesh)
	assert_true.call(
		first_layout != null
		and second_layout != null
		and not first_layout.faces.is_empty()
		and first_layout.geometry_fingerprint == second_layout.geometry_fingerprint
		and first_layout.representation_fingerprint
			== second_layout.representation_fingerprint
		and not has_uv2,
		"8.4.1A reconstructs stable face/page ownership from two repeated real FuncGodot builds with UV2 unwrap disabled, proving production brush-light coordinates no longer depend on Godot lightmap_unwrap()"
	)
	first.queue_free()
	second.queue_free()
	await tree.process_frame


func _test_ledge_city_scale_and_slot_budget(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	var ledge: FuncGodotMap = await _build_func_map(
		tree, LEDGE_MAP_PATH, "LayoutLedgeCity"
	)
	var descriptors: Dictionary = _collect_light_descriptors(ledge)
	var analysis_builder := VarkAnimatedLightmapLayoutBuilder.new()
	var analysis: VarkAnimatedLightmapLayout = analysis_builder.build_from_root(
		ledge,
		descriptors,
		{
			"max_light_slots": 64,
		}
	)
	var report: Dictionary = analysis.get_scale_report() if analysis != null else {}
	print("[ANIMATED_LIGHTMAP_LAYOUT_LEDGE] ", JSON.stringify(report))
	var max_candidates: int = int(report.get("max_candidate_lights_per_tile", 0))
	var production_builder := VarkAnimatedLightmapLayoutBuilder.new()
	var production: VarkAnimatedLightmapLayout = production_builder.build_from_root(
		ledge, descriptors
	)
	assert_true.call(
		analysis != null
		and descriptors.size() == 23
		and int(report.get("logical_faces", 0)) > 0
		and int(report.get("face_tiles", 0)) >= int(report.get("logical_faces", 0))
		and int(report.get("atlas_pages", 0)) > 0
		and max_candidates
			<= VarkAnimatedLightmapLayout.DEFAULT_MAX_LIGHT_SLOTS_PER_TILE
		and production != null
		and production.get_validation_errors(
			production.geometry_fingerprint,
			VarkAnimatedLightmapLayoutBuilder.compute_light_influence_fingerprint(
				descriptors
			)
		).is_empty(),
		"8.4.1A Ledge City dry analysis measures the real 23-light mission before locking the sparse slot ABI and fits the declared eight-light per-tile limit without truncation"
	)
	ledge.queue_free()
	await tree.process_frame


func _build_func_map(
	tree: SceneTree,
	map_path: String,
	name: String
) -> FuncGodotMap:
	var func_map := FuncGodotMap.new()
	func_map.name = name
	func_map.map_settings = load(MAP_SETTINGS_PATH) as FuncGodotMapSettings
	func_map.local_map_file = map_path
	func_map.build_flags = 0
	tree.get_root().add_child(func_map)
	func_map.build()
	await tree.process_frame
	return func_map


func _collect_light_descriptors(root: Node) -> Dictionary:
	var descriptors: Dictionary = {}
	if root == null:
		return descriptors
	for candidate: Node in root.find_children("*", "", true, false):
		var light := candidate as VarkGameplayLight
		if light == null:
			continue
		var light_id: String = str(light.gameplay_light_id).strip_edges()
		if light_id.is_empty() or descriptors.has(light_id):
			continue
		descriptors[light_id] = VarkAnimatedLightmapBaker.descriptor_from_gameplay_light(
			light
		)
	return descriptors


func _first_func_godot_mesh(root: Node) -> MeshInstance3D:
	if root == null:
		return null
	for candidate: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if (
			mesh_instance != null
			and mesh_instance.mesh != null
			and mesh_instance.get_parent() != null
			and mesh_instance.get_parent().has_meta("func_godot_mesh_data")
		):
			return mesh_instance
	return null


func _mesh_has_any_uv2(mesh_instance: MeshInstance3D) -> bool:
	if mesh_instance == null or mesh_instance.mesh == null:
		return false
	for surface_index: int in mesh_instance.mesh.get_surface_count():
		var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface_index)
		var uv2_variant: Variant = arrays[Mesh.ARRAY_TEX_UV2]
		if uv2_variant is PackedVector2Array and not (uv2_variant as PackedVector2Array).is_empty():
			return true
	return false


func _two_adjacent_square_mesh(
	reverse_blocks: bool,
	geometry_delta: float = 0.0,
	material_id: String = "vark_surfaces/stone"
) -> MeshInstance3D:
	var left := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(1, 1, 0), Vector3(0, 1, 0),
	])
	var right := PackedVector3Array([
		Vector3(1, 0, 0), Vector3(2 + geometry_delta, 0, 0),
		Vector3(2 + geometry_delta, 1, 0), Vector3(1, 1, 0),
	])
	var blocks: Array[PackedVector3Array] = [left, right]
	if reverse_blocks:
		blocks.reverse()
	return _mesh_from_face_blocks(blocks, material_id)


func _duplicate_square_mesh() -> MeshInstance3D:
	var square := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(1, 1, 0), Vector3(0, 1, 0),
	])
	return _mesh_from_face_blocks([square, square], "vark_surfaces/stone")


func _triangle_mesh() -> MeshInstance3D:
	var vertices := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD,
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_name(0, "vark_surfaces/stone")
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	return instance


func _rectangle_mesh(width: float, height: float) -> MeshInstance3D:
	var rectangle := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(width, 0, 0),
		Vector3(width, height, 0), Vector3(0, height, 0),
	])
	return _mesh_from_face_blocks([rectangle], "vark_surfaces/stone")


func _mesh_from_face_blocks(
	blocks: Array[PackedVector3Array],
	material_id: String
) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for block: PackedVector3Array in blocks:
		var base: int = vertices.size()
		vertices.append_array(block)
		for _index: int in block.size():
			normals.append(Vector3.FORWARD)
		if block.size() == 4:
			indices.append_array(PackedInt32Array([
				base, base + 1, base + 2,
				base, base + 2, base + 3,
			]))
		elif block.size() == 3:
			indices.append_array(PackedInt32Array([base, base + 1, base + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_name(0, material_id)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	return instance


func _guarded_tiles_are_linearly_isolated(
	layout: VarkAnimatedLightmapLayout
) -> bool:
	if layout == null or layout.tiles.size() < 2:
		return false
	var first: Dictionary = layout.tiles[0]
	var second: Dictionary = layout.tiles[1]
	if int(first.get("page_index", -1)) != int(second.get("page_index", -2)):
		return false
	var image := Image.create_empty(
		layout.page_size,
		layout.page_size,
		false,
		Image.FORMAT_RGBAH
	)
	image.fill(Color.BLACK)
	_fill_rect(image, first, Color(4.0, 0.0, 0.0, 1.0))
	_fill_rect(image, second, Color(0.0, 0.0, 0.0, 1.0))
	var rect_pos: Vector2i = first.get("rect_position", Vector2i.ZERO)
	var useful: Vector2i = first.get("useful_size", Vector2i.ZERO)
	var guard: int = layout.guard_texels
	var y: float = float(rect_pos.y + guard) + maxf(float(useful.y - 1), 0.0) * 0.5
	var left_sample := Vector2(
		float(rect_pos.x + guard) - 0.25,
		y
	)
	var right_sample := Vector2(
		float(rect_pos.x + guard + useful.x - 1) + 0.25,
		y
	)
	var left: Color = _sample_bilinear_pixel_space(image, left_sample)
	var right: Color = _sample_bilinear_pixel_space(image, right_sample)
	return left.r > 3.5 and right.r > 3.5 and left.g < 0.01 and right.g < 0.01


func _fill_rect(image: Image, tile: Dictionary, color: Color) -> void:
	var position: Vector2i = tile.get("rect_position", Vector2i.ZERO)
	var size: Vector2i = tile.get("rect_size", Vector2i.ZERO)
	for y: int in range(position.y, position.y + size.y):
		for x: int in range(position.x, position.x + size.x):
			image.set_pixel(x, y, color)


func _sample_bilinear_pixel_space(image: Image, point: Vector2) -> Color:
	var x0: int = clampi(floori(point.x), 0, image.get_width() - 1)
	var y0: int = clampi(floori(point.y), 0, image.get_height() - 1)
	var x1: int = mini(x0 + 1, image.get_width() - 1)
	var y1: int = mini(y0 + 1, image.get_height() - 1)
	var fx: float = point.x - floorf(point.x)
	var fy: float = point.y - floorf(point.y)
	var top: Color = image.get_pixel(x0, y0).lerp(image.get_pixel(x1, y0), fx)
	var bottom: Color = image.get_pixel(x0, y1).lerp(image.get_pixel(x1, y1), fx)
	return top.lerp(bottom, fy)


func _contains_error(errors: PackedStringArray, fragment: String) -> bool:
	for error: String in errors:
		if error.contains(fragment):
			return true
	return false
