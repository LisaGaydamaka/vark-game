extends Node


# Keep this reusable script independent of custom global-class scan order.
# These values are stable semantic contract values owned by the corresponding
# guard/session APIs; runtime interaction stays on built-in Node seams.
const GUARD_LIFE_CONSCIOUS: StringName = &"conscious"
const HOSTILE_IMPACT_SOUND_KIND: StringName = &"combat.hostile_impact"
const WORLD_SESSION_STATE_PLAYING: int = 4

const STATE_UNAWARE: StringName = &"unaware"
const STATE_SUSPICIOUS: StringName = &"suspicious"
const STATE_INVESTIGATING: StringName = &"investigating"
const STATE_SEARCHING: StringName = &"searching"
const STATE_ALERTED: StringName = &"alerted"
const STATE_RECOVERING: StringName = &"recovering"
const STATE_INACTIVE: StringName = &"inactive"

const NAV_INVESTIGATE: StringName = &"investigate"
const NAV_SEARCH: StringName = &"search"
const NAV_PURSUIT: StringName = &"pursuit"

const SEARCH_ACTION_MOVING: StringName = &"moving"
const SEARCH_ACTION_ARRIVAL_PAUSE: StringName = &"arrival_pause"
const SEARCH_ACTION_LOOK_TURN: StringName = &"look_turn"
const SEARCH_ACTION_LOOK_HOLD: StringName = &"look_hold"
const SEARCH_ACTION_BETWEEN_PAUSE: StringName = &"between_look_pause"
const SEARCH_ACTION_DEPARTURE_PAUSE: StringName = &"departure_pause"

@export var player_path: NodePath = NodePath("../../Player")
@export var listener_path: NodePath = NodePath("../Hearing")
@export var speech_path: NodePath = NodePath("../Speech")
@export var exposure_path: NodePath = NodePath("../../GameplayExposure")
@export var status_label_path: NodePath = NodePath("../ReactionLabel")
@export var vision_distance: float = 6.0
@export var vision_facing_dot: float = 0.30
@export_range(10.0, 85.0, 1.0) var vision_vertical_angle_degrees: float = 55.0
@export_range(10.0, 89.0, 1.0) var vision_engaged_vertical_angle_degrees: float = 80.0
@export var vision_suspicion_exposure_threshold: float = 0.12
@export var vision_confirm_exposure_threshold: float = 0.28
@export var vision_darkness_confirm_distance: float = 1.50
@export var vision_darkness_confirm_facing_dot: float = 0.75
@export var hearing_investigate_strength: float = 0.16
@export var suspicion_seconds: float = 1.25
@export var investigation_seconds: float = 2.50
@export var search_seconds: float = 32.00
@export_range(2, 6, 1) var search_point_count: int = 4
@export_range(0.5, 6.0, 0.1) var search_radius: float = 2.80
@export_range(0.5, 10.0, 0.1) var search_max_radius: float = 6.00
@export_range(0.1, 3.0, 0.1) var search_radius_expansion: float = 1.40
@export_range(0.25, 3.0, 0.05) var search_point_min_separation: float = 1.40
@export_range(0.0, 0.5, 0.01) var search_confidence_decay_per_second: float = 0.08
@export_range(0.0, 0.5, 0.01) var search_confidence_drop_per_expansion: float = 0.12
@export_range(0.05, 0.75, 0.05) var search_min_confidence: float = 0.20
@export_range(0.20, 1.0, 0.05) var search_arrival_distance: float = 0.40
@export_range(0.20, 1.0, 0.05) var search_move_speed_scale_min: float = 0.45
@export_range(0.20, 1.0, 0.05) var search_move_speed_scale_max: float = 0.68
@export_range(0.05, 3.0, 0.05) var search_arrival_pause_min: float = 0.45
@export_range(0.05, 3.0, 0.05) var search_arrival_pause_max: float = 1.30
@export_range(0.05, 2.0, 0.05) var search_look_turn_min: float = 0.25
@export_range(0.05, 2.0, 0.05) var search_look_turn_max: float = 0.65
@export_range(0.10, 3.0, 0.05) var search_look_hold_min: float = 0.80
@export_range(0.10, 3.0, 0.05) var search_scan_seconds: float = 2.20
@export_range(0.05, 2.0, 0.05) var search_between_pause_min: float = 0.20
@export_range(0.05, 2.0, 0.05) var search_between_pause_max: float = 0.80
@export_range(0.05, 3.0, 0.05) var search_departure_pause_min: float = 0.35
@export_range(0.05, 3.0, 0.05) var search_departure_pause_max: float = 1.10
@export_range(1, 3, 1) var search_look_count_min: int = 1
@export_range(1, 4, 1) var search_look_count_max: int = 3
@export_range(5.0, 60.0, 1.0) var search_look_min_degrees: float = 20.0
@export_range(10.0, 100.0, 1.0) var search_scan_degrees: float = 70.0
@export var alert_loss_seconds: float = 1.00
@export var recovery_seconds: float = 2.00
@export_range(0.25, 1.0, 0.05) var recovery_hearing_threshold_scale: float = 0.65

var _guard: CharacterBody3D = null
var _player: CharacterBody3D = null
var _listener: Node = null
var _speech: Node = null
var _exposure: Node = null
var _status_label: Label3D = null
var _world_session: Node = null

var _awareness_state: StringName = STATE_UNAWARE
var _heard_count: int = 0
var _seen_count: int = 0
var _speech_reaction_count: int = 0
var _last_heard_kind: StringName = &""
var _last_heard_origin: Vector3 = Vector3.ZERO
var _last_heard_strength: float = 0.0
var _last_vision_target: Vector3 = Vector3.ZERO
var _last_vision_exposure: float = 0.0
var _last_vision_blocked: bool = false
var _last_vision_blocker: String = ""
var _last_vision_distance: float = 0.0
var _last_vision_facing_dot: float = -1.0
var _last_vision_vertical_angle_degrees: float = 0.0
var _last_vision_vertical_limit_degrees: float = 0.0
var _last_vision_darkness_override: bool = false
var _last_seen_position: Vector3 = Vector3.ZERO
var _investigation_target: Vector3 = Vector3.ZERO
var _has_investigation_target: bool = false
var _state_remaining_seconds: float = 0.0
var _alert_loss_remaining_seconds: float = 0.0
var _has_alert_loss_timer: bool = false
var _last_gameplay_time_sample: float = 0.0
var _search_anchor: Vector3 = Vector3.ZERO
var _search_points: Array[Vector3] = []
var _search_index: int = 0
var _search_scan_active: bool = false
var _search_scan_remaining_seconds: float = 0.0
var _search_scan_base_direction: Vector3 = Vector3.FORWARD
var _search_points_visited: int = 0
var _search_reseed_count: int = 0
var _search_seed: int = 0
var _search_stage: int = 0
var _search_uncertainty_radius: float = 0.0
var _search_confidence: float = 0.0
var _search_age_seconds: float = 0.0
var _search_visited_positions: Array[Vector3] = []
var _residual_alert_strength: float = 0.0
var _search_action: StringName = SEARCH_ACTION_MOVING
var _search_action_remaining_seconds: float = 0.0
var _search_action_duration_seconds: float = 0.0
var _search_action_serial: int = 0
var _search_looks_remaining: int = 0
var _search_look_start_direction: Vector3 = Vector3.FORWARD
var _search_look_target_direction: Vector3 = Vector3.FORWARD
var _search_move_speed_scale: float = 0.60


