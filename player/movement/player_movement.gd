class_name PlayerMovement
extends RefCounted


const MOTION_EPSILON_SQUARED: float = 0.000001
const VERTICAL_NORMAL_EPSILON: float = 0.0001
const CONSTRAINT_EPSILON: float = 0.000001
const SAME_PLANE_DOT: float = 0.999


var max_collision_iterations: int
var ground_motion: PlayerGroundMotion

var jump_debug_previous_move_frame: int = -1
var jump_debug_previous_move_mode: String = "none"
var jump_debug_previous_collision_count: int = 0
var jump_debug_previous_contact_count: int = 0
var jump_debug_previous_contacts: PackedStringArray = PackedStringArray()


func _init(p_max_collision_iterations: int) -> void:
	max_collision_iterations = p_max_collision_iterations
	ground_motion = PlayerGroundMotion.new()


func move(
	player: CharacterBody3D,
	delta: float,
	assist_velocity: Vector3 = Vector3.ZERO,
	support: PlayerSupport = null
) -> Array[KinematicCollision3D]:
	var move_mode: String = "free"
	var collisions: Array[KinematicCollision3D]

	if (
		support != null
		and support.has_support
		and support.walkable
		and absf(player.velocity.y) <= sqrt(MOTION_EPSILON_SQUARED)
		and assist_velocity.length_squared() <= MOTION_EPSILON_SQUARED
	):
		move_mode = "walkable_ground"
		collisions = _move_walkable_ground(player, support, delta)
	else:
		collisions = _move_free(player, delta, assist_velocity)

	_debug_rejected_jump_contacts(
		player,
		support,
		move_mode,
		collisions
	)
	_cache_jump_debug_contacts(move_mode, collisions)
	return collisions


func _move_walkable_ground(
	player: CharacterBody3D,
	support: PlayerSupport,
	delta: float
) -> Array[KinematicCollision3D]:
	var collisions: Array[KinematicCollision3D] = []
	var active_horizontal_planes: Array[Vector3] = []
	var remaining_horizontal := Vector3(
		player.velocity.x,
		0.0,
		player.velocity.z
	) * delta
	var desired_horizontal_destination: Vector3 = (
		player.global_position + remaining_horizontal
	)
	var current_support_normal: Vector3 = support.support_normal

	# Ground locomotion is solved in XZ. Walkable terrain contributes only the
	# temporary Y required to follow the support surface. Blocking contacts are
	# accumulated for the whole move so a later wall cannot reintroduce motion
	# into an earlier wall merely because collision order changed.
	for _iteration: int in range(max_collision_iterations):
		if remaining_horizontal.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var motion: Vector3 = ground_motion.get_surface_motion(
			remaining_horizontal,
			current_support_normal
		)
		if motion.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var collision: KinematicCollision3D = player.move_and_collide(motion)
		if collision == null:
			break

		collisions.append(collision)
		var collision_normals: Array[Vector3] = _get_collision_normals(collision)
		var blocked_above: bool = false
		var next_support_normal: Vector3 = current_support_normal
		var next_support_y: float = -INF

		for normal: Vector3 in collision_normals:
			_constrain_vertical_velocity_from_collision(player, normal)

			if (
				normal.y < -VERTICAL_NORMAL_EPSILON
				and motion.y > 0.0
			):
				blocked_above = true

			if support.is_walkable_surface(normal):
				if normal.y > next_support_y:
					next_support_y = normal.y
					next_support_normal = normal
				continue

			var horizontal_normal := Vector3(normal.x, 0.0, normal.z)
			if horizontal_normal.length_squared() <= MOTION_EPSILON_SQUARED:
				continue
			_append_unique_plane(
				active_horizontal_planes,
				horizontal_normal
			)

		if blocked_above:
			break
		if next_support_y > -INF:
			current_support_normal = next_support_normal

		# Resolve toward the original horizontal endpoint, not toward a remainder
		# that may already contain a collision-generated deflection. This preserves
		# the player's requested motion as the source of truth for every iteration.
		var horizontal_to_destination := Vector3(
			desired_horizontal_destination.x - player.global_position.x,
			0.0,
			desired_horizontal_destination.z - player.global_position.z
		)
		remaining_horizontal = _resolve_horizontal_constraints(
			horizontal_to_destination,
			active_horizontal_planes
		)

	return collisions


