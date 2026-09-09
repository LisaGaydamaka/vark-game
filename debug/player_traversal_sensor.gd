class_name PlayerTraversalSensor
extends RefCounted


const CHAIN_WINDOW_FRAMES: int = 3


var enabled: bool = OS.is_debug_build()
var previous_mantling: bool = false
var previous_step_active: bool = false
var previous_continuation_count: int = 0
var last_mantle_end_frame: int = -1000000
var last_step_end_frame: int = -1000000


func observe(
	player: CharacterBody3D,
	step: PlayerStep,
	mantle: PlayerMantle,
	ledge_state: int
) -> void:
	if not enabled:
		return

	var frame: int = Engine.get_physics_frames()
	var mantling: bool = (
		ledge_state == PlayerLedgeController.State.MANTLING
	)
	var step_active: bool = step != null and step.is_active()

	# Record endings first so a different traversal action starting in the same
	# physics frame is reported as an immediate transition rather than unrelated.
	if previous_mantling and not mantling:
		_log_event(
			frame,
			"MANTLE_END",
			player.global_position,
			""
		)
		last_mantle_end_frame = frame

	if previous_step_active and not step_active:
		_log_event(
			frame,
			"STEP_END",
			player.global_position,
			""
		)
		last_step_end_frame = frame

	if mantling and not previous_mantling:
		var relation: String = _recent_relation(
			frame,
			last_mantle_end_frame,
			"after_mantle"
		)
		if relation.is_empty():
			relation = _recent_relation(
				frame,
				last_step_end_frame,
				"after_step"
			)
		_log_event(
			frame,
			"MANTLE_START",
			player.global_position,
			_join_details(_mantle_details(mantle), relation)
		)

	if step_active and not previous_step_active:
		var relation: String = _recent_relation(
			frame,
			last_mantle_end_frame,
			"after_mantle"
		)
		_log_event(
			frame,
			"STEP_START",
			player.global_position,
			_join_details(_step_details(step), relation)
		)

	if (
		mantling
		and mantle != null
		and mantle.edge_continuation_count > previous_continuation_count
	):
		_log_event(
			frame,
			"MANTLE_CONTINUATION",
			player.global_position,
			_mantle_details(mantle)
		)

	if mantling and step_active and not (previous_mantling and previous_step_active):
		_log_event(
			frame,
			"MANTLE_STEP_OVERLAP",
			player.global_position,
			_join_details(_mantle_details(mantle), _step_details(step))
		)

	previous_mantling = mantling
	previous_step_active = step_active
	if mantling and mantle != null:
		previous_continuation_count = mantle.edge_continuation_count
	else:
		previous_continuation_count = 0


func _mantle_details(mantle: PlayerMantle) -> String:
	if mantle == null:
		return ""
	var details: String = (
		"phase=%d continuations=%d origin=%s route_edge=%s"
		% [
			mantle.phase,
			mantle.edge_continuation_count,
			str(mantle.mantle_origin_edge_point),
			str(mantle.route_edge_point),
		]
	)
	if mantle.active_candidate != null:
		details += " active_edge=%s wall=%s" % [
			str(mantle.active_candidate.edge_point),
			str(mantle.active_candidate.wall_normal),
		]
	return details


func _step_details(step: PlayerStep) -> String:
	if step == null or step.active_candidate == null:
		return ""
	return (
		"edge=%s wall=%s height=%.4f alignment=%.4f direction=%s distance=%.4f"
		% [
			str(step.active_candidate.edge_point),
			str(step.active_candidate.wall_normal),
			step.active_candidate.step_height,
			step.active_candidate.approach_alignment,
			str(step.active_candidate.crossing_direction),
			step.active_candidate.crossing_distance,
		]
	)


func _recent_relation(
	frame: int,
	last_end_frame: int,
	label: String
) -> String:
	var frame_distance: int = frame - last_end_frame
	if frame_distance < 0 or frame_distance > CHAIN_WINDOW_FRAMES:
		return ""
	return "relation=%s frames=%d" % [label, frame_distance]


func _join_details(first: String, second: String) -> String:
	if first.is_empty():
		return second
	if second.is_empty():
		return first
	return first + " " + second


func _log_event(
	frame: int,
	event_name: String,
	position: Vector3,
	details: String
) -> void:
	var line: String = (
		"[TRAVERSAL] frame=%d event=%s pos=%s"
		% [frame, event_name, str(position)]
	)
	if not details.is_empty():
		line += " " + details
	print(line)
