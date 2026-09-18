from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


prop_path = Path("gameplay/props/ordinary_prop.gd")
prop = prop_path.read_text(encoding="utf-8")

# Continuous player pressure and one-shot prop impacts are different physical
# causes. Player contact owns a bounded horizontal motion floor; prop impacts
# use the solver's contact impulse instead of post-solver body velocity.
prop = replace_once(
    prop,
    'const PROP_IMPACT_MIN_SPEED: float = 0.40\nconst PROP_IMPACT_TRANSFER_SCALE: float = 0.35\n',
    'const PROP_IMPACT_MIN_IMPULSE: float = 0.05\nconst PROP_IMPACT_TRANSFER_SCALE: float = 0.35\n',
    "contact impulse tuning",
)
prop = replace_once(
    prop,
    '@export var player_push_impulse_scale: float = 0.16\n@export var player_push_max_impulse: float = 0.55\n',
    '@export var player_push_speed_scale: float = 0.22\n@export var player_push_min_motion_speed: float = 0.30\n@export var player_push_max_motion_speed: float = 0.70\n',
    "player push motion tuning",
)

prop = replace_once(
    prop,
    'var _pending_prop_impacts: Array[Dictionary] = []\n',
    'var _pending_prop_impacts: Array[Dictionary] = []\nvar _pending_external_impulse: Vector3 = Vector3.ZERO\nvar _pending_player_push_velocity: Vector3 = Vector3.ZERO\n',
    "solver-owned external motion state",
)

# The moving source body records the equal-and-opposite impulse that belongs on
# the contacted prop. This stays meaningful even after Jolt has already changed
# the source body's velocity during contact resolution.
prop = replace_once(
    prop,
    '\t\t\t\t\t"source_velocity": state.linear_velocity,\n',
    '\t\t\t\t\t"target_impulse": -state.get_contact_impulse(contact_index),\n',
    "capture contact impulse",
)
prop = replace_once(
    prop,
    '\t\tbody.call("receive_prop_impact", impact.get("source_velocity", Vector3.ZERO))\n',
    '\t\tbody.call("receive_prop_impact", impact.get("target_impulse", Vector3.ZERO))\n',
    "dispatch contact impulse",
)

integrate_anchor = '''\t\t_pending_rigid_launch = false
\t\t_pending_launch_velocity = Vector3.ZERO
\t\tcan_sleep = true

\tif _phase == PHASE_SETTLING and _settle_alignment_active:
'''
integrate_new = '''\t\t_pending_rigid_launch = false
\t\t_pending_launch_velocity = Vector3.ZERO
\t\tcan_sleep = true

\tif not _pending_external_impulse.is_zero_approx():
\t\tstate.apply_central_impulse(_pending_external_impulse)
\t\tstate.sleeping = false
\t\t_pending_external_impulse = Vector3.ZERO

\tif not _pending_player_push_velocity.is_zero_approx():
\t\tvar push_direction: Vector3 = _pending_player_push_velocity.normalized()
\t\tvar target_speed: float = _pending_player_push_velocity.length()
\t\tvar current_horizontal := Vector3(
\t\t\tstate.linear_velocity.x,
\t\t\t0.0,
\t\t\tstate.linear_velocity.z
\t\t)
\t\tvar current_along_push: float = current_horizontal.dot(push_direction)
\t\tif current_along_push < target_speed:
\t\t\tstate.linear_velocity += push_direction * (target_speed - current_along_push)
\t\tstate.sleeping = false
\t\t_pending_player_push_velocity = Vector3.ZERO

\tif _phase == PHASE_SETTLING and _settle_alignment_active:
'''
prop = replace_once(prop, integrate_anchor, integrate_new, "solver-owned external motion integration")