func _move_free(
	player: CharacterBody3D,
	delta: float,
	assist_velocity: Vector3
) -> Array[KinematicCollision3D]:
	var collisions: Array[KinematicCollision3D] = []
	var active_planes: Array[Vector3] = []

	# Persistent velocity is locomotion/physics state owned by the motor.
	# Temporary traversal assist contributes only to this frame's displacement.
	var motion: Vector3 = (
		player.velocity + assist_velocity
	) * delta
	var desired_destination: Vector3 = player.global_position + motion

	# Each collision adds constraints to one active contact manifold. Every
	# iteration resolves toward the original requested endpoint, so a deflection
	# created by one contact never becomes new intent for later contacts.
	for _iteration: int in range(max_collision_iterations):
		if motion.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var collision: KinematicCollision3D = player.move_and_collide(motion)
		if collision == null:
			break

		collisions.append(collision)
		var collision_normals: Array[Vector3] = _get_collision_normals(collision)
		for normal: Vector3 in collision_normals:
			# Collision response may terminate persistent vertical physics at a floor
			# or ceiling, but never rewrites X/Z locomotion.
			_constrain_vertical_velocity_from_collision(player, normal)
			_append_unique_plane(active_planes, normal)

		var desired_remaining: Vector3 = (
			desired_destination - player.global_position
		)
		motion = _resolve_3d_constraints(
			desired_remaining,
			active_planes
		)

	return collisions


func _debug_rejected_jump_contacts(
	player: CharacterBody3D,
	support: PlayerSupport,
	move_mode: String,
	collisions: Array[KinematicCollision3D]
) -> void:
	if not Input.is_action_just_pressed("jump"):
		return
	if support != null and support.is_grounded():
		return

	var current_contacts: PackedStringArray = _describe_collision_contacts(
		collisions
	)
	var current_contact_count: int = _count_collision_contacts(collisions)
	var has_support: bool = support != null and support.has_support
	var walkable: bool = support != null and support.walkable
	var grounded: bool = support != null and support.is_grounded()
	print(
		"[JUMP_DEBUG] frame=%d event=REJECTED_JUMP_MOVE_CONTACTS mode=%s grounded=%s has_support=%s walkable=%s pos=%s vel=%s previous_frame=%d previous_mode=%s previous_collisions=%d previous_contacts=%d previous=[%s] current_collisions=%d current_contacts=%d current=[%s]"
		% [
			Engine.get_physics_frames(),
			move_mode,
			str(grounded),
			str(has_support),
			str(walkable),
			str(player.global_position),
			str(player.velocity),
			jump_debug_previous_move_frame,
			jump_debug_previous_move_mode,
			jump_debug_previous_collision_count,
			jump_debug_previous_contact_count,
			", ".join(jump_debug_previous_contacts),
			collisions.size(),
			current_contact_count,
			", ".join(current_contacts),
		]
	)


func _cache_jump_debug_contacts(
	move_mode: String,
	collisions: Array[KinematicCollision3D]
) -> void:
	jump_debug_previous_move_frame = Engine.get_physics_frames()
	jump_debug_previous_move_mode = move_mode
	jump_debug_previous_collision_count = collisions.size()
	jump_debug_previous_contact_count = _count_collision_contacts(collisions)
	jump_debug_previous_contacts = _describe_collision_contacts(collisions)


func _count_collision_contacts(
	collisions: Array[KinematicCollision3D]
) -> int:
	var contact_count: int = 0
	for collision: KinematicCollision3D in collisions:
		if collision == null:
			continue
		contact_count += maxi(1, collision.get_collision_count())
	return contact_count


