extends Area3D


@export var surface_id: StringName = &"surface"
@export_range(0.01, 2.0, 0.01) var gameplay_sound_strength: float = 0.30


func _ready() -> void:
	add_to_group(&"vark_footstep_surface")


func contains_body(body: PhysicsBody3D) -> bool:
	return body != null and overlaps_body(body)


func get_surface_summary() -> Dictionary:
	return {
		"surface_id": surface_id,
		"gameplay_sound_strength": gameplay_sound_strength,
	}
