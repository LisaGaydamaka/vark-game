class_name VarkOrdinaryProp
extends RigidBody3D


const PHASE_SETTLED: StringName = &"settled"
const PHASE_CARRIED_JUNK: StringName = &"carried_junk"
const PHASE_MOVING: StringName = &"moving"

const MOTION_NONE: StringName = &"none"
const MOTION_RELEASED: StringName = &"released"
const MOTION_THROWN: StringName = &"thrown"
const MOTION_UNSUPPORTED: StringName = &"unsupported"
const MOTION_DISTURBED: StringName = &"disturbed"

const PLAYER_PUSH_MIN_SPEED: float = 0.15
const PROP_IMPACT_MIN_IMPULSE: float = 0.035
const PROP_IMPACT_TRANSFER_SCALE: float = 0.60
const PROP_IMPACT_MAX_IMPULSE: float = 3.25

const IMPACT_SOUND_KIND: StringName = &"prop.impact"

const PROP_VARIANT_ORDINARY_CRATE: String = "ordinary_crate"
const PROP_VARIANT_TALL_CRATE: String = "tall_crate"
const PROP_VARIANT_TALL_MODEL_PATH: String = (
	"res://assets/models/props/ordinary_crate_tall.obj"
)
const PROP_VARIANT_DEFAULT_COLLISION_SIZE: Vector3 = Vector3(0.6, 0.6, 0.6)
const PROP_VARIANT_TALL_COLLISION_SIZE: Vector3 = Vector3(0.5, 0.7, 0.5)

# Dedicated physics categories let an overlapping released prop ignore the
# player without disabling collision with the world or other props.
const COLLISION_LAYER_WORLD: int = 1 << 0
const COLLISION_LAYER_PLAYER: int = 1 << 1
const COLLISION_LAYER_ORDINARY_PROP: int = 1 << 2
const COLLISION_LAYER_PROP_IGNORING_PLAYER: int = 1 << 3


@export var persistent_id: String = ""
@export var prop_id: StringName = &"prop"
@export var prop_variant: String = "ordinary_crate"
@export var visual_model: Mesh
@export var visual_model_path: String = ""
@export var collision_size: Vector3 = Vector3(0.6, 0.6, 0.6)
@export var base_color: Color = Color(0.42, 0.27, 0.12, 1.0)
@export var throw_speed: float = 6.0
@export var impact_sound_strength: float = 0.55
@export var gentle_release_sound_scale: float = 0.35
@export var rest_linear_speed: float = 0.12
@export var rest_contact_frames_required: int = 5
@export var player_push_speed_scale: float = 0.32
@export var player_push_min_motion_speed: float = 0.40
@export var player_push_max_motion_speed: float = 1.00
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
var _rest_contact_frames: int = 0
var _unsupported_frames: int = 0
var _last_contact_count: int = 0
var _ordinary_collision_layer: int = 1
var _ordinary_collision_mask: int = 1
var _dynamic_contact_count: int = 0
var _dynamic_support_valid: bool = false
var _temporarily_ignored_player: PhysicsBody3D = null
var _pending_rigid_launch: bool = false
var _pending_launch_transform: Transform3D = Transform3D.IDENTITY
var _pending_launch_velocity: Vector3 = Vector3.ZERO
var _pending_prop_impacts: Array[Dictionary] = []
var _pending_external_impulse: Vector3 = Vector3.ZERO
var _pending_player_push_velocity: Vector3 = Vector3.ZERO
var _moving_support_source: CollisionObject3D = null


