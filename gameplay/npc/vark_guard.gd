class_name VarkGuard
extends CharacterBody3D


const DOOR_REQUEST_OPEN_METHOD: StringName = &"request_open"
const DOOR_BODY_IN_PASSAGE_METHOD: StringName = &"is_body_in_navigation_passage"
const DOOR_BLOCKED_BY_METHOD: StringName = &"is_motion_blocked_by"
const DOOR_TRAVERSAL_CLEAR_METHOD: StringName = &"is_navigation_traversal_clear"
const DOOR_OWNS_LINK_METHOD: StringName = &"owns_navigation_link"
const DOOR_GET_LINK_METHOD: StringName = &"get_navigation_link"
const DOOR_LINK_CLEARANCE_METHOD: StringName = &"get_navigation_link_clearance"
const DOOR_PHASE_METHOD: StringName = &"get_semantic_phase"
const DOOR_PHASE_CLOSED: StringName = &"closed"
const DOOR_PHASE_OPEN: StringName = &"open"
const DOOR_REQUEST_RETRY_SECONDS: float = 0.35
const LIFE_STATE_REQUEST_EVENT: StringName = &"actor.life_state_requested"
const LIFE_STATE_CHANGED_EVENT: StringName = &"actor.life_state_changed"
const CRUDE_HOSTILE_EFFECT_EVENT: StringName = &"combat.crude_hostile_effect"
const CRUDE_HOSTILE_EFFECT_KNOCKOUT: StringName = &"knockout"
const CRUDE_HOSTILE_IMPACT_SOUND_KIND: StringName = &"combat.hostile_impact"
const LIFE_CONSCIOUS: StringName = &"conscious"
const LIFE_UNCONSCIOUS: StringName = &"unconscious"
const LIFE_DEAD: StringName = &"dead"

enum DoorTraversalState {
	IDLE,
	WAITING_OPEN,
	CROSSING,
	CLEAR,
}

@export var persistent_id: String = ""
@export var content_id: String = ""
@export var guard_id: String = ""
@export var patrol_a_id: String = ""
@export var patrol_b_id: String = ""
@export var door_id: String = ""
@export var movement_speed: float = 2.5
@export var door_use_distance: float = 2.0

var _navigation_agent: NavigationAgent3D = null
var _world_session: Node = null
var _life_state: StringName = LIFE_CONSCIOUS
var _patrol_positions: Array[Vector3] = []
var _target_index: int = 1
var _door: Node = null
var _configured: bool = false
var _door_traversal_state: DoorTraversalState = DoorTraversalState.IDLE
var _door_use_active: bool = false
var _door_request_pending: bool = false
var _door_retry_remaining: float = 0.0
var _door_use_count: int = 0
var _door_open_request_count: int = 0
var _crossing_block_open_count: int = 0
var _door_traversal_failure_count: int = 0
var _door_link_entry: Vector3 = Vector3.ZERO
var _door_link_exit: Vector3 = Vector3.ZERO
var _last_door_error: String = ""
var _patrol_leg_count: int = 0
var _patrol_cycle_count: int = 0
var _max_observed_path_x: float = -INF
var _max_observed_path_point_count: int = 0
var _last_error: String = ""
var _restored_goal_id: String = ""
var _awareness_goal_active: bool = false
var _awareness_goal_position: Vector3 = Vector3.ZERO
var _awareness_goal_reason: StringName = &""


func _ready() -> void:
	add_to_group(&"vark_guard")
	collision_layer = 2
	collision_mask = 1
	up_direction = Vector3.UP
	_ensure_components()
	_world_session = _find_world_session()
	if _world_session != null:
		var life_registered: bool = bool(_world_session.call(
			"register_semantic_event_handler",
			LIFE_STATE_REQUEST_EVENT,
			Callable(self, "_on_life_state_requested")
		))
		if not life_registered:
			push_error("Guard '%s' could not register actor life-state requests." % guard_id)
		var hostile_registered: bool = bool(_world_session.call(
			"register_semantic_event_handler",
			CRUDE_HOSTILE_EFFECT_EVENT,
			Callable(self, "_on_crude_hostile_effect")
		))
		if not hostile_registered:
			push_error("Guard '%s' could not register crude hostile effects." % guard_id)
	_refresh_life_state_presentation()


