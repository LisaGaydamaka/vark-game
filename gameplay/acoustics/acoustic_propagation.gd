class_name VarkAcousticPropagation
extends Node


const GAMEPLAY_SOUND_EVENT_NAME: StringName = &"gameplay.sound"
const DISTANCE_DECAY_PER_METER: float = 0.12
const MINIMUM_TRANSMISSION: float = 0.000001
const COST_EPSILON: float = 0.000001

var _world_root: Node = null
var _world_session: Node = null
var _spaces_by_id: Dictionary = {}
var _spaces: Array = []
var _portals: Array = []
var _listeners: Array = []
var _doors_by_id: Dictionary = {}
var _adjacency: Dictionary = {}
var _configured: bool = false
var _topology_enabled: bool = false
var _handler_registered: bool = false
var _errors: PackedStringArray = PackedStringArray()
var _last_sound_debug: Dictionary = {}

var _sorted_door_ids: Array[String] = []
var _cached_evaluation_valid: bool = false
var _cached_evaluation_origin: Vector3 = Vector3.ZERO
var _cached_evaluation_listener: Vector3 = Vector3.ZERO
var _cached_evaluation_strength: float = 0.0
var _cached_evaluation_door_signature: int = 0
var _cached_evaluation_result: Dictionary = {}
var _evaluation_count: int = 0
var _route_search_count: int = 0
var _same_space_fast_path_count: int = 0
var _cache_hit_count: int = 0
var _threshold_rejection_count: int = 0


func _ready() -> void:
	var world_root: Node = get_parent()
	var result: Dictionary = configure(world_root)
	if not bool(result.get("ok", false)):
		for error_message: String in _errors:
			push_error("Acoustic topology validation failed: %s" % error_message)
		return
	_world_session = _find_world_session()
	if _world_session == null:
		push_error("VarkAcousticPropagation requires a WorldSession ancestor.")
		return
	_handler_registered = bool(_world_session.call(
		"register_semantic_event_handler",
		GAMEPLAY_SOUND_EVENT_NAME,
		Callable(self, "handle_gameplay_sound")
	))
	if not _handler_registered:
		push_error("VarkAcousticPropagation could not register the gameplay.sound handler.")


func _exit_tree() -> void:
	if (
		_handler_registered
		and _world_session != null
		and is_instance_valid(_world_session)
		and _world_session.has_method("unregister_semantic_event_handler")
	):
		_world_session.call(
			"unregister_semantic_event_handler",
			GAMEPLAY_SOUND_EVENT_NAME,
			Callable(self, "handle_gameplay_sound")
		)
	_handler_registered = false
	_world_session = null
	clear()


