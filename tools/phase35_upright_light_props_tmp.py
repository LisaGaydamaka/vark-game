from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


# Ordinary prop: make carry->world orientation authoritative/upright, keep already
# upright boxes from rotating again during settle, expose traversal stability, and
# tune the same rigid body to feel lighter/more responsive.
prop_path = Path("gameplay/props/ordinary_prop.gd")
prop = prop_path.read_text(encoding="utf-8")
prop = replace_once(
    prop,
    '''const PROP_IMPACT_MIN_IMPULSE: float = 0.05
const PROP_IMPACT_TRANSFER_SCALE: float = 0.35
const PROP_IMPACT_MAX_IMPULSE: float = 2.50
''',
    '''const PROP_IMPACT_MIN_IMPULSE: float = 0.035
const PROP_IMPACT_TRANSFER_SCALE: float = 0.60
const PROP_IMPACT_MAX_IMPULSE: float = 3.25
''',
    "lighter prop impact tuning",
)
prop = replace_once(
    prop,
    '''@export var player_push_speed_scale: float = 0.22
@export var player_push_min_motion_speed: float = 0.30
@export var player_push_max_motion_speed: float = 0.70
''',
    '''@export var player_push_speed_scale: float = 0.32
@export var player_push_min_motion_speed: float = 0.40
@export var player_push_max_motion_speed: float = 1.00
''',
    "lighter player shove tuning",
)
prop = replace_once(
    prop,
    '''func is_supported() -> bool:
\tif _phase == PHASE_CARRIED_JUNK:
\t\treturn false
\treturn _has_support()


func is_world_presentation_enabled() -> bool:
''',
    '''func is_supported() -> bool:
\tif _phase == PHASE_CARRIED_JUNK:
\t\treturn false
\treturn _has_support()


func is_traversal_attachment_stable() -> bool:
\t# Ledge/mantle geometry is sampled in world space. Ordinary props are valid
\t# traversal anchors only while their semantic transform is exact/stable.
\treturn _phase == PHASE_SETTLED


func is_world_presentation_enabled() -> bool:
''',
    "prop traversal stability seam",
)
prop = replace_once(
    prop,
    '''\t_cancel_settle_alignment()
\t_clear_temporary_player_collision_ignore()
\t_holder = null
\tglobal_transform = release_transform
\tvar overlaps_releasing_player: bool = (
\t\treleasing_player != null
\t\tand is_instance_valid(releasing_player)
\t\tand _shape_overlaps_body_at_transform(release_transform, releasing_player)
\t)
\tif prop_mesh != null:
\t\tprop_mesh.visible = true
\tif overlaps_releasing_player:
\t\t_begin_temporary_player_collision_ignore(releasing_player)
\telse:
\t\tcollision_layer = _ordinary_collision_layer
\t\tcollision_mask = _ordinary_collision_mask
\t# F and R differ only by motion kind/velocity. The body becomes live now,
\t# while the exact transform + velocity commit is synchronized with Jolt in
\t# _integrate_forces() on the first active rigid-body step.
\t_stage_rigid_launch(motion_kind, release_transform, initial_velocity)
\treturn true
''',
    '''\tvar upright_release_transform: Transform3D = release_transform
\tupright_release_transform.basis = _top_up_basis_for_yaw(
\t\t_yaw_from_basis(release_transform.basis)
\t)
\t# Carry->world orientation is semantic physics state, not later settle
\t# presentation. Both F and R enter the world with the box top already up.
\tif not is_release_transform_world_clear(upright_release_transform, releasing_player):
\t\treturn false
\t_cancel_settle_alignment()
\t_clear_temporary_player_collision_ignore()
\t_holder = null
\tglobal_transform = upright_release_transform
\tvar overlaps_releasing_player: bool = (
\t\treleasing_player != null
\t\tand is_instance_valid(releasing_player)
\t\tand _shape_overlaps_body_at_transform(upright_release_transform, releasing_player)
\t)
\tif prop_mesh != null:
\t\tprop_mesh.visible = true
\tif overlaps_releasing_player:
\t\t_begin_temporary_player_collision_ignore(releasing_player)
\telse:
\t\tcollision_layer = _ordinary_collision_layer
\t\tcollision_mask = _ordinary_collision_mask
\t# F and R differ only by motion kind/velocity. The body becomes live now,
\t# while the exact transform + velocity commit is synchronized with Jolt in
\t# _integrate_forces() on the first active rigid-body step.
\t_stage_rigid_launch(motion_kind, upright_release_transform, initial_velocity)
\treturn true
''',
    "upright carry to world handoff",
)
prop = replace_once(
    prop,
    '''\tvar normal: Vector3 = support_normal.normalized() if support_normal.length_squared() > 0.000001 else Vector3.UP
\tvar target_basis: Basis = _top_up_basis_for_yaw(_settle_yaw)
\tvar target_origin: Vector3 = _origin_reseated_on_support(
''',
    '''\tvar normal: Vector3 = support_normal.normalized() if support_normal.length_squared() > 0.000001 else Vector3.UP
\tvar current_basis: Basis = global_transform.basis.orthonormalized()
\tvar target_basis: Basis = current_basis
\t# Carry release/throw is already exactly top-up and angular motion is locked.
\t# Preserve that exact orientation through settle instead of recomputing a
\t# second yaw basis that can make a symmetric box appear to roll to a new face.
\tif current_basis.y.dot(Vector3.UP) < 0.999999:
\t\ttarget_basis = _top_up_basis_for_yaw(_settle_yaw)
\tvar target_origin: Vector3 = _origin_reseated_on_support(
''',
    "settle preserves already upright orientation",
)
prop_path.write_text(prop, encoding="utf-8")


