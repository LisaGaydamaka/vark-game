class_name VarkOrdinaryDoor
extends AnimatableBody3D


const PHASE_CLOSED: StringName = &"closed"
const PHASE_OPENING: StringName = &"opening"
const PHASE_OPEN: StringName = &"open"
const PHASE_CLOSING: StringName = &"closing"
const STATE_CHANGED_EVENT_NAME: StringName = &"door.state_changed"
const USE_SOUND_KIND: StringName = &"door.use"


@export var persistent_id: String = ""
@export var door_id: StringName = &"door"
@export var transition_seconds: float = 0.55
@export var open_angle_degrees: float = 90.0
@export var gameplay_sound_strength: float = 0.65
@export var base_color: Color = Color(0.34, 0.20, 0.10, 1.0)
@export var visual_model: Mesh
@export var obstacle_probe_step_degrees: float = 2.0

@onready var door_mesh: MeshInstance3D = $DoorMesh
@onready var door_collision: CollisionShape3D = $CollisionShape3D

var _phase: StringName = PHASE_CLOSED
var _open_fraction: float = 0.0
var _closed_rotation_y: float = 0.0
var _motion_blocked: bool = false
var _motion_blocker: CollisionObject3D = null
var _highlighted: bool = false
var _material: StandardMaterial3D = null
var _world_session: Node = null


func _ready() -> void:
	add_to_group(&"vark_interactable")
	_closed_rotation_y = rotation.y
	_world_session = _find_world_session()
	_material = StandardMaterial3D.new()
	door_mesh.material_override = _material
	if not set_visual_model(visual_model):
		push_error("VarkOrdinaryDoor requires a configured visual_model Mesh.")
	_sync_derived_state()


func _physics_process(delta: float) -> void:
	if _phase != PHASE_OPENING and _phase != PHASE_CLOSING:
		return
	if _motion_blocked:
		return

	var duration: float = maxf(transition_seconds, 0.001)
	var step: float = delta / duration
	var next_fraction: float = _open_fraction
	if _phase == PHASE_OPENING:
		next_fraction = minf(1.0, _open_fraction + step)
	else:
		next_fraction = maxf(0.0, _open_fraction - step)

	var sweep_limited_fraction: float = _get_sweep_limited_fraction(next_fraction)
	if not is_equal_approx(sweep_limited_fraction, next_fraction):
		if not is_equal_approx(sweep_limited_fraction, _open_fraction):
			_open_fraction = sweep_limited_fraction
			_sync_derived_state()
		_motion_blocked = true
		return

	_open_fraction = next_fraction
	if _phase == PHASE_OPENING and is_equal_approx(_open_fraction, 1.0):
		_open_fraction = 1.0
		_phase = PHASE_OPEN
		_motion_blocked = false
		_motion_blocker = null
		_sync_derived_state()
		_queue_state_changed()
		return
	if _phase == PHASE_CLOSING and is_zero_approx(_open_fraction):
		_open_fraction = 0.0
		_phase = PHASE_CLOSED
		_motion_blocked = false
		_motion_blocker = null
		_sync_derived_state()
		_queue_state_changed()
		return

	_sync_derived_state()


func is_vark_persistent_entity() -> bool:
	return not persistent_id.strip_edges().is_empty()


func get_persistent_id() -> String:
	return persistent_id


func get_content_id() -> String:
	return str(door_id)


func can_interact(_interactor: Node) -> bool:
	return true


func interact(interactor: Node) -> void:
	if _phase == PHASE_CLOSED or _phase == PHASE_CLOSING:
		request_open(interactor)
		return
	request_close(interactor)


func request_open(_requester: Node = null) -> void:
	# AI/navigation consumers express an idempotent desired state instead of
	# using the player's toggle interaction. Re-requesting a blocked opening
	# clears only the obstruction latch; the next physics sweep still decides
	# whether motion can safely continue.
	if _phase == PHASE_OPEN:
		return
	if _phase == PHASE_OPENING:
		_motion_blocked = false
		_motion_blocker = null
		return
	_phase = PHASE_OPENING
	_motion_blocked = false
	_motion_blocker = null
	_queue_use_sound()


func request_close(_requester: Node = null) -> void:
	# AI door maneuvers need the symmetric idempotent desired state. This is
	# intentionally not the player's toggle seam: retrying CLOSE only releases
	# a transient obstruction latch and never turns a closing/closed door open.
	if _phase == PHASE_CLOSED:
		return
	if _phase == PHASE_CLOSING:
		_motion_blocked = false
		_motion_blocker = null
		return
	_phase = PHASE_CLOSING
	_motion_blocked = false
	_motion_blocker = null
	_queue_use_sound()


