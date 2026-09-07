class_name PlayerMovement
extends RefCounted


const MOTION_EPSILON_SQUARED: float = 0.000001


var max_collision_iterations: int


func _init(p_max_collision_iterations: int) -> void:
	max_collision_iterations = p_max_collision_iterations


func move(
	player: CharacterBody3D,
	delta: float
) -> Array[KinematicCollision3D]:
	var collisions: Array[KinematicCollision3D] = []
	var motion: Vector3 = player.velocity * delta

	for _iteration: int in range(max_collision_iterations):
		if motion.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var collision: KinematicCollision3D = player.move_and_collide(motion)
		if collision == null:
			break

		collisions.append(collision)
		var normal: Vector3 = collision.get_normal()
		var normal_velocity: float = player.velocity.dot(normal)
		if normal_velocity < 0.0:
			player.velocity -= normal * normal_velocity

		motion = collision.get_remainder().slide(normal)

	return collisions


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