old_impact = '''func receive_prop_impact(source_velocity: Vector3) -> bool:
\tif _phase != PHASE_SETTLED and _phase != PHASE_SETTLING:
\t\treturn false
\tvar horizontal_velocity := Vector3(source_velocity.x, 0.0, source_velocity.z)
\tvar speed: float = horizontal_velocity.length()
\tif speed < PROP_IMPACT_MIN_SPEED:
\t\treturn false
\tvar impulse_strength: float = minf(
\t\tspeed * mass * PROP_IMPACT_TRANSFER_SCALE,
\t\tPROP_IMPACT_MAX_IMPULSE
\t)
\tif impulse_strength <= 0.0:
\t\treturn false
\t_begin_motion(MOTION_DISTURBED, Vector3.ZERO)
\tapply_central_impulse(horizontal_velocity.normalized() * impulse_strength)
\treturn true
'''
new_impact = '''func receive_prop_impact(contact_impulse: Vector3) -> bool:
\tif _phase != PHASE_SETTLED and _phase != PHASE_SETTLING:
\t\treturn false
\tvar impulse_magnitude: float = contact_impulse.length()
\tif impulse_magnitude < PROP_IMPACT_MIN_IMPULSE:
\t\treturn false
\tvar transferred_impulse: Vector3 = contact_impulse * PROP_IMPACT_TRANSFER_SCALE
\tif transferred_impulse.length() > PROP_IMPACT_MAX_IMPULSE:
\t\ttransferred_impulse = transferred_impulse.normalized() * PROP_IMPACT_MAX_IMPULSE
\tif transferred_impulse.is_zero_approx():
\t\treturn false
\t_begin_motion(MOTION_DISTURBED, Vector3.ZERO)
\t_pending_external_impulse += transferred_impulse
\tsleeping = false
\treturn true
'''
prop = replace_once(prop, old_impact, new_impact, "solver-owned prop contact impulse")

old_push = '''func receive_player_push(player_velocity: Vector3) -> bool:
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
new_push = '''func receive_player_push(player_velocity: Vector3) -> bool:
\tif _phase == PHASE_CARRIED_JUNK:
\t\treturn false
\tvar horizontal_velocity := Vector3(player_velocity.x, 0.0, player_velocity.z)
\tvar speed: float = horizontal_velocity.length()
\tif speed < PLAYER_PUSH_MIN_SPEED:
\t\treturn false
\tif _phase == PHASE_SETTLED or _phase == PHASE_SETTLING:
\t\t_begin_motion(MOTION_DISTURBED, linear_velocity)
\tvar target_speed: float = clampf(
\t\tspeed * maxf(player_push_speed_scale, 0.0),
\t\tmaxf(player_push_min_motion_speed, 0.0),
\t\tmaxf(player_push_max_motion_speed, player_push_min_motion_speed)
\t)
\t_pending_player_push_velocity = horizontal_velocity.normalized() * target_speed
\tsleeping = false
\treturn true
'''
prop = replace_once(prop, old_push, new_push, "solver-owned player push")

prop = replace_once(
    prop,
    '''func _clear_dynamic_contact_state() -> void:
\t_dynamic_contact_count = 0
''',
    '''func _clear_dynamic_contact_state() -> void:
\t_pending_external_impulse = Vector3.ZERO
\t_pending_player_push_velocity = Vector3.ZERO
\t_dynamic_contact_count = 0
''',
    "clear pending external motion with dynamic state",
)
prop_path.write_text(prop, encoding="utf-8")

trans_path = Path("tests/props/phase_3_5_transition_regressions.gd")
trans = trans_path.read_text(encoding="utf-8")
old_striker = '''\tvar striker_state := {
\t\t"phase": OrdinaryProp.PHASE_MOVING,
\t\t"motion_kind": OrdinaryProp.MOTION_THROWN,
\t\t"transform": striker.global_transform,
\t\t"linear_velocity": Vector3(0.0, 0.0, -5.0),
\t\t"settle_yaw": 0.0,
\t}
\tassert_true.call(bool(striker.call("apply_semantic_state", striker_state)), "Prop-impact fixture launches a real rigid striker")
'''
new_striker = '''\tassert_true.call(
\t\tbool(striker.call("begin_carried_junk", world))
\t\tand bool(striker.call(
\t\t\t"release_from_carry",
\t\t\tOrdinaryProp.MOTION_THROWN,
\t\t\tstriker.global_transform,
\t\t\tVector3(0.0, 0.0, -5.0),
\t\t\tnull
\t\t)),
\t\t"Prop-impact fixture launches through the production carry-to-rigid handoff"
\t)
'''
trans = replace_once(trans, old_striker, new_striker, "production-path striker launch regression")
trans = replace_once(
    trans,
    '"A moving prop transfers physical motion into a sleeping settled prop without free tumbling"',
    '"A moving prop transfers solver contact impulse into a settled prop without free tumbling"',
    "prop impact regression wording",
)
trans_path.write_text(trans, encoding="utf-8")

print("STAGED_SOLVER_OWNED_EXTERNAL_PROP_MOTION")
