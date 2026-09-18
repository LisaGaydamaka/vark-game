from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one anchor, found {count}")
    p.write_text(text.replace(old, new, 1))


replace_once(
    "player/traversal/player_ledge_detector.gd",
    '''class LedgeCandidate:
\tvar wall_collider_rid: RID = RID()
\tvar wall_shape_index: int = -1
\tvar top_collider_rid: RID = RID()
\tvar top_shape_index: int = -1

\tvar edge_point: Vector3 = Vector3.ZERO''',
    '''class LedgeCandidate:
\tvar wall_collider_rid: RID = RID()
\tvar wall_shape_index: int = -1
\tvar top_collider_rid: RID = RID()
\tvar top_shape_index: int = -1
\tvar attachment_collider_rid: RID = RID()
\tvar attachment_collider_transform: Transform3D = Transform3D.IDENTITY
\tvar attachment_collider_transform_valid: bool = false

\tvar edge_point: Vector3 = Vector3.ZERO'''
)

replace_once(
    "player/traversal/player_ledge_detector.gd",
    '''func is_candidate_attachment_stable(candidate: LedgeCandidate) -> bool:
\tif candidate == null:
\t\treturn false
\treturn (
\t\t_collider_allows_traversal_attachment(candidate.wall_collider_rid)
\t\tand _collider_allows_traversal_attachment(candidate.top_collider_rid)
\t)


func _collider_allows_traversal_attachment(collider_rid: RID) -> bool:''',
    '''func is_candidate_attachment_stable(candidate: LedgeCandidate) -> bool:
\tif candidate == null:
\t\treturn false
\treturn (
\t\t_collider_allows_traversal_attachment(candidate.wall_collider_rid)
\t\tand _collider_allows_traversal_attachment(candidate.top_collider_rid)
\t)


func refresh_candidate_attachment(candidate: LedgeCandidate) -> bool:
\tif candidate == null:
\t\treturn false
\tif not candidate.attachment_collider_transform_valid:
\t\treturn true
\tvar collider: Node3D = _get_candidate_attachment_collider(
\t\tcandidate.attachment_collider_rid
\t)
\tif collider == null:
\t\treturn false
\tvar current_transform: Transform3D = collider.global_transform
\tvar previous_transform: Transform3D = candidate.attachment_collider_transform
\tif current_transform.is_equal_approx(previous_transform):
\t\treturn true
\tvar previous_inverse: Transform3D = previous_transform.affine_inverse()
\tvar basis_delta: Basis = (
\t\tcurrent_transform.basis * previous_transform.basis.inverse()
\t)
\tcandidate.edge_point = current_transform * (previous_inverse * candidate.edge_point)
\tcandidate.top_point = current_transform * (previous_inverse * candidate.top_point)
\tcandidate.hang_position = current_transform * (previous_inverse * candidate.hang_position)
\tcandidate.wall_normal = (basis_delta * candidate.wall_normal).normalized()
\tcandidate.top_normal = (basis_delta * candidate.top_normal).normalized()
\tcandidate.ledge_direction = (basis_delta * candidate.ledge_direction).normalized()
\tcandidate.attachment_collider_transform = current_transform
\treturn true


func _capture_candidate_attachment_transform(candidate: LedgeCandidate) -> void:
\tif (
\t\tcandidate == null
\t\tor not candidate.wall_collider_rid.is_valid()
\t\tor candidate.wall_collider_rid != candidate.top_collider_rid
\t):
\t\treturn
\tvar collider: Node3D = _get_candidate_attachment_collider(
\t\tcandidate.wall_collider_rid
\t)
\tif collider == null:
\t\treturn
\tcandidate.attachment_collider_rid = candidate.wall_collider_rid
\tcandidate.attachment_collider_transform = collider.global_transform
\tcandidate.attachment_collider_transform_valid = true


func _get_candidate_attachment_collider(collider_rid: RID) -> Node3D:
\tif not collider_rid.is_valid():
\t\treturn null
\tvar instance_id: int = PhysicsServer3D.body_get_object_instance_id(collider_rid)
\tif instance_id == 0:
\t\treturn null
\tvar collider: Object = instance_from_id(instance_id)
\tif (
\t\tcollider == null
\t\tor not is_instance_valid(collider)
\t\tor not (collider is Node3D)
\t):
\t\treturn null
\treturn collider as Node3D


func _collider_allows_traversal_attachment(collider_rid: RID) -> bool:'''
)

