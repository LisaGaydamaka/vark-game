from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


# Make the temporary player collision exception truly pairwise. The prop's
# dynamic solver and the player's CharacterBody motion queries must both ignore
# one another until the actual collision volumes separate.
path = Path("gameplay/props/ordinary_prop.gd")
text = path.read_text(encoding="utf-8")
text = replace_once(
    text,
    "var _temporary_player_collision_exception: PhysicsBody3D = null\n",
    "var _temporary_player_collision_exception: PhysicsBody3D = null\nvar _player_escape_collision_suppressed: bool = false\n",
    "player escape suppression field",
)
text = replace_once(
    text,
    "\t\tadd_collision_exception_with(releasing_player)\n\t\t_temporary_player_collision_exception = releasing_player\n",
    "\t\tadd_collision_exception_with(releasing_player)\n\t\treleasing_player.add_collision_exception_with(self)\n\t\t_temporary_player_collision_exception = releasing_player\n",
    "symmetric release exception add",
)
text = replace_once(
    text,
    "\t\tremove_collision_exception_with(_temporary_player_collision_exception)\n\t_temporary_player_collision_exception = null\n",
    "\t\tremove_collision_exception_with(_temporary_player_collision_exception)\n\t\t_temporary_player_collision_exception.remove_collision_exception_with(self)\n\t_temporary_player_collision_exception = null\n",
    "symmetric release exception clear",
)

# The carried body has collision layer/mask zero. If a valid world-clear release
# transform still overlaps the player, Jolt 4.7.2 can resolve that pair on the
# first rigid tick even though both public collision-exception lists contain the
# other body. Keep the prop dynamic and preserve its launch velocity, but keep
# its collision layer/mask suppressed only while its actual collision volume
# overlaps the releasing player. The geometric separation predicate, not time or
# distance travelled, owns restoration of normal rigid collision.
old_release_order = '''\t_holder = null
\tglobal_transform = release_transform
\tif (
\t\treleasing_player != null
\t\tand is_instance_valid(releasing_player)
\t\tand _shape_overlaps_body_at_transform(release_transform, releasing_player)
\t):
\t\tadd_collision_exception_with(releasing_player)
\t\treleasing_player.add_collision_exception_with(self)
\t\t_temporary_player_collision_exception = releasing_player
\t_set_world_presentation_enabled(true)
\t_begin_motion(motion_kind, initial_velocity)
'''
new_release_order = '''\t_holder = null
\tglobal_transform = release_transform
\tvar overlaps_releasing_player: bool = (
\t\treleasing_player != null
\t\tand is_instance_valid(releasing_player)
\t\tand _shape_overlaps_body_at_transform(release_transform, releasing_player)
\t)
\t_set_world_presentation_enabled(true)
\tif overlaps_releasing_player:
\t\tadd_collision_exception_with(releasing_player)
\t\treleasing_player.add_collision_exception_with(self)
\t\t_temporary_player_collision_exception = releasing_player
\t\tcollision_layer = 0
\t\tcollision_mask = 0
\t\t_player_escape_collision_suppressed = true
\t_begin_motion(motion_kind, initial_velocity)
'''
text = replace_once(text, old_release_order, new_release_order, "release collision activation order")

# PhysicsDirectSpaceState3D.intersect_shape() exposes both the collider object
# and its RID. Use actual body identity as the primary overlap predicate so the
# pairwise exception lifetime is derived from the queried collision volume.
old_overlap = '''func _shape_overlaps_body_at_transform(body_transform: Transform3D, other_body: PhysicsBody3D) -> bool:
\tif (
\t\tother_body == null
\t\tor not is_instance_valid(other_body)
\t\tor prop_collision == null
\t\tor prop_collision.shape == null
\t\tor not is_inside_tree()
\t):
\t\treturn false
\tvar query := PhysicsShapeQueryParameters3D.new()
\tquery.shape = prop_collision.shape
\tquery.transform = body_transform * prop_collision.transform
\tquery.collision_mask = 0xFFFFFFFF
\tquery.collide_with_areas = false
\tquery.collide_with_bodies = true
\tquery.margin = 0.001
\tquery.exclude = [get_rid()]
\tvar other_rid: RID = other_body.get_rid()
\tfor hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 32):
\t\tvar hit_rid: Variant = hit.get("rid")
\t\tif hit_rid is RID and hit_rid == other_rid:
\t\t\treturn true
\treturn false
'''
new_overlap = '''func _shape_overlaps_body_at_transform(body_transform: Transform3D, other_body: PhysicsBody3D) -> bool:
\tif (
\t\tother_body == null
\t\tor not is_instance_valid(other_body)
\t\tor prop_collision == null
\t\tor prop_collision.shape == null
\t\tor not is_inside_tree()
\t):
\t\treturn false
\tvar query := PhysicsShapeQueryParameters3D.new()
\tquery.shape = prop_collision.shape
\tquery.transform = body_transform * prop_collision.transform
\tquery.collision_mask = 0xFFFFFFFF
\tquery.collide_with_areas = false
\tquery.collide_with_bodies = true
\tquery.margin = 0.001
\tquery.exclude = [get_rid()]
\tvar other_rid: RID = other_body.get_rid()
\tfor hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 32):
\t\tvar hit_collider: Variant = hit.get("collider")
\t\tif hit_collider == other_body:
\t\t\treturn true
\t\tvar hit_rid: Variant = hit.get("rid")
\t\tif hit_rid is RID and hit_rid == other_rid:
\t\t\treturn true
\treturn false
'''
text = replace_once(text, old_overlap, new_overlap, "player overlap collider identity")

