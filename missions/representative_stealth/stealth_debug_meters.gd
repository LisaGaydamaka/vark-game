class_name VarkStealthDebugMeters
extends CanvasLayer


@export var exposure_path: NodePath = NodePath("../GameplayExposure")
@export var footstep_emitter_path: NodePath = NodePath("../FootstepEmitter")
@export_range(0.05, 2.0, 0.05) var sound_hold_seconds: float = 0.20
@export_range(0.10, 3.0, 0.05) var sound_decay_seconds: float = 0.80
@export_range(0.1, 3.0, 0.05) var sound_display_max_strength: float = 1.0

var _exposure: VarkGameplayExposure = null
var _footstep_emitter: VarkPlayerFootstepEmitter = null
var _light_label: Label = null
var _light_bar: ProgressBar = null
var _sound_label: Label = null
var _sound_bar: ProgressBar = null
var _sound_display_strength: float = 0.0
var _sound_age_seconds: float = INF
var _last_sound_strength: float = 0.0
var _last_surface_id: StringName = &""
var _last_gait: String = ""
var _last_sound_kind: StringName = &""


func _ready() -> void:
	_exposure = get_node_or_null(exposure_path) as VarkGameplayExposure
	_footstep_emitter = (
		get_node_or_null(footstep_emitter_path) as VarkPlayerFootstepEmitter
	)
	_build_ui()
	if _footstep_emitter != null:
		_footstep_emitter.gameplay_noise_emitted.connect(
			_on_gameplay_noise_emitted
		)
	_refresh_ui()


func _process(delta: float) -> void:
	if _sound_age_seconds < INF:
		_sound_age_seconds += maxf(delta, 0.0)
		if _sound_age_seconds > sound_hold_seconds:
			var decay_rate: float = (
				maxf(sound_display_max_strength, 0.1)
				/ maxf(sound_decay_seconds, 0.10)
			)
			_sound_display_strength = move_toward(
				_sound_display_strength,
				0.0,
				decay_rate * maxf(delta, 0.0)
			)
	_refresh_ui()


func get_debug_state() -> Dictionary:
	return {
		"light_exposure": (
			_exposure.get_current_exposure()
			if _exposure != null and is_instance_valid(_exposure)
			else 0.0
		),
		"sound_display_strength": _sound_display_strength,
		"last_sound_strength": _last_sound_strength,
		"last_surface_id": _last_surface_id,
		"last_gait": _last_gait,
		"last_sound_kind": _last_sound_kind,
		"exposure_connected": _exposure != null and is_instance_valid(_exposure),
		"sound_connected": (
			_footstep_emitter != null and is_instance_valid(_footstep_emitter)
		),
		"ui_ready": (
			_light_label != null
			and _light_bar != null
			and _sound_label != null
			and _sound_bar != null
		),
		"light_bar_value": _light_bar.value if _light_bar != null else -1.0,
		"sound_bar_value": _sound_bar.value if _sound_bar != null else -1.0,
	}


func set_debug_visible(enabled: bool) -> void:
	visible = enabled


func _on_gameplay_noise_emitted(summary: Dictionary) -> void:
	var strength: float = maxf(float(summary.get("last_strength", 0.0)), 0.0)
	_last_sound_strength = strength
	_sound_display_strength = strength
	_sound_age_seconds = 0.0
	_last_surface_id = StringName(summary.get("last_surface_id", &""))
	_last_gait = str(summary.get("last_gait", ""))
	_last_sound_kind = StringName(summary.get("last_sound_kind", &""))
	_refresh_ui()


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.position = Vector2(16.0, 16.0)
	panel.custom_minimum_size = Vector2(310.0, 0.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(rows)

	var title := Label.new()
	title.text = "STEALTH DEBUG"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(title)

	_light_label = Label.new()
	_light_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(_light_label)

	_light_bar = ProgressBar.new()
	_light_bar.name = "LightMeter"
	_light_bar.min_value = 0.0
	_light_bar.max_value = 1.0
	_light_bar.step = 0.001
	_light_bar.show_percentage = false
	_light_bar.custom_minimum_size = Vector2(290.0, 12.0)
	_light_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(_light_bar)

	_sound_label = Label.new()
	_sound_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(_sound_label)

	_sound_bar = ProgressBar.new()
	_sound_bar.name = "SoundMeter"
	_sound_bar.min_value = 0.0
	_sound_bar.max_value = maxf(sound_display_max_strength, 0.1)
	_sound_bar.step = 0.001
	_sound_bar.show_percentage = false
	_sound_bar.custom_minimum_size = Vector2(290.0, 12.0)
	_sound_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(_sound_bar)


func _refresh_ui() -> void:
	if _light_label == null or _sound_label == null:
		return
	var exposure: float = (
		_exposure.get_current_exposure()
		if _exposure != null and is_instance_valid(_exposure)
		else 0.0
	)
	_light_label.text = "LIGHT  %.2f" % exposure
	_light_bar.value = clampf(exposure, 0.0, 1.0)

	var sound_suffix: String = ""
	if not _last_surface_id.is_empty() or not _last_gait.is_empty():
		sound_suffix = "  last %.2f  %s/%s" % [
			_last_sound_strength,
			str(_last_surface_id),
			_last_gait,
		]
	_sound_label.text = "SOUND  %.2f%s" % [
		_sound_display_strength,
		sound_suffix,
	]
	_sound_bar.max_value = maxf(sound_display_max_strength, 0.1)
	_sound_bar.value = clampf(
		_sound_display_strength,
		0.0,
		_sound_bar.max_value
	)
