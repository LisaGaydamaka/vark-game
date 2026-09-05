class_name PlayerStepUp
extends RefCounted


const PROBE_SAFE_MARGIN: float = 0.001
const PROBE_MAX_COLLISIONS: int = 8


var max_step_height: float
var max_riser_tilt_degrees: float
var collision_shape: CollisionShape3D
var debug_enabled: bool


func _init(
	p_max_step_height: float,
	p_max_riser_tilt_degrees: float,
	p_collision_shape: CollisionShape3D,
	p_debug_enabled: bool
) -> void:
	max_step_height = p_max_step_height
	max_riser_tilt_degrees = p_max_riser_tilt_degrees
	collision_shape = p_collision_shape
	debug_enabled = p_debug_enabled

	var capsule_shape: CapsuleShape3D = get_capsule_shape()
	debug(
		"CONFIG: capsule radius="
		+ str(capsule_shape.radius)
		+ " height="
		+ str(capsule_shape.height)
	)


func probe_horizontal_obstacle(
	player: CharacterBody3D,
	horizontal_motion: Vector3,
	support: PlayerSupport
) -> void:
	if horizontal_motion.length_squared() <= 0.000001:
		return

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
		return

	debug("DETECT: horizontal motion blocked")
	debug("motion: " + str(horizontal_motion))

	var collision_count: int = collision.get_collision_count()
	debug("collision count: " + str(collision_count))

	for collision_index: int in range(collision_count):
		var collision_position: Vector3 = (
			collision.get_position(collision_index)
		)
		var collision_normal: Vector3 = (
			collision.get_normal(collision_index)
		)
		var classification: String = classify_surface(
			collision_normal,
			support
		)

		debug(
			"collision "
			+ str(collision_index)
			+ ": position="
			+ str(collision_position)
			+ " normal="
			+ str(collision_normal)
			+ " classification="
			+ classification
		)


func classify_surface(
	normal: Vector3,
	support: PlayerSupport
) -> String:
	if support.is_walkable_surface(normal):
		return "WALKABLE"

	if is_step_riser(normal):
		return "RISER"

	return "STEEP_SLOPE"


func is_step_riser(
	normal: Vector3
) -> bool:
	var maximum_normal_y: float = sin(
		deg_to_rad(max_riser_tilt_degrees)
	)

	return absf(normal.y) <= maximum_normal_y


func get_capsule_shape() -> CapsuleShape3D:
	var shape: Shape3D = collision_shape.shape
	assert(
		shape is CapsuleShape3D,
		"PlayerStepUp requires the player collision shape to be CapsuleShape3D."
	)

	return shape as CapsuleShape3D


func get_capsule_radius() -> float:
	var capsule_shape: CapsuleShape3D = get_capsule_shape()
	return capsule_shape.radius


func debug(
	message: String
) -> void:
	if debug_enabled:
		print("STEP: ", message)