func _describe_collision_contacts(
	collisions: Array[KinematicCollision3D]
) -> PackedStringArray:
	var details := PackedStringArray()
	for move_index: int in range(collisions.size()):
		var collision: KinematicCollision3D = collisions[move_index]
		if collision == null:
			continue

		var collision_count: int = collision.get_collision_count()
		if collision_count <= 0:
			details.append(
				"move=%d contact=0 normal=%s point=%s travel=%s remainder=%s"
				% [
					move_index,
					str(collision.get_normal()),
					str(collision.get_position()),
					str(collision.get_travel()),
					str(collision.get_remainder()),
				]
			)
			continue

		for contact_index: int in range(collision_count):
			details.append(
				"move=%d contact=%d normal=%s point=%s travel=%s remainder=%s"
				% [
					move_index,
					contact_index,
					str(collision.get_normal(contact_index)),
					str(collision.get_position(contact_index)),
					str(collision.get_travel()),
					str(collision.get_remainder()),
				]
			)
	return details


func _resolve_horizontal_constraints(
	desired_motion: Vector3,
	planes: Array[Vector3]
) -> Vector3:
	var desired := Vector3(
		desired_motion.x,
		0.0,
		desired_motion.z
	)
	if desired.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO
	if planes.is_empty() or _satisfies_constraints(desired, planes):
		return desired

	# In 2D the closest feasible point is either the desired point, a projection
	# onto one active boundary, or the corner at zero. Testing each boundary
	# against every plane makes the answer independent of which wall was hit first.
	var best_motion: Vector3 = Vector3.ZERO
	var best_distance_squared: float = desired.length_squared()

	for plane: Vector3 in planes:
		var candidate: Vector3 = desired.slide(plane)
		candidate.y = 0.0
		if not _satisfies_constraints(candidate, planes):
			continue
		var distance_squared: float = candidate.distance_squared_to(desired)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_motion = candidate

	return best_motion


func _resolve_3d_constraints(
	desired_motion: Vector3,
	planes: Array[Vector3]
) -> Vector3:
	if desired_motion.length_squared() <= MOTION_EPSILON_SQUARED:
		return Vector3.ZERO
	if planes.is_empty() or _satisfies_constraints(desired_motion, planes):
		return desired_motion

	# Project the requested remainder onto the feasible contact cone. In 3D the
	# closest point can lie on one plane, on the crease formed by two planes, or
	# at the fully constrained origin. Every candidate must satisfy every active
	# plane, so a new contact can only remove freedom; it cannot reopen an older
	# blocked direction.
	var best_motion: Vector3 = Vector3.ZERO
	var best_distance_squared: float = desired_motion.length_squared()

	for plane: Vector3 in planes:
		var candidate: Vector3 = desired_motion.slide(plane)
		if not _satisfies_constraints(candidate, planes):
			continue
		var distance_squared: float = candidate.distance_squared_to(desired_motion)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_motion = candidate

	for first_index: int in range(planes.size()):
		for second_index: int in range(first_index + 1, planes.size()):
			var crease: Vector3 = planes[first_index].cross(planes[second_index])
			if crease.length_squared() <= MOTION_EPSILON_SQUARED:
				continue
			crease = crease.normalized()
			var candidate: Vector3 = (
				crease * desired_motion.dot(crease)
			)
			if not _satisfies_constraints(candidate, planes):
				continue
			var distance_squared: float = candidate.distance_squared_to(
				desired_motion
			)
			if distance_squared < best_distance_squared:
				best_distance_squared = distance_squared
				best_motion = candidate

	return best_motion


func _satisfies_constraints(
	motion: Vector3,
	planes: Array[Vector3]
) -> bool:
	for plane: Vector3 in planes:
		if motion.dot(plane) < -CONSTRAINT_EPSILON:
			return false
	return true


func _append_unique_plane(
	planes: Array[Vector3],
	normal: Vector3
) -> void:
	if normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return
	var normalized_normal: Vector3 = normal.normalized()
	for existing_plane: Vector3 in planes:
		# Same-facing near-parallel contacts describe the same constraint. Opposite
		# normals are intentionally retained because together they can constrain a
		# body between two opposing surfaces.
		if normalized_normal.dot(existing_plane) >= SAME_PLANE_DOT:
			return
	planes.append(normalized_normal)