func _ready() -> void:
	_guard = get_parent() as CharacterBody3D
	_player = get_node_or_null(player_path) as CharacterBody3D
	_listener = get_node_or_null(listener_path)
	_speech = get_node_or_null(speech_path)
	_exposure = get_node_or_null(exposure_path)
	_status_label = get_node_or_null(status_label_path) as Label3D
	_world_session = _find_world_session()
	_last_gameplay_time_sample = _get_gameplay_time()
	if _listener != null and _listener.has_signal(&"gameplay_sound_heard"):
		_listener.connect(
			&"gameplay_sound_heard",
			Callable(self, "_on_gameplay_sound_heard")
		)
	_refresh_label()


func _exit_tree() -> void:
	var heard_callable: Callable = Callable(self, "_on_gameplay_sound_heard")
	if (
		_listener != null
		and is_instance_valid(_listener)
		and _listener.is_connected(&"gameplay_sound_heard", heard_callable)
	):
		_listener.disconnect(&"gameplay_sound_heard", heard_callable)


func _physics_process(_delta: float) -> void:
	if _guard == null or not is_instance_valid(_guard):
		return
	if not _guard_is_conscious():
		if _awareness_state != STATE_INACTIVE:
			_enter_state(STATE_INACTIVE)
		_sync_gameplay_clock()
		return

	var elapsed: float = _advance_gameplay_timers()
	if _awareness_state == STATE_SEARCHING:
		_advance_search_behavior(elapsed)
	sample_vision_now()
	_advance_state_if_expired()


func sample_vision_now() -> bool:
	if (
		_guard == null
		or _player == null
		or _exposure == null
		or not is_instance_valid(_guard)
		or not is_instance_valid(_player)
		or not is_instance_valid(_exposure)
	):
		return false
	if not _guard_is_conscious():
		_enter_state(STATE_INACTIVE)
		return false

	var exposure: float = float(_exposure.call("get_current_exposure"))
	_last_vision_exposure = exposure
	_last_vision_target = _get_player_vision_target()
	_last_vision_blocked = false
	_last_vision_blocker = ""
	_last_vision_distance = 0.0
	_last_vision_facing_dot = -1.0
	_last_vision_vertical_angle_degrees = 0.0
	_last_vision_vertical_limit_degrees = 0.0
	_last_vision_darkness_override = false

	# Darkness is strong protection, not magical invisibility. Distance, facing,
	# and physical LOS must be resolved before exposure can reject vision so a
	# guard standing face-to-face with the player can still receive decisive
	# visual evidence in complete gameplay darkness.
	var eye: Vector3 = _guard.global_position + Vector3.UP * 1.35
	var target: Vector3 = _last_vision_target
	var to_player: Vector3 = target - eye
	var distance: float = to_player.length()
	_last_vision_distance = distance
	if distance <= 0.001 or distance > vision_distance:
		_record_vision_loss()
		return false
	var horizontal_to_player := Vector3(to_player.x, 0.0, to_player.z)
	var horizontal_distance: float = horizontal_to_player.length()
	var facing: Vector3 = _horizontal_facing_direction()
	var facing_dot: float = 1.0
	if horizontal_distance > 0.001:
		facing_dot = facing.dot(horizontal_to_player / horizontal_distance)
	_last_vision_facing_dot = facing_dot
	_last_vision_vertical_angle_degrees = rad_to_deg(atan2(
		absf(to_player.y),
		maxf(horizontal_distance, 0.001)
	))
	_last_vision_vertical_limit_degrees = _current_vision_vertical_limit_degrees()
	if (
		facing_dot < vision_facing_dot
		or _last_vision_vertical_angle_degrees
			> _last_vision_vertical_limit_degrees
	):
		_record_vision_loss()
		return false

	var query := PhysicsRayQueryParameters3D.create(eye, target)
	query.collision_mask = 1 | 4
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [_guard.get_rid()]
	var hit: Dictionary = _guard.get_world_3d().direct_space_state.intersect_ray(
		query
	)
	if not hit.is_empty():
		_last_vision_blocked = true
		var blocker: Object = hit.get("collider") as Object
		if blocker != null:
			_last_vision_blocker = str(blocker.get("name"))
		_record_vision_loss()
		return false

	_last_vision_darkness_override = (
		exposure < vision_confirm_exposure_threshold
		and distance <= maxf(vision_darkness_confirm_distance, 0.0)
		and facing_dot >= vision_darkness_confirm_facing_dot
	)
	if (
		exposure < vision_suspicion_exposure_threshold
		and not _last_vision_darkness_override
	):
		_record_vision_loss()
		return false

	_last_seen_position = target
	_investigation_target = target
	_has_investigation_target = true
	_has_alert_loss_timer = false
	_alert_loss_remaining_seconds = 0.0

	if (
		exposure >= vision_confirm_exposure_threshold
		or _last_vision_darkness_override
		or _awareness_state == STATE_ALERTED
	):
		if _awareness_state != STATE_ALERTED:
			_seen_count += 1
			_enter_state(STATE_ALERTED, target, true)
		else:
			_guard.call(
				"set_awareness_navigation_target",
				NAV_PURSUIT,
				target
			)
		_refresh_label()
		return true

	if (
		_awareness_state == STATE_UNAWARE
		or _awareness_state == STATE_RECOVERING
	):
		_enter_state(STATE_SUSPICIOUS, target, true)
	elif _awareness_state == STATE_SUSPICIOUS:
		_state_remaining_seconds = maxf(
			_state_remaining_seconds,
			suspicion_seconds
		)
	_refresh_label()
	return false


