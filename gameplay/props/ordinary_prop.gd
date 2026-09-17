class_name VarkOrdinaryProp
extends CharacterBody3D


const PHASE_SETTLED: StringName = &"settled"
const PHASE_HELD: StringName = &"held"
const PHASE_MOVING: StringName = &"moving"
const PHASE_SETTLING: StringName = &"settling"

const MOTION_NONE: StringName = &"none"
const MOTION_DROPPED: StringName = &"dropped"
const MOTION_THROWN: StringName = &"thrown"
const MOTION_UNSUPPORTED: StringName = &"unsupported"

const IMPACT_SOUND_KIND: StringName = &"prop.impact"


@export var prop_id: StringName = &"prop"
@export var visual_model: Mesh
@export var base_color: Color = Color(0.42, 0.27, 0.12, 1.0)
@export var gravity: float = 16.0
@export var terminal_fall_speed: float = 18.0
@export var throw_speed: float = 6.0
@export var impact_sound_strength: float = 0.55
@export var support_probe_distance: float = 0.14
@export var support_probe_inset: float = 1.0
@export var minimum_support_normal_y: float = 0.55

@onready var prop_mesh: MeshInstance3D = $PropMesh
@onready var prop_collision: CollisionShape3D = $CollisionShape3D

var _phase: StringName = PHASE_SETTLED
var _motion_kind: StringName = MOTION_NONE
var _highlighted: bool = false
var _material: StandardMaterial3D = null
var _world_session: Node = null
var _holder: Node = null
var _settling_frames_remaining: int = 0
var _unsupported_frames: int = 0
var _ordinary_collision_layer: int = 1
var _ordinary_collision_mask: int = 1


func _ready() -> void:
	add_to_group(&"vark_interactable")
	_ordinary_collision_layer = collision_layer
	_ordinary_collision_mask = collision_mask
	_world_session = _find_world_session()
	_material = StandardMaterial3D.new()
	prop_mesh.material_override = _material
	if not set_visual_model(visual_model):
		push_error("VarkOrdinaryProp requires a configured visual_model Mesh.")
	_refresh_visual()


func _physics_process(delta: float) -> void:
	match _phase:
		PHASE_SETTLED:
			velocity = Vector3.ZERO
			if _has_support():
				_unsupported_frames = 0
			else:
				_unsupported_frames += 1
				if _unsupported_frames >= 2:
					_begin_motion(MOTION_UNSUPPORTED, Vector3.ZERO)
		PHASE_HELD:
			velocity = Vector3.ZERO
			_unsupported_frames = 0
		PHASE_MOVING:
			_unsupported_frames = 0
			_advance_motion(delta)
		PHASE_SETTLING:
			velocity = Vector3.ZERO
			_unsupported_frames = 0
			_settling_frames_remaining -= 1
			if _settling_frames_remaining <= 0:
				_phase = PHASE_SETTLED
				_motion_kind = MOTION_NONE


func can_interact(interactor: Node) -> bool:
	return (
		_phase != PHASE_HELD
		and interactor != null
		and interactor.has_method("try_carry_prop")
	)


func interact(interactor: Node) -> void:
	if not can_interact(interactor):
		return
	interactor.call("try_carry_prop", self)


func set_interaction_highlighted(highlighted: bool) -> void:
	_highlighted = highlighted
	_refresh_visual()


func is_interaction_highlighted() -> bool:
	return _highlighted


func set_visual_model(model: Mesh) -> bool:
	if model == null:
		return false
	visual_model = model
	if prop_mesh != null:
		prop_mesh.mesh = model
	return true


func get_visual_model() -> Mesh:
	return visual_model


func get_semantic_phase() -> StringName:
	return _phase


func get_motion_kind() -> StringName:
	return _motion_kind


func is_supported() -> bool:
	if _phase == PHASE_HELD:
		return false
	return _has_support()


func begin_held(holder: Node) -> bool:
	if holder == null or _phase == PHASE_HELD:
		return false

	_holder = holder
	_phase = PHASE_HELD
	_motion_kind = MOTION_NONE
	_settling_frames_remaining = 0
	_unsupported_frames = 0
	velocity = Vector3.ZERO
	set_interaction_highlighted(false)
	_set_collision_enabled(false)
	return true


func set_held_pose(pose: Transform3D) -> bool:
	if _phase != PHASE_HELD:
		return false
	global_transform = pose
	velocity = Vector3.ZERO
	return true


func release_from_hold(motion_kind: StringName, initial_velocity: Vector3) -> bool:
	if _phase != PHASE_HELD:
		return false
	if motion_kind != MOTION_DROPPED and motion_kind != MOTION_THROWN:
		return false
	if not _is_finite_vector(initial_velocity):
		return false

	_holder = null
	_set_collision_enabled(true)
	_begin_motion(motion_kind, initial_velocity)
	return true


func capture_semantic_state() -> Dictionary:
	return {
		"phase": _phase,
		"motion_kind": _motion_kind,
		"transform": global_transform,
		"linear_velocity": velocity,
	}


