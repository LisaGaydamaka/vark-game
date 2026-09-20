class_name VarkFootstepSurface
extends Area3D


@export var surface_profile: VarkSurfaceProfile


func _ready() -> void:
	add_to_group(&"vark_footstep_surface")
	if not has_valid_surface_profile():
		push_error(
			"VarkFootstepSurface '%s' requires a valid SurfaceProfile."
			% name
		)


func contains_body(body: PhysicsBody3D) -> bool:
	return body != null and overlaps_body(body)


func has_valid_surface_profile() -> bool:
	return (
		surface_profile != null
		and surface_profile.is_valid_profile()
	)


func get_surface_profile() -> VarkSurfaceProfile:
	return surface_profile


func get_surface_summary() -> Dictionary:
	if not has_valid_surface_profile():
		return {}
	return surface_profile.get_semantic_summary().duplicate(true)