func _ready() -> void:
	add_to_group(&"vark_interactable")
	_ordinary_collision_layer = collision_layer
	_ordinary_collision_mask = collision_mask
	_world_session = _find_world_session()
	global_transform = _top_up_transform(global_transform)
	_apply_authored_variant_defaults()
	if not _configure_collision_shape():
		push_error("VarkOrdinaryProp requires a BoxShape3D collision shape.")

	# Ordinary props are frozen while settled, but released/unsupported props
	# use the real rigid-body solver for gravity and translational collision.
	# Rotation is deliberately locked for the whole ordinary-prop lifecycle: the
	# top face is always world-up and only horizontal yaw is preserved.
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
	var configured_visual: Mesh = visual_model
	if visual_model_path.strip_edges().is_empty():
		if not _apply_visual_model(configured_visual, true):
			push_error("VarkOrdinaryProp requires a configured visual_model Mesh.")
	else:
		var requested_path: String = visual_model_path
		if not set_visual_model_from_path(requested_path):
			visual_model_path = requested_path
			if not _apply_visual_model(configured_visual, false):
				push_error(
					"VarkOrdinaryProp could not load visual_model_path '%s' and has no fallback Mesh."
					% requested_path
				)
			else:
				push_error(
					"VarkOrdinaryProp could not load visual_model_path '%s'; using the default compatible model."
					% requested_path
				)
	_refresh_visual()


func _physics_process(_delta: float) -> void:
	match _phase:
		PHASE_SETTLED:
			_update_settled_state()
		PHASE_CARRIED_JUNK:
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			_unsupported_frames = 0
			_rest_contact_frames = 0
			_last_contact_count = 0
			_clear_dynamic_contact_state()
		PHASE_MOVING:
			_unsupported_frames = 0
			angular_velocity = Vector3.ZERO
			_dispatch_pending_prop_impacts()
			_update_dynamic_rest()
	_update_temporary_player_collision_ignore()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _pending_rigid_launch:
		# Commit the carry->world handoff through the synchronized direct-body
		# state. This avoids splitting a mode change, transform change, collision
		# filter change, and launch velocity across unrelated PhysicsServer writes.
		state.transform = _pending_launch_transform
		state.collision_layer = collision_layer
		state.collision_mask = collision_mask
		state.linear_velocity = _pending_launch_velocity
		state.angular_velocity = Vector3.ZERO
		state.sleeping = false
		_pending_rigid_launch = false
		_pending_launch_velocity = Vector3.ZERO
		can_sleep = true

	if not _pending_external_impulse.is_zero_approx():
		state.apply_central_impulse(_pending_external_impulse)
		state.sleeping = false
		_pending_external_impulse = Vector3.ZERO

	if not _pending_player_push_velocity.is_zero_approx():
		var push_direction: Vector3 = _pending_player_push_velocity.normalized()
		var target_speed: float = _pending_player_push_velocity.length()
		var current_horizontal := Vector3(
			state.linear_velocity.x,
			0.0,
			state.linear_velocity.z
		)
		var current_along_push: float = current_horizontal.dot(push_direction)
		if current_along_push < target_speed:
			state.linear_velocity += push_direction * (target_speed - current_along_push)
		state.sleeping = false
		_pending_player_push_velocity = Vector3.ZERO

	if _phase != PHASE_MOVING:
		return

	# lock_rotation prevents solver angular response, and this direct-state
	# normalization also closes any external/restore path that could introduce a
	# tilted basis while the body is live. Translation remains fully physical.
	state.transform = _top_up_transform(state.transform)
	state.angular_velocity = Vector3.ZERO
	_capture_dynamic_contact_state(state)


func _capture_dynamic_contact_state(state: PhysicsDirectBodyState3D) -> void:
	_pending_prop_impacts.clear()
	_dynamic_contact_count = state.get_contact_count()
	_dynamic_support_valid = false
	var body_origin: Vector3 = state.transform.origin
	var impact_target_ids: Dictionary = {}
	for contact_index: int in range(_dynamic_contact_count):
		var collider: Object = state.get_contact_collider_object(contact_index)
		if collider != null and collider != self and collider.has_method("receive_prop_impact"):
			var collider_id: int = collider.get_instance_id()
			if not impact_target_ids.has(collider_id):
				impact_target_ids[collider_id] = true
				_pending_prop_impacts.append({
					"body": collider,
					"target_impulse": -state.get_contact_impulse(contact_index),
				})
		var local_point: Vector3 = state.get_contact_local_position(contact_index)
		if local_point.y > body_origin.y + 0.05:
			continue
		var normal: Vector3 = state.get_contact_local_normal(contact_index)
		if normal.length_squared() <= 0.000001:
			continue
		normal = normal.normalized()
		if normal.y < 0.0:
			normal = -normal
		if normal.y >= minimum_support_normal_y:
			_dynamic_support_valid = true


