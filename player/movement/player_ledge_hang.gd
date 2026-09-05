class_name PlayerLedgeHang
extends RefCounted


const MOTION_EPSILON_SQUARED: float = 0.000001
const SHIMMY_SPEED_RATIO: float = 0.5
const SHIMMY_INTENT_DEADZONE: float = 0.2


enum Action {
	NONE,
	DROP,
	DIRECTIONAL_JUMP,
	MANTLE_REQUEST,
}


var max_speed: float
var acceleration: float
var air_max_speed: float
var jump_height: float
var gravity: float
var detector: PlayerLedgeDetector

var active_candidate: PlayerLedgeDetector.LedgeCandidate = null
var shimmy_velocity: float = 0.0


func _init(
	p_max_speed: float,
	p_acceleration: float,
	p_air_max_speed: float,
	p_jump_height: float,
	p_gravity: float,
	p_detector: PlayerLedgeDetector
) -> void:
	max_speed = p_max_speed
	acceleration = p_acceleration
	air_max_speed = p_air_max_speed
	jump_height = p_jump_height
	gravity = p_gravity
	detector = p_detector

	assert(
		max_speed >= 0.0,
		"PlayerLedgeHang requires max_speed to be non-negative."
	)
	assert(
		acceleration >= 0.0,
		"PlayerLedgeHang requires acceleration to be non-negative."
	)
	assert(
		air_max_speed >= 0.0,
		"PlayerLedgeHang requires air_max_speed to be non-negative."
	)
	assert(
		jump_height >= 0.0,
		"PlayerLedgeHang requires jump_height to be non-negative."
	)
	assert(
		gravity > 0.0,
		"PlayerLedgeHang requires gravity to be greater than zero."
	)


func start(
	candidate: PlayerLedgeDetector.LedgeCandidate
) -> void:
	active_candidate = candidate
	shimmy_velocity = 0.0


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

	if drop_pressed:
		return Action.DROP

	if jump_pressed:
		if (
			input_direction.length_squared()
			> MOTION_EPSILON_SQUARED
		):
			return Action.DIRECTIONAL_JUMP

		return Action.MANTLE_REQUEST

	update_shimmy(
		player,
		support,
		input_direction,
		delta
	)
	return Action.NONE


func update_shimmy(
	player: CharacterBody3D,
	support: PlayerSupport,
	input_direction: Vector3,
	delta: float
) -> void:
	if active_candidate == null:
		return

	var ledge_intent: float = input_direction.dot(
		active_candidate.ledge_direction
	)
	var target_speed: float = 0.0
	var maximum_shimmy_speed: float = get_max_shimmy_speed()

	if absf(ledge_intent) > SHIMMY_INTENT_DEADZONE:
		if ledge_intent > 0.0:
			target_speed = maximum_shimmy_speed
		else:
			target_speed = -maximum_shimmy_speed

	update_shimmy_velocity(
		target_speed,
		delta
	)

	if absf(shimmy_velocity) <= 0.000001:
		shimmy_velocity = 0.0
		return

	var proposed_position: Vector3 = (
		player.global_position
		+ active_candidate.ledge_direction
		* shimmy_velocity
		* delta
	)
	var next_candidate: PlayerLedgeDetector.LedgeCandidate = (
		detector.find_hang_candidate_at_position(
			player,
			support,
			active_candidate,
			proposed_position
		)
	)

	if next_candidate == null:
		shimmy_velocity = 0.0
		return

	var motion: Vector3 = (
		next_candidate.hang_position
		- player.global_position
	)

	if motion.length_squared() <= MOTION_EPSILON_SQUARED:
		active_candidate = next_candidate
		return

	var collision: KinematicCollision3D = (
		player.move_and_collide(motion)
	)

	if collision != null:
		shimmy_velocity = 0.0
		return

	active_candidate = next_candidate


func update_shimmy_velocity(
	target_speed: float,
	delta: float
) -> void:
	if max_speed <= 0.000001:
		shimmy_velocity = 0.0
		return

	var velocity_error: float = (
		target_speed
		- shimmy_velocity
	)
	var response_rate: float = (
		acceleration
		/ max_speed
	)
	var velocity_change: float = (
		velocity_error
		* response_rate
		* delta
	)

	if absf(velocity_change) > absf(velocity_error):
		velocity_change = velocity_error

	shimmy_velocity += velocity_change


func apply_directional_jump(
	player: CharacterBody3D,
	input_direction: Vector3
) -> void:
	if active_candidate == null:
		return

	var horizontal_input: Vector3 = Vector3(
		input_direction.x,
		0.0,
		input_direction.z
	)
	var input_strength: float = minf(
		horizontal_input.length(),
		1.0
	)
	var horizontal_velocity: Vector3 = Vector3.ZERO

	if input_strength > 0.000001:
		horizontal_velocity = (
			horizontal_input.normalized()
			* air_max_speed
			* input_strength
		)

	player.velocity = horizontal_velocity
	player.velocity.y = get_jump_speed()
	cancel()


func get_max_shimmy_speed() -> float:
	return max_speed * SHIMMY_SPEED_RATIO


func get_jump_speed() -> float:
	return sqrt(
		2.0
		* gravity
		* maxf(jump_height, 0.0)
	)


func is_active() -> bool:
	return active_candidate != null


func get_candidate() -> PlayerLedgeDetector.LedgeCandidate:
	return active_candidate


func cancel() -> void:
	active_candidate = null
	shimmy_velocity = 0.0
