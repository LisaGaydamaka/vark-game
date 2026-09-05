class_name PlayerLedgeHang
extends RefCounted


const MOTION_EPSILON_SQUARED: float = 0.000001
const SHIMMY_SPEED_RATIO: float = 0.5
const SHIMMY_INTENT_DEADZONE: float = 0.2
const MANTLE_INTENT_THRESHOLD: float = 0.35
const HANG_JUMP_AWAY_SPEED_RATIO: float = 0.5


enum Action {
	NONE,
	DROP,
	JUMP,
	MANTLE,
}


var max_speed: float
var air_max_speed: float
var jump_height: float
var gravity: float
var detector: PlayerLedgeDetector

var active_candidate: PlayerLedgeDetector.LedgeCandidate = null


func _init(
	p_max_speed: float,
	p_air_max_speed: float,
	p_jump_height: float,
	p_gravity: float,
	p_detector: PlayerLedgeDetector
) -> void:
	max_speed = p_max_speed
	air_max_speed = p_air_max_speed
	jump_height = p_jump_height
	gravity = p_gravity
	detector = p_detector

	assert(
		max_speed >= 0.0,
		"PlayerLedgeHang requires max_speed to be non-negative."
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
		var toward_wall_strength: float = (
			input_direction.dot(
				-active_candidate.wall_normal
			)
		)

		if toward_wall_strength >= MANTLE_INTENT_THRESHOLD:
			return Action.MANTLE

		return Action.JUMP

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

	if absf(ledge_intent) <= SHIMMY_INTENT_DEADZONE:
		return

	var direction_sign: float = 1.0

	if ledge_intent < 0.0:
		direction_sign = -1.0

	var shimmy_speed: float = (
		max_speed
		* SHIMMY_SPEED_RATIO
	)
	var proposed_position: Vector3 = (
		player.global_position
		+ active_candidate.ledge_direction
		* direction_sign
		* shimmy_speed
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
		return

	active_candidate = next_candidate


func apply_jump_away(
	player: CharacterBody3D
) -> void:
	if active_candidate == null:
		return

	var jump_speed: float = sqrt(
		2.0
		* gravity
		* maxf(jump_height, 0.0)
	)
	var away_speed: float = minf(
		air_max_speed,
		jump_speed
		* HANG_JUMP_AWAY_SPEED_RATIO
	)
	var vertical_speed_squared: float = maxf(
		0.0,
		jump_speed * jump_speed
		- away_speed * away_speed
	)
	var vertical_speed: float = sqrt(
		vertical_speed_squared
	)

	player.velocity = (
		active_candidate.wall_normal
		* away_speed
		+ Vector3.UP
		* vertical_speed
	)

	cancel()


func is_active() -> bool:
	return active_candidate != null


func get_candidate() -> PlayerLedgeDetector.LedgeCandidate:
	return active_candidate


func cancel() -> void:
	active_candidate = null