func _exit_tree() -> void:
	if _world_session == null or not is_instance_valid(_world_session):
		return
	_world_session.call(
		"unregister_semantic_event_handler",
		LIFE_STATE_REQUEST_EVENT,
		Callable(self, "_on_life_state_requested")
	)
	_world_session.call(
		"unregister_semantic_event_handler",
		CRUDE_HOSTILE_EFFECT_EVENT,
		Callable(self, "_on_crude_hostile_effect")
	)


func is_vark_persistent_entity() -> bool:
	return true


func get_persistent_id() -> String:
	return persistent_id


func get_content_id() -> String:
	return content_id


func get_life_state() -> StringName:
	return _life_state


func query_actor_state() -> Dictionary:
	return {
		"persistent_id": persistent_id,
		"content_id": content_id,
		"actor_id": guard_id,
		"life_state": _life_state,
		"conscious": _life_state == LIFE_CONSCIOUS,
		"awareness_eligible": _life_state == LIFE_CONSCIOUS,
		"navigation_owned": _navigation_agent != null,
		"navigation_active": _life_state == LIFE_CONSCIOUS and _configured,
		"body_state": _life_state != LIFE_CONSCIOUS,
	}


func set_awareness_navigation_target(
	reason: StringName,
	target_position: Vector3
) -> bool:
	if (
		_life_state != LIFE_CONSCIOUS
		or _navigation_agent == null
		or reason.is_empty()
		or not _is_finite_vector(target_position)
	):
		return false
	_awareness_goal_active = true
	_awareness_goal_reason = reason
	_awareness_goal_position = target_position
	_apply_current_navigation_target()
	return true


func clear_awareness_navigation_target() -> bool:
	var had_goal: bool = _awareness_goal_active
	_awareness_goal_active = false
	_awareness_goal_reason = &""
	_awareness_goal_position = Vector3.ZERO
	_apply_current_navigation_target()
	return had_goal


func get_awareness_navigation_state() -> Dictionary:
	return {
		"active": _awareness_goal_active,
		"reason": _awareness_goal_reason,
		"target_position": _awareness_goal_position,
	}


func resolve_local_search_points(
	anchor: Vector3,
	radius: float,
	desired_count: int
) -> Array[Vector3]:
	var resolved: Array[Vector3] = []
	if (
		_navigation_agent == null
		or not _configured
		or not _is_finite_vector(anchor)
	):
		return resolved
	var navigation_map: RID = _navigation_agent.get_navigation_map()
	if (
		not navigation_map.is_valid()
		or NavigationServer3D.map_get_iteration_id(navigation_map) == 0
	):
		return resolved

	var clamped_radius: float = maxf(radius, 0.50)
	var clamped_count: int = clampi(desired_count, 2, 6)
	var near_radius: float = clamped_radius * 0.55
	var offsets: Array[Vector3] = [
		Vector3.ZERO,
		Vector3.RIGHT * near_radius,
		Vector3.FORWARD * near_radius,
		Vector3.LEFT * near_radius,
		Vector3.BACK * near_radius,
		(Vector3.RIGHT + Vector3.FORWARD).normalized() * clamped_radius,
		(Vector3.LEFT + Vector3.FORWARD).normalized() * clamped_radius,
		(Vector3.LEFT + Vector3.BACK).normalized() * clamped_radius,
		(Vector3.RIGHT + Vector3.BACK).normalized() * clamped_radius,
	]
	var max_projection_error: float = maxf(0.75, clamped_radius * 0.45)
	for offset: Vector3 in offsets:
		if resolved.size() >= clamped_count:
			break
		var candidate: Vector3 = anchor + offset
		var projected: Vector3 = NavigationServer3D.map_get_closest_point(
			navigation_map,
			candidate
		)
		if not _is_finite_vector(projected):
			continue
		var projection_error := Vector3(
			projected.x - candidate.x,
			0.0,
			projected.z - candidate.z
		).length()
		var anchor_distance := Vector3(
			projected.x - anchor.x,
			0.0,
			projected.z - anchor.z
		).length()
		if (
			projection_error > max_projection_error
			or anchor_distance > clamped_radius + 0.35
		):
			continue
		if not is_navigation_position_reachable(projected):
			continue
		var duplicate: bool = false
		for existing: Vector3 in resolved:
			if Vector3(
				existing.x - projected.x,
				0.0,
				existing.z - projected.z
			).length() < 0.45:
				duplicate = true
				break
		if duplicate:
			continue
		resolved.append(projected)
	return resolved


