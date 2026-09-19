class_name VarkWorldSpeechSpeaker
extends Node3D


@export var speech_line: VarkSpeechLine
@export var propagation_path: NodePath = NodePath("../AcousticPropagation")
@export var listener_path: NodePath = NodePath("../Player/SpeechListener")
@export var label_path: NodePath = NodePath("SpeechLabel")
@export_range(0.0, 10.0, 0.1) var auto_repeat_seconds: float = 3.0

var _world_session: Node = null
var _propagation: VarkAcousticPropagation = null
var _listener: VarkAcousticListener = null
var _label: Label3D = null
var _timer: Timer = null

var _utterance_active: bool = false
var _utterance_remaining_seconds: float = 0.0
var _queued_boundary_serial: int = -1
var _pending_sound_kind: StringName = &""

var _queued_count: int = 0
var _heard_count: int = 0
var _presentation_update_count: int = 0
var _last_perception: Dictionary = {}
var _live_propagation: Dictionary = {}


func _ready() -> void:
	# Presentation observes the completed semantic consequence pass. The speech
	# source still emits exactly one gameplay.sound event per utterance.
	process_physics_priority = WorldSession.STABLE_BOUNDARY_PHYSICS_PRIORITY + 1
	_world_session = _find_world_session()
	_propagation = get_node_or_null(propagation_path) as VarkAcousticPropagation
	_listener = get_node_or_null(listener_path) as VarkAcousticListener
	_label = get_node_or_null(label_path) as Label3D
	if _label != null:
		_label.visible = false
		_label.text = ""
	if _listener != null:
		_listener.gameplay_sound_heard.connect(_on_gameplay_sound_heard)

	_timer = Timer.new()
	_timer.name = "SpeechRepeatTimer"
	_timer.one_shot = false
	add_child(_timer)
	_timer.timeout.connect(_on_repeat_timeout)
	_refresh_auto_repeat()


func _physics_process(delta: float) -> void:
	if not _utterance_active:
		return

	_utterance_remaining_seconds = maxf(
		_utterance_remaining_seconds - delta,
		0.0
	)
	if _utterance_remaining_seconds <= 0.0:
		_end_utterance()
		return

	if (
		_world_session == null
		or not is_instance_valid(_world_session)
		or _propagation == null
		or not is_instance_valid(_propagation)
		or _listener == null
		or not is_instance_valid(_listener)
	):
		_hide_line()
		return

	# Never reveal before the semantic sound has crossed the authoritative
	# stable consequence boundary that owns ordinary hearing.
	var current_boundary_serial: int = int(
		_world_session.call("get_stable_gameplay_boundary_serial")
	)
	if current_boundary_serial <= _queued_boundary_serial:
		_hide_line()
		return

	# The one semantic event has now completed, whether its initial listener
	# result was HEARD or MUTED. From here until expiry, presentation is a live
	# acoustic query only and does not enqueue more gameplay consequences.
	_pending_sound_kind = &""
	_update_live_presentation()


func _exit_tree() -> void:
	if (
		_listener != null
		and is_instance_valid(_listener)
		and _listener.gameplay_sound_heard.is_connected(_on_gameplay_sound_heard)
	):
		_listener.gameplay_sound_heard.disconnect(_on_gameplay_sound_heard)


func speak_line() -> bool:
	if (
		speech_line == null
		or not speech_line.is_valid_line()
		or _world_session == null
		or not is_instance_valid(_world_session)
		or _propagation == null
		or not is_instance_valid(_propagation)
		or _listener == null
		or not is_instance_valid(_listener)
	):
		return false

	_end_utterance()
	_pending_sound_kind = speech_line.sound_kind
	_queued_boundary_serial = int(
		_world_session.call("get_stable_gameplay_boundary_serial")
	)
	var session_id: int = int(_world_session.get("session_id"))
	var queued: bool = bool(_world_session.call(
		"queue_gameplay_sound",
		session_id,
		speech_line.sound_kind,
		global_position,
		speech_line.gameplay_sound_strength
	))
	if not queued:
		_pending_sound_kind = &""
		_queued_boundary_serial = -1
		return false

	_queued_count += 1
	_utterance_active = true
	_utterance_remaining_seconds = speech_line.presentation_duration_seconds
	return true


