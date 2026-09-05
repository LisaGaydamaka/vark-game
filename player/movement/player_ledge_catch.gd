class_name PlayerLedgeCatch
extends RefCounted


const PROBE_SAFE_MARGIN: float = 0.001
const PROBE_MAX_COLLISIONS: int = 8
const MOTION_EPSILON_SQUARED: float = 0.000001
const CATCH_ACCELERATION_GRAVITY_MULTIPLIER: float = 2.0
const CATCH_COMPLETION_RADIUS_RATIO: float = 0.02


var jump_height: float
var gravity: float
var collision_shape: CollisionShape3D

var active_candidate: PlayerLedgeDetector.LedgeCandidate = null
var completed_candidate: PlayerLedgeDetector.LedgeCandidate = null
var catch_velocity: Vector3 = Vector3.ZERO


func _init(
	p_jump_height: float,
	p_gravity: float,
	p_collision_shape: CollisionShape3D
) -> void:
	jump_height = p_jump_height
	gravity = p_gravity
	collision_shape = p_collision_shape

	assert(
		jump_height >= 0.0,
		"PlayerLedgeCatch requires jump_height to be non-negative."
	)
	assert(
		gravity > 0.0,
		"PlayerLedgeCatch requires gravity to be greater than zero."
	)

	get_capsule_shape()


func try_start(
	player: CharacterBody3D,
	candidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	if candidate == null:
		return false

	if not candidate.hangable:
		return false

	var motion_to_hang: Vector3 = (
		candidate.hang_position
		- player.global_position
	)

	if (
		motion_to_hang.length_squared()
		> MOTION_EPSILON_SQUARED
		and player.test_move(
			player.global_transform,
			motion_to_hang,
			null,
			PROBE_SAFE_MARGIN,
			false,
			PROBE_MAX_COLLISIONS
		)
	):
		return false

	active_candidate = candidate
	completed_candidate = null
	catch_velocity = player.velocity
	return true


func update(
	player: CharacterBody3D,
	delta: float
) -> void:
	if active_candidate == null:
		return

	var to_target: Vector3 = (
		active_candidate.hang_position
		- player.global_position
	)
	var distance_to_target: float = to_target.length()

	if distance_to_target <= get_completion_distance():
		complete(player)
		return

	var catch_acceleration: float = (
		gravity
		* CATCH_ACCELERATION_GRAVITY_MULTIPLIER
	)
	var braking_speed: float = sqrt(
		2.0
		* catch_acceleration
		* distance_to_target
	)
	var target_speed: float = minf(
		get_max_catch_speed(),
		braking_speed
	)
	var target_velocity: Vector3 = (
		to_target
		/ distance_to_target
		* target_speed
	)

	catch_velocity = catch_velocity.move_toward(
		target_velocity,
		catch_acceleration * delta
	)

	var motion: Vector3 = catch_velocity * delta

	if (
		motion.dot(to_target) > 0.0
		and motion.length_squared()
		> to_target.length_squared()
	):
		motion = to_target

	var collision: KinematicCollision3D = (
		player.move_and_collide(motion)
	)

	if collision != null:
		var collision_normal: Vector3 = (
			collision.get_normal()
		)
		player.velocity = catch_velocity.slide(
			collision_normal
		)
		active_candidate = null
		return

	player.velocity = catch_velocity

	if (
		player.global_position.distance_to(
			active_candidate.hang_position
		)
		<= get_completion_distance()
	):
		complete(player)


func is_active() -> bool:
	return active_candidate != null


func has_completed() -> bool:
	return completed_candidate != null


func take_completed_candidate() -> PlayerLedgeDetector.LedgeCandidate:
	var candidate: PlayerLedgeDetector.LedgeCandidate = (
		completed_candidate
	)
	completed_candidate = null
	return candidate


func cancel() -> void:
	active_candidate = null
	completed_candidate = null
	catch_velocity = Vector3.ZERO


func complete(
	player: CharacterBody3D
) -> void:
	completed_candidate = active_candidate
	active_candidate = null
	catch_velocity = Vector3.ZERO
	player.velocity = Vector3.ZERO


func get_max_catch_speed() -> float:
	var characteristic_height: float = maxf(
		jump_height,
		get_capsule_radius()
	)

	return sqrt(
		2.0
		* gravity
		* characteristic_height
	)


func get_completion_distance() -> float:
	return maxf(
		PROBE_SAFE_MARGIN,
		get_capsule_radius()
		* CATCH_COMPLETION_RADIUS_RATIO
	)


func get_capsule_radius() -> float:
	return get_capsule_shape().radius


func get_capsule_shape() -> CapsuleShape3D:
	var shape: Shape3D = collision_shape.shape
	assert(
		shape is CapsuleShape3D,
		"PlayerLedgeCatch requires the player collision shape to be CapsuleShape3D."
	)

	return shape as CapsuleShape3D
