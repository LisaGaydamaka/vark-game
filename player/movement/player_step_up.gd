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


func try_step(
	player: CharacterBody3D,
	horizontal_motion: Vector3,
	support: PlayerSupport
) -> bool:
	if horizontal_motion.length_squared() <= 0.000001:
		return false

	if not support.walkable:
		return false

	var horizontal_direction: Vector3 = horizontal_motion.normalized()
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
		return false

	debug("DETECT: horizontal motion blocked")
	debug("motion: " + str(horizontal_motion))

	var collision_count: int = collision.get_collision_count()
	var candidate_riser_normal: Vector3 = Vector3.ZERO
	var candidate_push_strength: float = 0.0
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
		var push_strength: float = 0.0

		if classification == "RISER":
			push_strength = -horizontal_direction.dot(
				collision_normal
			)

			if push_strength > candidate_push_strength:
				candidate_push_strength = push_strength
				candidate_riser_normal = collision_normal

		debug(
			"collision "
			+ str(collision_index)
			+ ": position="
			+ str(collision_position)
			+ " normal="
			+ str(collision_normal)
			+ " classification="
			+ classification
			+ " push="
			+ str(push_strength)
		)

	if candidate_push_strength <= 0.0:
		return false

	var up_motion: Vector3 = get_up_motion()

	if not test_up_clearance(
		player,
		up_motion
	):
		return false

	var raised_transform: Transform3D = (
		player.global_transform.translated(up_motion)
	)
	var across_motion: Vector3 = get_across_motion(
		horizontal_direction,
		candidate_push_strength
	)

	if not test_across_clearance(
		player,
		raised_transform,
		across_motion,
		candidate_riser_normal,
		candidate_push_strength
	):
		return false

	var across_transform: Transform3D = (
		raised_transform.translated(across_motion)
	)
	var down_collision: KinematicCollision3D = (
		find_valid_down_landing(
			player,
			support,
			across_transform
		)
	)

	if down_collision == null:
		return false

	var down_motion: Vector3 = down_collision.get_travel()
	var landing_transform: Transform3D = (
		across_transform.translated(down_motion)
	)
	var rise: float = (
		landing_transform.origin.y
		- player.global_transform.origin.y
	)

	commit_step(
		player,
		up_motion,
		across_motion,
		down_motion
	)

	debug("SUCCESS: rise=" + str(rise))
	return true


func test_up_clearance(
	player: CharacterBody3D,
	up_motion: Vector3
) -> bool:
	debug("UP TEST: motion=" + str(up_motion))

	var blocked: bool = player.test_move(
		player.global_transform,
		up_motion,
		null,
		PROBE_SAFE_MARGIN,
		false,
		1
	)

	if blocked:
		debug("UP BLOCKED")
		return false

	debug("UP CLEAR")
	return true


func test_across_clearance(
	player: CharacterBody3D,
	raised_transform: Transform3D,
	across_motion: Vector3,
	riser_normal: Vector3,
	push_strength: float
) -> bool:
	debug("ACROSS TEST: riser normal=" + str(riser_normal))
	debug("ACROSS TEST: push=" + str(push_strength))
	debug("ACROSS TEST: distance=" + str(across_motion.length()))
	debug("ACROSS TEST: motion=" + str(across_motion))

	var blocked: bool = player.test_move(
		raised_transform,
		across_motion,
		null,
		PROBE_SAFE_MARGIN,
		false,
		1
	)

	if blocked:
		debug("ACROSS BLOCKED")
		return false

	debug("ACROSS CLEAR")
	return true


func find_valid_down_landing(
	player: CharacterBody3D,
	support: PlayerSupport,
	across_transform: Transform3D
) -> KinematicCollision3D:
	var down_motion: Vector3 = Vector3.DOWN * (
		get_up_motion().y + PROBE_SAFE_MARGIN
	)
	var collision: KinematicCollision3D = KinematicCollision3D.new()

	debug("DOWN TEST: motion=" + str(down_motion))

	var blocked: bool = player.test_move(
		across_transform,
		down_motion,
		collision,
		PROBE_SAFE_MARGIN,
		false,
		PROBE_MAX_COLLISIONS
	)

	if not blocked:
		debug("DOWN REJECT: no landing")
		return null

	var collision_count: int = collision.get_collision_count()
	var has_walkable_landing: bool = false
	var best_landing_normal: Vector3 = Vector3.ZERO

	debug("DOWN collision count: " + str(collision_count))

	for collision_index: int in range(collision_count):
		var collision_position: Vector3 = (
			collision.get_position(collision_index)
		)
		var collision_normal: Vector3 = (
			collision.get_normal(collision_index)
		)
		var walkable: bool = support.is_walkable_surface(
			collision_normal
		)

		if (
			walkable
			and (
				not has_walkable_landing
				or collision_normal.y > best_landing_normal.y
			)
		):
			has_walkable_landing = true
			best_landing_normal = collision_normal

		debug(
			"DOWN collision "
			+ str(collision_index)
			+ ": position="
			+ str(collision_position)
			+ " normal="
			+ str(collision_normal)
			+ " walkable="
			+ str(walkable)
		)

	if not has_walkable_landing:
		debug("DOWN REJECT: landing is not walkable")
		return null

	var down_travel: Vector3 = collision.get_travel()
	var landing_transform: Transform3D = (
		across_transform.translated(down_travel)
	)
	var rise: float = (
		landing_transform.origin.y
		- player.global_transform.origin.y
	)

	debug("DOWN travel=" + str(down_travel))
	debug("DOWN landing normal=" + str(best_landing_normal))
	debug("DOWN rise=" + str(rise))

	if rise <= PROBE_SAFE_MARGIN:
		debug("DOWN REJECT: landing does not rise above support")
		return null

	if rise > max_step_height + PROBE_SAFE_MARGIN:
		debug("DOWN REJECT: landing exceeds max step height")
		return null

	debug("DOWN VALID")
	return collision


func commit_step(
	player: CharacterBody3D,
	up_motion: Vector3,
	across_motion: Vector3,
	down_motion: Vector3
) -> void:
	debug("COMMIT: UP=" + str(up_motion))
	player.move_and_collide(
		up_motion,
		false,
		PROBE_SAFE_MARGIN,
		false,
		PROBE_MAX_COLLISIONS
	)

	debug("COMMIT: ACROSS=" + str(across_motion))
	player.move_and_collide(
		across_motion,
		false,
		PROBE_SAFE_MARGIN,
		false,
		PROBE_MAX_COLLISIONS
	)

	debug("COMMIT: DOWN=" + str(down_motion))
	player.move_and_collide(
		down_motion,
		false,
		PROBE_SAFE_MARGIN,
		false,
		PROBE_MAX_COLLISIONS
	)


func get_up_motion() -> Vector3:
	return Vector3.UP * (
		max_step_height + PROBE_SAFE_MARGIN
	)


func get_across_motion(
	horizontal_direction: Vector3,
	push_strength: float
) -> Vector3:
	var capsule_radius: float = get_capsule_radius()
	var across_distance: float = (
		capsule_radius + PROBE_SAFE_MARGIN
	) / push_strength

	return horizontal_direction * across_distance


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
