extends RefCounted

const LabScene = preload(
	"res://scenes/animated_lightmap_lab/AnimatedLightmapLab.tscn"
)


func run(tree: SceneTree, assert_true: Callable) -> void:
	await _test_dynamic_receiver_shadow_policy(tree, assert_true)


func _test_dynamic_receiver_shadow_policy(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	var lab := LabScene.instantiate() as VarkAnimatedLightmapLab
	tree.get_root().add_child(lab)
	await tree.process_frame
	await tree.physics_frame
	await tree.process_frame

	var binding: VarkAnimatedLightRuntimeBinding = lab.get_runtime_binding()
	var light: VarkGameplayLight = lab.get_source_light()
	var crate: VarkOrdinaryProp = lab.get_dynamic_crate()
	var emitter: Light3D = light.get_emitter() if light != null else null
	var prop_mesh := (
		crate.get_node_or_null("PropMesh") as MeshInstance3D
		if crate != null else null
	)
	var expected_bias: float = (
		VarkAnimatedLightRuntimeBinding.DYNAMIC_SPOT_SHADOW_BIAS
		if emitter is SpotLight3D
		else VarkAnimatedLightRuntimeBinding.DYNAMIC_OMNI_SHADOW_BIAS
	)
	var binding_debug: Dictionary = (
		binding.get_debug_state() if binding != null else {}
	)
	assert_true.call(
		binding != null
		and binding.is_configured()
		and emitter != null
		and emitter.shadow_enabled
		and is_equal_approx(emitter.shadow_bias, expected_bias)
		and is_equal_approx(
			emitter.shadow_normal_bias,
			VarkAnimatedLightRuntimeBinding.DYNAMIC_SHADOW_NORMAL_BIAS
		)
		and is_equal_approx(
			emitter.shadow_blur,
			VarkAnimatedLightRuntimeBinding.DYNAMIC_SHADOW_BLUR
		)
		and int(binding_debug.get("dynamic_shadow_profile_correct_count", 0))
			== int(binding_debug.get("dynamic_shadow_profile_expected_count", -1))
		and prop_mesh != null
		and prop_mesh.cast_shadow
			== GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		and _mesh_uses_flat_triangle_normals(prop_mesh.mesh),
		"8.4.2 runtime-bound animated lights use the dynamic-receiver shadow profile while the real ordinary crate remains a hard-edged realtime shadow caster/receiver rather than exposing its hidden triangulation through legacy ultra-low shadow bias"
	)

	if binding != null and light != null and emitter != null:
		binding.dispose()
		assert_true.call(
			is_equal_approx(
				emitter.shadow_bias,
				VarkGameplayLight.POSITIONAL_SHADOW_BIAS
			)
			and is_equal_approx(
				emitter.shadow_normal_bias,
				VarkGameplayLight.POSITIONAL_SHADOW_NORMAL_BIAS
			)
			and is_equal_approx(
				emitter.shadow_blur,
				VarkGameplayLight.POSITIONAL_SHADOW_BLUR
			),
			"8.4.2 dynamic shadow tuning belongs to the runtime binding and restores the gameplay light's pre-binding profile on disposal instead of globally retuning every legacy light"
		)

	lab.queue_free()
	await tree.process_frame
	await tree.process_frame


func _mesh_uses_flat_triangle_normals(mesh: Mesh) -> bool:
	if mesh == null or mesh.get_surface_count() <= 0:
		return false
	var triangle_count: int = 0
	var unique_normals: Dictionary = {}
	for surface_index: int in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var normals_variant: Variant = arrays[Mesh.ARRAY_NORMAL]
		var indices_variant: Variant = arrays[Mesh.ARRAY_INDEX]
		if not (normals_variant is PackedVector3Array):
			return false
		var normals: PackedVector3Array = normals_variant as PackedVector3Array
		if normals.is_empty():
			return false
		var indices := PackedInt32Array()
		if indices_variant is PackedInt32Array:
			indices = indices_variant as PackedInt32Array
		if indices.is_empty():
			if normals.size() % 3 != 0:
				return false
			for index: int in range(0, normals.size(), 3):
				if not _triangle_normals_match(
					normals[index], normals[index + 1], normals[index + 2]
				):
					return false
				triangle_count += 1
				unique_normals[_normal_key(normals[index])] = true
			continue
		if indices.size() % 3 != 0:
			return false
		for index: int in range(0, indices.size(), 3):
			var a: int = indices[index]
			var b: int = indices[index + 1]
			var c: int = indices[index + 2]
			if (
				a < 0 or b < 0 or c < 0
				or a >= normals.size()
				or b >= normals.size()
				or c >= normals.size()
			):
				return false
			if not _triangle_normals_match(normals[a], normals[b], normals[c]):
				return false
			triangle_count += 1
			unique_normals[_normal_key(normals[a])] = true
	return triangle_count >= 12 and unique_normals.size() >= 6


func _triangle_normals_match(a: Vector3, b: Vector3, c: Vector3) -> bool:
	var an: Vector3 = a.normalized()
	var bn: Vector3 = b.normalized()
	var cn: Vector3 = c.normalized()
	return an.dot(bn) > 0.9999 and an.dot(cn) > 0.9999


func _normal_key(normal: Vector3) -> String:
	var n: Vector3 = normal.normalized()
	return "%.3f,%.3f,%.3f" % [n.x, n.y, n.z]
