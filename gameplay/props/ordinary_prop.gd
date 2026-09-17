class_name VarkOrdinaryProp
extends RigidBody3D


const PHASE_SETTLED: StringName = &"settled"
const PHASE_CARRIED_JUNK: StringName = &"carried_junk"
const PHASE_MOVING: StringName = &"moving"
const PHASE_SETTLING: StringName = &"settling"

const MOTION_NONE: StringName = &"none"
const MOTION_RELEASED: StringName = &"released"
const MOTION_THROWN: StringName = &"thrown"
const MOTION_UNSUPPORTED: StringName = &"unsupported"

const IMPACT_SOUND_KIND: StringName = &"prop.impact"


@export var prop_id: StringName = &"prop"
@export var visual_model: Mesh
@export var base_color: Color = Color(0.42, 0.27, 0.12, 1.0)
@export var throw_speed: float = 6.0
@export var impact_sound_strength: float = 0.55
@export var gentle_release_sound_scale: float = 0.35
@export var settle_linear_speed: float = 0.12
@export var settle_contact_frames_required: int = 5
@export var support_probe_distance: float = 0.08
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
var _settle_yaw: float = 0.0
var _settle_contact_frames: int = 0
var _unsupported_frames: int = 0
var _last_contact_count: int = 0
var _ordinary_collision_layer: int = 1
var _ordinary_collision_mask: int = 1


func _ready() -> void:
	add_to_group(&"vark_interactable")
	_ordinary_collision_layer = collision_layer
	_ordinary_collision_mask = collision_mask
	_settle_yaw = _yaw_from_basis(global_transform.basis)
	_world_session = _find_world_session()

	# Ordinary props are frozen while settled, but released/unsupported props
	# use the real rigid-body solver for gravity and translational collision.
	contact_monitor = true
	if max_contacts_reported < 8:
		max_contacts_reported = 8
	continuous_cd = true
	lock_rotation = true
	can_sleep = true
	freeze = true
	sleeping = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	_material = StandardMaterial3D.new()
	_material.cull_mode = BaseMaterial3D.CULL_BACK
	_material.roughness = 0.82
	_material.metallic = 0.0
	prop_mesh.material_override = _material
	prop_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if not set_visual_model(visual_model):
		push_error("VarkOrdinaryProp requires a configured visual_model Mesh.")
	_refresh_visual()


func _physics_process(_delta: float) -> void:
	match _phase:
		PHASE_SETTLED:
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			_last_contact_count = 0
			if _has_support():
				_unsupported_frames = 0
			else:
				_unsupported_frames += 1
				if _unsupported_frames >= 2:
					_begin_motion(MOTION_UNSUPPORTED, Vector3.ZERO)
		PHASE_CARRIED_JUNK:
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			_unsupported_frames = 0
			_settle_contact_frames = 0
			_last_contact_count = 0
		PHASE_MOVING, PHASE_SETTLING:
			_unsupported_frames = 0
			angular_velocity = Vector3.ZERO
			_update_dynamic_settling()


func can_interact(interactor: Node) -> bool:
	return _phase != PHASE_CARRIED_JUNK and interactor != null and interactor.has_method("try_carry_prop")


func interact(interactor: Node) -> void:
	if can_interact(interactor):
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
	if _phase == PHASE_CARRIED_JUNK:
		return false
	return _has_support()


func is_world_presentation_enabled() -> bool:
	return prop_mesh != null and prop_mesh.visible and collision_layer != 0 and collision_mask != 0


func get_release_clearance_along(world_direction: Vector3, release_basis: Basis) -> float:
	var box: BoxShape3D = prop_collision.shape as BoxShape3D if prop_collision != null else null
	if box == null:
		return 0.3
	var direction: Vector3 = world_direction.normalized()
	if direction.is_zero_approx():
		return box.size.length() * 0.5
	var local_direction: Vector3 = release_basis.inverse() * direction
	var half: Vector3 = box.size * 0.5
	return (
		absf(local_direction.x) * half.x
		+ absf(local_direction.y) * half.y
		+ absf(local_direction.z) * half.z
	)


func begin_carried_junk(holder: Node) -> bool:
	if holder == null or _phase == PHASE_CARRIED_JUNK:
		return false
	_holder = holder
	_phase = PHASE_CARRIED_JUNK
	_motion_kind = MOTION_NONE
	_settle_contact_frames = 0
	_unsupported_frames = 0
	_last_contact_count = 0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true
	sleeping = true
	set_interaction_highlighted(false)
	_set_world_presentation_enabled(false)
	return true


func release_from_carry(
	motion_kind: StringName,
	release_transform: Transform3D,
	initial_velocity: Vector3
) -> bool:
	if _phase != PHASE_CARRIED_JUNK:
		return false
	if motion_kind != MOTION_RELEASED and motion_kind != MOTION_THROWN:
		return false
	if not _is_finite_transform(release_transform) or not _is_finite_vector(initial_velocity):
		return false
	_holder = null
	global_transform = release_transform
	_set_world_presentation_enabled(true)
	_begin_motion(motion_kind, initial_velocity)
	return true


