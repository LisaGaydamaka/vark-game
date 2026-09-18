from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one seam anchor, found {count}")
    p.write_text(text.replace(old, new, 1))


replace_once(
    "player/traversal/player_ledge_controller.gd",
    '''func _candidate_matches_any_contact(
\tcandidate: PlayerLedgeDetector.LedgeCandidate,
\tcollisions: Array[KinematicCollision3D]
) -> bool:''',
    '''func try_enter_ground_mantle_from_moved_candidate(
\tinput_direction: Vector3
) -> bool:
\t# Ledge discovery happens before the locomotion transaction. A lightweight
\t# exact-collider ledge can translate away during that same physics frame,
\t# leaving no post-move KinematicCollision even though it is the same mantle
\t# opportunity. Bridge only that proven same-frame transform change: no timer,
\t# no coyote window, and no static/no-contact mantle path is introduced.
\tvar candidates: Array[PlayerLedgeDetector.LedgeCandidate] = (
\t\tledge_detector.get_candidates()
\t)
\tfor candidate: PlayerLedgeDetector.LedgeCandidate in candidates:
\t\tif (
\t\t\tcandidate == null
\t\t\tor not candidate.attachment_collider_transform_valid
\t\t\tor not candidate.attachment_collider_rid.is_valid()
\t\t):
\t\t\tcontinue

\t\tvar attachment_rid: RID = candidate.attachment_collider_rid
\t\tvar discovery_transform: Transform3D = candidate.attachment_collider_transform
\t\tif not ledge_detector.refresh_candidate_attachment(candidate):
\t\t\tcontinue
\t\tif (
\t\t\tnot candidate.attachment_collider_transform_valid
\t\t\tor candidate.attachment_collider_rid != attachment_rid
\t\t\tor candidate.attachment_collider_transform.is_equal_approx(
\t\t\t\tdiscovery_transform
\t\t\t)
\t\t):
\t\t\tcontinue
\t\tif traversal_guard.is_mantle_blocked(candidate):
\t\t\tcontinue
\t\tif not _should_attempt_ground_mantle_contact(candidate, input_direction):
\t\t\tcontinue
\t\tif _try_start_free_mantle(candidate):
\t\t\treturn true
\treturn false


func _candidate_matches_any_contact(
\tcandidate: PlayerLedgeDetector.LedgeCandidate,
\tcollisions: Array[KinematicCollision3D]
) -> bool:'''
)

replace_once(
    "player/locomotion/player_locomotion_controller.gd",
    '''\tif ground_mantle_requested:
\t\tstep.cancel()
\t\tsupport.release_walkable_support(body)
\t\t_apply_controlled_jump()''',
    '''\tif ground_mantle_requested and collisions.is_empty():
\t\t# A pushable ledge can move out of the contact solver during the same
\t\t# grounded mantle frame. The traversal controller accepts this only when
\t\t# the exact candidate collider proves a transform change since discovery.
\t\tif ledge_controller.try_enter_ground_mantle_from_moved_candidate(
\t\t\tinput_direction
\t\t):
\t\t\tstep.cancel()
\t\t\treturn

\tif ground_mantle_requested:
\t\tstep.cancel()
\t\tsupport.release_walkable_support(body)
\t\t_apply_controlled_jump()'''
)

print("STAGED_GROUND_MANTLE_MOVED_COLLIDER_CONTACT_SEAM")
