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

@export var player_path: NodePath = NodePath("../../Player")
@export var listener_path: NodePath = NodePath("../Hearing")
@export var speech_path: NodePath = NodePath("../Speech")
@export var exposure_path: NodePath = NodePath("../../GameplayExposure")
@export var status_label_path: NodePath = NodePath("../ReactionLabel")
@export var vision_distance: float = 6.0
@export var vision_facing_dot: float = 0.30
@export var vision_suspicion_exposure_threshold: float = 0.12
@export var vision_confirm_exposure_threshold: float = 0.28
@export var hearing_investigate_strength: float = 0.16
@export var suspicion_seconds: float = 1.25
@export var investigation_seconds: float = 2.50
@export var search_seconds: float = 3.50
@export var alert_loss_seconds: float = 1.00
@export var recovery_seconds: float = 1.25

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
var _last_seen_position: Vector3 = Vector3.ZERO
var _investigation_target: Vector3 = Vector3.ZERO
var _has_investigation_target: bool = false
var _state_remaining_seconds: float = 0.0
var _alert_loss_remaining_seconds: float = 0.0
var _has_alert_loss_timer: bool = false
var _last_gameplay_time_sample: float = 0.0


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
	var heard_callable := Callable(self, "_on_gameplay_sound_heard")
	if (
		_listener != null
		and is_instance_valid(_listener)
		and _listener.is_connected(&"gameplay_sound_heard", heard_callable)
	):
		_listener.disconnect(&"gameplay_sound_heard", heard_callable)


func _physics_process(_delta: float) -> void:
	if _guard == null or not is_instance_valid(_guard):
		return
	if StringName(_guard.call("get_life_state")) != GUARD_LIFE_CONSCIOUS:
		if _awareness_state != STATE_INACTIVE:
			_enter_state(STATE_INACTIVE)
		_sync_gameplay_clock()
		return

	_advance_gameplay_timers()
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
	if StringName(_guard.call("get_life_state")) != GUARD_LIFE_CONSCIOUS:
		_enter_state(STATE_INACTIVE)
		return false

	var exposure: float = float(_exposure.call("get_current_exposure"))
	_last_vision_exposure = exposure
	_last_vision_target = _get_player_vision_target()
	_last_vision_blocked = false
	_last_vision_blocker = ""
	if exposure < vision_suspicion_exposure_threshold:
		_record_vision_loss()
		return false

	var eye: Vector3 = _guard.global_position + Vector3.UP * 1.35
	var target: Vector3 = _last_vision_target
	var to_player: Vector3 = target - eye
	var distance: float = to_player.length()
	if distance <= 0.001 or distance > vision_distance:
		_record_vision_loss()
		return false
	var direction: Vector3 = to_player / distance
	var facing: Vector3 = _guard.global_transform.basis.z.normalized()
	if facing.dot(direction) < vision_facing_dot:
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

	_last_seen_position = target
	_investigation_target = target
	_has_investigation_target = true
	_has_alert_loss_timer = false
	_alert_loss_remaining_seconds = 0.0

	if (
		exposure >= vision_confirm_exposure_threshold
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
	_last_seen_position = Vector3.ZERO
	_investigation_target = Vector3.ZERO
	_has_investigation_target = false
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
		"last_seen_position": _last_seen_position,
		"investigation_target": _investigation_target,
		"has_investigation_target": _has_investigation_target,
		"state_remaining_seconds": _state_remaining_seconds,
		"alert_loss_remaining_seconds": _alert_loss_remaining_seconds,
		"has_alert_loss_timer": _has_alert_loss_timer,
		"vision_distance": vision_distance,
		"vision_facing_dot": vision_facing_dot,
		"vision_suspicion_exposure_threshold": (
			vision_suspicion_exposure_threshold
		),
		"vision_confirm_exposure_threshold": (
			vision_confirm_exposure_threshold
		),
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
	}


func apply_semantic_state(snapshot: Dictionary) -> bool:
	var session: Node = _find_world_session()
	if (
		session != null
		and is_instance_valid(session)
		and int(session.get("state")) == WORLD_SESSION_STATE_PLAYING
	):
		return false
	if snapshot.size() != 18:
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
	):
		return false
	for key: String in [
		"last_heard_strength",
		"last_vision_exposure",
		"state_remaining_seconds",
		"alert_loss_remaining_seconds",
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
	]:
		if not _is_finite_vector(snapshot[vector_key]):
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
	_last_gameplay_time_sample = _get_gameplay_time()
	return true


func reconcile_after_restore() -> bool:
	_last_gameplay_time_sample = _get_gameplay_time()
	_apply_navigation_for_state()
	_refresh_label()
	return true


func after_restore() -> bool:
	return true


func _advance_gameplay_timers() -> void:
	var now: float = _get_gameplay_time()
	var elapsed: float = maxf(
		0.0,
		now - _last_gameplay_time_sample
	)
	_last_gameplay_time_sample = now
	if elapsed <= 0.0:
		return
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
	_awareness_state = new_state
	_has_alert_loss_timer = false
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
	_apply_navigation_for_state()
	_refresh_label()


func _apply_navigation_for_state() -> void:
	if _guard == null or not is_instance_valid(_guard):
		return
	if StringName(_guard.call("get_life_state")) != GUARD_LIFE_CONSCIOUS:
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
			if _has_investigation_target:
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


func _on_gameplay_sound_heard(perception: Dictionary) -> void:
	if _guard == null or StringName(_guard.call("get_life_state")) != GUARD_LIFE_CONSCIOUS:
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

	if _awareness_state != STATE_ALERTED:
		if _last_heard_strength >= hearing_investigate_strength:
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
		if StringName(property.get("name", "")) == property_name:
			return true
	return false


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
				"SEARCHING\n%.1fs"
				% _state_remaining_seconds
			)
		STATE_ALERTED:
			_status_label.text = (
				"ALERT / PURSUIT\nexposure %.2f"
				% _last_vision_exposure
			)
		STATE_RECOVERING:
			_status_label.text = (
				"RECOVERING\n%.1fs"
				% _state_remaining_seconds
			)
		STATE_INACTIVE:
			_status_label.text = "ACTOR INACTIVE"
