from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, got {count}")
    return text.replace(old, new, 1)


# Give physics categories separate vocabulary so an overlapping released prop can
# ignore the player without also dropping world/prop collision.
project_path = Path("project.godot")
project = project_path.read_text(encoding="utf-8")
project = replace_once(
    project,
    "\n[physics]\n",
    "\n[layer_names]\n\n"
    '3d_physics/layer_1="world"\n'
    '3d_physics/layer_2="player"\n'
    '3d_physics/layer_3="ordinary_prop"\n'
    '3d_physics/layer_4="ordinary_prop_player_overlap"\n\n'
    "[physics]\n",
    "project collision-layer names",
)
project_path.write_text(project, encoding="utf-8")

player_scene_path = Path("player/Player.tscn")
player_scene = player_scene_path.read_text(encoding="utf-8")
player_scene = replace_once(
    player_scene,
    '[node name="Player" type="CharacterBody3D" unique_id=911918640 groups=["vark_player"]]\n'
    'script = ExtResource("1_ulp21")\n',
    '[node name="Player" type="CharacterBody3D" unique_id=911918640 groups=["vark_player"]]\n'
    'collision_layer = 2\n'
    'collision_mask = 5\n'
    'script = ExtResource("1_ulp21")\n',
    "player collision channels",
)
player_scene_path.write_text(player_scene, encoding="utf-8")

prop_scene_path = Path("gameplay/props/OrdinaryProp.tscn")
prop_scene = prop_scene_path.read_text(encoding="utf-8")
prop_scene = replace_once(
    prop_scene,
    '[node name="OrdinaryProp" type="RigidBody3D"]\n'
    'mass = 1.5\n',
    '[node name="OrdinaryProp" type="RigidBody3D"]\n'
    'collision_layer = 4\n'
    'collision_mask = 15\n'
    'mass = 1.5\n',
    "ordinary prop collision channels",
)
prop_scene_path.write_text(prop_scene, encoding="utf-8")

door_scene_path = Path("gameplay/doors/OrdinaryDoor.tscn")
door_scene = door_scene_path.read_text(encoding="utf-8")
door_scene = replace_once(
    door_scene,
    '[node name="OrdinaryDoor" type="AnimatableBody3D"]\n'
    'script = ExtResource("1_door")\n',
    '[node name="OrdinaryDoor" type="AnimatableBody3D"]\n'
    'collision_layer = 1\n'
    'collision_mask = 15\n'
    'script = ExtResource("1_door")\n',
    "door obstacle-query collision channels",
)
door_scene_path.write_text(door_scene, encoding="utf-8")

prop_path = Path("gameplay/props/ordinary_prop.gd")
prop = prop_path.read_text(encoding="utf-8")

prop = replace_once(
    prop,
    'const IMPACT_SOUND_KIND: StringName = &"prop.impact"\n',
    'const IMPACT_SOUND_KIND: StringName = &"prop.impact"\n\n'
    '# Dedicated physics categories let an overlapping released prop ignore the\n'
    '# player without disabling collision with the world or other props.\n'
    'const COLLISION_LAYER_WORLD: int = 1 << 0\n'
    'const COLLISION_LAYER_PLAYER: int = 1 << 1\n'
    'const COLLISION_LAYER_ORDINARY_PROP: int = 1 << 2\n'
    'const COLLISION_LAYER_PROP_IGNORING_PLAYER: int = 1 << 3\n',
    "prop collision constants",
)

old_vars = '''var _temporary_player_collision_exception: PhysicsBody3D = null
var _player_escape_collision_suppressed: bool = false
var _player_escape_launch_velocity: Vector3 = Vector3.ZERO
var _player_escape_step_velocity: Vector3 = Vector3.ZERO
'''
prop = replace_once(
    prop,
    old_vars,
    'var _temporarily_ignored_player: PhysicsBody3D = null\n',
    "player-overlap transient variables",
)

prop = replace_once(
    prop,
    '''func _physics_process(delta: float) -> void:
\tif _player_escape_collision_suppressed:
\t\t_advance_player_escape(delta)
\t\treturn
\tmatch _phase:
''',
    '''func _physics_process(_delta: float) -> void:
\tmatch _phase:
''',
    "remove kinematic escape branch",
)
prop = prop.replace(
    "\t_update_temporary_player_collision_exception()\n",
    "\t_update_temporary_player_collision_ignore()\n",
)

prop = replace_once(
    prop,
    '''func has_temporary_player_collision_exception() -> bool:
\treturn (
\t\t_temporary_player_collision_exception != null
\t\tand is_instance_valid(_temporary_player_collision_exception)
\t)
''',
    '''func is_temporarily_ignoring_player_collision() -> bool:
\treturn (
\t\t_temporarily_ignored_player != null
\t\tand is_instance_valid(_temporarily_ignored_player)
\t)
''',
    "player-ignore query",
)

prop = prop.replace(
    "_clear_temporary_player_collision_exception()",
    "_clear_temporary_player_collision_ignore()",
)

