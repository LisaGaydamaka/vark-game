from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


# This script runs after phase35_wakeable_props_tmp.py and corrects the model
# from continuously sleeping Jolt bodies to exact settled stability plus
# explicit physics promotion on real impacts/player contact.
prop_path = Path("gameplay/props/ordinary_prop.gd")
prop = prop_path.read_text(encoding="utf-8")

prop = replace_once(
    prop,
    'const PLAYER_PUSH_MIN_SPEED: float = 0.15\n',
    'const PLAYER_PUSH_MIN_SPEED: float = 0.15\nconst PROP_IMPACT_MIN_SPEED: float = 0.40\nconst PROP_IMPACT_TRANSFER_SCALE: float = 0.35\nconst PROP_IMPACT_MAX_IMPULSE: float = 2.50\n',
    "prop impact tuning constants",
)

prop = replace_once(
    prop,
    'var _settle_alignment_unsupported_frames: int = 0\n',
    'var _settle_alignment_unsupported_frames: int = 0\nvar _pending_prop_impacts: Array[Dictionary] = []\n',
    "pending prop impact state",
)

prop = replace_once(
    prop,
    '\tcan_sleep = true\n\tfreeze = false\n\tsleeping = true\n',
    '\tcan_sleep = true\n\tfreeze = true\n\tsleeping = true\n',
    "stable settled ready state",
)

prop = replace_once(
    prop,
    '\t\tPHASE_MOVING:\n\t\t\t_unsupported_frames = 0\n\t\t\tangular_velocity = Vector3.ZERO\n\t\t\t_update_dynamic_settling()\n',
    '\t\tPHASE_MOVING:\n\t\t\t_unsupported_frames = 0\n\t\t\tangular_velocity = Vector3.ZERO\n\t\t\t_dispatch_pending_prop_impacts()\n\t\t\t_update_dynamic_settling()\n',
    "dispatch rigid contact impacts",
)

prop = replace_once(
    prop,
    'func _capture_dynamic_contact_state(state: PhysicsDirectBodyState3D) -> void:\n\t_dynamic_contact_count = state.get_contact_count()\n',
    'func _capture_dynamic_contact_state(state: PhysicsDirectBodyState3D) -> void:\n\t_pending_prop_impacts.clear()\n\t_dynamic_contact_count = state.get_contact_count()\n',
    "clear pending contact impacts",
)

contact_anchor = '''\tfor contact_index: int in range(_dynamic_contact_count):
\t\tvar local_point: Vector3 = state.get_contact_local_position(contact_index)
'''
contact_new = '''\tvar impact_target_ids: Dictionary = {}
\tfor contact_index: int in range(_dynamic_contact_count):
\t\tvar collider: Object = state.get_contact_collider_object(contact_index)
\t\tif collider != null and collider != self and collider.has_method("receive_prop_impact"):
\t\t\tvar collider_id: int = collider.get_instance_id()
\t\t\tif not impact_target_ids.has(collider_id):
\t\t\t\timpact_target_ids[collider_id] = true
\t\t\t\t_pending_prop_impacts.append({
\t\t\t\t\t"body": collider,
\t\t\t\t\t"source_velocity": state.linear_velocity,
\t\t\t\t})
\t\tvar local_point: Vector3 = state.get_contact_local_position(contact_index)
'''
prop = replace_once(prop, contact_anchor, contact_new, "capture contacted prop objects")

prop = replace_once(
    prop,
    '''\tif phase == PHASE_SETTLED:
\t\tfreeze = false
\t\tsleeping = true
\t\treturn true
''',
    '''\tif phase == PHASE_SETTLED:
\t\tfreeze = true
\t\tsleeping = true
\t\treturn true
''',
    "restore stable settled state",
)

prop = replace_once(
    prop,
    '''\tif _phase == PHASE_SETTLED:
\t\tfreeze = false
\t\tsleeping = true
''',
    '''\tif _phase == PHASE_SETTLED:
\t\tfreeze = true
\t\tsleeping = true
''',
    "reconcile stable settled state",
)

