class_name PlayerMotor
extends RefCounted


const MOTION_EPSILON: float = 0.000001


var acceleration: float
var ground_deceleration: float
var gravity: float

var static_friction_coefficient: float
var kinetic_friction_coefficient: float

var air_max_speed: float
var air_acceleration: float
var air_deceleration: float


func _init(
	_p_max_speed: float,
	p_acceleration: float,
	p_ground_deceleration: float,
	p_gravity: float,
	p_static_friction_coefficient: float,
	p_kinetic_friction_coefficient: float,
	p_air_max_speed: float,
	p_air_acceleration: float,
	p_air_deceleration: float
) -> void:
	acceleration = p_acceleration
	ground_deceleration = p_ground_deceleration
	gravity = p_gravity
	static_friction_coefficient = p_static_friction_coefficient
	kinetic_friction_coefficient = p_kinetic_friction_coefficient
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
		player.velocity.y -= gravity * delta
		apply_air_horizontal_velocity(player, input_direction, delta)
		constrain_horizontal_speed(player, ground_target_speed)
		return

	if support.walkable:
		_update_walkable_ground(
			player,
			support,
			input_direction,
			ground_target_speed,
			delta
		)
		return

	_update_steep_support(
		player,
		support,
		input_direction,
		ground_target_speed,
		delta
	)


func update_step_horizontal(
	player: CharacterBody3D,
	support: PlayerSupport,
	input_direction: Vector3,
	target_speed: float,
	delta: float
) -> void:
	# An active step is a kinematic configuration owned by PlayerMotionSolver.
	# Preserve ground-style X/Z response while the capsule is temporarily lifted
	# away from its support, and keep ballistic Y completely out of step motion.
	_update_walkable_ground(
		player,
		support,
		input_direction,
		target_speed,
		delta
	)


func _update_walkable_ground(
	player: CharacterBody3D,
	support: PlayerSupport,
	input_direction: Vector3,
	target_speed: float,
	delta: float
) -> void:
	# Walkable ground owns no persistent vertical momentum. Slope rise/fall is
	# temporary displacement produced later from actual accepted X/Z movement.
	player.velocity.y = 0.0

	var horizontal_velocity := Vector3(
		player.velocity.x,
		0.0,
		player.velocity.z
	)
	var horizontal_input := Vector3(
		input_direction.x,
		0.0,
		input_direction.z
	)
	var input_strength: float = minf(horizontal_input.length(), 1.0)

	var slope_acceleration: Vector3 = _get_walkable_slope_acceleration(support)
	var external_acceleration: Vector3 = slope_acceleration

	if input_strength > MOTION_EPSILON:
		var clamped_target_speed: float = maxf(target_speed, 0.0)
		if clamped_target_speed > MOTION_EPSILON:
			var desired_velocity: Vector3 = (
				horizontal_input.normalized()
				* clamped_target_speed
				* input_strength
			)
			var velocity_error: Vector3 = desired_velocity - horizontal_velocity
			external_acceleration += velocity_error * (
				acceleration / clamped_target_speed
			)
	elif _walkable_static_friction_holds(support):
		external_acceleration = Vector3.ZERO

	horizontal_velocity += external_acceleration * delta

	if input_strength <= MOTION_EPSILON:
		var stopping_acceleration: float = maxf(
			maxf(ground_deceleration, 0.0),
			kinetic_friction_coefficient
			* get_normal_load_acceleration(support)
		)
		horizontal_velocity = horizontal_velocity.move_toward(
			Vector3.ZERO,
			stopping_acceleration * delta
		)
	else:
		horizontal_velocity = _apply_horizontal_kinetic_friction(
			horizontal_velocity,
			support,
			delta
		)

	player.velocity.x = horizontal_velocity.x
	player.velocity.z = horizontal_velocity.z
	player.velocity.y = 0.0
	constrain_horizontal_speed(player, target_speed)


func _update_steep_support(
	player: CharacterBody3D,
	support: PlayerSupport,
	input_direction: Vector3,
	target_speed: float,
	delta: float
) -> void:
	# Motor output is intent plus real acceleration only. Do not project input or
	# gravity into the support plane here: doing so manufactures terrain-derived
	# Y before other contacts are known. PlayerContactMotionSolver owns the joint
	# contact solve and turns this raw intent into physically feasible motion.
	var horizontal_velocity := Vector3(
		player.velocity.x,
		0.0,
		player.velocity.z
	)
	var horizontal_input := Vector3(
		input_direction.x,
		0.0,
		input_direction.z
	)
	var input_strength: float = minf(horizontal_input.length(), 1.0)

	if input_strength > MOTION_EPSILON:
		var clamped_target_speed: float = maxf(target_speed, 0.0)
		if clamped_target_speed > MOTION_EPSILON:
			var desired_velocity: Vector3 = (
				horizontal_input.normalized()
				* clamped_target_speed
				* input_strength
			)
			var velocity_error: Vector3 = desired_velocity - horizontal_velocity
			horizontal_velocity += velocity_error * (
				acceleration / clamped_target_speed * delta
			)

	player.velocity.x = horizontal_velocity.x
	player.velocity.z = horizontal_velocity.z
	player.velocity.y -= gravity * delta

	# Friction remains a material force. Contact projection itself is deferred to
	# the motion solver so no single support plane gets privileged over another.
	apply_kinetic_friction(player, support, delta)
	constrain_horizontal_speed(player, target_speed)


func _get_walkable_slope_acceleration(
	support: PlayerSupport
) -> Vector3:
	var surface_gravity: Vector3 = (
		Vector3.DOWN * gravity
	).slide(support.support_normal)
	return Vector3(
		surface_gravity.x,
		0.0,
		surface_gravity.z
	)