replace_once(
    "player/traversal/player_ledge_detector.gd",
    '''\tcandidate.hang_position = get_hang_position(
\t\tgeometry.edge_point,
\t\tgeometry.wall_normal
\t)
\treturn candidate''',
    '''\tcandidate.hang_position = get_hang_position(
\t\tgeometry.edge_point,
\t\tgeometry.wall_normal
\t)
\t_capture_candidate_attachment_transform(candidate)
\treturn candidate'''
)

replace_once(
    "player/traversal/player_mantle.gd",
    '''\tif source_candidate == null:
\t\treturn null

\tvar refreshed_source: PlayerLedgeDetector.LedgeCandidate = source_candidate''',
    '''\tif source_candidate == null:
\t\treturn null
\tif not detector.refresh_candidate_attachment(source_candidate):
\t\treturn null

\tvar refreshed_source: PlayerLedgeDetector.LedgeCandidate = source_candidate'''
)

replace_once(
    "player/traversal/player_mantle.gd",
    '''func update(
\tplayer: CharacterBody3D,
\tdelta: float
) -> bool:
\tif active_candidate == null or phase == Phase.NONE:
\t\treturn false

\tplayer.velocity = Vector3.ZERO''',
    '''func _refresh_active_attachment_route() -> bool:
\tif active_candidate == null or active_candidate.source_candidate == null:
\t\treturn false
\tvar source: PlayerLedgeDetector.LedgeCandidate = active_candidate.source_candidate
\tif not source.attachment_collider_transform_valid:
\t\treturn true
\tvar previous_transform: Transform3D = source.attachment_collider_transform
\tif not detector.refresh_candidate_attachment(source):
\t\treturn false
\tvar current_transform: Transform3D = source.attachment_collider_transform
\tif current_transform.is_equal_approx(previous_transform):
\t\treturn true

\tvar previous_inverse: Transform3D = previous_transform.affine_inverse()
\troute_edge_point = current_transform * (previous_inverse * route_edge_point)
\tmantle_origin_edge_point = (
\t\tcurrent_transform * (previous_inverse * mantle_origin_edge_point)
\t)

\tvar basis_delta: Basis = (
\t\tcurrent_transform.basis * previous_transform.basis.inverse()
\t)
\tmantle_origin_wall_normal = basis_delta * mantle_origin_wall_normal
\tmantle_origin_wall_normal.y = 0.0
\tif mantle_origin_wall_normal.length_squared() <= MOTION_EPSILON_SQUARED:
\t\treturn false
\tmantle_origin_wall_normal = mantle_origin_wall_normal.normalized()

\tactive_candidate.edge_point = source.edge_point
\tactive_candidate.wall_normal = Vector3(
\t\tsource.wall_normal.x,
\t\t0.0,
\t\tsource.wall_normal.z
\t)
\tif active_candidate.wall_normal.length_squared() <= MOTION_EPSILON_SQUARED:
\t\treturn false
\tactive_candidate.wall_normal = active_candidate.wall_normal.normalized()
\tactive_candidate.ledge_axis = source.ledge_direction
\tif active_candidate.ledge_axis.length_squared() <= MOTION_EPSILON_SQUARED:
\t\treturn false
\tactive_candidate.ledge_axis = active_candidate.ledge_axis.normalized()
\tvar horizontal_ledge := Vector3(
\t\tactive_candidate.ledge_axis.x,
\t\t0.0,
\t\tactive_candidate.ledge_axis.z
\t)
\tif horizontal_ledge.length_squared() <= MOTION_EPSILON_SQUARED:
\t\treturn false
\tactive_candidate.traversal_axis = horizontal_ledge.normalized()

\tlift_target_height = (
\t\troute_edge_point.y
\t\t+ get_vertical_edge_clearance()
\t\t- get_bottom_cap_center_offset()
\t)
\tif not is_finite(lift_target_height):
\t\treturn false
\tactive_candidate.target_position = Vector3(
\t\troute_edge_point.x,
\t\tlift_target_height,
\t\troute_edge_point.z
\t)
\treturn true


func update(
\tplayer: CharacterBody3D,
\tdelta: float
) -> bool:
\tif active_candidate == null or phase == Phase.NONE:
\t\treturn false
\tif not _refresh_active_attachment_route():
\t\treturn false

\tplayer.velocity = Vector3.ZERO'''
)