prop = replace_once(
    prop,
    '''\tgravity_scale = _ordinary_gravity_scale
\tcan_sleep = true
\tfreeze = false
\tsleeping = true
\t_phase = PHASE_SETTLED
''',
    '''\tgravity_scale = _ordinary_gravity_scale
\tcan_sleep = true
\tfreeze = true
\tsleeping = true
\t_phase = PHASE_SETTLED
''',
    "smooth settle completes stable",
)

settled_start = prop.index('func _update_settled_state() -> void:\n')
settled_end = prop.index('\n\nfunc _origin_reseated_on_support(', settled_start)
new_settled = '''func _update_settled_state() -> void:
\t# Settled is intentionally exact/stable. Explicit causes promote the same
\t# RigidBody3D back to dynamic motion; background solver stabilization does not.
\tlinear_velocity = Vector3.ZERO
\tangular_velocity = Vector3.ZERO
\t_last_contact_count = 0
\t_clear_dynamic_contact_state()
\tif _has_support():
\t\t_unsupported_frames = 0
\t\treturn
\t_unsupported_frames += 1
\tif _unsupported_frames >= 2:
\t\t_begin_motion(MOTION_UNSUPPORTED, Vector3.ZERO)
'''
prop = prop[:settled_start] + new_settled + prop[settled_end:]

push_anchor = '''func receive_player_push(player_velocity: Vector3) -> bool:
\tif _phase == PHASE_CARRIED_JUNK:
\t\treturn false
'''
impact_methods = '''func _dispatch_pending_prop_impacts() -> void:
\tif _pending_prop_impacts.is_empty():
\t\treturn
\tvar pending: Array[Dictionary] = _pending_prop_impacts.duplicate()
\t_pending_prop_impacts.clear()
\tfor impact: Dictionary in pending:
\t\tvar body_value: Variant = impact.get("body")
\t\tif not (body_value is Object) or not is_instance_valid(body_value):
\t\t\tcontinue
\t\tvar body: Object = body_value
\t\tif not body.has_method("receive_prop_impact"):
\t\t\tcontinue
\t\tbody.call("receive_prop_impact", impact.get("source_velocity", Vector3.ZERO))


func receive_prop_impact(source_velocity: Vector3) -> bool:
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
prop = replace_once(prop, push_anchor, impact_methods + push_anchor, "explicit prop impact receiver")

# The generated first-pass implementation routed player pushing too late in the
# controller. Restore that file and put the capability at the actual contact
# transaction inside PlayerContactMotionSolver.
controller_path = Path("player/locomotion/player_locomotion_controller.gd")
controller = controller_path.read_text(encoding="utf-8")
controller = replace_once(
    controller,
    '\tvar prop_push_source_velocity: Vector3 = body.velocity\n\tvar collisions: Array[KinematicCollision3D] = []\n',
    '\tvar collisions: Array[KinematicCollision3D] = []\n',
    "remove late push velocity capture",
)
controller = replace_once(
    controller,
    '\t_push_props_from_collisions(collisions, prop_push_source_velocity)\n\n\t# Any completed movement transaction invalidates the pre-move support\n',
    '\t# Any completed movement transaction invalidates the pre-move support\n',
    "remove late push dispatch",
)
helper_start = controller.index('\n\nfunc _push_props_from_collisions(\n')
helper_end = controller.index('\n\nfunc _apply_controlled_jump() -> void:', helper_start)
controller = controller[:helper_start] + controller[helper_end:]
controller_path.write_text(controller, encoding="utf-8")

contact_path = Path("player/locomotion/player_contact_motion_solver.gd")
contact = contact_path.read_text(encoding="utf-8")
contact = replace_once(
    contact,
    '\tvar contact_planes: Array[Vector3] = []\n',
    '\tvar contact_planes: Array[Vector3] = []\n\tvar pushed_prop_ids: Dictionary = {}\n',
    "contact solver push bookkeeping",
)
contact = replace_once(
    contact,
    '\t\tcollisions.append(collision)\n\t\tfor normal: Vector3 in contact_projector.get_collision_normals(collision):\n',
    '\t\tcollisions.append(collision)\n\t\t_push_contacted_props(collision, requested_horizontal_velocity, pushed_prop_ids)\n\t\tfor normal: Vector3 in contact_projector.get_collision_normals(collision):\n',
    "contact solver explicit prop push",
)
contact_helper_anchor = '\n\nfunc _resolve_remaining_motion(\n'
contact_helper = '''

