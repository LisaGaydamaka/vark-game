class_name PlayerMotor
extends RefCounted


var max_speed: float
var acceleration: float
var gravity: float

var static_friction_coefficient: float
var kinetic_friction_coefficient: float

var air_max_speed: float
var air_acceleration: float
var air_deceleration: float


func _init(
	p_max_speed: float,
	p_acceleration: float,
	p_gravity: float,
	p_static_friction_coefficient: float,
	p_kinetic_friction_coefficient: float,
	p_air_max_speed: float,
	p_air_acceleration: float,
	p_air_deceleration: float
) -> void:
	max_speed = p_max_speed
	acceleration = p_acceleration
	gravity = p_gravity

	static_friction_coefficient = (
		p_static_friction_coefficient
	)

	kinetic_friction_coefficient = (
		p_kinetic_friction_coefficient
	)

	air_max_speed = p_air_max_speed
	air_acceleration = p_air_acceleration
	air_deceleration = p_air_deceleration


func update(
	player: CharacterBody3D,
	support: PlayerSupport,
	input_direction: Vector3,
	ground_target_speed: float,
	use_air_control: bool,
	delta: float
) -> void:
	if use_air_control:
		player.velocity += (
			Vector3.DOWN
			* gravity
			* delta
		)

		apply_air_horizontal_velocity(
			player,
			input_direction,
			delta
		)
		return

	var external_acceleration: Vector3 = (
		Vector3.DOWN
		* gravity
	)

	if not input_direction.is_zero_approx():
		external_acceleration += (
			get_motor_acceleration(
				player,
				support,
				input_direction,
				ground_target_speed
			)
		)

	if (
		support.has_support
		and support.walkable
		and input_direction.is_zero_approx()
	):
		external_acceleration = (
			apply_static_friction(
				external_acceleration,
				support
			)
		)

	player.velocity += (
		external_acceleration
		* delta
	)

	if support.has_support:
		apply_kinetic_friction(
			player,
			support,
			delta
		)


func apply_jump(
	player: CharacterBody3D,
	jump_height: float
) -> void:
	var jump_speed: float = sqrt(
		2.0
		* gravity
		* maxf(jump_height, 0.0)
	)

	player.velocity.y = jump_speed


func apply_directional_jump(
	player: CharacterBody3D,
	input_direction: Vector3,
	jump_height: float
) -> void:
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
	apply_jump(
		player,
		jump_height
	)


func apply_air_horizontal_velocity(
	player: CharacterBody3D,
	input_direction: Vector3,
	delta: float
) -> void:
	var horizontal_velocity: Vector3 = Vector3(
		player.velocity.x,
		0.0,
		player.velocity.z
	)
	var target_velocity: Vector3 = Vector3.ZERO
	var change_rate: float = air_deceleration

	if not input_direction.is_zero_approx():
		target_velocity = (
			input_direction
			* air_max_speed
		)
		change_rate = air_acceleration

	horizontal_velocity = horizontal_velocity.move_toward(
		target_velocity,
		change_rate * delta
	)

	player.velocity.x = horizontal_velocity.x
	player.velocity.z = horizontal_velocity.z


func get_motor_acceleration(
	player: CharacterBody3D,
	support: PlayerSupport,
	input_direction: Vector3,
	target_speed: float
) -> Vector3:
	var clamped_target_speed: float = maxf(
		target_speed,
		0.0
	)

	if clamped_target_speed <= 0.000001:
		return Vector3.ZERO

	var movement_direction: Vector3 = (
		input_direction
	)
	var input_projection_scale: float = 1.0
	var controlled_velocity: Vector3 = Vector3(
		player.velocity.x,
		0.0,
		player.velocity.z
	)

	if support.has_support:
		var projected_input: Vector3 = (
			input_direction.slide(
				support.support_normal
			)
		)

		var projected_input_length: float = (
			projected_input.length()
		)

		if projected_input_length <= 0.000001:
			return Vector3.ZERO

		movement_direction = (
			projected_input
			/ projected_input_length
		)

		input_projection_scale = (
			projected_input_length
		)

		controlled_velocity = (
			player.velocity.slide(
				support.support_normal
			)
		)

	var target_velocity: Vector3 = (
		movement_direction
		* clamped_target_speed
	)
	var velocity_error: Vector3 = (
		target_velocity
		- controlled_velocity
	)

	return velocity_error * (
		acceleration
		/ clamped_target_speed
		* input_projection_scale
	)


func apply_static_friction(
	external_acceleration: Vector3,
	support: PlayerSupport
) -> Vector3:
	var surface_acceleration: Vector3 = (
		external_acceleration.slide(
			support.support_normal
		)
	)

	var normal_load_acceleration: float = (
		get_normal_load_acceleration(
			support
		)
	)

	var maximum_static_friction: float = (
		static_friction_coefficient
		* normal_load_acceleration
	)

	if (
		surface_acceleration.length()
		<= maximum_static_friction
	):
		return (
			external_acceleration
			- surface_acceleration
		)

	return external_acceleration


func apply_kinetic_friction(
	player: CharacterBody3D,
	support: PlayerSupport,
	delta: float
) -> void:
	var surface_velocity: Vector3 = (
		player.velocity.slide(
			support.support_normal
		)
	)

	var surface_speed: float = (
		surface_velocity.length()
	)

	if surface_speed <= 0.000001:
		return

	var normal_load_acceleration: float = (
		get_normal_load_acceleration(
			support
		)
	)

	if normal_load_acceleration <= 0.0:
		return

	var friction_acceleration: float = (
		kinetic_friction_coefficient
		* normal_load_acceleration
	)

	var new_surface_velocity: Vector3 = (
		surface_velocity.move_toward(
			Vector3.ZERO,
			friction_acceleration
			* delta
		)
	)

	var normal_velocity: Vector3 = (
		player.velocity
		- surface_velocity
	)

	player.velocity = (
		normal_velocity
		+ new_surface_velocity
	)


func get_normal_load_acceleration(
	support: PlayerSupport
) -> float:
	if not support.has_support:
		return 0.0

	return maxf(
		0.0,
		gravity
		* support.support_normal.dot(
			Vector3.UP
		)
	)
