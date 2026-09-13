# Vark Regression Test Plan

This document defines what should be protected by automated tests, when tests should be added, and how test suites should be organized as Vark grows.

Automated tests are for objective behavior. Subjective questions such as feel, pacing, readability, atmosphere, and whether a mechanic matches the intended experience are decided by playtesting and feedback in chat, not by automated assertions.

## Core rule

If a behavior is objective, reproducible, and expensive or annoying to rediscover manually, prefer an automated regression test.

When a reproducible gameplay bug is fixed, add a regression test if the bug can reasonably be recreated in a deterministic test fixture.

Do not add tests merely to increase test count. Each test should protect a meaningful invariant or previously broken behavior.

---

# Current test infrastructure

The current local movement suite is:

```powershell
godot --headless --path . --script res://tests/movement/run_movement_tests.gd
```

The runner:

- executes real Godot physics
- uses the real `Player.tscn` where player behavior is under test
- aggregates failures instead of stopping at the first assertion
- exits with code `0` on success and nonzero on failure
- releases simulated input between fixtures

The runner also has an intentional failure mode for validating the test harness itself:

```powershell
godot --headless --path . --script res://tests/movement/run_movement_tests.gd -- --intentional-failure
```

## Current automated movement coverage

### Framework sanity

Protects that the runner and assertion collector execute and report normally.

### Walk-off edge support refresh

Protects against support remaining grounded for one stale frame after a collision-free move off an edge.

Fixture behavior:

- real player starts grounded on a platform
- simulated forward input walks the player off the edge
- once the capsule is physically clear of the platform, grounded state must already be false on that completed movement frame

### Sprint-jump inherited momentum

Protects against airborne movement clamping inherited sprint speed down to ordinary run/air speed.

Fixture behavior:

- real player starts grounded
- forward+sprint reaches speed clearly above ordinary running speed
- jump actually leaves support
- horizontal speed immediately after takeoff must preserve the inherited pre-jump momentum within the intended tolerance

### Normal step

Protects ordinary grounded step acquisition/crossing.

Fixture behavior:

- real player approaches a valid step
- body must gain the expected elevation and progress across the obstacle

### Floating / undercut step

Protects the valid support-to-support step case where the blocker does not extend down to the source floor.

Fixture behavior:

- real player approaches an elevated thin/undercut obstacle
- step logic must not require an artificial floor-connected riser
- player must acquire and cross the step

### Wall-seam unsupported fall

Protects against modular wall seams or convex contacts cancelling vertical falling motion.

Fixture behavior:

- unsupported player falls while contacting modular wall geometry
- player reaches below the seam
- downward motion continues for subsequent frames
- no fake grounded state is created

### Multi-contact fall

Protects against simultaneous wall contacts manufacturing support or cancelling unsupported downward motion.

Fixture behavior:

- unsupported player falls while driven into a multi-contact corner
- player continues falling a meaningful distance
- vertical velocity remains downward
- no grounded state is manufactured

## Existing manual movement coverage

`docs/player_movement_regression_checklist.md` remains the broad manual controller checklist. It is intentionally broader than the automated suite and should be used after major movement/traversal changes.

The automated suite does not replace that checklist; it reduces the number of known correctness regressions that must be discovered by hand.

---

# Test design rules

## 1. Prefer real gameplay objects

When testing player movement, use the real player scene and real physics geometry instead of mocked collision logic.

When testing guard perception, prefer the real guard perception component/state model in a minimal fixture rather than reimplementing the algorithm inside the test.

## 2. Keep fixtures small

A regression fixture should contain only enough geometry/actors to reproduce the behavior.

Good:

- one player + one platform edge
- one guard + one wall + one target
- one door + one player interaction probe

Bad:

- loading an entire production mission to test one state transition

## 3. Test semantics, not private implementation details

Prefer assertions such as:

- `is_grounded() == false`
- guard state becomes `SUSPICIOUS`
- door state becomes `OPEN`
- loot total increases once

Avoid assertions that depend on private helper call order unless that ordering is itself the required behavior.

Small read-only semantic query methods are acceptable when they expose meaningful gameplay state without giving tests control over implementation internals.

## 4. Deterministic physics only

Use fixed starting transforms, fixed geometry, fixed input, and physics-frame progression.

Avoid:

- real-time sleeps
- dependence on render FPS
- random placement without a fixed seed
- broad timing windows that hide nondeterminism

If a test intermittently fails, treat the test or system as unstable before adding it to CI.

## 5. Clean up all input/state

Every fixture must release simulated input and free its nodes before the next fixture. Tests must be runnable in any suite order unless explicit dependencies are unavoidable.

## 6. Assert the actual regression boundary

A regression test should fail as close as possible to the original bug.

Example: for stale walk-off support, do not merely assert that the player becomes airborne eventually. Assert that support is already gone once the completed movement pose is physically unsupported.

## 7. Do not encode subjective tuning accidentally

A test may protect an intentional configured value or relationship, but should not convert temporary feel-tuning into a permanent invariant without a design reason.

Example: the sprint-jump test should prove that inherited sprint momentum is preserved, not that the player reaches an exact theoretical sprint cap before jumping.

---

# When to add tests

Add automated coverage when one or more of these is true:

- fixing a reproducible gameplay bug
- introducing a state machine or important state transition
- changing collision/traversal/contact code
- adding mission/objective/stat persistence logic
- adding deterministic inventory/interaction ownership
- adding AI perception rules
- changing save/load or cross-mission consequences
- refactoring code whose behavior is already correct and easy to regress

A test is optional when the behavior is primarily visual, artistic, or subjective and there is no useful objective invariant.

