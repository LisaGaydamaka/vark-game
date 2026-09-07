class_name PlayerLedgeController
extends RefCounted


enum State {
	NONE,
	CATCHING,
	HANGING,
	CORNERING,
	MANTLING,
}


const LOOK_DIRECTION_EPSILON_SQUARED: float = 0.000001
const LEDGE_LOCAL_MATCH_MAX_WALL_ANGLE_DEGREES: float = 15.0
const MANTLE_CONTACT_PLANE_TOLERANCE_RADIUS_RATIO: float = 0.25


var body: CharacterBody3D
var head: Node3D
var player_input: PlayerInput
var support: PlayerSupport
var motor: PlayerMotor
var movement: PlayerMovement
var step_up: PlayerStepUp
var ledge_detector: PlayerLedgeDetector
var ledge_catch: PlayerLedgeCatch
var ledge_hang: PlayerLedgeHang
var ledge_corner: PlayerLedgeCorner
var ledge_mantle: PlayerMantle
var look: PlayerLook

var jump_height: float
var max_step_height: float
var max_speed: float
var ledge_jump_horizontal_speed: float
var ledge_sprint_jump_horizontal_speed: float
var ledge_max_approach_angle_degrees: float
var gravity: float
var debug_logging: bool
var minimum_air_mantle_alignment: float
var minimum_local_ledge_alignment: float

var state: int = State.NONE
var active_catch_candidate: PlayerLedgeDetector.LedgeCandidate = null
var jump_regrab_candidates: Array[PlayerLedgeDetector.LedgeCandidate] = []
var drop_regrab_candidates: Array[PlayerLedgeDetector.LedgeCandidate] = []
var failed_catch_regrab_candidates: Array[PlayerLedgeDetector.LedgeCandidate] = []
var failed_mantle_candidates: Array[PlayerLedgeDetector.LedgeCandidate] = []
var corner_release_suppression_candidates: Array[PlayerLedgeDetector.LedgeCandidate] = []


func _init(
	player_body: CharacterBody3D,
	player_head: Node3D,
	input_source: PlayerInput,
	player_support: PlayerSupport,
	player_motor: PlayerMotor,
	player_movement: PlayerMovement,
	player_step_up: PlayerStepUp,
	detector: PlayerLedgeDetector,
	catch_action: PlayerLedgeCatch,
	hang_action: PlayerLedgeHang,
	corner_action: PlayerLedgeCorner,
	mantle_action: PlayerMantle,
	player_look: PlayerLook,
	configured_jump_height: float,
	configured_max_step_height: float,
	configured_max_speed: float,
	configured_ledge_jump_horizontal_speed: float,
	configured_ledge_sprint_jump_horizontal_speed: float,
	configured_ledge_max_approach_angle_degrees: float,
	configured_gravity: float,
	configured_debug_logging: bool
) -> void:
	body = player_body
	head = player_head
	player_input = input_source
	support = player_support
	motor = player_motor
	movement = player_movement
	step_up = player_step_up
	ledge_detector = detector
	ledge_catch = catch_action
	ledge_hang = hang_action
	ledge_corner = corner_action
	ledge_mantle = mantle_action
	look = player_look
	jump_height = configured_jump_height
	max_step_height = configured_max_step_height
	max_speed = configured_max_speed
	ledge_jump_horizontal_speed = configured_ledge_jump_horizontal_speed
	ledge_sprint_jump_horizontal_speed = configured_ledge_sprint_jump_horizontal_speed
	ledge_max_approach_angle_degrees = configured_ledge_max_approach_angle_degrees
	gravity = configured_gravity
	debug_logging = configured_debug_logging

	var maximum_approach_angle: float = clampf(ledge_max_approach_angle_degrees, 0.0, 89.0)
	minimum_air_mantle_alignment = cos(deg_to_rad(maximum_approach_angle))
	minimum_local_ledge_alignment = cos(deg_to_rad(LEDGE_LOCAL_MATCH_MAX_WALL_ANGLE_DEGREES))


func is_active() -> bool:
	return state != State.NONE


