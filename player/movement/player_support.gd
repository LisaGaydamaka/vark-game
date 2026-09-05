class_name PlayerSupport
extends RefCounted


var has_support: bool = false
var support_normal: Vector3 = Vector3.UP
var support_point: Vector3 = Vector3.ZERO
var walkable: bool = false


var max_walkable_slope: float
var support_check_distance: float


func _init(
	p_max_walkable_slope: float,
	p_support_check_distance: float
) -> void:
	max_walkable_slope = p_max_walkable_slope
	support_check_distance = p_support_check_distance


func update(
	player: CharacterBody3D
) -> void:
	has_support = false
	support_normal = Vector3.UP
	support_point = player.global_position
	walkable = false

	var parameters := PhysicsTestMotionParameters3D.new()
	var result := PhysicsTestMotionResult3D.new()

	parameters.from = player.global_transform

	parameters.motion = (
		Vector3.DOWN
		* support_check_distance
	)

	parameters.margin = 0.001
	parameters.recovery_as_collision = true

	var has_contact: bool = (
		PhysicsServer3D.body_test_motion(
			player.get_rid(),
			parameters,
			result
		)
	)

	if not has_contact:
		return

	var normal: Vector3 = (
		result.get_collision_normal()
	)

	if normal.dot(Vector3.UP) <= 0.0:
		return

	has_support = true
	support_normal = normal

	support_point = (
		result.get_collision_point()
	)

	walkable = is_walkable_surface(
		normal
	)

	constrain_supported_velocity(
		player
	)


func constrain_supported_velocity(
	player: CharacterBody3D
) -> void:
	if not has_support:
		return

	var normal_velocity: float = (
		player.velocity.dot(
			support_normal
		)
	)

	if normal_velocity < 0.0:
		player.velocity -= (
			support_normal
			* normal_velocity
		)


func is_walkable_surface(
	normal: Vector3
) -> bool:
	var minimum_normal_y: float = cos(
		deg_to_rad(
			max_walkable_slope
		)
	)

	return (
		normal.y
		>= minimum_normal_y - 0.00001
	)
