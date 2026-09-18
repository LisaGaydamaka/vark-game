from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one anchor, found {count}")
    p.write_text(text.replace(old, new, 1))


# Preserve the accepted pre-regression entry path exactly. Tracking begins only
# after PlayerMantle owns the traversal, so start feel/policy stays unchanged.
replace_once(
    "player/traversal/player_mantle.gd",
    '''\tif source_candidate == null:
\t\treturn null
\tif not detector.refresh_candidate_attachment(source_candidate):
\t\treturn null

\tvar refreshed_source: PlayerLedgeDetector.LedgeCandidate = source_candidate''',
    '''\tif source_candidate == null:
\t\treturn null

\tvar refreshed_source: PlayerLedgeDetector.LedgeCandidate = source_candidate'''
)

replace_once(
    "player/traversal/player_ledge_controller.gd",
    '''\tfor candidate: PlayerLedgeDetector.LedgeCandidate in candidates:
\t\tif candidate == null:
\t\t\tcontinue
\t\t# Discovery occurs before locomotion resolves the contact. A lightweight
\t\t# prop can move during that same transaction, so refresh its exact sampled
\t\t# geometry before comparing the candidate with the post-move collision.
\t\tif not ledge_detector.refresh_candidate_attachment(candidate):
\t\t\tcontinue
\t\tif traversal_guard.is_mantle_blocked(candidate):''',
    '''\tfor candidate: PlayerLedgeDetector.LedgeCandidate in candidates:
\t\tif candidate == null:
\t\t\tcontinue
\t\tif traversal_guard.is_mantle_blocked(candidate):'''
)

# The last gameplay commit also added a second moving-prop rejection inside the
# shared free-mantle starter. Removing only the outer candidate filter is not
# enough: this inner guard still turns a valid grounded mantle request into the
# caller's ballistic-jump fallback. Restore the pre-regression shared starter so
# ground and air contact mantles both use find_air_candidate() -> try_start().
replace_once(
    "player/traversal/player_ledge_controller.gd",
    '''func _try_start_free_mantle(
\tcandidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
\tif not ledge_detector.is_candidate_attachment_stable(candidate):
\t\treturn false
\tvar mantle_candidate: PlayerMantle.MantleCandidate = (''',
    '''func _try_start_free_mantle(
\tcandidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
\tvar mantle_candidate: PlayerMantle.MantleCandidate = ('''
)

path = Path("tests/props/phase_3_5_transition_regressions.gd")
text = path.read_text()
start_marker = "func _prove_ground_mantle_tracks_moving_prop(\n"
end_marker = "\n\nfunc _prove_support_invalidation("
start = text.find(start_marker)
if start < 0:
    raise SystemExit("ground mantle regression start marker not found")
end = text.find(end_marker, start)
if end < 0:
    raise SystemExit("ground mantle regression end marker not found")
replacement = '''func _prove_ground_mantle_tracks_moving_prop(
\ttree: SceneTree,
\tworld: Node3D,
\tplayer: CharacterBody3D,
\tassert_true: Callable
) -> void:
\tvar prop: RigidBody3D = OrdinaryPropScene.instantiate() as RigidBody3D
\tworld.add_child(prop)
\tawait tree.process_frame
\tprop.global_position = Vector3(-3.0, 0.3, -2.0)
\tplayer.global_position = Vector3(-3.0, 0.0, -1.40)
\tplayer.rotation.y = 0.0
\tplayer.velocity = Vector3.ZERO
\tvar head: Node3D = player.get_node("Head") as Node3D
\thead.rotation.x = 0.0
\tvar velocity_state: PlayerVelocityState = player.get("velocity_state") as PlayerVelocityState
\tvelocity_state.capture_body_as_controlled(player)
\tawait _settle_physics(tree, 2)

\t# This is the accepted ground-mantle entry: forward + jump at the ledge.
\t# The correction must not replace it with a ballistic jump or a new special
\t# ground traversal. It must enter the same PlayerMantle state as before.
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
\t\t"Grounded prop mantle retains the accepted PlayerMantle entry instead of becoming a ballistic jump"
\t)

\t# Reproduce the original failure only after the accepted mantle owns motion:
\t# the source crate becomes dynamic beneath the player. The mantle path should
\t# follow that collider rather than completing against its stale sampled pose.
\tvar moving_start: Vector3 = prop.global_position
\tvar disturbed_during_mantle: bool = false
\tif entered_mantle:
\t\tdisturbed_during_mantle = bool(prop.call(
\t\t\t"receive_player_push",
\t\t\tVector3(0.0, 0.0, -1.5)
\t\t))
\tassert_true.call(
\t\tdisturbed_during_mantle,
\t\t"Active ground-mantle fixture can promote its source crate into moving world physics"
\t)

\tvar saw_prop_motion: bool = false
\tvar completed_mantle: bool = false
\tfor _frame_index: int in range(120):
\t\tawait _settle_physics(tree)
\t\tif prop.global_position.distance_to(moving_start) > 0.01:
\t\t\tsaw_prop_motion = true
\t\tif (
\t\t\tentered_mantle
\t\t\tand controller.state == PlayerLedgeController.State.NONE
\t\t\tand bool(player.call("is_grounded"))
\t\t):
\t\t\tcompleted_mantle = true
\t\t\tbreak
\tassert_true.call(
\t\tsaw_prop_motion,
\t\t"The source crate physically moves while the ordinary mantle is active"
\t)
\tassert_true.call(
\t\tcompleted_mantle,
\t\t"Ground mantle tracks the moving source prop through the ordinary lift/forward path and completes supported"
\t)

\tvar locomotion_start: Vector3 = player.global_position
\tInput.action_press("move_right")
\tawait _settle_physics(tree, 8)
\tInput.action_release("move_right")
\tassert_true.call(
\t\tcompleted_mantle
\t\tand player.global_position.distance_to(locomotion_start) > 0.025,
\t\t"Completed moving-prop mantle returns ordinary locomotion instead of leaving the player stuck on top"
\t)
\tprop.queue_free()
\tawait tree.process_frame
\tawait _settle_physics(tree, 2)
'''
path.write_text(text[:start] + replacement + text[end:])

print("RESTORED_ACCEPTED_GROUND_MANTLE_ENTRY_AND_TARGETED_ACTIVE_TRACKING")