func update(jump_pressed: bool, crouch_pressed: bool, delta: float) -> void:
	match state:
		State.CATCHING:
			_update_ledge_catch(crouch_pressed, delta)
		State.HANGING:
			_update_ledge_hang(jump_pressed, crouch_pressed, delta)
		State.CORNERING:
			_update_ledge_corner(jump_pressed, crouch_pressed, delta)
		State.MANTLING:
			_update_ledge_mantle(jump_pressed, crouch_pressed, delta)


func update_transition_guards() -> void:
	_update_jump_regrab_guard()
	_update_drop_regrab_guard()
	_update_failed_catch_regrab_guard()
	_update_failed_mantle_guard()
	_update_corner_release_suppression()


func try_enter_hang_from_normal(delta: float) -> bool:
	var candidates: Array[PlayerLedgeDetector.LedgeCandidate] = (
		ledge_detector.get_candidates()
	)

	for candidate: PlayerLedgeDetector.LedgeCandidate in candidates:
		if candidate == null or not candidate.hangable:
			continue
		if (
			_is_jump_regrab_blocked(candidate)
			or _is_drop_regrab_blocked(candidate)
			or _is_failed_catch_regrab_blocked(candidate)
			or _is_corner_release_suppressed(candidate)
		):
			continue

		if ledge_catch.try_start(body, candidate):
			active_catch_candidate = candidate
			step_up.cancel_traversal()
			ledge_detector.clear_candidate()
			look.enter_ledge_view(candidate.wall_normal)
			state = State.CATCHING
			ledge_catch.update(body, delta)
			_finish_ledge_catch_if_ready()
			return true
	return false


func try_enter_mantle_from_contacts(
	input_direction: Vector3,
	collisions: Array[KinematicCollision3D],
	ground_request: bool,
	air_request: bool
) -> bool:
	if collisions.is_empty() or (not ground_request and not air_request):
		return false

	var candidates: Array[PlayerLedgeDetector.LedgeCandidate] = (
		ledge_detector.get_candidates()
	)
	for candidate: PlayerLedgeDetector.LedgeCandidate in candidates:
		if candidate == null:
			continue
		if (
			_is_jump_regrab_blocked(candidate)
			or _is_drop_regrab_blocked(candidate)
			or _is_failed_catch_regrab_blocked(candidate)
			or _is_corner_release_suppressed(candidate)
			or _is_failed_mantle_blocked(candidate)
		):
			continue
		if not _candidate_matches_any_contact(candidate, collisions):
			continue

		if ground_request:
			if (
				_should_attempt_ground_mantle_contact(candidate, input_direction)
				and _try_start_free_mantle(candidate, "Ground mantle entered")
			):
				return true
			continue

		# Hangable airborne geometry remains owned by catch/hang. Even if catch
		# could not start, persistent Space may not silently convert it to mantle.
		if candidate.hangable:
			continue
		if (
			air_request
			and _should_attempt_air_mantle_contact(candidate)
			and _try_start_free_mantle(candidate, "Air mantle entered")
		):
			return true
	return false


func _candidate_matches_any_contact(
	candidate: PlayerLedgeDetector.LedgeCandidate,
	collisions: Array[KinematicCollision3D]
) -> bool:
	for collision: KinematicCollision3D in collisions:
		if collision == null:
			continue
		for collision_index: int in range(collision.get_collision_count()):
			if _candidate_matches_contact(
				candidate,
				collision,
				collision_index
			):
				return true
	return false


func _candidate_matches_contact(
	candidate: PlayerLedgeDetector.LedgeCandidate,
	collision: KinematicCollision3D,
	collision_index: int
) -> bool:
	if candidate == null or collision == null:
		return false

	var contact_normal: Vector3 = collision.get_normal(collision_index)
	var horizontal_normal := Vector3(
		contact_normal.x,
		0.0,
		contact_normal.z
	)
	if horizontal_normal.length_squared() <= LOOK_DIRECTION_EPSILON_SQUARED:
		return false
	horizontal_normal = horizontal_normal.normalized()
	if horizontal_normal.dot(candidate.wall_normal) < minimum_local_ledge_alignment:
		return false

	var candidate_rid: RID = candidate.wall_collider_rid
	var contact_rid: RID = collision.get_collider_rid(collision_index)
	if (
		candidate_rid.is_valid()
		and contact_rid.is_valid()
		and candidate_rid != contact_rid
	):
		return false

	var contact_point: Vector3 = collision.get_position(collision_index)
	var plane_tolerance: float = maxf(
		0.01,
		ledge_detector.get_capsule_radius()
		* MANTLE_CONTACT_PLANE_TOLERANCE_RADIUS_RATIO
	)
	if absf(
		(contact_point - candidate.edge_point).dot(candidate.wall_normal)
	) > plane_tolerance:
		return false

	var horizontal_delta := Vector3(
		contact_point.x - candidate.edge_point.x,
		0.0,
		contact_point.z - candidate.edge_point.z
	)
	var lateral_delta: Vector3 = horizontal_delta.slide(candidate.wall_normal)
	var lateral_limit: float = (
		ledge_detector.get_max_horizontal_reach()
		+ ledge_detector.get_capsule_radius()
	)
	return lateral_delta.length_squared() <= lateral_limit * lateral_limit


