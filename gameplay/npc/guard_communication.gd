class_name VarkGuardCommunication
extends Node


const LOCAL_WARNING_EVENT_NAME: StringName = &"npc.local_warning"
const ALARM_EVENT_NAME: StringName = &"npc.alarm_raised"
const WARNING_SOUND_KIND: StringName = &"npc.warning"
const WORLD_SESSION_STATE_PLAYING: int = 4

@export var guard_path: NodePath
@export var awareness_path: NodePath
@export var listener_path: NodePath
@export var acoustic_propagation_path: NodePath
@export var faction_id: StringName = &"guards"
@export_range(0.05, 3.0, 0.05) var warning_source_strength: float = 1.0
@export var alarm_channels: PackedStringArray = PackedStringArray()

var _guard: Node = null
var _awareness: Node = null
var _listener: Node = null
var _propagation: Node = null
var _world_session: Node = null
var _configured: bool = false
var _warnings_sent: int = 0
var _warnings_received: int = 0
var _alarms_received: int = 0
var _last_report_kind: StringName = &""
var _last_report_source_actor_id: String = ""
var _last_report_evidence_position: Vector3 = Vector3.ZERO
var _last_warning_propagated_strength: float = 0.0
var _last_warning_route_found: bool = false
var _last_error: String = ""


func _ready() -> void:
	_guard = get_node_or_null(guard_path)
	_awareness = get_node_or_null(awareness_path)
	_listener = get_node_or_null(listener_path)
	_propagation = get_node_or_null(acoustic_propagation_path)
	_world_session = _find_world_session()

	if not _validate_dependencies():
		push_error(_last_error)
		return

	var confirm_callable := Callable(self, "_on_local_alert_confirmed")
	if not _awareness.is_connected(&"local_alert_confirmed", confirm_callable):
		_awareness.connect(&"local_alert_confirmed", confirm_callable)

	var warning_registered: bool = bool(_world_session.call(
		"register_semantic_event_handler",
		LOCAL_WARNING_EVENT_NAME,
		Callable(self, "_on_local_warning")
	))
	var alarm_registered: bool = bool(_world_session.call(
		"register_semantic_event_handler",
		ALARM_EVENT_NAME,
		Callable(self, "_on_alarm_raised")
	))
	if not warning_registered or not alarm_registered:
		_last_error = "Guard communication could not register semantic event handlers."
		push_error(_last_error)
		return
	_configured = true


func _exit_tree() -> void:
	var confirm_callable := Callable(self, "_on_local_alert_confirmed")
	if (
		_awareness != null
		and is_instance_valid(_awareness)
		and _awareness.is_connected(&"local_alert_confirmed", confirm_callable)
	):
		_awareness.disconnect(&"local_alert_confirmed", confirm_callable)
	if _world_session == null or not is_instance_valid(_world_session):
		return
	if not _world_session.has_method("unregister_semantic_event_handler"):
		return
	_world_session.call(
		"unregister_semantic_event_handler",
		LOCAL_WARNING_EVENT_NAME,
		Callable(self, "_on_local_warning")
	)
	_world_session.call(
		"unregister_semantic_event_handler",
		ALARM_EVENT_NAME,
		Callable(self, "_on_alarm_raised")
	)


func get_debug_summary() -> Dictionary:
	return {
		"configured": _configured,
		"faction_id": faction_id,
		"alarm_channels": alarm_channels.duplicate(),
		"warning_source_strength": warning_source_strength,
		"warnings_sent": _warnings_sent,
		"warnings_received": _warnings_received,
		"alarms_received": _alarms_received,
		"last_report_kind": _last_report_kind,
		"last_report_source_actor_id": _last_report_source_actor_id,
		"last_report_evidence_position": _last_report_evidence_position,
		"last_warning_propagated_strength": _last_warning_propagated_strength,
		"last_warning_route_found": _last_warning_route_found,
		"last_error": _last_error,
	}


func _on_local_alert_confirmed(evidence_position: Vector3) -> void:
	if not _configured or not _is_playing_session():
		return
	if not _is_finite_vector(evidence_position):
		return
	var actor_id: String = _guard_actor_id()
	if actor_id.is_empty():
		return
	var strength: float = maxf(warning_source_strength, 0.0)
	if not is_finite(strength) or strength <= 0.0:
		return
	var payload := {
		"reporter_actor_id": actor_id,
		"faction_id": faction_id,
		"origin": (_guard as Node3D).global_position,
		"evidence_position": evidence_position,
		"strength": strength,
	}
	var queued: bool = bool(_world_session.call(
		"queue_semantic_gameplay_event",
		int(_world_session.get("session_id")),
		LOCAL_WARNING_EVENT_NAME,
		payload
	))
	if not queued:
		_last_error = "Guard communication could not queue a local warning."
		return
	_warnings_sent += 1
	# The warning is also a gameplay-significant vocal sound. Knowledge transfer
	# still uses the explicit warning payload below; the sound event carries no
	# hidden evidence position.
	_world_session.call(
		"queue_gameplay_sound",
		int(_world_session.get("session_id")),
		WARNING_SOUND_KIND,
		(_guard as Node3D).global_position,
		strength
	)


