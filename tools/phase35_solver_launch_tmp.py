from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, got {count}")
    return text.replace(old, new, 1)


prop_path = Path("gameplay/props/ordinary_prop.gd")
prop = prop_path.read_text(encoding="utf-8")

# A release request arrives from the player callback, but the authoritative
# rigid-body transform/velocity handoff belongs to PhysicsDirectBodyState3D.
prop = replace_once(
    prop,
    'var _temporarily_ignored_player: PhysicsBody3D = null\n',
    'var _temporarily_ignored_player: PhysicsBody3D = null\n'
    'var _pending_rigid_launch: bool = false\n'
    'var _pending_launch_transform: Transform3D = Transform3D.IDENTITY\n'
    'var _pending_launch_velocity: Vector3 = Vector3.ZERO\n',
    "pending launch variables",
)

old_integrate = '''func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
\tif _phase != PHASE_MOVING and _phase != PHASE_SETTLING:
\t\treturn
\t_dynamic_contact_count = state.get_contact_count()
'''
new_integrate = '''func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
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
\tif _phase != PHASE_MOVING and _phase != PHASE_SETTLING:
\t\treturn
\t_dynamic_contact_count = state.get_contact_count()
'''
prop = replace_once(prop, old_integrate, new_integrate, "solver-synchronized integrate launch")

# Carried/settled transitions must cancel any unconsumed transient handoff.
prop = replace_once(
    prop,
    '''func begin_carried_junk(holder: Node) -> bool:
\tif holder == null or _phase == PHASE_CARRIED_JUNK:
\t\treturn false
\t_clear_temporary_player_collision_ignore()
''',
    '''func begin_carried_junk(holder: Node) -> bool:
\tif holder == null or _phase == PHASE_CARRIED_JUNK:
\t\treturn false
\t_clear_pending_rigid_launch()
\t_clear_temporary_player_collision_ignore()
''',
    "cancel pending launch on carry",
)

# The collision-channel staging helper currently calls _begin_motion() directly.
# Replace only the release transaction tail with a staged solver handoff.
prop = replace_once(
    prop,
    '''\t# F and R differ only by the supplied launch velocity/motion kind. Once the
\t# prop leaves carried Junk it is immediately a real rigid body; no manual
\t# translation or frozen escape phase can dilute the throw.
\t_begin_motion(motion_kind, initial_velocity)
\treturn true
''',
    '''\t# F and R differ only by motion kind/velocity. The body becomes live now,
\t# while the exact transform + velocity commit is synchronized with Jolt in
\t# _integrate_forces() on the first active rigid-body step.
\t_stage_rigid_launch(motion_kind, release_transform, initial_velocity)
\treturn true
''',
    "stage release through solver",
)

# Semantic capture exposes the intended physical state, not the transient
# implementation detail that the first solver callback has not consumed it yet.
prop = replace_once(
    prop,
    '''func capture_semantic_state() -> Dictionary:
\treturn {
\t\t"phase": _phase,
\t\t"motion_kind": _motion_kind,
\t\t"transform": global_transform,
\t\t"linear_velocity": linear_velocity,
\t\t"settle_yaw": _settle_yaw,
\t}
''',
    '''func capture_semantic_state() -> Dictionary:
\treturn {
\t\t"phase": _phase,
\t\t"motion_kind": _motion_kind,
\t\t"transform": _pending_launch_transform if _pending_rigid_launch else global_transform,
\t\t"linear_velocity": _pending_launch_velocity if _pending_rigid_launch else linear_velocity,
\t\t"settle_yaw": _settle_yaw,
\t}
''',
    "capture intended pending launch state",
)

# Applying/restoring semantic state replaces any unconsumed local transient.
prop = replace_once(
    prop,
    '''\t_clear_temporary_player_collision_ignore()
\t_clear_dynamic_contact_state()
\t_phase = phase
''',
    '''\t_clear_pending_rigid_launch()
\t_clear_temporary_player_collision_ignore()
\t_clear_dynamic_contact_state()
\t_phase = phase
''',
    "clear pending launch on semantic apply",
)

# Insert staged-launch helpers immediately before the ordinary motion helper.
marker = 'func _begin_motion(motion_kind: StringName, initial_velocity: Vector3) -> void:\n'
if prop.count(marker) != 1:
    raise SystemExit(f"motion helper marker count={prop.count(marker)}")