func _push_contacted_props(
\tcollision: KinematicCollision3D,
\trequested_horizontal_velocity: Vector3,
\tpushed_prop_ids: Dictionary
) -> void:
\tif collision == null or requested_horizontal_velocity.length_squared() <= MOTION_EPSILON_SQUARED:
\t\treturn
\tfor contact_index: int in range(collision.get_collision_count()):
\t\tvar collider: Object = collision.get_collider(contact_index)
\t\tif collider == null or not collider.has_method("receive_player_push"):
\t\t\tcontinue
\t\tvar normal: Vector3 = collision.get_normal(contact_index)
\t\tvar lateral_normal := Vector3(normal.x, 0.0, normal.z)
\t\tif lateral_normal.length_squared() <= MOTION_EPSILON_SQUARED:
\t\t\tcontinue
\t\tlateral_normal = lateral_normal.normalized()
\t\tif requested_horizontal_velocity.dot(lateral_normal) >= -0.01:
\t\t\tcontinue
\t\tvar collider_id: int = collider.get_instance_id()
\t\tif pushed_prop_ids.has(collider_id):
\t\t\tcontinue
\t\tpushed_prop_ids[collider_id] = true
\t\tcollider.call("receive_player_push", requested_horizontal_velocity)
'''
contact = replace_once(contact, contact_helper_anchor, contact_helper + contact_helper_anchor, "contact solver push helper")
contact_path.write_text(contact, encoding="utf-8")

# Revert the scene's initial body state to exact settled stability. Dynamic
# physics is promoted explicitly by impact/player/support transitions.
tscn_path = Path("gameplay/props/OrdinaryProp.tscn")
tscn = tscn_path.read_text(encoding="utf-8")
tscn = replace_once(tscn, 'lock_rotation = true\nsleeping = true\n', 'lock_rotation = true\nfreeze = true\n', "stable initial prop state")
tscn_path.write_text(tscn, encoding="utf-8")

# Update regression expectations to the explicit-promotion contract.
reg_path = Path("tests/props/prop_regressions.gd")
reg = reg_path.read_text(encoding="utf-8")
reg = replace_once(
    reg,
    'assert_true.call(not pickup_prop.freeze and pickup_prop.sleeping and pickup_prop.lock_rotation and pickup_prop.continuous_cd, "Settled props sleep as wakeable rigid bodies while keeping rotation locked")',
    'assert_true.call(pickup_prop.freeze and pickup_prop.lock_rotation and pickup_prop.continuous_cd, "Settled props remain exactly stable until an explicit physical cause promotes them")',
    "stable settled regression",
)
reg = replace_once(
    reg,
    'assert_true.call(not pickup_prop.freeze and pickup_prop.sleeping and pickup_prop.global_transform.basis.orthonormalized().y.dot(Vector3.UP) > 0.999 and released_settled_facing.dot(released_facing) > 0.995, "Gentle release settles top-up by removing pitch/roll while preserving its yaw, then sleeps wakeable")',
    'assert_true.call(pickup_prop.freeze and pickup_prop.global_transform.basis.orthonormalized().y.dot(Vector3.UP) > 0.999 and released_settled_facing.dot(released_facing) > 0.995, "Gentle release smoothly settles top-up by removing pitch/roll while preserving its yaw, then becomes exactly stable")',
    "released stable settle regression",
)
reg = replace_once(
    reg,
    'assert_true.call(not pickup_prop.freeze and pickup_prop.sleeping and pickup_prop.global_transform.basis.orthonormalized().y.dot(Vector3.UP) > 0.999 and thrown_settled_facing.dot(thrown_facing) > 0.995 and pickup_prop.linear_velocity.is_zero_approx(), "Thrown box settles top-up and sleeping without a global compass-facing snap")',
    'assert_true.call(pickup_prop.freeze and pickup_prop.global_transform.basis.orthonormalized().y.dot(Vector3.UP) > 0.999 and thrown_settled_facing.dot(thrown_facing) > 0.995 and pickup_prop.linear_velocity.is_zero_approx(), "Thrown box smoothly settles top-up and stable without a global compass-facing snap")',
    "thrown stable settle regression",
)
reg_path.write_text(reg, encoding="utf-8")

trans_path = Path("tests/props/phase_3_5_transition_regressions.gd")
trans = trans_path.read_text(encoding="utf-8")
trans = replace_once(
    trans,
    '''\tassert_true.call(
\t\ttarget.call("get_semantic_phase") == OrdinaryProp.PHASE_SETTLED
\t\tand target.sleeping and not target.freeze,
\t\t"Settled ordinary props rest by sleeping rather than becoming frozen/static"
\t)
''',
    '''\tassert_true.call(
\t\ttarget.call("get_semantic_phase") == OrdinaryProp.PHASE_SETTLED
\t\tand target.freeze,
\t\t"Settled ordinary props remain exactly stable until an explicit physical cause promotes them"
\t)
''',
    "transition stable target assertion",
)
trans = replace_once(
    trans,
    '''\t\tprop.call("get_semantic_phase") == OrdinaryProp.PHASE_SETTLED
