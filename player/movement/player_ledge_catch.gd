class_name PlayerLedgeCatch
extends RefCounted


const PROBE_SAFE_MARGIN: float = 0.001
const PROBE_MAX_COLLISIONS: int = 8
const MOTION_EPSILON_SQUARED: float = 0.000001
const CATCH_ACCELERATION_GRAVITY_MULTIPLIER: float = 2.0
const CATCH_COMPLETION_RADIUS_RATIO: float = 0.02
const EXPECTED_WALL_CONTACT_MIN_ALIGNMENT: float = 0.9
const EXPECTED_WALL_PLANE_TOLERANCE_RADIUS_RATIO: float = 0.25
const EXPECTED_TOP_CONTACT_MIN_ALIGNMENT: float = 0.9
const EXPECTED_TOP_PLANE_TOLERANCE_RADIUS_RATIO: float = 0.25
const EXPECTED_TOP_SIDE_PLANE_TOLERANCE_RADIUS_RATIO: float = 1.0
const EXPECTED_TOP_SIDE_VERTICAL_RANGE_RADIUS_RATIO: float = 1.0
const EXPECTED_TOP_CONTACT_RANGE_RADIUS_RATIO: float = 1.5


enum State {
	INACTIVE,
	ACTIVE,
	COMPLETED,
	FAILED,
}


enum FailureReason {
	NONE,
	UNEXPECTED_COLLISION,
	BLOCKED_PATH,
	INVALID_HANG_POSE,
}


var jump_height: float
var gravity: float
var detector: PlayerLedgeDetector
var collision_shape: CollisionShape3D

var active_candidate: PlayerLedgeDetector.LedgeCandidate = null
var completed_candidate: PlayerLedgeDetector.LedgeCandidate = null
var failed_candidate: PlayerLedgeDetector.LedgeCandidate = null
var catch_velocity: Vector3 = Vector3.ZERO
var state: int = State.INACTIVE
var failure_reason: int = FailureReason.NONE
var failure_collider_rid: RID = RID()
var failure_normal: Vector3 = Vector3.ZERO


func _init(
	p_jump_height: float,
	p_gravity: float,
	p_detector: PlayerLedgeDetector,
	p_collision_shape: CollisionShape3D
) -> void:
	jump_height = p_jump_height
	gravity = p_gravity
	detector = p_detector
	collision_shape = p_collision_shape

	assert(
		jump_height >= 0.0,
		"PlayerLedgeCatch requires jump_height to be non-negative."
	)
	assert(
		gravity > 0.0,
		"PlayerLedgeCatch requires gravity to be greater than zero."
	)
	assert(
		detector != null,
		"PlayerLedgeCatch requires a ledge detector."
	)

	get_capsule_shape()