func _walkable_static_friction_holds(
	support: PlayerSupport
) -> bool:
	var surface_gravity: Vector3 = (
		Vector3.DOWN * gravity
	).slide(support.support_normal)
	var maximum_static_friction: float = (
		static_friction_coefficient
		* get_normal_load_acceleration(support)
	)
	return surface_gravity.length() <= maximum_static_friction


func _apply_horizontal_kinetic_friction(
	horizontal_velocity: Vector3,
	support: PlayerSupport,
	delta: float
) -> Vector3:
	var horizontal_speed: float = horizontal_velocity.length()
	if horizontal_speed <= MOTION_EPSILON:
		return horizontal_velocity

	var friction_acceleration: float = (
		kinetic_friction_coefficient
		* get_normal_load_acceleration(support)
	)
	return horizontal_velocity.move_toward(
		Vector3.ZERO,
		friction_acceleration * delta
	)


func _constrain_velocity_to_support(
	player: CharacterBody3D,
	support: PlayerSupport
) -> void:
	if not support.has_support:
		return

	var normal_velocity: float = player.velocity.dot(support.support_normal)
	if normal_velocity < 0.0:
		player.velocity -= support.support_normal * normal_velocity


func constrain_horizontal_speed(
	player: CharacterBody3D,
	target_speed: float
) -> void:
	var horizontal_velocity := Vector3(
		player.velocity.x,
		0.0,
		player.velocity.z
	)
	var speed_limit: float = maxf(target_speed, 0.0)
	var horizontal_speed: float = horizontal_velocity.length()
	if horizontal_speed <= speed_limit or horizontal_speed <= MOTION_EPSILON:
		return

	horizontal_velocity = horizontal_velocity.normalized() * speed_limit
	player.velocity.x = horizontal_velocity.x
	player.velocity.z = horizontal_velocity.z


func apply_jump(
	player: CharacterBody3D,
	jump_height: float
) -> void:
	var jump_speed: float = sqrt(
		2.0 * gravity * maxf(jump_height, 0.0)
	)
	player.velocity.y = jump_speed


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
	var horizontal_velocity: Vector3 = Vector3.ZERO
	var clamped_launch_speed: float = maxf(horizontal_launch_speed, 0.0)

	if input_strength > MOTION_EPSILON:
		horizontal_velocity = (
			horizontal_input.normalized()
			* clamped_launch_speed
			* input_strength
		)

	player.velocity = horizontal_velocity
	apply_jump(player, jump_height)


func apply_air_horizontal_velocity(
	player: CharacterBody3D,
	input_direction: Vector3,
	delta: float
) -> void:
	var horizontal_velocity := Vector3(
		player.velocity.x,
		0.0,
		player.velocity.z
	)
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
		current_alignment = horizontal_velocity.normalized().dot(
			desired_direction
		)

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
		change_rate * delta
	)

	if preserve_inherited_speed:
		var steered_speed: float = horizontal_velocity.length()
		if steered_speed > MOTION_EPSILON:
			horizontal_velocity = (
				horizontal_velocity.normalized()
				* current_speed
			)

	player.velocity.x = horizontal_velocity.x
	player.velocity.z = horizontal_velocity.z


func get_motor_acceleration(
	player: CharacterBody3D,
	support: PlayerSupport,
	input_direction: Vector3,
	target_speed: float
) -> Vector3:
	var clamped_target_speed: float = maxf(target_speed, 0.0)
	if clamped_target_speed <= MOTION_EPSILON:
		return Vector3.ZERO

	var movement_direction: Vector3 = input_direction
	var input_projection_scale: float = 1.0
	var controlled_velocity := Vector3(
		player.velocity.x,
		0.0,
		player.velocity.z
	)

	if support.has_support:
		var projected_input: Vector3 = input_direction.slide(
			support.support_normal
		)
		var projected_input_length: float = projected_input.length()
		if projected_input_length <= MOTION_EPSILON:
			return Vector3.ZERO

		movement_direction = projected_input / projected_input_length
		input_projection_scale = projected_input_length
		controlled_velocity = player.velocity.slide(
			support.support_normal
		)

	var target_velocity: Vector3 = (
		movement_direction * clamped_target_speed
	)
	var velocity_error: Vector3 = target_velocity - controlled_velocity
	return velocity_error * (
		acceleration
		/ clamped_target_speed
		* input_projection_scale
	)


func apply_kinetic_friction(
	player: CharacterBody3D,
	support: PlayerSupport,
	delta: float
) -> void:
	var surface_velocity: Vector3 = player.velocity.slide(
		support.support_normal
	)
	var surface_speed: float = surface_velocity.length()
	if surface_speed <= MOTION_EPSILON:
		return

	var normal_load_acceleration: float = get_normal_load_acceleration(
		support
	)
	if normal_load_acceleration <= 0.0:
		return

	var friction_acceleration: float = (
		kinetic_friction_coefficient
		* normal_load_acceleration
	)
	var new_surface_velocity: Vector3 = surface_velocity.move_toward(
		Vector3.ZERO,
		friction_acceleration * delta
	)
	var normal_velocity: Vector3 = player.velocity - surface_velocity
	player.velocity = normal_velocity + new_surface_velocity


func get_normal_load_acceleration(
	support: PlayerSupport
) -> float:
	if not support.has_support:
		return 0.0

	return maxf(
		0.0,
		gravity * support.support_normal.dot(Vector3.UP)
	)
