class_name VarkAcousticPortal
extends Node3D


@export var portal_id: StringName = &""
@export var space_a_id: StringName = &""
@export var space_b_id: StringName = &""
@export var door_id: StringName = &""
@export_range(0.0, 1.0, 0.01) var closed_transmission: float = 0.08
@export_range(0.0, 1.0, 0.01) var open_transmission: float = 1.0


func _ready() -> void:
	add_to_group(&"vark_acoustic_portal")


func connects_space(candidate_space_id: StringName) -> bool:
	return candidate_space_id == space_a_id or candidate_space_id == space_b_id


func get_other_space(candidate_space_id: StringName) -> StringName:
	if candidate_space_id == space_a_id:
		return space_b_id
	if candidate_space_id == space_b_id:
		return space_a_id
	return &""


func get_transmission(door: Node = null) -> float:
	if door_id.is_empty():
		return clampf(open_transmission, 0.0, 1.0)
	if door == null or not is_instance_valid(door) or not door.has_method("get_acoustic_openness"):
		return 0.0
	var openness: float = clampf(float(door.call("get_acoustic_openness")), 0.0, 1.0)
	return lerpf(
		clampf(closed_transmission, 0.0, 1.0),
		clampf(open_transmission, 0.0, 1.0),
		openness
	)


func has_valid_transmission() -> bool:
	return (
		is_finite(closed_transmission)
		and is_finite(open_transmission)
		and closed_transmission >= 0.0
		and closed_transmission <= 1.0
		and open_transmission >= 0.0
		and open_transmission <= 1.0
		and closed_transmission <= open_transmission
	)