old_exception_update = '''func _update_temporary_player_collision_exception() -> void:
\tif _temporary_player_collision_exception == null:
\t\treturn
\tif not is_instance_valid(_temporary_player_collision_exception):
\t\t_temporary_player_collision_exception = null
\t\treturn
\tif _shape_overlaps_body_at_transform(global_transform, _temporary_player_collision_exception):
\t\treturn
\t_clear_temporary_player_collision_exception()


func _clear_temporary_player_collision_exception() -> void:
\tif (
\t\t_temporary_player_collision_exception != null
\t\tand is_instance_valid(_temporary_player_collision_exception)
\t):
\t\tremove_collision_exception_with(_temporary_player_collision_exception)
\t\t_temporary_player_collision_exception.remove_collision_exception_with(self)
\t_temporary_player_collision_exception = null
'''
new_exception_update = '''func _update_temporary_player_collision_exception() -> void:
\tif _temporary_player_collision_exception == null:
\t\treturn
\tif not is_instance_valid(_temporary_player_collision_exception):
\t\t_clear_temporary_player_collision_exception()
\t\treturn
\tif _shape_overlaps_body_at_transform(global_transform, _temporary_player_collision_exception):
\t\treturn
\t_clear_temporary_player_collision_exception()


func _clear_temporary_player_collision_exception() -> void:
\tif (
\t\t_temporary_player_collision_exception != null
\t\tand is_instance_valid(_temporary_player_collision_exception)
\t):
\t\tremove_collision_exception_with(_temporary_player_collision_exception)
\t\t_temporary_player_collision_exception.remove_collision_exception_with(self)
\t_temporary_player_collision_exception = null
\tif _player_escape_collision_suppressed:
\t\tcollision_layer = _ordinary_collision_layer
\t\tcollision_mask = _ordinary_collision_mask
\t\t_player_escape_collision_suppressed = false
'''
text = replace_once(text, old_exception_update, new_exception_update, "geometric player escape restoration")

# Preserve the inexpensive authored-placement support rays, but let the real
# collision shape provide a shallow rest query when a legitimate edge/corner
# support falls between those discrete samples.
old_support_tail = '''\tfor local_point: Vector3 in local_points:
\t\tvar bottom: Vector3 = global_transform * local_point
\t\tvar origin: Vector3 = bottom + Vector3.UP * 0.02
\t\tvar query := PhysicsRayQueryParameters3D.create(
\t\t\torigin,
\t\t\tbottom + Vector3.DOWN * maxf(support_probe_distance, 0.03)
\t\t)
\t\tquery.exclude = [get_rid()]
\t\tquery.collision_mask = _ordinary_collision_mask
\t\tquery.collide_with_areas = false
\t\tquery.collide_with_bodies = true
\t\tvar hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
\t\tif not hit.is_empty():
\t\t\tvar normal: Vector3 = hit.get("normal", Vector3.UP)
\t\t\tif normal.y >= minimum_support_normal_y:
\t\t\t\treturn true
\treturn false
'''
new_support_tail = '''\tfor local_point: Vector3 in local_points:
\t\tvar bottom: Vector3 = global_transform * local_point
\t\tvar origin: Vector3 = bottom + Vector3.UP * 0.02
\t\tvar query := PhysicsRayQueryParameters3D.create(
\t\t\torigin,
\t\t\tbottom + Vector3.DOWN * maxf(support_probe_distance, 0.03)
\t\t)
\t\tquery.exclude = [get_rid()]
\t\tquery.collision_mask = _ordinary_collision_mask
\t\tquery.collide_with_areas = false
\t\tquery.collide_with_bodies = true
\t\tvar hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
\t\tif not hit.is_empty():
\t\t\tvar normal: Vector3 = hit.get("normal", Vector3.UP)
\t\t\tif normal.y >= minimum_support_normal_y:
\t\t\t\treturn true

\tvar support_query := PhysicsShapeQueryParameters3D.new()
\tsupport_query.shape = prop_collision.shape
\tvar support_transform: Transform3D = global_transform * prop_collision.transform
\tsupport_transform.origin += Vector3.DOWN * clampf(support_probe_distance, 0.01, 0.04)
\tsupport_query.transform = support_transform
\tsupport_query.exclude = [get_rid()]
\tsupport_query.collision_mask = _ordinary_collision_mask
\tsupport_query.collide_with_areas = false
\tsupport_query.collide_with_bodies = true
\tsupport_query.margin = 0.001
\tvar rest_info: Dictionary = get_world_3d().direct_space_state.get_rest_info(support_query)
\tif rest_info.is_empty():
\t\treturn false
\tvar rest_normal: Vector3 = rest_info.get("normal", Vector3.ZERO)
\treturn (
\t\trest_normal.length_squared() > 0.000001
\t\tand rest_normal.normalized().y >= minimum_support_normal_y
\t)
'''
text = replace_once(text, old_support_tail, new_support_tail, "settled support shape fallback")
path.write_text(text, encoding="utf-8")


