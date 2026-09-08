class_name PlayerSupport
extends RefCounted


const MOTION_EPSILON_SQUARED: float = 0.000001
const STEP_RISER_NORMAL_ALIGNMENT: float = 0.8


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
	player: CharacterBody3D,
	ignored_step_wall_normal: Vector3 = Vector3.ZERO
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

	var candidate_walkable: bool = is_walkable_surface(normal)

	# A rounded capsule touching the active stair edge can make the downward
	# support probe report a steep diagonal normal from the riser. Treating that
	# as support projects persistent velocity against the edge and destroys the
	# horizontal speed that step-up is supposed to preserve. Ignore only a
	# non-walkable contact whose horizontal normal matches the active step face.
	if (
		not candidate_walkable
		and _matches_ignored_step_riser(
			normal,
			ignored_step_wall_normal
		)
	):
		return

	has_support = true
	support_normal = normal

	support_point = (
		result.get_collision_point()
	)

	walkable = candidate_walkable

	constrain_supported_velocity(
		player
	)


func _matches_ignored_step_riser(
	contact_normal: Vector3,
	step_wall_normal: Vector3
) -> bool:
	var horizontal_contact_normal := Vector3(
		contact_normal.x,
		0.0,
		contact_normal.z
	)
	var horizontal_step_normal := Vector3(
		step_wall_normal.x,
		0.0,
		step_wall_normal.z
	)

	if (
		horizontal_contact_normal.length_squared() <= MOTION_EPSILON_SQUARED
		or horizontal_step_normal.length_squared() <= MOTION_EPSILON_SQUARED
	):
		return false

	return (
		horizontal_contact_normal.normalized().dot(
			horizontal_step_normal.normalized()
		)
		>= STEP_RISER_NORMAL_ALIGNMENT
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


func is_grounded() -> bool:
	return has_support and walkable
