# Vark Testing

This document is the single source of truth for how Vark is verified. It records testing conventions, authoritative local commands, automated coverage that actually exists, broad manual regression checks, and CI policy.

Planned tests for unimplemented features belong in the matching item of `DEVELOPMENT_PLAN.md`; this document should not duplicate speculative future coverage.

## Testing principle

Automate objective, deterministic behavior that is costly or annoying to rediscover manually. When a reproducible gameplay bug is fixed, keep a regression test if the bug can reasonably be recreated in a deterministic fixture.

Do not automate subjective feel, pacing, readability, atmosphere, animation quality, level fun, or artistic judgment. Those are accepted through playtesting and feedback in chat.

Do not add tests merely to increase test count. Every automated test should protect a meaningful invariant or a previously broken behavior.

## Test design rules

1. Prefer real gameplay objects and real Godot physics where practical.
2. Keep fixtures minimal: only the actors/geometry needed to reproduce the behavior.
3. Assert semantic gameplay state rather than private helper call order.
4. Use fixed transforms, fixed input, physics-frame progression, and deterministic configuration.
5. Avoid real-time sleeps, render-FPS dependence, uncontrolled randomness, and broad timing windows that hide instability.
6. Release simulated input and free fixture state between tests.
7. Assert the original regression boundary, not merely an eventual outcome.
8. Do not freeze temporary tuning into tests unless the value/relationship is an intentional design contract.
9. Existing relevant suites must remain green when behavior is intentionally unchanged.
10. A flaky test or flaky system must be stabilized before it is used as a CI gate.

Small read-only semantic query methods are acceptable when tests need meaningful state such as grounded, alert, open/closed, or objective-complete without taking control of implementation internals.

## Current local automated barrier

Run from the project root:

```powershell
godot --headless --path . --script res://tests/movement/run_movement_tests.gd
```

Expected result: exit code `0` and `ALL MOVEMENT TESTS PASSED`.

Harness failure-path check:

```powershell
godot --headless --path . --script res://tests/movement/run_movement_tests.gd -- --intentional-failure
```

Expected result: nonzero exit code and the intentional failure reported.

The movement runner currently:

- executes real Godot physics;
- uses the real `Player.tscn` where player behavior is under test;
- aggregates failures rather than stopping at the first assertion;
- exits `0` on success and nonzero on failure;
- releases simulated input between fixtures.

When more than one real test suite exists, add one authoritative `tests/run_all_tests.gd` (or equivalent) and make local full-regression/CI use that entry point.

## Current automated coverage

### Framework sanity

Confirms the runner and assertion collector execute and report normally.

### Walk-off edge support refresh

Protects against grounded/support state remaining stale for one frame after a collision-free move off an edge. Once the capsule is physically clear of the platform on a completed movement frame, the player must already be airborne.

### Sprint-jump inherited momentum

Protects against airborne movement clamping inherited sprint speed down to ordinary run/air speed. The fixture first proves the player is moving faster than normal running speed, then verifies takeoff preserves that inherited horizontal speed within the intended tolerance.

### Normal step

Protects ordinary grounded step acquisition and crossing using real player movement and collision geometry.

### Floating / undercut step

Protects a valid support-to-support step where the blocker does not extend down to the source floor. Step logic must not require an artificial floor-connected riser.

### Wall-seam unsupported fall

Protects against modular wall seams or convex contacts cancelling unsupported vertical falling motion or manufacturing ground support.

### Multi-contact fall

Protects against simultaneous wall contacts manufacturing support or cancelling unsupported downward motion.

## Manual regression policy

Per-item manual acceptance belongs in `DEVELOPMENT_PLAN.md`. The checklist below is a broader integration pass for substantial player-controller/traversal changes; it is not required after every small unrelated change.

As new major systems become real, add concise manual regression sections here only when they provide broad integration value. Do not create a separate checklist document for every feature.

### Project load / player scene