new_helpers = '''func _stage_rigid_launch(
\tmotion_kind: StringName,
\trelease_transform: Transform3D,
\tinitial_velocity: Vector3
) -> void:
\t_phase = PHASE_MOVING
\t_motion_kind = motion_kind
\t_settle_yaw = _yaw_from_basis(release_transform.basis)
\t_settle_contact_frames = 0
\t_unsupported_frames = 0
\t_last_contact_count = 0
\t_clear_dynamic_contact_state()
\t_pending_launch_transform = release_transform
\t_pending_launch_velocity = initial_velocity
\t_pending_rigid_launch = true
\t# Keep the newly activated body awake until the direct-state callback has
\t# consumed the pending launch. Afterwards normal sleeping policy resumes.
\tcan_sleep = false
\tfreeze = false
\tsleeping = false


func _clear_pending_rigid_launch() -> void:
\t_pending_rigid_launch = false
\t_pending_launch_transform = Transform3D.IDENTITY
\t_pending_launch_velocity = Vector3.ZERO
\tcan_sleep = true


'''
prop = prop.replace(marker, new_helpers + marker, 1)

# Once a body settles, no launch transaction may remain live.
prop = replace_once(
    prop,
    '''func _settle_now(support_point: Vector3, support_normal: Vector3) -> void:
\tvar top_up_basis: Basis = _top_up_basis_for_yaw(_settle_yaw)
''',
    '''func _settle_now(support_point: Vector3, support_normal: Vector3) -> void:
\t_clear_pending_rigid_launch()
\tvar top_up_basis: Basis = _top_up_basis_for_yaw(_settle_yaw)
''',
    "clear pending launch on settle",
)

prop_path.write_text(prop, encoding="utf-8")


test_path = Path("tests/props/phase_3_5_transition_regressions.gd")
tests = test_path.read_text(encoding="utf-8")

# The direct carry call may occur between solver steps. Validate immediate mode
# and filtering first, then validate the solver-owned velocity/displacement once
# the next rigid-body step has occurred.
tests = replace_once(
    tests,
    '''\tassert_true.call(
\t\tthrown
\t\tand prop.call("get_motion_kind") == OrdinaryProp.MOTION_THROWN
\t\tand prop.linear_velocity.length() > 4.0
\t\tand not prop.freeze
\t\tand not prop.sleeping
\t\tand prop.collision_layer == OrdinaryProp.COLLISION_LAYER_PROP_IGNORING_PLAYER
\t\tand (prop.collision_mask & OrdinaryProp.COLLISION_LAYER_WORLD) != 0
\t\tand (prop.collision_mask & OrdinaryProp.COLLISION_LAYER_ORDINARY_PROP) != 0
\t\tand (prop.collision_mask & OrdinaryProp.COLLISION_LAYER_PLAYER) == 0
\t\tand bool(prop.call("is_temporarily_ignoring_player_collision"))
\t\tand player.get_collision_exceptions().is_empty()
\t\tand prop.get_collision_exceptions().is_empty(),
\t\t"F throw is immediately a live world/prop-colliding rigid body while the overlapping player channel alone is filtered"
\t)
\tvar overlap_throw_start: Vector3 = prop.global_position
\tawait _settle_physics(tree)
\tassert_true.call(
\t\tprop.global_position.distance_to(overlap_throw_start) > 0.05,
\t\t"Initial player overlap escapes along the throw vector instead of canceling the throw"
\t)
''',
    '''\tassert_true.call(
\t\tthrown
\t\tand prop.call("get_motion_kind") == OrdinaryProp.MOTION_THROWN
\t\tand not prop.freeze
\t\tand prop.collision_layer == OrdinaryProp.COLLISION_LAYER_PROP_IGNORING_PLAYER
\t\tand (prop.collision_mask & OrdinaryProp.COLLISION_LAYER_WORLD) != 0
\t\tand (prop.collision_mask & OrdinaryProp.COLLISION_LAYER_ORDINARY_PROP) != 0
\t\tand (prop.collision_mask & OrdinaryProp.COLLISION_LAYER_PLAYER) == 0
\t\tand bool(prop.call("is_temporarily_ignoring_player_collision"))
\t\tand player.get_collision_exceptions().is_empty()
\t\tand prop.get_collision_exceptions().is_empty(),
\t\t"F throw activates a live world/prop-colliding body while the overlapping player channel alone is filtered"
\t)
\tvar overlap_throw_start: Vector3 = prop.global_position
\tvar launched: bool = await _wait_for_solver_launch_motion(tree, prop, overlap_throw_start, 4)
\tassert_true.call(
\t\tlaunched
\t\tand prop.linear_velocity.length() > 4.0
\t\tand prop.global_position.distance_to(overlap_throw_start) > 0.05,
\t\t"Initial player-overlap throw receives its full velocity through the synchronized rigid-body solver handoff"
\t)
''',
    "solver launch regression",
)