func set_interaction_highlighted(highlighted: bool) -> void:
	_highlighted = highlighted
	_refresh_visual()


func is_interaction_highlighted() -> bool:
	return _highlighted


func set_visual_model(model: Mesh) -> bool:
	if model == null:
		return false
	visual_model = model
	if door_mesh != null:
		door_mesh.mesh = model
	return true


func get_visual_model() -> Mesh:
	return visual_model


func get_semantic_phase() -> StringName:
	return _phase


func get_open_fraction() -> float:
	return _open_fraction


func is_motion_blocked() -> bool:
	return _motion_blocked


func is_motion_blocked_by(body: CollisionObject3D) -> bool:
	return (
		_motion_blocked
		and body != null
		and is_instance_valid(_motion_blocker)
		and _motion_blocker == body
	)


func get_acoustic_openness() -> float:
	# This is a door-side source-state seam only. Phase 3.6 still owns how
	# openness affects propagated audibility through actual architecture.
	return _open_fraction


func is_navigation_passage_open() -> bool:
	# The first guard/nav proof can consume this same seam without the door
	# knowing anything about a particular NPC or navigation implementation.
	return _phase == PHASE_OPEN


func is_body_in_navigation_passage(body: CollisionObject3D) -> bool:
	if (
		body == null
		or not body.is_inside_tree()
		or door_collision == null
		or door_collision.shape == null
		or not is_inside_tree()
	):
		return false

	# Passage occupancy is physical door truth. Test the requested body against
	# the leaf's closed position, independent of the leaf's current angle.
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = door_collision.shape
	query.transform = _collision_transform_at_fraction(0.0)
	query.collision_mask = body.collision_layer
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	for result: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 8):
		if result.get("collider", null) == body:
			return true
	return false


func get_navigation_swing_radius() -> float:
	if door_collision == null or door_collision.shape == null:
		return 0.0
	var box := door_collision.shape as BoxShape3D
	if box == null:
		return 0.0

	# The navigation consumer needs a safe approach boundary, not a guessed
	# standoff. Derive the horizontal sweep radius from the real leaf collider,
	# including its offset from the hinge.
	var half_size: Vector3 = box.size * 0.5
	var max_radius: float = 0.0
	for x_sign: float in [-1.0, 1.0]:
		for z_sign: float in [-1.0, 1.0]:
			var local_corner: Vector3 = door_collision.transform * Vector3(
				half_size.x * x_sign,
				0.0,
				half_size.z * z_sign
			)
			max_radius = maxf(
				max_radius,
				Vector2(local_corner.x, local_corner.z).length()
			)
	return max_radius


func get_navigation_passage_center() -> Vector3:
	if door_collision == null or door_collision.shape == null:
		return global_position
	return _collision_transform_at_fraction(0.0).origin


func get_navigation_doorway_frame() -> Dictionary:
	if door_collision == null or door_collision.shape == null:
		return {"valid": false}
	var box := door_collision.shape as BoxShape3D
	if box == null:
		return {"valid": false}

	var closed_transform: Transform3D = _collision_transform_at_fraction(0.0)
	var normal: Vector3 = closed_transform.basis.z
	var tangent: Vector3 = closed_transform.basis.x
	normal.y = 0.0
	tangent.y = 0.0
	if normal.length_squared() <= 0.000001 or tangent.length_squared() <= 0.000001:
		return {"valid": false}
	normal = normal.normalized()
	tangent = tangent.normalized()

	# The closed visual leaf expresses the authored doorway span. Some fixtures
	# deliberately shrink only the collision leaf for sweep tolerance, so do
	# not mistake that local physics tolerance for a narrower doorway.
	var doorway_width: float = box.size.x
	var model: Mesh = get_visual_model()
	if model != null:
		doorway_width = maxf(doorway_width, model.get_aabb().size.x)
	return {
		"valid": true,
		"center": closed_transform.origin,
		"normal": normal,
		"tangent": tangent,
		"half_width": doorway_width * 0.5,
	}