# Carry placement must test the same upright volume that the prop will actually
# hand to physics; otherwise the later normalization could invalidate clearance.
carry_path = Path("player/interaction/player_prop_carry.gd")
carry = carry_path.read_text(encoding="utf-8")
carry = replace_once(
    carry,
    '''\tvar view_basis: Basis = camera.global_transform.basis.orthonormalized()
\tvar forward: Vector3 = -view_basis.z.normalized()
\tvar release_basis: Basis = (view_basis * Basis(Vector3.BACK, PI * 0.5)).orthonormalized()
''',
    '''\tvar view_basis: Basis = camera.global_transform.basis.orthonormalized()
\tvar forward: Vector3 = -view_basis.z.normalized()
\tvar release_basis: Basis = _upright_release_basis(view_basis)
''',
    "upright release placement basis",
)
carry = replace_once(
    carry,
    '''func _is_release_pose_world_clear(candidate: Transform3D) -> bool:
''',
    '''func _upright_release_basis(view_basis: Basis) -> Basis:
\tvar horizontal_forward: Vector3 = -view_basis.z
\thorizontal_forward.y = 0.0
\tif horizontal_forward.length_squared() <= 0.000001 and player != null:
\t\thorizontal_forward = -player.global_transform.basis.z
\t\thorizontal_forward.y = 0.0
\tif horizontal_forward.length_squared() <= 0.000001:
\t\treturn Basis.IDENTITY
\thorizontal_forward = horizontal_forward.normalized()
\tvar yaw: float = atan2(-horizontal_forward.x, -horizontal_forward.z)
\treturn Basis(Vector3.UP, yaw).orthonormalized()


func _is_release_pose_world_clear(candidate: Transform3D) -> bool:
''',
    "upright release basis helper",
)
carry_path.write_text(carry, encoding="utf-8")


# Physical tuning: significantly lighter than the previous 1.5 kg / high-friction
# crate while retaining enough friction to stack and stop predictably.
scene_path = Path("gameplay/props/OrdinaryProp.tscn")
scene = scene_path.read_text(encoding="utf-8")
scene = replace_once(scene, "friction = 0.8\n", "friction = 0.55\n", "prop friction")
scene = replace_once(scene, "mass = 1.5\n", "mass = 0.85\n", "prop mass")
scene = replace_once(scene, "linear_damp = 0.1\n", "linear_damp = 0.08\n", "prop linear damping")
scene_path.write_text(scene, encoding="utf-8")


# Ledge candidates are world-space snapshots. Resolve their body RIDs back to the
# gameplay object and ask dynamic geometry whether it is currently stable enough
# to remain an attachment source.
detector_path = Path("player/traversal/player_ledge_detector.gd")
detector = detector_path.read_text(encoding="utf-8")
detector = replace_once(
    detector,
    '''func invalidate_collider(collider_rid: RID) -> bool:
''',
    '''func is_candidate_attachment_stable(candidate: LedgeCandidate) -> bool:
\tif candidate == null:
\t\treturn false
\treturn (
\t\t_collider_allows_traversal_attachment(candidate.wall_collider_rid)
\t\tand _collider_allows_traversal_attachment(candidate.top_collider_rid)
\t)


func _collider_allows_traversal_attachment(collider_rid: RID) -> bool:
\tif not collider_rid.is_valid():
\t\treturn true
\tvar instance_id: int = PhysicsServer3D.body_get_object_instance_id(collider_rid)
\tif instance_id == 0:
\t\treturn true
\tvar collider: Object = instance_from_id(instance_id)
\tif collider == null or not is_instance_valid(collider):
\t\treturn false
\tif collider.has_method("is_traversal_attachment_stable"):
\t\treturn bool(collider.call("is_traversal_attachment_stable"))
\treturn true


func invalidate_collider(collider_rid: RID) -> bool:
''',
    "dynamic traversal attachment stability",
)
detector_path.write_text(detector, encoding="utf-8")