func is_vark_persistent_entity() -> bool:
	return not persistent_id.strip_edges().is_empty()


func get_persistent_id() -> String:
	return persistent_id


func get_content_id() -> String:
	return str(prop_id)


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


func _apply_authored_variant_defaults() -> void:
	if not visual_model_path.strip_edges().is_empty():
		return
	if prop_variant.strip_edges() != PROP_VARIANT_TALL_CRATE:
		return

	visual_model_path = PROP_VARIANT_TALL_MODEL_PATH
	if collision_size.is_equal_approx(PROP_VARIANT_DEFAULT_COLLISION_SIZE):
		collision_size = PROP_VARIANT_TALL_COLLISION_SIZE


func set_visual_model(model: Mesh) -> bool:
	return _apply_visual_model(model, true)


func set_visual_model_from_path(path: String) -> bool:
	var normalized_path: String = path.strip_edges()
	if normalized_path.is_empty() or not ResourceLoader.exists(normalized_path):
		return false
	var loaded: Resource = ResourceLoader.load(normalized_path)
	if not (loaded is Mesh):
		return false
	visual_model_path = normalized_path
	return _apply_visual_model(loaded as Mesh, false)


func get_visual_model() -> Mesh:
	return visual_model


func get_visual_model_path() -> String:
	return visual_model_path


func get_collision_size() -> Vector3:
	var box := prop_collision.shape as BoxShape3D if prop_collision != null else null
	return box.size if box != null else Vector3.ZERO


func _apply_visual_model(model: Mesh, update_path: bool) -> bool:
	if model == null:
		return false
	visual_model = model
	if update_path and not model.resource_path.is_empty():
		visual_model_path = model.resource_path
	if prop_mesh != null:
		prop_mesh.mesh = model
	return true


func _configure_collision_shape() -> bool:
	if prop_collision == null:
		return false
	var source_box := prop_collision.shape as BoxShape3D
	if source_box == null:
		return false
	collision_size = Vector3(
		maxf(absf(collision_size.x), 0.05),
		maxf(absf(collision_size.y), 0.05),
		maxf(absf(collision_size.z), 0.05)
	)
	# Preserve the accepted Phase 3 default physics resource exactly when the
	# authored dimensions are unchanged. Only a real per-instance size variant
	# needs a localized shape resource.
	if source_box.size.is_equal_approx(collision_size):
		return true
	var box := source_box.duplicate() as BoxShape3D
	if box == null:
		return false
	box.size = collision_size
	prop_collision.shape = box
	return true


func get_semantic_phase() -> StringName:
	return _phase


func get_motion_kind() -> StringName:
	return _motion_kind


func is_supported() -> bool:
	if _phase == PHASE_CARRIED_JUNK:
		return false
	return _has_support()


func is_supported_by(body: CollisionObject3D) -> bool:
	if (
		_phase == PHASE_CARRIED_JUNK
		or body == null
		or not is_instance_valid(body)
	):
		return false
	return _find_support_rid() == body.get_rid()


func get_collision_world_bottom_y() -> float:
	var box := prop_collision.shape as BoxShape3D if prop_collision != null else null
	if box == null:
		return global_position.y
	var collision_transform: Transform3D = prop_collision.global_transform
	var half: Vector3 = box.size * 0.5
	var vertical_extent: float = (
		absf(collision_transform.basis.x.y) * half.x
		+ absf(collision_transform.basis.y.y) * half.y
		+ absf(collision_transform.basis.z.y) * half.z
	)
	return collision_transform.origin.y - vertical_extent