func reset_reaction() -> void:
	_enter_state(STATE_UNAWARE)
	_last_heard_kind = &""
	_last_heard_origin = Vector3.ZERO
	_last_heard_strength = 0.0
	_last_vision_target = Vector3.ZERO
	_last_vision_exposure = 0.0
	_last_vision_blocked = false
	_last_vision_blocker = ""
	_last_vision_distance = 0.0
	_last_vision_facing_dot = -1.0
	_last_vision_vertical_angle_degrees = 0.0
	_last_vision_vertical_limit_degrees = 0.0
	_last_vision_darkness_override = false
	_last_seen_position = Vector3.ZERO
	_investigation_target = Vector3.ZERO
	_has_investigation_target = false
	_clear_search_plan(true)
	_search_reseed_count = 0
	_refresh_label()


func get_debug_summary() -> Dictionary:
	return {
		# "state" retains the Phase 3 debug vocabulary for old fixtures. New
		# gameplay truth is awareness_state/captured semantic state below.
		"state": _legacy_debug_state(),
		"awareness_state": _awareness_state,
		"heard_count": _heard_count,
		"seen_count": _seen_count,
		"speech_reaction_count": _speech_reaction_count,
		"last_heard_kind": _last_heard_kind,
		"last_heard_origin": _last_heard_origin,
		"last_heard_strength": _last_heard_strength,
		"last_vision_target": _last_vision_target,
		"last_vision_exposure": _last_vision_exposure,
		"last_vision_blocked": _last_vision_blocked,
		"last_vision_blocker": _last_vision_blocker,
		"last_vision_distance": _last_vision_distance,
		"last_vision_facing_dot": _last_vision_facing_dot,
		"last_vision_vertical_angle_degrees": _last_vision_vertical_angle_degrees,
		"last_vision_vertical_limit_degrees": _last_vision_vertical_limit_degrees,
		"last_vision_darkness_override": _last_vision_darkness_override,
		"last_seen_position": _last_seen_position,
		"investigation_target": _investigation_target,
		"has_investigation_target": _has_investigation_target,
		"state_remaining_seconds": _state_remaining_seconds,
		"alert_loss_remaining_seconds": _alert_loss_remaining_seconds,
		"has_alert_loss_timer": _has_alert_loss_timer,
		"search_anchor": _search_anchor,
		"search_points": _search_points.duplicate(),
		"search_index": _search_index,
		"search_scan_active": _search_scan_active,
		"search_scan_remaining_seconds": _search_scan_remaining_seconds,
		"search_points_visited": _search_points_visited,
		"search_reseed_count": _search_reseed_count,
		"search_seed": _search_seed,
		"search_stage": _search_stage,
		"search_uncertainty_radius": _search_uncertainty_radius,
		"search_confidence": _search_confidence,
		"search_age_seconds": _search_age_seconds,
		"search_visited_positions": _search_visited_positions.duplicate(),
		"residual_alert_strength": _residual_alert_strength,
		"search_action": _search_action,
		"search_action_remaining_seconds": _search_action_remaining_seconds,
		"search_action_duration_seconds": _search_action_duration_seconds,
		"search_action_serial": _search_action_serial,
		"search_looks_remaining": _search_looks_remaining,
		"search_look_start_direction": _search_look_start_direction,
		"search_look_target_direction": _search_look_target_direction,
		"search_move_speed_scale": _search_move_speed_scale,
		"search_radius": search_radius,
		"search_max_radius": search_max_radius,
		"search_point_count": search_point_count,
		"search_point_min_separation": search_point_min_separation,
		"vision_distance": vision_distance,
		"vision_facing_dot": vision_facing_dot,
		"vision_vertical_angle_degrees": vision_vertical_angle_degrees,
		"vision_engaged_vertical_angle_degrees": vision_engaged_vertical_angle_degrees,
		"current_vision_vertical_limit_degrees": _current_vision_vertical_limit_degrees(),
		"vision_suspicion_exposure_threshold": (
			vision_suspicion_exposure_threshold
		),
		"vision_confirm_exposure_threshold": (
			vision_confirm_exposure_threshold
		),
		"vision_darkness_confirm_distance": vision_darkness_confirm_distance,
		"vision_darkness_confirm_facing_dot": vision_darkness_confirm_facing_dot,
		"hearing_investigate_strength": hearing_investigate_strength,
		"gameplay_time_seconds": _get_gameplay_time(),
	}


func get_semantic_save_id() -> String:
	if _guard == null or not is_instance_valid(_guard):
		return ""
	return "guard_awareness:%s" % str(_guard.call("get_persistent_id"))


func capture_semantic_state() -> Dictionary:
	return {
		"guard_persistent_id": (
			str(_guard.call("get_persistent_id"))
			if _guard != null and is_instance_valid(_guard)
			else ""
		),
		"state": _awareness_state,
		"heard_count": _heard_count,
		"seen_count": _seen_count,
		"speech_reaction_count": _speech_reaction_count,
		"last_heard_kind": _last_heard_kind,
		"last_heard_origin": _last_heard_origin,
		"last_heard_strength": _last_heard_strength,
		"last_vision_target": _last_vision_target,
		"last_vision_exposure": _last_vision_exposure,
		"last_vision_blocked": _last_vision_blocked,
		"last_vision_blocker": _last_vision_blocker,
		"last_seen_position": _last_seen_position,
		"investigation_target": _investigation_target,
		"has_investigation_target": _has_investigation_target,
		"state_remaining_seconds": _state_remaining_seconds,
		"alert_loss_remaining_seconds": _alert_loss_remaining_seconds,
		"has_alert_loss_timer": _has_alert_loss_timer,
		"search_anchor": _search_anchor,
		"search_points": _search_points.duplicate(),
		"search_index": _search_index,
		"search_scan_active": _search_scan_active,
		"search_scan_remaining_seconds": _search_scan_remaining_seconds,
		"search_scan_base_direction": _search_scan_base_direction,
		"search_points_visited": _search_points_visited,
		"search_seed": _search_seed,
		"search_stage": _search_stage,
		"search_uncertainty_radius": _search_uncertainty_radius,
		"search_confidence": _search_confidence,
		"search_age_seconds": _search_age_seconds,
		"search_visited_positions": _search_visited_positions.duplicate(),
		"residual_alert_strength": _residual_alert_strength,
		"search_action": _search_action,
		"search_action_remaining_seconds": _search_action_remaining_seconds,
		"search_action_duration_seconds": _search_action_duration_seconds,
		"search_action_serial": _search_action_serial,
		"search_looks_remaining": _search_looks_remaining,
		"search_look_start_direction": _search_look_start_direction,
		"search_look_target_direction": _search_look_target_direction,
		"search_move_speed_scale": _search_move_speed_scale,
	}