func set_auto_repeat_enabled(enabled: bool) -> void:
	if _timer == null:
		return
	if enabled and auto_repeat_seconds > 0.0:
		_timer.wait_time = auto_repeat_seconds
		_timer.start()
	else:
		_timer.stop()


func get_debug_summary() -> Dictionary:
	var threshold: float = (
		maxf(_listener.hearing_threshold, 0.000001)
		if _listener != null and is_instance_valid(_listener)
		else 0.0
	)
	var propagated: float = float(
		_live_propagation.get("propagated_strength", 0.0)
	)
	return {
		"line_id": speech_line.line_id if speech_line != null else &"",
		"sound_kind": speech_line.sound_kind if speech_line != null else &"",
		"queued_count": _queued_count,
		"heard_count": _heard_count,
		"presentation_update_count": _presentation_update_count,
		"utterance_active": _utterance_active,
		"utterance_remaining_seconds": _utterance_remaining_seconds,
		"label_visible": _label != null and _label.visible,
		"label_alpha": _label.modulate.a if _label != null else 0.0,
		"pending_sound_kind": _pending_sound_kind,
		"queued_boundary_serial": _queued_boundary_serial,
		"current_propagated_strength": propagated,
		"current_threshold_ratio": (
			propagated / threshold
			if threshold > 0.0
			else 0.0
		),
		"last_perception": _last_perception.duplicate(true),
		"live_propagation": _live_propagation.duplicate(true),
	}


func _on_repeat_timeout() -> void:
	speak_line()


func _on_gameplay_sound_heard(perception: Dictionary) -> void:
	if speech_line == null:
		return
	if perception.get("kind", &"") != _pending_sound_kind:
		return
	if _pending_sound_kind != speech_line.sound_kind:
		return

	# Record the one semantic hearing consequence. Presentation is deliberately
	# not latched to this signal: while the utterance is alive, current acoustic
	# propagation owns visibility and opacity.
	_pending_sound_kind = &""
	_heard_count += 1
	_last_perception = perception.duplicate(true)


func _update_live_presentation() -> void:
	if speech_line == null or _label == null:
		return

	_live_propagation = _propagation.evaluate(
		global_position,
		speech_line.gameplay_sound_strength,
		_listener.global_position
	)
	_presentation_update_count += 1

	var threshold: float = maxf(_listener.hearing_threshold, 0.000001)
	var propagated: float = float(
		_live_propagation.get("propagated_strength", 0.0)
	)
	var route_found: bool = bool(_live_propagation.get("route_found", false))
	var alpha: float = (
		_continuous_display_alpha(propagated, threshold)
		if route_found
		else 0.0
	)

	if alpha <= 0.0:
		_hide_line()
		return

	_label.text = speech_line.text
	_label.modulate = Color(1.0, 1.0, 1.0, alpha)
	_label.visible = true


func _continuous_display_alpha(propagated: float, threshold: float) -> float:
	if propagated <= threshold:
		return 0.0
	# Continuous fade: exactly zero at the hearing threshold, then smoothly
	# increasing with live acoustic margin. sqrt keeps marginal speech readable
	# without introducing discrete distance/fade states.
	var above_threshold_ratio: float = (
		(propagated - threshold) / maxf(threshold, 0.000001)
	)
	return sqrt(clampf(above_threshold_ratio, 0.0, 1.0))


func _end_utterance() -> void:
	_utterance_active = false
	_utterance_remaining_seconds = 0.0
	_queued_boundary_serial = -1
	_pending_sound_kind = &""
	_live_propagation.clear()
	_hide_line()


func _hide_line() -> void:
	if _label == null:
		return
	_label.visible = false
	_label.text = ""
	_label.modulate = Color(1.0, 1.0, 1.0, 0.0)


func _refresh_auto_repeat() -> void:
	if _timer == null:
		return
	if auto_repeat_seconds <= 0.0:
		_timer.stop()
		return
	_timer.wait_time = auto_repeat_seconds
	_timer.start()


func _find_world_session() -> Node:
	var cursor: Node = get_parent()
	while cursor != null:
		if cursor.has_method("queue_gameplay_sound") and cursor.has_method(
			"register_semantic_event_handler"
		):
			return cursor
		cursor = cursor.get_parent()
	return null
