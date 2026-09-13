# Vark repository workflow

This file is the process contract for AI-assisted work in this repository.

## Sources of truth

- `docs/GAME_VISION.md`: product/design direction.
- `docs/DEVELOPMENT_PLAN.md`: ordered roadmap, dependencies, acceptance criteria, and status.
- `docs/REGRESSION_TEST_PLAN.md`: automated-test policy and protected invariants.
- `docs/player_movement_regression_checklist.md`: broad manual movement/traversal checks.

Current repository files take precedence over stale chat context. The user's latest explicit design instruction takes precedence over older documentation.

## Roadmap work

For a request such as `implement 2.3`, first read the matching roadmap item and the relevant vision/test sections, then inspect the current code and tests. Implement only that bounded item plus the minimum supporting architecture it genuinely requires. Do not silently bundle adjacent roadmap items or speculative future systems.

Prefer root-cause fixes, clear ownership, and semantic APIs over duplicated logic, arbitrary thresholds, or workarounds. Do not change intended gameplay merely to make a test pass; fix an incorrect test invariant instead.

## Tests

Automate objective, deterministic behavior that is expensive to rediscover manually. In particular, add or update regression coverage when fixing a reproducible gameplay bug, changing movement/collision/traversal, adding important state transitions, adding AI perception rules, or adding deterministic interaction, mission, persistence, inventory, or save/load logic.

Subjective feel, pacing, readability, atmosphere, animation quality, and whether a mechanic feels like Vark are decided by the user's playtest feedback, not by automated assertions.

Tests should use real gameplay objects/physics where practical, minimal deterministic fixtures, semantic assertions, fixed inputs/transforms, physics-frame progression, and complete cleanup between cases. Existing relevant suites must continue passing.

## Documentation

Update `GAME_VISION.md` only for confirmed design-direction changes. Update `DEVELOPMENT_PLAN.md` when roadmap scope, dependencies, acceptance criteria, or truthful implementation status changes. Update `REGRESSION_TEST_PLAN.md` when meaningful automated coverage or its protected invariant changes.

Roadmap status meanings:

- `[ ]`: not implemented.
- `[~]`: implemented or substantially implemented but still awaiting planned validation/follow-up.
- `[x]`: implementation has passed the required local automated checks and the user's manual/playtest acceptance criteria.

Do not mark newly uploaded gameplay code `[x]` before the user validates it.

Do not create or maintain `PLAYTEST_NOTES.md`; subjective feedback stays in chat unless the user explicitly requests a document later.

## GitHub policy

Repository writes require the user's explicit phrase `upload to gh` in the current request. Without it, GitHub work is read-only.

Authorized writes go only to the existing `test` branch. Never write to `main` or another branch, and do not create helper branches. One authorization covers one coherent requested patch; after that patch is uploaded and verified, later writes require a new authorization.

Before a write, re-read the current `test` head and the current versions of files being modified. After a write, verify the final `test` head and compare it with the pre-write head to confirm the exact changed-file set.

Do not claim Godot/runtime tests were run unless they actually were. When runtime execution is unavailable, give the user the exact local automated command and manual playtest scenario required for acceptance.

## Development loop

1. User selects one roadmap item.
2. Implement the bounded item.
3. Add/update objective tests and relevant docs.
4. Upload only when explicitly authorized.
5. User runs automated tests locally.
6. User playtests in Godot.
7. User reports bugs or feel differences in chat.
8. Fix/tune the requested issue.
9. Mark the roadmap item complete only after required validation is accepted.
10. Move to the next item.

## Current movement constraint

Wall dash is not part of Vark's planned movement set. Do not add or plan wall-dash behavior unless the user explicitly changes that decision.