func capture_semantic_state() -> Dictionary:
	return {
		"phase": _phase,
		"motion_kind": _motion_kind,
		"transform": global_transform,
		"linear_velocity": linear_velocity,
		"settle_yaw": _settle_yaw,
	}


func apply_semantic_state(snapshot: Dictionary) -> bool:
	if snapshot.size() != 4 and snapshot.size() != 5:
		return false
	if not snapshot.has("phase") or not snapshot.has("motion_kind") or not snapshot.has("transform") or not snapshot.has("linear_velocity"):
		return false
	if typeof(snapshot["phase"]) != TYPE_STRING_NAME or typeof(snapshot["motion_kind"]) != TYPE_STRING_NAME:
		return false
	if typeof(snapshot["transform"]) != TYPE_TRANSFORM3D or typeof(snapshot["linear_velocity"]) != TYPE_VECTOR3:
		return false
	if snapshot.has("settle_yaw") and typeof(snapshot["settle_yaw"]) != TYPE_FLOAT and typeof(snapshot["settle_yaw"]) != TYPE_INT:
		return false
	var phase: StringName = snapshot["phase"]
	var motion_kind: StringName = snapshot["motion_kind"]
	var restored_transform: Transform3D = snapshot["transform"]
	var restored_velocity: Vector3 = snapshot["linear_velocity"]
	if not _is_valid_phase(phase) or not _is_valid_motion_kind(motion_kind):
		return false
	if not _is_finite_transform(restored_transform) or not _is_finite_vector(restored_velocity):
		return false
	if (phase == PHASE_SETTLED or phase == PHASE_CARRIED_JUNK) and (motion_kind != MOTION_NONE or not restored_velocity.is_zero_approx()):
		return false
	if (phase == PHASE_MOVING or phase == PHASE_SETTLING) and motion_kind == MOTION_NONE:
		return false

	_phase = phase
	_motion_kind = motion_kind
	global_transform = restored_transform
	linear_velocity = restored_velocity
	angular_velocity = Vector3.ZERO
	_settle_yaw = float(snapshot.get("settle_yaw", _yaw_from_basis(restored_transform.basis)))
	_holder = null
	_settle_contact_frames = 0
	_unsupported_frames = 0
	_last_contact_count = 0
	_set_world_presentation_enabled(phase != PHASE_CARRIED_JUNK)
	set_interaction_highlighted(false)
	if phase == PHASE_SETTLED or phase == PHASE_CARRIED_JUNK:
		freeze = true
		sleeping = true
	else:
		freeze = false
		sleeping = false
	return true


func reconcile_after_restore(holder: Node = null) -> bool:
	if _phase == PHASE_CARRIED_JUNK:
		if holder == null or not holder.has_method("reconcile_carried_junk_prop"):
			return false
		return bool(holder.call("reconcile_carried_junk_prop", self))
	_holder = null
	_set_world_presentation_enabled(true)
	if _phase == PHASE_SETTLED:
		freeze = true
		sleeping = true
	else:
		freeze = false
		sleeping = false
	return true


func _begin_motion(motion_kind: StringName, initial_velocity: Vector3) -> void:
	_phase = PHASE_MOVING
	_motion_kind = motion_kind
	_settle_yaw = _yaw_from_basis(global_transform.basis)
	_settle_contact_frames = 0
	_unsupported_frames = 0
	_last_contact_count = 0
	linear_velocity = initial_velocity
	angular_velocity = Vector3.ZERO
	freeze = false
	sleeping = false


func _update_dynamic_settling() -> void:
	var contact_count: int = get_colliding_bodies().size()
	if contact_count > 0 and _last_contact_count == 0:
		_queue_impact_sound(linear_velocity.length())
	_last_contact_count = contact_count

	var support_y: float = _find_dynamic_support_surface_y()
	if is_finite(support_y) and linear_velocity.length() <= maxf(settle_linear_speed, 0.01):
		_settle_contact_frames += 1
		_phase = PHASE_SETTLING
		if _settle_contact_frames >= maxi(settle_contact_frames_required, 1):
			_settle_now(support_y)
		return

	_settle_contact_frames = 0
	_phase = PHASE_MOVING


func _settle_now(support_y: float) -> void:
	var top_up_basis: Basis = _top_up_basis_for_yaw(_settle_yaw)
	var settled_origin: Vector3 = global_position
	var box: BoxShape3D = prop_collision.shape as BoxShape3D if prop_collision != null else null
	if box != null and is_finite(support_y):
		settled_origin.y = support_y + _vertical_support_extent(top_up_basis, box.size * 0.5)
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(top_up_basis, settled_origin)
	sleeping = true
	_phase = PHASE_SETTLED
	_motion_kind = MOTION_NONE
	_settle_contact_frames = 0
	_unsupported_frames = 0
	_last_contact_count = 0