- [ ] Project reopens without new missing-script, parser, global-class, UID, or player-code errors.
- [ ] `Player.tscn` loads and spawns normally.
- [ ] No unexpected resource/UID churn appears after a normal project rescan.

### Input and look

- [ ] Walk in all four directions and diagonally.
- [ ] Mouse look and mouse capture/release behave normally.
- [ ] Combined movement, jump, crouch, and sprint inputs do not create stale one-frame states.

### Ground, support, slopes, and falling

- [ ] Walk/sprint/start/stop normally on flat ground.
- [ ] Walk up, down, and across representative walkable slopes; standing still does not slide unexpectedly.
- [ ] Land normally from jumps and longer falls.
- [ ] Narrow beams/edges support the capsule when physically valid.
- [ ] Rubbing walls, modular seams, and convex edges while falling does not stick, launch, or create fake support.

### Steps

- [ ] Climb representative valid steps straight-on, diagonally, and while strafing onto them.
- [ ] Strafing along a riser without inward motion does not spuriously start a step.
- [ ] Wall seams near foot height are not treated as steps.
- [ ] Jumping/falling into step geometry does not create an airborne step.
- [ ] Steps from slopes/other valid source support do not introduce unexpected height changes.
- [ ] Representative heights up to the configured maximum work.
- [ ] Blocked overhead/crossing routes do not force the capsule through geometry.

### Crouch, sprint, jump, and air control

- [ ] Crouch/stand repeatedly; standing remains blocked under low clearance until space exists.
- [ ] Crouch movement and sprint movement remain distinct and usable.
- [ ] Jump from standstill, walking, and sprinting.
- [ ] Jump releases support cleanly and ascent is not immediately re-grounded.
- [ ] Air steering, reversal, and landing remain coherent.
- [ ] Held/released jump does not leave stale mantle-intent behavior across attempts.

### Ledge grab / hang / traversal

- [ ] Grab a normal ledge from a jump and while falling alongside valid geometry.
- [ ] Hang without unexpected support/step transitions.
- [ ] Shimmy both directions and traverse representative supported corners.
- [ ] Directional, sprint-directional, and no-input hang jumps release cleanly.
- [ ] Jump/drop/failed catch/failed mantle suppression prevents immediate illegitimate regrab/retry but later legitimate attempts still work.

### Mantle

- [ ] Ground-requested mantle starts only from a valid contacted ledge.
- [ ] Airborne jump-hold mantle buffering works.
- [ ] Mantle a normal wide platform and supported thin geometry.
- [ ] Crouch-clearance mantle cases behave as intended.
- [ ] Invalid landing surfaces are rejected once that behavior is implemented.
- [ ] Successful mantle does not sink, stick, fall through, snap backward, or preserve unintended player velocity.
- [ ] Walking/jumping from the resulting support works normally.

### Velocity / collision integration

- [ ] Traversal entry/release does not leave stale locomotion velocity.
- [ ] Valid landings terminate downward controlled velocity only after support is actually validated.
- [ ] Unsupported collision response does not create displacement longer than requested motion or turn tiny downward motion into a large sideways launch.

If a broad manual regression item changes intentionally, update the checklist so it describes the new accepted behavior rather than preserving obsolete behavior forever.

## CI policy

Add GitHub Actions only after the local suite it will run is deterministic.

CI should:

- use the exact project Godot version;
- run headlessly;
- call the same authoritative command used locally;
- run on pushes to `test` and pull requests;
- fail on nonzero test exit.

When multiple suites exist, CI should call the single all-tests entry point rather than duplicating suite commands in workflow YAML.

Only consider making a CI check required after it has proven stable and non-flaky.

## Maintenance

The agent updates this file automatically during authorized repository patches when:

- a meaningful automated regression test is added, removed, or changes what it protects;
- the authoritative test command changes;
- a new real suite is introduced;
- broad manual regression coverage needs to change;
- CI/testing strategy materially changes.

Do not turn this file into a line-by-line mirror of test code. It should describe the verification contract at the behavior level.