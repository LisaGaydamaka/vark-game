class_name PlayerLedgeHang
extends RefCounted


const PROBE_SAFE_MARGIN: float = 0.001
const PROBE_MAX_COLLISIONS: int = 8
const MOTION_EPSILON_SQUARED: float = 0.000001
const SHIMMY_SPEED_RATIO: float = 0.5
const SHIMMY_INTENT_DEADZONE: float = 0.2
const EXPECTED_WALL_CONTACT_MIN_ALIGNMENT: float = 0.95


enum Action {
	NONE,
	DROP,
	DIRECTIONAL_JUMP,
	MANTLE_REQUEST,
	LOST_LEDGE,
}


var max_speed: float
var acceleration: float
var jump_height: float
var gravity: float
var detector: PlayerLedgeDetector

var active_candidate: PlayerLedgeDetector.LedgeCandidate = null
var segment_wall_normal: Vector3 = Vector3.ZERO
var segment_ledge_direction: Vector3 = Vector3.ZERO
var shimmy_velocity: float = 0.0


func _init(
	p_max_speed: float,
	p_acceleration: float,
	p_jump_height: float,
	p_gravity: float,
	p_detector: PlayerLedgeDetector
) -> void:
	max_speed = p_max_speed
	acceleration = p_acceleration
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
	segment_wall_normal = candidate.wall_normal.normalized()
	segment_ledge_direction = (
		Vector3.UP.cross(segment_wall_normal)
	).normalized()


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

	if not revalidate_attachment(
		player,
		support
	):
		return Action.LOST_LEDGE

	if not update_shimmy(
		player,
		support,
		input_direction,
		delta
	):
		return Action.LOST_LEDGE

	return Action.NONE


func revalidate_attachment(
	player: CharacterBody3D,
	support: PlayerSupport
) -> bool:
	if active_candidate == null:
		return false

	var refreshed_candidate: PlayerLedgeDetector.LedgeCandidate = (
		detector.find_hang_candidate_at_position(
			player,
			support,
			active_candidate,
			segment_wall_normal,
			player.global_position
		)
	)

	if refreshed_candidate == null:
		return false

	active_candidate = refreshed_candidate
	return true


func update_shimmy(
	player: CharacterBody3D,
	support: PlayerSupport,
	input_direction: Vector3,
	delta: float
) -> bool:
	if active_candidate == null:
		return false

	var ledge_intent: float = input_direction.dot(
		segment_ledge_direction
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
		return true

	var proposed_position: Vector3 = (
		player.global_position
		+ segment_ledge_direction
		* shimmy_velocity
		* delta
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
		shimmy_velocity = 0.0
		return true

	var motion: Vector3 = (
		next_candidate.hang_position
		- player.global_position
	)

	if motion.length_squared() <= MOTION_EPSILON_SQUARED:
		active_candidate = next_candidate
		return true

	if not is_shimmy_path_clear(
		player,
		motion,
		next_candidate
	):
		shimmy_velocity = 0.0
		return true

	if not move_shimmy_motion(
		player,
		motion,
		next_candidate
	):
		shimmy_velocity = 0.0
		return revalidate_attachment(
			player,
			support
		)

	active_candidate = next_candidate
	return true


func is_shimmy_path_clear(
	player: CharacterBody3D,
	motion: Vector3,
	next_candidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	var simulated_transform: Transform3D = player.global_transform
	var remaining_motion: Vector3 = motion

	for _iteration: int in range(
		PROBE_MAX_COLLISIONS
	):
		if (
			remaining_motion.length_squared()
			<= MOTION_EPSILON_SQUARED
		):
			return true

		var collision: KinematicCollision3D = (
			KinematicCollision3D.new()
		)
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

		var previous_motion_length_squared: float = (
			remaining_motion.length_squared()
		)
		var next_motion: Vector3 = (
			collision.get_remainder()
		)
		var collision_count: int = (
			collision.get_collision_count()
		)

		for collision_index: int in range(
			collision_count
		):
			if not is_expected_wall_contact(
				collision,
				collision_index,
				next_candidate
			):
				return false

			next_motion = next_motion.slide(
				collision.get_normal(
					collision_index
				)
			)

		var travel: Vector3 = collision.get_travel()
		simulated_transform.origin += travel

		if (
			travel.length_squared()
			<= MOTION_EPSILON_SQUARED
			and next_motion.length_squared()
			>= previous_motion_length_squared
			- MOTION_EPSILON_SQUARED
		):
			return false

		remaining_motion = next_motion

	return (
		remaining_motion.length_squared()
		<= MOTION_EPSILON_SQUARED
	)


func move_shimmy_motion(
	player: CharacterBody3D,
	motion: Vector3,
	next_candidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	var remaining_motion: Vector3 = motion

	for _iteration: int in range(
		PROBE_MAX_COLLISIONS
	):
		if (
			remaining_motion.length_squared()
			<= MOTION_EPSILON_SQUARED
		):
			return true

		var collision: KinematicCollision3D = (
			player.move_and_collide(
				remaining_motion,
				false,
				PROBE_SAFE_MARGIN,
				false,
				PROBE_MAX_COLLISIONS
			)
		)

		if collision == null:
			return true

		var previous_motion_length_squared: float = (
			remaining_motion.length_squared()
		)
		var next_motion: Vector3 = (
			collision.get_remainder()
		)
		var collision_count: int = (
			collision.get_collision_count()
		)

		for collision_index: int in range(
			collision_count
		):
			if not is_expected_wall_contact(
				collision,
				collision_index,
				next_candidate
			):
				return false

			next_motion = next_motion.slide(
				collision.get_normal(
					collision_index
				)
			)

		if (
			collision.get_travel().length_squared()
			<= MOTION_EPSILON_SQUARED
			and next_motion.length_squared()
			>= previous_motion_length_squared
			- MOTION_EPSILON_SQUARED
		):
			return false

		remaining_motion = next_motion

	return (
		remaining_motion.length_squared()
		<= MOTION_EPSILON_SQUARED
	)


func is_expected_wall_contact(
	collision: KinematicCollision3D,
	collision_index: int,
	next_candidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	var collision_normal: Vector3 = (
		collision.get_normal(
			collision_index
		)
	)

	if (
		collision_normal.dot(segment_wall_normal)
		< EXPECTED_WALL_CONTACT_MIN_ALIGNMENT
	):
		return false

	return (
		matches_candidate_wall(
			collision,
			collision_index,
			active_candidate
		)
		or matches_candidate_wall(
			collision,
			collision_index,
			next_candidate
		)
	)


func matches_candidate_wall(
	collision: KinematicCollision3D,
	collision_index: int,
	candidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	if candidate == null:
		return false

	if (
		collision.get_collider_rid(
			collision_index
		)
		!= candidate.wall_collider_rid
	):
		return false

	var collider_shape_index: int = (
		collision.get_collider_shape_index(
			collision_index
		)
	)

	if (
		candidate.wall_shape_index >= 0
		and collider_shape_index >= 0
		and collider_shape_index
		!= candidate.wall_shape_index
	):
		return false

	return true


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
			* max_speed
			* input_strength
		)

	player.velocity = horizontal_velocity
	player.velocity.y = get_jump_speed()


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
	segment_wall_normal = Vector3.ZERO
	segment_ledge_direction = Vector3.ZERO
	shimmy_velocity = 0.0
