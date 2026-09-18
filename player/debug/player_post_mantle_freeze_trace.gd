class_name PlayerPostMantleFreezeTrace
extends RefCounted


const PRE_TRIGGER_FRAME_COUNT: int = 120
const POST_TRIGGER_FRAME_COUNT: int = 30
const MAX_BUFFER_FRAME_COUNT: int = 180
const WATCH_FRAME_COUNT: int = 120
const REQUIRED_STUCK_FRAME_COUNT: int = 8
const INPUT_STRENGTH_THRESHOLD: float = 0.25
const HORIZONTAL_DISPLACEMENT_THRESHOLD: float = 0.0025


var _frames: Array[Dictionary] = []
var _sequence: int = 0
var _watch_frames_remaining: int = 0
var _consecutive_stuck_frames: int = 0
var _mantle_completion_sequence: int = -1
var _trigger_sequence: int = -1
var _post_trigger_frames_remaining: int = 0


func record_frame(snapshot: Dictionary) -> Dictionary:
	var frame: Dictionary = snapshot.duplicate(true)
	frame["sequence"] = _sequence
	_sequence += 1
	_frames.append(frame)
	while _frames.size() > MAX_BUFFER_FRAME_COUNT:
		_frames.pop_front()

	var traversal_before: String = str(frame.get("traversal_before", ""))
	var traversal_after: String = str(frame.get("traversal_after", ""))
	if traversal_before == "mantling" and traversal_after == "normal":
		_begin_post_mantle_watch(int(frame["sequence"]))

	if _trigger_sequence >= 0:
		if int(frame["sequence"]) > _trigger_sequence:
			_post_trigger_frames_remaining -= 1
		if _post_trigger_frames_remaining <= 0:
			var completed_capture: Dictionary = _build_capture(true)
			_reset_watch_state()
			return completed_capture
		return {}

	if _watch_frames_remaining <= 0:
		return {}
	_watch_frames_remaining -= 1

	if _is_stuck_frame(frame):
		_consecutive_stuck_frames += 1
	else:
		_consecutive_stuck_frames = 0

	if _consecutive_stuck_frames < REQUIRED_STUCK_FRAME_COUNT:
		return {}

	_trigger_sequence = int(frame["sequence"])
	_post_trigger_frames_remaining = POST_TRIGGER_FRAME_COUNT
	return _build_capture(false)


func get_debug_state() -> Dictionary:
	return {
		"watching": _watch_frames_remaining > 0,
		"watch_frames_remaining": _watch_frames_remaining,
		"consecutive_stuck_frames": _consecutive_stuck_frames,
		"mantle_completion_sequence": _mantle_completion_sequence,
		"trigger_sequence": _trigger_sequence,
		"post_trigger_frames_remaining": _post_trigger_frames_remaining,
		"buffered_frame_count": _frames.size(),
	}


func _begin_post_mantle_watch(completion_sequence: int) -> void:
	_watch_frames_remaining = WATCH_FRAME_COUNT
	_consecutive_stuck_frames = 0
	_mantle_completion_sequence = completion_sequence
	_trigger_sequence = -1
	_post_trigger_frames_remaining = 0


func _is_stuck_frame(frame: Dictionary) -> bool:
	return (
		str(frame.get("traversal_after", "")) == "normal"
		and bool(frame.get("grounded", false))
		and float(frame.get("command_strength", 0.0)) >= INPUT_STRENGTH_THRESHOLD
		and float(frame.get("horizontal_displacement", 0.0))
		<= HORIZONTAL_DISPLACEMENT_THRESHOLD
	)


func _build_capture(complete: bool) -> Dictionary:
	var earliest_sequence: int = max(0, _trigger_sequence - PRE_TRIGGER_FRAME_COUNT)
	var latest_sequence: int = (
		_trigger_sequence + POST_TRIGGER_FRAME_COUNT
		if complete
		else _trigger_sequence
	)
	var selected_frames: Array[Dictionary] = []
	for frame: Dictionary in _frames:
		var frame_sequence: int = int(frame.get("sequence", -1))
		if frame_sequence < earliest_sequence or frame_sequence > latest_sequence:
			continue
		selected_frames.append(frame.duplicate(true))

	return {
		"format": "vark.post_mantle_freeze_trace.v1",
		"reason": "grounded post-mantle input produced negligible horizontal displacement",
		"complete": complete,
		"mantle_completion_sequence": _mantle_completion_sequence,
		"trigger_sequence": _trigger_sequence,
		"required_stuck_frames": REQUIRED_STUCK_FRAME_COUNT,
		"input_strength_threshold": INPUT_STRENGTH_THRESHOLD,
		"horizontal_displacement_threshold": HORIZONTAL_DISPLACEMENT_THRESHOLD,
		"frames": selected_frames,
	}


func _reset_watch_state() -> void:
	_watch_frames_remaining = 0
	_consecutive_stuck_frames = 0
	_mantle_completion_sequence = -1
	_trigger_sequence = -1
	_post_trigger_frames_remaining = 0