# Traversal controller owns the active attachment transaction. Reject a moving
# prop before start and cancel immediately if a previously settled prop becomes
# dynamic during catch/hang/corner/mantle.
controller_path = Path("player/traversal/player_ledge_controller.gd")
controller = controller_path.read_text(encoding="utf-8")
controller = replace_once(
    controller,
    '''func update(jump_pressed: bool, crouch_pressed: bool, delta: float) -> void:
\tmatch state:
''',
    '''func update(jump_pressed: bool, crouch_pressed: bool, delta: float) -> void:
\tif state != State.NONE and not _active_attachment_is_stable():
\t\t_release_unstable_attachment(delta)
\t\treturn
\tmatch state:
''',
    "active traversal stability guard",
)
controller = replace_once(
    controller,
    '''func _candidate_uses_collider(
\tcandidate: PlayerLedgeDetector.LedgeCandidate,
\tcollider_rid: RID
) -> bool:
\tif candidate == null or not collider_rid.is_valid():
\t\treturn false
\treturn (
\t\t(candidate.wall_collider_rid.is_valid() and candidate.wall_collider_rid == collider_rid)
\t\tor (candidate.top_collider_rid.is_valid() and candidate.top_collider_rid == collider_rid)
\t)


func update(jump_pressed: bool, crouch_pressed: bool, delta: float) -> void:
''',
    '''func _candidate_uses_collider(
\tcandidate: PlayerLedgeDetector.LedgeCandidate,
\tcollider_rid: RID
) -> bool:
\tif candidate == null or not collider_rid.is_valid():
\t\treturn false
\treturn (
\t\t(candidate.wall_collider_rid.is_valid() and candidate.wall_collider_rid == collider_rid)
\t\tor (candidate.top_collider_rid.is_valid() and candidate.top_collider_rid == collider_rid)
\t)


func _active_attachment_is_stable() -> bool:
\tmatch state:
\t\tState.CATCHING:
\t\t\treturn ledge_detector.is_candidate_attachment_stable(active_catch_candidate)
\t\tState.HANGING:
\t\t\treturn ledge_detector.is_candidate_attachment_stable(ledge_hang.get_candidate())
\t\tState.CORNERING:
\t\t\tvar candidates: Array[PlayerLedgeDetector.LedgeCandidate] = ledge_corner.get_release_candidates()
\t\t\tif candidates.is_empty():
\t\t\t\treturn false
\t\t\tfor candidate: PlayerLedgeDetector.LedgeCandidate in candidates:
\t\t\t\tif not ledge_detector.is_candidate_attachment_stable(candidate):
\t\t\t\t\treturn false
\t\t\treturn true
\t\tState.MANTLING:
\t\t\treturn ledge_detector.is_candidate_attachment_stable(ledge_mantle.get_release_candidate())
\treturn true


func _release_unstable_attachment(delta: float) -> void:
\tmatch state:
\t\tState.CATCHING:
\t\t\tledge_catch.cancel()
\t\t\tactive_catch_candidate = null
\t\tState.HANGING:
\t\t\tledge_hang.cancel()
\t\tState.CORNERING:
\t\t\tledge_corner.cancel()
\t\tState.MANTLING:
\t\t\tledge_mantle.cancel()
\t_finish_release_to_air(delta, true)


func update(jump_pressed: bool, crouch_pressed: bool, delta: float) -> void:
''',
    "active traversal stability helpers",
)
controller = replace_once(
    controller,
    '''\tfor candidate: PlayerLedgeDetector.LedgeCandidate in candidates:
\t\tif candidate == null or not candidate.hangable:
\t\t\tcontinue
\t\tif traversal_guard.is_hang_blocked(candidate):
''',
    '''\tfor candidate: PlayerLedgeDetector.LedgeCandidate in candidates:
\t\tif candidate == null or not candidate.hangable:
\t\t\tcontinue
\t\tif not ledge_detector.is_candidate_attachment_stable(candidate):
\t\t\tcontinue
\t\tif traversal_guard.is_hang_blocked(candidate):
''',
    "hang rejects moving dynamic attachment",
)
controller = replace_once(
    controller,
    '''\tfor candidate: PlayerLedgeDetector.LedgeCandidate in candidates:
\t\tif candidate == null:
\t\t\tcontinue
\t\tif traversal_guard.is_mantle_blocked(candidate):
''',
    '''\tfor candidate: PlayerLedgeDetector.LedgeCandidate in candidates:
\t\tif candidate == null:
\t\t\tcontinue
\t\tif not ledge_detector.is_candidate_attachment_stable(candidate):
\t\t\tcontinue
\t\tif traversal_guard.is_mantle_blocked(candidate):
''',
    "mantle rejects moving dynamic attachment",
)
controller = replace_once(
    controller,
    '''func _try_start_free_mantle(
\tcandidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
\tvar mantle_candidate: PlayerMantle.MantleCandidate = (
''',
    '''func _try_start_free_mantle(
\tcandidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
\tif not ledge_detector.is_candidate_attachment_stable(candidate):
\t\treturn false
\tvar mantle_candidate: PlayerMantle.MantleCandidate = (
''',
    "free mantle dynamic attachment guard",
)
controller = replace_once(
    controller,
    '''\t\tif completed_candidate == null:
\t\t\t_release_corner_to_air(delta)
\t\t\treturn
''',
    '''\t\tif (
\t\t\tcompleted_candidate == null
\t\t\tor not ledge_detector.is_candidate_attachment_stable(completed_candidate)
\t\t):
\t\t\t_release_corner_to_air(delta)
\t\t\treturn
''',
    "corner completion dynamic attachment guard",
)
controller_path.write_text(controller, encoding="utf-8")


