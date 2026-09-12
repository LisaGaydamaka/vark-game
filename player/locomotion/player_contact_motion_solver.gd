class_name PlayerContactMotionSolver
extends RefCounted


const MOTION_EPSILON_SQUARED: float = PlayerContactProjector.MOTION_EPSILON_SQUARED
const MINIMUM_SUPPORT_NORMAL_Y: float = 0.0001


var max_collision_iterations: int
var contact_projector: PlayerContactProjector


func _init(p_max_collision_iterations: int) -> void:
	max_collision_iterations = p_max_collision_iterations
	contact_projector = PlayerContactProjector.new()


func move(
	player: CharacterBody3D,
	delta: float,
	support: PlayerSupport
) -> Array[KinematicCollision3D]:
	var collisions: Array[KinematicCollision3D] = []
	if delta <= 0.0:
		return collisions

	var requested_velocity: Vector3 = player.velocity
	var requested_horizontal_velocity := Vector3(
		requested_velocity.x,
		0.0,
		requested_velocity.z
	)
	var requested_destination: Vector3 = (
		player.global_position + requested_velocity * delta
	)
	var requested_horizontal_destination: Vector3 = (
		player.global_position + requested_horizontal_velocity * delta
	)

	var contact_planes: Array[Vector3] = []
	var walkable_support_active: bool = false
	var walkable_support_normal: Vector3 = Vector3.UP

	if support != null and support.has_support:
		# Primary support is also part of the physical manifold. If another
		# walkable face becomes primary later in the move, this original support
		# remains available as a simultaneous unilateral constraint.
		contact_projector.append_unique_plane(
			contact_planes,
			support.support_normal
		)
		if (
			support.walkable
			and requested_velocity.y <= sqrt(MOTION_EPSILON_SQUARED)
		):
			walkable_support_active = true
			walkable_support_normal = support.support_normal

	var motion: Vector3 = _resolve_remaining_motion(
		player,
		requested_destination,
		requested_horizontal_destination,
		walkable_support_active,
		walkable_support_normal,
		contact_planes
	)

	for _iteration: int in range(max_collision_iterations):
		if motion.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var collision: KinematicCollision3D = player.move_and_collide(motion)
		if collision == null:
			break

		collisions.append(collision)
		for normal: Vector3 in contact_projector.get_collision_normals(collision):
			# Collision geometry is always physical truth. Support classification
			# may decide which contact carries the player, but it never removes a
			# simultaneous contact from the admissible-motion manifold.
			contact_projector.append_unique_plane(contact_planes, normal)

		if support != null:
			support.update(player)
			if support.has_support:
				contact_projector.append_unique_plane(
					contact_planes,
					support.support_normal
				)
			if (
				support.is_grounded()
				and requested_velocity.y <= sqrt(MOTION_EPSILON_SQUARED)
			):
				# Walkable support is an equality constraint for locomotion: the
				# accepted X/Z displacement determines its terrain-following Y.
				walkable_support_active = true
				walkable_support_normal = support.support_normal

		motion = _resolve_remaining_motion(
			player,
			requested_destination,
			requested_horizontal_destination,
			walkable_support_active,
			walkable_support_normal,
			contact_planes
		)

	_commit_resolved_velocity(
		player,
		requested_velocity,
		requested_horizontal_velocity,
		walkable_support_active,
		walkable_support_normal,
		contact_planes
	)
	return collisions


func _resolve_remaining_motion(
	player: CharacterBody3D,
	requested_destination: Vector3,
	requested_horizontal_destination: Vector3,
	walkable_support_active: bool,
	walkable_support_normal: Vector3,
	contact_planes: Array[Vector3]
) -> Vector3:
	if walkable_support_active:
		var remaining_horizontal := Vector3(
			requested_horizontal_destination.x - player.global_position.x,
			0.0,
			requested_horizontal_destination.z - player.global_position.z
		)
		return contact_projector.project_walkable_support_motion(
			remaining_horizontal,
			walkable_support_normal,
			contact_planes,
			MINIMUM_SUPPORT_NORMAL_Y
		)

	var remaining: Vector3 = requested_destination - player.global_position
	return contact_projector.project_contact_manifold(
		remaining,
		contact_planes
	)


func _commit_resolved_velocity(
	player: CharacterBody3D,
	requested_velocity: Vector3,
	requested_horizontal_velocity: Vector3,
	walkable_support_active: bool,
	walkable_support_normal: Vector3,
	contact_planes: Array[Vector3]
) -> void:
	if walkable_support_active:
		var resolved_surface_velocity: Vector3 = (
			contact_projector.project_walkable_support_motion(
				requested_horizontal_velocity,
				walkable_support_normal,
				contact_planes,
				MINIMUM_SUPPORT_NORMAL_Y
			)
		)
		# Terrain-following Y is displacement geometry, not momentum. Persist only
		# the accepted player-controlled X/Z velocity while grounded.
		player.velocity = Vector3(
			resolved_surface_velocity.x,
			0.0,
			resolved_surface_velocity.z
		)
		return

	# For free/steep motion velocity is physical. Any component removed by a
	# static contact is removed from persistent velocity as well, so blocked fall
	# speed or wall speed cannot be stored and released later.
	player.velocity = contact_projector.project_contact_manifold(
		requested_velocity,
		contact_planes
	)