func apply_semantic_state(snapshot: Dictionary) -> bool:
	var session: Node = _find_world_session()
	if (
		session != null
		and is_instance_valid(session)
		and int(session.get("state")) == WORLD_SESSION_STATE_PLAYING
	):
		return false
	if snapshot.size() != 40:
		return false
	if _guard == null or not is_instance_valid(_guard):
		return false
	if (
		str(snapshot.get("guard_persistent_id", "")).strip_edges()
		!= str(_guard.call("get_persistent_id"))
	):
		return false
	var restored_state: StringName = snapshot.get("state", &"")
	if not _is_valid_awareness_state(restored_state):
		return false
	for key: String in [
		"heard_count",
		"seen_count",
		"speech_reaction_count",
	]:
		if typeof(snapshot.get(key, null)) != TYPE_INT or int(snapshot[key]) < 0:
			return false
	if (
		typeof(snapshot.get("last_heard_kind", null)) != TYPE_STRING_NAME
		or typeof(snapshot.get("last_heard_origin", null)) != TYPE_VECTOR3
		or typeof(snapshot.get("last_vision_target", null)) != TYPE_VECTOR3
		or typeof(snapshot.get("last_vision_blocked", null)) != TYPE_BOOL
		or typeof(snapshot.get("last_vision_blocker", null)) != TYPE_STRING
		or typeof(snapshot.get("last_seen_position", null)) != TYPE_VECTOR3
		or typeof(snapshot.get("investigation_target", null)) != TYPE_VECTOR3
		or typeof(snapshot.get("has_investigation_target", null)) != TYPE_BOOL
		or typeof(snapshot.get("has_alert_loss_timer", null)) != TYPE_BOOL
		or typeof(snapshot.get("search_anchor", null)) != TYPE_VECTOR3
		or typeof(snapshot.get("search_points", null)) != TYPE_ARRAY
		or typeof(snapshot.get("search_index", null)) != TYPE_INT
		or typeof(snapshot.get("search_scan_active", null)) != TYPE_BOOL
		or typeof(snapshot.get("search_scan_base_direction", null)) != TYPE_VECTOR3
		or typeof(snapshot.get("search_points_visited", null)) != TYPE_INT
		or typeof(snapshot.get("search_seed", null)) != TYPE_INT
		or typeof(snapshot.get("search_stage", null)) != TYPE_INT
		or typeof(snapshot.get("search_visited_positions", null)) != TYPE_ARRAY
		or typeof(snapshot.get("search_action", null)) != TYPE_STRING_NAME
		or typeof(snapshot.get("search_action_serial", null)) != TYPE_INT
		or typeof(snapshot.get("search_looks_remaining", null)) != TYPE_INT
		or typeof(snapshot.get("search_look_start_direction", null)) != TYPE_VECTOR3
		or typeof(snapshot.get("search_look_target_direction", null)) != TYPE_VECTOR3
	):
		return false
	for key: String in [
		"last_heard_strength",
		"last_vision_exposure",
		"state_remaining_seconds",
		"alert_loss_remaining_seconds",
		"search_scan_remaining_seconds",
		"search_uncertainty_radius",
		"search_confidence",
		"search_age_seconds",
		"residual_alert_strength",
		"search_action_remaining_seconds",
		"search_action_duration_seconds",
		"search_move_speed_scale",
	]:
		var value: Variant = snapshot.get(key, null)
		if (
			(typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT)
			or not is_finite(float(value))
			or (
				(
					key == "state_remaining_seconds"
					or key == "alert_loss_remaining_seconds"
				)
				and float(value) < 0.0
			)
		):
			return false
	for vector_key: String in [
		"last_heard_origin",
		"last_vision_target",
		"last_seen_position",
		"investigation_target",
		"search_anchor",
		"search_scan_base_direction",
		"search_look_start_direction",
		"search_look_target_direction",
	]:
		var vector_value: Vector3 = snapshot[vector_key]
		if not _is_finite_vector(vector_value):
			return false

	var restored_search_points: Array[Vector3] = []
	for point_value: Variant in snapshot.get("search_points", []):
		if typeof(point_value) != TYPE_VECTOR3:
			return false
		var point: Vector3 = point_value
		if not _is_finite_vector(point):
			return false
		restored_search_points.append(point)
	var restored_visited_positions: Array[Vector3] = []
	for visited_value: Variant in snapshot.get("search_visited_positions", []):
		if typeof(visited_value) != TYPE_VECTOR3:
			return false
		var visited_point: Vector3 = visited_value
		if not _is_finite_vector(visited_point):
			return false
		restored_visited_positions.append(visited_point)
	var restored_search_index: int = int(snapshot.get("search_index", 0))
	var restored_visited: int = int(snapshot.get("search_points_visited", 0))
	var restored_seed: int = int(snapshot.get("search_seed", 0))
	var restored_stage: int = int(snapshot.get("search_stage", 0))
	var restored_radius: float = float(snapshot.get("search_uncertainty_radius", 0.0))
	var restored_confidence: float = float(snapshot.get("search_confidence", 0.0))
	var restored_age: float = float(snapshot.get("search_age_seconds", 0.0))
	var restored_residual: float = float(snapshot.get("residual_alert_strength", 0.0))
	var restored_action: StringName = snapshot.get("search_action", &"")
	var restored_action_remaining: float = float(snapshot.get("search_action_remaining_seconds", 0.0))
	var restored_action_duration: float = float(snapshot.get("search_action_duration_seconds", 0.0))
	var restored_action_serial: int = int(snapshot.get("search_action_serial", 0))
	var restored_looks_remaining: int = int(snapshot.get("search_looks_remaining", 0))
	var restored_look_start: Vector3 = snapshot.get("search_look_start_direction", Vector3.FORWARD)
	var restored_look_target: Vector3 = snapshot.get("search_look_target_direction", Vector3.FORWARD)
	var restored_move_scale: float = float(snapshot.get("search_move_speed_scale", 0.0))
	if (
		restored_search_index < 0
		or restored_visited < 0
		or restored_seed < 0
		or restored_stage < 0
		or restored_radius < 0.0
		or restored_confidence < 0.0
		or restored_confidence > 1.0
		or restored_age < 0.0
		or restored_residual < 0.0
		or restored_residual > 1.0
		or restored_visited != restored_visited_positions.size()
		or (
			restored_search_points.is_empty()
			and restored_search_index != 0
		)
		or (
			not restored_search_points.is_empty()
			and restored_search_index >= restored_search_points.size()
		)
		or (
			restored_state != STATE_SEARCHING
			and (
				not restored_search_points.is_empty()
				or not restored_visited_positions.is_empty()
				or restored_radius > 0.0
				or restored_confidence > 0.0
				or restored_age > 0.0
			)
		)
		or (
			bool(snapshot.get("search_scan_active", false))
			and restored_state != STATE_SEARCHING
		)
		or (
			restored_state != STATE_RECOVERING
			and restored_residual > 0.0
		)
		or (
			restored_state != STATE_SEARCHING
			and restored_action != SEARCH_ACTION_MOVING
		)
	):
		return false

	_awareness_state = restored_state
	_heard_count = int(snapshot["heard_count"])
	_seen_count = int(snapshot["seen_count"])
	_speech_reaction_count = int(snapshot["speech_reaction_count"])
	_last_heard_kind = snapshot["last_heard_kind"]
	_last_heard_origin = snapshot["last_heard_origin"]
	_last_heard_strength = float(snapshot["last_heard_strength"])
	_last_vision_target = snapshot["last_vision_target"]
	_last_vision_exposure = float(snapshot["last_vision_exposure"])
	_last_vision_blocked = bool(snapshot["last_vision_blocked"])
	_last_vision_blocker = str(snapshot["last_vision_blocker"])
	_last_seen_position = snapshot["last_seen_position"]
	_investigation_target = snapshot["investigation_target"]
	_has_investigation_target = bool(snapshot["has_investigation_target"])
	_state_remaining_seconds = float(snapshot["state_remaining_seconds"])
	_alert_loss_remaining_seconds = float(
		snapshot["alert_loss_remaining_seconds"]
	)
	_has_alert_loss_timer = bool(snapshot["has_alert_loss_timer"])
	_search_anchor = snapshot["search_anchor"]
	_search_points = restored_search_points
	_search_index = restored_search_index
	_search_scan_active = bool(snapshot["search_scan_active"])
	_search_scan_remaining_seconds = float(
		snapshot["search_scan_remaining_seconds"]
	)
	_search_scan_base_direction = snapshot["search_scan_base_direction"]
	_search_points_visited = restored_visited
	_search_seed = restored_seed
	_search_stage = restored_stage
	_search_uncertainty_radius = restored_radius
	_search_confidence = restored_confidence
	_search_age_seconds = restored_age
	_search_visited_positions = restored_visited_positions
	_residual_alert_strength = restored_residual
	_search_action = restored_action
	_search_action_remaining_seconds = restored_action_remaining
	_search_action_duration_seconds = restored_action_duration
	_search_action_serial = restored_action_serial
	_search_looks_remaining = restored_looks_remaining
	_search_look_start_direction = restored_look_start
	_search_look_target_direction = restored_look_target
	_search_move_speed_scale = restored_move_scale
	_last_gameplay_time_sample = _get_gameplay_time()
	return true


