class_name VarkConfiguredBreakable
extends StaticBody3D


const EFFECT_IMPACT: StringName = &"impact"
const BROKEN_EVENT_NAME: StringName = &"breakable.broken"


@export var persistent_id: String = ""
@export var content_id: String = "breakable"
@export var accepted_effect_id: String = "impact"
@export var break_threshold: float = 1.5
@export var visual_model_path: String = ""
@export var collision_size: Vector3 = Vector3(0.6, 0.6, 0.6)
@export var base_color: Color = Color(0.48, 0.32, 0.16, 1.0)

@onready var breakable_collision: CollisionShape3D = $CollisionShape3D
@onready var breakable_mesh: MeshInstance3D = $MeshInstance3D

var _broken: bool = false
var _world_session: Node = null
var _material: StandardMaterial3D = null
var _intact_collision_layer: int = 1
var _intact_collision_mask: int = 1


func _ready() -> void:
	_world_session = _find_world_session()
	_intact_collision_layer = collision_layer
	_intact_collision_mask = collision_mask
	if breakable_collision != null and breakable_collision.shape != null:
		breakable_collision.shape = breakable_collision.shape.duplicate()
	if not _configure_collision():
		push_error("VarkConfiguredBreakable requires a BoxShape3D collision shape.")
	_configure_visual()
	_refresh_state()


func is_vark_persistent_entity() -> bool:
	return not persistent_id.strip_edges().is_empty()


func get_persistent_id() -> String:
	return persistent_id


func get_content_id() -> String:
	return content_id


func is_broken() -> bool:
	return _broken


func get_effect_summary() -> Dictionary:
	return {
		"accepted_effect_id": accepted_effect_id,
		"break_threshold": break_threshold,
		"broken": _broken,
		"visual_model_path": visual_model_path,
		"collision_size": collision_size,
	}


func receive_prop_impact(contact_impulse: Vector3) -> bool:
	return apply_gameplay_effect(
		EFFECT_IMPACT,
		contact_impulse.length(),
		global_position
	)


func apply_gameplay_effect(
	effect_id: StringName,
	strength: float,
	source_position: Vector3 = Vector3.ZERO
) -> bool:
	if (
		_broken
		or str(effect_id) != accepted_effect_id
		or not is_finite(strength)
		or strength < maxf(break_threshold, 0.0)
	):
		return false
	_broken = true
	_refresh_state()
	_queue_broken_event(effect_id, strength, source_position)
	return true


func capture_semantic_state() -> Dictionary:
	return {"broken": _broken}


func apply_semantic_state(snapshot: Dictionary) -> bool:
	if (
		snapshot.size() != 1
		or not snapshot.has("broken")
		or typeof(snapshot["broken"]) != TYPE_BOOL
	):
		return false
	_broken = bool(snapshot["broken"])
	_refresh_state()
	return true


func reconcile_after_restore() -> bool:
	_refresh_state()
	return true


func after_restore() -> bool:
	return true


func _configure_collision() -> bool:
	if breakable_collision == null:
		return false
	var box := breakable_collision.shape as BoxShape3D
	if box == null:
		return false
	collision_size = Vector3(
		maxf(absf(collision_size.x), 0.05),
		maxf(absf(collision_size.y), 0.05),
		maxf(absf(collision_size.z), 0.05)
	)
	box.size = collision_size
	return true


func _configure_visual() -> void:
	if breakable_mesh == null:
		return
	var requested_path: String = visual_model_path.strip_edges()
	if not requested_path.is_empty() and ResourceLoader.exists(requested_path):
		var loaded: Resource = ResourceLoader.load(requested_path)
		if loaded is Mesh:
			breakable_mesh.mesh = loaded as Mesh
			visual_model_path = requested_path
	elif breakable_mesh.mesh is BoxMesh:
		var localized_box := breakable_mesh.mesh.duplicate() as BoxMesh
		if localized_box != null:
			localized_box.size = collision_size
			breakable_mesh.mesh = localized_box
	_material = StandardMaterial3D.new()
	_material.albedo_color = base_color
	_material.roughness = 0.78
	breakable_mesh.material_override = _material
	breakable_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _refresh_state() -> void:
	if _broken:
		collision_layer = 0
		collision_mask = 0
		if breakable_mesh != null:
			breakable_mesh.visible = false
		return
	collision_layer = _intact_collision_layer
	collision_mask = _intact_collision_mask
	if breakable_mesh != null:
		breakable_mesh.visible = true


func _queue_broken_event(
	effect_id: StringName,
	strength: float,
	source_position: Vector3
) -> void:
	if _world_session == null or not is_instance_valid(_world_session):
		return
	var source_session_id: int = int(_world_session.get("session_id"))
	_world_session.call(
		"queue_semantic_gameplay_event",
		source_session_id,
		BROKEN_EVENT_NAME,
		{
			"persistent_id": persistent_id.strip_edges(),
			"content_id": content_id.strip_edges(),
			"effect_id": effect_id,
			"strength": strength,
			"source_position": source_position,
		}
	)


func _find_world_session() -> Node:
	var cursor: Node = get_parent()
	while cursor != null:
		if cursor.has_method("queue_semantic_gameplay_event"):
			return cursor
		cursor = cursor.get_parent()
	return null
