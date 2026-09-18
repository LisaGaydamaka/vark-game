class_name PlayerPostMantleFreezeTrace
extends RefCounted


const PRE_TRIGGER_FRAME_COUNT: int = 120
const POST_TRIGGER_FRAME_COUNT: int = 30
const MAX_BUFFER_FRAME_COUNT: int = 240
const WATCH_FRAME_COUNT: int = 180
const REQUIRED_STUCK_FRAME_COUNT: int = 8
const INPUT_STRENGTH_THRESHOLD: float = 0.25
const HORIZONTAL_DISPLACEMENT_THRESHOLD: float = 0.0025
const VERTICAL_DISPLACEMENT_THRESHOLD: float = 0.0025


var _frames: Array[Dictionary] = []
var _sequence: int = 0
var _watch_frames_remaining: int = 0
var _consecutive_stuck_frames: int = 0
var _mantle_seen_sequence: int = -1
var _mantle_completion_sequence: int = -1
var _trigger_sequence: int = -1
var _post_trigger_frames_remaining: int = 0
var _trigger_reason: String = ""


func record_frame(snapshot: Dictionary) -> Dictionary:
	var frame: Dictionary = snapshot.duplicate(true)
	frame["sequence"] = _sequence
	_sequence += 1
	_frames.append(frame)
	while _frames.size() > MAX_BUFFER_FRAME_COUNT:
		_frames.pop_front()

	var sequence: int = int(frame["sequence"])
	var traversal_before: String = str(frame.get("traversal_before", ""))
	var traversal_after: String = str(frame.get("traversal_after", ""))
	if traversal_before == "mantling" or traversal_after == "mantling":
		_note_mantle_activity(sequence)
	if traversal_before == "mantling" and traversal_after == "normal":
		_mantle_completion_sequence = sequence
		_watch_frames_remaining = maxi(_watch_frames_remaining, WATCH_FRAME_COUNT)

	if _trigger_sequence >= 0:
		if sequence > _trigger_sequence:
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

	_trigger_sequence = sequence
	_trigger_reason = _classify_stuck_frame(frame)
	_post_trigger_frames_remaining = POST_TRIGGER_FRAME_COUNT
	return _build_capture(false)


func get_debug_state() -> Dictionary:
	return {
		"watching": _watch_frames_remaining > 0,
		"watch_frames_remaining": _watch_frames_remaining,
		"consecutive_stuck_frames": _consecutive_stuck_frames,
		"mantle_seen_sequence": _mantle_seen_sequence,
		"mantle_completion_sequence": _mantle_completion_sequence,
		"trigger_sequence": _trigger_sequence,
		"trigger_reason": _trigger_reason,
		"post_trigger_frames_remaining": _post_trigger_frames_remaining,
		"buffered_frame_count": _frames.size(),
	}


func _note_mantle_activity(sequence: int) -> void:
	if _mantle_seen_sequence < 0:
		_mantle_seen_sequence = sequence
		_consecutive_stuck_frames = 0
	_watch_frames_remaining = maxi(_watch_frames_remaining, WATCH_FRAME_COUNT)


func _is_stuck_frame(frame: Dictionary) -> bool:
	var raw_strength: float = float(frame.get("raw_input_strength", 0.0))
	var command_strength: float = float(frame.get("command_strength", 0.0))
	if maxf(raw_strength, command_strength) < INPUT_STRENGTH_THRESHOLD:
		return false
	if (
		float(frame.get("horizontal_displacement", 0.0))
		> HORIZONTAL_DISPLACEMENT_THRESHOLD
	):
		return false

	var traversal_after: String = str(frame.get("traversal_after", ""))
	if traversal_after == "normal":
		# Do not require grounded/support truth here. A visually completed mantle
		# that failed to reacquire support is one of the failure classes we need
		# the trace to distinguish.
		return true
	if traversal_after != "mantling":
		return false

	# A healthy lift phase may have almost no horizontal motion, so active mantle
	# is considered stalled only when vertical progress is also negligible. This
	# captures a mantle that never exits after reaching/pressing against the top.
	return (
		absf(float(frame.get("vertical_displacement", 0.0)))
		<= VERTICAL_DISPLACEMENT_THRESHOLD
	)


func _classify_stuck_frame(frame: Dictionary) -> String:
	var raw_strength: float = float(frame.get("raw_input_strength", 0.0))
	var command_strength: float = float(frame.get("command_strength", 0.0))
	if raw_strength >= INPUT_STRENGTH_THRESHOLD and command_strength < INPUT_STRENGTH_THRESHOLD:
		return "raw WASD is held but the sampled locomotion command is neutral"
	if str(frame.get("traversal_after", "")) == "mantling":
		return "mantle ownership remained active with negligible movement"
	if not bool(frame.get("support_valid", false)):
		return "traversal exited but support was not reacquired while movement stalled"
	return "post-mantle locomotion input was present but horizontal movement stalled"


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
		"format": "vark.post_mantle_freeze_trace.v2",
		"reason": _trigger_reason,
		"complete": complete,
		"mantle_seen_sequence": _mantle_seen_sequence,
		"mantle_completion_sequence": _mantle_completion_sequence,
		"trigger_sequence": _trigger_sequence,
		"required_stuck_frames": REQUIRED_STUCK_FRAME_COUNT,
		"input_strength_threshold": INPUT_STRENGTH_THRESHOLD,
		"horizontal_displacement_threshold": HORIZONTAL_DISPLACEMENT_THRESHOLD,
		"vertical_displacement_threshold": VERTICAL_DISPLACEMENT_THRESHOLD,
		"frames": selected_frames,
	}


func _reset_watch_state() -> void:
	_watch_frames_remaining = 0
	_consecutive_stuck_frames = 0
	_mantle_seen_sequence = -1
	_mantle_completion_sequence = -1
	_trigger_sequence = -1
	_trigger_reason = ""
	_post_trigger_frames_remaining = 0
