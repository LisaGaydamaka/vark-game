from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


prop_path = Path("gameplay/props/ordinary_prop.gd")
prop = prop_path.read_text(encoding="utf-8")

prop = replace_once(
    prop,
    'const MOTION_UNSUPPORTED: StringName = &"unsupported"\n',
    'const MOTION_UNSUPPORTED: StringName = &"unsupported"\nconst MOTION_DISTURBED: StringName = &"disturbed"\n\nconst SETTLE_ALIGNMENT_INTERRUPT_SPEED: float = 0.75\nconst PLAYER_PUSH_MIN_SPEED: float = 0.15\n',
    "motion kind constants",
)

prop = replace_once(
    prop,
    '@export var settle_contact_frames_required: int = 5\n@export var support_probe_distance: float = 0.08\n',
    '@export var settle_contact_frames_required: int = 5\n@export var settle_alignment_duration: float = 0.20\n@export var player_push_impulse_scale: float = 0.16\n@export var player_push_max_impulse: float = 0.55\n@export var support_probe_distance: float = 0.08\n',
    "prop physics exports",
)

prop = replace_once(
    prop,
    'var _ordinary_collision_layer: int = 1\nvar _ordinary_collision_mask: int = 1\nvar _dynamic_contact_count: int = 0\n',
    'var _ordinary_collision_layer: int = 1\nvar _ordinary_collision_mask: int = 1\nvar _ordinary_gravity_scale: float = 1.0\nvar _dynamic_contact_count: int = 0\n',
    "ordinary gravity state",
)

prop = replace_once(
    prop,
    'var _pending_rigid_launch: bool = false\nvar _pending_launch_transform: Transform3D = Transform3D.IDENTITY\nvar _pending_launch_velocity: Vector3 = Vector3.ZERO\n',
    'var _pending_rigid_launch: bool = false\nvar _pending_launch_transform: Transform3D = Transform3D.IDENTITY\nvar _pending_launch_velocity: Vector3 = Vector3.ZERO\nvar _settle_alignment_active: bool = false\nvar _settle_alignment_start: Transform3D = Transform3D.IDENTITY\nvar _settle_alignment_target: Transform3D = Transform3D.IDENTITY\nvar _settle_alignment_support_point: Vector3 = Vector3.ZERO\nvar _settle_alignment_support_normal: Vector3 = Vector3.UP\nvar _settle_alignment_elapsed: float = 0.0\nvar _settle_alignment_unsupported_frames: int = 0\n',
    "settle animation state",
)

prop = replace_once(
    prop,
    '\t_ordinary_collision_layer = collision_layer\n\t_ordinary_collision_mask = collision_mask\n\t_settle_yaw = _yaw_from_basis(global_transform.basis)\n',
    '\t_ordinary_collision_layer = collision_layer\n\t_ordinary_collision_mask = collision_mask\n\t_ordinary_gravity_scale = gravity_scale\n\t_settle_yaw = _yaw_from_basis(global_transform.basis)\n',
    "ready gravity capture",
)

prop = replace_once(
    prop,
    '\tcan_sleep = true\n\tfreeze = true\n\tsleeping = true\n',
    '\tcan_sleep = true\n\tfreeze = false\n\tsleeping = true\n',
    "settled ready body state",
)

start = prop.index('func _physics_process(_delta: float) -> void:\n')
end = prop.index('\n\nfunc can_interact(interactor: Node) -> bool:', start)
new_runtime = '''func _physics_process(_delta: float) -> void:
\tmatch _phase:
\t\tPHASE_SETTLED:
\t\t\t_update_settled_state()
\t\tPHASE_CARRIED_JUNK:
\t\t\tlinear_velocity = Vector3.ZERO
\t\t\tangular_velocity = Vector3.ZERO
\t\t\t_unsupported_frames = 0
\t\t\t_settle_contact_frames = 0
\t\t\t_last_contact_count = 0
\t\t\t_clear_dynamic_contact_state()
\t\tPHASE_MOVING:
\t\t\t_unsupported_frames = 0
\t\t\tangular_velocity = Vector3.ZERO
\t\t\t_update_dynamic_settling()
\t\tPHASE_SETTLING:
\t\t\tangular_velocity = Vector3.ZERO
\t\t\t_update_settle_alignment_support()
\t_update_temporary_player_collision_ignore()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
\tif _pending_rigid_launch:
\t\t# Commit the carry->world handoff through the synchronized direct-body
\t\t# state. This avoids splitting a mode change, transform change, collision
\t\t# filter change, and launch velocity across unrelated PhysicsServer writes.
\t\tstate.transform = _pending_launch_transform
\t\tstate.collision_layer = collision_layer
\t\tstate.collision_mask = collision_mask
\t\tstate.linear_velocity = _pending_launch_velocity
\t\tstate.angular_velocity = Vector3.ZERO
\t\tstate.sleeping = false
\t\t_pending_rigid_launch = false
\t\t_pending_launch_velocity = Vector3.ZERO
\t\tcan_sleep = true

\tif _phase == PHASE_SETTLING and _settle_alignment_active:
\t\t_integrate_settle_alignment(state)
\t\treturn
\tif _phase != PHASE_MOVING:
\t\treturn
\t_capture_dynamic_contact_state(state)


func _capture_dynamic_contact_state(state: PhysicsDirectBodyState3D) -> void:
\t_dynamic_contact_count = state.get_contact_count()
\t_dynamic_support_valid = false
\t_dynamic_support_point = Vector3.ZERO
\t_dynamic_support_normal = Vector3.UP
\tvar body_origin: Vector3 = state.transform.origin
\tfor contact_index: int in range(_dynamic_contact_count):
\t\tvar local_point: Vector3 = state.get_contact_local_position(contact_index)
\t\tif local_point.y > body_origin.y + 0.05:
\t\t\tcontinue
\t\tvar normal: Vector3 = state.get_contact_local_normal(contact_index)
\t\tif normal.length_squared() <= 0.000001:
\t\t\tcontinue
\t\tnormal = normal.normalized()
\t\tif normal.y < 0.0:
\t\t\tnormal = -normal
\t\tif normal.y < minimum_support_normal_y:
\t\t\tcontinue
\t\tvar support_point: Vector3 = state.get_contact_collider_position(contact_index)
\t\tif not _dynamic_support_valid or support_point.y > _dynamic_support_point.y:
\t\t\t_dynamic_support_valid = true
\t\t\t_dynamic_support_point = support_point
\t\t\t_dynamic_support_normal = normal


func _integrate_settle_alignment(state: PhysicsDirectBodyState3D) -> void:
\t# The alignment is deliberate settle presentation, not free angular physics.
\t# Gravity is suspended for this short phase, but a meaningful external hit
\t# can still interrupt it and return the same body to ordinary rigid motion.
\tif state.linear_velocity.length() >= SETTLE_ALIGNMENT_INTERRUPT_SPEED:
\t\tvar interrupted_velocity: Vector3 = state.linear_velocity
\t\t_cancel_settle_alignment()
\t\t_phase = PHASE_MOVING
\t\t_motion_kind = MOTION_DISTURBED
\t\t_settle_yaw = _yaw_from_basis(state.transform.basis)
\t\t_settle_contact_frames = 0
\t\t_last_contact_count = 0
\t\tstate.linear_velocity = interrupted_velocity
\t\tstate.angular_velocity = Vector3.ZERO
\t\tstate.sleeping = false
\t\treturn

\tvar duration: float = maxf(settle_alignment_duration, maxf(state.step, 0.001))
\t_settle_alignment_elapsed = minf(_settle_alignment_elapsed + state.step, duration)
\tvar linear_weight: float = clampf(_settle_alignment_elapsed / duration, 0.0, 1.0)
\tvar eased_weight: float = linear_weight * linear_weight * (3.0 - 2.0 * linear_weight)
\tvar next_basis: Basis = _settle_alignment_start.basis.slerp(
\t\t_settle_alignment_target.basis,
\t\teased_weight
\t).orthonormalized()
\tvar next_origin: Vector3 = _origin_reseated_on_support(
\t\tnext_basis,
\t\t_settle_alignment_start.origin,
\t\t_settle_alignment_support_point,
\t\t_settle_alignment_support_normal
\t)
\tstate.transform = Transform3D(next_basis, next_origin)
\tstate.linear_velocity = Vector3.ZERO
\tstate.angular_velocity = Vector3.ZERO
\tstate.sleeping = false

\tif linear_weight < 1.0:
\t\treturn
\tstate.transform = _settle_alignment_target
\tstate.linear_velocity = Vector3.ZERO
\tstate.angular_velocity = Vector3.ZERO
\tstate.sleeping = true
\t_finish_settle_alignment()
'''
prop = prop[:start] + new_runtime + prop[end:]