func configure(world_root: Node) -> Dictionary:
	clear()
	_world_root = world_root
	if world_root == null:
		_errors.append("Acoustic propagation requires a world root.")
		return _configuration_result()

	var world_nodes: Array[Node] = [world_root]
	world_nodes.append_array(world_root.find_children("*", "", true, false))
	for node: Node in world_nodes:
		if node is VarkAcousticSpace:
			_spaces.append(node)
		elif node is VarkAcousticPortal:
			_portals.append(node)
		elif node is VarkAcousticListener:
			_listeners.append(node)
		if node.has_method("get_acoustic_openness") and _has_property(node, &"door_id"):
			var door_id: String = str(node.get("door_id"))
			if not door_id.is_empty():
				if _doors_by_id.has(door_id):
					_errors.append("Duplicate acoustic door_id '%s'." % door_id)
				else:
					_doors_by_id[door_id] = node

	_sorted_door_ids.clear()
	for door_id_value: Variant in _doors_by_id.keys():
		_sorted_door_ids.append(str(door_id_value))
	_sorted_door_ids.sort()
	_invalidate_evaluation_cache()

	if _spaces.is_empty() and _portals.is_empty() and _listeners.is_empty():
		_configured = true
		return _configuration_result()
	if _spaces.is_empty():
		_errors.append("Acoustic portals/listeners require at least one acoustic space.")

	for space_value: Variant in _spaces:
		var space: VarkAcousticSpace = space_value as VarkAcousticSpace
		if space == null:
			continue
		if space.space_id.is_empty():
			_errors.append("Acoustic space at %s has an empty space_id." % space.get_path())
			continue
		if not space.has_valid_extents():
			_errors.append("Acoustic space '%s' has invalid half extents." % space.space_id)
		if _spaces_by_id.has(space.space_id):
			_errors.append("Duplicate acoustic space_id '%s'." % space.space_id)
			continue
		_spaces_by_id[space.space_id] = space
		_adjacency[space.space_id] = []

	var portal_ids: Dictionary = {}
	for portal_index: int in range(_portals.size()):
		var portal: VarkAcousticPortal = _portals[portal_index] as VarkAcousticPortal
		if portal == null:
			continue
		if portal.portal_id.is_empty():
			_errors.append("Acoustic portal at %s has an empty portal_id." % portal.get_path())
		elif portal_ids.has(portal.portal_id):
			_errors.append("Duplicate acoustic portal_id '%s'." % portal.portal_id)
		else:
			portal_ids[portal.portal_id] = true
		if (
			portal.space_a_id.is_empty()
			or portal.space_b_id.is_empty()
			or portal.space_a_id == portal.space_b_id
		):
			_errors.append("Acoustic portal '%s' requires two distinct space IDs." % portal.portal_id)
			continue
		if not _spaces_by_id.has(portal.space_a_id):
			_errors.append("Acoustic portal '%s' references missing space '%s'." % [portal.portal_id, portal.space_a_id])
		if not _spaces_by_id.has(portal.space_b_id):
			_errors.append("Acoustic portal '%s' references missing space '%s'." % [portal.portal_id, portal.space_b_id])
		if not portal.has_valid_transmission():
			_errors.append("Acoustic portal '%s' has invalid transmission tuning." % portal.portal_id)
		if not portal.door_id.is_empty() and not _doors_by_id.has(portal.door_id):
			_errors.append("Acoustic portal '%s' references missing door_id '%s'." % [portal.portal_id, portal.door_id])
		if _spaces_by_id.has(portal.space_a_id):
			(_adjacency[portal.space_a_id] as Array).append(portal_index)
		if _spaces_by_id.has(portal.space_b_id):
			(_adjacency[portal.space_b_id] as Array).append(portal_index)

	var listener_ids: Dictionary = {}
	for listener_value: Variant in _listeners:
		var listener: VarkAcousticListener = listener_value as VarkAcousticListener
		if listener == null:
			continue
		if listener.listener_id.is_empty():
			_errors.append("Acoustic listener at %s has an empty listener_id." % listener.get_path())
		elif listener_ids.has(listener.listener_id):
			_errors.append("Duplicate acoustic listener_id '%s'." % listener.listener_id)
		else:
			listener_ids[listener.listener_id] = true
		if not is_finite(listener.hearing_threshold) or listener.hearing_threshold <= 0.0:
			_errors.append("Acoustic listener '%s' has an invalid hearing threshold." % listener.listener_id)

	_configured = _errors.is_empty()
	_topology_enabled = _configured and not _spaces.is_empty()
	return _configuration_result()


func clear() -> void:
	_world_root = null
	_spaces_by_id.clear()
	_spaces.clear()
	_portals.clear()
	_listeners.clear()
	_doors_by_id.clear()
	_sorted_door_ids.clear()
	_adjacency.clear()
	_invalidate_evaluation_cache()
	_configured = false
	_topology_enabled = false
	_errors = PackedStringArray()
	_last_sound_debug.clear()
	_evaluation_count = 0
	_route_search_count = 0
	_same_space_fast_path_count = 0
	_cache_hit_count = 0
	_threshold_rejection_count = 0


func is_configured() -> bool:
	return _configured


func has_topology() -> bool:
	return _topology_enabled


func get_configuration_errors() -> PackedStringArray:
	return _errors.duplicate()


func get_debug_summary() -> Dictionary:
	return {
		"configured": _configured,
		"topology_enabled": _topology_enabled,
		"handler_registered": _handler_registered,
		"space_count": _spaces.size(),
		"portal_count": _portals.size(),
		"listener_count": _listeners.size(),
		"door_count": _doors_by_id.size(),
		"evaluation_count": _evaluation_count,
		"route_search_count": _route_search_count,
		"same_space_fast_path_count": _same_space_fast_path_count,
		"cache_hit_count": _cache_hit_count,
		"threshold_rejection_count": _threshold_rejection_count,
		"errors": _errors.duplicate(),
	}


func get_portal_debug_states() -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	for portal_value: Variant in _portals:
		var portal := portal_value as VarkAcousticPortal
		if portal == null or not is_instance_valid(portal):
			continue
		var door: Node = null
		if not portal.door_id.is_empty():
			door = _doors_by_id.get(portal.door_id) as Node
		states.append(portal.get_debug_state(door))
	states.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("portal_id", &"")) < str(b.get("portal_id", &""))
	)
	return states


