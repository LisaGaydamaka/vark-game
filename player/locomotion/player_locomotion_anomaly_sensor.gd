class_name PlayerLocomotionAnomalySensor
extends RefCounted


const MOTION_EPSILON_SQUARED: float = 0.000001
const MIN_REQUESTED_HORIZONTAL_DISTANCE: float = 0.01
const STUCK_MAX_PROGRESS_RATIO: float = 0.15
const STUCK_FRAMES_TO_REPORT: int = 4
const JITTER_MIN_REALIZED_DISTANCE: float = 0.001
const STABLE_REQUEST_DIRECTION_DOT: float = 0.8
const JITTER_REALIZED_DIRECTION_DOT: float = -0.25
const JITTER_SCORE_TO_REPORT: int = 2
const REPORT_INTERVAL_FRAMES: int = 15
const SAME_NORMAL_DOT: float = 0.995


var stuck_frames: int = 0
var jitter_score: int = 0
var anomaly_active: bool = false
var last_report_frame: int = -REPORT_INTERVAL_FRAMES
var previous_requested_horizontal: Vector3 = Vector3.ZERO
var previous_realized_horizontal: Vector3 = Vector3.ZERO


func observe(
	body: CharacterBody3D,
	support: PlayerSupport,
	velocity_state: PlayerVelocityState,
	input_direction: Vector3,
	start_position: Vector3,
	requested_velocity: Vector3,
	delta: float,
	collisions: Array[KinematicCollision3D],
	grounded_before_move: bool,
	step_active: bool
) -> void:
	var requested_motion: Vector3 = requested_velocity * delta
	var realized_motion: Vector3 = body.global_position - start_position
	var requested_horizontal: Vector3 = _horizontal(requested_motion)
	var realized_horizontal: Vector3 = _horizontal(realized_motion)
	var input_horizontal: Vector3 = _horizontal(input_direction)
	var requested_distance: float = requested_horizontal.length()
	var realized_distance: float = realized_horizontal.length()
	var progress_ratio: float = 1.0
	if requested_distance > sqrt(MOTION_EPSILON_SQUARED):
		progress_ratio = (
			realized_horizontal.dot(requested_horizontal.normalized())
			/ requested_distance
		)

	var collision_normals: Array[Vector3] = _collect_collision_normals(collisions)
	var walkable_normals: Array[Vector3] = []
	if support != null and support.has_support:
		_append_unique_normal(walkable_normals, support.support_normal)
	for normal: Vector3 in collision_normals:
		if support != null and support.is_walkable_surface(normal):
			_append_unique_normal(walkable_normals, normal)

	var diagnostic_contact_context: bool = walkable_normals.size() >= 2
	var substantial_request: bool = (
		grounded_before_move
		and not step_active
		and input_horizontal.length_squared() > MOTION_EPSILON_SQUARED
		and requested_distance >= MIN_REQUESTED_HORIZONTAL_DISTANCE
		and not collisions.is_empty()
		and diagnostic_contact_context
	)

	var stuck_candidate: bool = (
		substantial_request
		and progress_ratio <= STUCK_MAX_PROGRESS_RATIO
	)
	if stuck_candidate:
		stuck_frames += 1
	else:
		stuck_frames = 0

	var stable_request_direction: bool = false
	if (
		requested_distance >= MIN_REQUESTED_HORIZONTAL_DISTANCE
		and previous_requested_horizontal.length()
		>= MIN_REQUESTED_HORIZONTAL_DISTANCE
	):
		stable_request_direction = (
			requested_horizontal.normalized().dot(
				previous_requested_horizontal.normalized()
			)
			>= STABLE_REQUEST_DIRECTION_DOT
		)

	var reversed_realized_motion: bool = false
	if (
		realized_distance >= JITTER_MIN_REALIZED_DISTANCE
		and previous_realized_horizontal.length()
		>= JITTER_MIN_REALIZED_DISTANCE
	):
		reversed_realized_motion = (
			realized_horizontal.normalized().dot(
				previous_realized_horizontal.normalized()
			)
			<= JITTER_REALIZED_DIRECTION_DOT
		)

	var jitter_candidate: bool = (
		substantial_request
		and stable_request_direction
		and reversed_realized_motion
	)
	if jitter_candidate:
		jitter_score += 1
	else:
		jitter_score = maxi(jitter_score - 1, 0)

	var stuck_detected: bool = stuck_frames >= STUCK_FRAMES_TO_REPORT
	var jitter_detected: bool = jitter_score >= JITTER_SCORE_TO_REPORT
	var anomaly_detected: bool = stuck_detected or jitter_detected
	var physics_frame: int = Engine.get_physics_frames()

	if anomaly_detected:
		if (
			not anomaly_active
			or physics_frame - last_report_frame >= REPORT_INTERVAL_FRAMES
		):
			_print_report(
				physics_frame,
				stuck_detected,
				jitter_detected,
				body,
				support,
				velocity_state,
				input_direction,
				start_position,
				requested_velocity,
				requested_motion,
				realized_motion,
				progress_ratio,
				collisions,
				collision_normals,
				walkable_normals
			)
			last_report_frame = physics_frame

	anomaly_active = anomaly_detected
	previous_requested_horizontal = requested_horizontal
	previous_realized_horizontal = realized_horizontal


