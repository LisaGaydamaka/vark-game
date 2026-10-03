class_name VarkAnimatedLightmapLab
extends Node3D

const MAP_SOURCE_PATH: String = (
	"res://scenes/animated_lightmap_lab/animated_lightmap_lab.map"
)
const BAKE_DATA_PATH: String = (
	"res://scenes/animated_lightmap_lab/animated_surface_bake.tres"
)
const LIGHT_ID: String = "light.phase8.anim_foundation"
const FADE_SECONDS: float = 0.65
const OrdinaryPropScene = preload("res://gameplay/props/OrdinaryProp.tscn")

@export var auto_apply_committed_bake: bool = true

@onready var player: CharacterBody3D = $Player
@onready var func_map: FuncGodotMap = $FuncGodotMap
@onready var gameplay_exposure: VarkGameplayExposure = $GameplayExposure
@onready var static_renderer: VarkAnimatedLightmapStaticRenderer = $AnimatedStaticRenderer
@onready var status_label: Label3D = $StatusLabel

var source_light: VarkGameplayLight = null
var expected_light_descriptors: Dictionary = {}
var surface_layout: VarkAnimatedLightmapLayout = null
var surface_bake: VarkAnimatedLightmapBakeData = null
var runtime_binding: VarkAnimatedLightRuntimeBinding = null
var dynamic_crate: VarkOrdinaryProp = null
var _validation_errors := PackedStringArray()


func _ready() -> void:
	func_map.local_map_file = MAP_SOURCE_PATH
	func_map.build()
	source_light = _find_source_light()
	if source_light == null:
		_fail("8.4.2 Animated Lightmap Lab failed to resolve the authored gameplay light.")
		return

	var emitter: Light3D = source_light.get_emitter()
	if emitter != null:
		# Preserve the accepted 8.4.1B proof contract while the lab is used as a
		# bake-only fixture: no realtime receiver or shadow path may contribute to
		# static architecture until the committed bake is actually bound.
		emitter.light_cull_mask = 0
		emitter.shadow_enabled = false

	expected_light_descriptors = {
		LIGHT_ID: _descriptor_from_gameplay_light(source_light),
	}
	var builder := VarkAnimatedLightmapLayoutBuilder.new()
	surface_layout = builder.build_from_root(
		func_map, expected_light_descriptors
	)
	if surface_layout == null:
		_validation_errors = builder.get_errors()
		_fail(
			"8.4.2 Animated Lightmap Lab could not build the per-surface layout: %s"
			% str(_validation_errors)
		)
		return

	if auto_apply_committed_bake:
		surface_bake = (
			load(BAKE_DATA_PATH) as VarkAnimatedLightmapBakeData
			if ResourceLoader.exists(BAKE_DATA_PATH)
			else null
		)
		if surface_bake == null:
			_validation_errors = PackedStringArray([
				"missing tracked per-surface bake: %s" % BAKE_DATA_PATH,
			])
			_fail(
				"8.4.2 Animated Lightmap Lab has no committed surface-light bake."
			)
			return
		if not static_renderer.configure(
			surface_layout,
			surface_bake,
			MAP_SOURCE_PATH,
			expected_light_descriptors
		):
			_validation_errors = static_renderer.get_validation_errors()
			_fail(
				"8.4.2 Animated Lightmap Lab refused stale/invalid bake: %s"
				% str(_validation_errors)
			)
			return

		# 8.4.2 changes only runtime ownership. The tracked bake source remains
		# byte-identical; the production gameplay-light owner supplies smooth
		# runtime output and a realtime shadowed representation for dynamic props.
		source_light.visual_transition_seconds = FADE_SECONDS
		source_light.shadow_enabled = true
		if emitter != null:
			emitter.light_cull_mask = 1
			emitter.shadow_enabled = true

		runtime_binding = VarkAnimatedLightRuntimeBinding.new()
		runtime_binding.name = "AnimatedLightRuntimeBinding"
		add_child(runtime_binding)
		if not runtime_binding.configure(
			static_renderer,
			surface_layout.light_ids,
			[source_light]
		):
			_validation_errors = runtime_binding.get_validation_errors()
			_fail(
				"8.4.2 Animated Lightmap Lab could not bind gameplay-light ownership: %s"
				% str(_validation_errors)
			)
			return
		_set_source_static_shadow_casters_enabled(true)
		_spawn_dynamic_crate_proof()

	_update_status()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_L:
		set_proof_light_enabled(not source_light.is_enabled_state())
	elif key.keycode == KEY_P:
		print(
			"[8.4.2_VISIBLE_SURFACE] ",
			JSON.stringify(get_center_view_surface_diagnostics())
		)


