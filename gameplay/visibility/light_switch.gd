class_name VarkLightSwitch
extends StaticBody3D


const USE_SOUND_KIND: StringName = &"switch.use"
const USED_EVENT_NAME: StringName = &"switch.used"


@export var switch_id: StringName = &"switch"
@export var control_id: StringName = &""
@export var base_model: Mesh
@export var base_model_path: String = ""
@export var lever_model: Mesh
@export var lever_model_path: String = ""
@export var base_color: Color = Color(0.24, 0.22, 0.18, 1.0)
@export var lever_color: Color = Color(0.50, 0.42, 0.25, 1.0)
@export var off_rotation_degrees: float = -25.0
@export var on_rotation_degrees: float = 25.0
@export var transition_seconds: float = 0.18
@export var gameplay_sound_strength: float = 0.25

@onready var base_mesh: MeshInstance3D = $BaseMesh
@onready var lever_pivot: Node3D = $LeverPivot
@onready var lever_mesh: MeshInstance3D = $LeverPivot/LeverMesh

var _world_session: Node = null
var _highlighted: bool = false
var _display_fraction: float = 0.0
var _base_material: StandardMaterial3D = null
var _lever_material: StandardMaterial3D = null


func _ready() -> void:
	add_to_group(&"vark_interactable")
	add_to_group(&"vark_light_switch")
	_world_session = _find_world_session()
	_configure_models()
	_display_fraction = 1.0 if _group_is_on() else 0.0
	_apply_pose()
	_refresh_visual()


func _process(delta: float) -> void:
	var target: float = 1.0 if _group_is_on() else 0.0
	var duration: float = maxf(transition_seconds, 0.001)
	_display_fraction = move_toward(_display_fraction, target, delta / duration)
	_apply_pose()


func get_content_id() -> String:
	return str(switch_id)


func can_interact(_interactor: Node) -> bool:
	return not control_id.is_empty() and not _controlled_lights().is_empty()


func interact(_interactor: Node) -> void:
	if not can_interact(_interactor):
		return
	var next_enabled: bool = not _group_is_on()
	var changed_count: int = 0
	for light: VarkGameplayLight in _controlled_lights():
		if light.set_enabled_state(next_enabled, true, switch_id):
			changed_count += 1
	if changed_count <= 0:
		return
	_queue_use_sound()
	_queue_used_event(next_enabled, changed_count)


func set_interaction_highlighted(highlighted: bool) -> void:
	_highlighted = highlighted
	_refresh_visual()


func is_interaction_highlighted() -> bool:
	return _highlighted


func get_debug_summary() -> Dictionary:
	return {
		"switch_id": switch_id,
		"control_id": control_id,
		"group_on": _group_is_on(),
		"controlled_light_count": _controlled_lights().size(),
		"display_fraction": _display_fraction,
	}


func _controlled_lights() -> Array[VarkGameplayLight]:
	var result: Array[VarkGameplayLight] = []
	if control_id.is_empty() or not is_inside_tree():
		return result
	for candidate: Node in get_tree().get_nodes_in_group(&"vark_gameplay_light"):
		var light := candidate as VarkGameplayLight
		if light == null or not is_instance_valid(light):
			continue
		if light.control_id == control_id:
			result.append(light)
	result.sort_custom(
		func(a: VarkGameplayLight, b: VarkGameplayLight) -> bool:
			return str(a.gameplay_light_id) < str(b.gameplay_light_id)
	)
	return result


func _group_is_on() -> bool:
	var lights: Array[VarkGameplayLight] = _controlled_lights()
	if lights.is_empty():
		return false
	for light: VarkGameplayLight in lights:
		if not light.is_enabled_state():
			return false
	return true


func _apply_pose() -> void:
	if lever_pivot == null:
		return
	lever_pivot.rotation_degrees.x = lerpf(
		off_rotation_degrees,
		on_rotation_degrees,
		clampf(_display_fraction, 0.0, 1.0)
	)


func _configure_models() -> void:
	base_model = _resolve_mesh(base_model_path, base_model)
	lever_model = _resolve_mesh(lever_model_path, lever_model)
	base_mesh.mesh = base_model
	lever_mesh.mesh = lever_model
	_base_material = StandardMaterial3D.new()
	_lever_material = StandardMaterial3D.new()
	base_mesh.material_override = _base_material
	lever_mesh.material_override = _lever_material


func _resolve_mesh(path: String, fallback: Mesh) -> Mesh:
	var normalized: String = path.strip_edges()
	if normalized.is_empty() or not ResourceLoader.exists(normalized):
		return fallback
	var loaded: Resource = ResourceLoader.load(normalized)
	return loaded as Mesh if loaded is Mesh else fallback


func _refresh_visual() -> void:
	_apply_material_state(_base_material, base_color)
	_apply_material_state(_lever_material, lever_color)


func _apply_material_state(
	material: StandardMaterial3D,
	color: Color
) -> void:
	if material == null:
		return
	material.albedo_color = color
	material.emission_enabled = false
	material.shading_mode = (
		BaseMaterial3D.SHADING_MODE_UNSHADED
		if _highlighted
		else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	)
	material.disable_receive_shadows = _highlighted


func _queue_use_sound() -> void:
	if _world_session == null:
		return
	_world_session.call(
		"queue_gameplay_sound",
		int(_world_session.get("session_id")),
		USE_SOUND_KIND,
		global_position,
		maxf(gameplay_sound_strength, 0.0)
	)


func _queue_used_event(enabled: bool, changed_count: int) -> void:
	if _world_session == null:
		return
	_world_session.call(
		"queue_semantic_gameplay_event",
		int(_world_session.get("session_id")),
		USED_EVENT_NAME,
		{
			"switch_id": switch_id,
			"control_id": control_id,
			"enabled": enabled,
			"changed_light_count": changed_count,
		}
	)


func _find_world_session() -> Node:
	var cursor: Node = get_parent()
	while cursor != null:
		if (
			cursor.has_method("queue_semantic_gameplay_event")
			and cursor.has_method("queue_gameplay_sound")
		):
			return cursor
		cursor = cursor.get_parent()
	return null