func reconcile_after_restore() -> bool:
	_last_gameplay_time_sample = _get_gameplay_time()
	_apply_navigation_for_state()
	if _awareness_state == STATE_SEARCHING:
		if _search_action != SEARCH_ACTION_MOVING:
			_set_search_motion_paused(true)
		_apply_search_action_pose()
	_refresh_label()
	return true


func after_restore() -> bool:
	return true


func _advance_gameplay_timers() -> float:
	var now: float = _get_gameplay_time()
	var elapsed: float = maxf(
		0.0,
		now - _last_gameplay_time_sample
	)
	_last_gameplay_time_sample = now
	if elapsed <= 0.0:
		return 0.0
	if _state_remaining_seconds > 0.0:
		_state_remaining_seconds = maxf(
			0.0,
			_state_remaining_seconds - elapsed
		)
	if _has_alert_loss_timer:
		_alert_loss_remaining_seconds = maxf(
			0.0,
			_alert_loss_remaining_seconds - elapsed
		)
	if _awareness_state == STATE_RECOVERING:
		_residual_alert_strength = clampf(
			_state_remaining_seconds / maxf(recovery_seconds, 0.01),
			0.0,
			1.0
		)
	return elapsed


func _advance_state_if_expired() -> void:
	if (
		_awareness_state == STATE_ALERTED
		and _has_alert_loss_timer
		and _alert_loss_remaining_seconds <= 0.0
	):
		_enter_state(
			STATE_SEARCHING,
			_last_seen_position,
			true
		)
		return
	if _state_remaining_seconds > 0.0:
		return
	match _awareness_state:
		STATE_SUSPICIOUS:
			_enter_state(STATE_UNAWARE)
		STATE_INVESTIGATING:
			_enter_state(
				STATE_SEARCHING,
				_investigation_target,
				_has_investigation_target
			)
		STATE_SEARCHING:
			_enter_state(STATE_RECOVERING)
		STATE_RECOVERING:
			_enter_state(STATE_UNAWARE)


func _record_vision_loss() -> void:
	if (
		_awareness_state == STATE_ALERTED
		and not _has_alert_loss_timer
	):
		_has_alert_loss_timer = true
		_alert_loss_remaining_seconds = maxf(
			alert_loss_seconds,
			0.0
		)
	_refresh_label()


func _enter_state(
	new_state: StringName,
	target: Vector3 = Vector3.ZERO,
	has_target: bool = false
) -> void:
	if _awareness_state == STATE_SEARCHING and new_state != STATE_SEARCHING:
		_clear_search_plan(false)
	_awareness_state = new_state
	_has_alert_loss_timer = false
	_residual_alert_strength = 1.0 if new_state == STATE_RECOVERING else 0.0
	_alert_loss_remaining_seconds = 0.0
	match new_state:
		STATE_SUSPICIOUS:
			_state_remaining_seconds = maxf(
				suspicion_seconds,
				0.0
			)
		STATE_INVESTIGATING:
			_state_remaining_seconds = maxf(
				investigation_seconds,
				0.0
			)
		STATE_SEARCHING:
			_state_remaining_seconds = maxf(
				search_seconds,
				0.0
			)
		STATE_RECOVERING:
			_state_remaining_seconds = maxf(
				recovery_seconds,
				0.0
			)
		_:
			_state_remaining_seconds = 0.0

	if has_target:
		_investigation_target = target
		_has_investigation_target = true
	elif new_state == STATE_UNAWARE:
		_investigation_target = Vector3.ZERO
		_has_investigation_target = false
	if new_state == STATE_SEARCHING:
		var search_source: Vector3 = (
			target
			if has_target
			else _investigation_target
		)
		_begin_search(search_source)
	_apply_navigation_for_state()
	_refresh_label()


