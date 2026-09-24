@tool
class_name VarkCollectibleAsset
extends Resource


@export var asset_id: StringName = &""
@export var visual_model: Mesh
@export var collision_size: Vector3 = Vector3(0.10, 0.10, 0.10)
@export var collision_offset: Vector3 = Vector3.ZERO
@export var interaction_size: Vector3 = Vector3(0.24, 0.24, 0.24)
@export var interaction_offset: Vector3 = Vector3.ZERO
@export var label_offset: Vector3 = Vector3(0.0, 0.16, 0.0)
@export var base_color: Color = Color(0.78, 0.62, 0.18, 1.0)


func is_valid_asset() -> bool:
	return (
		not asset_id.is_empty()
		and visual_model != null
		and collision_size.x > 0.0
		and collision_size.y > 0.0
		and collision_size.z > 0.0
		and interaction_size.x >= collision_size.x
		and interaction_size.y >= collision_size.y
		and interaction_size.z >= collision_size.z
		and (
			visual_model.resource_path.ends_with(".obj")
			or visual_model.resource_path.ends_with(".glb")
			or visual_model.resource_path.ends_with(".gltf")
		)
	)


func get_summary() -> Dictionary:
	return {
		"asset_id": asset_id,
		"model_path": visual_model.resource_path if visual_model != null else "",
		"visual_size": visual_model.get_aabb().size if visual_model != null else Vector3.ZERO,
		"collision_size": collision_size,
		"collision_offset": collision_offset,
		"interaction_size": interaction_size,
		"interaction_offset": interaction_offset,
		"label_offset": label_offset,
	}
