class_name VarkFootstepSurface
extends Area3D


const VARIANT_PROFILE_PATHS: Dictionary = {
	"stone": "res://gameplay/noise/profiles/stone.tres",
	"carpet": "res://gameplay/noise/profiles/carpet.tres",
	"tile": "res://gameplay/noise/profiles/tile.tres",
}


@export var surface_variant: String = "stone"
@export var surface_profile: VarkSurfaceProfile


func _ready() -> void:
	add_to_group(&"vark_footstep_surface")
	if surface_profile != null:
		if not has_valid_surface_profile():
			push_error(
				"VarkFootstepSurface '%s' requires a valid SurfaceProfile."
				% name
			)
	else:
		call_deferred("_validate_profile_after_authoring")


func _func_godot_apply_properties(_properties: Dictionary) -> void:
	surface_profile = null
	_apply_authored_variant_defaults()
	if not has_valid_surface_profile():
		push_error(
			"VarkFootstepSurface mapper properties did not resolve a valid SurfaceProfile."
		)


func _validate_profile_after_authoring() -> void:
	if not is_inside_tree():
		return
	_apply_authored_variant_defaults()
	if not has_valid_surface_profile():
		push_error(
			"VarkFootstepSurface '%s' requires a valid SurfaceProfile."
			% name
		)


func _apply_authored_variant_defaults() -> void:
	if surface_profile != null:
		return
	var profile_path: String = str(
		VARIANT_PROFILE_PATHS.get(surface_variant.strip_edges(), "")
	)
	if profile_path.is_empty() or not ResourceLoader.exists(profile_path):
		return
	var loaded: Resource = ResourceLoader.load(profile_path)
	if loaded is VarkSurfaceProfile:
		surface_profile = loaded as VarkSurfaceProfile


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
