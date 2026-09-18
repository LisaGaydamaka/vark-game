from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one diagnostic anchor, found {count}")
    p.write_text(text.replace(old, new, 1))


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
\t\tif traversal_guard.is_mantle_blocked(candidate):
\t\t\tcontinue
\t\tif not _candidate_matches_any_contact(candidate, collisions):
\t\t\tcontinue

\t\tif ground_request:
\t\t\tif (
\t\t\t\t_should_attempt_ground_mantle_contact(candidate, input_direction)
\t\t\t\tand _try_start_free_mantle(candidate)
\t\t\t):
\t\t\t\treturn true
\t\t\tcontinue''',
    '''\tfor candidate: PlayerLedgeDetector.LedgeCandidate in candidates:
\t\tif candidate == null:
\t\t\tcontinue
\t\tvar debug_refresh_ok: bool = ledge_detector.refresh_candidate_attachment(candidate)
\t\tprint(
\t\t\t"MANTLE_ADMISSION_DEBUG refresh=", debug_refresh_ok,
\t\t\t" ground=", ground_request,
\t\t\t" air=", air_request,
\t\t\t" collisions=", collisions.size(),
\t\t\t" edge=", candidate.edge_point
\t\t)
\t\tif not debug_refresh_ok:
\t\t\tcontinue
\t\tvar debug_blocked: bool = traversal_guard.is_mantle_blocked(candidate)
\t\tvar debug_matches: bool = _candidate_matches_any_contact(candidate, collisions)
\t\tprint(
\t\t\t"MANTLE_ADMISSION_DEBUG blocked=", debug_blocked,
\t\t\t" matches=", debug_matches,
\t\t\t" input=", input_direction,
\t\t\t" wall=", candidate.wall_normal
\t\t)
\t\tif debug_blocked:
\t\t\tcontinue
\t\tif not debug_matches:
\t\t\tcontinue

\t\tif ground_request:
\t\t\tvar debug_ground_gate: bool = _should_attempt_ground_mantle_contact(
\t\t\t\tcandidate,
\t\t\t\tinput_direction
\t\t\t)
\t\t\tprint("MANTLE_ADMISSION_DEBUG ground_gate=", debug_ground_gate)
\t\t\tif debug_ground_gate:
\t\t\t\tvar debug_started: bool = _try_start_free_mantle(candidate)
\t\t\t\tprint("MANTLE_ADMISSION_DEBUG started=", debug_started)
\t\t\t\tif debug_started:
\t\t\t\t\treturn true
\t\t\tcontinue'''
)

replace_once(
    "player/traversal/player_ledge_controller.gd",
    '''func _try_start_free_mantle(
\tcandidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
\tvar mantle_candidate: PlayerMantle.MantleCandidate = (
\t\tledge_mantle.find_air_candidate(
\t\t\tbody,
\t\t\tsupport,
\t\t\tcandidate
\t\t)
\t)
\tif mantle_candidate == null or not ledge_mantle.try_start(body, mantle_candidate):
\t\treturn false

\tledge_detector.clear_candidate()''',
    '''func _try_start_free_mantle(
\tcandidate: PlayerLedgeDetector.LedgeCandidate
) -> bool:
\tvar mantle_candidate: PlayerMantle.MantleCandidate = (
\t\tledge_mantle.find_air_candidate(
\t\t\tbody,
\t\t\tsupport,
\t\t\tcandidate
\t\t)
\t)
\tprint(
\t\t"MANTLE_ADMISSION_DEBUG mantle_candidate_null=",
\t\tmantle_candidate == null
\t)
\tif mantle_candidate == null:
\t\treturn false
\tvar debug_try_start: bool = ledge_mantle.try_start(body, mantle_candidate)
\tprint("MANTLE_ADMISSION_DEBUG try_start=", debug_try_start)
\tif not debug_try_start:
\t\treturn false

\tledge_detector.clear_candidate()'''
)

print("STAGED_MANTLE_ADMISSION_DIAGNOSTICS")