func get_portal_debug_state(portal_id: StringName) -> Dictionary:
	for state: Dictionary in get_portal_debug_states():
		if state.get("portal_id", &"") == portal_id:
			return state.duplicate(true)
	return {}


func get_last_sound_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = _last_sound_debug.duplicate(true)
	# Portal debug state is inspection data, not gameplay consequence data.
	# Materialize it only when a debugger actually asks for the snapshot instead
	# of allocating one dictionary per portal for every ordinary footstep.
	snapshot["portal_states"] = get_portal_debug_states()
	return snapshot


func get_debug_inspection() -> Dictionary:
	return {
		"summary": get_debug_summary(),
		"portals": get_portal_debug_states(),
		"last_sound": get_last_sound_debug_snapshot(),
	}


func handle_gameplay_sound(event: Dictionary) -> bool:
	if not _configured:
		return false
	if not _topology_enabled:
		return true
	var payload: Dictionary = event.get("payload", {})
	var origin: Vector3 = payload.get("origin", Vector3.ZERO)
	var strength: float = float(payload.get("strength", 0.0))
	var listener_results: Array[Dictionary] = []
	for listener_value: Variant in _listeners:
		if not (listener_value is VarkAcousticListener):
			continue
		var listener: VarkAcousticListener = listener_value as VarkAcousticListener
		if listener == null or not is_instance_valid(listener):
			continue
		var propagation: Dictionary = _evaluate_for_listener(
			origin,
			strength,
			listener
		)
		if not listener.receive_gameplay_sound(event, propagation):
			return false
		var perception: Dictionary = listener.get_last_perception()
		perception["path_distance"] = propagation.get(
			"path_distance",
			INF
		)
		perception["path_cost"] = propagation.get(
			"path_cost",
			INF
		)
		perception["listener_position"] = listener.global_position
		listener_results.append(perception)
	listener_results.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("listener_id", &"")) < str(
				b.get("listener_id", &"")
			)
	)
	_last_sound_debug = {
		"kind": payload.get("kind", &""),
		"origin": origin,
		"source_strength": strength,
		"listeners": listener_results,
	}
	return true


func evaluate(
	origin: Vector3,
	strength: float,
	listener_position: Vector3
) -> Dictionary:
	_evaluation_count += 1
	var empty_result := {
		"route_found": false,
		"propagated_strength": 0.0,
		"source_space_id": "",
		"listener_space_id": "",
		"portal_route": [],
		"path_distance": INF,
		"path_cost": INF,
	}
	if not _configured or not _topology_enabled:
		return empty_result
	if not is_finite(strength) or strength <= 0.0:
		return empty_result

	var door_signature: int = _current_door_signature()
	if (
		_cached_evaluation_valid
		and origin.is_equal_approx(_cached_evaluation_origin)
		and listener_position.is_equal_approx(_cached_evaluation_listener)
		and is_equal_approx(strength, _cached_evaluation_strength)
		and door_signature == _cached_evaluation_door_signature
	):
		_cache_hit_count += 1
		return _cached_evaluation_result.duplicate(true)

	var source_space: VarkAcousticSpace = _find_space(origin)
	var listener_space: VarkAcousticSpace = _find_space(listener_position)
	if source_space == null or listener_space == null:
		_cache_evaluation(
			origin,
			strength,
			listener_position,
			door_signature,
			empty_result
		)
		return empty_result

	# Same-space propagation has no portal choice. The previous implementation
	# still entered the full frontier search even for the player's own footstep
	# listener; direct distance is the exact same acoustic result.
	if source_space.space_id == listener_space.space_id:
		_same_space_fast_path_count += 1
		var direct_distance: float = origin.distance_to(listener_position)
		var direct_cost: float = DISTANCE_DECAY_PER_METER * direct_distance
		var direct_result := {
			"route_found": true,
			"propagated_strength": strength * exp(-direct_cost),
			"source_space_id": source_space.space_id,
			"listener_space_id": listener_space.space_id,
			"portal_route": [],
			"path_distance": direct_distance,
			"path_cost": direct_cost,
		}
		_cache_evaluation(
			origin,
			strength,
			listener_position,
			door_signature,
			direct_result
		)
		return direct_result

	_route_search_count += 1
	var route: Dictionary = _find_best_route(
		source_space.space_id,
		listener_space.space_id,
		origin,
		listener_position
	)
	if not bool(route.get("route_found", false)):
		empty_result["source_space_id"] = source_space.space_id
		empty_result["listener_space_id"] = listener_space.space_id
		_cache_evaluation(
			origin,
			strength,
			listener_position,
			door_signature,
			empty_result
		)
		return empty_result

	var path_cost: float = float(route["path_cost"])
	var result := {
		"route_found": true,
		"propagated_strength": strength * exp(-path_cost),
		"source_space_id": source_space.space_id,
		"listener_space_id": listener_space.space_id,
		"portal_route": (route["portal_route"] as Array).duplicate(true),
		"path_distance": float(route["path_distance"]),
		"path_cost": path_cost,
	}
	_cache_evaluation(
		origin,
		strength,
		listener_position,
		door_signature,
		result
	)
	return result


