# Vark Testing

This document is the single source of truth for how Vark is verified. It records testing conventions, authoritative local commands, automated coverage that actually exists, broad manual regression checks, and CI policy.

Planned tests for unimplemented features belong in the matching item of `DEVELOPMENT_PLAN.md`; this document should not pretend future coverage already exists.

---

# Testing principle

Automate objective, deterministic behavior that is costly or annoying to rediscover manually.

When a reproducible gameplay bug is fixed, keep a regression test if the bug can reasonably be recreated in a deterministic fixture.

Do not automate subjective feel, pacing, readability, atmosphere, animation quality, level fun, or artistic judgment. Those are accepted through playtesting and feedback in chat.

Do not add tests merely to increase test count. Every automated test should protect a meaningful invariant or previously broken behavior.

Systemic features require **integrated proof**, not only isolated unit proof. A door is not complete because it animates; a save system is not complete because it serializes data; an acoustic system is not complete because a distance check passes.

For cross-cutting systems, test ownership and failure boundaries as aggressively as happy paths. A restore that fails safely is part of save correctness; a torn-down world that cannot affect its replacement is part of lifecycle correctness; a snapshot whose fields all describe the same semantic instant is part of save correctness.

---

# Decision-state relationship

- **LOCKED** behavior should receive regression protection where deterministic.
- **TARGET** behavior may be tested during prototyping, but tests must not accidentally make an unvalidated design permanent.
- **OPEN** behavior should first use focused fixtures to discover the correct model; once accepted, convert the meaningful invariants into regressions.

---

# Player-controller testing contract

The current player movement/look/traversal **behavior and feel are accepted and LOCKED**.

The controller's implementation is **not** frozen.

Refactors may change:

- how Godot input is sampled
- command routing
- pause/cutscene/UI gating
- component ownership
- mouse-capture ownership
- internal class/scene structure
- test-input injection

provided the same accepted player-facing behavior remains.

Tests therefore protect semantic results, not private call order.

For large controller/input refactors, prefer a command/behavior trace approach:

```text
same initial fixture
+ same semantic locomotion command sequence
≈ same position/velocity/stance/traversal/support/look result
```

Use intentional numeric tolerances where floating-point/physics behavior requires them. Do not demand meaningless byte-identical internal state.

The locomotion trace is not the universal input API. Interaction, combat, and inventory should receive separate semantic domains as they become real; tests should prove application-level gating without requiring the locomotion controller to understand menus/cutscenes.

---

# Test design rules

1. Prefer real gameplay objects and real Godot physics where practical.
2. Keep fixtures minimal: only the actors/geometry needed to reproduce the behavior.
3. Assert semantic gameplay state rather than private helper call order.
4. Use fixed transforms, fixed input/commands, physics-frame progression, and deterministic configuration.
5. Avoid real-time sleeps, render-FPS dependence, uncontrolled randomness, and broad timing windows that hide instability.
6. Release simulated input and free fixture/world-session state between tests.
7. Assert the original regression boundary, not merely an eventual outcome.
8. Do not freeze temporary tuning into tests unless the value/relationship is an intentional design contract.
9. Existing relevant suites must remain green when behavior is intentionally unchanged.
10. A flaky test or flaky system must be stabilized before it becomes a CI gate.
11. Test integrated state transitions at subsystem boundaries where bugs are likely to appear: world teardown/replacement, restore/startup, doors/nav/sound, perception/knowledge, authored IDs/reimport, props/support.
12. Prefer explicit test maps/fixtures for spatial systems over hidden hard-coded geometry assumptions.
13. Save/load tests must assert coherent snapshot capture, absence of duplicate consequences, failed-transaction safety, and compatibility refusal—not only equality of serialized fields.
14. Performance fixtures should report measured cost/scale and the reference tool/runtime environment; do not invent premature micro-budgets without measurement.
15. Event-system tests must assert ordering and lifecycle behavior rather than relying on incidental signal/call-stack order.
16. Persistence tests must distinguish authored-present, authored-removed, and runtime-created objects whenever those cases exist while keeping authored-removed as state of an authored identity rather than a third identity kind.
17. Input tests must distinguish continuous held state from one-frame edge intent and prove disabled domains do not replay stale edges on resume.
18. Save-capture tests must verify one immutable snapshot is copied at a stable semantic boundary; asynchronous/deferred file encoding must not read live gameplay objects after capture.
19. Candidate-load tests must prove the active/frozen old world and non-playing candidate cannot both participate in authoritative gameplay services.

