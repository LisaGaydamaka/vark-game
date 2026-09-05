class_name PlayerStepUp
extends RefCounted


var max_step_height: float
var max_riser_tilt_degrees: float
var debug_enabled: bool


func _init(
	p_max_step_height: float = 0.5,
	p_max_riser_tilt_degrees: float = 5.0,
	p_debug_enabled: bool = false
) -> void:
	max_step_height = p_max_step_height
	max_riser_tilt_degrees = p_max_riser_tilt_degrees
	debug_enabled = p_debug_enabled


func debug(
	message: String
) -> void:
	if debug_enabled:
		print("STEP: ", message)
