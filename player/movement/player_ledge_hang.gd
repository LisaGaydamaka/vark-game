class_name PlayerLedgeHang
extends RefCounted


const PROBE_SAFE_MARGIN: float = 0.001
const PROBE_MAX_COLLISIONS: int = 8
const MOTION_EPSILON_SQUARED: float = 0.000001
const SHIMMY_SPEED_RATIO: float = 0.5
const SHIMMY_INTENT_DEADZONE: float = 0.2
const EXPECTED_WALL_CONTACT_MIN_ALIGNMENT: float = 0.95
const ATTACHMENT_REVALIDATION_INTERVAL_SECONDS: float = 1.0 / 30.0


enum Action {
	NONE,
	DROP,
	DIRECTIONAL_JUMP,
	MANTLE_REQUEST,
	SHIMMY_BLOCKED,
	LOST_LEDGE,
}


var max_speed: float
var acceleration: float
var detector: PlayerLedgeDetector

var active_candidate: PlayerLedgeDetector.LedgeCandidate = null
var segment_wall_normal: Vector3 = Vector3.ZERO
var segment_ledge_direction: Vector3 = Vector3.ZERO
var segment_input_direction: Vector3 = Vector3.ZERO
var shimmy_velocity: float = 0.0
var blocked_shimmy_direction: Vector3 = Vector3.ZERO
var blocked_endpoint_direction: Vector3 = Vector3.ZERO
var blocked_endpoint_input_released: bool = false
var attachment_revalidation_elapsed: float = 0.0


func _init(
	p_max_speed: float,
	p_acceleration: float,
	p_detector: PlayerLedgeDetector
) -> void:
	max_speed = p_max_speed
	acceleration = p_acceleration
	detector = p_detector
	assert(max_speed >= 0.0, "PlayerLedgeHang requires max_speed to be non-negative.")
	assert(acceleration >= 0.0, "PlayerLedgeHang requires acceleration to be non-negative.")
	assert(detector != null, "PlayerLedgeHang requires a PlayerLedgeDetector.")


func start(candidate: PlayerLedgeDetector.LedgeCandidate) -> void:
	set_active_candidate(candidate)
	shimmy_velocity = 0.0
	blocked_shimmy_direction = Vector3.ZERO
	attachment_revalidation_elapsed = 0.0
	clear_blocked_endpoint()


func update(
	player: CharacterBody3D,
	support: PlayerSupport,
	input_direction: Vector3,
	jump_pressed: bool,
	drop_pressed: bool,
	delta: float
) -> int:
	if active_candidate == null:
		return Action.NONE
	player.velocity = Vector3.ZERO
	blocked_shimmy_direction = Vector3.ZERO

	if drop_pressed:
		return Action.DROP
	if jump_pressed:
		if input_direction.length_squared() > MOTION_EPSILON_SQUARED:
			return Action.DIRECTIONAL_JUMP
		return Action.MANTLE_REQUEST

	attachment_revalidation_elapsed += delta
	if (
		attachment_revalidation_elapsed >= ATTACHMENT_REVALIDATION_INTERVAL_SECONDS
		and not revalidate_attachment(player, support)
	):
		return Action.LOST_LEDGE

	update_blocked_endpoint_input_state(input_direction)
	if not update_shimmy(player, support, input_direction, delta):
		return Action.LOST_LEDGE
	if blocked_shimmy_direction.length_squared() > MOTION_EPSILON_SQUARED:
		return Action.SHIMMY_BLOCKED
	return Action.NONE


func revalidate_attachment(player: CharacterBody3D, support: PlayerSupport) -> bool:
	if active_candidate == null:
		return false
	var refreshed_candidate: PlayerLedgeDetector.LedgeCandidate = (
		detector.find_attachment_candidate_at_position(
			player,
			support,
			active_candidate,
			segment_wall_normal,
			player.global_position
		)
	)
	if refreshed_candidate == null:
		return false
	set_active_candidate(refreshed_candidate)
	attachment_revalidation_elapsed = 0.0
	return true


