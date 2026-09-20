class_name VarkNoiseMeter
extends PanelContainer


@export var emitter_path: NodePath = NodePath("../../FootstepEmitter")
@export var bar_path: NodePath = NodePath("VBox/LoudnessBar")
@export var readout_path: NodePath = NodePath("VBox/Readout")
@export_range(0.10, 2.0, 0.05) var pulse_seconds: float = 0.55

var _emitter: VarkPlayerFootstepEmitter = null
var _bar: ProgressBar = null
var _readout: Label = null
var _last_summary: Dictionary = {}
var _current_loudness: float = 0.0
var _pulse_remaining: float = 0.0
var _debug_text: String = ""


func _ready() -> void:
	_emitter = get_node_or_null(emitter_path) as VarkPlayerFootstepEmitter
	_bar = get_node_or_null(bar_path) as ProgressBar
	_readout = get_node_or_null(readout_path) as Label
	if _emitter != null:
		_emitter.gameplay_noise_emitted.connect(
			Callable(self, "_on_gameplay_noise_emitted")
		)
	refresh_now()


func _exit_tree() -> void:
	var callback := Callable(self, "_on_gameplay_noise_emitted")
	if (
		_emitter != null
		and is_instance_valid(_emitter)
		and _emitter.gameplay_noise_emitted.is_connected(callback)
	):
		_emitter.gameplay_noise_emitted.disconnect(callback)


func _process(delta: float) -> void:
	if _pulse_remaining <= 0.0:
		return
	_pulse_remaining = maxf(0.0, _pulse_remaining - delta)
	if _pulse_remaining <= 0.0:
		_current_loudness = 0.0
		_render()


func refresh_now() -> String:
	if _emitter == null or not is_instance_valid(_emitter):
		_last_summary = {}
		_current_loudness = 0.0
		_debug_text = "LOUDNESS unavailable"
		_apply_presentation()
		return _debug_text
	_last_summary = _emitter.get_debug_summary()
	_render()
	return _debug_text


func get_current_loudness() -> float:
	return _current_loudness


func get_last_summary() -> Dictionary:
	return _last_summary.duplicate(true)


func get_debug_text() -> String:
	return _debug_text


func _on_gameplay_noise_emitted(summary: Dictionary) -> void:
	_last_summary = summary.duplicate(true)
	_current_loudness = clampf(
		float(_last_summary.get("last_strength", 0.0)),
		0.0,
		1.0
	)
	_pulse_remaining = maxf(pulse_seconds, 0.10)
	_render()


func _render() -> void:
	var filled: int = clampi(roundi(_current_loudness * 10.0), 0, 10)
	var bar_text: String = ""
	for index: int in 10:
		bar_text += "#" if index < filled else "-"
	var last_strength: float = float(
		_last_summary.get("last_strength", 0.0)
	)
	var kind: String = str(_last_summary.get("last_sound_kind", &""))
	var gait: String = str(_last_summary.get("last_gait", "walking"))
	_debug_text = (
		"LOUDNESS %.2f [%s]\n"
		+ "last %.2f · %s · %s"
	) % [
		_current_loudness,
		bar_text,
		last_strength,
		kind if not kind.is_empty() else "none",
		gait,
	]
	_apply_presentation()


func _apply_presentation() -> void:
	if _bar != null and is_instance_valid(_bar):
		_bar.value = _current_loudness
	if _readout != null and is_instance_valid(_readout):
		_readout.text = _debug_text
