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

\t# Reproduce the player-facing sequence through production ownership: push the
\t# lightweight crate with ordinary locomotion, keep holding forward, then
\t# request mantle. The prop can translate out of direct contact in that same
\t# physics transaction, but the exact collider-backed candidate must remain the
\t# same mantle opportunity instead of degrading to a ballistic jump.
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
\t\tproduction_shove_observed and bool(player.call("is_grounded")),
\t\t"Ground-mantle fixture reaches the moving-crate state through real grounded player contact"
\t)

\tInput.action_press("jump")
\tawait _settle_physics(tree)
\tInput.action_release("jump")
\tvar controller: PlayerLedgeController = player.get("ledge_controller") as PlayerLedgeController
\tvar entered_mantle: bool = (
\t\tproduction_shove_observed
\t\tand controller != null
\t\tand controller.state == PlayerLedgeController.State.MANTLING
\t)
\tassert_true.call(
\t\tentered_mantle and absf(player.velocity.y) <= 0.05,
\t\t"Grounded mantle while pushing a moving prop enters the ordinary PlayerMantle path instead of ballistic jump"
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
\t\tsaw_prop_motion_during_mantle
\t\tor prop.call("get_semantic_phase") == OrdinaryProp.PHASE_SETTLED,
\t\t"Prop-backed mantle remains coherent while the shoved source prop moves or finishes settling"
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