func is_navigation_position_reachable(target_position: Vector3) -> bool:
	if (
		_navigation_agent == null
		or not _configured
		or not _is_finite_vector(target_position)
	):
		return false
	var navigation_map: RID = _navigation_agent.get_navigation_map()
	if (
		not navigation_map.is_valid()
		or NavigationServer3D.map_get_iteration_id(navigation_map) == 0
	):
		return false
	var start: Vector3 = NavigationServer3D.map_get_closest_point(
		navigation_map,
		global_position
	)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(
		navigation_map,
		start,
		target_position,
		true
	)
	if path.is_empty():
		return false
	var endpoint: Vector3 = path[path.size() - 1]
	return Vector3(
		endpoint.x - target_position.x,
		0.0,
		endpoint.z - target_position.z
	).length() <= 0.55


func request_life_state(target_state: StringName) -> bool:
	if _world_session == null or not is_instance_valid(_world_session):
		return false
	if persistent_id.strip_edges().is_empty():
		return false
	if not _is_runtime_transition_allowed(_life_state, target_state):
		return false
	return bool(_world_session.call(
		"queue_semantic_gameplay_event",
		int(_world_session.get("session_id")),
		LIFE_STATE_REQUEST_EVENT,
		{
			"persistent_id": persistent_id,
			"actor_id": guard_id,
			"target_state": target_state,
		}
	))


func capture_semantic_state() -> Dictionary:
	return {
		"persistent_id": persistent_id,
		"actor_id": guard_id,
		"life_state": _life_state,
		"transform": global_transform,
		"velocity": velocity,
		"goal_id": _current_goal_id(),
	}


func apply_semantic_state(snapshot: Dictionary) -> bool:
	if (
		_world_session != null
		and is_instance_valid(_world_session)
		and int(_world_session.get("state")) == WorldSession.State.PLAYING
	):
		return false
	if snapshot.size() != 6:
		return false
	if str(snapshot.get("persistent_id", "")).strip_edges() != persistent_id:
		return false
	if str(snapshot.get("actor_id", "")).strip_edges() != guard_id:
		return false
	var restored_state: StringName = snapshot.get("life_state", &"")
	var restored_goal_id: String = str(snapshot.get("goal_id", "")).strip_edges()
	if (
		not _is_valid_life_state(restored_state)
		or (
			restored_goal_id != patrol_a_id
			and restored_goal_id != patrol_b_id
		)
		or typeof(snapshot.get("transform", null)) != TYPE_TRANSFORM3D
		or typeof(snapshot.get("velocity", null)) != TYPE_VECTOR3
	):
		return false
	var restored_transform: Transform3D = snapshot["transform"]
	var restored_velocity: Vector3 = snapshot["velocity"]
	if (
		not _is_finite_transform(restored_transform)
		or not _is_finite_vector(restored_velocity)
	):
		return false

	global_transform = restored_transform
	velocity = restored_velocity
	_restored_goal_id = restored_goal_id
	_target_index = 0 if restored_goal_id == patrol_a_id else 1
	_apply_life_state(restored_state)
	if _configured and _navigation_agent != null and _patrol_positions.size() == 2:
		_apply_current_navigation_target()
		_restored_goal_id = ""
	return true


func reconcile_after_restore() -> bool:
	_refresh_life_state_presentation()
	_apply_current_navigation_target()
	return true