Small read-only semantic query methods are acceptable when tests need meaningful state such as grounded, alert, open/closed, objective-complete, audible, supported, restoring, world-session generation, stable-boundary state, or persistence identity.

---

# Current local automated barrier

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

---

# Current automated coverage

The following coverage exists now.

## Framework sanity

Confirms the runner and assertion collector execute and report normally.

## Walk-off edge support refresh

Protects against grounded/support state remaining stale for one frame after a collision-free move off an edge. Once the capsule is physically clear of the platform on a completed movement frame, the player must already be airborne.

## Sprint-jump inherited momentum

Protects against airborne movement clamping inherited sprint speed down to ordinary run/air speed. The fixture first proves the player is moving faster than normal running speed, then verifies takeoff preserves that inherited horizontal speed within the intended tolerance.

## Normal step

Protects ordinary grounded step acquisition and crossing using real player movement and collision geometry.

## Floating / undercut step

Protects a valid support-to-support step where the blocker does not extend down to the source floor. Step logic must not require an artificial floor-connected riser.

## Wall-seam unsupported fall

Protects against modular wall seams or convex contacts cancelling unsupported vertical falling motion or manufacturing ground support.

## Multi-contact fall

Protects against simultaneous wall contacts manufacturing support or cancelling unsupported downward motion.

No other future-system coverage described below should be reported as existing until the tests are actually implemented.

---

# Required future fixture strategy

These fixture requirements become active when the corresponding systems are implemented.

## Controller behavior-trace fixture

Purpose: permit internal input/controller refactors without changing accepted feel.

Protect representative traces for:

- walk/start/stop
- sprint
- crouch
- jump/sprint-jump
- representative step
- ledge catch/hang/release
- representative shimmy/corner/mantle where deterministic

The trace should compare semantic state, not private component internals.

## World-session lifetime fixture

Purpose: prove application ownership is complete across startup, pause, teardown, restart, load replacement, and promotion.

Protect:

- BUILDING/non-playing startup produces no ordinary gameplay consequences;
- a session becomes PLAYING only through application ownership;
- teardown stops/discards world-owned event queues, gameplay timers, registries, and representative deferred work;
- a stale callback/event/timer from the old session cannot mutate the replacement session;
- restart creates fresh world state;
- pause follows one explicit simulation policy, not just input suppression;
- quickload freezes/stops ordinary gameplay in the old world while an isolated candidate is restored;
- candidate registries/events/timers remain candidate-local before promotion;
- old and candidate worlds never both produce authoritative gameplay consequences;
- candidate failure leaves one coherent application-owned recovery state and leaks no work into the old/current/next world.

A generation/session-token implementation may be tested if used, but protect the semantic outcome rather than the token itself.

## Input-domain fixture

Prove:

- accepted locomotion behavior is preserved through the semantic input boundary;
- application ownership can suppress gameplay input without private locomotion changes;
- as domains arrive, interaction/combat/inventory input is not forced through the locomotion `PlayerCommand` object;
- one semantic input frame maps to one gameplay simulation tick;
- held state may persist only while physically/currently held and permitted;
- pressed/released edge intent exists for one semantic frame only;
- pause/UI/cutscene/teardown/world-replacement gating clears transient edges rather than replaying stale one-frame gameplay intents on resume.

## Persistent-ID/reimport fixture

Prove:

