class_name PlayerMovement
extends RefCounted


const MOTION_EPSILON_SQUARED: float = 0.000001
const CONTACT_EPSILON: float = 0.000001
const VERTICAL_NORMAL_EPSILON: float = 0.0001


class MotionComponents:
	var locomotion: Vector3 = Vector3.ZERO
	var vertical_physics: Vector3 = Vector3.ZERO
	var traversal: Vector3 = Vector3.ZERO

	func total() -> Vector3:
		return locomotion + vertical_physics + traversal

	func scale_remaining(fraction: float) -> void:
		locomotion *= fraction
		vertical_physics *= fraction
		traversal *= fraction


class NormalMoveResult:
	var collisions: Array[KinematicCollision3D] = []
	var vertical_velocity: float = 0.0


var max_collision_iterations: int


func _init(p_max_collision_iterations: int) -> void:
	max_collision_iterations = p_max_collision_iterations


func move_normal(
	player: CharacterBody3D,
	delta: float,
	horizontal_velocity: Vector3,
	vertical_velocity: float,
	traversal_velocity: Vector3,
	support: PlayerSupport
) -> NormalMoveResult:
	var result := NormalMoveResult.new()
	result.vertical_velocity = vertical_velocity

	var components := MotionComponents.new()
	components.locomotion = Vector3(
		horizontal_velocity.x,
		0.0,
		horizontal_velocity.z
	) * delta
	components.vertical_physics = Vector3.UP * vertical_velocity * delta
	components.traversal = traversal_velocity * delta

	for _iteration: int in range(max_collision_iterations):
		var requested_motion: Vector3 = components.total()
		if requested_motion.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var collision: KinematicCollision3D = player.move_and_collide(
			requested_motion
		)
		if collision == null:
			break

		result.collisions.append(collision)
		var normal: Vector3 = collision.get_normal()
		if normal.length_squared() <= MOTION_EPSILON_SQUARED:
			break
		normal = normal.normalized()

		# All sources advance to the same time-of-impact. Keep them separate for the
		# remaining part of the frame so collision response can respect provenance.
		var remaining_fraction: float = _get_remaining_fraction(
			requested_motion,
			collision.get_remainder()
		)
		components.scale_remaining(remaining_fraction)

		var walkable: bool = support.is_walkable_surface(normal)
		components.locomotion = _resolve_locomotion(
			components.locomotion,
			normal,
			walkable
		)
		components.vertical_physics = _resolve_vertical_physics(
			components.vertical_physics,
			normal,
			walkable,
			result
		)
		components.traversal = _resolve_traversal(
			components.traversal,
			normal
		)

	return result


func _get_remaining_fraction(
	requested_motion: Vector3,
	remainder: Vector3
) -> float:
	var requested_length_squared: float = requested_motion.length_squared()
	if requested_length_squared <= MOTION_EPSILON_SQUARED:
		return 0.0

	# move_and_collide() returns the untraveled part of the original request.
	# Project it back onto that request to recover the common fraction remaining
	# before any source-specific response changes its direction.
	return clampf(
		remainder.dot(requested_motion) / requested_length_squared,
		0.0,
		1.0
	)


func _resolve_locomotion(
	motion: Vector3,
	normal: Vector3,
	walkable: bool
) -> Vector3:
	if not _moves_into_surface(motion, normal):
		return motion

	if walkable:
		# Only a walkable surface may turn horizontal locomotion into vertical
		# surface-following displacement.
		return motion.slide(normal)

	# Walls and steep slopes may remove the into-wall XZ component, but may not
	# manufacture Y. Preserve any Y already authorized by a prior walkable contact.
	var resolved_y: float = motion.y
	var horizontal_motion := Vector3(motion.x, 0.0, motion.z)
	var horizontal_normal := Vector3(normal.x, 0.0, normal.z)
	if horizontal_normal.length_squared() > MOTION_EPSILON_SQUARED:
		horizontal_motion = horizontal_motion.slide(
			horizontal_normal.normalized()
		)
	return horizontal_motion + Vector3.UP * resolved_y


func _resolve_vertical_physics(
	motion: Vector3,
	normal: Vector3,
	walkable: bool,
	result: NormalMoveResult
) -> Vector3:
	if not _moves_into_surface(motion, normal):
		return motion

	if result.vertical_velocity < -CONTACT_EPSILON:
		if walkable:
			# Landing on a legitimate floor terminates falling physics.
			result.vertical_velocity = 0.0
			return Vector3.ZERO

		# Gravity/falling may become downhill tangential displacement on a steep
		# surface. It may never turn into upward motion.
		var downhill_motion: Vector3 = motion.slide(normal)
		if downhill_motion.y > 0.0:
			downhill_motion.y = 0.0
		return downhill_motion

	if result.vertical_velocity > CONTACT_EPSILON:
		if normal.y < -VERTICAL_NORMAL_EPSILON:
			# A ceiling terminates positive vertical physics.
			result.vertical_velocity = 0.0
			return Vector3.ZERO

		# A non-ceiling contact may redirect a jump tangentially, but collision
		# geometry is never allowed to amplify the requested upward displacement.
		var jump_motion: Vector3 = motion.slide(normal)
		jump_motion.y = minf(jump_motion.y, motion.y)
		return jump_motion

	return motion


func _resolve_traversal(
	motion: Vector3,
	normal: Vector3
) -> Vector3:
	if not _moves_into_surface(motion, normal):
		return motion

	# Traversal is already explicitly authorized by its owning system. Collision
	# may block or redirect it, but may never create more upward traversal than was
	# requested. A ceiling stops upward traversal completely.
	if motion.y > CONTACT_EPSILON and normal.y < -VERTICAL_NORMAL_EPSILON:
		return Vector3.ZERO

	var resolved: Vector3 = motion.slide(normal)
	if resolved.y > motion.y:
		resolved.y = motion.y
	return resolved


func _moves_into_surface(
	motion: Vector3,
	normal: Vector3
) -> bool:
	return motion.dot(normal) < -CONTACT_EPSILON


# Compatibility path for ledge actions. Ledge catch/hang/corner/mantle own the
# body's motion directly and predate normal locomotion provenance. Normal player
# locomotion never uses this method.
func move(
	player: CharacterBody3D,
	delta: float,
	assist_velocity: Vector3 = Vector3.ZERO
) -> Array[KinematicCollision3D]:
	var collisions: Array[KinematicCollision3D] = []
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
		_constrain_vertical_velocity_legacy(player, normal)
		motion = collision.get_remainder().slide(normal)

	return collisions


func _constrain_vertical_velocity_legacy(
	player: CharacterBody3D,
	normal: Vector3
) -> void:
	if absf(normal.y) <= VERTICAL_NORMAL_EPSILON:
		return

	if player.velocity.y < 0.0 and normal.y > 0.0:
		player.velocity.y = 0.0
	elif player.velocity.y > 0.0 and normal.y < 0.0:
		player.velocity.y = 0.0


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
		_constrain_vertical_velocity_legacy(player, normal)
		motion = collision.get_remainder().slide(normal)