func set_proof_light_enabled(enabled: bool) -> void:
	if source_light == null:
		return
	source_light.set_enabled_state(enabled, true, "phase8.4.2.lab")
	_update_status()


func get_source_light() -> VarkGameplayLight:
	return source_light


func get_expected_light_descriptors() -> Dictionary:
	return expected_light_descriptors.duplicate(true)


func get_surface_layout() -> VarkAnimatedLightmapLayout:
	return surface_layout


func get_surface_bake() -> VarkAnimatedLightmapBakeData:
	return surface_bake


func get_static_renderer() -> VarkAnimatedLightmapStaticRenderer:
	return static_renderer


func get_runtime_binding() -> VarkAnimatedLightRuntimeBinding:
	return runtime_binding


func get_dynamic_crate() -> VarkOrdinaryProp:
	return dynamic_crate


func get_validation_errors() -> PackedStringArray:
	return _validation_errors.duplicate()


func get_probe_positions() -> Dictionary:
	if source_light == null:
		return {}
	return {
		"lit_floor": Vector3(0.25, 0.03, -4.8),
		"blocked_neighbor": Vector3(0.25, 0.03, 0.5),
		"blocked_upper": Vector3(0.25, 3.03, -3.0),
		"pillar_shadow": Vector3(2.3, 0.03, -3.3),
		"light_position": source_light.get_emitter_global_position(),
	}


func get_surface_diagnostics(
	world_point: Vector3,
	plane_tolerance: float = 0.08
) -> Dictionary:
	if surface_layout == null or surface_bake == null:
		return {"resolved": false, "error": "per-surface layout/bake is not available", "world_point": world_point}
	var face: Dictionary = VarkAnimatedLightmapLayoutBuilder.find_face_at_world_point(
		surface_layout, world_point, plane_tolerance
	)
	if face.is_empty():
		return {"resolved": false, "error": "no owning rendered face", "world_point": world_point}
	var continuous: Vector2 = VarkAnimatedLightmapLayoutBuilder.world_to_face_texel(
		face, world_point, surface_layout.texel_size_meters
	)
	var face_texel := Vector2i(floori(continuous.x), floori(continuous.y))
	var face_id: String = str(face.get("face_id", ""))
	var tile: Dictionary = _find_owning_tile(face_id, face_texel)
	if tile.is_empty():
		return {"resolved": false, "error": "owning face has no tile for the resolved texel", "world_point": world_point, "face_id": face_id, "face_texel": face_texel}
	var tile_id: String = str(tile.get("tile_id", ""))
	var candidate_ids: PackedStringArray = tile.get("candidate_light_ids", PackedStringArray())
	var contributing_ids: PackedStringArray = surface_bake.get_tile_light_ids(tile_id)
	var light_ownership: Array[Dictionary] = []
	for binding: Dictionary in tile.get("light_bindings", []):
		var light_id: String = str(binding.get("light_id", ""))
		var baked: float = surface_bake.get_contribution_at_face_texel(surface_layout, face_id, face_texel, light_id)
		var weight: float = static_renderer.get_light_weight(light_id) if static_renderer.is_applied() else 0.0
		light_ownership.append({
			"light_id": light_id,
			"slot": int(binding.get("slot", -1)),
			"layer_index": int(binding.get("layer_index", -1)),
			"weight_index": int(binding.get("weight_index", -1)),
			"contribution_handle": "%d|%s" % [int(tile.get("page_index", -1)), light_id],
			"resident_for_tile": contributing_ids.has(light_id),
			"bake_contribution": baked,
			"weight": weight,
			"weighted_contribution": baked * weight,
		})
	return {
		"resolved": true,
		"world_point": world_point,
		"face_id": face_id,
		"material_id": str(face.get("material_id", "")),
		"face_texel": face_texel,
		"tile_id": tile_id,
		"page_index": int(tile.get("page_index", -1)),
		"rect_position": tile.get("rect_position", Vector2i.ZERO),
		"rect_size": tile.get("rect_size", Vector2i.ZERO),
		"candidate_light_ids": candidate_ids.duplicate(),
		"contributing_light_ids": contributing_ids,
		"light_ownership": light_ownership,
		"weighted_direct": static_renderer.sample_weighted_direct_at_world_point(world_point, plane_tolerance) if static_renderer.is_applied() else Color.BLACK,
	}