release_start = prop.index("func release_from_carry(")
release_end = prop.index("\n\nfunc capture_semantic_state()", release_start)
new_release = '''func release_from_carry(
\tmotion_kind: StringName,
\trelease_transform: Transform3D,
\tinitial_velocity: Vector3,
\treleasing_player: PhysicsBody3D = null
) -> bool:
\tif _phase != PHASE_CARRIED_JUNK:
\t\treturn false
\tif motion_kind != MOTION_RELEASED and motion_kind != MOTION_THROWN:
\t\treturn false
\tif not _is_finite_transform(release_transform) or not _is_finite_vector(initial_velocity):
\t\treturn false
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
\t# F and R differ only by the supplied launch velocity/motion kind. Once the
\t# prop leaves carried Junk it is immediately a real rigid body; no manual
\t# translation or frozen escape phase can dilute the throw.
\t_begin_motion(motion_kind, initial_velocity)
\treturn true'''
prop = prop[:release_start] + new_release + prop[release_end:]

escape_start = prop.index("func _advance_player_escape(")
escape_end = prop.index("func _shape_overlaps_body_at_transform(", escape_start)
new_filter_helpers = '''func _begin_temporary_player_collision_ignore(player: PhysicsBody3D) -> void:
\t_temporarily_ignored_player = player
\t# Jolt evaluates body pairs from both objects' layers/masks. Move only this
\t# prop onto a channel the Player does not scan, while retaining world/prop
\t# categories in its mask. This suppresses exactly the player relationship
\t# without disabling real rigid-body collision with the environment.
\tcollision_layer = COLLISION_LAYER_PROP_IGNORING_PLAYER
\tcollision_mask = (
\t\t(_ordinary_collision_mask | COLLISION_LAYER_WORLD | COLLISION_LAYER_ORDINARY_PROP | COLLISION_LAYER_PROP_IGNORING_PLAYER)
\t\t& ~COLLISION_LAYER_PLAYER
\t)


func _update_temporary_player_collision_ignore() -> void:
\tif _temporarily_ignored_player == null:
\t\treturn
\tif not is_instance_valid(_temporarily_ignored_player):
\t\t_clear_temporary_player_collision_ignore()
\t\treturn
\tif _shape_overlaps_body_at_transform(global_transform, _temporarily_ignored_player):
\t\treturn
\t_clear_temporary_player_collision_ignore()


func _clear_temporary_player_collision_ignore() -> void:
\t_temporarily_ignored_player = null
\tcollision_layer = _ordinary_collision_layer
\tcollision_mask = _ordinary_collision_mask


'''
prop = prop[:escape_start] + new_filter_helpers + prop[escape_end:]

prop_path.write_text(prop, encoding="utf-8")