func release_from_moving_support(support_body: CollisionObject3D) -> bool:
	if (
		_phase != PHASE_SETTLED
		or support_body == null
		or not is_instance_valid(support_body)
		or not is_supported_by(support_body)
	):
		return false
	_begin_motion(MOTION_UNSUPPORTED, Vector3.ZERO)
	_moving_support_source = support_body
	return true


func is_released_from_moving_support(support_body: CollisionObject3D) -> bool:
	return (
		_phase == PHASE_MOVING
		and support_body != null
		and is_instance_valid(support_body)
		and _moving_support_source != null
		and is_instance_valid(_moving_support_source)
		and _moving_support_source == support_body
	)


func is_traversal_attachment_stable() -> bool:
	# Long-lived catch/hang/corner attachments require an exact stationary prop.
	# Mantle is short-lived and tracks its source collider transform separately.
	return _phase == PHASE_SETTLED


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


func is_release_transform_world_clear(
	release_transform: Transform3D,
	ignored_body: PhysicsBody3D = null
) -> bool:
	if prop_collision == null or prop_collision.shape == null or not is_inside_tree():
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = prop_collision.shape
	query.transform = release_transform * prop_collision.transform
	query.collision_mask = _ordinary_collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.margin = 0.001
	var excluded: Array[RID] = [get_rid()]
	if ignored_body != null and is_instance_valid(ignored_body):
		excluded.append(ignored_body.get_rid())
	query.exclude = excluded
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func is_temporarily_ignoring_player_collision() -> bool:
	return (
		_temporarily_ignored_player != null
		and is_instance_valid(_temporarily_ignored_player)
	)


func begin_carried_junk(holder: Node) -> bool:
	if holder == null or _phase == PHASE_CARRIED_JUNK:
		return false
	_clear_pending_rigid_launch()
	_clear_temporary_player_collision_ignore()
	_clear_dynamic_contact_state()
	_moving_support_source = null
	_holder = holder
	_phase = PHASE_CARRIED_JUNK
	_motion_kind = MOTION_NONE
	_rest_contact_frames = 0
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
	initial_velocity: Vector3,
	releasing_player: PhysicsBody3D = null
) -> bool:
	if _phase != PHASE_CARRIED_JUNK:
		return false
	if motion_kind != MOTION_RELEASED and motion_kind != MOTION_THROWN:
		return false
	if not _is_finite_transform(release_transform) or not _is_finite_vector(initial_velocity):
		return false
	var upright_release_transform: Transform3D = _top_up_transform(release_transform)
	# Carry->world orientation is semantic physics state. Both F and R enter the
	# world top-up and remain top-up for their entire dynamic lifetime.
	_clear_temporary_player_collision_ignore()
	_holder = null
	global_transform = upright_release_transform
	var overlaps_releasing_player: bool = (
		releasing_player != null
		and is_instance_valid(releasing_player)
		and _shape_overlaps_body_at_transform(upright_release_transform, releasing_player)
	)
	if prop_mesh != null:
		prop_mesh.visible = true
	if overlaps_releasing_player:
		_begin_temporary_player_collision_ignore(releasing_player)
	else:
		collision_layer = _ordinary_collision_layer
		collision_mask = _ordinary_collision_mask
	# F and R differ only by motion kind/velocity. The body becomes live now,
	# while the exact transform + velocity commit is synchronized with Jolt in
	# _integrate_forces() on the first active rigid-body step.
	_stage_rigid_launch(motion_kind, upright_release_transform, initial_velocity)
	return true


func capture_semantic_state() -> Dictionary:
	return {
		"phase": _phase,
		"motion_kind": _motion_kind,
		"transform": _pending_launch_transform if _pending_rigid_launch else global_transform,
		"linear_velocity": _pending_launch_velocity if _pending_rigid_launch else linear_velocity,
	}