prop = replace_once(
    prop,
    '\t_clear_pending_rigid_launch()\n\t_clear_temporary_player_collision_ignore()\n\t_clear_dynamic_contact_state()\n\t_holder = holder\n',
    '\t_clear_pending_rigid_launch()\n\t_cancel_settle_alignment()\n\t_clear_temporary_player_collision_ignore()\n\t_clear_dynamic_contact_state()\n\t_holder = holder\n',
    "carry cancels settle alignment",
)

prop = replace_once(
    prop,
    '\t_clear_temporary_player_collision_ignore()\n\t_holder = null\n\tglobal_transform = release_transform\n',
    '\t_cancel_settle_alignment()\n\t_clear_temporary_player_collision_ignore()\n\t_holder = null\n\tglobal_transform = release_transform\n',
    "release cancels settle alignment",
)

capture_start = prop.index('func capture_semantic_state() -> Dictionary:\n')
capture_end = prop.index('\n\nfunc apply_semantic_state(snapshot: Dictionary) -> bool:', capture_start)
new_capture = '''func capture_semantic_state() -> Dictionary:
\tvar snapshot := {
\t\t"phase": _phase,
\t\t"motion_kind": _motion_kind,
\t\t"transform": _pending_launch_transform if _pending_rigid_launch else global_transform,
\t\t"linear_velocity": _pending_launch_velocity if _pending_rigid_launch else linear_velocity,
\t\t"settle_yaw": _settle_yaw,
\t}
\tif _phase == PHASE_SETTLING and _settle_alignment_active:
\t\tvar duration: float = maxf(settle_alignment_duration, 0.001)
\t\tsnapshot["settle_alignment"] = {
\t\t\t"start": _settle_alignment_start,
\t\t\t"target": _settle_alignment_target,
\t\t\t"support_point": _settle_alignment_support_point,
\t\t\t"support_normal": _settle_alignment_support_normal,
\t\t\t"progress": clampf(_settle_alignment_elapsed / duration, 0.0, 1.0),
\t\t}
\treturn snapshot
'''
prop = prop[:capture_start] + new_capture + prop[capture_end:]