# Regression contract updates.
prop_test_path = Path("tests/props/prop_regressions.gd")
prop_test = prop_test_path.read_text(encoding="utf-8")
prop_test = replace_once(
    prop_test,
    '''\tassert_true.call(pickup_prop.freeze and pickup_prop.lock_rotation and pickup_prop.continuous_cd, "Settled props remain exactly stable until an explicit physical cause promotes them")
''',
    '''\tassert_true.call(pickup_prop.freeze and pickup_prop.lock_rotation and pickup_prop.continuous_cd, "Settled props remain exactly stable until an explicit physical cause promotes them")
\tvar prop_physics_material: PhysicsMaterial = pickup_prop.physics_material_override
\tassert_true.call(
\t\tpickup_prop.mass <= 0.9
\t\tand prop_physics_material != null
\t\tand prop_physics_material.friction <= 0.6
\t\tand float(pickup_prop.get("player_push_speed_scale")) >= 0.3,
\t\t"Ordinary crates use the lighter, more responsive Phase 3.5 physical tuning"
\t)
''',
    "light prop tuning regression",
)
prop_test = replace_once(
    prop_test,
    '''\tvar released_facing: Vector3 = _horizontal_forward_from_basis(pickup_prop.global_transform.basis)
\tassert_true.call(not pickup_prop.freeze and released_state.get("motion_kind", &"") == OrdinaryProp.MOTION_RELEASED and released_velocity.length() < 2.0 and release_direction.dot(release_forward) > 0.72, "R gently restores the prop as a live rigid body at a view-derived release point")
\tassert_true.call(absf(pickup_prop.global_transform.basis.orthonormalized().y.dot(Vector3.UP)) < 0.25, "Released moving box starts side-on rather than canonical top-up")
\tawait _settle_until_phase(tree, pickup_prop, OrdinaryProp.PHASE_SETTLED, 160)
\tvar released_strength: float = _max_impact_strength(sound_events, released_sound_start)
\tvar released_settled_facing: Vector3 = _horizontal_forward_from_basis(pickup_prop.global_transform.basis)
\tassert_true.call(pickup_prop.freeze and pickup_prop.global_transform.basis.orthonormalized().y.dot(Vector3.UP) > 0.999 and released_settled_facing.dot(released_facing) > 0.995, "Gentle release smoothly settles top-up by removing pitch/roll while preserving its yaw, then becomes exactly stable")
''',
    '''\tvar released_basis: Basis = pickup_prop.global_transform.basis.orthonormalized()
\tvar released_facing: Vector3 = _horizontal_forward_from_basis(released_basis)
\tassert_true.call(not pickup_prop.freeze and released_state.get("motion_kind", &"") == OrdinaryProp.MOTION_RELEASED and released_velocity.length() < 2.0 and release_direction.dot(release_forward) > 0.72, "R gently restores the prop as a live rigid body at a view-derived release point")
\tassert_true.call(released_basis.y.dot(Vector3.UP) > 0.999999, "R release enters world physics with the box top already up")
\tawait _settle_until_phase(tree, pickup_prop, OrdinaryProp.PHASE_SETTLED, 160)
\tvar released_strength: float = _max_impact_strength(sound_events, released_sound_start)
\tvar released_settled_basis: Basis = pickup_prop.global_transform.basis.orthonormalized()
\tvar released_settled_facing: Vector3 = _horizontal_forward_from_basis(released_settled_basis)
\tassert_true.call(pickup_prop.freeze and released_settled_basis.y.dot(Vector3.UP) > 0.999999 and released_settled_facing.dot(released_facing) > 0.995 and released_settled_basis.is_equal_approx(released_basis), "Gentle release keeps its upright orientation through settle instead of rolling onto another face")
''',
    "upright R release regression",
)
prop_test = replace_once(
    prop_test,
    '''\tassert_true.call(not pickup_prop.freeze and thrown_state.get("motion_kind", &"") == OrdinaryProp.MOTION_THROWN and thrown_velocity.length() > released_velocity.length() + 2.0 and pickup_prop.get_instance_id() == original_instance_id, "F throws the same prop identity as an active rigid body with substantially stronger motion than R release")
''',
    '''\tassert_true.call(not pickup_prop.freeze and thrown_state.get("motion_kind", &"") == OrdinaryProp.MOTION_THROWN and thrown_velocity.length() > released_velocity.length() + 2.0 and pickup_prop.get_instance_id() == original_instance_id and thrown_basis.y.dot(Vector3.UP) > 0.999999, "F throws the same prop identity upright as an active rigid body with substantially stronger motion than R release")
''',
    "upright F throw regression",
)
prop_test = replace_once(
    prop_test,
    '''\tvar thrown_settled_facing: Vector3 = _horizontal_forward_from_basis(pickup_prop.global_transform.basis)
\tassert_true.call(pickup_prop.freeze and pickup_prop.global_transform.basis.orthonormalized().y.dot(Vector3.UP) > 0.999 and thrown_settled_facing.dot(thrown_facing) > 0.995 and pickup_prop.linear_velocity.is_zero_approx(), "Thrown box smoothly settles top-up and stable without a global compass-facing snap")
''',
    '''\tvar thrown_settled_basis: Basis = pickup_prop.global_transform.basis.orthonormalized()
\tvar thrown_settled_facing: Vector3 = _horizontal_forward_from_basis(thrown_settled_basis)
\tassert_true.call(pickup_prop.freeze and thrown_settled_basis.y.dot(Vector3.UP) > 0.999999 and thrown_settled_facing.dot(thrown_facing) > 0.995 and thrown_settled_basis.is_equal_approx(thrown_basis) and pickup_prop.linear_velocity.is_zero_approx(), "Thrown box remains upright through collision and settle without a second face-changing rotation")
''',
    "upright throw settle regression",
)
prop_test_path.write_text(prop_test, encoding="utf-8")