replace_once(
    "player/traversal/player_ledge_controller.gd",
    '''\t\tState.MANTLING:
\t\t\treturn ledge_detector.is_candidate_attachment_stable(ledge_mantle.get_release_candidate())
\treturn true''',
    '''\t\tState.MANTLING:
\t\t\treturn true
\treturn true'''
)

replace_once(
    "player/traversal/player_ledge_controller.gd",
    '''func update(jump_pressed: bool, crouch_pressed: bool, delta: float) -> void:
\tif state != State.NONE and not _active_attachment_is_stable():
\t\t_release_unstable_attachment(delta)
\t\treturn''',
    '''func update(jump_pressed: bool, crouch_pressed: bool, delta: float) -> void:
\tif (
\t\tstate != State.NONE
\t\tand state != State.MANTLING
\t\tand not _active_attachment_is_stable()
\t):
\t\t_release_unstable_attachment(delta)
\t\treturn'''
)

replace_once(
    "player/traversal/player_ledge_controller.gd",
    '''\tfor candidate: PlayerLedgeDetector.LedgeCandidate in candidates:
\t\tif candidate == null:
\t\t\tcontinue
\t\tif not ledge_detector.is_candidate_attachment_stable(candidate):
\t\t\tcontinue
\t\tif traversal_guard.is_mantle_blocked(candidate):''',
    '''\tfor candidate: PlayerLedgeDetector.LedgeCandidate in candidates:
\t\tif candidate == null:
\t\t\tcontinue
\t\tif traversal_guard.is_mantle_blocked(candidate):'''
)

replace_once(
    "gameplay/props/ordinary_prop.gd",
    '''func is_traversal_attachment_stable() -> bool:
\t# Ledge/mantle geometry is sampled in world space. Ordinary props are valid
\t# traversal anchors only while their semantic transform is exact/stable.
\treturn _phase == PHASE_SETTLED''',
    '''func is_traversal_attachment_stable() -> bool:
\t# Long-lived catch/hang/corner attachments require an exact stationary prop.
\t# Mantle is short-lived and tracks its source collider transform separately.
\treturn _phase == PHASE_SETTLED'''
)

replace_once(
    "tests/props/phase_3_5_transition_regressions.gd",
    '''\tawait _prove_wakeable_world_physics(tree, world, player, assert_true)
\tawait _prove_support_invalidation(tree, player, edge_prop, assert_true)''',
    '''\tawait _prove_wakeable_world_physics(tree, world, player, assert_true)
\tawait _prove_ground_mantle_tracks_moving_prop(tree, world, player, assert_true)
\tawait _prove_support_invalidation(tree, player, edge_prop, assert_true)'''
)