apply_start = prop.index('func apply_semantic_state(snapshot: Dictionary) -> bool:\n')
apply_end = prop.index('\n\nfunc reconcile_after_restore(holder: Node = null) -> bool:', apply_start)
new_apply = '''func apply_semantic_state(snapshot: Dictionary) -> bool:
\tif snapshot.size() < 4 or snapshot.size() > 6:
\t\treturn false
\tif not snapshot.has("phase") or not snapshot.has("motion_kind") or not snapshot.has("transform") or not snapshot.has("linear_velocity"):
\t\treturn false
\tif typeof(snapshot["phase"]) != TYPE_STRING_NAME or typeof(snapshot["motion_kind"]) != TYPE_STRING_NAME:
\t\treturn false
\tif typeof(snapshot["transform"]) != TYPE_TRANSFORM3D or typeof(snapshot["linear_velocity"]) != TYPE_VECTOR3:
\t\treturn false
\tif snapshot.has("settle_yaw") and typeof(snapshot["settle_yaw"]) != TYPE_FLOAT and typeof(snapshot["settle_yaw"]) != TYPE_INT:
\t\treturn false
\tif snapshot.has("settle_alignment") and typeof(snapshot["settle_alignment"]) != TYPE_DICTIONARY:
\t\treturn false
\tvar phase: StringName = snapshot["phase"]
\tvar motion_kind: StringName = snapshot["motion_kind"]
\tvar restored_transform: Transform3D = snapshot["transform"]
\tvar restored_velocity: Vector3 = snapshot["linear_velocity"]
\tif not _is_valid_phase(phase) or not _is_valid_motion_kind(motion_kind):
\t\treturn false
\tif not _is_finite_transform(restored_transform) or not _is_finite_vector(restored_velocity):
\t\treturn false
\tif (phase == PHASE_SETTLED or phase == PHASE_CARRIED_JUNK) and (motion_kind != MOTION_NONE or not restored_velocity.is_zero_approx()):
\t\treturn false
\tif (phase == PHASE_MOVING or phase == PHASE_SETTLING) and motion_kind == MOTION_NONE:
\t\treturn false
\tif snapshot.has("settle_alignment") and phase != PHASE_SETTLING:
\t\treturn false

\t_clear_pending_rigid_launch()
\t_cancel_settle_alignment()
\t_clear_temporary_player_collision_ignore()
\t_clear_dynamic_contact_state()
\t_phase = phase
\t_motion_kind = motion_kind
\tglobal_transform = restored_transform
\tlinear_velocity = restored_velocity
\tangular_velocity = Vector3.ZERO
\t_settle_yaw = float(snapshot.get("settle_yaw", _yaw_from_basis(restored_transform.basis)))
\t_holder = null
\t_settle_contact_frames = 0
\t_unsupported_frames = 0
\t_last_contact_count = 0
\t_set_world_presentation_enabled(phase != PHASE_CARRIED_JUNK)
\tset_interaction_highlighted(false)
\tif phase == PHASE_CARRIED_JUNK:
\t\tfreeze = true
\t\tsleeping = true
\t\treturn true
\tif phase == PHASE_SETTLED:
\t\tfreeze = false
\t\tsleeping = true
\t\treturn true
\tif phase == PHASE_SETTLING:
\t\tvar alignment: Dictionary = snapshot.get("settle_alignment", {})
\t\tif alignment.is_empty():
\t\t\t# Legacy settling snapshots did not carry interpolation state. Resume as
\t\t\t# ordinary motion and let contact truth rediscover a fresh settle.
\t\t\t_phase = PHASE_MOVING
\t\t\tfreeze = false
\t\t\tsleeping = false
\t\t\treturn true
\t\tif not _restore_settle_alignment_snapshot(alignment):
\t\t\treturn false
\t\treturn true
\tfreeze = false
\tsleeping = false
\treturn true
'''
prop = prop[:apply_start] + new_apply + prop[apply_end:]

prop = replace_once(
    prop,
    '\tif _phase == PHASE_SETTLED:\n\t\tfreeze = true\n\t\tsleeping = true\n\telse:\n\t\tfreeze = false\n\t\tsleeping = false\n\treturn true\n',
    '\tif _phase == PHASE_SETTLED:\n\t\tfreeze = false\n\t\tsleeping = true\n\telif _phase == PHASE_SETTLING and _settle_alignment_active:\n\t\tfreeze = false\n\t\tsleeping = false\n\telse:\n\t\tfreeze = false\n\t\tsleeping = false\n\treturn true\n',
    "restore settled sleeping state",
)

prop = replace_once(
    prop,
    'func _begin_motion(motion_kind: StringName, initial_velocity: Vector3) -> void:\n\t_phase = PHASE_MOVING\n',
    'func _begin_motion(motion_kind: StringName, initial_velocity: Vector3) -> void:\n\t_cancel_settle_alignment()\n\t_phase = PHASE_MOVING\n',
    "motion cancels settle alignment",
)