func _apply_navigation_for_state() -> void:
	if _guard == null or not is_instance_valid(_guard):
		return
	if not _guard_is_conscious():
		_guard.call("clear_awareness_navigation_target")
		return
	match _awareness_state:
		STATE_INVESTIGATING:
			if _has_investigation_target:
				_guard.call(
					"set_awareness_navigation_target",
					NAV_INVESTIGATE,
					_investigation_target
				)
		STATE_SEARCHING:
			if not _search_points.is_empty():
				_guard.call(
					"set_awareness_navigation_target",
					NAV_SEARCH,
					_search_points[_search_index]
				)
				_guard.call(
					"set_awareness_motion_profile",
					_search_move_speed_scale,
					_search_action != SEARCH_ACTION_MOVING
				)
			elif _has_investigation_target:
				_guard.call(
					"set_awareness_navigation_target",
					NAV_SEARCH,
					_investigation_target
				)
		STATE_ALERTED:
			if _has_investigation_target:
				_guard.call(
					"set_awareness_navigation_target",
					NAV_PURSUIT,
					_investigation_target
				)
		_:
			_guard.call("clear_awareness_navigation_target")


func _begin_search(anchor: Vector3) -> void:
	_search_anchor = anchor
	_search_points.clear()
	_search_index = 0
	_search_scan_active = false
	_search_scan_remaining_seconds = 0.0
	_search_scan_base_direction = Vector3.FORWARD
	_search_points_visited = 0
	_search_visited_positions.clear()
	_search_seed = _derive_search_seed(anchor)
	_search_stage = 0
	_search_uncertainty_radius = maxf(search_radius, 0.50)
	_search_confidence = 1.0
	_search_age_seconds = 0.0
	_search_action_serial = 0
	_search_looks_remaining = 0
	_search_look_start_direction = Vector3.FORWARD
	_search_look_target_direction = Vector3.FORWARD
	_resolve_search_stage()


func _resolve_search_stage() -> void:
	_search_points.clear()
	_search_index = 0
	_search_scan_active = false
	_search_scan_remaining_seconds = 0.0
	if (
		_guard != null
		and is_instance_valid(_guard)
		and _guard.has_method("resolve_local_search_points")
	):
		var variation_key: int = posmod(
			_search_seed + _search_stage * 7919,
			2147483647
		)
		var resolved: Variant = _guard.call(
			"resolve_local_search_points",
			_search_anchor,
			_search_uncertainty_radius,
			search_point_count,
			variation_key,
			_search_visited_positions,
			search_point_min_separation
		)
		if typeof(resolved) == TYPE_ARRAY:
			for point_value: Variant in resolved:
				if typeof(point_value) == TYPE_VECTOR3:
					_search_points.append(point_value)
	if _search_points.is_empty():
		_search_points.append(_search_anchor)
	_begin_search_move()


func _try_expand_search() -> bool:
	var maximum_radius: float = maxf(search_max_radius, search_radius)
	if _search_uncertainty_radius >= maximum_radius - 0.01:
		return false
	_search_stage += 1
	_search_uncertainty_radius = minf(
		maximum_radius,
		_search_uncertainty_radius + maxf(search_radius_expansion, 0.10)
	)
	_search_confidence = maxf(
		search_min_confidence,
		_search_confidence - maxf(search_confidence_drop_per_expansion, 0.0)
	)
	_resolve_search_stage()
	return not _search_points.is_empty()


func _clear_search_plan(reset_visited: bool) -> void:
	_search_anchor = Vector3.ZERO
	_search_points.clear()
	_search_index = 0
	_search_scan_active = false
	_search_scan_remaining_seconds = 0.0
	_search_scan_base_direction = Vector3.FORWARD
	_search_seed = 0
	_search_stage = 0
	_search_uncertainty_radius = 0.0
	_search_confidence = 0.0
	_search_age_seconds = 0.0
	_search_visited_positions.clear()
	_search_action = SEARCH_ACTION_MOVING
	_search_action_remaining_seconds = 0.0
	_search_action_duration_seconds = 0.0
	_search_action_serial = 0
	_search_looks_remaining = 0
	_search_look_start_direction = Vector3.FORWARD
	_search_look_target_direction = Vector3.FORWARD
	_search_move_speed_scale = maxf(search_move_speed_scale_max, 0.10)
	if reset_visited:
		_search_points_visited = 0


func _advance_search_behavior(elapsed: float) -> void:
	if (
		_awareness_state != STATE_SEARCHING
		or _guard == null
		or not is_instance_valid(_guard)
		or _search_points.is_empty()
	):
		return
	_search_age_seconds += elapsed
	_search_confidence = maxf(
		search_min_confidence,
		_search_confidence
			- elapsed * maxf(search_confidence_decay_per_second, 0.0)
	)

	if _search_action != SEARCH_ACTION_MOVING:
		_search_action_remaining_seconds = maxf(
			0.0,
			_search_action_remaining_seconds - elapsed
		)
		_search_scan_remaining_seconds = _search_action_remaining_seconds
		_apply_search_action_pose()
		if _search_action_remaining_seconds > 0.0:
			return
		_advance_search_stop_action()
		return

	var current_point: Vector3 = _search_points[_search_index]
	var horizontal_distance := Vector3(
		current_point.x - _guard.global_position.x,
		0.0,
		current_point.z - _guard.global_position.z
	).length()
	if horizontal_distance > maxf(search_arrival_distance, 0.20):
		return
	_begin_search_stop()


func _begin_search_move() -> void:
	_search_action = SEARCH_ACTION_MOVING
	_search_action_remaining_seconds = 0.0
	_search_action_duration_seconds = 0.0
	_search_scan_active = false
	_search_scan_remaining_seconds = 0.0
	_search_looks_remaining = 0
	var low: float = minf(search_move_speed_scale_min, search_move_speed_scale_max)
	var high: float = maxf(search_move_speed_scale_min, search_move_speed_scale_max)
	var confidence_scale: float = lerpf(
		low,
		high,
		clampf(_search_confidence, 0.0, 1.0)
	)
	var jitter: float = (
		_search_random_unit(101 + _search_stage * 17 + _search_index * 31) - 0.5
	) * 0.10
	_search_move_speed_scale = clampf(confidence_scale + jitter, low, high)
	_set_search_motion_paused(false)


func _begin_search_stop() -> void:
	_search_scan_active = true
	_search_scan_base_direction = _search_evidence_facing_direction()
	var minimum_looks: int = mini(search_look_count_min, search_look_count_max)
	var maximum_looks: int = maxi(search_look_count_min, search_look_count_max)
	var look_span: int = maximum_looks - minimum_looks + 1
	_search_looks_remaining = minimum_looks + int(floor(
		_search_random_unit(211 + _search_index * 19) * float(look_span)
	))
	_search_looks_remaining = clampi(
		_search_looks_remaining,
		minimum_looks,
		maximum_looks
	)
	_set_search_motion_paused(true)
	_start_search_timed_action(
		SEARCH_ACTION_ARRIVAL_PAUSE,
		search_arrival_pause_min,
		search_arrival_pause_max,
		301
	)


