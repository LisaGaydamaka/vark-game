from pathlib import Path

def replace_once(text: str, old: str, new: str, label: str) -> str:
    if text.count(old) != 1:
        raise SystemExit(f"{label}: expected 1 match, got {text.count(old)}")
    return text.replace(old, new, 1)

prop_path = Path("gameplay/props/ordinary_prop.gd")
prop = prop_path.read_text(encoding="utf-8")

for line in (
    "var _player_escape_collision_suppressed: bool = false\n",
    "var _player_escape_launch_velocity: Vector3 = Vector3.ZERO\n",
    "var _player_escape_step_velocity: Vector3 = Vector3.ZERO\n",
):
    prop = replace_once(prop, line, "", line.strip())

prop = replace_once(
    prop,
    "func _physics_process(delta: float) -> void:\n"
    "\tif _player_escape_collision_suppressed:\n"
    "\t\t_advance_player_escape(delta)\n"
    "\t\treturn\n",
    "func _physics_process(_delta: float) -> void:\n",
    "physics escape branch",
)

release_start = prop.index("func release_from_carry(")
tail_start = prop.index("\t_clear_temporary_player_collision_exception()\n", release_start)
tail_end = prop.index("\n\nfunc capture_semantic_state()", tail_start)
new_tail = '''\t_clear_temporary_player_collision_exception()
\t_holder = null
\tglobal_transform = release_transform
\tvar overlaps_releasing_player: bool = (
\t\treleasing_player != null
\t\tand is_instance_valid(releasing_player)
\t\tand _shape_overlaps_body_at_transform(release_transform, releasing_player)
\t)
\tif overlaps_releasing_player:
\t\t# Install the pairwise exception while the carried prop is still frozen and
\t\t# absent from collision participation, before Jolt can create this contact.
\t\tadd_collision_exception_with(releasing_player)
\t\treleasing_player.add_collision_exception_with(self)
\t\t_temporary_player_collision_exception = releasing_player
\t_set_world_presentation_enabled(true)
\t# Throw/release is immediately real rigid motion. World/prop collision stays
\t# active from the first tick; only the overlapping releasing player is ignored.
\t_begin_motion(motion_kind, initial_velocity)
\treturn true'''
prop = prop[:tail_start] + new_tail + prop[tail_end:]

escape_start = prop.index("func _advance_player_escape(")
escape_end = prop.index("func _update_temporary_player_collision_exception()", escape_start)
prop = prop[:escape_start] + prop[escape_end:]

prop = replace_once(
    prop,
    "func _update_temporary_player_collision_exception() -> void:\n"
    "\tif _player_escape_collision_suppressed:\n"
    "\t\treturn\n",
    "func _update_temporary_player_collision_exception() -> void:\n",
    "temporary exception update",
)
prop = replace_once(
    prop,
    "\t_temporary_player_collision_exception = null\n"
    "\tif _player_escape_collision_suppressed:\n"
    "\t\tcollision_layer = _ordinary_collision_layer\n"
    "\t\tcollision_mask = _ordinary_collision_mask\n"
    "\t\t_player_escape_collision_suppressed = false\n",
    "\t_temporary_player_collision_exception = null\n",
    "temporary exception cleanup",
)
prop_path.write_text(prop, encoding="utf-8")

test_path = Path("tests/props/phase_3_5_transition_regressions.gd")
tests = test_path.read_text(encoding="utf-8")
tests = replace_once(
    tests,
    '\t\tand prop.linear_velocity.length() > 4.0\n'
    '\t\tand bool(prop.call("has_temporary_player_collision_exception"))\n',
    '\t\tand prop.linear_velocity.length() > 4.0\n'
    '\t\tand not prop.freeze\n'
    '\t\tand not prop.sleeping\n'
    '\t\tand prop.collision_layer == 1\n'
    '\t\tand prop.collision_mask == 1\n'
    '\t\tand bool(prop.call("has_temporary_player_collision_exception"))\n',
    "immediate rigid throw assertions",
)
tests = replace_once(
    tests,
    '"F throw keeps its impulse through an initial player overlap"',
    '"F throw is immediately a live world-colliding rigid body while only the overlapping player pair is ignored"',
    "throw assertion label",
)
test_path.write_text(tests, encoding="utf-8")

plan_path = Path("docs/DEVELOPMENT_PLAN.md")
plan = plan_path.read_text(encoding="utf-8")
p0 = plan.index("1. **Release/throw collision transaction.**")
p1 = plan.index("\n", p0)
plan_line = (
    "1. **Release/throw collision transaction.** Release placement uses the prop's real collision volume "
    "against world/other-prop blockers while deliberately allowing the chosen pose to overlap the releasing "
    "player's capsule when space is cramped. Once Junk leaves the carried slot it is immediately a live rigid "
    "body with ordinary world/prop collision. If the release pose overlaps the player, establish only a temporary "
    "prop↔player collision exception **before** restoring collision participation, keep real rigid physics active "
    "from the first moving tick, and remove that pairwise exception as soon as the actual collision volumes separate. "
    "Do not freeze/kinematically translate the prop, zero its global collision layers, use a timer, or use an arbitrary "
    "travel-distance escape mode."
)
plan = plan[:p0] + plan_line + plan[p1:]
plan_path.write_text(plan, encoding="utf-8")

vision_path = Path("docs/GAME_VISION.md")
vision = vision_path.read_text(encoding="utf-8")
v0 = vision.index("Release placement uses the prop's real collision volume.")
v1 = vision.index("\n\nA prop that leaves world participation", v0)
vision_paragraph = (
    "Release placement uses the prop's real collision volume. World geometry and other physical objects remain solid "
    "blockers, but the placement search deliberately ignores the releasing player's capsule so cramped spaces may choose "
    "a world-clear pose that initially overlaps the player. The prop is never given a fake kinematic escape phase: as soon "
    "as it leaves carried Junk it is an ordinary live rigid body with normal world/prop collision and the full throw or "
    "gentle-release velocity. If the chosen pose overlaps the player, only that exact prop↔player collision pair is "
    "temporarily excepted, and the exception is installed before the prop re-enters collision participation so the physics "
    "backend never creates an initial player contact that can cancel the launch. The exception ends from actual geometric "
    "separation of the two collision volumes, after which player collision is ordinary again. No timer, arbitrary "
    "travel-distance expiry, global collision-layer suppression, manual escape translation, or saved escape state is part "
    "of this contract."
)
vision = vision[:v0] + vision_paragraph + vision[v1:]
vision_path.write_text(vision, encoding="utf-8")