func _get_collision_normals(
	collision: KinematicCollision3D
) -> Array[Vector3]:
	var normals: Array[Vector3] = []
	if collision == null:
		return normals

	var collision_count: int = collision.get_collision_count()
	if collision_count <= 0:
		_append_unique_plane(normals, collision.get_normal())
		return normals

	for collision_index: int in range(collision_count):
		_append_unique_plane(
			normals,
			collision.get_normal(collision_index)
		)
	return normals


func _constrain_vertical_velocity_from_collision(
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
	var debug_jump: bool = Input.is_action_just_pressed("jump")
	var start_position: Vector3 = player.global_position
	var start_velocity: Vector3 = player.velocity
	var motion: Vector3 = Vector3.UP * player.velocity.y * delta
	var desired_destination: Vector3 = player.global_position + motion
	var active_planes: Array[Vector3] = []

	if debug_jump:
		print(
			"[JUMP_DEBUG] frame=%d event=VERTICAL_MOVE_BEGIN pos=%s vel=%s requested_motion=%s desired_destination=%s"
			% [
				Engine.get_physics_frames(),
				str(start_position),
				str(start_velocity),
				str(motion),
				str(desired_destination),
			]
		)

	for iteration: int in range(max_collision_iterations):
		if motion.length_squared() <= MOTION_EPSILON_SQUARED:
			break

		var requested_motion: Vector3 = motion
		var collision: KinematicCollision3D = player.move_and_collide(motion)
		if collision == null:
			if debug_jump:
				print(
					"[JUMP_DEBUG] frame=%d event=VERTICAL_MOVE_CLEAR iteration=%d requested=%s pos=%s vel=%s"
					% [
						Engine.get_physics_frames(),
						iteration,
						str(requested_motion),
						str(player.global_position),
						str(player.velocity),
					]
				)
			break

		var collision_normals: Array[Vector3] = _get_collision_normals(collision)
		var velocity_before_constraints: Vector3 = player.velocity
		var contact_details := PackedStringArray()
		if debug_jump:
			var collision_count: int = collision.get_collision_count()
			if collision_count <= 0:
				contact_details.append(
					"contact=0 normal=%s point=%s"
					% [
						str(collision.get_normal()),
						str(collision.get_position()),
					]
				)
			else:
				for contact_index: int in range(collision_count):
					contact_details.append(
						"contact=%d normal=%s point=%s"
						% [
							contact_index,
							str(collision.get_normal(contact_index)),
							str(collision.get_position(contact_index)),
						]
					)

		for normal: Vector3 in collision_normals:
			_constrain_vertical_velocity_from_collision(player, normal)
			_append_unique_plane(active_planes, normal)

		if debug_jump:
			print(
				"[JUMP_DEBUG] frame=%d event=VERTICAL_MOVE_COLLISION iteration=%d requested=%s travel=%s remainder=%s velocity_before=%s velocity_after=%s contacts=[%s]"
				% [
					Engine.get_physics_frames(),
					iteration,
					str(requested_motion),
					str(collision.get_travel()),
					str(collision.get_remainder()),
					str(velocity_before_constraints),
					str(player.velocity),
					", ".join(contact_details),
				]
			)

		var desired_remaining: Vector3 = (
			desired_destination - player.global_position
		)
		motion = _resolve_3d_constraints(
			desired_remaining,
			active_planes
		)

	if debug_jump:
		print(
			"[JUMP_DEBUG] frame=%d event=VERTICAL_MOVE_END start_pos=%s end_pos=%s actual_displacement=%s start_vel=%s end_vel=%s"
			% [
				Engine.get_physics_frames(),
				str(start_position),
				str(player.global_position),
				str(player.global_position - start_position),
				str(start_velocity),
				str(player.velocity),
			]
		)
