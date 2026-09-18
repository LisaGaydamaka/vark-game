from pathlib import Path

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
\tplayer.global_position = Vector3(-3.0, 0.0, -0.95)
\tplayer.rotation.y = 0.0
\tplayer.velocity = Vector3.ZERO
\tvar head: Node3D = player.get_node("Head") as Node3D
\thead.rotation.x = 0.0
\tvar velocity_state: PlayerVelocityState = player.get("velocity_state") as PlayerVelocityState
\tvelocity_state.capture_body_as_controlled(player)
\tawait _settle_physics(tree, 2)

\t# Reproduce the player's report literally: run into the light crate until the
\t# production contact solver shoves it, keep holding forward, then press jump.
\tvar prop_start: Vector3 = prop.global_position
\tvar production_shove_observed: bool = false
\tInput.action_press("move_forward")
\tfor _frame_index: int in range(45):
\t\tawait _settle_physics(tree)
\t\tif (
\t\t\tprop.call("get_motion_kind") == OrdinaryProp.MOTION_DISTURBED
\t\t\tand prop.global_position.distance_to(prop_start) > 0.005
\t\t):
\t\t\tproduction_shove_observed = true
\t\t\tbreak
\tassert_true.call(
\t\tproduction_shove_observed,
\t\t"Ground-mantle fixture reaches the moving-crate state through real player contact"
\t)

\t# Diagnostic-only visibility for the gated candidate. This test helper is
\t# removed by the publishing commit; production code does not depend on it.
\tvar support: PlayerSupport = player.get("support") as PlayerSupport
\tvar detector: PlayerLedgeDetector = player.get("ledge_detector") as PlayerLedgeDetector
\tvar debug_forward: Vector3 = -head.global_transform.basis.z
\tvar debug_candidates: Array[PlayerLedgeDetector.LedgeCandidate] = detector.find_candidates(
\t\tplayer,
\t\tsupport,
\t\tVector3(0.0, 0.0, -1.0),
\t\tdebug_forward
\t)
\tprint(
\t\t"MANTLE_DEBUG pre_jump grounded=", bool(player.call("is_grounded")),
\t\t" support=", support.has_support,
\t\t" candidates=", debug_candidates.size(),
\t\t" player_pos=", player.global_position,
\t\t" prop_pos=", prop.global_position,
\t\t" prop_phase=", prop.call("get_semantic_phase"),
\t\t" velocity=", player.velocity
\t)
\tif not debug_candidates.is_empty():
\t\tvar debug_candidate: PlayerLedgeDetector.LedgeCandidate = debug_candidates[0]
\t\tprint(
\t\t\t"MANTLE_DEBUG candidate wall_rid=", debug_candidate.wall_collider_rid,
\t\t\t" top_rid=", debug_candidate.top_collider_rid,
\t\t\t" stable=", detector.is_candidate_attachment_stable(debug_candidate),
\t\t\t" edge=", debug_candidate.edge_point,
\t\t\t" wall_normal=", debug_candidate.wall_normal
\t\t)

\tInput.action_press("jump")
\tawait _settle_physics(tree)
\tInput.action_release("jump")
\tvar controller: PlayerLedgeController = player.get("ledge_controller") as PlayerLedgeController
\tprint(
\t\t"MANTLE_DEBUG post_jump state=", controller.state,
\t\t" grounded=", bool(player.call("is_grounded")),
\t\t" detector_candidates=", detector.get_candidates().size(),
\t\t" velocity=", player.velocity,
\t\t" player_pos=", player.global_position,
\t\t" prop_pos=", prop.global_position
\t)
\tvar entered_mantle: bool = (
\t\tproduction_shove_observed
\t\tand controller != null
\t\tand controller.state == PlayerLedgeController.State.MANTLING
\t)
\tassert_true.call(
\t\tentered_mantle and absf(player.velocity.y) <= 0.05,
\t\t"Grounded mantle while pushing a moving prop retains the accepted PlayerMantle entry instead of ballistic jump"
\t)
\tInput.action_release("move_forward")

\tvar moving_start: Vector3 = prop.global_position
\tvar saw_prop_motion_during_mantle: bool = false
\tvar completed_mantle: bool = false
\tfor _frame_index: int in range(120):
\t\tawait _settle_physics(tree)
\t\tif prop.global_position.distance_to(moving_start) > 0.01:
\t\t\tsaw_prop_motion_during_mantle = true
\t\tif (
\t\t\tentered_mantle
\t\t\tand controller.state == PlayerLedgeController.State.NONE
\t\t\tand bool(player.call("is_grounded"))
\t\t):
\t\t\tcompleted_mantle = true
\t\t\tbreak
\tassert_true.call(
\t\tcompleted_mantle,
\t\t"Ground mantle completes through the ordinary PlayerMantle lift/forward path on the moving prop"
\t)
\tassert_true.call(
\t\tsaw_prop_motion_during_mantle or prop.call("get_semantic_phase") == OrdinaryProp.PHASE_SETTLED,
\t\t"Prop-backed mantle stays coherent while the shoved source prop moves or finishes settling"
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
print("STAGED_REAL_PUSH_THEN_GROUND_MANTLE_REGRESSION")