- persistent IDs are unique;
- ordinary map move/reorder/reimport preserves identity;
- duplicate authored entities receive distinct identities;
- generated/repaired IDs are persisted back to the authoritative authored source and survive another reimport;
- running validation/import again on an already-valid source does not rewrite it or churn IDs;
- ID repair/writeback does not create an import/rewrite loop;
- a stale generated/imported representation cannot overwrite a newer authoritative authored edit;
- semantic `content_id` duplicates are rejected;
- missing semantic references report clearly.

## Gameplay-event/stable-boundary fixture

Before mission logic or save capture depends on the event path, prove:

- semantic events are owned by the current world session;
- emitted events process FIFO at the chosen controlled gameplay point;
- the same emitted sequence produces deterministic ordering;
- events emitted while processing append rather than recursively reordering dispatch;
- normal dispatch is disabled while BUILDING, RESTORING, and TEARING_DOWN;
- queued/stale events from a torn-down world cannot affect a replacement world;
- one completed semantic gameplay step drains its defined consequence pass before the stable gameplay boundary is reported;
- save capture requested mid-step occurs only after that stable boundary, not during a half-processed event/consequence state.

Do not freeze a broad event framework; freeze only these required semantics.

## Acoustic fixture

Use a tiny authored map containing at minimum:

- open room
- doorway
- closed door
- separated room
- L-shaped/corner corridor

Protect deterministic propagation relationships once the accepted acoustic model exists, such as:

- open connection transmits more than closed door;
- closed solid separation does not behave like open air;
- connected around-corner space can transmit according to the accepted model;
- audibility affects both guard hearing and world-space speech presentation consistently.

If the accepted model requires authored rooms/portals/zones/topology, the fixture/workflow must also prove ordinary mapper edit/reimport does not require fragile generated-output repair.

Do not freeze arbitrary numeric falloff values before they are accepted.

## Gameplay-light fixture

Use a small chamber for:

- darkness
- partial light
- full light
- behind/around occluder
- edge of influence
- multiple relevant lights

Automate only objective accepted relationships. Final subjective correspondence between rendered scene and light-gem feel still requires playtest.

## Door integration fixture

The same ordinary door should eventually be exercised for:

- interaction
- collision
- open/closed state
- lock/key state
- sight obstruction
- acoustic transmission
- NPC/nav traversal
- physical obstruction by prop where deterministic
- semantic events
- save/load state

Avoid separate fake door models per subsystem.

## Thief-style prop fixture

This behavior is LOCKED and deserves deterministic regression protection.

At minimum cover:

### Stable edge support

A settled box with valid support, even if visibly overhanging an edge, does not topple, rotate, slide, or fall merely because realistic torque would make it unstable.

### Stable stack

A settled stack remains stationary without wobble, drift, rolling, or spontaneous rotation.

### Support removal

Given:

```text
C supported by B
B supported by A
A supported by world
```

removing A causes the unsupported supported-group above to fall until supported.

The group must not explode, scatter, or topple as a side effect of unrestricted rigid-body simulation.

### Drop/throw/settle

A held object may be dropped/thrown, move/collide, then return to the settled stationary contract.

It must not continue indefinite rolling/sliding/spinning after the accepted settling condition.

### Save/load

A settled or transient representative prop state restores coherently without gaining extra motion.

## Nav/reimport fixture

Prove a representative imported map can:

- build/rebuild navigation
- spawn one NPC
- patrol
- use/route through an ordinary door
- survive a normal map edit/reimport workflow

This exists early to discover toolchain/nav incompatibility before large AI systems depend on it.

## Save snapshot/restore transaction fixture

Save and restore must be tested as semantic transactions, not merely data serialization.

### Capture

Prove:

- a save request may be made during ordinary active/transient gameplay;
- capture waits only until the next defined stable gameplay boundary rather than waiting for the world to become idle;
- current semantic event/consequence processing for the completed step is drained before capture;
- every save-owning system contributes to one immutable in-memory snapshot representing the same semantic instant;
- gameplay may resume after that snapshot copy is complete;
- later encoding/file writing consumes the immutable snapshot and does not continue querying mutable live gameplay objects.