func does_navigation_route_cross_passage(
	route_points: PackedVector3Array,
	body_radius: float,
	lateral_margin: float = 0.02
) -> bool:
	# Door interaction is relevant only when the route actually changes sides
	# through this fixed doorway. Merely approaching, walking beside, or having
	# a capsule prediction touch the moving leaf is not traversal intent.
	if route_points.size() < 2:
		return false
	var frame: Dictionary = get_navigation_doorway_frame()
	if not bool(frame.get("valid", false)):
		return false

	var center: Vector3 = frame.get("center", global_position)
	var normal: Vector3 = frame.get("normal", Vector3.ZERO)
	var tangent: Vector3 = frame.get("tangent", Vector3.ZERO)
	var half_width: float = float(frame.get("half_width", 0.0))
	# route_points are NavigationAgent centerline truth and are already
	# radius-safe against baked static geometry. Subtracting body_radius here
	# would erode the opening a second time and reject valid edge-of-opening
	# routes. Body fit against the moving leaf remains the later physical query.
	var usable_half_width: float = (
		half_width + maxf(lateral_margin, 0.0)
	)
	if usable_half_width <= 0.0:
		return false

	const PLANE_EPSILON: float = 0.02
	var previous_nonzero_point: Vector3 = Vector3.ZERO
	var previous_side_distance: float = 0.0
	var has_previous_nonzero: bool = false
	for point: Vector3 in route_points:
		var offset: Vector3 = point - center
		offset.y = 0.0
		var side_distance: float = offset.dot(normal)
		if absf(side_distance) <= PLANE_EPSILON:
			continue
		if not has_previous_nonzero:
			previous_nonzero_point = point
			previous_side_distance = side_distance
			has_previous_nonzero = true
			continue
		if previous_side_distance * side_distance < 0.0:
			var denominator: float = side_distance - previous_side_distance
			if absf(denominator) > 0.000001:
				var crossing_weight: float = clampf(
					-previous_side_distance / denominator,
					0.0,
					1.0
				)
				var crossing: Vector3 = previous_nonzero_point.lerp(
					point,
					crossing_weight
				)
				var crossing_offset: Vector3 = crossing - center
				crossing_offset.y = 0.0
				if absf(crossing_offset.dot(tangent)) <= usable_half_width:
					return true
		previous_nonzero_point = point
		previous_side_distance = side_distance
	return false


func get_navigation_operating_point(
	reference_position: Vector3,
	body_radius: float,
	safety_margin: float = 0.05
) -> Vector3:
	# Door operation is side-aware and based on the closed doorway frame, not
	# the current leaf angle. The point sits in front of the passage center and
	# outside the full physical swing radius, so closing/reopening cannot sweep
	# through the requesting body merely because the leaf started fully open.
	if door_collision == null or door_collision.shape == null:
		return reference_position
	var closed_transform: Transform3D = _collision_transform_at_fraction(0.0)
	var closed_normal: Vector3 = closed_transform.basis.z
	closed_normal.y = 0.0
	if closed_normal.length_squared() <= 0.000001:
		return reference_position
	closed_normal = closed_normal.normalized()
	var reference_offset: Vector3 = reference_position - closed_transform.origin
	reference_offset.y = 0.0
	var side: float = 1.0 if reference_offset.dot(closed_normal) >= 0.0 else -1.0
	var clearance: float = (
		get_navigation_swing_radius()
		+ maxf(body_radius, 0.0)
		+ maxf(safety_margin, 0.0)
	)
	var result: Vector3 = (
		closed_transform.origin
		+ closed_normal * side * clearance
	)
	result.y = reference_position.y
	return result


func capture_semantic_state() -> Dictionary:
	return {
		"phase": _phase,
		"open_fraction": _open_fraction,
		"motion_blocked": _motion_blocked,
	}


func apply_semantic_state(snapshot: Dictionary) -> bool:
	if snapshot.size() != 3:
		return false
	if (
		not snapshot.has("phase")
		or not snapshot.has("open_fraction")
		or not snapshot.has("motion_blocked")
	):
		return false
	if typeof(snapshot["phase"]) != TYPE_STRING_NAME:
		return false
	var phase: StringName = snapshot["phase"]
	if not _is_valid_phase(phase):
		return false
	var fraction_value: Variant = snapshot["open_fraction"]
	if typeof(fraction_value) != TYPE_FLOAT and typeof(fraction_value) != TYPE_INT:
		return false
	var fraction: float = float(fraction_value)
	if not is_finite(fraction) or fraction < 0.0 or fraction > 1.0:
		return false
	if typeof(snapshot["motion_blocked"]) != TYPE_BOOL:
		return false
	var motion_blocked: bool = bool(snapshot["motion_blocked"])
	if phase == PHASE_CLOSED and not is_zero_approx(fraction):
		return false
	if phase == PHASE_OPEN and not is_equal_approx(fraction, 1.0):
		return false
	if (
		motion_blocked
		and (
			(phase != PHASE_OPENING and phase != PHASE_CLOSING)
			or is_zero_approx(fraction)
			or is_equal_approx(fraction, 1.0)
		)
	):
		return false

	_phase = phase
	_open_fraction = fraction
	_motion_blocked = motion_blocked
	# Blocker identity is transient physical context, not semantic save state.
	_motion_blocker = null
	_sync_derived_state()
	return true