func configure_patrol(patrol_points: Dictionary, door: Node) -> bool:
	_last_error = ""
	_configured = false
	_patrol_positions.clear()
	_door = null
	_door_traversal_state = DoorTraversalState.IDLE
	_door_use_active = false
	_door_request_pending = false
	_door_retry_remaining = 0.0
	_door_use_count = 0
	_door_open_request_count = 0
	_crossing_block_open_count = 0
	_door_traversal_failure_count = 0
	_door_link_entry = Vector3.ZERO
	_door_link_exit = Vector3.ZERO
	_last_door_error = ""
	_patrol_leg_count = 0
	_patrol_cycle_count = 0
	_max_observed_path_x = -INF
	_max_observed_path_x = -INF
	_max_observed_path_point_count = 0

	var patrol_a := patrol_points.get(patrol_a_id) as Node3D
	var patrol_b := patrol_points.get(patrol_b_id) as Node3D
	if patrol_a == null or patrol_b == null:
		_last_error = (
			"Guard '%s' could not resolve patrol points '%s' and '%s'."
			% [guard_id, patrol_a_id, patrol_b_id]
		)
		push_error(_last_error)
		return false
	if door == null:
		_last_error = "Guard '%s' could not resolve ordinary door '%s'." % [guard_id, door_id]
		push_error(_last_error)
		return false
	if (
		not door.has_method(DOOR_REQUEST_OPEN_METHOD)
		or not door.has_method(DOOR_BODY_IN_PASSAGE_METHOD)
		or not door.has_method(DOOR_BLOCKED_BY_METHOD)
		or not door.has_method(DOOR_TRAVERSAL_CLEAR_METHOD)
		or not door.has_method(DOOR_OWNS_LINK_METHOD)
		or not door.has_method(DOOR_GET_LINK_METHOD)
		or not door.has_method(DOOR_LINK_CLEARANCE_METHOD)
		or not door.has_method(DOOR_PHASE_METHOD)
	):
		_last_error = "Guard '%s' received a door without the ordinary navigation seam." % guard_id
		push_error(_last_error)
		return false
	if _navigation_agent == null:
		_last_error = "Guard '%s' has no NavigationAgent3D." % guard_id
		push_error(_last_error)
		return false

	_patrol_positions = [patrol_a.global_position, patrol_b.global_position]
	if _restored_goal_id == patrol_a_id:
		_target_index = 0
	elif _restored_goal_id == patrol_b_id:
		_target_index = 1
	else:
		_target_index = 1
	_door = door
	_configured = true
	_apply_current_navigation_target()
	_restored_goal_id = ""
	return true


