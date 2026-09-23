@tool
class_name VarkCollectible
extends StaticBody3D


const KIND_KEY: StringName = &"key"
const KIND_MISSION_ITEM: StringName = &"mission_item"
const KIND_LOOT: StringName = &"loot"


@export var persistent_id: String = ""
@export var content_id: String = ""
@export var pickup_kind: StringName = KIND_LOOT
@export var loot_value: int = 0
@export var display_label: String = "Collectible"
@export var base_color: Color = Color(0.78, 0.62, 0.18, 1.0)

@onready var pickup_mesh: MeshInstance3D = $MeshInstance3D
@onready var pickup_label: Label3D = $Label3D

var _highlighted: bool = false
var _collected: bool = false
var _material: StandardMaterial3D = null


func _ready() -> void:
	add_to_group(&"vark_interactable")
	_material = StandardMaterial3D.new()
	pickup_mesh.material_override = _material
	pickup_label.text = display_label
	_refresh_visual()


func is_vark_persistent_entity() -> bool:
	return not persistent_id.strip_edges().is_empty()


func get_persistent_id() -> String:
	return persistent_id


func get_content_id() -> String:
	return content_id


func can_interact(interactor: Node) -> bool:
	return (
		not _collected
		and interactor != null
		and interactor.has_method("collect_authored_pickup")
	)


func interact(interactor: Node) -> void:
	if can_interact(interactor):
		interactor.call("collect_authored_pickup", self)


func set_interaction_highlighted(highlighted: bool) -> void:
	_highlighted = highlighted and not _collected
	_refresh_visual()


func is_interaction_highlighted() -> bool:
	return _highlighted


func is_collected() -> bool:
	return _collected


func get_collection_payload() -> Dictionary:
	return {
		"persistent_id": persistent_id.strip_edges(),
		"content_id": content_id.strip_edges(),
		"kind": pickup_kind,
		"loot_value": loot_value,
	}


func mark_collected_for_tombstone() -> bool:
	if _collected:
		return false
	_collected = true
	_highlighted = false
	collision_layer = 0
	collision_mask = 0
	if pickup_mesh != null:
		pickup_mesh.visible = false
	if pickup_label != null:
		pickup_label.visible = false
	_refresh_visual()
	queue_free()
	return true


func _refresh_visual() -> void:
	if _material == null:
		return
	_material.albedo_color = base_color
	_material.emission_enabled = false
	if _highlighted:
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.disable_receive_shadows = true
	else:
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_material.disable_receive_shadows = false
	if pickup_mesh != null:
		pickup_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