transition_path = Path("tests/props/phase_3_5_transition_regressions.gd")
transition = transition_path.read_text(encoding="utf-8")
transition = replace_once(
    transition,
    '''\tvar mantle: RefCounted = player.get("ledge_mantle") as RefCounted
\tif controller == null or hang == null or corner == null or mantle == null:
''',
    '''\tvar mantle: RefCounted = player.get("ledge_mantle") as RefCounted
\tvar detector: RefCounted = player.get("ledge_detector") as RefCounted
\tif controller == null or hang == null or corner == null or mantle == null or detector == null:
''',
    "traversal test detector dependency",
)
transition = replace_once(
    transition,
    '''\tassert_true.call(bool(controller.call("invalidate_collider", prop.get_rid())) and int(controller.get("state")) == PlayerLedgeController.State.NONE, "Mantle state invalidates with its prop collider")
''',
    '''\tassert_true.call(bool(controller.call("invalidate_collider", prop.get_rid())) and int(controller.get("state")) == PlayerLedgeController.State.NONE, "Mantle state invalidates with its prop collider")

\tvar settled_snapshot: Dictionary = prop.call("capture_semantic_state")
\tassert_true.call(bool(detector.call("is_candidate_attachment_stable", candidate)), "A settled prop is valid traversal attachment geometry")
\tvar moving_snapshot := {
\t\t"phase": OrdinaryProp.PHASE_MOVING,
\t\t"motion_kind": OrdinaryProp.MOTION_DISTURBED,
\t\t"transform": prop.global_transform,
\t\t"linear_velocity": Vector3.ZERO,
\t\t"settle_yaw": 0.0,
\t}
\tassert_true.call(
\t\tbool(prop.call("apply_semantic_state", moving_snapshot))
\t\tand not bool(detector.call("is_candidate_attachment_stable", candidate)),
\t\t"A moving ordinary prop is rejected as stale world-space traversal geometry"
\t)
\tmantle_candidate = PlayerMantle.MantleCandidate.new()
\tmantle_candidate.source_candidate = candidate
\tmantle_candidate.valid = true
\tmantle.set("active_candidate", mantle_candidate)
\tmantle.set("phase", PlayerMantle.Phase.LIFT)
\tcontroller.set("state", PlayerLedgeController.State.MANTLING)
\tcontroller.call("update", false, false, 1.0 / 60.0)
\tassert_true.call(
\t\tint(controller.get("state")) == PlayerLedgeController.State.NONE
\t\tand int(mantle.get("phase")) == PlayerMantle.Phase.NONE,
\t\t"Active mantle cancels to air when its ordinary-prop attachment becomes dynamic"
\t)
\tassert_true.call(
\t\tbool(prop.call("apply_semantic_state", settled_snapshot))
\t\tand bool(detector.call("is_candidate_attachment_stable", candidate)),
\t\t"Traversal attachment eligibility returns only after the prop is semantically settled again"
\t)
''',
    "moving prop mantle invalidation regression",
)
transition_path.write_text(transition, encoding="utf-8")