replace_once(
    "tests/props/phase_3_5_transition_regressions.gd",
    '''\tpush_prop.queue_free()
\tawait tree.process_frame


func _prove_support_invalidation(''',
    '''\tpush_prop.queue_free()
\tawait tree.process_frame


func _prove_ground_mantle_tracks_moving_prop(
\ttree: SceneTree,
\tworld: Node3D,
\tplayer: CharacterBody3D,
\tassert_true: Callable
) -> void:
\tvar prop: RigidBody3D = OrdinaryPropScene.instantiate() as RigidBody3D
\tworld.add_child(prop)
\tawait tree.process_frame
\tprop.global_position = Vector3(-3.0, 0.3, -2.0)
\tplayer.global_position = Vector3(-3.0, 0.0, -1.44)
\tplayer.rotation.y = 0.0
\tplayer.velocity = Vector3.ZERO
\tvar head: Node3D = player.get_node("Head") as Node3D
\thead.rotation.x = 0.0
\tvar velocity_state: PlayerVelocityState = player.get("velocity_state") as PlayerVelocityState
\tvelocity_state.capture_body_as_controlled(player)
\tawait _settle_physics(tree, 2)

\tassert_true.call(
\t\tbool(prop.call("receive_player_push", Vector3(0.0, 0.0, -0.8))),
\t\t"Ground-mantle fixture promotes its crate into the same moving prop state"
\t)
\tawait _settle_physics(tree)
\tplayer.global_position = Vector3(
\t\tprop.global_position.x,
\t\t0.0,
\t\tprop.global_position.z + 0.56
\t)
\tplayer.velocity = Vector3.ZERO
\tvelocity_state.capture_body_as_controlled(player)

\tInput.action_press("move_forward")
\tInput.action_press("jump")
\tawait _settle_physics(tree)
\tInput.action_release("jump")
\tInput.action_release("move_forward")
\tvar controller: PlayerLedgeController = player.get("ledge_controller") as PlayerLedgeController
\tvar entered_mantle: bool = (
\t\tcontroller != null
\t\tand controller.state == PlayerLedgeController.State.MANTLING
\t)
\tassert_true.call(
\t\tentered_mantle and absf(player.velocity.y) <= 0.05,
\t\t"A grounded jump press against an already-moving prop enters mantle instead of falling through to ballistic jump"
\t)

\tvar moving_start: Vector3 = prop.global_position
\tvar saw_prop_motion: bool = false
\tvar completed_mantle: bool = false
\tfor _frame_index: int in range(120):
\t\tawait _settle_physics(tree)
\t\tif prop.global_position.distance_to(moving_start) > 0.015:
\t\t\tsaw_prop_motion = true
\t\tif (
\t\t\tentered_mantle
\t\t\tand controller.state == PlayerLedgeController.State.NONE
\t\t\tand bool(player.call("is_grounded"))
\t\t):
\t\t\tcompleted_mantle = true
\t\t\tbreak
\tassert_true.call(
\t\tsaw_prop_motion and completed_mantle,
\t\t"Ground mantle keeps the ordinary air-mantle motion while its prop-backed route follows the moving collider to a supported completion"
\t)

\tvar locomotion_start: Vector3 = player.global_position
\tInput.action_press("move_right")
\tawait _settle_physics(tree, 8)
\tInput.action_release("move_right")
\tassert_true.call(
\t\tplayer.global_position.distance_to(locomotion_start) > 0.025,
\t\t"Completed moving-prop mantle returns ordinary locomotion instead of leaving the player stuck on top"
\t)
\tprop.queue_free()
\tawait tree.process_frame
\tawait _settle_physics(tree, 2)


func _prove_support_invalidation('''
)

replace_once(
    "tests/props/phase_3_5_transition_regressions.gd",
    '''\tassert_true.call(
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
\t)''',
    '''\tassert_true.call(
\t\tbool(prop.call("apply_semantic_state", moving_snapshot))
\t\tand not bool(detector.call("is_candidate_attachment_stable", candidate)),
\t\t"Moving ordinary props remain ineligible for stationary catch/hang/corner attachment"
\t)
\tassert_true.call(
\t\tbool(prop.call("apply_semantic_state", settled_snapshot))
\t\tand bool(detector.call("is_candidate_attachment_stable", candidate)),
\t\t"Stationary traversal attachment eligibility returns after the prop is semantically settled again"
\t)'''
)