A deterministic fixture should deliberately mutate several systems around a save request—such as door state/event, guard awareness, player/prop motion—and prove the restored result corresponds to one coherent boundary rather than a mixture of adjacent ticks.

### Restore

During restore, ordinary gameplay consequences must be suppressed until state application/reconciliation/validation are complete.

Deterministic tests should cover as systems exist:

- save header contains `save_format_version`, `mission_id`, and `mission_content_revision`;
- unsupported save-format version refuses clearly;
- unsupported mission-content revision refuses clearly;
- mission restart creates fresh state;
- save → restore round trip;
- authored removals/tombstones are applied before semantic state is applied to surviving objects;
- runtime-persistent objects are recreated/registered before their semantic state is applied;
- player transform/velocity/stance/relevant traversal state;
- door state/open fraction/lock state;
- prop state/support/transient motion;
- NPC semantic awareness/goal state;
- mission facts/objectives;
- mission-script custom state;
- no duplicate one-shot rule execution;
- no duplicate objective transitions;
- no duplicate loot/stat changes;
- no duplicate alarms/dialogue/events caused by loading;
- quickload prevents the old world from continuing ordinary gameplay while the candidate is restored;
- candidate world services remain isolated until promotion;
- a deliberately forced restore failure never promotes a partially restored candidate world;
- a failed candidate cannot leak stale events/timers/deferred work into the current/next session;
- a deliberately failed durable write does not intentionally replace the previous valid save with incomplete data.

## Removed-authored persistence fixture

Once authored objects can permanently disappear (for example collected loot), prove:

- the authored object's `persistent_id` is represented as removed/tombstoned state rather than creating a third identity kind;
- save after removal → restore keeps it absent;
- reloading does not grant duplicate loot/value or replay the collection consequence;
- absence is not inferred only from the current scene tree.

## Runtime-created persistence fixture

Once a runtime-created object must survive save/load (for example a deployable), prove:

- it receives a runtime persistent identity distinct from authored instances;
- save captures enough spawn/type provenance to recreate the correct object;
- semantic state is restored only after recreation/registration;
- duplicate/repeated restore does not create multiple copies;
- its lifecycle obeys normal world teardown/replacement ownership.

## Actor-state compatibility fixture

Before final combat exists, prove conscious/unconscious/dead states do not require replacing the guard identity/event/save model.

In particular, changing an actor into unconscious/dead/body behavior must preserve the same persistent identity and semantic actor reference even if runtime nodes/presentation are reorganized internally.

## Crude hostile compatibility fixture

Before stealth architecture is hardened, exercise one deliberately crude hostile path:

```text
attack intent
→ semantic hostile effect
→ actor/life-state consequence
→ gameplay event and gameplay sound
→ other AI/perception reaction where applicable
→ save
→ restore
```

The test protects reuse of the real input-domain, actor, event, world-session, perception, and persistence contracts. It must not lock combat damage numbers, timings, animations, weapon feel, or Phase 9 design.

## Mission fact/rule fixture

Once the rule system exists:

- fact type/default/scope validation;
- invalid fact assignment rejection/reporting;
- deterministic rule ordering relative to the gameplay-event queue;
- one-shot vs repeat behavior;
- rule state persistence through save/load;
- missing entity references report clearly.

---

# Manual regression policy

Per-item manual acceptance belongs in `DEVELOPMENT_PLAN.md`.

The checklist below is the broad integration pass for changes that could affect accepted player behavior. It is not required after every unrelated docs or gameplay change.

As new major systems become real, add concise manual regression sections here only when they provide broad integration value.

---

# Player manual regression checklist

## Project load / player scene

- [ ] Project reopens without new missing-script, parser, global-class, UID, or player-code errors.
- [ ] `Player.tscn` loads and spawns normally.
- [ ] No unexpected resource/UID churn appears after a normal project rescan.

## Input and look