func reconcile_after_restore() -> void:
	# Transform, interaction presentation, blockage, and the consumer seams are
	# derived from semantic phase/progress rather than serialized engine machinery.
	_sync_derived_state()


func _sync_derived_state() -> void:
	rotation.y = (
		_closed_rotation_y
		+ deg_to_rad(open_angle_degrees) * _open_fraction
	)
	_refresh_visual()


func _get_sweep_limited_fraction(next_fraction: float) -> float:
	if (
		door_collision == null
		or door_collision.shape == null
		or not is_inside_tree()
		or is_equal_approx(next_fraction, _open_fraction)
	):
		return next_fraction

	_motion_blocker = null
	var sweep_degrees: float = (
		absf(open_angle_degrees) * absf(next_fraction - _open_fraction)
	)
	var probe_step: float = maxf(absf(obstacle_probe_step_degrees), 0.25)
	var sample_count: int = maxi(1, ceili(sweep_degrees / probe_step))
	var last_clear_fraction: float = _open_fraction
	for sample_index: int in range(1, sample_count + 1):
		var sample_weight: float = float(sample_index) / float(sample_count)
		var sample_fraction: float = lerpf(_open_fraction, next_fraction, sample_weight)
		var blocker: CollisionObject3D = _get_obstacle_at_fraction(sample_fraction)
		if blocker != null:
			_motion_blocker = blocker
			return last_clear_fraction
		last_clear_fraction = sample_fraction
	return next_fraction


func _get_obstacle_at_fraction(sample_fraction: float) -> CollisionObject3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = door_collision.shape
	query.transform = _collision_transform_at_fraction(sample_fraction)
	query.collision_mask = collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	for result: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 8):
		var collider := result.get("collider", null) as CollisionObject3D
		if collider != null:
			return collider
	return null


func _collision_transform_at_fraction(sample_fraction: float) -> Transform3D:
	var delta_angle: float = (
		deg_to_rad(open_angle_degrees) * (sample_fraction - _open_fraction)
	)
	var candidate_root: Transform3D = global_transform.rotated_local(Vector3.UP, delta_angle)
	return candidate_root * door_collision.transform


func _refresh_visual() -> void:
	if _material == null:
		return
	_material.albedo_color = base_color
	_material.emission_enabled = false
	_material.disable_receive_shadows = _highlighted
	_material.shading_mode = (
		BaseMaterial3D.SHADING_MODE_UNSHADED
		if _highlighted
		else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	)


func _queue_use_sound() -> void:
	if _world_session == null:
		return
	var source_session_id: int = int(_world_session.get("session_id"))
	_world_session.call(
		"queue_gameplay_sound",
		source_session_id,
		USE_SOUND_KIND,
		door_mesh.global_position,
		gameplay_sound_strength
	)


func _queue_state_changed() -> void:
	if _world_session == null:
		return
	var source_session_id: int = int(_world_session.get("session_id"))
	_world_session.call(
		"queue_semantic_gameplay_event",
		source_session_id,
		STATE_CHANGED_EVENT_NAME,
		{
			"door_id": door_id,
			"state": _phase,
		}
	)


func _find_world_session() -> Node:
	var cursor: Node = get_parent()
	while cursor != null:
		if (
			cursor.has_method("queue_gameplay_sound")
			and cursor.has_method("queue_semantic_gameplay_event")
		):
			return cursor
		cursor = cursor.get_parent()
	return null


func _is_valid_phase(phase: StringName) -> bool:
	return (
		phase == PHASE_CLOSED
		or phase == PHASE_OPENING
		or phase == PHASE_OPEN
		or phase == PHASE_CLOSING
	)
