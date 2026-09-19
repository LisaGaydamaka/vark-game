class_name VarkGuard
extends CharacterBody3D


const DOOR_REQUEST_OPEN_METHOD: StringName = &"request_open"
const DOOR_BODY_IN_PASSAGE_METHOD: StringName = &"is_body_in_navigation_passage"
const DOOR_SWING_RADIUS_METHOD: StringName = &"get_navigation_swing_radius"
const DOOR_REQUEST_RETRY_SECONDS: float = 0.35

enum DoorTraversalState {
	APPROACHING,
	WAITING_OPEN,
	CROSSING,
	CLEAR,
}

@export var guard_id: String = ""
@export var patrol_a_id: String = ""
@export var patrol_b_id: String = ""
@export var door_id: String = ""
@export var movement_speed: float = 2.5
@export var door_use_distance: float = 2.0

var _navigation_agent: NavigationAgent3D = null
var _patrol_positions: Array[Vector3] = []
var _target_index: int = 1
var _door: Node = null
var _configured: bool = false
var _door_traversal_state: DoorTraversalState = DoorTraversalState.APPROACHING
var _door_use_active: bool = false
var _door_request_pending: bool = false
var _door_route_blocked: bool = false
var _door_obstruction_imminent: bool = false
var _door_retry_remaining: float = 0.0
var _door_use_count: int = 0
var _patrol_leg_count: int = 0
var _patrol_cycle_count: int = 0
var _max_observed_path_x: float = -INF
var _max_observed_path_point_count: int = 0
var _last_error: String = ""


func _ready() -> void:
	add_to_group(&"vark_guard")
	collision_layer = 2
	collision_mask = 1
	up_direction = Vector3.UP
	_ensure_components()


func configure_patrol(patrol_points: Dictionary, door: Node) -> bool:
	_last_error = ""
	_configured = false
	_patrol_positions.clear()
	_door = null
	_door_traversal_state = DoorTraversalState.APPROACHING
	_door_use_active = false
	_door_request_pending = false
	_door_route_blocked = false
	_door_obstruction_imminent = false
	_door_retry_remaining = 0.0
	_patrol_leg_count = 0
	_patrol_cycle_count = 0
	_door_use_count = 0
	_max_observed_path_x = -INF
	_max_observed_path_point_count = 0

	var patrol_a := patrol_points.get(patrol_a_id) as Node3D
	var patrol_b := patrol_points.get(patrol_b_id) as Node3D
	if patrol_a == null or patrol_b == null:
		_last_error = (
			"Guard '%s' could not resolve patrol points '%s' and '%s'."
			% [guard_id, patrol_a_id, patrol_b_id]
		)
		push_error(_last_error)
		return false
	if door == null:
		_last_error = "Guard '%s' could not resolve ordinary door '%s'." % [guard_id, door_id]
		push_error(_last_error)
		return false
	if (
		not door.has_method(DOOR_REQUEST_OPEN_METHOD)
		or not door.has_method(DOOR_BODY_IN_PASSAGE_METHOD)
		or not door.has_method(DOOR_SWING_RADIUS_METHOD)
	):
		_last_error = "Guard '%s' received a door without the ordinary navigation seam." % guard_id
		push_error(_last_error)
		return false
	if _navigation_agent == null:
		_last_error = "Guard '%s' has no NavigationAgent3D." % guard_id
		push_error(_last_error)
		return false

	_patrol_positions = [patrol_a.global_position, patrol_b.global_position]
	_target_index = 1
	_door = door
	_configured = true
	_navigation_agent.target_position = _patrol_positions[_target_index]
	return true


func get_debug_summary() -> Dictionary:
	var target_position := Vector3.ZERO
	if _configured and _target_index >= 0 and _target_index < _patrol_positions.size():
		target_position = _patrol_positions[_target_index]
	return {
		"guard_id": guard_id,
		"configured": _configured,
		"patrol_a_id": patrol_a_id,
		"patrol_b_id": patrol_b_id,
		"door_id": door_id,
		"door_use_distance": door_use_distance,
		"door_traversal_state": _door_traversal_state_name(),
		"door_use_active": _door_use_active,
		"door_request_pending": _door_request_pending,
		"door_route_blocked": _door_route_blocked,
		"door_obstruction_imminent": _door_obstruction_imminent,
		"door_approach_clearance": _door_approach_clearance(),
		"door_distance": _horizontal_distance_to_door(),
		"target_index": _target_index,
		"target_position": target_position,
		"door_use_count": _door_use_count,
		"patrol_leg_count": _patrol_leg_count,
		"patrol_cycle_count": _patrol_cycle_count,
		"global_position": global_position,
		"velocity": velocity,
		"max_observed_path_x": _max_observed_path_x,
		"max_observed_path_point_count": _max_observed_path_point_count,
		"last_error": _last_error,
	}


