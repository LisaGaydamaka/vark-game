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
    '''func try_enter_ground_mantle_from_dynamic_candidate(
\tinput_direction: Vector3
) -> bool:
\t# The ledge detector performs a real test_move against current world geometry
\t# before locomotion. A dynamic exact-collider ledge can advance before the
\t# player's movement callback, so the post-move collision list may be empty
\t# even though this same-frame detector result still proves the mantle surface.
\t# This fallback is intentionally limited to exact unstable/moving geometry;
\t# static ground-mantle admission remains contact-driven exactly as before.
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
\t\tif not ledge_detector.refresh_candidate_attachment(candidate):
\t\t\tcontinue
\t\tif ledge_detector.is_candidate_attachment_stable(candidate):
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
\t\t# Dynamic ledge geometry may have advanced before this callback and erased
\t\t# the movement collision. The same-frame detector result is accepted only
\t\t# for an exact currently-unstable collider; static no-contact behavior does
\t\t# not change.
\t\tif ledge_controller.try_enter_ground_mantle_from_dynamic_candidate(
\t\t\tinput_direction
\t\t):
\t\t\tstep.cancel()
\t\t\treturn

\tif ground_mantle_requested:
\t\tstep.cancel()
\t\tsupport.release_walkable_support(body)
\t\t_apply_controlled_jump()'''
)

print("STAGED_GROUND_MANTLE_DYNAMIC_COLLIDER_CONTACT_SEAM")
