class_name PlayerInteraction
extends RefCounted


const INTERACTABLE_GROUP: StringName = &"vark_interactable"


var player: CollisionObject3D
var camera: Camera3D
var max_range: float
var input_enabled: bool = true
var world_interaction_available: bool = true
var current_target: Node = null


func _init(
	interactor: CollisionObject3D,
	view_camera: Camera3D,
	interaction_range: float
) -> void:
	player = interactor
	camera = view_camera
	max_range = maxf(interaction_range, 0.0)


func update(interact_pressed: bool) -> void:
	if not is_available():
		_set_target(null)
		return

	_set_target(_select_target())
	if not interact_pressed or current_target == null:
		return

	current_target.call("interact", player)
	# Interaction is allowed to change the target's own eligibility or the
	# player's central world-interaction availability. Refresh immediately so
	# one-shot and pickup interactions cannot leave stale highlight.
	_set_target(_select_target())


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not input_enabled:
		_set_target(null)


func set_world_interaction_available(available: bool) -> void:
	world_interaction_available = available
	if not world_interaction_available:
		_set_target(null)


func is_available() -> bool:
	return input_enabled and world_interaction_available


func get_semantic_state() -> Dictionary:
	var has_target: bool = current_target != null and is_instance_valid(current_target)
	return {
		"available": is_available(),
		"has_target": has_target,
		"target_name": str(current_target.name) if has_target else "",
	}


func _select_target() -> Node:
	if not is_available():
		return null
	if player == null or camera == null:
		return null
	if not is_instance_valid(player) or not is_instance_valid(camera):
		return null
	if player.get_world_3d() == null:
		return null

	var origin: Vector3 = camera.global_position
	var direction: Vector3 = -camera.global_transform.basis.z.normalized()
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction * max_range
	)
	query.exclude = [player.get_rid()]
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null

	var collider: Node = hit.get("collider") as Node
	var candidate: Node = _find_interactable(collider)
	if candidate == null:
		return null
	if (
		not candidate.has_method("can_interact")
		or not candidate.has_method("interact")
		or not candidate.has_method("set_interaction_highlighted")
	):
		return null
	if not bool(candidate.call("can_interact", player)):
		return null
	return candidate


func _find_interactable(collider: Node) -> Node:
	var candidate: Node = collider
	while candidate != null:
		if candidate.is_in_group(INTERACTABLE_GROUP):
			return candidate
		candidate = candidate.get_parent()
	return null


func _set_target(target: Node) -> void:
	if current_target == target:
		return

	if (
		current_target != null
		and is_instance_valid(current_target)
		and current_target.has_method("set_interaction_highlighted")
	):
		current_target.call("set_interaction_highlighted", false)

	current_target = target
	if (
		current_target != null
		and is_instance_valid(current_target)
		and current_target.has_method("set_interaction_highlighted")
	):
		current_target.call("set_interaction_highlighted", true)