func _physics_process(delta: float) -> void:
	if not _configured or _navigation_agent == null:
		velocity = Vector3.ZERO
		return

	var next_position: Vector3 = _navigation_agent.get_next_path_position()
	_record_current_path()
	var target_position: Vector3 = _patrol_positions[_target_index]
	var horizontal_to_target := Vector3(
		target_position.x - global_position.x,
		0.0,
		target_position.z - global_position.z
	)
	if horizontal_to_target.length() <= maxf(_navigation_agent.target_desired_distance, 0.3):
		_complete_patrol_leg()
		return

	if _navigation_agent.is_navigation_finished():
		var target_id: String = patrol_b_id if _target_index == 1 else patrol_a_id
		_last_error = "Guard '%s' has no route to patrol target '%s'." % [guard_id, target_id]
		_configured = false
		velocity = Vector3.ZERO
		push_error(_last_error)
		return

	var direction := Vector3(
		next_position.x - global_position.x,
		0.0,
		next_position.z - global_position.z
	)
	if direction.length_squared() <= 0.000001:
		velocity = Vector3.ZERO
		return

	direction = direction.normalized()
	var planned_motion := Vector3(
		direction.x * movement_speed * delta,
		0.0,
		direction.z * movement_speed * delta
	)
	if _wait_for_door_if_needed(delta, planned_motion):
		velocity = Vector3.ZERO
		return

	velocity = Vector3(direction.x * movement_speed, 0.0, direction.z * movement_speed)
	look_at(global_position + direction, Vector3.UP, true)
	move_and_slide()


func _wait_for_door_if_needed(delta: float, planned_motion: Vector3) -> bool:
	if _door == null:
		return false

	var body_in_passage: bool = bool(_door.call(DOOR_BODY_IN_PASSAGE_METHOD, self))
	if body_in_passage:
		_door_traversal_state = DoorTraversalState.CROSSING
		_door_route_blocked = false
		_door_obstruction_imminent = false
		_door_request_pending = false
		_door_retry_remaining = 0.0
		return false

	if _door_traversal_state == DoorTraversalState.CROSSING:
		# Leaving the doorway completes this traversal. A door closing behind
		# the guard must not cause an unnecessary reopen.
		_door_traversal_state = DoorTraversalState.CLEAR
		_door_use_active = false
		_door_route_blocked = false
		_door_obstruction_imminent = false
		_door_request_pending = false
		_door_retry_remaining = 0.0
		return false

	if _horizontal_distance_to_door() > maxf(door_use_distance, _door_approach_clearance()):
		_door_traversal_state = DoorTraversalState.APPROACHING
		_door_use_active = false
		_door_route_blocked = false
		_door_obstruction_imminent = false
		_door_request_pending = false
		_door_retry_remaining = 0.0
		return false

	if _door_traversal_state == DoorTraversalState.CLEAR:
		_door_route_blocked = false
		_door_obstruction_imminent = false
		return false

	# Door phase is not traversability. Probe the guard's real capsule along
	# its near-future NavigationAgent path against the door's current collider.
	# A partially open/closing leaf that already leaves enough room is clear.
	_door_route_blocked = _current_route_hits_door()
	if _door_traversal_state == DoorTraversalState.WAITING_OPEN:
		if not _door_route_blocked:
			_door_traversal_state = DoorTraversalState.APPROACHING
			_door_obstruction_imminent = false
			_door_request_pending = false
			_door_retry_remaining = 0.0
			return false
		_door_obstruction_imminent = true
		_retry_door_open_request(delta)
		return true

	# The safe sweep boundary is only where the guard is allowed to stop.
	# It does not imply blockage: WAITING_OPEN begins only when the current
	# leaf also physically intersects the guard's near-future route.
	_door_obstruction_imminent = (
		_door_route_blocked
		and _planned_motion_enters_door_clearance(planned_motion)
	)
	if not _door_obstruction_imminent:
		_door_traversal_state = DoorTraversalState.APPROACHING
		_door_request_pending = false
		_door_retry_remaining = 0.0
		return false

	_door_traversal_state = DoorTraversalState.WAITING_OPEN
	if not _door_use_active:
		_door_use_active = true
		_door_use_count += 1
	if not _door_request_pending:
		_door_request_pending = true
		_door_retry_remaining = 0.0
	_retry_door_open_request(delta)
	return true


func _retry_door_open_request(delta: float) -> void:
	_door_request_pending = true
	_door_retry_remaining = maxf(0.0, _door_retry_remaining - delta)
	if is_zero_approx(_door_retry_remaining):
		_door.call(DOOR_REQUEST_OPEN_METHOD, self)
		_door_retry_remaining = DOOR_REQUEST_RETRY_SECONDS


