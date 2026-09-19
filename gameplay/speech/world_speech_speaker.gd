class_name VarkWorldSpeechSpeaker
extends Node3D


@export var speech_line: VarkSpeechLine
@export var listener_path: NodePath = NodePath("../Player/SpeechListener")
@export var label_path: NodePath = NodePath("SpeechLabel")
@export_range(0.0, 10.0, 0.1) var auto_repeat_seconds: float = 3.0

var _world_session: Node = null
var _listener: VarkAcousticListener = null
var _label: Label3D = null
var _timer: Timer = null
var _pending_sound_kind: StringName = &""
var _queued_count: int = 0
var _heard_count: int = 0
var _last_perception: Dictionary = {}


func _ready() -> void:
	_world_session = _find_world_session()
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
	):
		return false

	_hide_line()
	_pending_sound_kind = speech_line.sound_kind
	var session_id: int = int(_world_session.get("session_id"))
	var queued: bool = bool(_world_session.call(
		"queue_gameplay_sound",
		session_id,
		speech_line.sound_kind,
		global_position,
		speech_line.gameplay_sound_strength
	))
	if queued:
		_queued_count += 1
	else:
		_pending_sound_kind = &""
	return queued


func set_auto_repeat_enabled(enabled: bool) -> void:
	if _timer == null:
		return
	if enabled and auto_repeat_seconds > 0.0:
		_timer.wait_time = auto_repeat_seconds
		_timer.start()
	else:
		_timer.stop()


func get_debug_summary() -> Dictionary:
	return {
		"line_id": speech_line.line_id if speech_line != null else &"",
		"sound_kind": speech_line.sound_kind if speech_line != null else &"",
		"queued_count": _queued_count,
		"heard_count": _heard_count,
		"label_visible": _label != null and _label.visible,
		"label_alpha": _label.modulate.a if _label != null else 0.0,
		"pending_sound_kind": _pending_sound_kind,
		"last_perception": _last_perception.duplicate(true),
	}


func _on_repeat_timeout() -> void:
	speak_line()


func _on_gameplay_sound_heard(perception: Dictionary) -> void:
	if speech_line == null or _label == null:
		return
	if perception.get("kind", &"") != _pending_sound_kind:
		return
	if _pending_sound_kind != speech_line.sound_kind:
		return

	_pending_sound_kind = &""
	_heard_count += 1
	_last_perception = perception.duplicate(true)
	_label.text = speech_line.text
	_label.modulate = Color(1.0, 1.0, 1.0, _display_alpha(perception))
	_label.visible = true


func _display_alpha(perception: Dictionary) -> float:
	var threshold: float = maxf(
		float(perception.get("hearing_threshold", 0.08)),
		0.000001
	)
	var propagated: float = maxf(
		float(perception.get("propagated_strength", 0.0)),
		0.0
	)
	var threshold_ratio: float = propagated / threshold
	return clampf(
		0.35 + 0.65 * ((threshold_ratio - 1.0) / 2.0),
		0.35,
		1.0
	)


func _hide_line() -> void:
	if _label == null:
		return
	_label.visible = false
	_label.text = ""


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
