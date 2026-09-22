class_name PlayerInteraction
extends RefCounted


const INTERACTABLE_GROUP: StringName = &"vark_interactable"

const SELECTION_UNAVAILABLE: StringName = &"unavailable"
const SELECTION_INVALID_VIEW: StringName = &"invalid_view"
const SELECTION_NO_HIT: StringName = &"no_hit"
const SELECTION_BLOCKED: StringName = &"blocked"
const SELECTION_INVALID_CONTRACT: StringName = &"invalid_contract"
const SELECTION_INELIGIBLE: StringName = &"ineligible"
const SELECTION_TARGETED: StringName = &"targeted"


var player: CollisionObject3D
var camera: Camera3D
var max_range: float
var input_enabled: bool = true
var world_interaction_available: bool = true
var current_target: Node = null

var _last_selection_debug: Dictionary = {
	"selection_status": SELECTION_NO_HIT,
	"hit_name": "",
	"hit_class": "",
	"hit_distance": -1.0,
	"candidate_name": "",
	"max_range": 0.0,
	"areas_ignored": true,
}


func _init(
	interactor: CollisionObject3D,
	view_camera: Camera3D,
	interaction_range: float
) -> void:
	player = interactor
	camera = view_camera
	max_range = maxf(interaction_range, 0.0)
	_last_selection_debug["max_range"] = max_range


func update(interact_pressed: bool) -> void:
	if not is_available():
		_record_selection(SELECTION_UNAVAILABLE)
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
		_record_selection(SELECTION_UNAVAILABLE)
		_set_target(null)


func set_world_interaction_available(available: bool) -> void:
	world_interaction_available = available
	if not world_interaction_available:
		_record_selection(SELECTION_UNAVAILABLE)
		_set_target(null)


func is_available() -> bool:
	return input_enabled and world_interaction_available


func get_semantic_state() -> Dictionary:
	var has_target: bool = (
		current_target != null
		and is_instance_valid(current_target)
	)
	return {
		"available": is_available(),
		"has_target": has_target,
		"target_name": str(current_target.name) if has_target else "",
	}


func get_debug_summary() -> Dictionary:
	var summary: Dictionary = get_semantic_state()
	summary.merge(_last_selection_debug.duplicate(true), true)
	return summary


func _select_target() -> Node:
	if not is_available():
		_record_selection(SELECTION_UNAVAILABLE)
		return null
	if player == null or camera == null:
		_record_selection(SELECTION_INVALID_VIEW)
		return null
	if not is_instance_valid(player) or not is_instance_valid(camera):
		_record_selection(SELECTION_INVALID_VIEW)
		return null
	if player.get_world_3d() == null:
		_record_selection(SELECTION_INVALID_VIEW)
		return null

	var origin: Vector3 = camera.global_position
	var direction: Vector3 = -camera.global_transform.basis.z.normalized()
	if direction.length_squared() <= 0.000001:
		_record_selection(SELECTION_INVALID_VIEW)
		return null

	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction * max_range
	)
	query.exclude = [player.get_rid()]
	# Generic trigger/sensor Areas are not physical cover and must not steal the
	# center-view first hit from a real world object behind them. Current ordinary
	# interaction targets are physical bodies; a future Area-based interaction
	# would need an explicit targeting seam rather than making every mission sensor
	# participate in world selection.
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hit: Dictionary = (
		player.get_world_3d().direct_space_state.intersect_ray(query)
	)
	if hit.is_empty():
		_record_selection(SELECTION_NO_HIT)
		return null

	var collider: Node = hit.get("collider") as Node
	var hit_position: Vector3 = hit.get(
		"position",
		origin + direction * max_range
	)
	var hit_distance: float = origin.distance_to(hit_position)
	var candidate: Node = _find_interactable(collider)
	if candidate == null:
		_record_selection(
			SELECTION_BLOCKED,
			collider,
			null,
			hit_distance
		)
		return null

	if (
		not candidate.has_method("can_interact")
		or not candidate.has_method("interact")
		or not candidate.has_method("set_interaction_highlighted")
	):
		_record_selection(
			SELECTION_INVALID_CONTRACT,
			collider,
			candidate,
			hit_distance
		)
		return null

	var can_interact_result: Variant = candidate.call("can_interact", player)
	if typeof(can_interact_result) != TYPE_BOOL:
		_record_selection(
			SELECTION_INVALID_CONTRACT,
			collider,
			candidate,
			hit_distance
		)
		return null
	if not bool(can_interact_result):
		_record_selection(
			SELECTION_INELIGIBLE,
			collider,
			candidate,
			hit_distance
		)
		return null

	_record_selection(
		SELECTION_TARGETED,
		collider,
		candidate,
		hit_distance
	)
	return candidate


func _find_interactable(collider: Node) -> Node:
	var candidate: Node = collider
	while candidate != null:
		if candidate.is_in_group(INTERACTABLE_GROUP):
			return candidate
		candidate = candidate.get_parent()
	return null


func _record_selection(
	status: StringName,
	hit: Node = null,
	candidate: Node = null,
	hit_distance: float = -1.0
) -> void:
	_last_selection_debug = {
		"selection_status": status,
		"hit_name": _node_debug_name(hit),
		"hit_class": hit.get_class() if hit != null and is_instance_valid(hit) else "",
		"hit_distance": hit_distance,
		"candidate_name": _node_debug_name(candidate),
		"max_range": max_range,
		"areas_ignored": true,
	}


func _node_debug_name(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return ""
	return str(node.name)


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
