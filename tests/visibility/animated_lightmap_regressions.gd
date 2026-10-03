extends RefCounted

const LabScene = preload(
	"res://scenes/animated_lightmap_lab/AnimatedLightmapLab.tscn"
)
const LightSwitchScene = preload(
	"res://gameplay/visibility/LightSwitch.tscn"
)
const LIGHT_ID: String = VarkAnimatedLightmapLab.LIGHT_ID
const OBSOLETE_PATHS := [
	"res://gameplay/visibility/animated_lightmap_baker.gd",
	"res://gameplay/visibility/animated_lightmap_data.gd",
	"res://gameplay/visibility/animated_lightmap_surface.gd",
	"res://gameplay/visibility/animated_lightmap_surface.gdshader",
	"res://scenes/animated_lightmap_lab/animated_lightmap_data.tres",
	"res://tools/lighting/bake_animated_lightmap_lab.gd",
]


func run(tree: SceneTree, assert_true: Callable) -> void:
	_test_obsolete_representation_is_retired(assert_true)
	await _test_integrated_per_surface_lab_and_runtime_ownership(tree, assert_true)


func _test_obsolete_representation_is_retired(assert_true: Callable) -> void:
	var obsolete_absent: bool = true
	for path: String in OBSOLETE_PATHS:
		obsolete_absent = obsolete_absent and not FileAccess.file_exists(path)
	var lab_source: String = FileAccess.get_file_as_string(
		"res://scenes/animated_lightmap_lab/animated_lightmap_lab.gd"
	)
	var scene_source: String = FileAccess.get_file_as_string(
		"res://scenes/animated_lightmap_lab/AnimatedLightmapLab.tscn"
	)
	assert_true.call(
		obsolete_absent
		and not lab_source.contains("VarkAnimatedLightmapBaker")
		and not lab_source.contains("VarkAnimatedLightmapSurface")
		and not lab_source.contains("BAKE_TEXTURE_SIZE")
		and not scene_source.contains("animated_lightmap_surface.gd")
		and not scene_source.contains("AnimatedLightmapSurface")
		and not scene_source.contains("build_flags = 1"),
		"8.4.1C retires the rejected fixed-64x64/global-UV2/full-atlas-CPU-composite proof so the authoritative lab has only the A+B per-surface representation"
	)