func apply_semantic_state(snapshot: Dictionary) -> bool:
	if snapshot.size() != 4:
		return false
	if not snapshot.has("phase") or not snapshot.has("motion_kind") or not snapshot.has("transform") or not snapshot.has("linear_velocity"):
		return false
	if typeof(snapshot["phase"]) != TYPE_STRING_NAME or typeof(snapshot["motion_kind"]) != TYPE_STRING_NAME:
		return false
	if typeof(snapshot["transform"]) != TYPE_TRANSFORM3D or typeof(snapshot["linear_velocity"]) != TYPE_VECTOR3:
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
	if phase == PHASE_MOVING and motion_kind == MOTION_NONE:
		return false

	_clear_pending_rigid_launch()
	_clear_temporary_player_collision_ignore()
	_clear_dynamic_contact_state()
	_moving_support_source = null
	_phase = phase
	_motion_kind = motion_kind
	global_transform = _top_up_transform(restored_transform)
	linear_velocity = restored_velocity
	angular_velocity = Vector3.ZERO
	_holder = null
	_rest_contact_frames = 0
	_unsupported_frames = 0
	_last_contact_count = 0
	_set_world_presentation_enabled(phase != PHASE_CARRIED_JUNK)
	set_interaction_highlighted(false)
	if phase == PHASE_CARRIED_JUNK or phase == PHASE_SETTLED:
		freeze = true
		sleeping = true
		return true
	freeze = false
	sleeping = false
	return true


func reconcile_after_restore(holder: Node = null) -> bool:
	if _phase == PHASE_CARRIED_JUNK:
		# Keep the established explicit-holder restore seam for callers/tests,
		# while allowing the generic Phase 4.2 restore pass to omit the argument.
		if holder == null and _world_session != null and is_instance_valid(_world_session):
			holder = _world_session.get("player") as Node
		if holder == null or not holder.has_method("reconcile_carried_junk_prop"):
			return false
		return bool(holder.call("reconcile_carried_junk_prop", self))
	_holder = null
	_clear_temporary_player_collision_ignore()
	_set_world_presentation_enabled(true)
	global_transform = _top_up_transform(global_transform)
	if _phase == PHASE_SETTLED:
		freeze = true
		sleeping = true
	else:
		freeze = false
		sleeping = false
	return true


func _stage_rigid_launch(
	motion_kind: StringName,
	release_transform: Transform3D,
	initial_velocity: Vector3
) -> void:
	_moving_support_source = null
	_phase = PHASE_MOVING
	_motion_kind = motion_kind
	_rest_contact_frames = 0
	_unsupported_frames = 0
	_last_contact_count = 0
	_clear_dynamic_contact_state()
	_pending_launch_transform = _top_up_transform(release_transform)
	_pending_launch_velocity = initial_velocity
	_pending_rigid_launch = true
	# Keep the newly activated body awake until the direct-state callback has
	# consumed the pending launch. Afterwards normal sleeping policy resumes.
	can_sleep = false
	freeze = false
	sleeping = false


func _clear_pending_rigid_launch() -> void:
	_pending_rigid_launch = false
	_pending_launch_transform = Transform3D.IDENTITY
	_pending_launch_velocity = Vector3.ZERO
	can_sleep = true


func _begin_motion(motion_kind: StringName, initial_velocity: Vector3) -> void:
	_moving_support_source = null
	_phase = PHASE_MOVING
	_motion_kind = motion_kind
	global_transform = _top_up_transform(global_transform)
	_rest_contact_frames = 0
	_unsupported_frames = 0
	_last_contact_count = 0
	_clear_dynamic_contact_state()
	linear_velocity = initial_velocity
	angular_velocity = Vector3.ZERO
	freeze = false
	sleeping = false


func _update_dynamic_rest() -> void:
	var contact_count: int = _dynamic_contact_count
	if contact_count > 0 and _last_contact_count == 0:
		_queue_impact_sound(linear_velocity.length())
	_last_contact_count = contact_count
	if _dynamic_support_valid and linear_velocity.length() <= maxf(rest_linear_speed, 0.01):
		_rest_contact_frames += 1
		if _rest_contact_frames >= maxi(rest_contact_frames_required, 1):
			_finish_dynamic_rest()
		return
	_rest_contact_frames = 0