func _advance_search_stop_action() -> void:
	match _search_action:
		SEARCH_ACTION_ARRIVAL_PAUSE:
			_start_search_look_turn()
		SEARCH_ACTION_LOOK_TURN:
			_start_search_timed_action(
				SEARCH_ACTION_LOOK_HOLD,
				search_look_hold_min,
				search_scan_seconds,
				401
			)
		SEARCH_ACTION_LOOK_HOLD:
			_search_looks_remaining = maxi(0, _search_looks_remaining - 1)
			if _search_looks_remaining > 0:
				_start_search_timed_action(
					SEARCH_ACTION_BETWEEN_PAUSE,
					search_between_pause_min,
					search_between_pause_max,
					501
				)
			else:
				_start_search_timed_action(
					SEARCH_ACTION_DEPARTURE_PAUSE,
					search_departure_pause_min,
					search_departure_pause_max,
					601
				)
		SEARCH_ACTION_BETWEEN_PAUSE:
			_start_search_look_turn()
		SEARCH_ACTION_DEPARTURE_PAUSE:
			_complete_search_point()


func _start_search_look_turn() -> void:
	_search_look_start_direction = _horizontal_facing_direction()
	var minimum_degrees: float = minf(
		search_look_min_degrees,
		search_scan_degrees
	)
	var maximum_degrees: float = maxf(
		search_look_min_degrees,
		search_scan_degrees
	)
	var magnitude: float = lerpf(
		minimum_degrees,
		maximum_degrees,
		_search_random_unit(701 + _search_looks_remaining * 13)
	)
	var sign_value: float = (
		-1.0
		if _search_random_unit(751 + _search_looks_remaining * 29) < 0.5
		else 1.0
	)
	var base_direction: Vector3 = _search_scan_base_direction
	if base_direction.length_squared() <= 0.000001:
		base_direction = _search_look_start_direction
	_search_look_target_direction = base_direction.rotated(
		Vector3.UP,
		deg_to_rad(magnitude * sign_value)
	).normalized()
	_start_search_timed_action(
		SEARCH_ACTION_LOOK_TURN,
		search_look_turn_min,
		search_look_turn_max,
		801
	)


func _start_search_timed_action(
	action: StringName,
	minimum_seconds: float,
	maximum_seconds: float,
	salt: int
) -> void:
	var low: float = maxf(minf(minimum_seconds, maximum_seconds), 0.01)
	var high: float = maxf(maxf(minimum_seconds, maximum_seconds), low)
	_search_action = action
	_search_action_duration_seconds = lerpf(
		low,
		high,
		_search_random_unit(salt)
	)
	_search_action_remaining_seconds = _search_action_duration_seconds
	_search_scan_remaining_seconds = _search_action_remaining_seconds
	_search_action_serial += 1


func _complete_search_point() -> void:
	var completed_point: Vector3 = _search_points[_search_index]
	_search_visited_positions.append(completed_point)
	_search_points_visited = _search_visited_positions.size()
	_search_index += 1
	if _search_index >= _search_points.size():
		if _try_expand_search():
			_apply_navigation_for_state()
			return
		_enter_state(STATE_RECOVERING)
		return
	_begin_search_move()
	_apply_navigation_for_state()


func _set_search_motion_paused(paused: bool) -> void:
	if (
		_guard == null
		or not is_instance_valid(_guard)
		or not _guard.has_method("set_awareness_motion_profile")
	):
		return
	_guard.call(
		"set_awareness_motion_profile",
		_search_move_speed_scale,
		paused
	)


func _apply_search_action_pose() -> void:
	if (
		_guard == null
		or not is_instance_valid(_guard)
		or _search_action == SEARCH_ACTION_MOVING
	):
		return
	var direction: Vector3 = _horizontal_facing_direction()
	if _search_action == SEARCH_ACTION_LOOK_TURN:
		var duration: float = maxf(_search_action_duration_seconds, 0.01)
		var progress: float = clampf(
			1.0 - (_search_action_remaining_seconds / duration),
			0.0,
			1.0
		)
		direction = _search_look_start_direction.slerp(
			_search_look_target_direction,
			progress
		).normalized()
	elif _search_action == SEARCH_ACTION_LOOK_HOLD:
		direction = _search_look_target_direction
	else:
		return
	var look_target: Vector3 = _guard.global_position + direction
	look_target.y = _guard.global_position.y
	_guard.look_at(look_target, Vector3.UP, true)


func _horizontal_facing_direction() -> Vector3:
	if _guard == null or not is_instance_valid(_guard):
		return Vector3.FORWARD
	var direction: Vector3 = _guard.global_transform.basis.z
	direction.y = 0.0
	if direction.length_squared() <= 0.000001:
		return Vector3.FORWARD
	return direction.normalized()


func _search_evidence_facing_direction() -> Vector3:
	if _guard == null or not is_instance_valid(_guard):
		return Vector3.FORWARD
	var toward_anchor := Vector3(
		_search_anchor.x - _guard.global_position.x,
		0.0,
		_search_anchor.z - _guard.global_position.z
	)
	if toward_anchor.length_squared() <= 0.000001:
		return _horizontal_facing_direction()
	return toward_anchor.normalized()


func _search_random_unit(salt: int) -> float:
	var mixed: int = posmod(
		_search_seed * 48271
		+ (_search_stage + 1) * 69621
		+ (_search_index + 1) * 31337
		+ (_search_action_serial + 1) * 12289
		+ salt * 7919,
		2147483647
	)
	return float(mixed % 10000) / 9999.0


func _derive_search_seed(anchor: Vector3) -> int:
	var guard_id: String = (
		str(_guard.call("get_persistent_id"))
		if _guard != null and is_instance_valid(_guard)
		else ""
	)
	var semantic_key: String = "%s|%d|%d|%d|%d|%s" % [
		guard_id,
		roundi(anchor.x * 100.0),
		roundi(anchor.z * 100.0),
		_heard_count,
		_seen_count,
		str(_last_heard_kind),
	]
	return _stable_text_hash(semantic_key)


func _stable_text_hash(text: String) -> int:
	var value: int = 5381
	for index: int in text.length():
		value = posmod(
			value * 33 + text.unicode_at(index),
			2147483647
		)
	return value


