class_name PlayerStepUp
extends RefCounted


const PROBE_SAFE_MARGIN: float = 0.001
const PROBE_MAX_COLLISIONS: int = 8


var max_step_height: float
var max_riser_tilt_degrees: float
var debug_enabled: bool


func _init(
	p_max_step_height: float = 0.5,
	p_max_riser_tilt_degrees: float = 5.0,
	p_debug_enabled: bool = false
) -> void:
	max_step_height = p_max_step_height
	max_riser_tilt_degrees = p_max_riser_tilt_degrees
	debug_enabled = p_debug_enabled


func probe_horizontal_obstacle(
	player: CharacterBody3D,
	horizontal_motion: Vector3
) -> KinematicCollision3D:
	if horizontal_motion.length_squared() <= 0.000001:
		return null

	var collision: KinematicCollision3D = KinematicCollision3D.new()
	var blocked: bool = player.test_move(
		player.global_transform,
		horizontal_motion,
		collision,
		PROBE_SAFE_MARGIN,
		false,
		PROBE_MAX_COLLISIONS
	)

	if not blocked:
		return null

	debug("DETECT: horizontal motion blocked")
	debug("motion: " + str(horizontal_motion))

	var collision_count: int = collision.get_collision_count()
	debug("collision count: " + str(collision_count))

	for collision_index: int in range(collision_count):
		debug(
			"collision "
			+ str(collision_index)
			+ ": position="
			+ str(collision.get_position(collision_index))
			+ " normal="
			+ str(collision.get_normal(collision_index))
		)

	return collision


func debug(
	message: String
) -> void:
	if debug_enabled:
		print("STEP: ", message)
