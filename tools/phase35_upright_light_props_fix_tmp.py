from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


# The player carry owner already performs the shape-aware placement search using
# the exact upright collision basis. release_from_carry() is the lower-level
# semantic/physics handoff and must also support already-authorized internal
# transitions that begin tangent to a support surface. Do not duplicate the
# placement policy here.
prop_path = Path("gameplay/props/ordinary_prop.gd")
prop = prop_path.read_text(encoding="utf-8")
prop = replace_once(
    prop,
    '''\t# Carry->world orientation is semantic physics state, not later settle
\t# presentation. Both F and R enter the world with the box top already up.
\tif not is_release_transform_world_clear(upright_release_transform, releasing_player):
\t\treturn false
\t_cancel_settle_alignment()
''',
    '''\t# Carry->world orientation is semantic physics state, not later settle
\t# presentation. Both F and R enter the world with the box top already up.
\t# Shape-aware player placement is owned by PlayerPropCarry before this
\t# lower-level transition is accepted.
\t_cancel_settle_alignment()
''',
    "remove duplicate lower-level release clearance policy",
)
prop_path.write_text(prop, encoding="utf-8")


# The long Prop Lab integration intentionally throws the pickup crate through
# the same room before it checks support-loss behavior. With the new lightweight
# response, that earlier physical action may legitimately disturb the authored
# stack. Re-establish the dedicated stack fixture at its recorded authored
# transforms before testing support removal so the regression proves support
# semantics rather than depending on unrelated earlier impacts.
test_path = Path("tests/props/prop_regressions.gd")
test = test_path.read_text(encoding="utf-8")
anchor = '''\tvar upper_facing: Vector3 = _horizontal_forward_from_basis(stack_upper.global_transform.basis)
\tvar upper_xz := Vector2(stack_upper.global_position.x, stack_upper.global_position.z)
'''
replacement = '''\tvar reset_lower_state := {
\t\t"phase": OrdinaryProp.PHASE_SETTLED,
\t\t"motion_kind": OrdinaryProp.MOTION_NONE,
\t\t"transform": lower_start,
\t\t"linear_velocity": Vector3.ZERO,
\t}
\tvar reset_upper_state := {
\t\t"phase": OrdinaryProp.PHASE_SETTLED,
\t\t"motion_kind": OrdinaryProp.MOTION_NONE,
\t\t"transform": upper_start,
\t\t"linear_velocity": Vector3.ZERO,
\t}
\tassert_true.call(
\t\tbool(stack_lower.call("apply_semantic_state", reset_lower_state))
\t\tand bool(stack_upper.call("apply_semantic_state", reset_upper_state)),
\t\t"Support-loss stack fixture is restored after unrelated earlier prop impacts"
\t)
\tawait _settle_physics(tree, 2)
\tvar upper_facing: Vector3 = _horizontal_forward_from_basis(stack_upper.global_transform.basis)
\tvar upper_xz := Vector2(stack_upper.global_position.x, stack_upper.global_position.z)
'''
test = replace_once(test, anchor, replacement, "isolate support-loss stack fixture")
test_path.write_text(test, encoding="utf-8")

print("FIXED_PHASE35_UPRIGHT_LIGHT_PROP_STAGING_GATE")