func _find_dynamic_support_surface_y() -> float:
	if prop_collision == null or prop_collision.shape == null or not is_inside_tree():
		return NAN
	var box: BoxShape3D = prop_collision.shape as BoxShape3D
	if box == null:
		return NAN
	var half: Vector3 = box.size * 0.5
	var local_corners: Array[Vector3] = [
		Vector3(-half.x, -half.y, -half.z), Vector3(half.x, -half.y, -half.z),
		Vector3(-half.x, -half.y, half.z), Vector3(half.x, -half.y, half.z),
		Vector3(-half.x, half.y, -half.z), Vector3(half.x, half.y, -half.z),
		Vector3(-half.x, half.y, half.z), Vector3(half.x, half.y, half.z),
	]
	var world_corners: Array[Vector3] = []
	var lowest_y: float = INF
	for local_corner: Vector3 in local_corners:
		var world_corner: Vector3 = global_transform * local_corner
		world_corners.append(world_corner)
		lowest_y = minf(lowest_y, world_corner.y)

	var best_support_y: float = -INF
	for world_corner: Vector3 in world_corners:
		if world_corner.y > lowest_y + 0.025:
			continue
		var query := PhysicsRayQueryParameters3D.create(
			world_corner + Vector3.UP * 0.035,
			world_corner + Vector3.DOWN * 0.09
		)
		query.exclude = [get_rid()]
		query.collision_mask = _ordinary_collision_mask
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		var normal: Vector3 = hit.get("normal", Vector3.UP)
		if normal.y < minimum_support_normal_y:
			continue
		best_support_y = maxf(best_support_y, float(hit.get("position", world_corner).y))
	return best_support_y if is_finite(best_support_y) else NAN


func _vertical_support_extent(source_basis: Basis, half: Vector3) -> float:
	var basis: Basis = source_basis.orthonormalized()
	return (
		absf(basis.x.y) * half.x
		+ absf(basis.y.y) * half.y
		+ absf(basis.z.y) * half.z
	)

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
		Vector3(-x, -half.y, -z), Vector3(x, -half.y, -z),
		Vector3(-x, -half.y, z), Vector3(x, -half.y, z),
		Vector3(-x, -half.y, 0.0), Vector3(x, -half.y, 0.0),
		Vector3(0.0, -half.y, -z), Vector3(0.0, -half.y, z),
	]
	for local_point: Vector3 in local_points:
		var bottom: Vector3 = global_transform * local_point
		var origin: Vector3 = bottom + Vector3.UP * 0.02
		var query := PhysicsRayQueryParameters3D.create(
			origin,
			bottom + Vector3.DOWN * maxf(support_probe_distance, 0.03)
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


func _set_world_presentation_enabled(enabled: bool) -> void:
	if prop_mesh != null:
		prop_mesh.visible = enabled
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
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if _highlighted else BaseMaterial3D.SHADING_MODE_PER_PIXEL


func _queue_impact_sound(impact_speed: float) -> void:
	if _world_session == null:
		return
	var speed_scale: float = clampf(impact_speed / maxf(throw_speed, 0.1), 0.15, 1.0)
	var strength: float = impact_sound_strength * speed_scale
	if _motion_kind == MOTION_RELEASED:
		strength *= clampf(gentle_release_sound_scale, 0.0, 1.0)
	var source_session_id: int = int(_world_session.get("session_id"))
	_world_session.call("queue_gameplay_sound", source_session_id, IMPACT_SOUND_KIND, global_position, maxf(strength, 0.001))


func _find_world_session() -> Node:
	var cursor: Node = get_parent()
	while cursor != null:
		if cursor.has_method("queue_gameplay_sound"):
			return cursor
		cursor = cursor.get_parent()
	return null


func _yaw_from_basis(source_basis: Basis) -> float:
	var basis: Basis = source_basis.orthonormalized()
	var forward: Vector3 = -basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.000001:
		var right: Vector3 = basis.x
		right.y = 0.0
		if right.length_squared() <= 0.000001:
			return 0.0
		right = right.normalized()
		forward = Vector3(right.z, 0.0, -right.x)
	forward = forward.normalized()
	return atan2(-forward.x, -forward.z)


func _top_up_basis_for_yaw(yaw: float) -> Basis:
	return Basis(Vector3.UP, yaw).orthonormalized()


func _is_valid_phase(phase: StringName) -> bool:
	return phase == PHASE_SETTLED or phase == PHASE_CARRIED_JUNK or phase == PHASE_MOVING or phase == PHASE_SETTLING


func _is_valid_motion_kind(motion_kind: StringName) -> bool:
	return motion_kind == MOTION_NONE or motion_kind == MOTION_RELEASED or motion_kind == MOTION_THROWN or motion_kind == MOTION_UNSUPPORTED


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _is_finite_transform(value: Transform3D) -> bool:
	return _is_finite_vector(value.origin) and _is_finite_vector(value.basis.x) and _is_finite_vector(value.basis.y) and _is_finite_vector(value.basis.z)