settle_start = prop.index('func _update_dynamic_settling() -> void:\n')
settle_end = prop.index('\n\nfunc _support_extent_along_normal', settle_start)
new_settle = '''func _update_dynamic_settling() -> void:
\tvar contact_count: int = _dynamic_contact_count
\tif contact_count > 0 and _last_contact_count == 0:
\t\t_queue_impact_sound(linear_velocity.length())
\t_last_contact_count = contact_count
\tif _dynamic_support_valid and linear_velocity.length() <= maxf(settle_linear_speed, 0.01):
\t\t_settle_contact_frames += 1
\t\tif _settle_contact_frames >= maxi(settle_contact_frames_required, 1):
\t\t\t_begin_settle_alignment(_dynamic_support_point, _dynamic_support_normal)
\t\treturn
\t_settle_contact_frames = 0


func _begin_settle_alignment(support_point: Vector3, support_normal: Vector3) -> void:
\t_clear_pending_rigid_launch()
\tvar normal: Vector3 = support_normal.normalized() if support_normal.length_squared() > 0.000001 else Vector3.UP
\tvar target_basis: Basis = _top_up_basis_for_yaw(_settle_yaw)
\tvar target_origin: Vector3 = _origin_reseated_on_support(
\t\ttarget_basis,
\t\tglobal_position,
\t\tsupport_point,
\t\tnormal
\t)
\t_settle_alignment_active = true
\t_settle_alignment_start = global_transform
\t_settle_alignment_target = Transform3D(target_basis, target_origin)
\t_settle_alignment_support_point = support_point
\t_settle_alignment_support_normal = normal
\t_settle_alignment_elapsed = 0.0
\t_settle_alignment_unsupported_frames = 0
\t_phase = PHASE_SETTLING
\tlinear_velocity = Vector3.ZERO
\tangular_velocity = Vector3.ZERO
\tgravity_scale = 0.0
\tcan_sleep = false
\tfreeze = false
\tsleeping = false
\t_clear_dynamic_contact_state()


func _finish_settle_alignment() -> void:
\t_settle_alignment_active = false
\t_settle_alignment_elapsed = 0.0
\t_settle_alignment_unsupported_frames = 0
\tgravity_scale = _ordinary_gravity_scale
\tcan_sleep = true
\tfreeze = false
\tsleeping = true
\t_phase = PHASE_SETTLED
\t_motion_kind = MOTION_NONE
\t_settle_contact_frames = 0
\t_unsupported_frames = 0
\t_last_contact_count = 0
\t_clear_dynamic_contact_state()


func _cancel_settle_alignment() -> void:
\tif not _settle_alignment_active and gravity_scale == _ordinary_gravity_scale:
\t\treturn
\t_settle_alignment_active = false
\t_settle_alignment_elapsed = 0.0
\t_settle_alignment_unsupported_frames = 0
\tgravity_scale = _ordinary_gravity_scale
\tcan_sleep = true


func _update_settle_alignment_support() -> void:
\tif not _settle_alignment_active:
\t\t_phase = PHASE_MOVING
\t\treturn
\tif _has_support():
\t\t_settle_alignment_unsupported_frames = 0
\t\treturn
\t_settle_alignment_unsupported_frames += 1
\tif _settle_alignment_unsupported_frames < 2:
\t\treturn
\tvar velocity_before_fall: Vector3 = linear_velocity
\t_cancel_settle_alignment()
\t_begin_motion(MOTION_UNSUPPORTED, velocity_before_fall)


func _update_settled_state() -> void:
\tangular_velocity = Vector3.ZERO
\t_last_contact_count = 0
\t_clear_dynamic_contact_state()
\tif not sleeping and linear_velocity.length() > maxf(settle_linear_speed, 0.01):
\t\t_begin_motion(MOTION_DISTURBED, linear_velocity)
\t\treturn
\tif _has_support():
\t\t_unsupported_frames = 0
\t\tif not sleeping:
\t\t\tlinear_velocity = Vector3.ZERO
\t\t\tsleeping = true
\t\treturn
\t_unsupported_frames += 1
\tif _unsupported_frames >= 2:
\t\t_begin_motion(MOTION_UNSUPPORTED, linear_velocity)


func _origin_reseated_on_support(
\tsettled_basis: Basis,
\treference_origin: Vector3,
\tsupport_point: Vector3,
\tsupport_normal: Vector3
) -> Vector3:
\tvar origin: Vector3 = reference_origin
\tvar box: BoxShape3D = prop_collision.shape as BoxShape3D if prop_collision != null else null
\tvar normal: Vector3 = support_normal
\tif normal.length_squared() <= 0.000001:
\t\tnormal = Vector3.UP
\telse:
\t\tnormal = normal.normalized()
\tif box == null or normal.y < minimum_support_normal_y:
\t\treturn origin
\tvar support_extent: float = _support_extent_along_normal(
\t\tsettled_basis,
\t\tbox.size * 0.5,
\t\tnormal
\t)
\tvar horizontal_delta := Vector3(
\t\torigin.x - support_point.x,
\t\t0.0,
\t\torigin.z - support_point.z
\t)
\torigin.y = support_point.y + (
\t\tsupport_extent
\t\t- normal.x * horizontal_delta.x
\t\t- normal.z * horizontal_delta.z
\t) / normal.y
\treturn origin


func _restore_settle_alignment_snapshot(alignment: Dictionary) -> bool:
\tfor required_key: String in ["start", "target", "support_point", "support_normal", "progress"]:
\t\tif not alignment.has(required_key):
\t\t\treturn false
\tif typeof(alignment["start"]) != TYPE_TRANSFORM3D or typeof(alignment["target"]) != TYPE_TRANSFORM3D:
\t\treturn false
\tif typeof(alignment["support_point"]) != TYPE_VECTOR3 or typeof(alignment["support_normal"]) != TYPE_VECTOR3:
\t\treturn false
\tif typeof(alignment["progress"]) != TYPE_FLOAT and typeof(alignment["progress"]) != TYPE_INT:
\t\treturn false
\tvar start_transform: Transform3D = alignment["start"]
\tvar target_transform: Transform3D = alignment["target"]
\tvar support_point: Vector3 = alignment["support_point"]
\tvar support_normal: Vector3 = alignment["support_normal"]
\tvar progress: float = float(alignment["progress"])
\tif not _is_finite_transform(start_transform) or not _is_finite_transform(target_transform):
\t\treturn false
\tif not _is_finite_vector(support_point) or not _is_finite_vector(support_normal):
\t\treturn false
\tif progress < 0.0 or progress > 1.0:
\t\treturn false
\t_settle_alignment_active = true
\t_settle_alignment_start = start_transform
\t_settle_alignment_target = target_transform
\t_settle_alignment_support_point = support_point
\t_settle_alignment_support_normal = support_normal.normalized() if support_normal.length_squared() > 0.000001 else Vector3.UP
\t_settle_alignment_elapsed = progress * maxf(settle_alignment_duration, 0.001)
\t_settle_alignment_unsupported_frames = 0
\tgravity_scale = 0.0
\tcan_sleep = false
\tfreeze = false
\tsleeping = false
\tlinear_velocity = Vector3.ZERO
\tangular_velocity = Vector3.ZERO
\treturn true
'''
prop = prop[:settle_start] + new_settle + prop[settle_end:]

insert_at = prop.index('\n\nfunc _begin_temporary_player_collision_ignore')
player_push = '''

func receive_player_push(player_velocity: Vector3) -> bool:
\tif _phase == PHASE_CARRIED_JUNK:
\t\treturn false
\tvar horizontal_velocity := Vector3(player_velocity.x, 0.0, player_velocity.z)
\tvar speed: float = horizontal_velocity.length()
\tif speed < PLAYER_PUSH_MIN_SPEED:
\t\treturn false
\tvar impulse_strength: float = minf(
\t\tspeed * maxf(player_push_impulse_scale, 0.0),
\t\tmaxf(player_push_max_impulse, 0.0)
\t)
\tif impulse_strength <= 0.0:
\t\treturn false
\tif _phase == PHASE_SETTLED or _phase == PHASE_SETTLING:
\t\t_begin_motion(MOTION_DISTURBED, linear_velocity)
\tsleeping = false
\tapply_central_impulse(horizontal_velocity.normalized() * impulse_strength)
\treturn true
'''
prop = prop[:insert_at] + player_push + prop[insert_at:]

prop = replace_once(
    prop,
    'return motion_kind == MOTION_NONE or motion_kind == MOTION_RELEASED or motion_kind == MOTION_THROWN or motion_kind == MOTION_UNSUPPORTED\n',
    'return motion_kind == MOTION_NONE or motion_kind == MOTION_RELEASED or motion_kind == MOTION_THROWN or motion_kind == MOTION_UNSUPPORTED or motion_kind == MOTION_DISTURBED\n',
    "valid disturbed motion kind",
)

prop_path.write_text(prop, encoding="utf-8")

# Settled props are sleeping/wakeable rigid bodies. Carried Junk still freezes.
tscn_path = Path("gameplay/props/OrdinaryProp.tscn")
tscn = tscn_path.read_text(encoding="utf-8")ntscn = replace_once(tscn, 'lock_rotation = true\nfreeze = true\n', 'lock_rotation = true\nsleeping = true\n', "ordinary prop initial sleep")
tscn_path.write_text(tscn, encoding="utf-8")