func _try_start_free_mantle(
	candidate: PlayerLedgeDetector.LedgeCandidate,
	debug_message: String
) -> bool:
	var mantle_candidate: PlayerMantle.MantleCandidate = (
		ledge_mantle.find_air_candidate(
			body,
			support,
			candidate
		)
	)
	if mantle_candidate == null or not ledge_mantle.try_start(body, mantle_candidate):
		return false

	step_up.cancel_traversal()
	ledge_detector.clear_candidate()
	look.enter_ledge_view(candidate.wall_normal)
	state = State.MANTLING
	body.velocity = Vector3.ZERO
	if debug_logging:
		print(debug_message)
	return true


func _should_attempt_ground_mantle_contact(
	candidate: PlayerLedgeDetector.LedgeCandidate,
	input_direction: Vector3
) -> bool:
	if candidate == null or step_up.is_active():
		return false
	if not _is_input_toward_candidate(candidate, input_direction):
		return false
	return _is_above_step_height(candidate)


func _should_attempt_air_mantle_contact(
	candidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	if candidate == null or step_up.is_active():
		return false
	return _is_above_step_height(candidate)


func _is_above_step_height(candidate: PlayerLedgeDetector.LedgeCandidate) -> bool:
	var feet_height: float = (
		body.global_position.y
		+ ledge_detector.get_capsule_bottom_offset()
	)
	return candidate.edge_point.y - feet_height > max_step_height


func _is_input_toward_candidate(
	candidate: PlayerLedgeDetector.LedgeCandidate,
	input_direction: Vector3
) -> bool:
	if candidate == null:
		return false
	var horizontal_input := Vector3(input_direction.x, 0.0, input_direction.z)
	if horizontal_input.length_squared() <= LOOK_DIRECTION_EPSILON_SQUARED:
		return false
	return _is_direction_toward_candidate(
		candidate,
		horizontal_input.normalized()
	)


func _is_direction_toward_candidate(
	candidate: PlayerLedgeDetector.LedgeCandidate,
	direction: Vector3
) -> bool:
	if candidate == null or direction.length_squared() <= LOOK_DIRECTION_EPSILON_SQUARED:
		return false
	var toward_wall: Vector3 = -candidate.wall_normal
	toward_wall.y = 0.0
	if toward_wall.length_squared() <= LOOK_DIRECTION_EPSILON_SQUARED:
		return false
	return (
		direction.normalized().dot(toward_wall.normalized())
		>= minimum_air_mantle_alignment
	)


func _update_ledge_catch(crouch_pressed: bool, delta: float) -> void:
	if crouch_pressed:
		var input_direction: Vector3 = player_input.get_movement_direction(head.global_transform)
		_arm_drop_regrab_candidate(active_catch_candidate)
		ledge_catch.cancel()
		active_catch_candidate = null
		look.exit_ledge_view()
		state = State.NONE
		body.velocity = Vector3.DOWN * gravity * delta
		movement.move(body, support, input_direction, false, delta)
		support.update(body)
		if debug_logging:
			print("Ledge catch dropped")
		return
	ledge_catch.update(body, delta)
	_finish_ledge_catch_if_ready()


func _finish_ledge_catch_if_ready() -> void:
	if ledge_catch.has_completed():
		var candidate: PlayerLedgeDetector.LedgeCandidate = ledge_catch.take_completed_candidate()
		active_catch_candidate = null
		if candidate != null:
			ledge_hang.start(candidate)
			state = State.HANGING
			body.velocity = Vector3.ZERO
			if debug_logging:
				print("Ledge hang entered")
			return

	if ledge_catch.has_failed():
		var failed_candidate: PlayerLedgeDetector.LedgeCandidate = ledge_catch.get_failed_candidate()
		if failed_candidate != null:
			_arm_failed_catch_regrab_candidate(failed_candidate)
		var failure_description: String = ledge_catch.take_failure_description()
		active_catch_candidate = null
		look.exit_ledge_view()
		state = State.NONE
		if debug_logging:
			print("Ledge catch failed: ", failure_description)
		return

	if not ledge_catch.is_active():
		active_catch_candidate = null
		look.exit_ledge_view()
		state = State.NONE


func _update_ledge_hang(jump_pressed: bool, crouch_pressed: bool, delta: float) -> void:
	var input_direction: Vector3 = player_input.get_movement_direction(head.global_transform)
	var action: int = ledge_hang.update(
		body,
		support,
		input_direction,
		jump_pressed,
		crouch_pressed,
		delta
	)
	if action == PlayerLedgeHang.Action.DROP:
		_arm_drop_regrab_candidate(ledge_hang.get_candidate())
		_release_ledge_to_air(input_direction, delta)
		return
	if action == PlayerLedgeHang.Action.LOST_LEDGE:
		_release_ledge_to_air(input_direction, delta)
		if debug_logging:
			print("Ledge hang lost valid geometry")
		return
	if action == PlayerLedgeHang.Action.MANTLE_REQUEST:
		var mantle_source: PlayerLedgeDetector.LedgeCandidate = ledge_hang.get_candidate()
		var mantle_candidate: PlayerMantle.MantleCandidate = ledge_mantle.find_candidate(
			body,
			support,
			mantle_source
		)
		if mantle_candidate != null and ledge_mantle.try_start(body, mantle_candidate):
			ledge_hang.cancel()
			state = State.MANTLING
			body.velocity = Vector3.ZERO
			if debug_logging:
				print("Ledge mantle entered")
			return
		_perform_no_input_hang_jump(mantle_source, delta)
		if debug_logging:
			print("Mantle invalid; performed hang jump")
		return
	if action == PlayerLedgeHang.Action.SHIMMY_BLOCKED:
		var shimmy_direction: Vector3 = ledge_hang.take_blocked_shimmy_direction()
		var corner_candidate: PlayerLedgeCorner.CornerCandidate = ledge_corner.find_candidate(
			body,
			support,
			ledge_hang.get_candidate(),
			ledge_hang.get_segment_wall_normal(),
			shimmy_direction
		)
		if corner_candidate != null and ledge_corner.try_start(body, corner_candidate):
			ledge_hang.cancel()
			state = State.CORNERING
			look.update_ledge_view_center(ledge_corner.get_current_wall_normal())
			if debug_logging:
				print("Ledge corner entered")
		return
	if action == PlayerLedgeHang.Action.DIRECTIONAL_JUMP:
		var released_candidate: PlayerLedgeDetector.LedgeCandidate = ledge_hang.get_candidate()
		_arm_jump_regrab_candidate(released_candidate)
		var horizontal_launch_speed: float = ledge_jump_horizontal_speed
		if player_input.is_sprint_pressed():
			horizontal_launch_speed = ledge_sprint_jump_horizontal_speed
		motor.apply_directional_jump(
			body,
			input_direction,
			jump_height,
			horizontal_launch_speed
		)
		ledge_hang.cancel()
		look.exit_ledge_view()
		state = State.NONE
		movement.move(body, support, input_direction, false, delta)
		support.update(body)


func _update_ledge_corner(jump_pressed: bool, crouch_pressed: bool, delta: float) -> void:
	var input_direction: Vector3 = player_input.get_movement_direction(head.global_transform)
	if crouch_pressed:
		_arm_drop_regrab_guard(ledge_corner.get_release_candidates())
		_release_corner_to_air(input_direction, delta)
		return
	if jump_pressed:
		_arm_jump_regrab_guard(ledge_corner.get_release_candidates())
		if input_direction.length_squared() > LOOK_DIRECTION_EPSILON_SQUARED:
			motor.apply_directional_jump(body, input_direction, jump_height, max_speed)
			ledge_corner.cancel()
			look.exit_ledge_view()
			state = State.NONE
			movement.move(body, support, input_direction, false, delta)
			support.update(body)
			return
		body.velocity = Vector3.ZERO
		motor.apply_jump(body, jump_height)
		ledge_corner.cancel()
		look.exit_ledge_view()
		state = State.NONE
		movement.move(body, support, Vector3.ZERO, false, delta)
		support.update(body)
		if debug_logging:
			print("Mantle unavailable during corner; performed hang jump")
		return

	if not ledge_corner.update(body, delta):
		_release_corner_to_air(input_direction, delta)
		if debug_logging:
			print("Ledge corner lost valid traversal")
		return
	look.update_ledge_view_center(ledge_corner.get_current_wall_normal())

	if ledge_corner.has_completed():
		var target_reference: PlayerLedgeDetector.LedgeCandidate = ledge_corner.get_target_candidate()
		var target_wall_normal: Vector3 = ledge_corner.get_target_wall_normal()
		var completed_candidate: PlayerLedgeDetector.LedgeCandidate = ledge_detector.find_hang_candidate_at_position(
			body,
			support,
			target_reference,
			target_wall_normal,
			body.global_position
		)
		if completed_candidate == null:
			_release_corner_to_air(input_direction, delta)
			if debug_logging:
				print("Ledge corner final hang validation failed")
			return
		ledge_corner.cancel()
		ledge_hang.start(completed_candidate)
		body.velocity = Vector3.ZERO
		state = State.HANGING
		look.update_ledge_view_center(completed_candidate.wall_normal)
		if debug_logging:
			print("Ledge corner completed")


func _update_ledge_mantle(jump_pressed: bool, crouch_pressed: bool, delta: float) -> void:
	var input_direction: Vector3 = player_input.get_movement_direction(head.global_transform)
	if crouch_pressed:
		_arm_drop_regrab_candidate(ledge_mantle.get_release_candidate())
		_release_mantle_to_air(input_direction, delta)
		return
	if jump_pressed and input_direction.length_squared() > LOOK_DIRECTION_EPSILON_SQUARED:
		_arm_jump_regrab_candidate(ledge_mantle.get_release_candidate())
		motor.apply_directional_jump(body, input_direction, jump_height, max_speed)
		ledge_mantle.cancel()
		look.exit_ledge_view()
		state = State.NONE
		movement.move(body, support, input_direction, false, delta)
		support.update(body)
		return
	if not ledge_mantle.update(body, delta):
		_arm_failed_mantle_candidate(ledge_mantle.get_release_candidate())
		_release_mantle_to_air(input_direction, delta)
		if debug_logging:
			print("Ledge mantle lost valid traversal")
		return
	if not ledge_mantle.has_completed():
		return
	body.velocity = Vector3.ZERO
	support.update(body)
	ledge_mantle.cancel()
	look.exit_ledge_view()
	state = State.NONE
	body.velocity = Vector3.ZERO
	if debug_logging:
		print("Ledge mantle completed")


func _perform_no_input_hang_jump(
	released_candidate: PlayerLedgeDetector.LedgeCandidate,
	delta: float
) -> void:
	_arm_jump_regrab_candidate(released_candidate)
	body.velocity = Vector3.ZERO
	motor.apply_jump(body, jump_height)
	ledge_hang.cancel()
	look.exit_ledge_view()
	state = State.NONE
	movement.move(body, support, Vector3.ZERO, false, delta)
	support.update(body)


func _release_mantle_to_air(input_direction: Vector3, delta: float) -> void:
	ledge_mantle.cancel()
	look.exit_ledge_view()
	state = State.NONE
	body.velocity = Vector3.DOWN * gravity * delta
	movement.move(body, support, input_direction, false, delta)
	support.update(body)


func _release_ledge_to_air(input_direction: Vector3, delta: float) -> void:
	ledge_hang.cancel()
	look.exit_ledge_view()
	state = State.NONE
	body.velocity = Vector3.DOWN * gravity * delta
	movement.move(body, support, input_direction, false, delta)
	support.update(body)


func _release_corner_to_air(input_direction: Vector3, delta: float) -> void:
	_arm_corner_release_suppression(ledge_corner.get_release_candidates())
	ledge_corner.cancel()
	look.exit_ledge_view()
	state = State.NONE
	body.velocity = Vector3.DOWN * gravity * delta
	movement.move(body, support, input_direction, false, delta)
	support.update(body)


func _arm_jump_regrab_candidate(candidate: PlayerLedgeDetector.LedgeCandidate) -> void:
	jump_regrab_candidates.clear()
	if candidate != null:
		jump_regrab_candidates.append(candidate)


func _arm_jump_regrab_guard(candidates: Array[PlayerLedgeDetector.LedgeCandidate]) -> void:
	jump_regrab_candidates.clear()
	for candidate: PlayerLedgeDetector.LedgeCandidate in candidates:
		if candidate != null:
			jump_regrab_candidates.append(candidate)


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


func _is_jump_regrab_blocked(candidate: PlayerLedgeDetector.LedgeCandidate) -> bool:
	if candidate == null:
		return false
	for guarded_candidate: PlayerLedgeDetector.LedgeCandidate in jump_regrab_candidates:
		if _is_same_local_ledge(candidate, guarded_candidate):
			return true
	return false


func _arm_drop_regrab_candidate(candidate: PlayerLedgeDetector.LedgeCandidate) -> void:
	drop_regrab_candidates.clear()
	if candidate != null:
		drop_regrab_candidates.append(candidate)


func _arm_drop_regrab_guard(candidates: Array[PlayerLedgeDetector.LedgeCandidate]) -> void:
	drop_regrab_candidates.clear()
	for candidate: PlayerLedgeDetector.LedgeCandidate in candidates:
		if candidate != null:
			drop_regrab_candidates.append(candidate)


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


func _is_drop_regrab_blocked(candidate: PlayerLedgeDetector.LedgeCandidate) -> bool:
	if candidate == null:
		return false
	for guarded_candidate: PlayerLedgeDetector.LedgeCandidate in drop_regrab_candidates:
		if _is_same_local_ledge(candidate, guarded_candidate):
			return true
	return false


func _arm_failed_catch_regrab_candidate(candidate: PlayerLedgeDetector.LedgeCandidate) -> void:
	failed_catch_regrab_candidates.clear()
	if candidate != null:
		failed_catch_regrab_candidates.append(candidate)


func _update_failed_catch_regrab_guard() -> void:
	if failed_catch_regrab_candidates.is_empty():
		return
	for candidate_index: int in range(failed_catch_regrab_candidates.size() - 1, -1, -1):
		var candidate: PlayerLedgeDetector.LedgeCandidate = failed_catch_regrab_candidates[candidate_index]
		if not _is_in_drop_regrab_region(candidate):
			failed_catch_regrab_candidates.remove_at(candidate_index)


func _is_failed_catch_regrab_blocked(candidate: PlayerLedgeDetector.LedgeCandidate) -> bool:
	if candidate == null:
		return false
	for guarded_candidate: PlayerLedgeDetector.LedgeCandidate in failed_catch_regrab_candidates:
		if _is_same_local_ledge(candidate, guarded_candidate):
			return true
	return false


func _arm_failed_mantle_candidate(candidate: PlayerLedgeDetector.LedgeCandidate) -> void:
	failed_mantle_candidates.clear()
	if candidate != null:
		failed_mantle_candidates.append(candidate)


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


func _is_failed_mantle_blocked(candidate: PlayerLedgeDetector.LedgeCandidate) -> bool:
	if candidate == null:
		return false
	for guarded_candidate: PlayerLedgeDetector.LedgeCandidate in failed_mantle_candidates:
		if _is_same_local_ledge(candidate, guarded_candidate):
			return true
	return false


func _arm_corner_release_suppression(candidates: Array[PlayerLedgeDetector.LedgeCandidate]) -> void:
	corner_release_suppression_candidates.clear()
	for candidate: PlayerLedgeDetector.LedgeCandidate in candidates:
		if candidate != null:
			corner_release_suppression_candidates.append(candidate)


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


func _is_corner_release_suppressed(candidate: PlayerLedgeDetector.LedgeCandidate) -> bool:
	if candidate == null:
		return false
	for suppressed_candidate: PlayerLedgeDetector.LedgeCandidate in corner_release_suppression_candidates:
		if _is_same_local_ledge(candidate, suppressed_candidate):
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
