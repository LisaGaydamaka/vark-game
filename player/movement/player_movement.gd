class_name PlayerMovement
extends RefCounted


const MOTION_EPSILON_SQUARED: float = 0.000001
const STEP_RISER_NORMAL_ALIGNMENT: float = 0.8


var max_collision_iterations: int


func _init(p_max_collision_iterations: int) -> void:
	max_collision_iterations = p_max_collision_iterations


func move(
	player: CharacterBody3D,
	delta: float,
	assist_velocity: Vector3 = Vector3.ZERO,
	preserved_step_wall_normal: Vector3 = Vector3.ZERO
) -> Array[KinematicCollision3D]:
	var collisions: Array[KinematicCollision3D] = []

	# Assist velocity affects displacement only. player.velocity is the persistent
	# normal-physics velocity and is the only velocity collision response retains.
	# This prevents traversal assistance from becoming momentum on the next frame.
	var motion: Vector3 = (
		player.velocity + assist_velocity
	) * delta

	for _iteration: int in range(max_collision_iterations):
		if motion.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var collision: KinematicCollision3D = player.move_and_collide(motion)
		if collision == null:
			break

		collisions.append(collision)
		var normal: Vector3 = collision.get_normal()

		# The active step riser still clips this frame's displacement through the
		# remainder below, but it does not erase persistent horizontal locomotion.
		# This lets the existing walk/sprint speed carry the capsule across the tread
		# once the disposable vertical assist has raised it high enough.
		var preserve_step_velocity: bool = _matches_step_riser(
			normal,
			preserved_step_wall_normal
		)
		var normal_velocity: float = player.velocity.dot(normal)
		if normal_velocity < 0.0 and not preserve_step_velocity:
			player.velocity -= normal * normal_velocity

		motion = collision.get_remainder().slide(normal)

	return collisions


func _matches_step_riser(
	collision_normal: Vector3,
	step_wall_normal: Vector3
) -> bool:
	var horizontal_collision_normal := Vector3(
		collision_normal.x,
		0.0,
		collision_normal.z
	)
	var horizontal_step_normal := Vector3(
		step_wall_normal.x,
		0.0,
		step_wall_normal.z
	)

	if (
		horizontal_collision_normal.length_squared() <= MOTION_EPSILON_SQUARED
		or horizontal_step_normal.length_squared() <= MOTION_EPSILON_SQUARED
	):
		return false

	return (
		horizontal_collision_normal.normalized().dot(
			horizontal_step_normal.normalized()
		)
		>= STEP_RISER_NORMAL_ALIGNMENT
	)


func move_vertical_velocity(
	player: CharacterBody3D,
	delta: float
) -> void:
	var motion: Vector3 = Vector3.UP * player.velocity.y * delta

	for _iteration: int in range(max_collision_iterations):
		if motion.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var collision: KinematicCollision3D = player.move_and_collide(motion)
		if collision == null:
			break

		var normal: Vector3 = collision.get_normal()
		var normal_velocity: float = player.velocity.dot(normal)
		if normal_velocity < 0.0:
			player.velocity -= normal * normal_velocity

		motion = collision.get_remainder().slide(normal)