func get_debug_summary() -> Dictionary:
	var target_position := Vector3.ZERO
	if _awareness_goal_active:
		target_position = _awareness_goal_position
	elif _configured and _target_index >= 0 and _target_index < _patrol_positions.size():
		target_position = _patrol_positions[_target_index]
	return {
		"persistent_id": persistent_id,
		"content_id": content_id,
		"guard_id": guard_id,
		"life_state": _life_state,
		"awareness_eligible": _life_state == LIFE_CONSCIOUS,
		"navigation_owned": _navigation_agent != null,
		"navigation_active": _life_state == LIFE_CONSCIOUS and _configured,
		"body_state": _life_state != LIFE_CONSCIOUS,
		"configured": _configured,
		"patrol_a_id": patrol_a_id,
		"patrol_b_id": patrol_b_id,
		"door_id": door_id,
		"door_use_distance": door_use_distance,
		"door_traversal_state": _door_traversal_state_name(),
		"door_use_active": _door_use_active,
		"door_request_pending": _door_request_pending,
		"door_close_request_pending": false,
		"doorway_traversal_required": _door_use_active,
		"door_route_blocked": (
			_door_use_active
			and _door_traversal_state == DoorTraversalState.WAITING_OPEN
		),
		"door_obstruction_imminent": (
			_door_use_active
			and _door_traversal_state == DoorTraversalState.WAITING_OPEN
		),
		"door_approach_clearance": (
			float(_door.call(DOOR_LINK_CLEARANCE_METHOD))
			if _door != null
			else 0.0
		),
		"door_distance": _horizontal_distance_to_door(),
		"target_index": _target_index,
		"target_position": target_position,
		"awareness_goal_active": _awareness_goal_active,
		"awareness_goal_reason": _awareness_goal_reason,
		"awareness_goal_position": _awareness_goal_position,
		"door_use_count": _door_use_count,
		"door_open_request_count": _door_open_request_count,
		"crossing_block_open_count": _crossing_block_open_count,
		"door_maneuver_count": 0,
		"door_close_request_count": 0,
		"door_operating_point": Vector3.ZERO,
		"door_crossing_point": _door_link_exit,
		"door_maneuver_crossing_active": false,
		"door_maneuver_target_tolerance": (
			_navigation_agent.target_desired_distance
			if _navigation_agent != null
			else -1.0
		),
		"door_link_entry": _door_link_entry,
		"door_link_exit": _door_link_exit,
		"door_traversal_failure_count": _door_traversal_failure_count,
		"last_door_error": _last_door_error,
		"patrol_leg_count": _patrol_leg_count,
		"patrol_cycle_count": _patrol_cycle_count,
		"global_position": global_position,
		"velocity": velocity,
		"max_observed_path_x": _max_observed_path_x,
		"max_observed_path_point_count": _max_observed_path_point_count,
		"last_error": _last_error,
	}


func _physics_process(delta: float) -> void:
	if _life_state != LIFE_CONSCIOUS:
		velocity = Vector3.ZERO
		return
	if not _configured or _navigation_agent == null:
		velocity = Vector3.ZERO
		return
	if _door_use_active:
		_process_door_traversal(delta)
		return

	var next_position: Vector3 = _navigation_agent.get_next_path_position()
	# get_next_path_position() can synchronously emit link_reached. Once that
	# happens the explicit traversal task owns this frame and normal navigation
	# stops touching the agent until the body exits the link.
	if _door_use_active:
		_process_door_traversal(delta)
		return

	_record_current_path()
	var target_position: Vector3 = (
		_awareness_goal_position
		if _awareness_goal_active
		else _patrol_positions[_target_index]
	)
	var horizontal_to_target := Vector3(
		target_position.x - global_position.x,
		0.0,
		target_position.z - global_position.z
	)
	if horizontal_to_target.length() <= maxf(_navigation_agent.target_desired_distance, 0.3):
		velocity = Vector3.ZERO
		if not _awareness_goal_active:
			_complete_patrol_leg()
		return

	if _navigation_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		if _awareness_goal_active:
			return
		var target_id: String = patrol_b_id if _target_index == 1 else patrol_a_id
		_last_error = "Guard '%s' has no route to patrol target '%s'." % [guard_id, target_id]
		_configured = false
		push_error(_last_error)
		return

	var direction := Vector3(
		next_position.x - global_position.x,
		0.0,
		next_position.z - global_position.z
	)
	if direction.length_squared() <= 0.000001:
		velocity = Vector3.ZERO
		return
	direction = direction.normalized()
	velocity = Vector3(direction.x * movement_speed, 0.0, direction.z * movement_speed)
	look_at(global_position + direction, Vector3.UP, true)
	move_and_slide()


func _on_navigation_link_reached(details: Dictionary) -> void:
	if _door == null or _door_use_active:
		return
	var owner: Object = details.get("owner", null)
	if not bool(_door.call(DOOR_OWNS_LINK_METHOD, owner)):
		return
	var entry_value: Variant = details.get("link_entry_position", null)
	var exit_value: Variant = details.get("link_exit_position", null)
	if typeof(entry_value) != TYPE_VECTOR3 or typeof(exit_value) != TYPE_VECTOR3:
		_record_door_traversal_failure("door link metadata did not contain entry/exit positions")
		return
	var entry: Vector3 = entry_value
	var exit_position: Vector3 = exit_value
	if not _is_finite_vector(entry) or not _is_finite_vector(exit_position):
		_record_door_traversal_failure("door link metadata contained non-finite positions")
		return

	_door_link_entry = entry
	_door_link_exit = exit_position
	_door_use_active = true
	_door_request_pending = false
	_door_retry_remaining = 0.0
	_door_traversal_state = DoorTraversalState.WAITING_OPEN
	_door_use_count += 1
	_last_door_error = ""