func _finish_dynamic_rest() -> void:
	_clear_pending_rigid_launch()
	global_transform = _top_up_transform(global_transform)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	can_sleep = true
	freeze = true
	sleeping = true
	_phase = PHASE_SETTLED
	_motion_kind = MOTION_NONE
	_moving_support_source = null
	_rest_contact_frames = 0
	_unsupported_frames = 0
	_last_contact_count = 0
	_clear_dynamic_contact_state()


func _update_settled_state() -> void:
	# Settled is intentionally exact/stable. Explicit causes promote the same
	# RigidBody3D back to dynamic motion; background solver stabilization does not.
	global_transform = _top_up_transform(global_transform)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_last_contact_count = 0
	_clear_dynamic_contact_state()
	if _has_support():
		_unsupported_frames = 0
		return
	_unsupported_frames += 1
	if _unsupported_frames >= 2:
		_begin_motion(MOTION_UNSUPPORTED, Vector3.ZERO)


func _clear_dynamic_contact_state() -> void:
	_pending_prop_impacts.clear()
	_pending_external_impulse = Vector3.ZERO
	_pending_player_push_velocity = Vector3.ZERO
	_dynamic_contact_count = 0
	_dynamic_support_valid = false


func _dispatch_pending_prop_impacts() -> void:
	if _pending_prop_impacts.is_empty():
		return
	var pending: Array[Dictionary] = _pending_prop_impacts.duplicate()
	_pending_prop_impacts.clear()
	for impact: Dictionary in pending:
		var body_value: Variant = impact.get("body")
		if not (body_value is Object) or not is_instance_valid(body_value):
			continue
		var body: Object = body_value
		if not body.has_method("receive_prop_impact"):
			continue
		body.call("receive_prop_impact", impact.get("target_impulse", Vector3.ZERO))


func receive_prop_impact(contact_impulse: Vector3) -> bool:
	if _phase != PHASE_SETTLED:
		return false
	var impulse_magnitude: float = contact_impulse.length()
	if impulse_magnitude < PROP_IMPACT_MIN_IMPULSE:
		return false
	var transferred_impulse: Vector3 = contact_impulse * PROP_IMPACT_TRANSFER_SCALE
	if transferred_impulse.length() > PROP_IMPACT_MAX_IMPULSE:
		transferred_impulse = transferred_impulse.normalized() * PROP_IMPACT_MAX_IMPULSE
	if transferred_impulse.is_zero_approx():
		return false
	_begin_motion(MOTION_DISTURBED, Vector3.ZERO)
	_pending_external_impulse += transferred_impulse
	sleeping = false
	return true


func receive_player_push(player_velocity: Vector3) -> bool:
	if _phase == PHASE_CARRIED_JUNK:
		return false
	var horizontal_velocity := Vector3(player_velocity.x, 0.0, player_velocity.z)
	var speed: float = horizontal_velocity.length()
	if speed < PLAYER_PUSH_MIN_SPEED:
		return false
	if _phase == PHASE_SETTLED:
		_begin_motion(MOTION_DISTURBED, linear_velocity)
	var target_speed: float = clampf(
		speed * maxf(player_push_speed_scale, 0.0),
		maxf(player_push_min_motion_speed, 0.0),
		maxf(player_push_max_motion_speed, player_push_min_motion_speed)
	)
	_pending_player_push_velocity = horizontal_velocity.normalized() * target_speed
	sleeping = false
	return true


func _begin_temporary_player_collision_ignore(player: PhysicsBody3D) -> void:
	_temporarily_ignored_player = player
	# Jolt evaluates body pairs from both objects' layers/masks. Move only this
	# prop onto a channel the Player does not scan, while retaining world/prop
	# categories in its mask. This suppresses exactly the player relationship
	# without disabling real rigid-body collision with the environment.
	collision_layer = COLLISION_LAYER_PROP_IGNORING_PLAYER
	collision_mask = (
		(_ordinary_collision_mask | COLLISION_LAYER_WORLD | COLLISION_LAYER_ORDINARY_PROP | COLLISION_LAYER_PROP_IGNORING_PLAYER)
		& ~COLLISION_LAYER_PLAYER
	)