func _on_gameplay_sound_heard(perception: Dictionary) -> void:
	if _guard == null or not _guard_is_conscious():
		return
	var kind: StringName = perception.get("kind", &"")
	var kind_text: String = str(kind)
	if (
		kind != &"prop.impact"
		and kind != HOSTILE_IMPACT_SOUND_KIND
		and not kind_text.begins_with("footstep.")
	):
		return

	_heard_count += 1
	_last_heard_kind = kind
	_last_heard_origin = perception.get("origin", Vector3.ZERO)
	_last_heard_strength = float(
		perception.get("propagated_strength", 0.0)
	)
	_investigation_target = _last_heard_origin
	_has_investigation_target = true

	var flat_origin := Vector3(
		_last_heard_origin.x,
		_guard.global_position.y,
		_last_heard_origin.z
	)
	if flat_origin.distance_squared_to(_guard.global_position) > 0.001:
		_guard.look_at(flat_origin, Vector3.UP, true)

	if _awareness_state == STATE_SEARCHING:
		_search_reseed_count += 1
		_enter_state(
			STATE_INVESTIGATING,
			_last_heard_origin,
			true
		)
	elif _awareness_state != STATE_ALERTED:
		if _last_heard_strength >= _effective_hearing_investigate_strength():
			_enter_state(
				STATE_INVESTIGATING,
				_last_heard_origin,
				true
			)
		else:
			_enter_state(
				STATE_SUSPICIOUS,
				_last_heard_origin,
				true
			)

	if _speech_reaction_count == 0 and _speech != null:
		if bool(_speech.call("speak_line")):
			_speech_reaction_count += 1
	_refresh_label()


func _effective_hearing_investigate_strength() -> float:
	var threshold: float = hearing_investigate_strength
	if _awareness_state != STATE_RECOVERING:
		return threshold
	var scale: float = lerpf(
		1.0,
		clampf(recovery_hearing_threshold_scale, 0.25, 1.0),
		clampf(_residual_alert_strength, 0.0, 1.0)
	)
	return threshold * scale


func _legacy_debug_state() -> StringName:
	match _awareness_state:
		STATE_UNAWARE, STATE_RECOVERING:
			return &"calm"
		STATE_SUSPICIOUS, STATE_INVESTIGATING, STATE_SEARCHING:
			return &"heard_noise"
		STATE_ALERTED:
			return (
				&"heard_noise"
				if _has_alert_loss_timer
				else &"saw_player"
			)
		STATE_INACTIVE:
			return &"inactive"
	return &"calm"


func _is_valid_search_action(action: StringName) -> bool:
	return action in [
		SEARCH_ACTION_MOVING,
		SEARCH_ACTION_ARRIVAL_PAUSE,
		SEARCH_ACTION_LOOK_TURN,
		SEARCH_ACTION_LOOK_HOLD,
		SEARCH_ACTION_BETWEEN_PAUSE,
		SEARCH_ACTION_DEPARTURE_PAUSE,
	]


func _is_valid_awareness_state(state: StringName) -> bool:
	return state in [
		STATE_UNAWARE,
		STATE_SUSPICIOUS,
		STATE_INVESTIGATING,
		STATE_SEARCHING,
		STATE_ALERTED,
		STATE_RECOVERING,
		STATE_INACTIVE,
	]


func _current_vision_vertical_limit_degrees() -> float:
	var base_limit: float = clampf(vision_vertical_angle_degrees, 10.0, 85.0)
	var engaged_limit: float = clampf(
		maxf(vision_engaged_vertical_angle_degrees, base_limit),
		base_limit,
		89.0
	)
	match _awareness_state:
		STATE_SUSPICIOUS, STATE_RECOVERING:
			return lerpf(base_limit, engaged_limit, 0.40)
		STATE_INVESTIGATING:
			return lerpf(base_limit, engaged_limit, 0.75)
		STATE_SEARCHING, STATE_ALERTED:
			return engaged_limit
		_:
			return base_limit


func _get_player_vision_target() -> Vector3:
	if _player == null or not is_instance_valid(_player):
		return Vector3.ZERO
	var head := _player.get_node_or_null("Head") as Node3D
	if head != null:
		return head.global_position

	var collision := _player.get_node_or_null(
		"CollisionShape3D"
	) as CollisionShape3D
	var capsule: CapsuleShape3D = (
		collision.shape as CapsuleShape3D
		if collision != null
		else null
	)
	if collision != null and capsule != null:
		return collision.to_global(
			Vector3(0.0, capsule.height * 0.30, 0.0)
		)
	return _player.global_position + Vector3.UP * 0.75


func _get_gameplay_time() -> float:
	if _world_session == null or not is_instance_valid(_world_session):
		return 0.0
	return float(_world_session.get("gameplay_time_seconds"))


func _sync_gameplay_clock() -> void:
	_last_gameplay_time_sample = _get_gameplay_time()


func _find_world_session() -> Node:
	var cursor: Node = get_parent()
	while cursor != null:
		if (
			cursor.has_method("queue_semantic_gameplay_event")
			and _has_property(cursor, &"gameplay_time_seconds")
		):
			return cursor
		cursor = cursor.get_parent()
	return null


func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if str(property.get("name", "")) == str(property_name):
			return true
	return false


func _guard_is_conscious() -> bool:
	if (
		_guard == null
		or not is_instance_valid(_guard)
		or not _guard.has_method("get_life_state")
	):
		return false
	return str(_guard.call("get_life_state")) == str(GUARD_LIFE_CONSCIOUS)


func _is_finite_vector(value: Vector3) -> bool:
	return (
		is_finite(value.x)
		and is_finite(value.y)
		and is_finite(value.z)
	)


func _refresh_label() -> void:
	if _status_label == null:
		return
	match _awareness_state:
		STATE_UNAWARE:
			_status_label.text = "UNAWARE"
		STATE_SUSPICIOUS:
			_status_label.text = (
				"SUSPICIOUS\n%s\n%.1fs"
				% [
					str(_last_heard_kind),
					_state_remaining_seconds,
				]
			)
		STATE_INVESTIGATING:
			_status_label.text = (
				"INVESTIGATING\n%s\n%.1fs"
				% [
					str(_last_heard_kind),
					_state_remaining_seconds,
				]
			)
		STATE_SEARCHING:
			_status_label.text = (
				"SEARCHING · %s\nr %.1f · confidence %.0f%%\n%.1fs"
				% [
					str(_search_action),
					_search_uncertainty_radius,
					_search_confidence * 100.0,
					_state_remaining_seconds,
				]
			)
		STATE_ALERTED:
			_status_label.text = (
				"ALERT / PURSUIT\nexposure %.2f"
				% _last_vision_exposure
			)
		STATE_RECOVERING:
			_status_label.text = (
				"RECOVERING\nresidual alert %.0f%%\n%.1fs"
				% [
					_residual_alert_strength * 100.0,
					_state_remaining_seconds,
				]
			)
		STATE_INACTIVE:
			_status_label.text = "ACTOR INACTIVE"