# Documentation follows the new accepted-target behavior while keeping Phase 3.5
# in manual-acceptance state.
vision_path = Path("docs/GAME_VISION.md")
vision = vision_path.read_text(encoding="utf-8")
vision = replace_once(
    vision,
    '''A meaningful **explicit** physical contact is different from background drift. A thrown/moving prop can transfer momentum into a resting ordinary prop, and walking laterally into a suitable prop can give it a small physical shove. Those contacts promote the same rigid body into active motion and may translate it, but ordinary box-like Junk still keeps angular motion locked instead of tumbling freely.
''',
    '''A meaningful **explicit** physical contact is different from background drift. A thrown/moving prop can transfer momentum into a resting ordinary prop, and walking laterally into a suitable prop can give it a clear physical shove. Ordinary box-like Junk is intentionally lightweight and readily movable by deliberate player pressure and prop-on-prop impacts. Those contacts promote the same rigid body into active motion and may translate it, but angular motion remains locked instead of tumbling freely.
''',
    "vision lighter props",
)
vision = replace_once(
    vision,
    '''A prop that leaves world participation also invalidates player state derived from that exact collider. Standing support and active catch/hang/corner/mantle attachment cannot outlive a prop that has been picked up as carried Junk.
''',
    '''A prop that leaves world participation also invalidates player state derived from that exact collider. Standing support and active catch/hang/corner/mantle attachment cannot outlive a prop that has been picked up as carried Junk.

Ordinary props are valid ledge/mantle attachment geometry only while semantically settled. Their traversal candidates are world-space snapshots, so a moving or settling prop cannot start a new catch/hang/corner/mantle attachment, and an active traversal tied to that prop cancels to ordinary airborne motion if the prop becomes dynamic. Traversal may use that collider again only after it returns to the exact settled state.
''',
    "vision moving prop traversal ownership",
)
vision = replace_once(
    vision,
    '''Thrown/released/unsupported/disturbed objects use real rigid-body translation while moving: gravity and collisions may change their position, linear velocity, slide, and bounce. Ordinary box-like Junk keeps angular motion locked during this moving phase, so hitting a floor, wall, prop, or actor does **not** rotate the box in flight. It does not continuously track later camera turns. When the prop genuinely settles, only pitch/roll are normalized so the top points upward; its current yaw is preserved. This final normalization is a short smooth settle alignment rather than a one-frame visual pop. The interpolated pose remains re-seated against the detected support plane throughout the alignment, and completion returns the same rigid body to exact dormant/stable state. A later explicit impact, player shove, or support loss promotes it back into dynamic motion. Settling must never rotate a particular side toward world north or any other global compass direction.
''',
    '''Throw and gentle release enter world physics with the ordinary box already **top-up**, using the current view only to choose horizontal yaw and placement direction. Thrown/released/unsupported/disturbed objects then use real rigid-body translation while moving: gravity and collisions may change their position, linear velocity, slide, and bounce. Ordinary box-like Junk keeps angular motion locked, so hitting a floor, wall, prop, or actor does **not** rotate the box in flight and the object does not continuously track later camera turns. Because normal F/R carry release is already upright, ordinary settling preserves that exact orientation and only re-seats the body onto detected support; it must not perform a second face-changing roll after translation stops. A genuinely pre-tilted unsupported/restored prop may still use the short smooth pitch/roll correction to return top-up while preserving yaw. Completion returns the same rigid body to exact dormant/stable state. A later explicit impact, player shove, or support loss promotes it back into dynamic motion. Settling must never rotate a particular side toward world north or any other global compass direction.
''',
    "vision upright launch and settle orientation",
)
vision_path.write_text(vision, encoding="utf-8")