# Player locomotion owns the CharacterBody collision transaction, so it is the
# one place that translates a lateral player contact into a bounded prop push.
controller_path = Path("player/locomotion/player_locomotion_controller.gd")
controller = controller_path.read_text(encoding="utf-8")
controller = replace_once(
    controller,
    '\tvar collisions: Array[KinematicCollision3D] = []\n\tif step_traversal_active or not support.has_support:\n',
    '\tvar prop_push_source_velocity: Vector3 = body.velocity\n\tvar collisions: Array[KinematicCollision3D] = []\n\tif step_traversal_active or not support.has_support:\n',
    "capture player push velocity",
)
controller = replace_once(
    controller,
    '\t# Any completed movement transaction invalidates the pre-move support\n\t# snapshot. Refresh unconditionally at the final pose so collision-free\n',
    '\t_push_props_from_collisions(collisions, prop_push_source_velocity)\n\n\t# Any completed movement transaction invalidates the pre-move support\n\t# snapshot. Refresh unconditionally at the final pose so collision-free\n',
    "apply player prop pushes",
)
helper_anchor = '\n\nfunc _apply_controlled_jump() -> void:\n'
helper = '''

func _push_props_from_collisions(
\tcollisions: Array[KinematicCollision3D],
\tsource_velocity: Vector3
) -> void:
\tvar horizontal_velocity := Vector3(source_velocity.x, 0.0, source_velocity.z)
\tif horizontal_velocity.length_squared() <= 0.000001:
\t\treturn
\tvar pushed_ids: Dictionary = {}
\tfor collision: KinematicCollision3D in collisions:
\t\tif collision == null:
\t\t\tcontinue
\t\tfor contact_index: int in range(collision.get_collision_count()):
\t\t\tvar collider: Object = collision.get_collider(contact_index)
\t\t\tif collider == null or not collider.has_method("receive_player_push"):
\t\t\t\tcontinue
\t\t\tvar normal: Vector3 = collision.get_normal(contact_index)
\t\t\tvar lateral_normal := Vector3(normal.x, 0.0, normal.z)
\t\t\tif lateral_normal.length_squared() <= 0.000001:
\t\t\t\tcontinue
\t\t\tlateral_normal = lateral_normal.normalized()
\t\t\tif horizontal_velocity.dot(lateral_normal) >= -0.01:
\t\t\t\tcontinue
\t\t\tvar collider_id: int = collider.get_instance_id()
\t\t\tif pushed_ids.has(collider_id):
\t\t\t\tcontinue
\t\t\tpushed_ids[collider_id] = true
\t\t\tcollider.call("receive_player_push", horizontal_velocity)
'''
controller = replace_once(controller, helper_anchor, helper + helper_anchor, "player push helper")
controller_path.write_text(controller, encoding="utf-8")

# Update the lab instructions to make the new physical-rest contract visible.
lab_path = Path("scenes/PropLab.tscn")
lab = lab_path.read_text(encoding="utf-8")
lab = replace_once(
    lab,
    'text = "3.5 PROP LAB\\nF = pick up / throw · R = gentle release\\nReleased props use real rigid-body collision; rotation stays fixed until settle\\nOn settle: top-up only, yaw preserved · no floor hover gap"',
    'text = "3.5 PROP LAB\\nF = pick up / throw · R = gentle release\\nProps push other props; walking into a crate can shove it\\nSettle eases top-up, preserves yaw, then sleeps wakeable · no hover gap"',
    "Prop Lab instructions",
)
lab_path.write_text(lab, encoding="utf-8")

# Existing production-path prop expectations now require sleeping, wakeable rest.
reg_path = Path("tests/props/prop_regressions.gd")
reg = reg_path.read_text(encoding="utf-8")
reg = replace_once(
    reg,
    'assert_true.call(pickup_prop.freeze and pickup_prop.lock_rotation and pickup_prop.continuous_cd, "Settled props are frozen while retaining rigid-body collision configuration for later release")',
    'assert_true.call(not pickup_prop.freeze and pickup_prop.sleeping and pickup_prop.lock_rotation and pickup_prop.continuous_cd, "Settled props sleep as wakeable rigid bodies while keeping rotation locked")',
    "settled body regression",
)
reg = replace_once(
    reg,
    'assert_true.call(pickup_prop.freeze and pickup_prop.global_transform.basis.orthonormalized().y.dot(Vector3.UP) > 0.999 and released_settled_facing.dot(released_facing) > 0.995, "Gentle release settles top-up by removing pitch/roll while preserving its yaw")',
    'assert_true.call(not pickup_prop.freeze and pickup_prop.sleeping and pickup_prop.global_transform.basis.orthonormalized().y.dot(Vector3.UP) > 0.999 and released_settled_facing.dot(released_facing) > 0.995, "Gentle release settles top-up by removing pitch/roll while preserving its yaw, then sleeps wakeable")',
    "released settle regression",
)
reg = replace_once(
    reg,
    'assert_true.call(pickup_prop.freeze and pickup_prop.global_transform.basis.orthonormalized().y.dot(Vector3.UP) > 0.999 and thrown_settled_facing.dot(thrown_facing) > 0.995 and pickup_prop.linear_velocity.is_zero_approx(), "Thrown box settles top-up and stationary without a global compass-facing snap")',
    'assert_true.call(not pickup_prop.freeze and pickup_prop.sleeping and pickup_prop.global_transform.basis.orthonormalized().y.dot(Vector3.UP) > 0.999 and thrown_settled_facing.dot(thrown_facing) > 0.995 and pickup_prop.linear_velocity.is_zero_approx(), "Thrown box settles top-up and sleeping without a global compass-facing snap")',
    "thrown settle regression",
)
reg_path.write_text(reg, encoding="utf-8")

# Add integrated player-push/prop-impact/smooth-settle coverage to the focused
# transition regression.
trans_path = Path("tests/props/phase_3_5_transition_regressions.gd")
trans = trans_path.read_text(encoding="utf-8")
trans = replace_once(
    trans,
    '\tawait _prove_release_transaction(tree, world, player, pickup_prop, assert_true)\n\tawait _prove_support_invalidation(tree, player, edge_prop, assert_true)\n',
    '\tawait _prove_release_transaction(tree, world, player, pickup_prop, assert_true)\n\tawait _prove_wakeable_world_physics(tree, world, player, assert_true)\n\tawait _prove_support_invalidation(tree, player, edge_prop, assert_true)\n',
    "transition run wakeable physics",
)

