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
var motion_solver: PlayerMotionSolver
var ledge_detector: PlayerLedgeDetector
var ledge_catch: PlayerLedgeCatch
var ledge_hang: PlayerLedgeHang
var ledge_corner: PlayerLedgeCorner
var ledge_mantle: PlayerMantle
var look: PlayerLook
var traversal_guard: PlayerTraversalGuard

var jump_height: float
var max_speed: float
var ledge_jump_horizontal_speed: float
var ledge_sprint_jump_horizontal_speed: float
var ledge_max_approach_angle_degrees: float
var gravity: float
var minimum_air_mantle_alignment: float
var minimum_local_ledge_alignment: float

var state: int = State.NONE
var active_catch_candidate: PlayerLedgeDetector.LedgeCandidate = null


func _init(
	player_body: CharacterBody3D,
	player_head: Node3D,
	input_source: PlayerInput,
	player_support: PlayerSupport,
	player_motor: PlayerMotor,
	player_motion_solver: PlayerMotionSolver,
	detector: PlayerLedgeDetector,
	catch_action: PlayerLedgeCatch,
	hang_action: PlayerLedgeHang,
	corner_action: PlayerLedgeCorner,
	mantle_action: PlayerMantle,
	player_look: PlayerLook,
	configured_jump_height: float,
	configured_max_speed: float,
	configured_ledge_jump_horizontal_speed: float,
	configured_ledge_sprint_jump_horizontal_speed: float,
	configured_ledge_max_approach_angle_degrees: float,
	configured_gravity: float
) -> void:
	body = player_body
	head = player_head
	player_input = input_source
	support = player_support
	motor = player_motor
	motion_solver = player_motion_solver
	ledge_detector = detector
	ledge_catch = catch_action
	ledge_hang = hang_action
	ledge_corner = corner_action
	ledge_mantle = mantle_action
	look = player_look
	jump_height = configured_jump_height
	max_speed = configured_max_speed
	ledge_jump_horizontal_speed = configured_ledge_jump_horizontal_speed
	ledge_sprint_jump_horizontal_speed = configured_ledge_sprint_jump_horizontal_speed
	ledge_max_approach_angle_degrees = configured_ledge_max_approach_angle_degrees
	gravity = configured_gravity

	var maximum_approach_angle: float = clampf(ledge_max_approach_angle_degrees, 0.0, 89.0)
	minimum_air_mantle_alignment = cos(deg_to_rad(maximum_approach_angle))
	minimum_local_ledge_alignment = cos(deg_to_rad(LEDGE_LOCAL_MATCH_MAX_WALL_ANGLE_DEGREES))
	traversal_guard = PlayerTraversalGuard.new(
		body,
		player_input,
		ledge_detector,
		minimum_local_ledge_alignment
	)


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
	traversal_guard.update()


