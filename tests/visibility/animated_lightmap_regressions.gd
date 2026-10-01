extends RefCounted

const LabScene = preload(
	"res://scenes/animated_lightmap_lab/AnimatedLightmapLab.tscn"
)
const BAKE_DATA_PATH: String = (
	"res://scenes/animated_lightmap_lab/animated_lightmap_data.tres"
)

func run(tree: SceneTree, assert_true: Callable) -> void:
	var lab := LabScene.instantiate() as VarkAnimatedLightmapLab
	lab.auto_apply_committed_bake = false
	tree.get_root().add_child(lab)
	await tree.process_frame
	await tree.physics_frame
	var mesh: MeshInstance3D = lab.get_bake_mesh()
	var source_light: VarkGameplayLight = lab.get_source_light()
	var descriptors: Dictionary = lab.get_expected_light_descriptors()
	var fingerprint: String = (
		VarkAnimatedLightmapBaker.compute_geometry_fingerprint(mesh)
		if mesh != null else ""
	)
	assert_true.call(
		mesh != null
		and VarkAnimatedLightmapBaker.has_complete_uv2(mesh)
		and not fingerprint.is_empty()
		and source_light != null,
		"8.4.1 Animated Lightmap Lab builds authoritative FuncGodot geometry with complete UV2s and one authored bake-source gameplay-light identity"
	)
	if mesh == null or source_light == null:
		lab.queue_free()
		await tree.process_frame
		return

	var second := LabScene.instantiate() as VarkAnimatedLightmapLab
	second.auto_apply_committed_bake = false
	tree.get_root().add_child(second)
	await tree.process_frame
	await tree.physics_frame
	var second_mesh: MeshInstance3D = second.get_bake_mesh()
	var second_fingerprint: String = (
		VarkAnimatedLightmapBaker.compute_geometry_fingerprint(second_mesh)
		if second_mesh != null else ""
	)
	assert_true.call(
		second_mesh != null and fingerprint == second_fingerprint,
		"8.4.1 repeated FuncGodot builds produce the same UV2/geometry fingerprint"
	)
	# Do not leave the duplicate proof shell in the same physics world while
	# baking. Coincident duplicate colliders make ray-hit ownership ambiguous
	# even when the generated UV2/geometry data itself is deterministic.
	second.queue_free()
	await tree.process_frame
	await tree.physics_frame

	var context: Dictionary = lab.get_bake_context()
	var generated := VarkAnimatedLightmapBaker.bake_data(
		str(context.get("source_map_path", "")),
		mesh,
		descriptors,
		context.get("space_state", null) as PhysicsDirectSpaceState3D,
		context.get("texture_size", Vector2i.ZERO) as Vector2i
	)
	var committed := load(BAKE_DATA_PATH) as VarkAnimatedLightmapData
	var committed_matches: bool = (
		generated != null
		and committed != null
		and committed.content_equals(generated)
	)
	if generated != null and not committed_matches:
		print("ANIMATED_LIGHTMAP_RESOURCE_BEGIN")
		print(generated.to_resource_text())
		print("ANIMATED_LIGHTMAP_RESOURCE_END")
	assert_true.call(
		committed_matches,
		"8.4.1 tracked animated-lightmap asset exactly matches a fresh headless bake of authoritative source/UV2/light identity"
	)

	var probe: Dictionary = lab.get_probe_positions()
	var descriptor: Dictionary = descriptors.get(
		VarkAnimatedLightmapLab.LIGHT_ID, {}
	)
	var space_state: PhysicsDirectSpaceState3D = (
		lab.get_world_3d().direct_space_state
	)
	var light_position: Vector3 = probe.get("light_position", Vector3.ZERO)
	var lit_point: Vector3 = probe.get("lit_floor", Vector3.ZERO)
	var blocked_neighbor: Vector3 = probe.get(
		"blocked_neighbor", Vector3.ZERO
	)
	var blocked_upper: Vector3 = probe.get("blocked_upper", Vector3.ZERO)
	var shadow_point: Vector3 = probe.get("pillar_shadow", Vector3.ZERO)
	var lit: Color = VarkAnimatedLightmapBaker.sample_direct_light_at_point(
		lit_point, Vector3.UP, descriptor, space_state
	)
	var neighbor: Color = VarkAnimatedLightmapBaker.sample_direct_light_at_point(
		blocked_neighbor,
		(light_position - blocked_neighbor).normalized(),
		descriptor,
		space_state
	)
	var upper: Color = VarkAnimatedLightmapBaker.sample_direct_light_at_point(
		blocked_upper,
		(light_position - blocked_upper).normalized(),
		descriptor,
		space_state
	)
	var pillar_shadow: Color = (
		VarkAnimatedLightmapBaker.sample_direct_light_at_point(
			shadow_point, Vector3.UP, descriptor, space_state
		)
	)
	assert_true.call(
		_max_rgb(lit) > 0.05
		and _max_rgb(neighbor) <= 0.0001
		and _max_rgb(upper) <= 0.0001
		and _max_rgb(pillar_shadow) <= 0.0001,
		"8.4.1 offline direct-light sampler illuminates an unobstructed lower-room point while the real partition, upper floor and flush pillar physically occlude neighboring/upper/contact-shadow probes"
	)

	if generated != null:
		var surface := lab.animated_surface
		var configured: bool = surface.configure(
			mesh,
			generated,
			VarkAnimatedLightmapLab.MAP_SOURCE_PATH,
			descriptors
		)
		surface.set_light_weight(VarkAnimatedLightmapLab.LIGHT_ID, 1.0)
		var full_sum: int = _image_rgb_sum(surface.get_composite_image())
		surface.set_light_weight(VarkAnimatedLightmapLab.LIGHT_ID, 0.5)
		var half_sum: int = _image_rgb_sum(surface.get_composite_image())
		surface.set_light_weight(VarkAnimatedLightmapLab.LIGHT_ID, 0.0)
		var off_sum: int = _image_rgb_sum(surface.get_composite_image())
		assert_true.call(
			configured
			and full_sum > 0
			and half_sum > 0
			and half_sum < full_sum
			and off_sum == 0,
			"8.4.1 runtime material path independently weights the precomputed direct-light contribution through full, partial and fully-off states"
		)
		var stale := generated.duplicate(true) as VarkAnimatedLightmapData
		stale.geometry_fingerprint = "stale-geometry"
		var stale_surface := VarkAnimatedLightmapSurface.new()
		lab.add_child(stale_surface)
		var stale_applied: bool = stale_surface.configure(
			mesh,
			stale,
			VarkAnimatedLightmapLab.MAP_SOURCE_PATH,
			descriptors
		)
		assert_true.call(
			not stale_applied
			and not stale_surface.is_applied()
			and not stale_surface.get_validation_errors().is_empty(),
			"8.4.1 stale geometry/lightmap data fails closed instead of silently applying to changed authoritative geometry"
		)
		stale_surface.queue_free()

	var source_emitter: Light3D = source_light.get_emitter()
	var shadowed_realtime_count: int = 0
	for candidate: Node in lab.func_map.find_children("*", "Light3D", true, false):
		var light := candidate as Light3D
		if light != null and light.shadow_enabled:
			shadowed_realtime_count += 1
	assert_true.call(
		source_emitter != null
		and source_emitter.light_cull_mask == 0
		and not source_emitter.shadow_enabled
		and shadowed_realtime_count == 0,
		"8.4.1 lab static architecture requires no realtime positional shadow map: the authored gameplay-light emitter has no receivers/shadows and fixture self-fill is unshadowed/private"
	)

	var environment := lab.get_node("WorldEnvironment") as WorldEnvironment
	source_light.set_enabled_state(false, false)
	for _frame: int in 3:
		await tree.physics_frame
		await tree.process_frame
	var exposure: Dictionary = lab.gameplay_exposure.sample_now()
	assert_true.call(
		environment != null
		and environment.environment != null
		and environment.environment.ambient_light_energy > 0.0
		and is_zero_approx(float(exposure.get("exposure", -1.0))),
		"8.4.1 intentional Environment ambient remains visually present while disabled gameplay-light state leaves semantic LIGHT exposure at zero"
	)

	lab.queue_free()
	await tree.process_frame

func _max_rgb(color: Color) -> float:
	return maxf(color.r, maxf(color.g, color.b))

func _image_rgb_sum(image: Image) -> int:
	if image == null:
		return -1
	var data: PackedByteArray = image.get_data()
	var total: int = 0
	for byte_index: int in range(0, data.size(), 4):
		total += int(data[byte_index])
		total += int(data[byte_index + 1])
		total += int(data[byte_index + 2])
	return total
