class_name VarkAnimatedLightmapLab
extends Node3D

const MAP_SOURCE_PATH: String = (
	"res://scenes/animated_lightmap_lab/animated_lightmap_lab.map"
)
const BAKE_DATA_PATH: String = (
	"res://scenes/animated_lightmap_lab/animated_lightmap_data.tres"
)
const LIGHT_ID: String = "light.phase8.anim_foundation"
const BAKE_TEXTURE_SIZE := Vector2i(64, 64)
const FADE_SECONDS: float = 0.65

@export var auto_apply_committed_bake: bool = true

@onready var player: CharacterBody3D = $Player
@onready var func_map: Node = $FuncGodotMap
@onready var gameplay_exposure: VarkGameplayExposure = $GameplayExposure
@onready var animated_surface: VarkAnimatedLightmapSurface = $AnimatedLightmapSurface
@onready var status_label: Label3D = $StatusLabel

var source_light: VarkGameplayLight = null
var bake_mesh: MeshInstance3D = null
var expected_light_descriptors: Dictionary = {}
var _target_weight: float = 1.0

func _ready() -> void:
	func_map.set("local_map_file", MAP_SOURCE_PATH)
	func_map.call("build")
	source_light = _find_source_light()
	bake_mesh = VarkAnimatedLightmapBaker.find_single_bake_mesh(func_map)
	if source_light == null or bake_mesh == null:
		push_error("8.4.1 Animated Lightmap Lab failed to resolve source light/UV2 mesh.")
		_update_status()
		return
	var emitter: Light3D = source_light.get_emitter()
	if emitter != null:
		emitter.light_cull_mask = 0
		emitter.shadow_enabled = false
	expected_light_descriptors = {
		LIGHT_ID: VarkAnimatedLightmapBaker.descriptor_from_gameplay_light(
			source_light
		),
	}
	if auto_apply_committed_bake:
		var data := load(BAKE_DATA_PATH) as VarkAnimatedLightmapData
		if (
			data == null
			or not animated_surface.configure(
				bake_mesh, data, MAP_SOURCE_PATH, expected_light_descriptors
			)
		):
			push_error(
				"8.4.1 Animated Lightmap Lab refused stale/invalid bake: %s"
				% str(animated_surface.get_validation_errors())
			)
		else:
			animated_surface.set_light_weight(LIGHT_ID, 1.0)
	_update_status()

func _process(delta: float) -> void:
	if not animated_surface.is_applied():
		return
	var current: float = animated_surface.get_light_weight(LIGHT_ID)
	var next_weight: float = move_toward(
		current, _target_weight, delta / FADE_SECONDS
	)
	if not is_equal_approx(current, next_weight):
		animated_surface.set_light_weight(LIGHT_ID, next_weight)
		_update_status()

func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_L:
		set_proof_light_enabled(_target_weight < 0.5)

func set_proof_light_enabled(enabled: bool) -> void:
	_target_weight = 1.0 if enabled else 0.0
	_update_status()

func set_proof_light_weight_immediate(weight: float) -> bool:
	_target_weight = clampf(weight, 0.0, 1.0)
	var changed: bool = animated_surface.set_light_weight(
		LIGHT_ID, _target_weight
	)
	_update_status()
	return changed

func get_bake_mesh() -> MeshInstance3D:
	return bake_mesh

func get_source_light() -> VarkGameplayLight:
	return source_light

func get_expected_light_descriptors() -> Dictionary:
	return expected_light_descriptors.duplicate(true)

func get_bake_context() -> Dictionary:
	return {
		"source_map_path": MAP_SOURCE_PATH,
		"mesh": bake_mesh,
		"light_descriptors": get_expected_light_descriptors(),
		"space_state": get_world_3d().direct_space_state,
		"texture_size": BAKE_TEXTURE_SIZE,
	}

func get_probe_positions() -> Dictionary:
	if source_light == null:
		return {}
	return {
		"lit_floor": Vector3(0.25, 0.03, -4.8),
		"blocked_neighbor": Vector3(0.25, 0.8, 2.6),
		"blocked_upper": Vector3(0.25, 4.1, -3.0),
		"pillar_shadow": Vector3(2.3, 0.03, -3.3),
		"light_position": source_light.get_emitter_global_position(),
	}

func get_debug_state() -> Dictionary:
	var emitter: Light3D = source_light.get_emitter() if source_light != null else null
	return {
		"source_light_found": source_light != null,
		"bake_mesh_found": bake_mesh != null,
		"uv2_complete": (
			VarkAnimatedLightmapBaker.has_complete_uv2(bake_mesh)
			if bake_mesh != null else false
		),
		"surface": animated_surface.get_debug_state(),
		"realtime_emitter_shadow_enabled": (
			emitter.shadow_enabled if emitter != null else true
		),
		"realtime_emitter_cull_mask": (
			emitter.light_cull_mask if emitter != null else -1
		),
		"target_weight": _target_weight,
	}

func _find_source_light() -> VarkGameplayLight:
	for candidate: Node in func_map.find_children("*", "", true, false):
		var light := candidate as VarkGameplayLight
		if light != null and str(light.gameplay_light_id) == LIGHT_ID:
			return light
	return null

func _update_status() -> void:
	if status_label == null:
		return
	var weight: float = (
		animated_surface.get_light_weight(LIGHT_ID)
		if animated_surface.is_applied()
		else 0.0
	)
	status_label.text = (
		"8.4.1 ANIMATED STATIC-LIGHT FOUNDATION\n"
		+ "L toggles/fades the PRECOMPUTED direct-light layer (%.2f)\n" % weight
		+ "Lower-left should be warm; lower-right + upper storey stay ambient-only.\n"
		+ "Pillar/floor contact shadow is baked: no realtime static shadow map.\n"
		+ "8.4.2 will bind this weight to gameplay-light state/dynamic objects."
	)