func _print_report(
	physics_frame: int,
	stuck_detected: bool,
	jitter_detected: bool,
	body: CharacterBody3D,
	support: PlayerSupport,
	velocity_state: PlayerVelocityState,
	input_direction: Vector3,
	start_position: Vector3,
	requested_velocity: Vector3,
	requested_motion: Vector3,
	realized_motion: Vector3,
	progress_ratio: float,
	collisions: Array[KinematicCollision3D],
	collision_normals: Array[Vector3],
	walkable_normals: Array[Vector3]
) -> void:
	var reasons: Array[String] = []
	if stuck_detected:
		reasons.append("STUCK")
	if jitter_detected:
		reasons.append("JITTER")

	var contact: PlayerSupportContact = support.get_contact() if support != null else null
	var support_description: String = "none"
	if contact != null:
		support_description = (
			"valid=%s walkable=%s source=%s separation=%.6f point=%s normal=%s rid=%s"
			% [
				contact.valid,
				contact.walkable,
				_support_source_name(contact.source),
				contact.separation,
				contact.point,
				contact.normal,
				contact.collider_rid,
			]
		)

	var collision_details: Array[String] = []
	for collision_index: int in range(collisions.size()):
		var collision: KinematicCollision3D = collisions[collision_index]
		if collision == null:
			continue
		var contact_details: Array[String] = []
		var contact_count: int = collision.get_collision_count()
		if contact_count <= 0:
			contact_details.append("normal=%s" % collision.get_normal())
		else:
			for contact_index: int in range(contact_count):
				contact_details.append(
					"p=%s n=%s rid=%s"
					% [
						collision.get_position(contact_index),
						collision.get_normal(contact_index),
						collision.get_collider_rid(contact_index),
					]
				)
		collision_details.append(
			"#%d travel=%s contacts=[%s]"
			% [collision_index, collision.get_travel(), "; ".join(contact_details)]
		)

	print(
		"[LocomotionAnomaly] reason=%s frame=%d stuck_frames=%d jitter_score=%d\n"
		+ "  position_start=%s position_end=%s input=%s\n"
		+ "  requested_velocity=%s requested_motion=%s realized_motion=%s progress_ratio=%.4f\n"
		+ "  body_velocity=%s controlled_velocity=%s support_velocity=%s external_velocity=%s\n"
		+ "  support={%s}\n"
		+ "  walkable_normals=%s\n"
		+ "  collision_normals=%s\n"
		+ "  collisions=%s"
		% [
			"+".join(reasons),
			physics_frame,
			stuck_frames,
			jitter_score,
			start_position,
			body.global_position,
			input_direction,
			requested_velocity,
			requested_motion,
			realized_motion,
			progress_ratio,
			body.velocity,
			velocity_state.controlled_velocity,
			velocity_state.support_velocity,
			velocity_state.external_velocity,
			support_description,
			walkable_normals,
			collision_normals,
			collision_details,
		]
	)


func _collect_collision_normals(
	collisions: Array[KinematicCollision3D]
) -> Array[Vector3]:
	var normals: Array[Vector3] = []
	for collision: KinematicCollision3D in collisions:
		if collision == null:
			continue
		var collision_count: int = collision.get_collision_count()
		if collision_count <= 0:
			_append_unique_normal(normals, collision.get_normal())
			continue
		for collision_index: int in range(collision_count):
			_append_unique_normal(normals, collision.get_normal(collision_index))
	return normals


func _append_unique_normal(
	normals: Array[Vector3],
	normal: Vector3
) -> void:
	if normal.length_squared() <= MOTION_EPSILON_SQUARED:
		return
	var normalized_normal: Vector3 = normal.normalized()
	for existing_normal: Vector3 in normals:
		if normalized_normal.dot(existing_normal) >= SAME_NORMAL_DOT:
			return
	normals.append(normalized_normal)


func _horizontal(value: Vector3) -> Vector3:
	return Vector3(value.x, 0.0, value.z)


func _support_source_name(source: int) -> String:
	match source:
		PlayerSupportContact.Source.FOOTPRINT:
			return "FOOTPRINT"
		PlayerSupportContact.Source.CAPSULE_CONTACT:
			return "CAPSULE_CONTACT"
		_:
			return "NONE"