insert_anchor = '\n\nfunc _prove_support_invalidation(\n'
wake_tests = '''

func _prove_wakeable_world_physics(
\ttree: SceneTree,
\tworld: Node3D,
\tplayer: CharacterBody3D,
\tassert_true: Callable
) -> void:
\tvar target: RigidBody3D = OrdinaryPropScene.instantiate() as RigidBody3D
\tvar striker: RigidBody3D = OrdinaryPropScene.instantiate() as RigidBody3D
\tworld.add_child(target)
\tworld.add_child(striker)
\tawait tree.process_frame
\ttarget.global_position = Vector3(3.0, 0.3, 3.0)
\tstriker.global_position = Vector3(3.0, 0.3, 4.2)
\tawait _settle_physics(tree, 3)
\tvar target_start: Vector3 = target.global_position
\tassert_true.call(
\t\ttarget.call("get_semantic_phase") == OrdinaryProp.PHASE_SETTLED
\t\tand target.sleeping and not target.freeze,
\t\t"Settled ordinary props rest by sleeping rather than becoming frozen/static"
\t)
\tvar striker_state := {
\t\t"phase": OrdinaryProp.PHASE_MOVING,
\t\t"motion_kind": OrdinaryProp.MOTION_THROWN,
\t\t"transform": striker.global_transform,
\t\t"linear_velocity": Vector3(0.0, 0.0, -5.0),
\t\t"settle_yaw": 0.0,
\t}
\tassert_true.call(bool(striker.call("apply_semantic_state", striker_state)), "Prop-impact fixture launches a real rigid striker")
\tvar target_moved: bool = await _wait_for_displacement(tree, target, target_start, 0.08, 90)
\tassert_true.call(
\t\ttarget_moved
\t\tand target.call("get_motion_kind") == OrdinaryProp.MOTION_DISTURBED
\t\tand target.global_transform.basis.orthonormalized().y.dot(Vector3.UP) > 0.999,
\t\t"A moving prop transfers physical motion into a sleeping settled prop without free tumbling"
\t)
\ttarget.queue_free()
\tstriker.queue_free()
\tawait tree.process_frame
\tawait _settle_physics(tree, 2)

\tvar push_prop: RigidBody3D = OrdinaryPropScene.instantiate() as RigidBody3D
\tworld.add_child(push_prop)
\tawait tree.process_frame
\tpush_prop.global_position = Vector3(-3.0, 0.3, 3.0)
\tplayer.global_position = Vector3(-3.0, 0.0, 3.9)
\tplayer.rotation.y = 0.0
\tplayer.velocity = Vector3.ZERO
\tawait _settle_physics(tree, 3)
\tvar push_start: Vector3 = push_prop.global_position
\tInput.action_press("move_forward")
\tawait _settle_physics(tree, 24)
\tInput.action_release("move_forward")
\tawait _settle_physics(tree, 2)
\tassert_true.call(
\t\tpush_prop.global_position.distance_to(push_start) > 0.025
\t\tand push_prop.call("get_motion_kind") == OrdinaryProp.MOTION_DISTURBED,
\t\t"Production player locomotion gives a contacted ordinary prop a bounded physical shove"
\t)
\tpush_prop.queue_free()
\tawait tree.process_frame
'''
trans = replace_once(trans, insert_anchor, wake_tests + insert_anchor, "wakeable physics regression functions")

old_settle = '''\tassert_true.call(bool(prop.call("apply_semantic_state", moving_state)), "Narrow-support fixture enters moving rigid-body state")
\tawait _settle_until_phase(tree, prop, OrdinaryProp.PHASE_SETTLED, 220)
\tassert_true.call(
\t\tprop.call("get_semantic_phase") == OrdinaryProp.PHASE_SETTLED
\t\tand prop.freeze
\t\tand prop.global_transform.basis.orthonormalized().y.dot(Vector3.UP) > 0.999
\t\tand absf(prop.global_position.y - 1.1) <= 0.025
\t\tand bool(prop.call("is_supported")),
\t\t"Tilted box settles from real contact state on a narrow support the retired corner-ray authority misses"
\t)
'''
new_settle = '''\tassert_true.call(bool(prop.call("apply_semantic_state", moving_state)), "Narrow-support fixture enters moving rigid-body state")
\tawait _settle_until_phase(tree, prop, OrdinaryProp.PHASE_SETTLING, 200)
\tvar alignment_start_up: float = prop.global_transform.basis.orthonormalized().y.dot(Vector3.UP)
\tawait _settle_physics(tree, 2)
\tvar alignment_mid_up: float = prop.global_transform.basis.orthonormalized().y.dot(Vector3.UP)
\tassert_true.call(
\t\tprop.call("get_semantic_phase") == OrdinaryProp.PHASE_SETTLING
\t\tand alignment_mid_up > alignment_start_up + 0.001
\t\tand alignment_mid_up < 0.999,
\t\t"Final top-up settle is visibly interpolated across physics frames instead of snapping in one frame"
\t)
\tawait _settle_until_phase(tree, prop, OrdinaryProp.PHASE_SETTLED, 80)
\tassert_true.call(
\t\tprop.call("get_semantic_phase") == OrdinaryProp.PHASE_SETTLED
\t\tand not prop.freeze and prop.sleeping
\t\tand prop.global_transform.basis.orthonormalized().y.dot(Vector3.UP) > 0.999
\t\tand absf(prop.global_position.y - 1.1) <= 0.025
\t\tand bool(prop.call("is_supported")),
\t\t"Tilted box smoothly settles from real contact state, re-seats on support, then sleeps wakeable"
\t)
'''
trans = replace_once(trans, old_settle, new_settle, "smooth narrow-support settle regression")

helper_anchor = '\n\nfunc _settle_until_phase(tree: SceneTree, prop: Node, target_phase: StringName, max_frames: int) -> void:\n'
wait_helper = '''

func _wait_for_displacement(
\ttree: SceneTree,
\tprop: RigidBody3D,
\tstart_position: Vector3,
\trequired_distance: float,
\tmax_frames: int
) -> bool:
\tfor _frame_index: int in max_frames:
\t\tawait tree.physics_frame
\t\tawait tree.process_frame
\t\tif prop.global_position.distance_to(start_position) >= required_distance:
\t\t\treturn true
\treturn false
'''
trans = replace_once(trans, helper_anchor, wait_helper + helper_anchor, "displacement wait helper")
trans_path.write_text(trans, encoding="utf-8")