replace_once(
    "docs/GAME_VISION.md",
    '''Ordinary props are valid ledge/mantle attachment geometry only while semantically settled. Their traversal candidates are world-space snapshots, so a moving or settling prop cannot start a new catch/hang/corner/mantle attachment, and an active traversal tied to that prop cancels to ordinary airborne motion if the prop becomes dynamic. Traversal may use that collider again only after it returns to the exact settled state.''',
    '''Catch, hang, and corner attachment to an ordinary prop require that prop to be semantically settled. Mantle keeps the same accepted motion whether entered from grounded contact or airborne contact, including when a light prop has just been shoved into motion. Because ledge candidates begin as world-space samples, a prop-backed mantle binds the sampled edge/route to the exact collider transform that produced it and updates that geometry as the rigid body translates, instead of converting the request into a jump or completing against a stale prop position. If the tracked collider disappears or ceases to be the same physical attachment, the mantle releases to ordinary airborne control.'''
)

replace_once(
    "docs/DEVELOPMENT_PLAN.md",
    '''5. **Dynamic-prop traversal ownership.** Ledge/mantle candidates are world-space geometry snapshots, so an ordinary prop may be a traversal attachment only while its semantic transform is settled/stable. Moving/settling props are rejected for new catch/hang/corner/mantle entry, and an active traversal depending on a prop cancels to airborne motion if that prop becomes dynamic. The collider becomes eligible again only after semantic settle.''',
    '''5. **Dynamic-prop traversal ownership.** Catch/hang/corner keep requiring an exact settled prop, but mantle preserves the already-accepted traversal motion for both grounded and airborne contact. A prop-backed mantle records the collider transform that produced its world-space ledge sample and keeps the mantle edge/route bound to that same collider while it translates. A light crate that was just shoved therefore still mantles through the normal `PlayerMantle` path instead of falling through to jump or finishing against stale geometry; loss of the tracked collider releases cleanly to air.'''
)

replace_once(
    "docs/DEVELOPMENT_PLAN.md",
    '''**Done when:** world/prop blockers remain solid during release placement; F and R enter world physics with the box top already up and preserve that orientation through ordinary settle; an initially player-overlapping throw retains its intended impulse and restores normal player collision after separation; picking up the exact supporting/traversal prop ends that dependency immediately; moving ordinary props cannot provide stale mantle/ledge attachments and active traversal falls cleanly if its prop becomes dynamic; settled props remain exactly stable without drifting but are clearly easier to move by deliberate player pressure and react more strongly to another prop impact; pre-tilted unsupported contact can still use the smooth yaw-preserving support-reseated correction; no-gap/no-free-tumble behavior remains; and the authoritative all-tests barrier plus Windows x64 user acceptance pass.''',
    '''**Done when:** world/prop blockers remain solid during release placement; F and R enter world physics with the box top already up and preserve that orientation through ordinary settle; an initially player-overlapping throw retains its intended impulse and restores normal player collision after separation; picking up the exact supporting/traversal prop ends that dependency immediately; grounded contact with a recently shoved prop enters the same mantle motion as airborne contact, tracks that collider through completion, and returns ordinary locomotion instead of becoming a jump or stuck state; catch/hang/corner do not retain moving-prop snapshots; settled props remain exactly stable without drifting but are clearly easier to move by deliberate player pressure and react more strongly to another prop impact; pre-tilted unsupported contact can still use the smooth yaw-preserving support-reseated correction; no-gap/no-free-tumble behavior remains; and the authoritative all-tests barrier plus Windows x64 user acceptance pass.'''
)