func _process_door_traversal(delta: float) -> void:
	if _door == null:
		_abort_door_traversal("configured ordinary door disappeared")
		return

	var passage_clear: bool = bool(_door.call(
		DOOR_TRAVERSAL_CLEAR_METHOD,
		self,
		_door_link_entry,
		_door_link_exit
	))
	if _door_traversal_state == DoorTraversalState.WAITING_OPEN:
		velocity = Vector3.ZERO
		if passage_clear:
			_door_request_pending = false
			_door_retry_remaining = 0.0
			_door_traversal_state = DoorTraversalState.CROSSING
		else:
			_retry_door_open_request(delta)
			return

	if _door_traversal_state != DoorTraversalState.CROSSING:
		velocity = Vector3.ZERO
		return

	var body_in_passage: bool = bool(_door.call(DOOR_BODY_IN_PASSAGE_METHOD, self))
	if not passage_clear and not body_in_passage:
		_door_traversal_state = DoorTraversalState.WAITING_OPEN
		_retry_door_open_request(delta)
		velocity = Vector3.ZERO
		return

	if bool(_door.call(DOOR_BLOCKED_BY_METHOD, self)):
		_crossing_block_open_count += 1
		_retry_door_open_request(delta)

	var to_exit := Vector3(
		_door_link_exit.x - global_position.x,
		0.0,
		_door_link_exit.z - global_position.z
	)
	if to_exit.length() <= maxf(_navigation_agent.path_desired_distance * 0.5, 0.12):
		_finish_door_traversal()
		return
	if to_exit.length_squared() <= 0.000001:
		_finish_door_traversal()
		return

	var direction: Vector3 = to_exit.normalized()
	velocity = Vector3(direction.x * movement_speed, 0.0, direction.z * movement_speed)
	look_at(global_position + direction, Vector3.UP, true)
	move_and_slide()


func _retry_door_open_request(delta: float) -> void:
	_door_request_pending = true
	_door_retry_remaining = maxf(0.0, _door_retry_remaining - delta)
	if is_zero_approx(_door_retry_remaining):
		_door.call(DOOR_REQUEST_OPEN_METHOD, self)
		_door_open_request_count += 1
		_door_retry_remaining = DOOR_REQUEST_RETRY_SECONDS


func _finish_door_traversal() -> void:
	velocity = Vector3.ZERO
	_door_use_active = false
	_door_request_pending = false
	_door_retry_remaining = 0.0
	_door_traversal_state = DoorTraversalState.CLEAR
	_door_link_entry = Vector3.ZERO
	_door_link_exit = Vector3.ZERO
	# Awareness/patrol may have changed while crossing. Re-issue only the
	# semantic destination now; the door task never substitutes its own target.
	_apply_current_navigation_target()


func _abort_door_traversal(reason: String) -> void:
	_record_door_traversal_failure(reason)
	velocity = Vector3.ZERO
	_door_use_active = false
	_door_request_pending = false
	_door_retry_remaining = 0.0
	_door_traversal_state = DoorTraversalState.IDLE
	_door_link_entry = Vector3.ZERO
	_door_link_exit = Vector3.ZERO
	_apply_current_navigation_target()


func _record_door_traversal_failure(reason: String) -> void:
	_door_traversal_failure_count += 1
	_last_door_error = reason
	# A local smart-link failure must never invalidate the guard's whole
	# navigation configuration. Keep the semantic goal and let normal routing
	# retry/replan rather than turning the NPC off.
	push_warning("Guard '%s' door traversal: %s" % [guard_id, reason])


