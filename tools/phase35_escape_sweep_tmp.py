from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


path = Path("gameplay/props/ordinary_prop.gd")
text = path.read_text(encoding="utf-8")
old = '''func _advance_player_escape(delta: float) -> void:
\tvar launch_velocity: Vector3 = _player_escape_launch_velocity
\tif (
\t\t_temporary_player_collision_exception == null
\t\tor not is_instance_valid(_temporary_player_collision_exception)
\t):
\t\t_clear_temporary_player_collision_exception()
\t\t_player_escape_launch_velocity = Vector3.ZERO
\t\t_player_escape_step_velocity = Vector3.ZERO
\t\t_begin_motion(_motion_kind, launch_velocity)
\t\treturn
\tglobal_position += _player_escape_step_velocity * maxf(delta, 0.0)
\tlinear_velocity = _player_escape_launch_velocity
\tangular_velocity = Vector3.ZERO
\tif _shape_overlaps_body_at_transform(global_transform, _temporary_player_collision_exception):
\t\treturn
\t_clear_temporary_player_collision_exception()
\t_player_escape_launch_velocity = Vector3.ZERO
\t_player_escape_step_velocity = Vector3.ZERO
\t_begin_motion(_motion_kind, launch_velocity)


'''
new = '''func _advance_player_escape(delta: float) -> void:
\tvar launch_velocity: Vector3 = _player_escape_launch_velocity
\tif (
\t\t_temporary_player_collision_exception == null
\t\tor not is_instance_valid(_temporary_player_collision_exception)
\t):
\t\t_clear_temporary_player_collision_exception()
\t\t_player_escape_launch_velocity = Vector3.ZERO
\t\t_player_escape_step_velocity = Vector3.ZERO
\t\t_begin_motion(_motion_kind, launch_velocity)
\t\treturn
\tvar requested_motion: Vector3 = _player_escape_step_velocity * maxf(delta, 0.0)
\tvar safe_motion: Vector3 = _sweep_player_escape_motion(
\t\trequested_motion,
\t\t_temporary_player_collision_exception
\t)
\tglobal_position += safe_motion
\tlinear_velocity = _player_escape_launch_velocity
\tangular_velocity = Vector3.ZERO
\tif not _shape_overlaps_body_at_transform(global_transform, _temporary_player_collision_exception):
\t\t_clear_temporary_player_collision_exception()
\t\t_player_escape_launch_velocity = Vector3.ZERO
\t\t_player_escape_step_velocity = Vector3.ZERO
\t\t_begin_motion(_motion_kind, launch_velocity)
\t\treturn
\tif requested_motion.length_squared() > 0.000001 and safe_motion.length() + 0.0001 < requested_motion.length():
\t\t# World geometry won the sweep before the player volume cleared. Restore
\t\t# ordinary rigid collision here rather than ghosting through the blocker.
\t\t_clear_temporary_player_collision_exception()
\t\t_player_escape_launch_velocity = Vector3.ZERO
\t\t_player_escape_step_velocity = Vector3.ZERO
\t\t_begin_motion(_motion_kind, launch_velocity)


func _sweep_player_escape_motion(motion: Vector3, ignored_player: PhysicsBody3D) -> Vector3:
\tif (
\t\tmotion.length_squared() <= 0.000001
\t\tor prop_collision == null
\t\tor prop_collision.shape == null
\t\tor not is_inside_tree()
\t):
\t\treturn Vector3.ZERO
\tvar query := PhysicsShapeQueryParameters3D.new()
\tquery.shape = prop_collision.shape
\tquery.transform = global_transform * prop_collision.transform
\tquery.motion = motion
\tquery.collision_mask = _ordinary_collision_mask
\tquery.collide_with_areas = false
\tquery.collide_with_bodies = true
\tquery.margin = 0.001
\tvar excluded: Array[RID] = [get_rid()]
\tif ignored_player != null and is_instance_valid(ignored_player):
\t\texcluded.append(ignored_player.get_rid())
\tquery.exclude = excluded
\tvar fractions: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(query)
\tif fractions.size() < 1:
\t\treturn Vector3.ZERO
\treturn motion * clampf(fractions[0], 0.0, 1.0)


'''
text = replace_once(text, old, new, "world-safe player escape sweep")
path.write_text(text, encoding="utf-8")


# Keep documentation precise about the Jolt overlap-only handoff: the prop's
# solver participation is briefly suppressed, but its escape motion is swept
# against ordinary world blockers and restored by geometric separation.
path = Path("docs/GAME_VISION.md")
text = path.read_text(encoding="utf-8")
old = "If the nearest valid release pose still overlaps the releasing player's capsule, only that prop↔player pair is temporarily non-colliding so the object can leave the player's volume without having its throw/release impulse destroyed. Normal prop↔player collision returns automatically as soon as the collision volumes are geometrically separated; this is derived transient physics state, never a timer, arbitrary travel-distance rule, global collision-layer change, or saved semantic state."
new = "If the nearest valid release pose still overlaps the releasing player's capsule, the same prop enters a short overlap-only escape handoff so Jolt cannot destroy the intended throw/release impulse on its first rigid tick. During that handoff the prop's solver collision participation is suppressed, but its collision shape is swept against ordinary world blockers while ignoring only the releasing player. Normal rigid collision and the prop↔player relationship are restored as soon as the collision volumes are geometrically separated; if world geometry blocks the escape first, ordinary rigid collision is restored there instead of allowing the prop to ghost through the blocker. This is per-prop derived transient physics state, never a timer, arbitrary travel-distance expiry, project-wide collision-layer reassignment, or saved semantic state."
text = replace_once(text, old, new, "GAME_VISION overlap handoff wording")
path.write_text(text, encoding="utf-8")

path = Path("docs/DEVELOPMENT_PLAN.md")
text = path.read_text(encoding="utf-8")
old = "A release pose may temporarily ignore only the releasing player when the two volumes overlap; the exception ends from geometric separation, not a timer or distance guess."
new = "A release pose may enter an overlap-only escape handoff when it intersects the releasing player: the prop ignores that player while its shape is still swept against ordinary world blockers, then returns to normal rigid collision from geometric separation rather than a timer or distance guess."
text = replace_once(text, old, new, "DEVELOPMENT_PLAN overlap handoff wording")
path.write_text(text, encoding="utf-8")

path = Path("docs/TESTING.md")
text = path.read_text(encoding="utf-8")
old = "only the prop↔player pair is temporarily excluded and the exception disappears after geometric separation"
new = "an initial player overlap uses a world-swept escape handoff and the temporary prop↔player exception disappears after geometric separation"
text = replace_once(text, old, new, "TESTING overlap handoff wording")
path.write_text(text, encoding="utf-8")
