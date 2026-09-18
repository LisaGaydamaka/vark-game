from pathlib import Path

path = Path("player/traversal/player_ledge_controller.gd")
text = path.read_text()
old = '''\tfor candidate: PlayerLedgeDetector.LedgeCandidate in candidates:
\t\tif candidate == null:
\t\t\tcontinue
\t\tif traversal_guard.is_mantle_blocked(candidate):
\t\t\tcontinue
\t\tif not _candidate_matches_any_contact(candidate, collisions):'''
new = '''\tfor candidate: PlayerLedgeDetector.LedgeCandidate in candidates:
\t\tif candidate == null:
\t\t\tcontinue
\t\t# Discovery occurs before locomotion resolves the contact. A lightweight
\t\t# prop can move during that same transaction, so refresh its exact sampled
\t\t# geometry before comparing the candidate with the post-move collision.
\t\tif not ledge_detector.refresh_candidate_attachment(candidate):
\t\t\tcontinue
\t\tif traversal_guard.is_mantle_blocked(candidate):
\t\t\tcontinue
\t\tif not _candidate_matches_any_contact(candidate, collisions):'''
count = text.count(old)
if count != 1:
    raise SystemExit(f"mantle pre-match refresh anchor expected once, found {count}")
path.write_text(text.replace(old, new, 1))
print("STAGED_MANTLE_PREMATCH_ATTACHMENT_REFRESH")