plan_path = Path("docs/DEVELOPMENT_PLAN.md")
plan = plan_path.read_text(encoding="utf-8")
plan = replace_once(
    plan,
    '''3. **Explicit world-physics promotion.** A settled ordinary prop remains in exact dormant/stable state so authored edge placements and stacks cannot drift from background contact stabilization. A meaningful moving-prop impact transfers momentum and promotes the struck prop into real dynamic Jolt motion; lateral player locomotion contact applies one bounded shove at the production contact-solver boundary; standing on a prop does not count as a shove. Support removal also promotes the prop into unsupported motion. Angular motion remains locked, so these explicit disturbances translate boxes without introducing free tumble.
4. **Smooth dynamic settling authority.** Moving props use the real rigid-body contact manifold to identify support/rest candidates. The old lowest-corner proximity-ray heuristic is not settling authority. After genuine low-speed support is established, pitch/roll ease toward top-up over a short physics-step interpolation while yaw stays fixed and the collision shape is continuously re-seated on the detected support plane. A meaningful impact/player shove can interrupt this alignment. Completion returns the same body to exact dormant/stable settled state; only an explicit later cause promotes it again.
5. **Acceptance.** Keep the existing carried-Junk HUD, F throw, R gentle release, hard-edged rendering, real rigid translation, stable authored edge/stack rest, semantic sound/capture/reconcile seams, and accepted player movement feel unchanged.
''',
    '''3. **Explicit lightweight world-physics promotion.** A settled ordinary prop remains in exact dormant/stable state so authored edge placements and stacks cannot drift from background contact stabilization. Ordinary crates use lighter mass/friction and stronger bounded response tuning so deliberate player pressure moves them readily and prop-on-prop impacts transfer visibly more motion. A meaningful moving-prop impact promotes the struck prop into real dynamic Jolt motion; lateral player locomotion contact applies one bounded shove at the production contact-solver boundary; standing on a prop does not count as a shove. Support removal also promotes the prop into unsupported motion. Angular motion remains locked, so these explicit disturbances translate boxes without introducing free tumble.
4. **Upright carry handoff and settling authority.** F throw and R gentle release choose placement from the current view but normalize the box top-up before the carry→world rigid-body handoff, preserving horizontal yaw. The placement query uses that same upright collision volume. Moving props use the real rigid-body contact manifold to identify support/rest candidates. Because normal carry release is already upright and angular motion remains locked, settling preserves that exact orientation and re-seats translation onto support instead of performing a second face-changing roll. A genuinely pre-tilted unsupported/restored prop may still use the short yaw-preserving pitch/roll alignment. A meaningful impact/player shove can interrupt that alignment. Completion returns the same body to exact dormant/stable settled state.
5. **Dynamic-prop traversal ownership.** Ledge/mantle candidates are world-space geometry snapshots, so an ordinary prop may be a traversal attachment only while its semantic transform is settled/stable. Moving/settling props are rejected for new catch/hang/corner/mantle entry, and an active traversal depending on a prop cancels to airborne motion if that prop becomes dynamic. The collider becomes eligible again only after semantic settle.
6. **Acceptance.** Keep the existing carried-Junk HUD, F throw, R gentle release, hard-edged rendering, real rigid translation, stable authored edge/stack rest, semantic sound/capture/reconcile seams, and accepted player movement feel unchanged.
''',
    "plan Phase 3.5 correction order",
)
plan = replace_once(
    plan,
    '''**Done when:** world/prop blockers remain solid during release placement; an initially player-overlapping throw retains its intended impulse and restores normal player collision after separation; picking up the exact supporting/traversal prop ends that dependency immediately; settled props remain exactly stable without drifting but promote into dynamic translation when struck by another prop or deliberately pushed laterally by the player; low-speed tilted contact enters a visibly smooth, yaw-preserving, support-reseated top-up alignment instead of popping; meaningful contact can interrupt that alignment; no-gap/no-free-tumble behavior remains; and the authoritative all-tests barrier plus Windows x64 user acceptance pass.

**Automated:** required — the dedicated Props suite must exercise shape-aware world-blocked placement, overlapping-player throw impulse preservation, player-only overlap-filter lifetime, exact support RID invalidation, catch/hang/corner/mantle collider invalidation, exact settled stability, prop-on-prop impact promotion/translation, production-path player shove, multi-frame smooth narrow-support alignment, yaw/support re-seating, existing prop behavior, and the unchanged movement regression suite through `tests/run_all_tests.gd`.

**Manual:** pending — validator: **Windows x64 user/playtester**. Launch **Development Launch → Prop Lab**. Confirm the already-accepted F throw remains materially stronger than R release, including cramped player-overlap cases. Walk laterally into a resting crate and confirm it yields/moves a little without tumbling; throw one crate into another and confirm the struck crate wakes and is knocked back. Resting edge/stack props must remain exactly still until explicitly disturbed. Repeatedly release tilted boxes onto floors/box edges/corners and confirm the final top-up correction is adequately smooth rather than a visible pop, preserves yaw, stays seated with no hover gap, and returns to exact stable rest. Also retain pickup/HUD, movement/look/crouch/jump, lower-support fall, hard-edged rendering, support/traversal invalidation, wall/prop collision, and restored post-overlap player collision.
''',
    '''**Done when:** world/prop blockers remain solid during release placement; F and R enter world physics with the box top already up and preserve that orientation through ordinary settle; an initially player-overlapping throw retains its intended impulse and restores normal player collision after separation; picking up the exact supporting/traversal prop ends that dependency immediately; moving ordinary props cannot provide stale mantle/ledge attachments and active traversal falls cleanly if its prop becomes dynamic; settled props remain exactly stable without drifting but are clearly easier to move by deliberate player pressure and react more strongly to another prop impact; pre-tilted unsupported contact can still use the smooth yaw-preserving support-reseated correction; no-gap/no-free-tumble behavior remains; and the authoritative all-tests barrier plus Windows x64 user acceptance pass.

**Automated:** required — the dedicated Props suite must exercise upright F/R carry→world orientation, shape-aware world-blocked placement, overlapping-player throw impulse preservation, player-only overlap-filter lifetime, exact support RID invalidation, catch/hang/corner/mantle collider invalidation, moving-prop traversal ineligibility/active-mantle cancellation, lighter prop tuning, exact settled stability, prop-on-prop impact promotion/translation, production-path player shove, multi-frame smooth pre-tilted narrow-support alignment, yaw/support re-seating, existing prop behavior, and the unchanged movement regression suite through `tests/run_all_tests.gd`.

**Manual:** pending — validator: **Windows x64 user/playtester**. Launch **Development Launch → Prop Lab**. Confirm F throw remains materially stronger than R release and both leave the hand with the box top already up; after either action the box must not roll onto a different face when translation stops. Walk laterally into a resting crate and confirm the lighter crate yields clearly without tumbling; throw one crate into another and confirm the struck crate reacts more strongly than before. Run into a crate so it starts moving and immediately attempt mantle: moving/settling props must not become stale traversal anchors, and if an attached prop is disturbed during traversal the player must drop back to ordinary airborne control rather than ending stuck on it. Resting edge/stack props must remain exactly still until explicitly disturbed. Also retain cramped player-overlap release, pickup/HUD, movement/look/crouch/jump, lower-support fall, hard-edged rendering, wall/prop collision, pre-tilted support correction, no hover gap, and restored post-overlap player collision.
''',
    "plan Phase 3.5 acceptance update",
)
plan_path.write_text(plan, encoding="utf-8")