func get_center_view_surface_diagnostics(max_distance: float = 24.0) -> Dictionary:
	if player == null or not is_inside_tree():
		return {"resolved": false, "error": "player is unavailable"}
	var camera := player.get_node_or_null("Head/Camera3D") as Camera3D
	if camera == null:
		return {"resolved": false, "error": "player camera is unavailable"}
	var from: Vector3 = camera.global_position
	var to: Vector3 = from + (-camera.global_basis.z * maxf(max_distance, 0.1))
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [player.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"resolved": false, "error": "center view hit no static world surface", "ray_from": from, "ray_to": to}
	var diagnostic: Dictionary = get_surface_diagnostics(hit.get("position", Vector3.ZERO), 0.02)
	diagnostic["ray_from"] = from
	diagnostic["ray_to"] = to
	diagnostic["hit_position"] = hit.get("position", Vector3.ZERO)
	diagnostic["hit_normal"] = hit.get("normal", Vector3.ZERO)
	var collider: Object = hit.get("collider", null)
	diagnostic["collider"] = str(collider.get_path()) if collider is Node else str(collider)
	return diagnostic


func get_debug_state() -> Dictionary:
	var emitter: Light3D = source_light.get_emitter() if source_light != null else null
	var source_meshes: Array[MeshInstance3D] = _get_source_static_meshes()
	var shadow_only_source_meshes: int = 0
	for mesh_instance: MeshInstance3D in source_meshes:
		if mesh_instance.visible and mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			shadow_only_source_meshes += 1
	var probes: Dictionary = get_probe_positions()
	return {
		"source_light_found": source_light != null,
		"surface_layout_found": surface_layout != null,
		"surface_bake_found": surface_bake != null,
		"source_static_mesh_count": source_meshes.size(),
		"shadow_only_source_static_mesh_count": shadow_only_source_meshes,
		"func_godot_build_flags": func_map.build_flags,
		"renderer": static_renderer.get_debug_state(),
		"runtime_binding": runtime_binding.get_debug_state() if runtime_binding != null else {},
		"source_light": source_light.get_gameplay_debug_state() if source_light != null else {},
		"dynamic_crate_present": dynamic_crate != null,
		"layout_report": surface_layout.get_scale_report() if surface_layout != null else {},
		"validation_errors": get_validation_errors(),
		"lit_floor_surface": get_surface_diagnostics(probes.get("lit_floor", Vector3.ZERO)) if probes.has("lit_floor") else {},
		"realtime_emitter_shadow_enabled": emitter.shadow_enabled if emitter != null else false,
		"realtime_emitter_cull_mask": emitter.light_cull_mask if emitter != null else -1,
	}


