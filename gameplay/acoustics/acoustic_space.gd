class_name VarkAcousticSpace
extends Node3D


@export var space_id: StringName = &""
@export var half_extent_x: float = 2.0
@export var half_extent_y: float = 2.0
@export var half_extent_z: float = 2.0


func _ready() -> void:
	add_to_group(&"vark_acoustic_space")


func contains_world_point(world_point: Vector3) -> bool:
	if not has_valid_extents():
		return false
	var local_point: Vector3 = to_local(world_point)
	const TOLERANCE: float = 0.001
	return (
		absf(local_point.x) <= half_extent_x + TOLERANCE
		and absf(local_point.y) <= half_extent_y + TOLERANCE
		and absf(local_point.z) <= half_extent_z + TOLERANCE
	)


func has_valid_extents() -> bool:
	return (
		is_finite(half_extent_x)
		and is_finite(half_extent_y)
		and is_finite(half_extent_z)
		and half_extent_x > 0.0
		and half_extent_y > 0.0
		and half_extent_z > 0.0
	)


func get_world_volume() -> float:
	if not has_valid_extents():
		return INF
	return 8.0 * half_extent_x * half_extent_y * half_extent_z
