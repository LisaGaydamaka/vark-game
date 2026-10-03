extends RefCounted

const LabScene = preload(
	"res://scenes/animated_lightmap_lab/AnimatedLightmapLab.tscn"
)
const LIGHT_ID: String = VarkAnimatedLightmapLab.LIGHT_ID
const OBSOLETE_PATHS := PackedStringArray([
	"res://gameplay/visibility/animated_lightmap_baker.gd",
	"res://gameplay/visibility/animated_lightmap_data.gd",
	"res://gameplay/visibility/animated_lightmap_surface.gd",
	"res://gameplay/visibility/animated_lightmap_surface.gdshader",
	"res://scenes/animated_lightmap_lab/animated_lightmap_data.tres",
	"res://tools/lighting/bake_animated_lightmap_lab.gd",
])


func run(tree: SceneTree, assert_true: Callable) -> void:
	_test_obsolete_representation_is_retired(assert_true)
	await _test_integrated_per_surface_lab(tree, assert_true)


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


func _test_integrated_per_surface_lab(
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
	var debug: Dictionary = lab.get_debug_state()
	var renderer_debug: Dictionary = debug.get("renderer", {})
	var source_mesh_count: int = int(debug.get("source_static_mesh_count", 0))
	assert_true.call(
		layout != null
		and bake != null
		and renderer != null
		and renderer.is_applied()
		and lab.get_validation_errors().is_empty()
		and lab.func_map.build_flags == 0
		and source_mesh_count > 0
		and int(debug.get("hidden_source_static_mesh_count", -1))
			== source_mesh_count
		and int(renderer_debug.get("page_mesh_count", 0))
			== layout.pages.size()
		and int(renderer_debug.get("page_material_count", 0))
			== layout.pages.size()
		and int(renderer_debug.get("page_mesh_count", 0))
			< layout.tiles.size(),
		"8.4.1C integrated lab renders static architecture only through page-batched per-surface A+B geometry while preserving the original FuncGodot collision source hidden from rendering and disabling UV2 unwrap"
	)
	if layout == null or bake == null or renderer == null or not renderer.is_applied():
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
	var diagnostics_ok: bool = (
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
		and float(pillar_owner.get("bake_contribution", -1.0)) <= 0.0001
	)
	if not diagnostics_ok:
		print(
			"[8.4.1C_SURFACE_DIAGNOSTICS] ",
			{
				"lit": lit_diag,
				"neighbor": neighbor_diag,
				"upper": upper_diag,
				"pillar": pillar_diag,
			}
		)
	assert_true.call(
		diagnostics_ok,
		"8.4.1C visible-surface diagnostics resolve stable face/tile/page/rectangle plus animated-light slot/layer/weight handles and preserve lit versus partition/floor/pillar-occluded bake contributions"
	)

	var center_view: Dictionary = lab.get_center_view_surface_diagnostics()
	assert_true.call(
		_surface_identity_is_complete(center_view)
		and not str(center_view.get("collider", "")).is_empty(),
		"8.4.1C the playable lab can resolve the actually visible center-view world surface to the same face/tile/page diagnostics used by the bake/runtime path"
	)

	var source_light: VarkGameplayLight = lab.get_source_light()
	var emitter: Light3D = (
		source_light.get_emitter() if source_light != null else null
	)
	var environment := lab.get_node("WorldEnvironment") as WorldEnvironment
	var contribution_texture_id: int = renderer.get_contribution_texture_instance_id()
	var full: Color = renderer.sample_weighted_direct_at_world_point(lit_point)
	var before_weights: Dictionary = renderer.get_debug_state()
	lab.set_proof_light_weight_immediate(0.5)
	var half: Color = renderer.sample_weighted_direct_at_world_point(lit_point)
	lab.set_proof_light_weight_immediate(0.0)
	var off: Color = renderer.sample_weighted_direct_at_world_point(lit_point)
	var after_weights: Dictionary = renderer.get_debug_state()
	assert_true.call(
		full.r > full.g
		and full.g > full.b
		and _max_rgb(full) > 0.05
		and _max_rgb(half) > 0.0
		and _max_rgb(half) < _max_rgb(full)
		and _max_rgb(off) <= 0.0001
		and renderer.get_contribution_texture_instance_id()
			== contribution_texture_id
		and int(after_weights.get("contribution_texture_build_count", -1))
			== int(before_weights.get("contribution_texture_build_count", -2))
		and int(after_weights.get("weight_texture_upload_count", 0))
			> int(before_weights.get("weight_texture_upload_count", 0))
		and emitter != null
		and emitter.light_cull_mask == 0
		and not emitter.shadow_enabled
		and environment != null
		and environment.environment != null
		and environment.environment.ambient_light_energy > 0.0,
		"8.4.1C integrated lab produces the authored warm direct contribution and full/partial/off changes use only the GPU weight texture while intentional ambient remains and static architecture has no realtime positional shadow dependency"
	)

	var space_state: PhysicsDirectSpaceState3D = lab.get_world_3d().direct_space_state
	var support_query := PhysicsRayQueryParameters3D.create(
		lab.player.global_position + Vector3.UP * 0.05,
		lab.player.global_position + Vector3.DOWN * 0.30,
		1
	)
	var support_hit: Dictionary = space_state.intersect_ray(support_query)
	assert_true.call(
		not support_hit.is_empty(),
		"8.4.1C Development Launch player spawn remains supported by generated FuncGodot world collision after replacing only static rendering"
	)

	lab.queue_free()
	await tree.process_frame
	await tree.process_frame


func _surface_identity_is_complete(summary: Dictionary) -> bool:
	var rect_position: Vector2i = summary.get(
		"rect_position", Vector2i(-1, -1)
	)
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
		and a.get("rect_position", Vector2i(-1, -1))
			== b.get("rect_position", Vector2i(-2, -2))
		and a.get("rect_size", Vector2i.ZERO)
			== b.get("rect_size", Vector2i(-1, -1))
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