func update_shimmy(
	player: CharacterBody3D,
	support: PlayerSupport,
	input_direction: Vector3,
	delta: float
) -> bool:
	if active_candidate == null:
		return false
	if segment_input_direction.length_squared() <= MOTION_EPSILON_SQUARED:
		shimmy_velocity = 0.0
		return true

	var ledge_intent: float = input_direction.dot(segment_input_direction)
	var target_speed: float = 0.0
	var maximum_shimmy_speed: float = get_max_shimmy_speed()
	if absf(ledge_intent) > SHIMMY_INTENT_DEADZONE:
		target_speed = maximum_shimmy_speed if ledge_intent > 0.0 else -maximum_shimmy_speed
	update_shimmy_velocity(target_speed, delta)

	if absf(shimmy_velocity) <= 0.000001:
		shimmy_velocity = 0.0
		return true

	var input_shimmy_direction: Vector3 = segment_input_direction
	if shimmy_velocity < 0.0:
		input_shimmy_direction = -segment_input_direction

	var horizontal_path := Vector3(
		segment_ledge_direction.x,
		0.0,
		segment_ledge_direction.z
	)
	var horizontal_factor: float = horizontal_path.length()
	if horizontal_factor <= 0.000001:
		shimmy_velocity = 0.0
		return true

	# shimmy_velocity remains a horizontal tuning value. Convert it to distance
	# along the 3D ledge so flat ledges keep their existing speed while sloped
	# ledges add only the vertical component required by the geometry.
	var path_speed: float = shimmy_velocity / horizontal_factor
	var proposed_position: Vector3 = (
		player.global_position
		+ segment_ledge_direction * path_speed * delta
	)
	var next_candidate: PlayerLedgeDetector.LedgeCandidate = (
		detector.find_hang_candidate_at_position(
			player,
			support,
			active_candidate,
			segment_wall_normal,
			proposed_position
		)
	)

	if next_candidate == null:
		set_blocked_shimmy_direction(input_shimmy_direction)
		return true

	var motion: Vector3 = next_candidate.hang_position - player.global_position
	if motion.length_squared() <= MOTION_EPSILON_SQUARED:
		set_active_candidate(next_candidate)
		return true

	if not is_shimmy_path_clear(player, motion, next_candidate):
		set_blocked_shimmy_direction(input_shimmy_direction)
		return true

	if not move_shimmy_motion(player, motion, next_candidate):
		shimmy_velocity = 0.0
		if not revalidate_attachment(player, support):
			return false
		set_blocked_shimmy_direction(input_shimmy_direction)
		return true

	clear_blocked_endpoint()
	set_active_candidate(next_candidate)
	return true


func set_active_candidate(candidate: PlayerLedgeDetector.LedgeCandidate) -> void:
	active_candidate = candidate
	if candidate == null:
		segment_wall_normal = Vector3.ZERO
		segment_ledge_direction = Vector3.ZERO
		segment_input_direction = Vector3.ZERO
		return

	segment_wall_normal = Vector3(candidate.wall_normal.x, 0.0, candidate.wall_normal.z)
	if segment_wall_normal.length_squared() <= MOTION_EPSILON_SQUARED:
		segment_wall_normal = Vector3.ZERO
		segment_ledge_direction = Vector3.ZERO
		segment_input_direction = Vector3.ZERO
		return
	segment_wall_normal = segment_wall_normal.normalized()

	segment_ledge_direction = candidate.ledge_direction
	if segment_ledge_direction.length_squared() <= MOTION_EPSILON_SQUARED:
		segment_ledge_direction = detector.get_ledge_direction(
			candidate.wall_normal,
			candidate.top_normal
		)
	if segment_ledge_direction.length_squared() <= MOTION_EPSILON_SQUARED:
		segment_ledge_direction = Vector3.UP.cross(segment_wall_normal)
	if segment_ledge_direction.length_squared() <= MOTION_EPSILON_SQUARED:
		segment_ledge_direction = Vector3.ZERO
		segment_input_direction = Vector3.ZERO
		return
	segment_ledge_direction = segment_ledge_direction.normalized()

	segment_input_direction = Vector3(
		segment_ledge_direction.x,
		0.0,
		segment_ledge_direction.z
	)
	if segment_input_direction.length_squared() <= MOTION_EPSILON_SQUARED:
		segment_ledge_direction = Vector3.ZERO
		segment_input_direction = Vector3.ZERO
		return
	segment_input_direction = segment_input_direction.normalized()


func set_blocked_shimmy_direction(direction: Vector3) -> void:
	shimmy_velocity = 0.0
	var horizontal_direction := Vector3(direction.x, 0.0, direction.z)
	if horizontal_direction.length_squared() <= MOTION_EPSILON_SQUARED:
		return
	horizontal_direction = horizontal_direction.normalized()

	if blocked_endpoint_direction.length_squared() <= MOTION_EPSILON_SQUARED:
		blocked_endpoint_direction = horizontal_direction
		blocked_endpoint_input_released = false
		return
	if horizontal_direction.dot(blocked_endpoint_direction) <= 0.0:
		blocked_endpoint_direction = horizontal_direction
		blocked_endpoint_input_released = false
		return
	if not blocked_endpoint_input_released:
		return
	blocked_shimmy_direction = horizontal_direction
	clear_blocked_endpoint()


func update_blocked_endpoint_input_state(input_direction: Vector3) -> void:
	if blocked_endpoint_direction.length_squared() <= MOTION_EPSILON_SQUARED:
		return
	var endpoint_intent: float = input_direction.dot(blocked_endpoint_direction)
	if endpoint_intent < -SHIMMY_INTENT_DEADZONE:
		clear_blocked_endpoint()
		return
	if not blocked_endpoint_input_released and endpoint_intent <= SHIMMY_INTENT_DEADZONE:
		blocked_endpoint_input_released = true


