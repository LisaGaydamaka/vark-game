class_name VarkLightGem
extends PanelContainer


@export var exposure_path: NodePath = NodePath("../../GameplayExposure")
@export var bar_path: NodePath = NodePath("VBox/ExposureBar")
@export var readout_path: NodePath = NodePath("VBox/Readout")

var _exposure: VarkGameplayExposure = null
var _bar: ProgressBar = null
var _readout: Label = null
var _last_summary: Dictionary = {}
var _debug_text: String = ""


func _ready() -> void:
	_exposure = get_node_or_null(exposure_path) as VarkGameplayExposure
	_bar = get_node_or_null(bar_path) as ProgressBar
	_readout = get_node_or_null(readout_path) as Label
	if _exposure != null:
		_exposure.exposure_sampled.connect(
			Callable(self, "_on_exposure_sampled")
		)
	refresh_now()


func refresh_now() -> String:
	if _exposure == null or not is_instance_valid(_exposure):
		_last_summary = {}
		_debug_text = "EXPOSURE unavailable"
		_apply_presentation(0.0)
		return _debug_text
	return _render_summary(_exposure.get_exposure_summary())


func get_debug_text() -> String:
	return _debug_text


func get_last_summary() -> Dictionary:
	return _last_summary.duplicate(true)


func get_gem_value() -> float:
	return float(_last_summary.get("exposure", 0.0))


func get_filled_segments() -> int:
	return clampi(roundi(get_gem_value() * 10.0), 0, 10)


func _on_exposure_sampled(summary: Dictionary) -> void:
	_render_summary(summary)


func _render_summary(summary: Dictionary) -> String:
	_last_summary = summary.duplicate(true)
	var exposure_value: float = clampf(
		float(_last_summary.get("exposure", 0.0)),
		0.0,
		1.0
	)
	var filled: int = get_filled_segments()
	var bar_text: String = ""
	for index: int in 10:
		bar_text += "#" if index < filled else "-"

	var source_parts: PackedStringArray = []
	for light_summary: Dictionary in _last_summary.get("lights", []):
		var state: String = "ON"
		if not bool(light_summary.get("gameplay_enabled", false)):
			state = "DISABLED"
		elif not bool(light_summary.get("visible", false)):
			state = "HIDDEN"
		source_parts.append(
			"%s %s %.2f vis %d/%d"
			% [
				str(light_summary.get("light_id", &"")),
				state,
				float(light_summary.get("contribution", 0.0)),
				int(light_summary.get("visible_samples", 0)),
				int(light_summary.get("sample_count", 0)),
			]
		)
	var source_text: String = "no gameplay-light sources"
	if not source_parts.is_empty():
		source_text = " | ".join(source_parts)

	_debug_text = (
		"EXPOSURE %.2f [%s]\n"
		+ "sources %d active %d · %s"
	) % [
		exposure_value,
		bar_text,
		int(_last_summary.get("source_count", 0)),
		int(_last_summary.get("active_light_count", 0)),
		source_text,
	]
	_apply_presentation(exposure_value)
	return _debug_text


func _apply_presentation(exposure_value: float) -> void:
	if _bar != null and is_instance_valid(_bar):
		_bar.value = exposure_value
	if _readout != null and is_instance_valid(_readout):
		_readout.text = _debug_text