---

# Planned suites

Do not create all suites in advance. Create a new suite when the first real system in that category exists.

Once more than one suite exists, add a single `tests/run_all_tests.gd` (or equivalent) so local development and CI have one authoritative command for the full regression barrier.

## Movement / traversal

Location target: `tests/movement/`

Current coverage exists.

Planned next coverage:

- almost-vertical / invalid mantle landing surface is rejected
- valid mantle landing surface succeeds
- crouch-only mantle succeeds if stance-aware mantle behavior is touched
- important ledge/corner regressions as they become reproducible
- any future slide/ladder/swimming bug that has an objective deterministic fixture

Do not add speculative tests for unimplemented traversal systems.

## Stealth / perception

Location target: `tests/stealth/`

Create when Milestone 2 begins.

Planned objective coverage:

### Player light exposure

- known dark case produces low exposure
- known bright case produces higher exposure
- value remains in defined bounds
- deterministic occlusion/contribution rules behave as designed

### Guard vision

- visible target in FOV/range can generate visual evidence
- target outside FOV cannot generate equivalent evidence
- occluded target cannot be seen
- out-of-range target cannot be seen
- light exposure affects detection progression according to final design

### Guard hearing

- in-range noise can be heard
- out-of-range / too-weak noise is ignored
- deterministic occlusion/material rules if introduced
- heard evidence routes into guard state rather than bypassing state ownership

### Guard state transitions

- unaware → suspicious/investigating
- suspicious → alerted when sufficient evidence accumulates
- alerted → searching when target is lost according to final design
- searching/recovery transitions follow intended rules
- invalid/impossible transitions are rejected if the model enforces them

Do not attempt to automate whether detection “feels too fast”; tune that manually, then protect only deliberate chosen relationships/values where useful.

## Interaction

Location target: `tests/interaction/`

Create when the generic interaction framework exists.

Planned coverage:

- valid interactable can be focused/selected
- out-of-range target is rejected
- blocked/invalid target is rejected where designed
- action dispatch reaches the selected interactable once
- door/window state transitions
- locked/unlocked rules when those are implemented
- loot transfers once and cannot be duplicated
- turning off a gameplay-relevant light updates its state/exposure contribution
- held-object ownership transitions for pickup/drop/throw

## NPC state / takedowns

Location target: `tests/npc/` or `tests/combat/`, chosen when the first implementation exists.

Planned coverage:

- conscious → unconscious transition
- conscious → dead transition
- unconscious/dead NPC no longer runs normal guard AI
- knockout eligibility
- stealth-kill eligibility
- body pickup/release ownership
- mission kill/knockout counters when statistics exist

## Mission / objectives / campaign state

Location target: `tests/mission/`

This area should receive strong automated coverage because the behavior is mostly deterministic and regressions may otherwise appear much later.

Planned coverage:

- objective activation/completion/failure
- objective cannot complete twice
- mission cannot finish before required objectives
- mission can finish once required conditions are satisfied
- loot/kill/knockout/detection statistics count correctly
- campaign facts set/read correctly
- later-mission condition queries respond to previous actions
- save/load round-trip preserves campaign facts
- missing/older save data follows the chosen compatibility rule

## Inventory / tools

Location target: `tests/items/`

Planned coverage:

- add/remove/select item
- quantity and consumption rules
- healing clamps correctly
- mine placement/trigger state
- bomb/gas/flash eligibility/radius/line-of-effect rules when deterministic

Effects that depend on visual readability or subjective timing still require manual playtesting.

## Combat

Location target: `tests/combat/`

Planned coverage:

- deterministic damage outcomes
- lethal vs nonlethal result
- block rules
- parry timing-window boundaries once the chosen window is intentional
- duplicate hit prevention / invulnerability windows if part of final implementation

Do not use automated tests to decide whether a parry window feels good; use them to preserve the selected behavior after tuning.

---

# Manual playtesting remains mandatory

Automated tests cannot answer whether:

- movement feels good
- mantle feels too magnetic
- guards notice the player too abruptly
- suspicion/search pacing feels fair
- a room is fun to infiltrate
- combat feedback is satisfying
- UI is readable without being distracting
- lighting matches the intended visual language
- a mission has interesting routes

Those decisions remain part of the normal implementation → local test → playtest → feedback loop.

---

# Local regression workflow

For a normal gameplay-code change:

1. Run the most relevant focused suite while implementing.
2. Before considering the item technically complete, run the full available regression barrier.
3. Playtest the feature manually.
4. If a reproducible bug is found, first create or define the smallest fixture that can reproduce it, then fix the bug and keep the test.
5. If only feel is wrong, tune behavior without inventing a fake pass/fail assertion for subjective feedback.

For current movement work, the full available automated barrier is:

```powershell
godot --headless --path . --script res://tests/movement/run_movement_tests.gd
```

---

# CI policy

GitHub Actions should be added only after the local suites are deterministic.

Initial CI target:

- use the exact Godot version used by the project
- run headlessly
- execute the same command used locally
- run on pushes to `test`
- run on pull requests
- fail the job on nonzero test exit

When multiple suites exist, CI should call the single authoritative all-tests entry point rather than duplicating suite commands in workflow YAML.

Only consider making the CI check required after it has proven stable and non-flaky.

---

# Test-plan maintenance

Update this document when:

- a new suite is introduced
- an important regression test is added or removed
- a system’s testing strategy changes materially
- a former manual invariant becomes automated
- a feature is removed from the game and its planned coverage is no longer relevant

Do not turn this document into a list of every assertion line. It should explain the behaviors the test barrier protects and the testing strategy for upcoming systems.