# Protect the collision-channel contract and true rigid throw behavior.
test_path = Path("tests/props/phase_3_5_transition_regressions.gd")
tests = test_path.read_text(encoding="utf-8")
tests = replace_once(
    tests,
    '''\tassert_true.call(
\t\tthrown
\t\tand prop.call("get_motion_kind") == OrdinaryProp.MOTION_THROWN
\t\tand prop.linear_velocity.length() > 4.0
\t\tand bool(prop.call("has_temporary_player_collision_exception"))
\t\tand player in prop.get_collision_exceptions()
\t\tand prop in player.get_collision_exceptions(),
\t\t"F throw keeps its impulse through an initial player overlap"
\t)
''',
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
''',
    "overlap throw immediate assertions",
)
tests = replace_once(
    tests,
    '''\tvar cleared: bool = await _wait_for_player_exception_clear(tree, prop, player, 40)
\tassert_true.call(
\t\tcleared and not bool(prop.call("has_temporary_player_collision_exception"))
\t\tand not (player in prop.get_collision_exceptions())
\t\tand not (prop in player.get_collision_exceptions())
\t\tand prop.collision_layer == 1 and prop.collision_mask == 1
\t\tand not prop.freeze and prop.linear_velocity.length() > 2.0,
\t\t"Temporary prop-player collision exclusion ends after geometric separation"
\t)
''',
    '''\tvar cleared: bool = await _wait_for_player_ignore_clear(tree, prop, player, 40)
\tassert_true.call(
\t\tcleared and not bool(prop.call("is_temporarily_ignoring_player_collision"))
\t\tand prop.collision_layer == OrdinaryProp.COLLISION_LAYER_ORDINARY_PROP
\t\tand prop.collision_mask == 15
\t\tand not prop.freeze and prop.linear_velocity.length() > 2.0,
\t\t"Temporary player-only collision filtering ends after geometric separation and restores ordinary prop collision"
\t)
''',
    "overlap clear assertions",
)
tests = replace_once(
    tests,
    '''func _wait_for_player_exception_clear(tree: SceneTree, prop: RigidBody3D, player: CharacterBody3D, max_frames: int) -> bool:
\tfor _frame_index: int in max_frames:
\t\tif (
\t\t\tnot bool(prop.call("has_temporary_player_collision_exception"))
\t\t\tand not (player in prop.get_collision_exceptions())
\t\t\tand not (prop in player.get_collision_exceptions())
\t\t\tand prop.collision_layer == 1
\t\t\tand prop.collision_mask == 1
\t\t\tand not prop.freeze
\t\t):
\t\t\treturn true
\t\tawait tree.physics_frame
\t\tawait tree.process_frame
\treturn false
''',
    '''func _wait_for_player_ignore_clear(tree: SceneTree, prop: RigidBody3D, player: CharacterBody3D, max_frames: int) -> bool:
\tfor _frame_index: int in max_frames:
\t\tif (
\t\t\tnot bool(prop.call("is_temporarily_ignoring_player_collision"))
\t\t\tand prop.collision_layer == OrdinaryProp.COLLISION_LAYER_ORDINARY_PROP
\t\t\tand prop.collision_mask == 15
\t\t\tand not prop.freeze
\t\t\tand not bool(prop.call("_shape_overlaps_body_at_transform", prop.global_transform, player))
\t\t):
\t\t\treturn true
\t\tawait tree.physics_frame
\t\tawait tree.process_frame
\treturn false
''',
    "player-ignore wait helper",
)
# The player must scan world + ordinary props, but intentionally not the transient
# overlap-prop channel.
tests = replace_once(
    tests,
    '''\tif world == null or player == null:
\t\treturn
''',
    '''\tif world == null or player == null:
\t\treturn
\tassert_true.call(
\t\tplayer.collision_layer == OrdinaryProp.COLLISION_LAYER_PLAYER
\t\tand (player.collision_mask & OrdinaryProp.COLLISION_LAYER_WORLD) != 0
\t\tand (player.collision_mask & OrdinaryProp.COLLISION_LAYER_ORDINARY_PROP) != 0
\t\tand (player.collision_mask & OrdinaryProp.COLLISION_LAYER_PROP_IGNORING_PLAYER) == 0,
\t\t"Player collision channels distinguish ordinary props from the transient overlap-only prop channel"
\t)
''',
    "player collision-channel assertion",
)
test_path.write_text(tests, encoding="utf-8")

# Update the written contract: placement may overlap the player, but rigid motion
# never becomes a fake kinematic escape.
plan_path = Path("docs/DEVELOPMENT_PLAN.md")
plan = plan_path.read_text(encoding="utf-8")
p0 = plan.index("1. **Release/throw collision transaction.**")
p1 = plan.index("\n", p0)
plan_line = (
    "1. **Release/throw collision transaction.** Release placement uses the prop's real collision volume against world/other-prop blockers while deliberately allowing the chosen pose to overlap the releasing player's capsule when space is cramped. Physics categories are distinct (`world`, `player`, `ordinary_prop`, and one transient `ordinary_prop_player_overlap` filter channel), so once Junk leaves the carried slot it is immediately a live rigid body with ordinary world/prop collision and the full F-throw or R-release velocity. While the prop's actual shape still overlaps the releasing player, only that prop is moved to the transient channel that the player does not scan and its own mask excludes the player; world and prop channels remain active. Geometric separation restores the ordinary prop layer/mask. Do not freeze/kinematically translate the prop, zero global collision participation, use a timer/distance guess, or rely on a cached pairwise exception as the launch mechanism."
)
plan = plan[:p0] + plan_line + plan[p1:]
plan_path.write_text(plan, encoding="utf-8")

vision_path = Path("docs/GAME_VISION.md")
vision = vision_path.read_text(encoding="utf-8")
v0 = vision.index("Release placement uses the prop's real collision volume.")
v1 = vision.index("\n\nA prop that leaves world participation", v0)
vision_paragraph = (
    "Release placement uses the prop's real collision volume. World geometry and other physical objects remain solid blockers, but the placement search deliberately ignores the releasing player's capsule so cramped spaces may choose a world-clear pose that initially overlaps the player. Player, world, and ordinary props live on distinct physics collision channels. A carried prop that is released into player overlap uses a fourth transient filtering channel for that prop only: the player does not scan it and the prop does not scan the player, while the prop continues to scan world and ordinary-prop channels. The prop is therefore a normal live rigid body from the first moving physics tick with the complete throw or gentle-release velocity; there is no frozen/manual escape translation. As soon as the actual prop and player collision volumes are geometrically separated, the prop returns to its ordinary prop layer/mask and collides with the player normally again. This overlap filter is derived transient physics state, not a timer, arbitrary travel-distance expiry, global collision shutdown, collision-exception cache workaround, or saved semantic state."
)
vision = vision[:v0] + vision_paragraph + vision[v1:]
vision_path.write_text(vision, encoding="utf-8")

testing_path = Path("docs/TESTING.md")
testing = testing_path.read_text(encoding="utf-8")ntesting_old = "a valid throw pose intentionally overlapping the player retains its throw impulse; an initial player overlap uses a world-swept escape handoff and the temporary prop↔player exception disappears after geometric separation;"
testing_new = "a valid throw pose intentionally overlapping the player remains a live rigid body with its throw impulse; the overlap uses a player-only transient collision channel while retaining world/prop collision, and ordinary player collision returns after geometric separation;"
testing = replace_once(testing, testing_old, testing_new, "testing overlap contract")
testing_path.write_text(testing, encoding="utf-8")
