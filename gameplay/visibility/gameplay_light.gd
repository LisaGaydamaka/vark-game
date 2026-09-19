class_name VarkGameplayLight
extends OmniLight3D


@export var gameplay_light_id: StringName = &"light"
@export_range(0.0, 4.0, 0.01) var gameplay_strength: float = 1.0
@export var gameplay_enabled: bool = true
@export_flags_3d_physics var occlusion_mask: int = 1


func _ready() -> void:
	add_to_group(&"vark_gameplay_light")


func sample_gameplay_exposure(
	sample_position: Vector3,
	space_state: PhysicsDirectSpaceState3D
) -> Dictionary:
	var distance: float = global_position.distance_to(sample_position)
	var range_meters: float = maxf(omni_range, 0.001)
	if (
		not gameplay_enabled
		or not visible
		or gameplay_strength <= 0.0
		or distance >= range_meters
	):
		return {
			"light_id": gameplay_light_id,
			"distance": distance,
			"distance_weight": 0.0,
			"occluded": false,
			"contribution": 0.0,
		}

	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		sample_position
	)
	query.collision_mask = occlusion_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hit: Dictionary = space_state.intersect_ray(query)
	var occluded: bool = not hit.is_empty()
	var distance_weight: float = clampf(
		1.0 - distance / range_meters,
		0.0,
		1.0
	)
	return {
		"light_id": gameplay_light_id,
		"distance": distance,
		"distance_weight": distance_weight,
		"occluded": occluded,
		"contribution": (
			0.0
			if occluded
			else gameplay_strength * distance_weight
		),
	}