func _current_route_hits_door() -> bool:
	if _door == null or _navigation_agent == null or not is_inside_tree():
		return false
	var collision_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		return false

	var path: PackedVector3Array = _navigation_agent.get_current_navigation_path()
	var path_index: int = _navigation_agent.get_current_navigation_path_index()
	var segment_start: Vector3 = global_position
	var remaining_distance: float = maxf(
		door_use_distance,
		_door_approach_clearance() + _navigation_agent.radius
	)
	var sample_step: float = maxf(_navigation_agent.radius * 0.5, 0.08)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision_shape.shape
	query.collision_mask = int(_door.get("collision_layer"))
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	var base_transform: Transform3D = collision_shape.global_transform

	for point_index: int in range(path_index, path.size()):
		var segment_end: Vector3 = path[point_index]
		segment_end.y = global_position.y
		var segment: Vector3 = segment_end - segment_start
		var segment_length: float = segment.length()
		if segment_length <= 0.0001:
			segment_start = segment_end
			continue
		var tested_length: float = minf(segment_length, remaining_distance)
		var sample_count: int = maxi(1, ceili(tested_length / sample_step))
		for sample_index: int in range(1, sample_count + 1):
			var sample_distance: float = minf(
				tested_length,
				sample_step * float(sample_index)
			)
			var sample_position: Vector3 = (
				segment_start + segment.normalized() * sample_distance
			)
			var offset: Vector3 = sample_position - global_position
			query.transform = Transform3D(
				base_transform.basis,
				base_transform.origin + offset
			)
			for result: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 8):
				if result.get("collider", null) == _door:
					return true
		remaining_distance -= tested_length
		if remaining_distance <= 0.0:
			break
		segment_start = segment_end
	return false


func _planned_motion_enters_door_clearance(planned_motion: Vector3) -> bool:
	if planned_motion.length_squared() <= 0.000001 or _door == null:
		return false
	var current_distance: float = _horizontal_distance_to_door()
	var next_position: Vector3 = global_position + planned_motion
	var next_to_door: Vector3 = _door.global_position - next_position
	next_to_door.y = 0.0
	var next_distance: float = next_to_door.length()
	if next_distance >= current_distance:
		return false
	return next_distance <= _door_approach_clearance()


func _door_approach_clearance() -> float:
	if _door == null or _navigation_agent == null:
		return 0.0
	var swing_radius: float = float(_door.call(DOOR_SWING_RADIUS_METHOD))
	if swing_radius <= 0.0:
		return 0.0
	return swing_radius + _navigation_agent.radius + maxf(safe_margin, 0.01)


func _horizontal_distance_to_door() -> float:
	if _door == null:
		return INF
	var to_door: Vector3 = _door.global_position - global_position
	to_door.y = 0.0
	return to_door.length()


func _door_traversal_state_name() -> StringName:
	match _door_traversal_state:
		DoorTraversalState.WAITING_OPEN:
			return &"waiting_open"
		DoorTraversalState.CROSSING:
			return &"crossing"
		DoorTraversalState.CLEAR:
			return &"clear"
		_:
			return &"approaching"


func _complete_patrol_leg() -> void:
	velocity = Vector3.ZERO
	_patrol_leg_count += 1
	_door_traversal_state = DoorTraversalState.APPROACHING
	_door_use_active = false
	_door_request_pending = false
	_door_route_blocked = false
	_door_obstruction_imminent = false
	_door_retry_remaining = 0.0
	if _target_index == 1:
		_target_index = 0
	else:
		_target_index = 1
		_patrol_cycle_count += 1
	_navigation_agent.target_position = _patrol_positions[_target_index]


func _record_current_path() -> void:
	var path: PackedVector3Array = _navigation_agent.get_current_navigation_path()
	_max_observed_path_point_count = maxi(_max_observed_path_point_count, path.size())
	for path_point: Vector3 in path:
		_max_observed_path_x = maxf(_max_observed_path_x, path_point.x)


func _ensure_components() -> void:
	if get_node_or_null("CollisionShape3D") == null:
		var collision_shape := CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		collision_shape.position = Vector3(0.0, 0.85, 0.0)
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.28
		capsule.height = 1.7
		collision_shape.shape = capsule
		add_child(collision_shape)

	if get_node_or_null("GuardMesh") == null:
		var guard_mesh := MeshInstance3D.new()
		guard_mesh.name = "GuardMesh"
		guard_mesh.position = Vector3(0.0, 0.85, 0.0)
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3(0.55, 1.7, 0.55)
		guard_mesh.mesh = box_mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.58, 0.20, 0.14, 1.0)
		guard_mesh.material_override = material
		add_child(guard_mesh)

	_navigation_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if _navigation_agent == null:
		_navigation_agent = NavigationAgent3D.new()
		_navigation_agent.name = "NavigationAgent3D"
		# Phase 3.7 bakes navigation at Godot's 0.25 m default cell height.
		# The guard origin is at its feet, so align returned/checkable waypoints
		# to that grounded origin and keep waypoint tolerance above one voxel.
		_navigation_agent.path_height_offset = 0.25
		_navigation_agent.path_desired_distance = 0.30
		_navigation_agent.target_desired_distance = 0.28
		_navigation_agent.radius = 0.28
		_navigation_agent.height = 1.7
		_navigation_agent.avoidance_enabled = false
		add_child(_navigation_agent)