func _evaluate_for_listener(
	origin: Vector3,
	strength: float,
	listener: VarkAcousticListener
) -> Dictionary:
	if listener == null or not is_instance_valid(listener):
		return {
			"route_found": false,
			"propagated_strength": 0.0,
			"source_space_id": "",
			"listener_space_id": "",
			"portal_route": [],
			"path_distance": INF,
			"path_cost": INF,
		}

	# Transmission cannot amplify and an authored path cannot be shorter than
	# straight-line distance. If even that optimistic bound is under this
	# listener's hearing threshold, a graph expansion cannot change gameplay.
	var listener_position: Vector3 = listener.global_position
	var direct_distance: float = origin.distance_to(listener_position)
	var maximum_possible_strength: float = (
		strength * exp(-DISTANCE_DECAY_PER_METER * direct_distance)
	)
	if maximum_possible_strength < maxf(listener.hearing_threshold, 0.000001):
		_threshold_rejection_count += 1
		var source_space: VarkAcousticSpace = _find_space(origin)
		var listener_space: VarkAcousticSpace = _find_space(listener_position)
		return {
			"route_found": false,
			"propagated_strength": 0.0,
			"source_space_id": (
				source_space.space_id if source_space != null else ""
			),
			"listener_space_id": (
				listener_space.space_id if listener_space != null else ""
			),
			"portal_route": [],
			"path_distance": direct_distance,
			"path_cost": INF,
		}
	return evaluate(origin, strength, listener_position)


func _current_door_signature() -> int:
	var signature: int = 17
	for door_id: String in _sorted_door_ids:
		var door := _doors_by_id.get(door_id) as Node
		var openness: float = 0.0
		if (
			door != null
			and is_instance_valid(door)
			and door.has_method("get_acoustic_openness")
		):
			openness = clampf(
				float(door.call("get_acoustic_openness")),
				0.0,
				1.0
			)
		var quantized: int = roundi(openness * 1000000.0)
		signature = int((signature * 16777619) ^ quantized)
	return signature


func _cache_evaluation(
	origin: Vector3,
	strength: float,
	listener_position: Vector3,
	door_signature: int,
	result: Dictionary
) -> void:
	_cached_evaluation_valid = true
	_cached_evaluation_origin = origin
	_cached_evaluation_listener = listener_position
	_cached_evaluation_strength = strength
	_cached_evaluation_door_signature = door_signature
	_cached_evaluation_result = result.duplicate(true)


func _invalidate_evaluation_cache() -> void:
	_cached_evaluation_valid = false
	_cached_evaluation_result.clear()