# Keep the focused regression deterministic: the temporary blocker used for
# the first release-placement assertion must be gone from the physics space
# before the later intentional player-overlap throw begins.
path = Path("tests/props/phase_3_5_transition_regressions.gd")
text = path.read_text(encoding="utf-8")
text = replace_once(
    text,
    "\tblocker.queue_free()\n\tawait tree.process_frame\n\tassert_true.call(bool(player.call(\"try_carry_prop\", prop)), \"Released prop can re-enter carried Junk for overlap setup\")\n",
    "\tblocker.queue_free()\n\tawait tree.process_frame\n\tawait _settle_physics(tree, 2)\n\tassert_true.call(bool(player.call(\"try_carry_prop\", prop)), \"Released prop can re-enter carried Junk for overlap setup\")\n",
    "blocker physics-space cleanup",
)
text = replace_once(
    text,
    "\tsupport_body.global_position = Vector3(3.0, 0.4, 2.5)\n",
    "\tsupport_body.global_position = Vector3(2.89, 0.4, 2.5)\n",
    "narrow support fixture position",
)
text = replace_once(
    text,
    "\t\tand player in prop.get_collision_exceptions(),\n",
    "\t\tand player in prop.get_collision_exceptions()\n\t\tand prop in player.get_collision_exceptions(),\n",
    "pairwise overlap exception assertion",
)
text = replace_once(
    text,
    "\t\tcleared and not bool(prop.call(\"has_temporary_player_collision_exception\"))\n\t\tand not (player in prop.get_collision_exceptions()),\n",
    "\t\tcleared and not bool(prop.call(\"has_temporary_player_collision_exception\"))\n\t\tand not (player in prop.get_collision_exceptions())\n\t\tand not (prop in player.get_collision_exceptions())\n\t\tand prop.collision_layer == 1 and prop.collision_mask == 1,\n",
    "pairwise exception clear assertion",
)
text = replace_once(
    text,
    '''func _wait_for_player_exception_clear(tree: SceneTree, prop: RigidBody3D, player: CharacterBody3D, max_frames: int) -> bool:
\tfor _frame_index: int in max_frames:
\t\tif not bool(prop.call("has_temporary_player_collision_exception")) and not (player in prop.get_collision_exceptions()):
\t\t\treturn true
\t\tawait tree.physics_frame
\t\tawait tree.process_frame
\treturn false
''',
    '''func _wait_for_player_exception_clear(tree: SceneTree, prop: RigidBody3D, player: CharacterBody3D, max_frames: int) -> bool:
\tfor _frame_index: int in max_frames:
\t\tif (
\t\t\tnot bool(prop.call("has_temporary_player_collision_exception"))
\t\t\tand not (player in prop.get_collision_exceptions())
\t\t\tand not (prop in player.get_collision_exceptions())
\t\t\tand prop.collision_layer == 1
\t\t\tand prop.collision_mask == 1
\t\t):
\t\t\treturn true
\t\tawait tree.physics_frame
\t\tawait tree.process_frame
\treturn false
''',
    "pairwise exception wait",
)
path.write_text(text, encoding="utf-8")