- [ ] Move in all four directions and diagonally.
- [ ] Mouse look and mouse capture/release behave normally.
- [ ] Combined movement, jump, crouch, and sprint inputs do not create stale one-frame states.
- [ ] After input-router refactors, pause/UI/cutscene ownership suppresses gameplay input without changing resumed gameplay feel.
- [ ] Interaction/combat/inventory domains, once present, do not alter ordinary locomotion command semantics.
- [ ] Press/release actions performed while their domain is disabled do not fire later when gameplay resumes.

## Pause / world ownership

When Phase 1 exists:

- [ ] Pausing suppresses ordinary gameplay simulation according to the defined application policy, not only player input.
- [ ] Resume does not cause queued/stale gameplay intents, timers, or events to burst unexpectedly.
- [ ] Restart/mission replacement does not visibly receive effects from the previous world session.

## Ground, support, slopes, and falling

- [ ] Move/sprint/start/stop normally on flat ground.
- [ ] Move up, down, and across representative walkable slopes; standing still does not slide unexpectedly.
- [ ] Land normally from jumps and longer falls.
- [ ] Narrow beams/edges support the capsule when physically valid.
- [ ] Rubbing walls, modular seams, and convex edges while falling does not stick, launch, or create fake support.

## Steps

- [ ] Climb representative valid steps straight-on, diagonally, and while strafing onto them.
- [ ] Strafing along a riser without inward motion does not spuriously start a step.
- [ ] Wall seams near foot height are not treated as steps.
- [ ] Jumping/falling into step geometry does not create an airborne step.
- [ ] Steps from slopes/other valid source support do not introduce unexpected height changes.
- [ ] Representative heights up to the configured maximum work.
- [ ] Blocked overhead/crossing routes do not force the capsule through geometry.

## Crouch, sprint, jump, and air control

- [ ] Crouch/stand repeatedly; standing remains blocked under low clearance until space exists.
- [ ] Crouch movement and sprint movement remain distinct and usable.
- [ ] Jump from standstill, ordinary movement, and sprinting.
- [ ] Jump releases support cleanly and ascent is not immediately re-grounded.
- [ ] Air steering, reversal, and landing remain coherent.
- [ ] Held/released jump does not leave stale mantle-intent behavior across attempts.

## Ledge grab / hang / traversal

- [ ] Grab a normal ledge from a jump and while falling alongside valid geometry.
- [ ] Hang without unexpected support/step transitions.
- [ ] Shimmy both directions and traverse representative supported corners.
- [ ] Directional, sprint-directional, and no-input hang jumps release cleanly.
- [ ] Jump/drop/failed catch/failed mantle suppression prevents immediate illegitimate regrab/retry but later legitimate attempts still work.

## Mantle

- [ ] Ground-requested mantle starts from the same accepted contact/intent situations as the current controller.
- [ ] Airborne jump-hold mantle buffering behaves as currently accepted.
- [ ] Mantle a normal wide platform and supported thin geometry as currently accepted.
- [ ] Crouch-clearance mantle cases behave as currently accepted.
- [ ] Successful mantle does not sink, stick, fall through, snap backward, or preserve unintended player velocity.
- [ ] Walking/jumping from the resulting support works normally.

## Velocity / collision integration

- [ ] Traversal entry/release does not leave stale locomotion velocity.
- [ ] Valid landings terminate downward controlled velocity only after support is actually validated.
- [ ] Unsupported collision response does not create displacement longer than requested motion or turn tiny downward motion into a large sideways launch.

If the user explicitly reopens and changes a player movement/traversal behavior, update this checklist and automated regressions to the newly accepted contract rather than preserving obsolete behavior.

---

# Future integrated manual acceptance

When these systems exist, their phase gates should include representative playtests.

## Acoustic/speech

- [ ] Footsteps/impacts are intuitively affected by doors/openings/connected spaces.
- [ ] Stopping and listening provides useful positional information.
- [ ] Typed speech remains visible above an NPC through visual cover when it should be audible.
- [ ] Distant/marginal speech presentation fades as intended.
- [ ] Inaudible speech is not shown.
- [ ] If acoustic topology is mapper-authored, normal map editing/reimport remains understandable and low-friction.

