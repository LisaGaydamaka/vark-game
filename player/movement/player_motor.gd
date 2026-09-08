class_name PlayerMotor
extends RefCounted


const MOTION_EPSILON: float = 0.000001


var max_speed: float
var acceleration: float
var ground_deceleration: float
var gravity: float
var static_friction_coefficient: float
var kinetic_friction_coefficient: float
var air_max_speed: float
var air_acceleration: float
var air_deceleration: float

# Persistent normal-movement state is intentionally split by ownership.
# Horizontal locomotion can never contain Y. Vertical physics can never contain
# X/Z. Surface following and traversal assistance are not stored here at all.
var horizontal_velocity: Vector3 = Vector3.ZERO
var vertical_velocity: float = 0.0
var state_initialized: bool = false


func _init(
	p_max_speed: float,
	p_acceleration: float,
	p_ground_deceleration: float,
	p_gravity: float,
	p_static_friction_coefficient: float,
	p_kinetic_friction_coefficient: float,
	p_air_max_speed: float,
	p_air_acceleration: float,
	p_air_deceleration: float
) -> void:
	max_speed = p_max_speed
	acceleration = p_acceleration
	ground_deceleration = p_ground_deceleration
	gravity = p_gravity
	static_friction_coefficient = p_static_friction_coefficient
	kinetic_friction_coefficient = p_kinetic_friction_coefficient
	air_max_speed = p_air_max_speed
	air_acceleration = p_air_acceleration
	air_deceleration = p_air_deceleration


func sync_from_player(player: CharacterBody3D) -> void:
	horizontal_velocity = Vector3(
		player.velocity.x,
		0.0,
		player.velocity.z
	)
	vertical_velocity = player.velocity.y
	state_initialized = true


func write_to_player(player: CharacterBody3D) -> void:
	player.velocity = horizontal_velocity + Vector3.UP * vertical_velocity


func update(
	player: CharacterBody3D,
	support: PlayerSupport,
	input_direction: Vector3,
	ground_target_speed: float,
	use_air_control: bool,
	delta: float
) -> void:
	if not state_initialized:
		sync_from_player(player)

	if use_air_control:
		vertical_velocity -= gravity * delta
		_apply_air_horizontal_velocity(input_direction, delta)
		write_to_player(player)
		return

	# A validated floor owns positional support, not vertical momentum. While
	# supported, persistent vertical physics is zero; slope-following Y is composed
	# later by PlayerMovement as frame-local displacement.
	vertical_velocity = 0.0
	_apply_ground_horizontal_velocity(
		support,
		input_direction,
		ground_target_speed,
		delta
	)
	write_to_player(player)


func _apply_ground_horizontal_velocity(
	support: PlayerSupport,
	input_direction: Vector3,
	target_speed: float,
	delta: float
) -> void:
	var horizontal_input := Vector3(
		input_direction.x,
		0.0,
		input_direction.z
	)
	var input_strength: float = minf(horizontal_input.length(), 1.0)

	if input_strength > MOTION_EPSILON:
		var desired_velocity: Vector3 = (
			horizontal_input.normalized()
			* maxf(target_speed, 0.0)
			* input_strength
		)
		horizontal_velocity = horizontal_velocity.move_toward(
			desired_velocity,
			maxf(acceleration, 0.0) * delta
		)
		return

	var friction_deceleration: float = (
		kinetic_friction_coefficient
		* get_normal_load_acceleration(support)
	)
	var stopping_deceleration: float = maxf(
		maxf(ground_deceleration, 0.0),
		friction_deceleration
	)
	horizontal_velocity = horizontal_velocity.move_toward(
		Vector3.ZERO,
		stopping_deceleration * delta
	)


func _apply_air_horizontal_velocity(
	input_direction: Vector3,
	delta: float
) -> void:
	var horizontal_input := Vector3(
		input_direction.x,
		0.0,
		input_direction.z
	)
	var input_strength: float = minf(horizontal_input.length(), 1.0)
	if input_strength <= MOTION_EPSILON:
		return

	var desired_direction: Vector3 = horizontal_input.normalized()
	var current_speed: float = horizontal_velocity.length()
	var current_alignment: float = 1.0
	if current_speed > MOTION_EPSILON:
		current_alignment = horizontal_velocity.normalized().dot(desired_direction)

	var preserve_inherited_speed: bool = (
		current_speed > air_max_speed
		and current_alignment >= 0.0
	)
	var target_speed: float = air_max_speed * input_strength
	if preserve_inherited_speed:
		target_speed = current_speed

	var target_velocity: Vector3 = desired_direction * target_speed
	var change_rate: float = air_acceleration
	if current_alignment < 0.0:
		change_rate = air_deceleration

	horizontal_velocity = horizontal_velocity.move_toward(
		target_velocity,
		maxf(change_rate, 0.0) * delta
	)

	if preserve_inherited_speed:
		var steered_speed: float = horizontal_velocity.length()
		if steered_speed > MOTION_EPSILON:
			horizontal_velocity = (
				horizontal_velocity.normalized()
				* current_speed
			)


func apply_jump(
	player: CharacterBody3D,
	jump_height: float
) -> void:
	if not state_initialized:
		sync_from_player(player)
	vertical_velocity = sqrt(
		2.0 * gravity * maxf(jump_height, 0.0)
	)
	write_to_player(player)


func apply_directional_jump(
	player: CharacterBody3D,
	input_direction: Vector3,
	jump_height: float,
	horizontal_launch_speed: float
) -> void:
	var horizontal_input := Vector3(
		input_direction.x,
		0.0,
		input_direction.z
	)
	var input_strength: float = minf(horizontal_input.length(), 1.0)
	horizontal_velocity = Vector3.ZERO
	if input_strength > MOTION_EPSILON:
		horizontal_velocity = (
			horizontal_input.normalized()
			* maxf(horizontal_launch_speed, 0.0)
			* input_strength
		)
	vertical_velocity = sqrt(
		2.0 * gravity * maxf(jump_height, 0.0)
	)
	state_initialized = true
	write_to_player(player)


func set_vertical_velocity(value: float) -> void:
	vertical_velocity = value
	state_initialized = true


func accept_resolved_vertical_velocity(player: CharacterBody3D) -> void:
	vertical_velocity = player.velocity.y
	state_initialized = true


func get_horizontal_velocity() -> Vector3:
	return horizontal_velocity


func get_vertical_velocity() -> float:
	return vertical_velocity


func get_normal_load_acceleration(
	support: PlayerSupport
) -> float:
	if not support.has_support:
		return 0.0
	return maxf(
		0.0,
		gravity * support.support_normal.dot(Vector3.UP)
	)
