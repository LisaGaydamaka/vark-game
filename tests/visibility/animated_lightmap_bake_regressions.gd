extends RefCounted

const LabScene = preload(
	"res://scenes/animated_lightmap_lab/AnimatedLightmapLab.tscn"
)
const LAB_MAP_PATH: String = (
	"res://scenes/animated_lightmap_lab/animated_lightmap_lab.map"
)
const BAKE_PATH: String = (
	"res://scenes/animated_lightmap_lab/animated_surface_bake.tres"
)
const LIGHT_ID: String = VarkAnimatedLightmapLab.LIGHT_ID


func run(tree: SceneTree, assert_true: Callable) -> void:
	_test_deterministic_bvh_and_contact_fixture(assert_true)
	await _test_real_lab_bake_and_runtime(tree, assert_true)


func _test_deterministic_bvh_and_contact_fixture(
	assert_true: Callable
) -> void:
	var mesh: MeshInstance3D = _contact_fixture_mesh()
	var descriptors := {
		"light.contact": {
			"position": Vector3(-1.0, 1.0, 0.0),
			"color": Color(1.0, 0.7, 0.4, 1.0),
			"energy": 8.0,
			"range": 5.0,
		},
	}
	var builder := VarkAnimatedLightmapLayoutBuilder.new()
	var layout: VarkAnimatedLightmapLayout = builder.build_from_mesh_instances(
		[mesh],
		descriptors,
		{
			"texel_size_meters": 0.125,
			"page_size": 64,
			"guard_texels": 2,
			"max_light_slots": 8,
		}
	)
	var scene := VarkAnimatedLightmapBakeScene.new()
	var configured: bool = scene.configure(layout)
	var reordered: VarkAnimatedLightmapLayout = (
		layout.duplicate(true) as VarkAnimatedLightmapLayout
		if layout != null else null
	)
	if reordered != null:
		reordered.faces.reverse()
	var reordered_scene := VarkAnimatedLightmapBakeScene.new()
	var reordered_configured: bool = reordered_scene.configure(reordered)
	assert_true.call(
		layout != null
		and configured
		and reordered_configured
		and scene.get_triangle_count() == 4
		and scene.get_node_count() > 0
		and scene.get_fingerprint() == reordered_scene.get_fingerprint(),
		"8.4.1B deterministic static-render BVH is built from exact face triangles and is independent of face declaration order"
	)
	if layout == null or not configured:
		return

	var baker := VarkAnimatedLightmapSurfaceBaker.new()
	var bake: VarkAnimatedLightmapBakeData = baker.bake(
		LAB_MAP_PATH,
		layout,
		descriptors,
		4,
		null
	)
	var lit: float = (
		bake.get_contribution_at_world_point(
			layout, Vector3(-1.25, 0.01, 0.0), "light.contact", 0.05
		)
		if bake != null else 0.0
	)
	var shadow_a: float = (
		bake.get_contribution_at_world_point(
			layout, Vector3(0.25, 0.01, 0.0), "light.contact", 0.05
		)
		if bake != null else -1.0
	)
	var shadow_b: float = (
		bake.get_contribution_at_world_point(
			layout, Vector3(0.50, 0.01, 0.0), "light.contact", 0.05
		)
		if bake != null else -1.0
	)
	var side_lit: float = (
		bake.get_contribution_at_world_point(
			layout, Vector3(0.50, 0.01, 0.75), "light.contact", 0.05
		)
		if bake != null else 0.0
	)
	assert_true.call(
		bake != null
		and lit > 1.0
		and shadow_a <= 0.0001
		and shadow_b <= 0.0001
		and side_lit > 0.05,
		"8.4.1B 4x4 supersampled final texels preserve a finite flush wall/pillar contact shadow with no bright one-texel rim while a same-face point outside the blocker remains directly lit"
	)
	if bake == null:
		return
	var max_scalar: float = _max_bake_scalar(layout, bake)
	assert_true.call(
		max_scalar > 1.0,
		"8.4.1B real baked R16F irradiance remains HDR above 1.0 instead of clamping individual light contribution values"
	)