# Product contract: resting is sleeping and wakeable under explicit contact;
# top-up normalization is short and smooth rather than an instantaneous snap.
vision_path = Path("docs/GAME_VISION.md")
vision = vision_path.read_text(encoding="utf-8")
vision = replace_once(
    vision,
    'Settled movable props follow **Thief 1 & 2-style object behavior** rather than remaining continuously simulated. While a prop is actively thrown, gently released, or unsupported, it temporarily participates as a real dynamic rigid body so gravity, friction, bounce/slide, and solid collision response are resolved by the physics engine; once it genuinely comes to rest it becomes settled/frozen again.\n',
    'Settled movable props follow **Thief 1 & 2-style object behavior** while still remaining physically responsive to explicit contact. A genuinely resting prop sleeps as a real rigid body instead of becoming a frozen/static body. Sleep keeps authored/support-stable props exactly still until something acts on them, while a moving prop impact or a deliberate player shove can wake and translate them through the normal physics solver. Thrown, gently released, unsupported, or externally disturbed props use real dynamic rigid-body gravity, friction, bounce/slide, and solid collision response.\n',
    "vision settled physical object rule",
)
vision = replace_once(
    vision,
    '- react to background physics merely because a realistic rigid body would.\n',
    '- react to background physics merely because a realistic rigid body would.\n\nA meaningful **explicit** physical contact is different from background drift. A thrown/moving prop can transfer momentum into a resting ordinary prop, and walking laterally into a suitable prop can give it a small physical shove. Those contacts wake the same rigid body and may translate it, but ordinary box-like Junk still keeps angular motion locked instead of tumbling freely.\n',
    "vision explicit wake response",
)
vision = replace_once(
    vision,
    'An object remains where the mission creator placed it until something explicitly acts on it or its support disappears.\n',
    'An object remains where the mission creator placed it until something explicitly acts on it or its support disappears. Explicit action includes pickup/throw/release, another physical object striking it, or the player deliberately pushing into it.\n',
    "vision explicit action examples",
)
vision = replace_once(
    vision,
    'Thrown/released/unsupported objects use real rigid-body translation while moving: gravity and collisions may change their position, linear velocity, slide, and bounce. Ordinary box-like Junk keeps angular motion locked during this moving phase, so hitting a floor, wall, prop, or actor does **not** rotate the box in flight. It does not continuously track later camera turns. When the prop genuinely settles, only pitch/roll are normalized so the top points upward; its current yaw is preserved. Settling must never rotate a particular side toward world north or any other global compass direction. Top-up normalization must re-seat the rotated collision shape onto the real detected support plane before freezing, so the settled collider rests directly on its support instead of inheriting the larger vertical extent of its tilted moving pose and leaving a visible air gap.\n',
    'Thrown/released/unsupported/disturbed objects use real rigid-body translation while moving: gravity and collisions may change their position, linear velocity, slide, and bounce. Ordinary box-like Junk keeps angular motion locked during this moving phase, so hitting a floor, wall, prop, or actor does **not** rotate the box in flight. It does not continuously track later camera turns. When the prop genuinely settles, only pitch/roll are normalized so the top points upward; its current yaw is preserved. This final normalization is a short smooth settle alignment rather than a one-frame visual pop. The interpolated pose remains re-seated against the detected support plane throughout the alignment, and completion leaves the same rigid body sleeping/wakeable rather than frozen. Settling must never rotate a particular side toward world north or any other global compass direction.\n',
    "vision smooth wakeable settle",
)
vision = replace_once(
    vision,
    'Once motion resolves, the object becomes settled again. Supported/settled props then resume the ordinary stylized support rules above.\n',
    'Once motion resolves and the smooth top-up alignment completes, the object becomes settled/sleeping again. Supported props then resume the ordinary stylized support rules above, but a later meaningful impact or lateral player shove can wake them back into disturbed rigid motion.\n',
    "vision settle completion",
)
vision_path.write_text(vision, encoding="utf-8")