func _apply_current_navigation_target() -> void:
	if (
		not _configured
		or _navigation_agent == null
		or _patrol_positions.size() != 2
		or _door_use_active
	):
		return
	_navigation_agent.target_position = (
		_awareness_goal_position
		if _life_state == LIFE_CONSCIOUS and _awareness_goal_active
		else _patrol_positions[_target_index]
	)


func _horizontal_distance_to_door() -> float:
	if _door == null:
		return INF
	var to_door: Vector3 = _door.global_position - global_position
	to_door.y = 0.0
	return to_door.length()


func _door_traversal_state_name() -> StringName:
	match _door_traversal_state:
		DoorTraversalState.WAITING_OPEN:
			return &"waiting_open"
		DoorTraversalState.CROSSING:
			return &"crossing"
		DoorTraversalState.CLEAR:
			return &"clear"
		_:
			return &"idle"


func _complete_patrol_leg() -> void:
	velocity = Vector3.ZERO
	_patrol_leg_count += 1
	_door_traversal_state = DoorTraversalState.IDLE
	_door_use_active = false
	_door_request_pending = false
	_door_retry_remaining = 0.0
	if _target_index == 1:
		_target_index = 0
	else:
		_target_index = 1
		_patrol_cycle_count += 1
	_apply_current_navigation_target()


func _record_current_path() -> void:
	var path: PackedVector3Array = _navigation_agent.get_current_navigation_path()
	_max_observed_path_point_count = maxi(_max_observed_path_point_count, path.size())
	for path_point: Vector3 in path:
		_max_observed_path_x = maxf(_max_observed_path_x, path_point.x)


func _on_crude_hostile_effect(event: Dictionary) -> bool:
	var payload: Dictionary = event.get("payload", {})
	if str(payload.get("target_persistent_id", "")).strip_edges() != persistent_id:
		return true
	if str(payload.get("target_actor_id", "")).strip_edges() != guard_id:
		return true
	if _life_state != LIFE_CONSCIOUS:
		return true
	if payload.get("effect", &"") != CRUDE_HOSTILE_EFFECT_KNOCKOUT:
		return true

	var impact_origin: Vector3 = payload.get(
		"impact_origin",
		global_position + Vector3.UP * 0.9
	)
	var sound_strength: float = float(
		payload.get("sound_strength", 0.0)
	)
	if (
		not _is_finite_vector(impact_origin)
		or not is_finite(sound_strength)
		or sound_strength <= 0.0
	):
		return false

	# FIFO ordering is intentional: conscious acoustic listeners react to the
	# impact before this actor's existing semantic life-state request applies.
	var sound_queued: bool = bool(_world_session.call(
		"queue_semantic_gameplay_event",
		int(_world_session.get("session_id")),
		&"gameplay.sound",
		{
			"kind": CRUDE_HOSTILE_IMPACT_SOUND_KIND,
			"origin": impact_origin,
			"strength": sound_strength,
		}
	))
	if not sound_queued:
		return false
	return request_life_state(LIFE_UNCONSCIOUS)


func _on_life_state_requested(event: Dictionary) -> bool:
	var payload: Dictionary = event.get("payload", {})
	if str(payload.get("persistent_id", "")).strip_edges() != persistent_id:
		return true
	if str(payload.get("actor_id", "")).strip_edges() != guard_id:
		return true

	var target_state: StringName = payload.get("target_state", &"")
	if not _is_runtime_transition_allowed(_life_state, target_state):
		return true

	var previous_state: StringName = _life_state
	var changed_queued: bool = bool(_world_session.call(
		"queue_semantic_gameplay_event",
		int(_world_session.get("session_id")),
		LIFE_STATE_CHANGED_EVENT,
		{
			"persistent_id": persistent_id,
			"actor_id": guard_id,
			"from_state": previous_state,
			"to_state": target_state,
		}
	))
	if not changed_queued:
		return false

	_apply_life_state(target_state)
	return true


func _apply_life_state(target_state: StringName) -> void:
	_life_state = target_state
	if _life_state != LIFE_CONSCIOUS:
		velocity = Vector3.ZERO
		_door_use_active = false
		_door_request_pending = false
		_door_retry_remaining = 0.0
		_door_traversal_state = DoorTraversalState.IDLE
		_door_link_entry = Vector3.ZERO
		_door_link_exit = Vector3.ZERO
	_refresh_life_state_presentation()