func clear_blocked_endpoint() -> void:
	blocked_endpoint_direction = Vector3.ZERO
	blocked_endpoint_input_released = false


func is_shimmy_path_clear(
	player: CharacterBody3D,
	motion: Vector3,
	next_candidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	var simulated_transform: Transform3D = player.global_transform
	var remaining_motion: Vector3 = motion
	for _iteration: int in range(PROBE_MAX_COLLISIONS):
		if remaining_motion.length_squared() <= MOTION_EPSILON_SQUARED:
			return true
		var collision := KinematicCollision3D.new()
		var blocked: bool = player.test_move(
			simulated_transform,
			remaining_motion,
			collision,
			PROBE_SAFE_MARGIN,
			false,
			PROBE_MAX_COLLISIONS
		)
		if not blocked:
			return true

		var previous_motion_length_squared: float = remaining_motion.length_squared()
		var next_motion: Vector3 = collision.get_remainder()
		var collision_count: int = collision.get_collision_count()
		for collision_index: int in range(collision_count):
			if not is_expected_wall_contact(collision, collision_index, next_candidate):
				return false
			next_motion = next_motion.slide(collision.get_normal(collision_index))

		var travel: Vector3 = collision.get_travel()
		simulated_transform.origin += travel
		if (
			travel.length_squared() <= MOTION_EPSILON_SQUARED
			and next_motion.length_squared() >= previous_motion_length_squared - MOTION_EPSILON_SQUARED
		):
			return false
		remaining_motion = next_motion
	return remaining_motion.length_squared() <= MOTION_EPSILON_SQUARED


func move_shimmy_motion(
	player: CharacterBody3D,
	motion: Vector3,
	next_candidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	var remaining_motion: Vector3 = motion
	for _iteration: int in range(PROBE_MAX_COLLISIONS):
		if remaining_motion.length_squared() <= MOTION_EPSILON_SQUARED:
			return true
		var collision: KinematicCollision3D = player.move_and_collide(
			remaining_motion,
			false,
			PROBE_SAFE_MARGIN,
			false,
			PROBE_MAX_COLLISIONS
		)
		if collision == null:
			return true

		var previous_motion_length_squared: float = remaining_motion.length_squared()
		var next_motion: Vector3 = collision.get_remainder()
		var collision_count: int = collision.get_collision_count()
		for collision_index: int in range(collision_count):
			if not is_expected_wall_contact(collision, collision_index, next_candidate):
				return false
			next_motion = next_motion.slide(collision.get_normal(collision_index))

		if (
			collision.get_travel().length_squared() <= MOTION_EPSILON_SQUARED
			and next_motion.length_squared() >= previous_motion_length_squared - MOTION_EPSILON_SQUARED
		):
			return false
		remaining_motion = next_motion
	return remaining_motion.length_squared() <= MOTION_EPSILON_SQUARED


func is_expected_wall_contact(
	collision: KinematicCollision3D,
	collision_index: int,
	next_candidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	return (
		detector.is_expected_local_wall_contact(
			collision,
			collision_index,
			active_candidate,
			EXPECTED_WALL_CONTACT_MIN_ALIGNMENT
		)
		or detector.is_expected_local_wall_contact(
			collision,
			collision_index,
			next_candidate,
			EXPECTED_WALL_CONTACT_MIN_ALIGNMENT
		)
	)


func update_shimmy_velocity(target_speed: float, delta: float) -> void:
	if max_speed <= 0.000001:
		shimmy_velocity = 0.0
		return
	var velocity_error: float = target_speed - shimmy_velocity
	var response_rate: float = acceleration / max_speed
	var velocity_change: float = velocity_error * response_rate * delta
	if absf(velocity_change) > absf(velocity_error):
		velocity_change = velocity_error
	shimmy_velocity += velocity_change


func get_max_shimmy_speed() -> float:
	return max_speed * SHIMMY_SPEED_RATIO

func is_active() -> bool:
	return active_candidate != null

func get_candidate() -> PlayerLedgeDetector.LedgeCandidate:
	return active_candidate

func get_segment_wall_normal() -> Vector3:
	return segment_wall_normal

func take_blocked_shimmy_direction() -> Vector3:
	var result: Vector3 = blocked_shimmy_direction
	blocked_shimmy_direction = Vector3.ZERO
	return result


func cancel() -> void:
	active_candidate = null
	segment_wall_normal = Vector3.ZERO
	segment_ledge_direction = Vector3.ZERO
	segment_input_direction = Vector3.ZERO
	shimmy_velocity = 0.0
	blocked_shimmy_direction = Vector3.ZERO
	attachment_revalidation_elapsed = 0.0
	clear_blocked_endpoint()