plan_path = Path("docs/DEVELOPMENT_PLAN.md")
plan = plan_path.read_text(encoding="utf-8")
plan = replace_once(
    plan,
    '3. **Dynamic settling authority.** Moving/settling props use the real rigid-body contact manifold to identify support/rest candidates. The old lowest-corner proximity-ray heuristic is not settling authority. Final top-up normalization preserves yaw and re-seats the box on the detected support plane before freezing.\n4. **Acceptance.** Keep the existing carried-Junk HUD, F throw, R gentle release, hard-edged rendering, real rigid translation, stable settled edge/stack behavior, semantic sound/capture/reconcile seams, and accepted player movement feel unchanged.\n',
    '3. **Wakeable world physics.** A settled ordinary prop is a sleeping, non-frozen `RigidBody3D`. Meaningful prop-on-prop impact wakes/translates the struck prop through Jolt. Lateral player locomotion contact applies one bounded shove through the production controller; standing on a prop does not count as a shove. Angular motion remains locked, so these disturbances translate boxes without introducing free tumble.\n4. **Smooth dynamic settling authority.** Moving props use the real rigid-body contact manifold to identify support/rest candidates. The old lowest-corner proximity-ray heuristic is not settling authority. After genuine low-speed support is established, pitch/roll ease toward top-up over a short physics-step interpolation while yaw stays fixed and the collision shape is continuously re-seated on the detected support plane. A meaningful impact/player shove can interrupt this alignment. Completion returns the same body to sleeping/wakeable settled state, not frozen/static state.\n5. **Acceptance.** Keep the existing carried-Junk HUD, F throw, R gentle release, hard-edged rendering, real rigid translation, stable authored edge/stack rest, semantic sound/capture/reconcile seams, and accepted player movement feel unchanged.\n',
    "roadmap wakeable settle order",
)
plan = replace_once(
    plan,
    '**Done when:** world/prop blockers remain solid during release placement; an initially player-overlapping throw retains its intended impulse and restores normal player collision after separation; picking up the exact supporting/traversal prop ends that dependency immediately; low-speed tilted box-on-box contact can reach supported top-up settle from real contact state; yaw/no-gap/no-drift behavior remains; and the authoritative all-tests barrier plus Windows x64 user acceptance pass.\n',
    '**Done when:** world/prop blockers remain solid during release placement; an initially player-overlapping throw retains its intended impulse and restores normal player collision after separation; picking up the exact supporting/traversal prop ends that dependency immediately; settled props sleep without drifting but wake and translate when struck by another prop or deliberately pushed laterally by the player; low-speed tilted contact enters a visibly smooth, yaw-preserving, support-reseated top-up alignment instead of popping; meaningful contact can interrupt that alignment; no-gap/no-free-tumble behavior remains; and the authoritative all-tests barrier plus Windows x64 user acceptance pass.\n',
    "roadmap done when",
)
plan = replace_once(
    plan,
    '**Automated:** required — the dedicated Props suite must exercise shape-aware world-blocked placement, overlapping-player throw impulse preservation, pairwise exception lifetime, exact support RID invalidation, catch/hang/corner/mantle collider invalidation, real-contact narrow-support settling, existing prop behavior, and the unchanged movement regression suite through `tests/run_all_tests.gd`.\n',
    '**Automated:** required — the dedicated Props suite must exercise shape-aware world-blocked placement, overlapping-player throw impulse preservation, player-only overlap-filter lifetime, exact support RID invalidation, catch/hang/corner/mantle collider invalidation, sleeping/non-frozen settled state, prop-on-prop wake/translation, production-path player shove, multi-frame smooth narrow-support alignment, yaw/support re-seating, existing prop behavior, and the unchanged movement regression suite through `tests/run_all_tests.gd`.\n',
    "roadmap automated",
)
plan = replace_once(
    plan,
    '**Manual:** pending — validator: **Windows x64 user/playtester**. Launch **Development Launch → Prop Lab**. Confirm F pickup/HUD, movement/look/crouch/jump, F throw, R release, edge support, stacking, lower-support fall, hard-edged rendering, yaw-preserving top-up, and no hover/drift. Also test cramped release/throw near the player: the box may leave an initial player overlap without losing the throw, must still respect walls/props, and must collide with the player normally after separation. Stand on a prop and pick it up: support must end and the player must fall. Exercise a prop-based hang/catch/corner/mantle where practical and confirm pickup immediately ends the attachment. Repeatedly release tilted boxes onto box edges/corners and confirm genuine rest reaches top-up supported settle.\n',
    '**Manual:** pending — validator: **Windows x64 user/playtester**. Launch **Development Launch → Prop Lab**. Confirm the already-accepted F throw remains materially stronger than R release, including cramped player-overlap cases. Walk laterally into a resting crate and confirm it yields/moves a little without tumbling; throw one crate into another and confirm the struck crate wakes and is knocked back. Resting edge/stack props must remain exactly still until explicitly disturbed. Repeatedly release tilted boxes onto floors/box edges/corners and confirm the final top-up correction is adequately smooth rather than a visible pop, preserves yaw, stays seated with no hover gap, and returns to stable sleep. Also retain pickup/HUD, movement/look/crouch/jump, lower-support fall, hard-edged rendering, support/traversal invalidation, wall/prop collision, and restored post-overlap player collision.\n',
    "roadmap manual",
)
plan_path.write_text(plan, encoding="utf-8")

testing_path = Path("docs/TESTING.md")
testing = testing_path.read_text(encoding="utf-8")
old_testing = 'Phase 3.5 has a dedicated Props suite wired through the authoritative all-tests barrier. It retains the production-path Prop Lab coverage for outward/hard OBJ normals, normal lit/shadowed presentation, external-model replacement, real `RigidBody3D` ownership, frozen settled state, single-slot `carried_junk`, bottom-center HUD presentation, normal locomotion while carrying, central interaction/hand suppression, stale F/R edge suppression, F throw versus R release, semantic sound, detached capture/reconcile, edge support, stable stacks, lower-support fall, yaw-preserving top-up, no support gap, and no post-settle drift/spin. A second focused Phase 3.5 transition regression exercises the cross-system failure boundaries directly: shape-volume-aware release backs away from a world blocker; a valid throw pose intentionally overlapping the player activates a live rigid body whose full throw velocity/displacement is committed through the synchronized direct-body-state callback; the overlap uses a player-only transient collision channel while retaining world/prop collision, and ordinary player collision returns after geometric separation; standing support stores and invalidates the exact prop collider RID; catch/hang/corner/mantle state is canceled only when its referenced collider is invalidated; and a tilted moving crate resting on a narrow support settles from the real rigid-body contact manifold in a geometry case the retired lowest-corner ray heuristic cannot see. The authoritative all-tests barrier continues to run the accepted movement suite alongside these corrections. Acoustic propagation remains Phase 3.6.\n'
new_testing = 'Phase 3.5 has a dedicated Props suite wired through the authoritative all-tests barrier. It retains the production-path Prop Lab coverage for outward/hard OBJ normals, normal lit/shadowed presentation, external-model replacement, real `RigidBody3D` ownership, sleeping/wakeable settled state, single-slot `carried_junk`, bottom-center HUD presentation, normal locomotion while carrying, central interaction/hand suppression, stale F/R edge suppression, F throw versus R release, semantic sound, detached capture/reconcile, edge support, stable stacks, lower-support fall, yaw-preserving top-up, no support gap, and no post-settle drift/spin. A second focused Phase 3.5 transition regression exercises the cross-system failure boundaries directly: shape-volume-aware release backs away from a world blocker; a valid throw pose intentionally overlapping the player activates a live rigid body whose full throw velocity/displacement is committed through the synchronized direct-body-state callback; the overlap uses a player-only transient collision channel while retaining world/prop collision, and ordinary player collision returns after geometric separation; a sleeping settled prop is physically displaced by a real moving-prop impact; production player locomotion gives one bounded lateral shove to a contacted prop without making standing support a shove; standing support stores and invalidates the exact prop collider RID; catch/hang/corner/mantle state is canceled only when its referenced collider is invalidated; and a tilted moving crate resting on a narrow support enters a multi-frame support-reseated top-up alignment before returning to sleeping settled state. The authoritative all-tests barrier continues to run the accepted movement suite alongside these corrections. Acoustic propagation remains Phase 3.6.\n'
testing = replace_once(testing, old_testing, new_testing, "testing Phase 3.5 coverage")
testing_path.write_text(testing, encoding="utf-8")

print("STAGED_WAKEABLE_PROP_PATCH")