func apply_semantic_state(snapshot: Dictionary) -> bool:
	if snapshot.size() != 4:
		return false
	if (
		not snapshot.has("phase")
		or not snapshot.has("motion_kind")
		or not snapshot.has("transform")
		or not snapshot.has("linear_velocity")
	):
		return false
	if typeof(snapshot["phase"]) != TYPE_STRING_NAME:
		return false
	if typeof(snapshot["motion_kind"]) != TYPE_STRING_NAME:
		return false
	if typeof(snapshot["transform"]) != TYPE_TRANSFORM3D:
		return false
	if typeof(snapshot["linear_velocity"]) != TYPE_VECTOR3:
		return false

	var phase: StringName = snapshot["phase"]
	var motion_kind: StringName = snapshot["motion_kind"]
	var restored_transform: Transform3D = snapshot["transform"]
	var restored_velocity: Vector3 = snapshot["linear_velocity"]
	if not _is_valid_phase(phase) or not _is_valid_motion_kind(motion_kind):
		return false
	if not _is_finite_transform(restored_transform) or not _is_finite_vector(restored_velocity):
		return false
	if (
		(phase == PHASE_SETTLED or phase == PHASE_HELD)
		and (motion_kind != MOTION_NONE or not restored_velocity.is_zero_approx())
	):
		return false
	if (
		(phase == PHASE_MOVING or phase == PHASE_SETTLING)
		and motion_kind == MOTION_NONE
	):
		return false
	if phase == PHASE_SETTLING and not restored_velocity.is_zero_approx():
		return false

	_phase = phase
	_motion_kind = motion_kind
	global_transform = restored_transform
	velocity = restored_velocity
	_holder = null
	_settling_frames_remaining = 1 if phase == PHASE_SETTLING else 0
	_unsupported_frames = 0
	_set_collision_enabled(phase != PHASE_HELD)
	set_interaction_highlighted(false)
	return true


func reconcile_after_restore(holder: Node = null) -> bool:
	if _phase == PHASE_HELD:
		if holder == null or not holder.has_method("reconcile_held_prop"):
			return false
		return bool(holder.call("reconcile_held_prop", self))

	_holder = null
	_set_collision_enabled(true)
	return true


func _begin_motion(motion_kind: StringName, initial_velocity: Vector3) -> void:
	_phase = PHASE_MOVING
	_motion_kind = motion_kind
	_settling_frames_remaining = 0
	_unsupported_frames = 0
	velocity = initial_velocity


func _advance_motion(delta: float) -> void:
	var fall_limit: float = maxf(terminal_fall_speed, 0.1)
	velocity.y = maxf(velocity.y - maxf(gravity, 0.0) * delta, -fall_limit)

	var collision: KinematicCollision3D = move_and_collide(velocity * delta)
	if collision != null:
		_queue_impact_sound()
		var normal: Vector3 = collision.get_normal()
		if normal.y >= minimum_support_normal_y:
			_enter_settling()
			return
		velocity = velocity.slide(normal)
		velocity.x *= 0.35
		velocity.z *= 0.35


func _enter_settling() -> void:
	_phase = PHASE_SETTLING
	_settling_frames_remaining = 1
	_unsupported_frames = 0
	velocity = Vector3.ZERO


func _has_support() -> bool:
	if prop_collision == null or prop_collision.shape == null or not is_inside_tree():
		return false

	var box: BoxShape3D = prop_collision.shape as BoxShape3D
	if box == null:
		return false

	var half: Vector3 = box.size * 0.5
	var inset: float = clampf(support_probe_inset, 0.0, 1.0)
	var x: float = half.x * inset
	var z: float = half.z * inset
	var local_points: Array[Vector3] = [
		Vector3(0.0, -half.y, 0.0),
		Vector3(-x, -half.y, -z),
		Vector3(x, -half.y, -z),
		Vector3(-x, -half.y, z),
		Vector3(x, -half.y, z),
		Vector3(-x, -half.y, 0.0),
		Vector3(x, -half.y, 0.0),
		Vector3(0.0, -half.y, -z),
		Vector3(0.0, -half.y, z),
	]

	for local_point: Vector3 in local_points:
		var bottom: Vector3 = global_transform * local_point
		var origin: Vector3 = bottom + Vector3.UP * 0.04
		var query := PhysicsRayQueryParameters3D.create(
			origin,
			bottom + Vector3.DOWN * maxf(support_probe_distance, 0.05)
		)
		query.exclude = [get_rid()]
		query.collision_mask = _ordinary_collision_mask
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var normal: Vector3 = hit.get("normal", Vector3.UP)
			if normal.y >= minimum_support_normal_y:
				return true
	return false


func _set_collision_enabled(enabled: bool) -> void:
	if enabled:
		collision_layer = _ordinary_collision_layer
		collision_mask = _ordinary_collision_mask
	else:
		collision_layer = 0
		collision_mask = 0


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


func _queue_impact_sound() -> void:
	if _world_session == null:
		return
	var source_session_id: int = int(_world_session.get("session_id"))
	_world_session.call(
		"queue_gameplay_sound",
		source_session_id,
		IMPACT_SOUND_KIND,
		global_position,
		impact_sound_strength
	)


func _find_world_session() -> Node:
	var cursor: Node = get_parent()
	while cursor != null:
		if cursor.has_method("queue_gameplay_sound"):
			return cursor
		cursor = cursor.get_parent()
	return null


func _is_valid_phase(phase: StringName) -> bool:
	return (
		phase == PHASE_SETTLED
		or phase == PHASE_HELD
		or phase == PHASE_MOVING
		or phase == PHASE_SETTLING
	)


func _is_valid_motion_kind(motion_kind: StringName) -> bool:
	return (
		motion_kind == MOTION_NONE
		or motion_kind == MOTION_DROPPED
		or motion_kind == MOTION_THROWN
		or motion_kind == MOTION_UNSUPPORTED
	)


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _is_finite_transform(value: Transform3D) -> bool:
	return (
		_is_finite_vector(value.origin)
		and _is_finite_vector(value.basis.x)
		and _is_finite_vector(value.basis.y)
		and _is_finite_vector(value.basis.z)
	)
