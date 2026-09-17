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

# PhysicsDirectSpaceState3D.intersect_shape() exposes both the collider object
# and its RID. Use actual body identity as the primary overlap predicate so the
# pairwise exception lifetime is derived from the real queried collision
# volume, without depending on backend-specific RID reporting. Keep the RID as
# a compatibility fallback.
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


# Place the narrow support under the tilted cube's real lowest edge while still
# remaining between the retired nine ray samples, and assert the pairwise
# collision exception is present/cleared on both bodies.
path = Path("tests/props/phase_3_5_transition_regressions.gd")
text = path.read_text(encoding="utf-8")
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
    "\t\tcleared and not bool(prop.call(\"has_temporary_player_collision_exception\"))\n\t\tand not (player in prop.get_collision_exceptions())\n\t\tand not (prop in player.get_collision_exceptions()),\n",
    "pairwise exception clear assertion",
)
path.write_text(text, encoding="utf-8")