func _test_real_lab_bake_and_runtime(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	var lab := LabScene.instantiate() as VarkAnimatedLightmapLab
	lab.auto_apply_committed_bake = false
	tree.get_root().add_child(lab)
	await tree.process_frame
	await tree.physics_frame

	var descriptors: Dictionary = lab.get_expected_light_descriptors()
	var builder := VarkAnimatedLightmapLayoutBuilder.new()
	var layout: VarkAnimatedLightmapLayout = builder.build_from_root(
		lab.func_map, descriptors
	)
	assert_true.call(
		layout != null and builder.get_errors().is_empty(),
		"8.4.1B real Animated Lightmap Lab resolves the accepted A face/tile/page representation before baking"
	)
	if layout == null:
		lab.queue_free()
		await tree.process_frame
		return

	var bvh := VarkAnimatedLightmapBakeScene.new()
	var bvh_ok: bool = bvh.configure(layout)
	var reordered := layout.duplicate(true) as VarkAnimatedLightmapLayout
	reordered.faces.reverse()
	var reordered_bvh := VarkAnimatedLightmapBakeScene.new()
	var reordered_ok: bool = reordered_bvh.configure(reordered)
	assert_true.call(
		bvh_ok
		and reordered_ok
		and bvh.get_fingerprint() == reordered_bvh.get_fingerprint()
		and bvh.get_triangle_count() > 0,
		"8.4.1B repeated/canonical lab geometry produces the same Vark-owned static triangle/BVH truth"
	)

	var physics_baker := VarkAnimatedLightmapSurfaceBaker.new()
	var physics_bake: VarkAnimatedLightmapBakeData = physics_baker.bake(
		LAB_MAP_PATH,
		layout,
		descriptors,
		4,
		lab.get_world_3d().direct_space_state
	)
	var physics_diagnostics: Dictionary = physics_baker.get_diagnostics()
	var pure_baker := VarkAnimatedLightmapSurfaceBaker.new()
	var pure_bake: VarkAnimatedLightmapBakeData = pure_baker.bake(
		LAB_MAP_PATH,
		layout,
		descriptors,
		4,
		null
	)
	assert_true.call(
		physics_bake != null
		and pure_bake != null
		and physics_bake.content_equals(pure_bake)
		and int(physics_diagnostics.get("physics_checks", 0)) > 0
		and int(physics_diagnostics.get("bvh_triangles", 0)) > 0,
		"8.4.1B physics rays are diagnostic cross-checks only: removing PhysicsDirectSpaceState3D produces byte-identical authoritative BVH bake output"
	)
	if pure_bake == null:
		lab.queue_free()
		await tree.process_frame
		return

	var committed := (
		load(BAKE_PATH) as VarkAnimatedLightmapBakeData
		if ResourceLoader.exists(BAKE_PATH)
		else null
	)
	var committed_matches: bool = (
		committed != null and committed.content_equals(pure_bake)
	)
	if not committed_matches:
		print("ANIMATED_SURFACE_BAKE_RESOURCE_BEGIN")
		print(pure_bake.to_resource_text())
		print("ANIMATED_SURFACE_BAKE_RESOURCE_END")
	assert_true.call(
		committed_matches,
		"8.4.1B tracked per-surface lab bake exactly matches a fresh deterministic 4x4 supersampled BVH bake"
	)

	var candidate_pairs: int = 0
	for tile: Dictionary in layout.tiles:
		var candidates: PackedStringArray = tile.get(
			"candidate_light_ids", PackedStringArray()
		)
		candidate_pairs += candidates.size()
	var diagnostics: Dictionary = pure_baker.get_diagnostics()
	var contributing_pairs: int = int(
		diagnostics.get("contributing_tile_light_pairs", 0)
	)
	assert_true.call(
		contributing_pairs > 0
		and contributing_pairs < candidate_pairs
		and pure_bake.tile_contributing_light_ids.size() > 0
		and pure_bake.get_layer_keys().size()
			== int(diagnostics.get("resident_page_light_layers", -1)),
		"8.4.1B stores only face-tile/light relationships with at least one nonzero resolved texel; wholly unaffected candidate tiles own no baked contribution"
	)

	var lit_point := Vector3(0.25, 0.03, -4.8)
	var neighbor_floor := Vector3(0.25, 0.03, 0.5)
	var upper_floor := Vector3(0.25, 3.03, -3.0)
	var pillar_shadow := Vector3(2.3, 0.03, -3.3)
	var lit_value: float = pure_bake.get_contribution_at_world_point(
		layout, lit_point, LIGHT_ID
	)
	var neighbor_value: float = pure_bake.get_contribution_at_world_point(
		layout, neighbor_floor, LIGHT_ID
	)
	var upper_value: float = pure_bake.get_contribution_at_world_point(
		layout, upper_floor, LIGHT_ID
	)
	var pillar_value: float = pure_bake.get_contribution_at_world_point(
		layout, pillar_shadow, LIGHT_ID
	)
	assert_true.call(
		lit_value > 0.05
		and neighbor_value <= 0.0001
		and upper_value <= 0.0001
		and pillar_value <= 0.0001,
		"8.4.1B baked lab texels distinguish direct light from partition-, upper-floor- and flush-pillar-occluded static surfaces"
	)

	var renderer := VarkAnimatedLightmapStaticRenderer.new()
	lab.add_child(renderer)
	var renderer_ok: bool = renderer.configure(
		layout, pure_bake, LAB_MAP_PATH, descriptors
	)
	var contribution_texture_id: int = (
		renderer.get_contribution_texture_instance_id()
	)
	renderer.set_light_weight(LIGHT_ID, 1.0)
	var full: Color = renderer.sample_weighted_direct_at_world_point(lit_point)
	var after_full: Dictionary = renderer.get_debug_state()
	renderer.set_light_weight(LIGHT_ID, 0.5)
	var half: Color = renderer.sample_weighted_direct_at_world_point(lit_point)
	renderer.set_light_weight(LIGHT_ID, 0.0)
	var off: Color = renderer.sample_weighted_direct_at_world_point(lit_point)
	var after_off: Dictionary = renderer.get_debug_state()
	assert_true.call(
		renderer_ok
		and int(after_full.get("tile_mesh_count", 0)) > 0
		and int(after_full.get("tile_material_count", 0)) > 0
		and _max_rgb(full) > 0.05
		and _max_rgb(half) > 0.0
		and _max_rgb(half) < _max_rgb(full)
		and _max_rgb(off) <= 0.0001
		and renderer.get_contribution_texture_instance_id()
			== contribution_texture_id
		and int(after_off.get("contribution_texture_build_count", -1)) == 1
		and int(after_off.get("weight_texture_upload_count", 0)) >= 4,
		"8.4.1B runtime tile renderer binds exact face/tile/page contribution layers and applies full/partial/off weights through only the small GPU weight texture without rebuilding contribution atlases"
	)

	var changed_descriptors: Dictionary = descriptors.duplicate(true)
	var changed: Dictionary = (
		changed_descriptors.get(LIGHT_ID, {}) as Dictionary
	).duplicate(true)
	changed["energy"] = float(changed.get("energy", 0.0)) + 0.5
	changed_descriptors[LIGHT_ID] = changed
	var changed_renderer := VarkAnimatedLightmapStaticRenderer.new()
	lab.add_child(changed_renderer)
	var changed_ok: bool = changed_renderer.configure(
		layout, pure_bake, LAB_MAP_PATH, changed_descriptors
	)
	var stale_layout := layout.duplicate(true) as VarkAnimatedLightmapLayout
	stale_layout.representation_fingerprint = "stale-mapping"
	var stale_renderer := VarkAnimatedLightmapStaticRenderer.new()
	lab.add_child(stale_renderer)
	var stale_ok: bool = stale_renderer.configure(
		stale_layout, pure_bake, LAB_MAP_PATH, descriptors
	)
	var incomplete := pure_bake.duplicate(true) as VarkAnimatedLightmapBakeData
	var layer_keys: PackedStringArray = incomplete.get_layer_keys()
	if not layer_keys.is_empty():
		incomplete.layer_data_base64.erase(layer_keys[0])
	var incomplete_renderer := VarkAnimatedLightmapStaticRenderer.new()
	lab.add_child(incomplete_renderer)
	var incomplete_ok: bool = incomplete_renderer.configure(
		layout, incomplete, LAB_MAP_PATH, descriptors
	)
	assert_true.call(
		not changed_ok
		and _contains_error(
			changed_renderer.get_validation_errors(),
			"light bake fingerprint mismatch"
		)
		and not stale_ok
		and _contains_error(
			stale_renderer.get_validation_errors(),
			"surface layout fingerprint mismatch"
		)
		and not incomplete_ok
		and _contains_error(
			incomplete_renderer.get_validation_errors(),
			"missing/invalid contribution layer"
		),
		"8.4.1B runtime fails closed on changed light configuration, changed face/tile mapping, or missing sparse contribution storage"
	)

	var source_light: VarkGameplayLight = lab.get_source_light()
	var emitter: Light3D = (
		source_light.get_emitter() if source_light != null else null
	)
	var environment := lab.get_node("WorldEnvironment") as WorldEnvironment
	if source_light != null:
		source_light.set_enabled_state(false, false)
	for _frame: int in 3:
		await tree.physics_frame
		await tree.process_frame
	var exposure: Dictionary = lab.gameplay_exposure.sample_now()
	assert_true.call(
		emitter != null
		and emitter.light_cull_mask == 0
		and not emitter.shadow_enabled
		and environment != null
		and environment.environment != null
		and environment.environment.ambient_light_energy > 0.0
		and is_zero_approx(float(exposure.get("exposure", -1.0))),
		"8.4.1B static proof rendering requires no realtime direct-light/shadow receiver while intentional Environment ambient remains visual-only and outside semantic LIGHT exposure"
	)

	renderer.queue_free()
	changed_renderer.queue_free()
	stale_renderer.queue_free()
	incomplete_renderer.queue_free()
	lab.queue_free()
	await tree.process_frame


func _contact_fixture_mesh() -> MeshInstance3D:
	var floor := PackedVector3Array([
		Vector3(-2, 0, -2),
		Vector3(-2, 0, 2),
		Vector3(2, 0, 2),
		Vector3(2, 0, -2),
	])
	var blocker := PackedVector3Array([
		Vector3(0, 0, -0.35),
		Vector3(0, 2, -0.35),
		Vector3(0, 2, 0.35),
		Vector3(0, 0, 0.35),
	])
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for block: PackedVector3Array in [floor, blocker]:
		var base: int = vertices.size()
		vertices.append_array(block)
		var normal: Vector3 = (
			(block[1] - block[0]).cross(block[2] - block[0]).normalized()
		)
		for _index: int in block.size():
			normals.append(normal)
		indices.append_array(PackedInt32Array([
			base, base + 1, base + 2,
			base, base + 2, base + 3,
		]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	array_mesh.surface_set_name(0, "vark_surfaces/stone")
	var instance := MeshInstance3D.new()
	instance.mesh = array_mesh
	return instance


func _max_bake_scalar(
	layout: VarkAnimatedLightmapLayout,
	bake: VarkAnimatedLightmapBakeData
) -> float:
	var result: float = 0.0
	for layer_key: String in bake.get_layer_keys():
		var separator: int = layer_key.find("|")
		if separator <= 0:
			continue
		var page_index: int = int(layer_key.substr(0, separator))
		var light_id: String = layer_key.substr(separator + 1)
		var bytes: PackedByteArray = bake.get_layer_bytes(page_index, light_id)
		if bytes.is_empty():
			continue
		var image := Image.create_from_data(
			layout.page_size,
			layout.page_size,
			false,
			VarkAnimatedLightmapLayout.HDR_IMAGE_FORMAT,
			bytes
		)
		if image == null or image.is_empty():
			continue
		for y: int in image.get_height():
			for x: int in image.get_width():
				result = maxf(result, image.get_pixel(x, y).r)
	return result


func _contains_error(
	errors: PackedStringArray,
	fragment: String
) -> bool:
	for error: String in errors:
		if error.contains(fragment):
			return true
	return false


func _max_rgb(color: Color) -> float:
	return maxf(color.r, maxf(color.g, color.b))