func try_enter_hang_from_normal(delta: float) -> bool:
	var candidates: Array[PlayerLedgeDetector.LedgeCandidate] = (
		ledge_detector.get_candidates()
	)

	for candidate: PlayerLedgeDetector.LedgeCandidate in candidates:
		if candidate == null or not candidate.hangable:
			continue
		if traversal_guard.is_hang_blocked(candidate):
			continue

		if ledge_catch.try_start(body, candidate):
			active_catch_candidate = candidate
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
		if traversal_guard.is_mantle_blocked(candidate):
			continue
		if not _candidate_matches_any_contact(candidate, collisions):
			continue

		if ground_request:
			if (
				_should_attempt_ground_mantle_contact(candidate, input_direction)
				and _try_start_free_mantle(candidate)
			):
				return true
			continue

		if (
			air_request
			and _should_attempt_air_mantle_contact(candidate)
			and _try_start_free_mantle(candidate)
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
	candidate: PlayerLedgeDetector.LedgeCandidate
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

	ledge_detector.clear_candidate()
	look.enter_ledge_view(candidate.wall_normal)
	_enter_active_state(State.MANTLING)
	return true


func _should_attempt_ground_mantle_contact(
	candidate: PlayerLedgeDetector.LedgeCandidate,
	input_direction: Vector3
) -> bool:
	if candidate == null:
		return false
	return _is_input_toward_candidate(candidate, input_direction)


func _should_attempt_air_mantle_contact(
	candidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	return candidate != null


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
		traversal_guard.arm_drop_candidate(active_catch_candidate)
		ledge_catch.cancel()
		active_catch_candidate = null
		_finish_release_to_air(delta, true)
		return
	ledge_catch.update(body, delta)
	_finish_ledge_catch_if_ready()


func _finish_ledge_catch_if_ready() -> void:
	if ledge_catch.has_completed():
		var candidate: PlayerLedgeDetector.LedgeCandidate = ledge_catch.take_completed_candidate()
		active_catch_candidate = null
		if candidate != null:
			ledge_hang.start(candidate)
			_enter_active_state(State.HANGING)
			return

	if ledge_catch.has_failed():
		var failed_candidate: PlayerLedgeDetector.LedgeCandidate = ledge_catch.take_failed_candidate()
		if failed_candidate != null:
			traversal_guard.arm_failed_catch_candidate(failed_candidate)
		active_catch_candidate = null
		_exit_traversal_state()
		return

	if not ledge_catch.is_active():
		active_catch_candidate = null
		_exit_traversal_state()


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
		traversal_guard.arm_drop_candidate(ledge_hang.get_candidate())
		_release_ledge_to_air(delta)
		return
	if action == PlayerLedgeHang.Action.LOST_LEDGE:
		_release_ledge_to_air(delta)
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
			_enter_active_state(State.MANTLING)
			return
		_perform_no_input_hang_jump(mantle_source, delta)
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
		return
	if action == PlayerLedgeHang.Action.DIRECTIONAL_JUMP:
		var released_candidate: PlayerLedgeDetector.LedgeCandidate = ledge_hang.get_candidate()
		traversal_guard.arm_jump_candidate(released_candidate)
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
		_finish_release_to_air(delta, false)


func _update_ledge_corner(jump_pressed: bool, crouch_pressed: bool, delta: float) -> void:
	var input_direction: Vector3 = player_input.get_movement_direction(head.global_transform)
	if crouch_pressed:
		traversal_guard.arm_drop_candidates(ledge_corner.get_release_candidates())
		_release_corner_to_air(delta)
		return
	if jump_pressed:
		traversal_guard.arm_jump_candidates(ledge_corner.get_release_candidates())
		if input_direction.length_squared() > LOOK_DIRECTION_EPSILON_SQUARED:
			motor.apply_directional_jump(body, input_direction, jump_height, max_speed)
			ledge_corner.cancel()
			_finish_release_to_air(delta, false)
			return
		body.velocity = Vector3.ZERO
		motor.apply_jump(body, jump_height)
		ledge_corner.cancel()
		_finish_release_to_air(delta, false)
		return

	if not ledge_corner.update(body, delta):
		_release_corner_to_air(delta)
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
			_release_corner_to_air(delta)
			return
		ledge_corner.cancel()
		ledge_hang.start(completed_candidate)
		_enter_active_state(State.HANGING)
		look.update_ledge_view_center(completed_candidate.wall_normal)


func _update_ledge_mantle(jump_pressed: bool, crouch_pressed: bool, delta: float) -> void:
	var input_direction: Vector3 = player_input.get_movement_direction(head.global_transform)
	if crouch_pressed:
		traversal_guard.arm_drop_candidate(ledge_mantle.get_release_candidate())
		_release_mantle_to_air(delta)
		return
	if jump_pressed and input_direction.length_squared() > LOOK_DIRECTION_EPSILON_SQUARED:
		traversal_guard.arm_jump_candidate(ledge_mantle.get_release_candidate())
		motor.apply_directional_jump(body, input_direction, jump_height, max_speed)
		ledge_mantle.cancel()
		_finish_release_to_air(delta, false)
		return
	if not ledge_mantle.update(body, delta):
		traversal_guard.arm_failed_mantle_candidate(ledge_mantle.get_release_candidate())
		_release_mantle_to_air(delta)
		return
	if not ledge_mantle.has_completed():
		return
	body.velocity = Vector3.ZERO
	support.update(body)
	ledge_mantle.cancel()
	_exit_traversal_state()
	body.velocity = Vector3.ZERO


func _perform_no_input_hang_jump(
	released_candidate: PlayerLedgeDetector.LedgeCandidate,
	delta: float
) -> void:
	traversal_guard.arm_jump_candidate(released_candidate)
	body.velocity = Vector3.ZERO
	motor.apply_jump(body, jump_height)
	ledge_hang.cancel()
	_finish_release_to_air(delta, false)


func _release_mantle_to_air(delta: float) -> void:
	ledge_mantle.cancel()
	_finish_release_to_air(delta, true)


func _release_ledge_to_air(delta: float) -> void:
	ledge_hang.cancel()
	_finish_release_to_air(delta, true)


func _release_corner_to_air(delta: float) -> void:
	traversal_guard.arm_corner_release_suppression(
		ledge_corner.get_release_candidates()
	)
	ledge_corner.cancel()
	_finish_release_to_air(delta, true)


func _finish_release_to_air(delta: float, apply_fall_velocity: bool) -> void:
	_exit_traversal_state()
	if apply_fall_velocity:
		body.velocity = Vector3.DOWN * gravity * delta
	motion_solver.move(body, delta)
	support.update(body)


func _enter_active_state(next_state: int) -> void:
	state = next_state
	body.velocity = Vector3.ZERO


func _exit_traversal_state() -> void:
	look.exit_ledge_view()
	state = State.NONE