# Add a bounded helper that proves the body actually advances under solver
# ownership; this is not a gameplay timer and does not control collision state.
wait_marker = 'func _wait_for_player_ignore_clear('
idx = tests.find(wait_marker)
if idx < 0:
    raise SystemExit("player-ignore wait helper marker missing")
solver_wait = '''func _wait_for_solver_launch_motion(
\ttree: SceneTree,
\tprop: RigidBody3D,
\tstart_position: Vector3,
\tmax_frames: int
) -> bool:
\tfor _frame_index: int in max_frames:
\t\tawait tree.physics_frame
\t\tawait tree.process_frame
\t\tif (
\t\t\tprop.linear_velocity.length() > 4.0
\t\t\tand prop.global_position.distance_to(start_position) > 0.05
\t\t):
\t\t\treturn true
\treturn false


'''
tests = tests[:idx] + solver_wait + tests[idx:]
test_path.write_text(tests, encoding="utf-8")


# Document the direct-body-state boundary so a later refactor does not regress
# back to split PhysicsServer writes or kinematic escape logic.
plan_path = Path("docs/DEVELOPMENT_PLAN.md")
plan = plan_path.read_text(encoding="utf-8")nold = "Geometric separation restores the ordinary prop layer/mask. Do not freeze/kinematically translate the prop, zero global collision participation, use a timer/distance guess, or rely on a cached pairwise exception as the launch mechanism."
new = "Geometric separation restores the ordinary prop layer/mask. The carry→world launch itself is committed through the rigid body's synchronized `PhysicsDirectBodyState3D` boundary (`_integrate_forces`): the release callback stages the intended pose/velocity and wakes the body, then the first active solver step atomically receives transform, filter and full F/R velocity. Do not freeze/kinematically translate the prop, zero global collision participation, use a timer/distance guess, or rely on a cached pairwise exception as the launch mechanism."
plan = replace_once(plan, old, new, "development plan solver handoff")
plan_path.write_text(plan, encoding="utf-8")

vision_path = Path("docs/GAME_VISION.md")
vision = vision_path.read_text(encoding="utf-8")
old = "The prop is therefore a normal live rigid body from the first moving physics tick with the complete throw or gentle-release velocity; there is no frozen/manual escape translation."
new = "The prop is therefore a normal live rigid body from the first moving physics tick with the complete throw or gentle-release velocity. The carry→world handoff is staged by gameplay and committed atomically through the body's synchronized `PhysicsDirectBodyState3D` callback so mode/filter/pose/velocity cannot be split across stale physics-server state; there is no frozen/manual escape translation."
vision = replace_once(vision, old, new, "game vision solver handoff")
vision_path.write_text(vision, encoding="utf-8")

# Testing contract names the solver-owned launch proof explicitly.
testing_path = Path("docs/TESTING.md")
testing = testing_path.read_text(encoding="utf-8")
old = "a valid throw pose intentionally overlapping the player remains a live rigid body with its throw impulse; the overlap uses a player-only transient collision channel while retaining world/prop collision, and ordinary player collision returns after geometric separation;"
new = "a valid throw pose intentionally overlapping the player activates a live rigid body whose full throw velocity/displacement is committed through the synchronized direct-body-state callback; the overlap uses a player-only transient collision channel while retaining world/prop collision, and ordinary player collision returns after geometric separation;"
testing = replace_once(testing, old, new, "testing solver handoff")
testing_path.write_text(testing, encoding="utf-8")
