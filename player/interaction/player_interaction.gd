class_name PlayerInteraction
extends RefCounted


const INTERACTABLE_GROUP: StringName = &"vark_interactable"
const INTERACTION_PROXY_GROUP: StringName = &"vark_interaction_proxy"
const INTERACTION_PROXY_LAYER: int = 1 << 4

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
	"interaction_proxy_areas_enabled": true,
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
	var end_position: Vector3 = origin + direction * max_range
	var space_state := player.get_world_3d().direct_space_state

	# Physical bodies remain the authoritative blocker/ordinary-target ray.
	var body_query := PhysicsRayQueryParameters3D.create(origin, end_position)
	body_query.exclude = [player.get_rid()]
	body_query.collide_with_areas = false
	body_query.collide_with_bodies = true
	var body_hit: Dictionary = space_state.intersect_ray(body_query)

	# Tiny collectibles may expose a larger, non-solid aim proxy. Only the
	# dedicated interaction-proxy layer participates here; arbitrary mission
	# sensor Areas remain invisible to world interaction.
	var proxy_query := PhysicsRayQueryParameters3D.create(origin, end_position)
	proxy_query.exclude = [player.get_rid()]
	proxy_query.collision_mask = INTERACTION_PROXY_LAYER
	proxy_query.collide_with_areas = true
	proxy_query.collide_with_bodies = false
	var proxy_hit: Dictionary = space_state.intersect_ray(proxy_query)

	var chosen_hit: Dictionary = body_hit
	var proxy_collider := proxy_hit.get("collider", null) as Node
	if (
		not proxy_hit.is_empty()
		and proxy_collider != null
		and proxy_collider.is_in_group(INTERACTION_PROXY_GROUP)
	):
		var proxy_position: Vector3 = proxy_hit.get("position", end_position)
		var proxy_distance: float = origin.distance_to(proxy_position)
		var body_distance: float = INF
		if not body_hit.is_empty():
			body_distance = origin.distance_to(
				body_hit.get("position", end_position)
			)
		# A real wall/container/door in front still wins. The aim proxy only
		# widens selection where it is the nearest interaction surface.
		if proxy_distance <= body_distance + 0.0001:
			chosen_hit = proxy_hit

	if chosen_hit.is_empty():
		_record_selection(SELECTION_NO_HIT)
		return null

	var collider: Node = chosen_hit.get("collider") as Node
	var hit_position: Vector3 = chosen_hit.get("position", end_position)
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
		"interaction_proxy_areas_enabled": true,
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