## Gameplay lighting

- [ ] Light gem agrees intuitively with what the player sees across dark/partial/full/occluded cases.
- [ ] Decorative visual brightness does not accidentally create wrong stealth exposure.
- [ ] Switching/extinguishing a gameplay light updates exposure coherently.

## Thief-style props

- [ ] Edge-supported props look intentionally stable rather than "broken physics."
- [ ] Stacks remain motionless while supported.
- [ ] Pulling a lower support causes upper supported objects to fall without the stack exploding/scattering.
- [ ] Dropped/thrown props settle cleanly and stop.
- [ ] Props remain useful for stacking/climbing/door obstruction.

## Save/load

- [ ] Quicksave can be requested during ordinary active/transient gameplay and completes without requiring the world to become idle.
- [ ] A loaded quicksave reflects one coherent gameplay instant rather than mixed before/after state across doors, AI, objectives, props, etc.
- [ ] Representative transient states restore coherently.
- [ ] Loading does not visibly replay objective/loot/alarm/dialogue consequences.
- [ ] The old world does not visibly continue simulating while quickload constructs/restores the candidate world.
- [ ] Restored world resumes from the saved state rather than briefly simulating a fresh start first.
- [ ] An incompatible mission-content revision produces a clear refusal rather than a partially wrong world.
- [ ] A failed load leaves the application in a coherent recoverable state.
- [ ] A failed save attempt does not intentionally destroy the previous valid quicksave.

## Combat

Before combat becomes LOCKED, playtest:

- [ ] one guard
- [ ] two guards
- [ ] tight corridor
- [ ] open room
- [ ] stealth-to-combat transition
- [ ] lethal assault
- [ ] nonlethal assault
- [ ] retreat/break contact

Subjective combat feel is accepted by the user, not inferred from the earlier crude architecture-compatibility proof or deterministic tests.

---

# Performance-testing policy

Do not wait for the final representative mission before checking expensive-system scaling.

When each system becomes real, add a focused stress fixture and record representative measurements for:

- gameplay exposure with many relevant lights;
- many guards performing vision checks;
- many semantic sounds/hearing receivers;
- nav/path updates around changing doors;
- mission-event/rule bursts;
- save snapshot capture time, encoded size, and durable-write time as separate measurements where useful;
- prop support checks;
- runtime-created persistent objects if/when they become real.

Record the exact supported Godot/runtime configuration and enough reference-machine information to make later comparisons meaningful.

The purpose is early architectural warning, not premature optimization.

The later production-scale mission remains the final realistic performance proof.

---

# CI policy

Add GitHub Actions only after the local suite it will run is deterministic.

Under the repository's current GitHub workflow, `test` is the integration branch and authorized changes are written directly to it. Therefore CI on `test` is **post-push integration validation**, not a fictional pre-push safety gate.

CI should:

- use the exact supported project Godot/runtime configuration;
- run headlessly;
- call the same authoritative command used locally;
- run immediately on pushes to `test` and on pull requests if pull requests are used for other repository workflows;
- fail on nonzero test exit.

When multiple suites exist, CI should call one all-tests entry point rather than duplicating suite commands in workflow YAML.

A newly uploaded implementation commit is not accepted merely because it reached `test`. Keep the corresponding roadmap work `[~]` until the relevant CI/local automated validation is green and required manual/user validation is accepted.

Do not describe a `test` status check as a pre-merge/pre-push protection requirement while repository policy forbids helper branches and writes directly to `test`. If repository workflow changes later, CI protection policy may be revisited explicitly.

---

# Maintenance

The agent updates this file automatically during authorized repository patches when:

- meaningful automated regression coverage is added/removed/changed;
- the authoritative test command changes;
- a new real suite is introduced;
- broad manual regression coverage changes;
- CI/testing strategy materially changes;
- an OPEN/TARGET system becomes LOCKED and needs permanent verification rules.

Do not turn this file into a line-by-line mirror of test code. It should describe the verification contract at the behavior level.