\t\tand not prop.freeze and prop.sleeping
''',
    '''\t\tprop.call("get_semantic_phase") == OrdinaryProp.PHASE_SETTLED
\t\tand prop.freeze
''',
    "transition smooth settle completion assertion",
)
trans_path.write_text(trans, encoding="utf-8")

# Align living docs with the evidence-backed implementation: exact dormant rest
# plus explicit promotion, not continuously simulated sleeping stacks.
vision_path = Path("docs/GAME_VISION.md")
vision = vision_path.read_text(encoding="utf-8")
vision = replace_once(
    vision,
    'Settled movable props follow **Thief 1 & 2-style object behavior** while still remaining physically responsive to explicit contact. A genuinely resting prop sleeps as a real rigid body instead of becoming a frozen/static body. Sleep keeps authored/support-stable props exactly still until something acts on them, while a moving prop impact or a deliberate player shove can wake and translate them through the normal physics solver. Thrown, gently released, unsupported, or externally disturbed props use real dynamic rigid-body gravity, friction, bounce/slide, and solid collision response.\n',
    'Settled movable props follow **Thief 1 & 2-style object behavior** while still responding physically to explicit contact. A genuinely resting prop uses an exact dormant/stable state so authored edge placements and stacks do not drift from background solver stabilization. A meaningful moving-prop impact, deliberate lateral player shove, or support removal explicitly promotes that same `RigidBody3D` back into dynamic motion; from that point gravity, friction, bounce/slide, transferred momentum, and solid collision response are resolved by the physics engine until it settles again.\n',
    "vision explicit stable promotion",
)
vision = replace_once(
    vision,
    'A meaningful **explicit** physical contact is different from background drift. A thrown/moving prop can transfer momentum into a resting ordinary prop, and walking laterally into a suitable prop can give it a small physical shove. Those contacts wake the same rigid body and may translate it, but ordinary box-like Junk still keeps angular motion locked instead of tumbling freely.\n',
    'A meaningful **explicit** physical contact is different from background drift. A thrown/moving prop can transfer momentum into a resting ordinary prop, and walking laterally into a suitable prop can give it a small physical shove. Those contacts promote the same rigid body into active motion and may translate it, but ordinary box-like Junk still keeps angular motion locked instead of tumbling freely.\n',
    "vision promote wording",
)
vision = replace_once(
    vision,
    'The interpolated pose remains re-seated against the detected support plane throughout the alignment, and completion leaves the same rigid body sleeping/wakeable rather than frozen. Settling must never rotate a particular side toward world north or any other global compass direction.\n',
    'The interpolated pose remains re-seated against the detected support plane throughout the alignment, and completion returns the same rigid body to exact dormant/stable state. A later explicit impact, player shove, or support loss promotes it back into dynamic motion. Settling must never rotate a particular side toward world north or any other global compass direction.\n',
    "vision smooth settle stable completion",
)
vision = replace_once(
    vision,
    'Once motion resolves and the smooth top-up alignment completes, the object becomes settled/sleeping again. Supported props then resume the ordinary stylized support rules above, but a later meaningful impact or lateral player shove can wake them back into disturbed rigid motion.\n',
    'Once motion resolves and the smooth top-up alignment completes, the object becomes exactly settled/stable again. Supported props then resume the ordinary stylized support rules above, but a later meaningful impact or lateral player shove can explicitly promote them back into disturbed rigid motion.\n',
    "vision settle completion stable wording",
)
vision_path.write_text(vision, encoding="utf-8")

plan_path = Path("docs/DEVELOPMENT_PLAN.md")
plan = plan_path.read_text(encoding="utf-8")
plan = replace_once(
    plan,
    '3. **Wakeable world physics.** A settled ordinary prop is a sleeping, non-frozen `RigidBody3D`. Meaningful prop-on-prop impact wakes/translates the struck prop through Jolt. Lateral player locomotion contact applies one bounded shove through the production controller; standing on a prop does not count as a shove. Angular motion remains locked, so these disturbances translate boxes without introducing free tumble.\n',
    '3. **Explicit world-physics promotion.** A settled ordinary prop remains in exact dormant/stable state so authored edge placements and stacks cannot drift from background contact stabilization. A meaningful moving-prop impact transfers momentum and promotes the struck prop into real dynamic Jolt motion; lateral player locomotion contact applies one bounded shove at the production contact-solver boundary; standing on a prop does not count as a shove. Support removal also promotes the prop into unsupported motion. Angular motion remains locked, so these explicit disturbances translate boxes without introducing free tumble.\n',
    "roadmap explicit promotion",
)
plan = replace_once(
    plan,
    '4. **Smooth dynamic settling authority.** Moving props use the real rigid-body contact manifold to identify support/rest candidates. The old lowest-corner proximity-ray heuristic is not settling authority. After genuine low-speed support is established, pitch/roll ease toward top-up over a short physics-step interpolation while yaw stays fixed and the collision shape is continuously re-seated on the detected support plane. A meaningful impact/player shove can interrupt this alignment. Completion returns the same body to sleeping/wakeable settled state, not frozen/static state.\n',
    '4. **Smooth dynamic settling authority.** Moving props use the real rigid-body contact manifold to identify support/rest candidates. The old lowest-corner proximity-ray heuristic is not settling authority. After genuine low-speed support is established, pitch/roll ease toward top-up over a short physics-step interpolation while yaw stays fixed and the collision shape is continuously re-seated on the detected support plane. A meaningful impact/player shove can interrupt this alignment. Completion returns the same body to exact dormant/stable settled state; only an explicit later cause promotes it again.\n',
    "roadmap smooth stable settle",
)
plan = replace_once(
    plan,
    'settled props sleep without drifting but wake and translate when struck by another prop or deliberately pushed laterally by the player;',
    'settled props remain exactly stable without drifting but promote into dynamic translation when struck by another prop or deliberately pushed laterally by the player;',
    "roadmap done stable wording",
)
plan = replace_once(
    plan,
    'sleeping/non-frozen settled state, prop-on-prop wake/translation, production-path player shove,',
    'exact settled stability, prop-on-prop impact promotion/translation, production-path player shove,',
    "roadmap automated stable wording",
)
plan = replace_once(
    plan,
    'and returns to stable sleep.',
    'and returns to exact stable rest.',
    "roadmap manual stable wording",
)
plan_path.write_text(plan, encoding="utf-8")

testing_path = Path("docs/TESTING.md")
testing = testing_path.read_text(encoding="utf-8")
testing = replace_once(
    testing,
    'sleeping/wakeable settled state,',
    'exact dormant/stable settled state with explicit physics promotion,',
    "testing stable state wording",
)
testing = replace_once(
    testing,
    'a sleeping settled prop is physically displaced by a real moving-prop impact; production player locomotion gives one bounded lateral shove to a contacted prop without making standing support a shove;',
    'a stable settled prop is explicitly promoted and physically displaced by a real moving-prop impact; production player locomotion gives one bounded lateral shove at the contact-solver boundary without making standing support a shove;',
    "testing impact push wording",
)
testing = replace_once(
    testing,
    'before returning to sleeping settled state.',
    'before returning to exact stable settled state.',
    "testing settle completion wording",
)
testing_path.write_text(testing, encoding="utf-8")

print("STAGED_EXPLICIT_PROP_PHYSICS_ADJUSTMENT")