replace_once(
    "docs/DEVELOPMENT_PLAN.md",
    '''**Automated:** required — the dedicated Props suite must exercise upright F/R carry→world orientation, shape-aware world-blocked placement, overlapping-player throw impulse preservation, player-only overlap-filter lifetime, exact support RID invalidation, catch/hang/corner/mantle collider invalidation, moving-prop traversal ineligibility/active-mantle cancellation, lighter prop tuning, exact settled stability, prop-on-prop impact promotion/translation, production-path player shove, multi-frame smooth pre-tilted narrow-support alignment, yaw/support re-seating, existing prop behavior, and the unchanged movement regression suite through `tests/run_all_tests.gd`.''',
    '''**Automated:** required — the dedicated Props suite must exercise upright F/R carry→world orientation, shape-aware world-blocked placement, overlapping-player throw impulse preservation, player-only overlap-filter lifetime, exact support RID invalidation, catch/hang/corner/mantle collider invalidation, production-path grounded mantle entry on an already-moving prop, tracked moving-collider mantle completion plus post-mantle locomotion, stationary-only catch/hang/corner eligibility, lighter prop tuning, exact settled stability, prop-on-prop impact promotion/translation, production-path player shove, multi-frame smooth pre-tilted narrow-support alignment, yaw/support re-seating, existing prop behavior, and the unchanged movement regression suite through `tests/run_all_tests.gd`.'''
)

replace_once(
    "docs/DEVELOPMENT_PLAN.md",
    '''**Manual:** pending — validator: **Windows x64 user/playtester**. Launch **Development Launch → Prop Lab**. Confirm F throw remains materially stronger than R release and both leave the hand with the box top already up; after either action the box must not roll onto a different face when translation stops. Walk laterally into a resting crate and confirm the lighter crate yields clearly without tumbling; throw one crate into another and confirm the struck crate reacts more strongly than before. Run into a crate so it starts moving and immediately attempt mantle: moving/settling props must not become stale traversal anchors, and if an attached prop is disturbed during traversal the player must drop back to ordinary airborne control rather than ending stuck on it. Resting edge/stack props must remain exactly still until explicitly disturbed. Also retain cramped player-overlap release, pickup/HUD, movement/look/crouch/jump, lower-support fall, hard-edged rendering, wall/prop collision, pre-tilted support correction, no hover gap, and restored post-overlap player collision.''',
    '''**Manual:** pending — validator: **Windows x64 user/playtester**. Launch **Development Launch → Prop Lab**. Confirm F throw remains materially stronger than R release and both leave the hand with the box top already up; after either action the box must not roll onto a different face when translation stops. Walk laterally into a resting crate and confirm the lighter crate yields clearly without tumbling; throw one crate into another and confirm the struck crate reacts more strongly than before. For mantle, first mantle a normal static ledge from air, then run into a crate so it starts moving and press mantle from the ground: the grounded case must use the same smooth lift/forward mantle motion, not a jump, must follow the crate rather than completing against its old position, and must return normal movement immediately on top. Resting edge/stack props must remain exactly still until explicitly disturbed. Also retain cramped player-overlap release, pickup/HUD, movement/look/crouch/jump, lower-support fall, hard-edged rendering, wall/prop collision, pre-tilted support correction, no hover gap, and restored post-overlap player collision.'''
)

replace_once(
    "docs/TESTING.md",
    '''standing support stores and invalidates the exact prop collider RID; catch/hang/corner/mantle state is canceled only when its referenced collider is invalidated; ordinary props are accepted as traversal geometry only while semantically settled and an active mantle cancels if that attachment becomes dynamic; and a pre-tilted moving crate resting on a narrow support enters a multi-frame support-reseated top-up alignment before returning to exact stable settled state.''',
    '''standing support stores and invalidates the exact prop collider RID; catch/hang/corner/mantle state is canceled only when its referenced collider leaves world participation; catch/hang/corner remain stationary-prop attachments, while a production grounded mantle against an already-moving crate enters the same `PlayerMantle` path as air contact, tracks the source collider transform through completion, and proves ordinary locomotion resumes instead of leaving the player stuck on top; and a pre-tilted moving crate resting on a narrow support enters a multi-frame support-reseated top-up alignment before returning to exact stable settled state.'''
)

print("STAGED_PHASE35_MOVING_PROP_MANTLE_TRACKING")