func _test_integrated_per_surface_lab_and_runtime_ownership(
	tree: SceneTree,
	assert_true: Callable
) -> void:
	var lab := LabScene.instantiate() as VarkAnimatedLightmapLab
	tree.get_root().add_child(lab)
	await tree.process_frame
	await tree.physics_frame
	await tree.process_frame

	var renderer: VarkAnimatedLightmapStaticRenderer = lab.get_static_renderer()
	var layout: VarkAnimatedLightmapLayout = lab.get_surface_layout()
	var bake: VarkAnimatedLightmapBakeData = lab.get_surface_bake()
	var binding: VarkAnimatedLightRuntimeBinding = lab.get_runtime_binding()
	var source_light: VarkGameplayLight = lab.get_source_light()
	var crate: VarkOrdinaryProp = lab.get_dynamic_crate()
	var debug: Dictionary = lab.get_debug_state()
	var renderer_debug: Dictionary = debug.get("renderer", {})
	var binding_debug: Dictionary = debug.get("runtime_binding", {})
	var source_mesh_count: int = int(debug.get("source_static_mesh_count", 0))
	assert_true.call(
		layout != null
		and bake != null
		and renderer != null
		and renderer.is_applied()
		and binding != null
		and binding.is_configured()
		and source_light != null
		and crate != null
		and lab.get_validation_errors().is_empty()
		and lab.func_map.build_flags == 0
		and source_mesh_count > 0
		and int(debug.get("shadow_only_source_static_mesh_count", -1))
			== source_mesh_count
		and int(renderer_debug.get("page_mesh_count", 0)) == layout.pages.size()
		and int(renderer_debug.get("page_material_count", 0)) == layout.pages.size()
		and int(renderer_debug.get("page_mesh_count", 0)) < layout.tiles.size(),
		"8.4.1C accepted per-surface renderer remains authoritative for color while exact FuncGodot geometry is retained only as collision and realtime shadow-only occlusion for dynamic receivers"
	)
	if (
		layout == null
		or bake == null
		or renderer == null
		or source_light == null
		or binding == null
		or crate == null
	):
		lab.queue_free()
		await tree.process_frame
		return

	var probes: Dictionary = lab.get_probe_positions()
	var lit_point: Vector3 = probes.get("lit_floor", Vector3.ZERO)
	var neighbor_point: Vector3 = probes.get("blocked_neighbor", Vector3.ZERO)
	var upper_point: Vector3 = probes.get("blocked_upper", Vector3.ZERO)
	var pillar_point: Vector3 = probes.get("pillar_shadow", Vector3.ZERO)
	var lit_diag: Dictionary = lab.get_surface_diagnostics(lit_point)
	var lit_repeat: Dictionary = lab.get_surface_diagnostics(lit_point)
	var neighbor_diag: Dictionary = lab.get_surface_diagnostics(neighbor_point)
	var upper_diag: Dictionary = lab.get_surface_diagnostics(upper_point)
	var pillar_diag: Dictionary = lab.get_surface_diagnostics(pillar_point)
	var lit_owner: Dictionary = _find_light_ownership(lit_diag, LIGHT_ID)
	var neighbor_owner: Dictionary = _find_light_ownership(neighbor_diag, LIGHT_ID)
	var upper_owner: Dictionary = _find_light_ownership(upper_diag, LIGHT_ID)
	var pillar_owner: Dictionary = _find_light_ownership(pillar_diag, LIGHT_ID)
	assert_true.call(
		_surface_identity_is_complete(lit_diag)
		and _surface_identity_is_complete(neighbor_diag)
		and _surface_identity_is_complete(upper_diag)
		and _surface_identity_is_complete(pillar_diag)
		and _same_surface_identity(lit_diag, lit_repeat)
		and _ownership_is_complete(lit_owner)
		and _ownership_is_complete(neighbor_owner)
		and _ownership_is_complete(upper_owner)
		and _ownership_is_complete(pillar_owner)
		and float(lit_owner.get("bake_contribution", 0.0)) > 0.05
		and float(neighbor_owner.get("bake_contribution", -1.0)) <= 0.0001
		and float(upper_owner.get("bake_contribution", -1.0)) <= 0.0001
		and float(pillar_owner.get("bake_contribution", -1.0)) <= 0.0001,
		"8.4.1C visible-surface diagnostics retain stable face/tile/page ownership and the accepted lit versus opaque-separated/contact bake result"
	)

	var center_view: Dictionary = lab.get_center_view_surface_diagnostics()
	assert_true.call(
		_surface_identity_is_complete(center_view)
		and not str(center_view.get("collider", "")).is_empty(),
		"8.4.1C playable center-view diagnostics still resolve the visible static surface after runtime ownership integration"
	)

	var emitter: Light3D = source_light.get_emitter()
	var prop_mesh := crate.get_node_or_null("PropMesh") as MeshInstance3D
	assert_true.call(
		bool(binding_debug.get("configured", false))
		and binding.get_bound_light_ids() == PackedStringArray([LIGHT_ID])
		and int(binding_debug.get("static_page_mesh_count", 0)) == layout.pages.size()
		and int(binding_debug.get("static_page_layer_correct_count", 0)) == layout.pages.size()
		and bool(binding_debug.get("realtime_static_receiver_excluded", false))
		and emitter != null
		and emitter.shadow_enabled
		and (emitter.light_cull_mask & VarkAnimatedLightRuntimeBinding.STATIC_BAKED_VISUAL_LAYER) == 0
		and (emitter.light_cull_mask & 1) != 0
		and prop_mesh != null
		and (prop_mesh.layers & 1) != 0,
		"8.4.2 one binding keeps baked static pages off the realtime receiver mask while the same gameplay-light emitter remains available to ordinary dynamic meshes with realtime shadows"
	)

	# Stop automatic processing so fade/flicker assertions advance exactly the
	# authoritative owner clock requested by the regression.
	source_light.set_process(false)
	source_light.flicker_pattern = ""
	source_light.visual_transition_seconds = VarkAnimatedLightmapLab.FADE_SECONDS
	source_light.set_enabled_state(true, false)
	source_light.advance_runtime_visual_state(VarkAnimatedLightmapLab.FADE_SECONDS + 0.01)
	var contribution_texture_id: int = renderer.get_contribution_texture_instance_id()
	var before_fade: Dictionary = renderer.get_debug_state()
	var full: Color = renderer.sample_weighted_direct_at_world_point(lit_point)
	var semantic_point: Vector3 = lit_point + Vector3.UP * 0.8
	var full_semantic: float = source_light.sample_gameplay_contribution(
		semantic_point, lab.get_world_3d().direct_space_state
	)
	var full_energy: float = emitter.light_energy if emitter != null else 0.0

	source_light.set_enabled_state(false, false)
	var immediate_off_state: Dictionary = source_light.get_gameplay_debug_state()
	source_light.advance_runtime_visual_state(VarkAnimatedLightmapLab.FADE_SECONDS * 0.5)
	var half_weight: float = source_light.get_runtime_light_weight()
	var half_static: Color = renderer.sample_weighted_direct_at_world_point(lit_point)
	var half_semantic: float = source_light.sample_gameplay_contribution(
		semantic_point, lab.get_world_3d().direct_space_state
	)
	var half_energy: float = emitter.light_energy if emitter != null else 0.0
	source_light.advance_runtime_visual_state(VarkAnimatedLightmapLab.FADE_SECONDS)
	var off_static: Color = renderer.sample_weighted_direct_at_world_point(lit_point)
	var off_semantic: float = source_light.sample_gameplay_contribution(
		semantic_point, lab.get_world_3d().direct_space_state
	)
	var after_fade: Dictionary = renderer.get_debug_state()
	assert_true.call(
		_max_rgb(full) > 0.05
		and full_semantic > 0.0
		and full_energy > 0.0
		and not bool(immediate_off_state.get("fixture_lit", true))
		and half_weight > 0.0
		and half_weight < 1.0
		and is_equal_approx(renderer.get_light_weight(LIGHT_ID), source_light.get_runtime_light_weight())
		and _max_rgb(half_static) > 0.0
		and _max_rgb(half_static) < _max_rgb(full)
		and half_semantic >= 0.0
		and half_semantic < full_semantic
		and half_energy > 0.0
		and half_energy < full_energy
		and is_zero_approx(source_light.get_runtime_light_weight())
		and _max_rgb(off_static) <= 0.0001
		and off_semantic <= 0.0001
		and emitter != null
		and is_zero_approx(emitter.light_energy)
		and renderer.get_contribution_texture_instance_id() == contribution_texture_id
		and int(after_fade.get("contribution_texture_build_count", -1))
			== int(before_fade.get("contribution_texture_build_count", -2))
		and int(after_fade.get("weight_texture_upload_count", 0))
			> int(before_fade.get("weight_texture_upload_count", 0)),
		"8.4.2 VarkGameplayLight owns one fade output shared by fixture state, realtime emitter, baked static GPU weight and semantic LIGHT without rebuilding contribution textures"
	)

	# Real switch groups continue to mutate only the semantic light owner.
	source_light.visual_transition_seconds = 0.0
	var switch := LightSwitchScene.instantiate() as VarkLightSwitch
	switch.switch_id = "switch.phase8.runtime"
	switch.control_id = source_light.control_id
	lab.add_child(switch)
	await tree.process_frame
	switch.interact(null)
	var switch_on: bool = (
		source_light.is_enabled_state()
		and is_equal_approx(source_light.get_runtime_light_weight(), 1.0)
		and is_equal_approx(renderer.get_light_weight(LIGHT_ID), 1.0)
		and bool(source_light.get_gameplay_debug_state().get("fixture_lit", false))
	)
	switch.interact(null)
	var switch_off: bool = (
		not source_light.is_enabled_state()
		and is_zero_approx(source_light.get_runtime_light_weight())
		and is_zero_approx(renderer.get_light_weight(LIGHT_ID))
		and not bool(source_light.get_gameplay_debug_state().get("fixture_lit", true))
	)
	assert_true.call(
		switch_on and switch_off,
		"8.4.2 existing VarkLightSwitch control groups drive baked static light and lamp-glass ON/OFF through the same saved VarkGameplayLight owner"
	)

	# Classic lightstyle-like flicker is derived presentation, not persistence.
	source_light.set_enabled_state(true, false)
	source_light.flicker_pattern = "az"
	source_light.flicker_hz = 10.0
	source_light.restart_runtime_flicker()
	var flicker_dark: bool = (
		is_zero_approx(source_light.get_runtime_light_weight())
		and is_zero_approx(renderer.get_light_weight(LIGHT_ID))
		and is_zero_approx(emitter.light_energy)
	)
	source_light.advance_runtime_visual_state(0.11)
	var flicker_bright: bool = (
		source_light.get_runtime_light_weight() > 0.99
		and renderer.get_light_weight(LIGHT_ID) > 0.99
		and emitter.light_energy > 0.0
	)
	assert_true.call(
		flicker_dark and flicker_bright,
		"8.4.2 owner-local flicker modulates the same static/realtime runtime output without creating a second light-state owner"
	)
	source_light.flicker_pattern = ""
	source_light.restart_runtime_flicker()

	# Save truth remains the existing two semantic fields. Restore derives the
	# transient output and binding again rather than persisting a second weight.
	source_light.set_enabled_state(false, false)
	var saved: Dictionary = source_light.capture_semantic_state()
	source_light.set_enabled_state(true, false)
	var restore_ok: bool = source_light.apply_semantic_state(saved)
	restore_ok = restore_ok and source_light.reconcile_after_restore()
	assert_true.call(
		restore_ok
		and saved.size() == 2
		and not saved.has("runtime_weight")
		and not bool(saved.get("gameplay_enabled", true))
		and not source_light.is_enabled_state()
		and is_zero_approx(source_light.get_runtime_light_weight())
		and is_zero_approx(renderer.get_light_weight(LIGHT_ID))
		and is_zero_approx(emitter.light_energy)
		and not bool(source_light.get_gameplay_debug_state().get("fixture_lit", true)),
		"8.4.2 save/restore persists only the existing semantic gameplay-light truth and reconstructs static/realtime/fixture output without duplicated saved weight state"
	)

	# TARGET limitation: moving props participate in semantic/realtime occlusion
	# but do not mutate or rebake static-world contribution resources.
	source_light.set_enabled_state(true, false)
	var static_before_crate: Color = renderer.sample_weighted_direct_at_world_point(lit_point)
	var semantic_before_crate: float = source_light.sample_gameplay_contribution(
		semantic_point, lab.get_world_3d().direct_space_state
	)
	var texture_before_crate: int = renderer.get_contribution_texture_instance_id()
	var builds_before_crate: int = int(renderer.get_debug_state().get("contribution_texture_build_count", 0))
	var emitter_position: Vector3 = source_light.get_emitter_global_position()
	crate.freeze = true
	crate.global_position = emitter_position.lerp(semantic_point, 0.5)
	await tree.physics_frame
	await tree.process_frame
	var semantic_after_crate: float = source_light.sample_gameplay_contribution(
		semantic_point, lab.get_world_3d().direct_space_state
	)
	var static_after_crate: Color = renderer.sample_weighted_direct_at_world_point(lit_point)
	var builds_after_crate: int = int(renderer.get_debug_state().get("contribution_texture_build_count", 0))
	assert_true.call(
		semantic_before_crate > 0.0
		and semantic_after_crate <= 0.0001
		and _colors_close(static_before_crate, static_after_crate)
		and renderer.get_contribution_texture_instance_id() == texture_before_crate
		and builds_after_crate == builds_before_crate,
		"8.4.2 a moved ordinary crate can occlude authoritative gameplay LIGHT while the baked static wall/floor contribution remains immutable, explicitly protecting the TARGET moving-occluder limitation from accidental rebakes"
	)

	switch.queue_free()
	lab.queue_free()
	await tree.process_frame
	await tree.process_frame