func try_start(
	player: CharacterBody3D,
	candidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	if candidate == null:
		return false

	if not candidate.hangable:
		return false

	if not detector.is_hang_pose_valid(
		player,
		candidate,
		candidate.hang_position
	):
		return false

	active_candidate = candidate
	completed_candidate = null
	failed_candidate = null
	catch_velocity = player.velocity
	state = State.ACTIVE
	reset_failure()
	return true


func update(
	player: CharacterBody3D,
	delta: float
) -> void:
	if (
		state != State.ACTIVE
		or active_candidate == null
	):
		return

	var to_target: Vector3 = (
		active_candidate.hang_position
		- player.global_position
	)
	var distance_to_target: float = to_target.length()

	if distance_to_target <= get_completion_distance():
		try_complete(player)
		return

	var catch_acceleration: float = (
		gravity
		* CATCH_ACCELERATION_GRAVITY_MULTIPLIER
	)
	var braking_speed: float = sqrt(
		2.0
		* catch_acceleration
		* distance_to_target
	)
	var target_speed: float = minf(
		get_max_catch_speed(),
		braking_speed
	)
	var target_direction: Vector3 = (
		to_target
		/ distance_to_target
	)
	var target_velocity: Vector3 = (
		target_direction
		* target_speed
	)

	catch_velocity = catch_velocity.move_toward(
		target_velocity,
		catch_acceleration * delta
	)

	var away_speed: float = catch_velocity.dot(
		target_direction
	)

	if away_speed < 0.0:
		catch_velocity -= (
			target_direction
			* away_speed
		)

	var motion: Vector3 = catch_velocity * delta

	if (
		motion.dot(to_target) > 0.0
		and motion.length_squared()
		> to_target.length_squared()
	):
		motion = to_target

	if not is_catch_path_valid(
		player,
		active_candidate,
		player.global_transform,
		motion
	):
		player.velocity = catch_velocity
		fail_catch(
			FailureReason.BLOCKED_PATH,
			RID(),
			Vector3.ZERO
		)
		return

	if not move_catch_motion(
		player,
		motion
	):
		return

	player.velocity = catch_velocity

	if (
		player.global_position.distance_to(
			active_candidate.hang_position
		)
		<= get_completion_distance()
	):
		try_complete(player)


func move_catch_motion(
	player: CharacterBody3D,
	motion: Vector3
) -> bool:
	var remaining_motion: Vector3 = motion

	for _iteration: int in range(
		PROBE_MAX_COLLISIONS
	):
		if (
			remaining_motion.length_squared()
			<= MOTION_EPSILON_SQUARED
		):
			return true

		var collision: KinematicCollision3D = (
			player.move_and_collide(
				remaining_motion,
				false,
				PROBE_SAFE_MARGIN,
				false,
				PROBE_MAX_COLLISIONS
			)
		)

		if collision == null:
			return true

		var previous_motion_length_squared: float = (
			remaining_motion.length_squared()
		)
		var next_motion: Vector3 = (
			collision.get_remainder()
		)
		var collision_count: int = (
			collision.get_collision_count()
		)

		for collision_index: int in range(
			collision_count
		):
			var collision_normal: Vector3 = (
				collision.get_normal(
					collision_index
				)
			)

			if not is_expected_catch_contact(
				collision,
				collision_index,
				active_candidate
			):
				constrain_velocity_against_normal(
					collision_normal
				)
				player.velocity = catch_velocity
				fail_catch(
					FailureReason.UNEXPECTED_COLLISION,
					collision.get_collider_rid(
						collision_index
					),
					collision_normal
				)
				return false

			constrain_velocity_against_normal(
				collision_normal
			)
			next_motion = next_motion.slide(
				collision_normal
			)

		var travel_length_squared: float = (
			collision.get_travel().length_squared()
		)

		if (
			travel_length_squared <= MOTION_EPSILON_SQUARED
			and next_motion.length_squared()
			>= previous_motion_length_squared
			- MOTION_EPSILON_SQUARED
		):
			player.velocity = catch_velocity
			fail_catch(
				FailureReason.BLOCKED_PATH,
				RID(),
				Vector3.ZERO
			)
			return false

		remaining_motion = next_motion

	if (
		remaining_motion.length_squared()
		> MOTION_EPSILON_SQUARED
	):
		player.velocity = catch_velocity
		fail_catch(
			FailureReason.BLOCKED_PATH,
			RID(),
			Vector3.ZERO
		)
		return false

	return true


func is_catch_path_valid(
	player: CharacterBody3D,
	candidate: PlayerLedgeDetector.LedgeCandidate,
	from_transform: Transform3D,
	motion: Vector3
) -> bool:
	var simulated_transform: Transform3D = from_transform
	var remaining_motion: Vector3 = motion

	for _iteration: int in range(
		PROBE_MAX_COLLISIONS
	):
		if (
			remaining_motion.length_squared()
			<= MOTION_EPSILON_SQUARED
		):
			return true

		var collision: KinematicCollision3D = (
			KinematicCollision3D.new()
		)
		var blocked: bool = player.test_move(
			simulated_transform,
			remaining_motion,
			collision,
			PROBE_SAFE_MARGIN,
			false,
			PROBE_MAX_COLLISIONS
		)

		if not blocked:
			return true

		var previous_motion_length_squared: float = (
			remaining_motion.length_squared()
		)
		var next_motion: Vector3 = (
			collision.get_remainder()
		)
		var collision_count: int = (
			collision.get_collision_count()
		)

		for collision_index: int in range(
			collision_count
		):
			if not is_expected_catch_contact(
				collision,
				collision_index,
				candidate
			):
				return false

			next_motion = next_motion.slide(
				collision.get_normal(
					collision_index
				)
			)

		var travel: Vector3 = collision.get_travel()
		simulated_transform.origin += travel

		if (
			travel.length_squared()
			<= MOTION_EPSILON_SQUARED
			and next_motion.length_squared()
			>= previous_motion_length_squared
			- MOTION_EPSILON_SQUARED
		):
			return false

		remaining_motion = next_motion

	return (
		remaining_motion.length_squared()
		<= MOTION_EPSILON_SQUARED
	)


func is_expected_catch_contact(
	collision: KinematicCollision3D,
	collision_index: int,
	candidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	if candidate == null:
		return false

	var matches_wall: bool = matches_geometry_identity(
		collision,
		collision_index,
		candidate.wall_collider_rid,
		candidate.wall_shape_index
	)
	var matches_top: bool = matches_geometry_identity(
		collision,
		collision_index,
		candidate.top_collider_rid,
		candidate.top_shape_index
	)

	if not matches_wall and not matches_top:
		return false

	var collision_normal: Vector3 = collision.get_normal(
		collision_index
	)

	if (
		collision_normal.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return false

	collision_normal = collision_normal.normalized()
	var collision_point: Vector3 = collision.get_position(
		collision_index
	)

	if is_expected_wall_plane_contact(
		collision_point,
		collision_normal,
		candidate,
		matches_top
	):
		return true

	return (
		matches_top
		and is_expected_top_plane_contact(
			collision_point,
			collision_normal,
			candidate
		)
	)


func is_expected_wall_plane_contact(
	collision_point: Vector3,
	collision_normal: Vector3,
	candidate: PlayerLedgeDetector.LedgeCandidate,
	matches_top: bool
) -> bool:
	var wall_normal: Vector3 = candidate.wall_normal

	if (
		wall_normal.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return false

	wall_normal = wall_normal.normalized()

	if (
		collision_normal.dot(wall_normal)
		< EXPECTED_WALL_CONTACT_MIN_ALIGNMENT
	):
		return false

	var plane_distance: float = absf(
		(
			collision_point
			- candidate.edge_point
		).dot(wall_normal)
	)

	if not matches_top:
		return (
			plane_distance
			<= get_expected_wall_plane_tolerance()
		)

	if (
		plane_distance
		> get_expected_top_side_plane_tolerance()
	):
		return false

	return (
		absf(
			collision_point.y
			- candidate.edge_point.y
		)
		<= get_expected_top_side_vertical_range()
	)


func is_expected_top_plane_contact(
	collision_point: Vector3,
	collision_normal: Vector3,
	candidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
	var top_normal: Vector3 = candidate.top_normal

	if (
		top_normal.length_squared()
		<= MOTION_EPSILON_SQUARED
	):
		return false

	top_normal = top_normal.normalized()

	if (
		collision_normal.dot(top_normal)
		< EXPECTED_TOP_CONTACT_MIN_ALIGNMENT
	):
		return false

	var point_offset: Vector3 = (
		collision_point
		- candidate.top_point
	)
	var plane_distance: float = absf(
		point_offset.dot(top_normal)
	)

	if (
		plane_distance
		> get_expected_top_plane_tolerance()
	):
		return false

	var in_plane_offset: Vector3 = point_offset.slide(
		top_normal
	)
	var contact_range: float = get_expected_top_contact_range()
	return (
		in_plane_offset.length_squared()
		<= contact_range * contact_range
	)


func matches_geometry_identity(
	collision: KinematicCollision3D,
	collision_index: int,
	collider_rid: RID,
	shape_index: int
) -> bool:
	if collider_rid == RID():
		return false

	if (
		collision.get_collider_rid(
			collision_index
		)
		!= collider_rid
	):
		return false

	var collider_shape_index: int = (
		collision.get_collider_shape_index(
			collision_index
		)
	)

	if (
		shape_index >= 0
		and collider_shape_index >= 0
		and collider_shape_index != shape_index
	):
		return false

	return true


func constrain_velocity_against_normal(
	normal: Vector3
) -> void:
	var normal_velocity: float = (
		catch_velocity.dot(normal)
	)

	if normal_velocity < 0.0:
		catch_velocity -= (
			normal
			* normal_velocity
		)


func is_active() -> bool:
	return state == State.ACTIVE


func has_completed() -> bool:
	return (
		state == State.COMPLETED
		and completed_candidate != null
	)


func has_failed() -> bool:
	return state == State.FAILED


func get_failed_candidate() -> PlayerLedgeDetector.LedgeCandidate:
	return failed_candidate


func take_completed_candidate() -> PlayerLedgeDetector.LedgeCandidate:
	var candidate: PlayerLedgeDetector.LedgeCandidate = (
		completed_candidate
	)
	completed_candidate = null
	state = State.INACTIVE
	return candidate


func take_failure_description() -> String:
	var description: String = "unknown catch failure"

	if failure_reason == FailureReason.UNEXPECTED_COLLISION:
		description = (
			"unexpected collision rid="
			+ str(failure_collider_rid)
			+ " normal="
			+ str(failure_normal)
		)
	elif failure_reason == FailureReason.BLOCKED_PATH:
		description = "catch path could not make progress"
	elif failure_reason == FailureReason.INVALID_HANG_POSE:
		description = (
			"catch destination is no longer a valid hang pose"
		)

	state = State.INACTIVE
	failed_candidate = null
	reset_failure()
	return description


func cancel() -> void:
	active_candidate = null
	completed_candidate = null
	failed_candidate = null
	catch_velocity = Vector3.ZERO
	state = State.INACTIVE
	reset_failure()


func try_complete(
	player: CharacterBody3D
) -> void:
	if active_candidate == null:
		return

	if not detector.is_hang_pose_valid(
		player,
		active_candidate,
		player.global_position
	):
		player.velocity = catch_velocity
		fail_catch(
			FailureReason.INVALID_HANG_POSE,
			RID(),
			Vector3.ZERO
		)
		return

	complete(player)


func complete(
	player: CharacterBody3D
) -> void:
	completed_candidate = active_candidate
	active_candidate = null
	failed_candidate = null
	catch_velocity = Vector3.ZERO
	state = State.COMPLETED
	player.velocity = Vector3.ZERO


func fail_catch(
	reason: int,
	collider_rid: RID,
	collision_normal: Vector3
) -> void:
	failed_candidate = active_candidate
	active_candidate = null
	completed_candidate = null
	catch_velocity = Vector3.ZERO
	state = State.FAILED
	failure_reason = reason
	failure_collider_rid = collider_rid
	failure_normal = collision_normal


func reset_failure() -> void:
	failure_reason = FailureReason.NONE
	failure_collider_rid = RID()
	failure_normal = Vector3.ZERO


func get_max_catch_speed() -> float:
	var characteristic_height: float = maxf(
		jump_height,
		get_capsule_radius()
	)

	return sqrt(
		2.0
		* gravity
		* characteristic_height
	)


func get_completion_distance() -> float:
	return maxf(
		PROBE_SAFE_MARGIN,
		get_capsule_radius()
		* CATCH_COMPLETION_RADIUS_RATIO
	)


func get_expected_wall_plane_tolerance() -> float:
	return maxf(
		PROBE_SAFE_MARGIN,
		get_capsule_radius()
		* EXPECTED_WALL_PLANE_TOLERANCE_RADIUS_RATIO
	)


func get_expected_top_plane_tolerance() -> float:
	return maxf(
		PROBE_SAFE_MARGIN,
		get_capsule_radius()
		* EXPECTED_TOP_PLANE_TOLERANCE_RADIUS_RATIO
	)


func get_expected_top_side_plane_tolerance() -> float:
	return maxf(
		PROBE_SAFE_MARGIN,
		get_capsule_radius()
		* EXPECTED_TOP_SIDE_PLANE_TOLERANCE_RADIUS_RATIO
	)


func get_expected_top_side_vertical_range() -> float:
	return maxf(
		PROBE_SAFE_MARGIN,
		get_capsule_radius()
		* EXPECTED_TOP_SIDE_VERTICAL_RANGE_RADIUS_RATIO
	)


func get_expected_top_contact_range() -> float:
	return maxf(
		PROBE_SAFE_MARGIN,
		get_capsule_radius()
		* EXPECTED_TOP_CONTACT_RANGE_RADIUS_RATIO
	)


func get_capsule_radius() -> float:
	return get_capsule_shape().radius


func get_capsule_shape() -> CapsuleShape3D:
	var shape: Shape3D = collision_shape.shape
	assert(
		shape is CapsuleShape3D,
		"PlayerLedgeCatch requires the player collision shape to be CapsuleShape3D."
	)

	return shape as CapsuleShape3D