func _update_temporary_player_collision_ignore() -> void:
	if _temporarily_ignored_player == null:
		return
	if not is_instance_valid(_temporarily_ignored_player):
		_clear_temporary_player_collision_ignore()
		return
	if _shape_overlaps_body_at_transform(global_transform, _temporarily_ignored_player):
		return
	_clear_temporary_player_collision_ignore()


func _clear_temporary_player_collision_ignore() -> void:
	_temporarily_ignored_player = null
	collision_layer = _ordinary_collision_layer
	collision_mask = _ordinary_collision_mask


func _shape_overlaps_body_at_transform(body_transform: Transform3D, other_body: PhysicsBody3D) -> bool:
	if (
		other_body == null
		or not is_instance_valid(other_body)
		or prop_collision == null
		or prop_collision.shape == null
		or not is_inside_tree()
	):
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = prop_collision.shape
	query.transform = body_transform * prop_collision.transform
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.margin = 0.001
	query.exclude = [get_rid()]
	var other_rid: RID = other_body.get_rid()
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var hit_collider: Variant = hit.get("collider")
		if hit_collider == other_body:
			return true
		var hit_rid: Variant = hit.get("rid")
		if hit_rid is RID and hit_rid == other_rid:
			return true
	return false


func _has_support() -> bool:
	return _find_support_rid().is_valid()


func _find_support_rid() -> RID:
	if prop_collision == null or prop_collision.shape == null or not is_inside_tree():
		return RID()
	var box: BoxShape3D = prop_collision.shape as BoxShape3D
	if box == null:
		return RID()
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
				var rid_value: Variant = hit.get("rid")
				if rid_value is RID and rid_value.is_valid():
					return rid_value

	var support_query := PhysicsShapeQueryParameters3D.new()
	support_query.shape = prop_collision.shape
	var support_transform: Transform3D = global_transform * prop_collision.transform
	support_transform.origin += Vector3.DOWN * clampf(support_probe_distance, 0.01, 0.04)
	support_query.transform = support_transform
	support_query.exclude = [get_rid()]
	support_query.collision_mask = _ordinary_collision_mask
	support_query.collide_with_areas = false
	support_query.collide_with_bodies = true
	support_query.margin = 0.001
	var rest_info: Dictionary = get_world_3d().direct_space_state.get_rest_info(
		support_query
	)
	if rest_info.is_empty():
		return RID()
	var rest_normal: Vector3 = rest_info.get("normal", Vector3.ZERO)
	if (
		rest_normal.length_squared() <= 0.000001
		or rest_normal.normalized().y < minimum_support_normal_y
	):
		return RID()
	var rest_rid_value: Variant = rest_info.get("rid")
	if rest_rid_value is RID and rest_rid_value.is_valid():
		return rest_rid_value
	return RID()


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


func _top_up_transform(source: Transform3D) -> Transform3D:
	return Transform3D(
		_top_up_basis_for_yaw(_yaw_from_basis(source.basis)),
		source.origin
	)


func _is_valid_phase(phase: StringName) -> bool:
	return phase == PHASE_SETTLED or phase == PHASE_CARRIED_JUNK or phase == PHASE_MOVING


func _is_valid_motion_kind(motion_kind: StringName) -> bool:
	return motion_kind == MOTION_NONE or motion_kind == MOTION_RELEASED or motion_kind == MOTION_THROWN or motion_kind == MOTION_UNSUPPORTED or motion_kind == MOTION_DISTURBED


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _is_finite_transform(value: Transform3D) -> bool:
	return _is_finite_vector(value.origin) and _is_finite_vector(value.basis.x) and _is_finite_vector(value.basis.y) and _is_finite_vector(value.basis.z)