testing_path = Path("docs/TESTING.md")
testing = testing_path.read_text(encoding="utf-8")
testing = replace_once(
    testing,
    '''Phase 3.5 has a dedicated Props suite wired through the authoritative all-tests barrier. It retains the production-path Prop Lab coverage for outward/hard OBJ normals, normal lit/shadowed presentation, external-model replacement, real `RigidBody3D` ownership, exact dormant/stable settled state with explicit physics promotion, single-slot `carried_junk`, bottom-center HUD presentation, normal locomotion while carrying, central interaction/hand suppression, stale F/R edge suppression, F throw versus R release, semantic sound, detached capture/reconcile, edge support, stable stacks, lower-support fall, yaw-preserving top-up, no support gap, and no post-settle drift/spin. A second focused Phase 3.5 transition regression exercises the cross-system failure boundaries directly: shape-volume-aware release backs away from a world blocker; a valid throw pose intentionally overlapping the player activates a live rigid body whose full throw velocity/displacement is committed through the synchronized direct-body-state callback; the overlap uses a player-only transient collision channel while retaining world/prop collision, and ordinary player collision returns after geometric separation; a stable settled prop is explicitly promoted and physically displaced by a real moving-prop impact; production player locomotion gives one bounded lateral shove at the contact-solver boundary without making standing support a shove; standing support stores and invalidates the exact prop collider RID; catch/hang/corner/mantle state is canceled only when its referenced collider is invalidated; and a tilted moving crate resting on a narrow support enters a multi-frame support-reseated top-up alignment before returning to exact stable settled state. The authoritative all-tests barrier continues to run the accepted movement suite alongside these corrections. Acoustic propagation remains Phase 3.6.
''',
    '''Phase 3.5 has a dedicated Props suite wired through the authoritative all-tests barrier. It retains the production-path Prop Lab coverage for outward/hard OBJ normals, normal lit/shadowed presentation, external-model replacement, real `RigidBody3D` ownership, exact dormant/stable settled state with explicit physics promotion, single-slot `carried_junk`, bottom-center HUD presentation, normal locomotion while carrying, central interaction/hand suppression, stale F/R edge suppression, F throw versus R release, semantic sound, detached capture/reconcile, edge support, stable stacks, lower-support fall, no support gap, and no post-settle drift/spin. F throw and R release now enter world physics top-up using the same upright collision volume used by placement; normal settle preserves that exact orientation rather than rolling onto another face, while the synthetic pre-tilted unsupported fixture still proves the smooth yaw-preserving correction path. The crate fixture also protects the lighter mass/friction/player-shove tuning. A second focused Phase 3.5 transition regression exercises the cross-system failure boundaries directly: shape-volume-aware release backs away from a world blocker; a valid throw pose intentionally overlapping the player activates a live rigid body whose full throw velocity/displacement is committed through the synchronized direct-body-state callback; the overlap uses a player-only transient collision channel while retaining world/prop collision, and ordinary player collision returns after geometric separation; a stable settled prop is explicitly promoted and physically displaced by a real moving-prop impact; production player locomotion gives one bounded lateral shove at the contact-solver boundary without making standing support a shove; standing support stores and invalidates the exact prop collider RID; catch/hang/corner/mantle state is canceled only when its referenced collider is invalidated; ordinary props are accepted as traversal geometry only while semantically settled and an active mantle cancels if that attachment becomes dynamic; and a pre-tilted moving crate resting on a narrow support enters a multi-frame support-reseated top-up alignment before returning to exact stable settled state. The authoritative all-tests barrier continues to run the accepted movement suite alongside these corrections. Acoustic propagation remains Phase 3.6.
''',
    "testing Phase 3.5 behavior update",
)
testing_path.write_text(testing, encoding="utf-8")

print("STAGED_PHASE35_UPRIGHT_LIGHT_PROP_CORRECTION")