func _descriptor_from_gameplay_light(light: VarkGameplayLight) -> Dictionary:
	return {
		"position": light.get_emitter_global_position(),
		"color": light.light_color,
		"energy": maxf(light.get_configured_light_energy(), 0.0),
		"range": maxf(light.omni_range, 0.001),
	}


func _find_source_light() -> VarkGameplayLight:
	for candidate: Node in func_map.find_children("*", "", true, false):
		var light := candidate as VarkGameplayLight
		if light != null and str(light.gameplay_light_id) == LIGHT_ID:
			return light
	return null


func _get_source_static_meshes() -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for candidate: Node in func_map.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var owner: Node = mesh_instance.get_parent()
		if owner != null and owner.has_meta("func_godot_mesh_data"):
			meshes.append(mesh_instance)
	return meshes


func _set_source_static_shadow_casters_enabled(enabled: bool) -> void:
	for mesh_instance: MeshInstance3D in _get_source_static_meshes():
		mesh_instance.visible = enabled
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _spawn_dynamic_crate_proof() -> void:
	if dynamic_crate != null:
		return
	dynamic_crate = OrdinaryPropScene.instantiate() as VarkOrdinaryProp
	if dynamic_crate == null:
		return
	dynamic_crate.name = "DynamicCrateProof"
	dynamic_crate.persistent_id = "phase8.runtime.dynamic_crate"
	dynamic_crate.prop_id = "prop.phase8.runtime.dynamic_crate"
	dynamic_crate.position = Vector3(2.4, 0.32, -1.6)
	add_child(dynamic_crate)
	if source_light != null:
		# The production default remains world-geometry occlusion only. This lab
		# opts into the ordinary-prop layers solely to prove the documented
		# moving-occluder limitation without perturbing global stealth behavior.
		source_light.occlusion_mask |= (
			VarkOrdinaryProp.COLLISION_LAYER_ORDINARY_PROP
			| VarkOrdinaryProp.COLLISION_LAYER_PROP_IGNORING_PLAYER
		)


func _find_owning_tile(face_id: String, face_texel: Vector2i) -> Dictionary:
	if surface_layout == null:
		return {}
	for tile: Dictionary in surface_layout.tiles:
		if str(tile.get("face_id", "")) != face_id:
			continue
		var offset: Vector2i = tile.get("texel_offset", Vector2i.ZERO)
		var size: Vector2i = tile.get("useful_size", Vector2i.ZERO)
		if face_texel.x >= offset.x and face_texel.y >= offset.y and face_texel.x < offset.x + size.x and face_texel.y < offset.y + size.y:
			return tile
	return {}


func _short_id(value: String) -> String:
	return value if value.length() <= 12 else value.substr(0, 12)


func _fail(message: String) -> void:
	push_error(message)
	_update_status()


func _update_status() -> void:
	if status_label == null:
		return
	var weight: float = source_light.get_runtime_light_weight() if source_light != null else 0.0
	var diagnostic: Dictionary = {}
	var probes: Dictionary = get_probe_positions()
	if probes.has("lit_floor"):
		diagnostic = get_surface_diagnostics(probes.get("lit_floor", Vector3.ZERO))
	var ownership_text: String = "unresolved"
	if bool(diagnostic.get("resolved", false)):
		ownership_text = "face=%s tile=%s page=%d" % [
			_short_id(str(diagnostic.get("face_id", ""))),
			_short_id(str(diagnostic.get("tile_id", ""))),
			int(diagnostic.get("page_index", -1)),
		]
	status_label.text = (
		"8.4.2 GAMEPLAY-LIGHT RUNTIME OWNERSHIP\n"
		+ "L toggles the authoritative gameplay light; owner weight %.2f\n" % weight
		+ "Fixture glass, realtime crate light, baked static light, and LIGHT share that owner.\n"
		+ "Move/carry the crate between the lamp and a lit wall/floor.\n"
		+ "The crate is realtime-lit/occluding; baked static shadow intentionally does not move yet.\n"
		+ "P prints center-view face/tile/page/light ownership.\n"
		+ ownership_text
	)