func _on_local_warning(event: Dictionary) -> bool:
	var payload: Dictionary = event.get("payload", {})
	if not _valid_warning_payload(payload):
		_last_error = "Guard communication received a malformed local warning."
		return false
	if not _configured or not _guard_is_conscious():
		return true

	var reporter_actor_id: String = str(
		payload.get("reporter_actor_id", "")
	).strip_edges()
	if reporter_actor_id == _guard_actor_id():
		return true
	if payload.get("faction_id", &"") != faction_id:
		return true

	var propagation: Dictionary = _propagation.call(
		"evaluate",
		payload.get("origin", Vector3.ZERO),
		float(payload.get("strength", 0.0)),
		(_listener as Node3D).global_position
	)
	_last_warning_route_found = bool(
		propagation.get("route_found", false)
	)
	_last_warning_propagated_strength = float(
		propagation.get("propagated_strength", 0.0)
	)
	var hearing_threshold: float = float(
		_listener.get("hearing_threshold")
	)
	if (
		not _last_warning_route_found
		or _last_warning_propagated_strength < hearing_threshold
	):
		return true

	var evidence_position: Vector3 = payload.get(
		"evidence_position",
		Vector3.ZERO
	)
	var accepted: bool = bool(_awareness.call(
		"receive_shared_evidence",
		&"warning",
		reporter_actor_id,
		evidence_position
	))
	if accepted:
		_warnings_received += 1
		_record_report(&"warning", reporter_actor_id, evidence_position)
	return true


func _on_alarm_raised(event: Dictionary) -> bool:
	var payload: Dictionary = event.get("payload", {})
	if not _valid_alarm_payload(payload):
		_last_error = "Guard communication received a malformed alarm report."
		return false
	if not _configured or not _guard_is_conscious():
		return true
	if payload.get("audience_faction_id", &"") != faction_id:
		return true

	var alarm_id: String = str(payload.get("alarm_id", &""))
	if not alarm_channels.has(alarm_id):
		return true
	var source_actor_id: String = str(
		payload.get("source_actor_id", "")
	).strip_edges()
	var evidence_position: Vector3 = payload.get(
		"evidence_position",
		Vector3.ZERO
	)
	var accepted: bool = bool(_awareness.call(
		"receive_shared_evidence",
		&"alarm",
		source_actor_id,
		evidence_position
	))
	if accepted:
		_alarms_received += 1
		_record_report(&"alarm", source_actor_id, evidence_position)
	return true


func _record_report(
	kind: StringName,
	source_actor_id: String,
	evidence_position: Vector3
) -> void:
	_last_report_kind = kind
	_last_report_source_actor_id = source_actor_id
	_last_report_evidence_position = evidence_position


func _validate_dependencies() -> bool:
	if faction_id.is_empty():
		_last_error = "Guard communication requires a non-empty faction_id."
		return false
	if _guard == null or not (_guard is Node3D):
		_last_error = "Guard communication could not resolve its guard."
		return false
	if (
		not _guard.has_method("query_actor_state")
		or not _guard.has_method("get_persistent_id")
	):
		_last_error = "Guard communication guard lacks actor identity/state seams."
		return false
	if (
		_awareness == null
		or not _awareness.has_signal(&"local_alert_confirmed")
		or not _awareness.has_method("receive_shared_evidence")
	):
		_last_error = "Guard communication could not resolve guard awareness."
		return false
	if (
		_listener == null
		or not (_listener is Node3D)
		or not _has_property(_listener, &"hearing_threshold")
	):
		_last_error = "Guard communication could not resolve an acoustic listener."
		return false
	if (
		_propagation == null
		or not _propagation.has_method("evaluate")
	):
		_last_error = "Guard communication could not resolve acoustic propagation."
		return false
	if (
		_world_session == null
		or not _world_session.has_method("queue_semantic_gameplay_event")
		or not _world_session.has_method("queue_gameplay_sound")
		or not _world_session.has_method("register_semantic_event_handler")
	):
		_last_error = "Guard communication requires a WorldSession."
		return false
	return true


func _valid_warning_payload(payload: Dictionary) -> bool:
	if payload.size() != 5:
		return false
	var strength: Variant = payload.get("strength", null)
	return (
		typeof(payload.get("reporter_actor_id", null)) == TYPE_STRING
		and typeof(payload.get("faction_id", null)) == TYPE_STRING_NAME
		and typeof(payload.get("origin", null)) == TYPE_VECTOR3
		and typeof(payload.get("evidence_position", null)) == TYPE_VECTOR3
		and (typeof(strength) == TYPE_FLOAT or typeof(strength) == TYPE_INT)
		and is_finite(float(strength))
		and float(strength) > 0.0
		and _is_finite_vector(payload.get("origin", Vector3.ZERO))
		and _is_finite_vector(payload.get("evidence_position", Vector3.ZERO))
	)


func _valid_alarm_payload(payload: Dictionary) -> bool:
	if payload.size() != 5:
		return false
	return (
		typeof(payload.get("alarm_id", null)) == TYPE_STRING_NAME
		and typeof(payload.get("audience_faction_id", null)) == TYPE_STRING_NAME
		and typeof(payload.get("source_actor_id", null)) == TYPE_STRING
		and typeof(payload.get("evidence_position", null)) == TYPE_VECTOR3
		and typeof(payload.get("serial", null)) == TYPE_INT
		and int(payload.get("serial", -1)) > 0
		and _is_finite_vector(payload.get("evidence_position", Vector3.ZERO))
	)


func _guard_actor_id() -> String:
	if _guard == null or not is_instance_valid(_guard):
		return ""
	var state: Dictionary = _guard.call("query_actor_state")
	return str(state.get("actor_id", "")).strip_edges()


func _guard_is_conscious() -> bool:
	if _guard == null or not is_instance_valid(_guard):
		return false
	var state: Dictionary = _guard.call("query_actor_state")
	return bool(state.get("awareness_eligible", false))


func _is_playing_session() -> bool:
	return (
		_world_session != null
		and is_instance_valid(_world_session)
		and int(_world_session.get("state")) == WORLD_SESSION_STATE_PLAYING
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


func _has_property(node: Object, property_name: StringName) -> bool:
	for property_info: Dictionary in node.get_property_list():
		if StringName(property_info.get("name", "")) == property_name:
			return true
	return false


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
