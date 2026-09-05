class_name PlayerMovement
extends RefCounted


var max_collision_iterations: int


func _init(
	p_max_collision_iterations: int
) -> void:
	max_collision_iterations = p_max_collision_iterations


func move(
	player: CharacterBody3D,
	delta: float
) -> void:
	var motion: Vector3 = player.velocity * delta

	for _iteration: int in range(
		max_collision_iterations
	):
		if motion.length_squared() <= 0.000001:
			break

		var collision: KinematicCollision3D = (
			player.move_and_collide(motion)
		)

		if collision == null:
			break

		var normal: Vector3 = collision.get_normal()
		var remainder: Vector3 = collision.get_remainder()
		var normal_velocity: float = (
			player.velocity.dot(normal)
		)

		if normal_velocity < 0.0:
			player.velocity -= normal * normal_velocity

		motion = remainder.slide(normal)
