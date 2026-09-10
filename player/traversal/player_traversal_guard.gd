class_name PlayerTraversalGuard
extends RefCounted


const LOOK_DIRECTION_EPSILON_SQUARED: float = 0.000001


var body: CharacterBody3D
var player_input: PlayerInput
var ledge_detector: PlayerLedgeDetector
var minimum_local_ledge_alignment: float

var jump_regrab_candidates: Array[PlayerLedgeDetector.LedgeCandidate] = []
var drop_regrab_candidates: Array[PlayerLedgeDetector.LedgeCandidate] = []
var failed_catch_regrab_candidates: Array[PlayerLedgeDetector.LedgeCandidate] = []
var failed_mantle_candidates: Array[PlayerLedgeDetector.LedgeCandidate] = []
var corner_release_suppression_candidates: Array[PlayerLedgeDetector.LedgeCandidate] = []


func _init(
	player_body: CharacterBody3D,
	input_source: PlayerInput,
	detector: PlayerLedgeDetector,
	local_ledge_alignment: float
) -> void:
	body = player_body
	player_input = input_source
	ledge_detector = detector
	minimum_local_ledge_alignment = local_ledge_alignment


func update() -> void:
	_update_jump_regrab_guard()
	_update_drop_regrab_guard()
	_update_failed_catch_regrab_guard()
	_update_failed_mantle_guard()
	_update_corner_release_suppression()


func is_hang_blocked(candidate: PlayerLedgeDetector.LedgeCandidate) -> bool:
	return (
		_is_candidate_blocked_by_guard(candidate, jump_regrab_candidates)
		or _is_candidate_blocked_by_guard(candidate, drop_regrab_candidates)
		or _is_candidate_blocked_by_guard(candidate, failed_catch_regrab_candidates)
		or _is_candidate_blocked_by_guard(
			candidate,
			corner_release_suppression_candidates
		)
	)


func is_mantle_blocked(candidate: PlayerLedgeDetector.LedgeCandidate) -> bool:
	return (
		is_hang_blocked(candidate)
		or _is_candidate_blocked_by_guard(candidate, failed_mantle_candidates)
	)


func arm_jump_candidate(candidate: PlayerLedgeDetector.LedgeCandidate) -> void:
	_replace_guard_with_candidate(jump_regrab_candidates, candidate)


func arm_jump_candidates(
	candidates: Array[PlayerLedgeDetector.LedgeCandidate]
) -> void:
	_replace_guard_with_candidates(jump_regrab_candidates, candidates)


func arm_drop_candidate(candidate: PlayerLedgeDetector.LedgeCandidate) -> void:
	_replace_guard_with_candidate(drop_regrab_candidates, candidate)


func arm_drop_candidates(
	candidates: Array[PlayerLedgeDetector.LedgeCandidate]
) -> void:
	_replace_guard_with_candidates(drop_regrab_candidates, candidates)


func arm_failed_catch_candidate(
	candidate: PlayerLedgeDetector.LedgeCandidate
) -> void:
	_replace_guard_with_candidate(failed_catch_regrab_candidates, candidate)


func arm_failed_mantle_candidate(
	candidate: PlayerLedgeDetector.LedgeCandidate
) -> void:
	_replace_guard_with_candidate(failed_mantle_candidates, candidate)


func arm_corner_release_suppression(
	candidates: Array[PlayerLedgeDetector.LedgeCandidate]
) -> void:
	_replace_guard_with_candidates(corner_release_suppression_candidates, candidates)


func _update_jump_regrab_guard() -> void:
	if jump_regrab_candidates.is_empty():
		return
	if body.velocity.y <= 0.0:
		jump_regrab_candidates.clear()
		return
	for candidate_index: int in range(jump_regrab_candidates.size() - 1, -1, -1):
		var candidate: PlayerLedgeDetector.LedgeCandidate = jump_regrab_candidates[candidate_index]
		if not _is_in_jump_regrab_region(candidate):
			jump_regrab_candidates.remove_at(candidate_index)


func _is_in_jump_regrab_region(candidate: PlayerLedgeDetector.LedgeCandidate) -> bool:
	if candidate == null:
		return false
	var edge_offset: Vector3 = candidate.edge_point - body.global_position
	var horizontal_edge_offset := Vector3(edge_offset.x, 0.0, edge_offset.z)
	var max_reach: float = ledge_detector.get_max_horizontal_reach()
	if horizontal_edge_offset.length_squared() > max_reach * max_reach:
		return false
	return (
		edge_offset.y >= ledge_detector.get_min_edge_height()
		and edge_offset.y <= ledge_detector.get_max_catch_height()
	)


func _update_drop_regrab_guard() -> void:
	if drop_regrab_candidates.is_empty():
		return
	for candidate_index: int in range(drop_regrab_candidates.size() - 1, -1, -1):
		var candidate: PlayerLedgeDetector.LedgeCandidate = drop_regrab_candidates[candidate_index]
		if not _is_in_drop_regrab_region(candidate):
			drop_regrab_candidates.remove_at(candidate_index)