func _surface_identity_is_complete(summary: Dictionary) -> bool:
	var rect_position: Vector2i = summary.get("rect_position", Vector2i(-1, -1))
	var rect_size: Vector2i = summary.get("rect_size", Vector2i.ZERO)
	return (
		bool(summary.get("resolved", false))
		and not str(summary.get("face_id", "")).is_empty()
		and not str(summary.get("tile_id", "")).is_empty()
		and int(summary.get("page_index", -1)) >= 0
		and rect_position.x >= 0
		and rect_position.y >= 0
		and rect_size.x > 0
		and rect_size.y > 0
	)


func _same_surface_identity(a: Dictionary, b: Dictionary) -> bool:
	return (
		str(a.get("face_id", "")) == str(b.get("face_id", ""))
		and str(a.get("tile_id", "")) == str(b.get("tile_id", ""))
		and int(a.get("page_index", -1)) == int(b.get("page_index", -2))
		and a.get("rect_position", Vector2i(-1, -1)) == b.get("rect_position", Vector2i(-2, -2))
		and a.get("rect_size", Vector2i.ZERO) == b.get("rect_size", Vector2i(-1, -1))
	)


func _find_light_ownership(summary: Dictionary, light_id: String) -> Dictionary:
	for ownership: Dictionary in summary.get("light_ownership", []):
		if str(ownership.get("light_id", "")) == light_id:
			return ownership
	return {}


func _ownership_is_complete(ownership: Dictionary) -> bool:
	return (
		not ownership.is_empty()
		and int(ownership.get("slot", -1)) >= 0
		and int(ownership.get("layer_index", -1)) >= 0
		and int(ownership.get("weight_index", -1)) >= 0
		and not str(ownership.get("contribution_handle", "")).is_empty()
	)


func _max_rgb(color: Color) -> float:
	return maxf(color.r, maxf(color.g, color.b))


func _colors_close(a: Color, b: Color, epsilon: float = 0.0001) -> bool:
	return (
		absf(a.r - b.r) <= epsilon
		and absf(a.g - b.g) <= epsilon
		and absf(a.b - b.b) <= epsilon
	)