func _find_best_route(
	source_space_id: String,
	listener_space_id: String,
	origin: Vector3,
	listener_position: Vector3
) -> Dictionary:
	var source_key: String = _state_key(source_space_id, -1)
	var frontier: Array[Dictionary] = [{
		"key": source_key,
		"space_id": source_space_id,
		"entry_portal_index": -1,
		"cost": 0.0,
	}]
	var best_costs: Dictionary = {source_key: 0.0}
	var predecessors: Dictionary = {}
	var best_final_cost: float = INF
	var best_final_key: String = ""

	while not frontier.is_empty():
		var best_frontier_index: int = 0
		for candidate_index: int in range(1, frontier.size()):
			if float(frontier[candidate_index]["cost"]) < float(frontier[best_frontier_index]["cost"]):
				best_frontier_index = candidate_index
		var state: Dictionary = frontier[best_frontier_index]
		frontier.remove_at(best_frontier_index)
		var state_key: String = str(state["key"])
		var state_cost: float = float(state["cost"])
		if state_cost > float(best_costs.get(state_key, INF)) + COST_EPSILON:
			continue
		if state_cost >= best_final_cost:
			continue

		var state_space_id: String = str(state["space_id"])
		var entry_portal_index: int = int(state["entry_portal_index"])
		var current_position: Vector3 = origin
		if entry_portal_index >= 0:
			current_position = (_portals[entry_portal_index] as VarkAcousticPortal).global_position

		if state_space_id == listener_space_id:
			var final_cost: float = (
				state_cost
				+ DISTANCE_DECAY_PER_METER * current_position.distance_to(listener_position)
			)
			if final_cost < best_final_cost:
				best_final_cost = final_cost
				best_final_key = state_key

		var adjacent_portals: Array = _adjacency.get(state_space_id, [])
		for portal_index_value: Variant in adjacent_portals:
			var portal_index: int = int(portal_index_value)
			var portal: VarkAcousticPortal = _portals[portal_index] as VarkAcousticPortal
			if portal == null:
				continue
			var next_space_id: String = portal.get_other_space(state_space_id)
			if next_space_id.is_empty():
				continue
			var transmission: float = _get_portal_transmission(portal)
			if transmission <= MINIMUM_TRANSMISSION:
				continue
			var segment_distance: float = current_position.distance_to(portal.global_position)
			var portal_cost: float = -log(maxf(transmission, MINIMUM_TRANSMISSION))
			var next_cost: float = (
				state_cost
				+ DISTANCE_DECAY_PER_METER * segment_distance
				+ portal_cost
			)
			var next_key: String = _state_key(next_space_id, portal_index)
			if next_cost + COST_EPSILON >= float(best_costs.get(next_key, INF)):
				continue
			best_costs[next_key] = next_cost
			predecessors[next_key] = {
				"previous_key": state_key,
				"portal_index": portal_index,
			}
			frontier.append({
				"key": next_key,
				"space_id": next_space_id,
				"entry_portal_index": portal_index,
				"cost": next_cost,
			})

	if not is_finite(best_final_cost):
		return {
			"route_found": false,
			"portal_route": [],
			"path_distance": INF,
			"path_cost": INF,
		}

	var route_indices: Array[int] = []
	var cursor_key: String = best_final_key
	while predecessors.has(cursor_key):
		var step: Dictionary = predecessors[cursor_key]
		route_indices.push_front(int(step["portal_index"]))
		cursor_key = str(step["previous_key"])

	var portal_route: Array[StringName] = []
	var path_distance: float = 0.0
	var route_position: Vector3 = origin
	for portal_index: int in route_indices:
		var portal: VarkAcousticPortal = _portals[portal_index] as VarkAcousticPortal
		path_distance += route_position.distance_to(portal.global_position)
		route_position = portal.global_position
		portal_route.append(StringName(portal.portal_id))
	path_distance += route_position.distance_to(listener_position)
	return {
		"route_found": true,
		"portal_route": portal_route,
		"path_distance": path_distance,
		"path_cost": best_final_cost,
	}


func _find_space(world_point: Vector3) -> VarkAcousticSpace:
	var best_space: VarkAcousticSpace = null
	var best_volume: float = INF
	for space_value: Variant in _spaces:
		var space: VarkAcousticSpace = space_value as VarkAcousticSpace
		if space == null or not is_instance_valid(space):
			continue
		if not space.contains_world_point(world_point):
			continue
		var volume: float = space.get_world_volume()
		if volume < best_volume:
			best_volume = volume
			best_space = space
	return best_space


func _get_portal_transmission(portal: VarkAcousticPortal) -> float:
	var door: Node = null
	if not portal.door_id.is_empty():
		door = _doors_by_id.get(portal.door_id) as Node
	return portal.get_transmission(door)


func _state_key(space_id: String, entry_portal_index: int) -> String:
	return "%s|%d" % [space_id, entry_portal_index]


func _has_property(node: Object, property_name: StringName) -> bool:
	for property: Dictionary in node.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false


func _find_world_session() -> Node:
	var cursor: Node = get_parent()
	while cursor != null:
		if (
			cursor.has_method("register_semantic_event_handler")
			and cursor.has_method("unregister_semantic_event_handler")
		):
			return cursor
		cursor = cursor.get_parent()
	return null


func _configuration_result() -> Dictionary:
	return {
		"ok": _errors.is_empty(),
		"configured": _configured,
		"topology_enabled": _topology_enabled,
		"errors": _errors.duplicate(),
		"space_count": _spaces.size(),
		"portal_count": _portals.size(),
		"listener_count": _listeners.size(),
	}