func _is_in_drop_regrab_region(candidate: PlayerLedgeDetector.LedgeCandidate) -> bool:
	if candidate == null:
		return false
	var edge_offset: Vector3 = candidate.edge_point - body.global_position
	var horizontal_edge_offset := Vector3(edge_offset.x, 0.0, edge_offset.z)
	var capsule_radius: float = ledge_detector.get_capsule_radius()
	var horizontal_limit: float = ledge_detector.get_max_horizontal_reach() + capsule_radius
	if horizontal_edge_offset.length_squared() > horizontal_limit * horizontal_limit:
		return false
	return (
		edge_offset.y >= ledge_detector.get_min_edge_height() - capsule_radius
		and edge_offset.y <= ledge_detector.get_max_catch_height() + capsule_radius
	)


func _update_failed_catch_regrab_guard() -> void:
	if failed_catch_regrab_candidates.is_empty():
		return
	for candidate_index: int in range(failed_catch_regrab_candidates.size() - 1, -1, -1):
		var candidate: PlayerLedgeDetector.LedgeCandidate = failed_catch_regrab_candidates[candidate_index]
		if not _is_in_drop_regrab_region(candidate):
			failed_catch_regrab_candidates.remove_at(candidate_index)


func _update_failed_mantle_guard() -> void:
	if failed_mantle_candidates.is_empty():
		return

	# A held Space is one persistent mantle intent. A runtime failure gets one
	# attempt against this local ledge for that intent; releasing Space explicitly
	# re-arms it. Leaving the local ledge region also makes it a new opportunity.
	if not player_input.is_jump_pressed():
		failed_mantle_candidates.clear()
		return

	for candidate_index: int in range(failed_mantle_candidates.size() - 1, -1, -1):
		var candidate: PlayerLedgeDetector.LedgeCandidate = failed_mantle_candidates[candidate_index]
		if not _is_in_drop_regrab_region(candidate):
			failed_mantle_candidates.remove_at(candidate_index)


func _update_corner_release_suppression() -> void:
	if corner_release_suppression_candidates.is_empty():
		return
	for candidate_index: int in range(corner_release_suppression_candidates.size() - 1, -1, -1):
		var candidate: PlayerLedgeDetector.LedgeCandidate = corner_release_suppression_candidates[candidate_index]
		if not _should_keep_corner_release_suppression(candidate):
			corner_release_suppression_candidates.remove_at(candidate_index)


func _should_keep_corner_release_suppression(
	candidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	if candidate == null:
		return false
	var horizontal_velocity := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var toward_wall: Vector3 = -candidate.wall_normal
	if horizontal_velocity.dot(toward_wall) <= 0.0:
		return false
	var edge_offset: Vector3 = candidate.edge_point - body.global_position
	var horizontal_edge_offset := Vector3(edge_offset.x, 0.0, edge_offset.z)
	var capsule_radius: float = ledge_detector.get_capsule_radius()
	var horizontal_limit: float = ledge_detector.get_max_horizontal_reach() + capsule_radius
	if horizontal_edge_offset.length_squared() > horizontal_limit * horizontal_limit:
		return false
	return (
		edge_offset.y >= ledge_detector.get_min_edge_height() - capsule_radius
		and edge_offset.y <= ledge_detector.get_max_catch_height() + capsule_radius
	)


func _replace_guard_with_candidate(
	target: Array[PlayerLedgeDetector.LedgeCandidate],
	candidate: PlayerLedgeDetector.LedgeCandidate
) -> void:
	target.clear()
	if candidate != null:
		target.append(candidate)


func _replace_guard_with_candidates(
	target: Array[PlayerLedgeDetector.LedgeCandidate],
	candidates: Array[PlayerLedgeDetector.LedgeCandidate]
) -> void:
	target.clear()
	for candidate: PlayerLedgeDetector.LedgeCandidate in candidates:
		if candidate != null:
			target.append(candidate)


func _is_candidate_blocked_by_guard(
	candidate: PlayerLedgeDetector.LedgeCandidate,
	guarded_candidates: Array[PlayerLedgeDetector.LedgeCandidate]
) -> bool:
	if candidate == null:
		return false
	for guarded_candidate: PlayerLedgeDetector.LedgeCandidate in guarded_candidates:
		if _is_same_local_ledge(candidate, guarded_candidate):
			return true
	return false


func _is_same_local_ledge(
	first: PlayerLedgeDetector.LedgeCandidate,
	second: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	if first == null or second == null:
		return false
	var first_normal := Vector3(first.wall_normal.x, 0.0, first.wall_normal.z)
	var second_normal := Vector3(second.wall_normal.x, 0.0, second.wall_normal.z)
	if (
		first_normal.length_squared() <= LOOK_DIRECTION_EPSILON_SQUARED
		or second_normal.length_squared() <= LOOK_DIRECTION_EPSILON_SQUARED
	):
		return false
	first_normal = first_normal.normalized()
	second_normal = second_normal.normalized()
	if first_normal.dot(second_normal) < minimum_local_ledge_alignment:
		return false
	return ledge_detector.is_same_ledge_path(
		first,
		second,
		ledge_detector.get_max_horizontal_reach()
	)