func _refresh_life_state_presentation() -> void:
	var guard_mesh := get_node_or_null("GuardMesh") as MeshInstance3D
	if guard_mesh == null:
		return
	var material := guard_mesh.material_override as StandardMaterial3D
	match _life_state:
		LIFE_UNCONSCIOUS:
			guard_mesh.rotation_degrees.z = -65.0
			if material != null:
				material.albedo_color = Color(0.62, 0.42, 0.16, 1.0)
		LIFE_DEAD:
			guard_mesh.rotation_degrees.z = -90.0
			if material != null:
				material.albedo_color = Color(0.26, 0.26, 0.26, 1.0)
		_:
			guard_mesh.rotation_degrees.z = 0.0
			if material != null:
				material.albedo_color = Color(0.58, 0.20, 0.14, 1.0)


func _is_valid_life_state(state: StringName) -> bool:
	return state == LIFE_CONSCIOUS or state == LIFE_UNCONSCIOUS or state == LIFE_DEAD


func _is_runtime_transition_allowed(
	from_state: StringName,
	to_state: StringName
) -> bool:
	if not _is_valid_life_state(to_state) or from_state == to_state:
		return false
	if from_state == LIFE_CONSCIOUS:
		return to_state == LIFE_UNCONSCIOUS or to_state == LIFE_DEAD
	if from_state == LIFE_UNCONSCIOUS:
		return to_state == LIFE_DEAD
	return false


func _current_goal_id() -> String:
	if not _restored_goal_id.is_empty():
		return _restored_goal_id
	return patrol_a_id if _target_index == 0 else patrol_b_id


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _is_finite_transform(value: Transform3D) -> bool:
	return (
		_is_finite_vector(value.origin)
		and _is_finite_vector(value.basis.x)
		and _is_finite_vector(value.basis.y)
		and _is_finite_vector(value.basis.z)
	)


func _find_world_session() -> Node:
	var cursor: Node = get_parent()
	while cursor != null:
		if (
			cursor.has_method("queue_semantic_gameplay_event")
			and cursor.has_method("register_semantic_event_handler")
		):
			return cursor
		cursor = cursor.get_parent()
	return null


func _ensure_components() -> void:
	if get_node_or_null("CollisionShape3D") == null:
		var collision_shape := CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		collision_shape.position = Vector3(0.0, 0.85, 0.0)
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.28
		capsule.height = 1.7
		collision_shape.shape = capsule
		add_child(collision_shape)

	if get_node_or_null("GuardMesh") == null:
		var guard_mesh := MeshInstance3D.new()
		guard_mesh.name = "GuardMesh"
		guard_mesh.position = Vector3(0.0, 0.85, 0.0)
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3(0.55, 1.7, 0.55)
		guard_mesh.mesh = box_mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.58, 0.20, 0.14, 1.0)
		guard_mesh.material_override = material
		add_child(guard_mesh)

	_navigation_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if _navigation_agent == null:
		_navigation_agent = NavigationAgent3D.new()
		_navigation_agent.name = "NavigationAgent3D"
		# Phase 3.7 bakes navigation at Godot's 0.25 m default cell height.
		# The guard origin is at its feet, so align returned/checkable waypoints
		# to that grounded origin and keep waypoint tolerance above one voxel.
		_navigation_agent.path_height_offset = 0.25
		_navigation_agent.path_desired_distance = 0.30
		_navigation_agent.target_desired_distance = 0.28
		_navigation_agent.radius = 0.28
		_navigation_agent.height = 1.7
		_navigation_agent.avoidance_enabled = false
		add_child(_navigation_agent)
	_navigation_agent.path_metadata_flags = (
		NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_ALL
	)
	if not _navigation_agent.link_reached.is_connected(_on_navigation_link_reached):
		_navigation_agent.link_reached.connect(_on_navigation_link_reached)
