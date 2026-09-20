class_name VarkSurfaceProfile
extends Resource


@export var surface_id: StringName = &""
@export_range(0.01, 4.0, 0.01) var footstep_strength: float = 0.30


func is_valid_profile() -> bool:
	return (
		not surface_id.is_empty()
		and is_finite(footstep_strength)
		and footstep_strength > 0.0
	)


func get_footstep_sound_kind() -> StringName:
	if surface_id.is_empty():
		return &""
	return StringName("footstep.%s" % str(surface_id))


func get_semantic_summary() -> Dictionary:
	return {
		"surface_id": surface_id,
		"footstep_sound_kind": get_footstep_sound_kind(),
		"footstep_strength": footstep_strength,
	}
