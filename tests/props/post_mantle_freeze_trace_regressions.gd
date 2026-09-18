extends RefCounted


const FreezeTrace = preload("res://player/debug/player_post_mantle_freeze_trace.gd")


func run(assert_true: Callable) -> void:
	_prove_completed_mantle_stall_capture(assert_true)
	_prove_raw_input_loss_capture(assert_true)
	_prove_mantle_that_never_exits_capture(assert_true)
	_prove_normal_motion_does_not_trigger(assert_true)


func _prove_completed_mantle_stall_capture(assert_true: Callable) -> void:
	var trace: RefCounted = FreezeTrace.new()
	for frame_index: int in range(130):
		trace.call(
			"record_frame",
			_snapshot("normal", "normal", false, false, 0.0, 0.0, 0.02, 0.0, frame_index)
		)

	var capture: Dictionary = trace.call(
		"record_frame",
		_snapshot("mantling", "normal", true, true, 1.0, 1.0, 0.05, 0.01, 130)
	)
	assert_true.call(
		capture.is_empty(),
		"Post-mantle freeze trace arms without reporting a normal mantle-completion frame"
	)

	for frame_index: int in range(8):
		capture = trace.call(
			"record_frame",
			_snapshot("normal", "normal", true, true, 1.0, 1.0, 0.0001, 0.0, 131 + frame_index)
		)
	var debug_state: Dictionary = trace.call("get_debug_state")
	assert_true.call(
		not capture.is_empty()
		and not bool(capture.get("complete", true))
		and int(debug_state.get("trigger_sequence", -1)) >= 0,
		"Eight post-mantle frames with held input and negligible displacement trigger an immediate diagnostic capture"
	)

	var final_capture: Dictionary = {}
	for frame_index: int in range(30):
		var next_capture: Dictionary = trace.call(
			"record_frame",
			_snapshot("normal", "normal", true, true, 1.0, 1.0, 0.0001, 0.0, 139 + frame_index)
		)
		if not next_capture.is_empty():
			final_capture = next_capture

	var captured_frames: Array = final_capture.get("frames", [])
	var first_sequence: int = -1
	var last_sequence: int = -1
	if not captured_frames.is_empty():
		first_sequence = int((captured_frames[0] as Dictionary).get("sequence", -1))
		last_sequence = int((captured_frames[-1] as Dictionary).get("sequence", -1))
	var trigger_sequence: int = int(final_capture.get("trigger_sequence", -1))
	assert_true.call(
		not final_capture.is_empty()
		and bool(final_capture.get("complete", false))
		and str(final_capture.get("format", "")) == "vark.post_mantle_freeze_trace.v2"
		and first_sequence == max(0, trigger_sequence - 120)
		and last_sequence == trigger_sequence + 30,
		"Completed freeze trace retains the bounded pre-trigger and post-trigger frame window"
	)

	var trigger_frame: Dictionary = {}
	for frame_value: Variant in captured_frames:
		if not (frame_value is Dictionary):
			continue
		var frame: Dictionary = frame_value
		if int(frame.get("sequence", -1)) == trigger_sequence:
			trigger_frame = frame
			break
	var contact_solver: Dictionary = trigger_frame.get("contact_solver", {})
	assert_true.call(
		float(trigger_frame.get("command_strength", 0.0)) == 1.0
		and float(trigger_frame.get("horizontal_displacement", 1.0)) < 0.001
		and str(contact_solver.get("marker", "")) == "solver-snapshot",
		"Freeze trace preserves the input/displacement/contact-solver evidence from the trigger frame"
	)


func _prove_raw_input_loss_capture(assert_true: Callable) -> void:
	var trace: RefCounted = FreezeTrace.new()
	trace.call(
		"record_frame",
		_snapshot("normal", "mantling", false, false, 1.0, 1.0, 0.03, 0.03, 0)
	)
	trace.call(
		"record_frame",
		_snapshot("mantling", "normal", false, false, 1.0, 1.0, 0.03, 0.01, 1)
	)
	var capture: Dictionary = {}
	for frame_index: int in range(8):
		capture = trace.call(
			"record_frame",
			_snapshot("normal", "normal", false, false, 1.0, 0.0, 0.0001, 0.0, 2 + frame_index)
		)
	assert_true.call(
		not capture.is_empty()
		and "sampled locomotion command is neutral" in str(capture.get("reason", "")),
		"Raw held WASD still triggers the post-mantle diagnostic when the application command path goes neutral"
	)


func _prove_mantle_that_never_exits_capture(assert_true: Callable) -> void:
	var trace: RefCounted = FreezeTrace.new()
	trace.call(
		"record_frame",
		_snapshot("normal", "mantling", false, false, 1.0, 1.0, 0.02, 0.03, 0)
	)
	var capture: Dictionary = {}
	for frame_index: int in range(8):
		capture = trace.call(
			"record_frame",
			_snapshot("mantling", "mantling", false, false, 1.0, 1.0, 0.0001, 0.0001, 1 + frame_index)
		)
	assert_true.call(
		not capture.is_empty()
		and "mantle ownership remained active" in str(capture.get("reason", "")),
		"A mantle that reaches a zero-motion state but never exits is captured instead of leaving diagnostics silent"
	)


func _prove_normal_motion_does_not_trigger(assert_true: Callable) -> void:
	var trace: RefCounted = FreezeTrace.new()
	trace.call(
		"record_frame",
		_snapshot("normal", "mantling", false, false, 1.0, 1.0, 0.02, 0.03, 0)
	)
	trace.call(
		"record_frame",
		_snapshot("mantling", "normal", true, true, 1.0, 1.0, 0.05, 0.01, 1)
	)
	var capture: Dictionary = {}
	for frame_index: int in range(120):
		capture = trace.call(
			"record_frame",
			_snapshot("normal", "normal", true, true, 1.0, 1.0, 0.01, 0.0, 2 + frame_index)
		)
		if not capture.is_empty():
			break
	var debug_state: Dictionary = trace.call("get_debug_state")
	assert_true.call(
		capture.is_empty()
		and int(debug_state.get("trigger_sequence", -1)) == -1,
		"Ordinary locomotion after mantle does not create a false freeze capture"
	)


func _snapshot(
	traversal_before: String,
	traversal_after: String,
	grounded: bool,
	support_valid: bool,
	raw_input_strength: float,
	command_strength: float,
	horizontal_displacement: float,
	vertical_displacement: float,
	marker_index: int
) -> Dictionary:
	return {
		"traversal_before": traversal_before,
		"traversal_after": traversal_after,
		"grounded": grounded,
		"support_valid": support_valid,
		"raw_input_strength": raw_input_strength,
		"command_strength": command_strength,
		"horizontal_displacement": horizontal_displacement,
		"vertical_displacement": vertical_displacement,
		"contact_solver": {
			"marker": "solver-snapshot",
			"marker_index": marker_index,
		},
	}
