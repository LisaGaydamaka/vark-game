class_name VarkGuard
extends CharacterBody3D


const DOOR_OPEN_METHOD: StringName = &"is_navigation_passage_open"
const DOOR_INTERACT_METHOD: StringName = &"interact"

@export var guard_id: String = ""
@export var patrol_a_id: String = ""
@export var patrol_b_id: String = ""
@export var door_id: String = ""
@export var movement_speed: float = 2.5
@export var door_use_distance: float = 1.75

var _navigation_agent: NavigationAgent3D = null
var _patrol_positions: Array[Vector3] = []
var _target_index: int = 1
var _door: Node = null
var _configured: bool = false
var _door_request_pending: bool = false
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
	_door_request_pending = false
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
	if not door.has_method(DOOR_OPEN_METHOD) or not door.has_method(DOOR_INTERACT_METHOD):
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


func _physics_process(_delta: float) -> void:
	if not _configured or _navigation_agent == null:
		velocity = Vector3.ZERO
		return

	if _wait_for_door_if_needed():
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
	velocity = Vector3(direction.x * movement_speed, 0.0, direction.z * movement_speed)
	look_at(global_position + direction, Vector3.UP, true)
	move_and_slide()


func _wait_for_door_if_needed() -> bool:
	if _door == null:
		return false
	if bool(_door.call(DOOR_OPEN_METHOD)):
		_door_request_pending = false
		return false

	var to_door: Vector3 = _door.global_position - global_position
	to_door.y = 0.0
	if to_door.length() > door_use_distance:
		return false

	if not _door_request_pending:
		_door_request_pending = true
		_door_use_count += 1
		_door.call(DOOR_INTERACT_METHOD, self)
	return true


func _complete_patrol_leg() -> void:
	velocity = Vector3.ZERO
	_patrol_leg_count += 1
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
		_navigation_agent.path_desired_distance = 0.15
		_navigation_agent.target_desired_distance = 0.28
		_navigation_agent.radius = 0.28
		_navigation_agent.height = 1.7
		_navigation_agent.avoidance_enabled = false
		add_child(_navigation_agent)
