class_name PlayerGroundMotion
extends RefCounted


const MOTION_EPSILON_SQUARED: float = 0.000001
const MINIMUM_SUPPORT_NORMAL_Y: float = 0.0001


func get_surface_motion(
	horizontal_motion: Vector3,
	support_normal: Vector3
) -> Vector3:
	var flat_motion := Vector3(
		horizontal_motion.x,
		0.0,
		horizontal_motion.z
	)
	if flat_motion.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO

	var normal: Vector3 = support_normal
	if normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return flat_motion
	normal = normal.normalized()
	if normal.y <= MINIMUM_SUPPORT_NORMAL_Y:
		return flat_motion

	# Preserve the accepted X/Z displacement exactly. Only derive the temporary
	# Y displacement required for that horizontal travel to remain tangent to
	# the support plane. This value is movement for this frame, never momentum.
	var rise: float = -(
		normal.x * flat_motion.x
		+ normal.z * flat_motion.z
	) / normal.y
	return Vector3(flat_motion.x, rise, flat_motion.z)
