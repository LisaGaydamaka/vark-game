class_name PlayerMotor
extends RefCounted


var max_speed: float
var acceleration: float
var gravity: float

var static_friction_coefficient: float
var kinetic_friction_coefficient: float


func _init(
	p_max_speed: float,
	p_acceleration: float,
	p_gravity: float,
	p_static_friction_coefficient: float,
	p_kinetic_friction_coefficient: float
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


func update(
	player: CharacterBody3D,
	support: PlayerSupport,
	input_direction: Vector3,
	delta: float
) -> void:
	var external_acceleration: Vector3 = (
		Vector3.DOWN
		* gravity
	)

	if not input_direction.is_zero_approx():
		external_acceleration += (
			get_motor_acceleration(
				player,
				support,
				input_direction
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


func get_motor_acceleration(
	player: CharacterBody3D,
	support: PlayerSupport,
	input_direction: Vector3
) -> Vector3:
	if max_speed <= 0.000001:
		return Vector3.ZERO

	var movement_direction: Vector3 = (
		input_direction
	)

	var input_projection_scale: float = 1.0
	var current_speed: float = 0.0

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

		var surface_velocity: Vector3 = (
			player.velocity.slide(
				support.support_normal
			)
		)

		current_speed = (
			surface_velocity.dot(
				movement_direction
			)
		)

	else:
		current_speed = (
			player.velocity.dot(
				input_direction
			)
		)

	var speed_error: float = (
		max_speed
		- current_speed
	)

	var speed_control_acceleration: float = (
		acceleration
		* speed_error
		/ max_speed
	)

	return movement_direction * (
		speed_control_acceleration
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

	return max(
		0.0,
		gravity
		* support.support_normal.dot(
			Vector3.UP
		)
	)
