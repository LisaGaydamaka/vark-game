# Vark Testing

This document is the single source of truth for how Vark is verified. It records testing conventions, authoritative local commands, automated coverage that actually exists, broad manual regression checks, and CI policy.

Planned tests for unimplemented features belong in the matching roadmap item and future-fixture sections below; this document must not pretend future coverage already exists.

---

# Testing principle

Automate objective, deterministic behavior that is costly or annoying to rediscover manually.

When a reproducible gameplay bug is fixed, keep a regression test if it can reasonably be recreated deterministically. Prefer a regression that exercises the real production failure path and would fail against the pre-fix behavior rather than one that only proves a new helper works.

Do not automate subjective feel, pacing, readability, atmosphere, animation quality, level fun, or artistic judgment. Those remain playtest/user acceptance.

Do not add tests merely to increase test count. Every automated test should protect a meaningful invariant, failure boundary, or previously broken behavior.

An automated test does not count as coverage merely because a test file exists. It must be reachable from the appropriate authoritative local/CI entry point. When a second independent suite appears, introduce/update one all-tests entry point and make local full-regression/CI use it in the same coherent patch.

If a roadmap/fixture contract expects a named deterministic case “where practical” and that case cannot currently be automated credibly, record the exact case, why trustworthy automation is not practical yet, and the focused manual/integrated acceptance that covers the gap. Do not silently omit the case or weaken `Done when:`.

Systemic features require **integrated proof**, not only isolated unit proof. A door is not complete because it animates; a save system is not complete because it serializes data; an acoustic system is not complete because one distance check passes.

For cross-cutting systems, test ownership and failure boundaries as aggressively as happy paths. A restore that fails safely is part of save correctness; a torn-down world that cannot affect its replacement is part of lifecycle correctness; a detached snapshot that cannot mutate with the live world is part of save correctness.

---

# Decision-state relationship

- **LOCKED** behavior should receive regression protection where deterministic.
- **TARGET** behavior may be tested during prototyping, but tests must not accidentally make an unvalidated design permanent.
- **OPEN** behavior should first use focused fixtures to discover the correct model; once accepted, convert meaningful invariants into regressions.

---

# Player-controller testing contract

Current player movement/look/traversal **behavior and feel are accepted and LOCKED**. Implementation is not frozen.

Refactors may change input sampling, command routing, pause/cutscene/UI gating, component ownership, mouse capture, internal scene/class structure, and test-input injection, provided accepted player-facing behavior remains.

Tests protect semantic results, not private call order.

For large locomotion/input refactors, prefer command/behavior traces:

```text
same initial fixture
+ same semantic locomotion command sequence
≈ same position/velocity/stance/traversal/support result
```

Use intentional numeric tolerances where physics requires them.

The locomotion trace is not a universal input API. Interaction, combat, and inventory use separate world-gameplay intent domains as they become real.

The one-frame-per-gameplay-tick contract applies to **world gameplay intent**, not every input path. Accepted mouse-look response may remain event-driven and should not be forced into physics-tick latency merely for architectural uniformity. Treat the resulting view pose as input-owned state: world gameplay samples it in the controlled simulation pass, and save capture may synchronously capture it at the stable boundary. UI/menu input is application input and may operate independently of world simulation.

---

# Test design rules

1. Prefer real gameplay objects and real Godot physics where practical.
2. Keep fixtures minimal: only the actors/geometry needed to reproduce the behavior.
3. Assert semantic gameplay state rather than private helper call order.
4. Use fixed transforms, fixed gameplay intent/commands, physics-frame progression, and deterministic configuration.
5. Avoid real-time sleeps, render-FPS dependence, uncontrolled randomness, and broad timing windows that hide instability. When gameplay intentionally uses randomness, inject deterministic choices for tests and verify already-resolved choices survive restore rather than rerolling.
6. Release simulated input and free fixture/world-session state between tests.
7. Assert the original regression boundary, not merely an eventual outcome.
8. Do not freeze temporary tuning unless it is an intentional design contract.
9. Existing relevant suites remain green when behavior is intentionally unchanged.
10. Stabilize flaky tests/systems before making them CI gates.
11. Test integrated boundaries likely to fail: world replacement, restore/startup, doors/nav/sound, perception/knowledge, authored IDs/reimport, props/support.
12. Prefer explicit test maps/fixtures for spatial systems over hidden hard-coded geometry assumptions.
13. Save/load tests assert coherent detached capture, source-session ownership, no duplicate consequences, failed-transaction safety, slot ordering, and compatibility refusal—not merely serialized-field equality.
14. Performance fixtures report measured cost/scale and reference environment; do not invent premature micro-budgets.
15. Event tests assert emitted-order FIFO, lifecycle behavior, synchronous drain, and runaway-cascade handling rather than incidental signal/call-stack order.
16. Do not assert a global deterministic order for unrelated physics discoveries unless gameplay explicitly defines a semantic tie-breaker.
17. Persistence tests distinguish authored-present, authored-removed, and runtime-created cases while keeping authored-removed as state of authored identity.
18. Gameplay-input tests distinguish continuous held state from one-frame edges, prove disabled domains do not replay stale edges, and prove domain loss cancels incomplete gestures that depend on a future edge.
19. Save-capture tests prove snapshot data is detached/value-owned: mutating live state after capture cannot mutate the captured snapshot.
20. World-session tests prove shared authored/config Resources and autoload/application state do not become accidental mutable mission-state bridges across sessions.
21. Durable world-semantic mutation must be tested at the controlled gameplay-step/consequence boundary. Engine callbacks outside it may update presentation/input-owned view pose or enqueue future work, not race persistent gameplay truth.
22. Mission-script tests must prove supported mutation commands cannot bypass the controlled gameplay boundary when invoked from `_process()`, arbitrary signals, or async continuations.
23. Gameplay-time tests use world simulation time, not wall-clock elapsed time through pause/load.
24. Long-running saveable behavior is tested through explicit semantic stage/progress/remaining-time state, not serialized engine timers/coroutine stacks.
25. Each semantic fact has one authoritative owner; tests should not require generic mission facts to mirror system-owned state or become premature campaign storage.
26. Compatibility tests distinguish global `save_format_version` semantic compatibility from authored `mission_content_revision` compatibility.
27. Runtime-persistence tests prove restored IDs remain reserved and cannot collide with later runtime-created objects.
28. Campaign-progression tests, once campaign state exists, must prove completion consequences are applied exactly once and stale in-mission saves cannot silently load against an already-advanced campaign baseline.
29. New deterministic tests must be wired into the authoritative suite/entry point that actually runs locally and in CI; orphan test files are not coverage.
30. For deterministic bug regressions, verify the test exercises the original production boundary and, where practical, would fail against the pre-fix behavior.

Small read-only semantic query methods are acceptable when tests need meaningful state such as grounded, alert, open/closed, objective complete, audible, supported, restoring, world generation, stable-boundary state, gameplay time, player view pose, or persistence identity.

---

# Current local automated barrier

After a fresh clone, after deleting `.godot/`, or whenever Godot's generated project metadata/class registry is absent, initialize the project once from the project root:

```powershell
godot --headless --path . --import
```

Then run the authoritative movement barrier from project root:

```powershell
godot --headless --path . --script res://tests/movement/run_movement_tests.gd
```

Expected result: exit code `0` and `ALL MOVEMENT TESTS PASSED`.

The import bootstrap is not required before every ordinary local test run when the project has already been imported successfully; it exists so a clean checkout follows the same reproducible startup path used by CI.

Harness failure-path check:

```powershell
godot --headless --path . --script res://tests/movement/run_movement_tests.gd -- --intentional-failure
```

Expected result: nonzero exit code and intentional failure reported.

The movement runner currently:

- executes real Godot physics;
- uses the real `Player.tscn` where player behavior is under test;
- aggregates failures rather than stopping at first assertion;
- exits `0` on success and nonzero on failure;
- releases simulated input between fixtures.

Every new movement regression must be added to the movement runner (directly or through a suite it invokes), so the authoritative command and CI actually execute it. When more than one independent real suite exists, add one authoritative `tests/run_all_tests.gd` (or equivalent), switch local full-regression and CI to that entry point in the same patch, and keep individual suite commands only for focused diagnosis.

---

# Automated acceptance evidence outside CI

A green authoritative CI run proves only what that barrier actually executes.

Every required `Automated:` criterion that is not continuously covered by CI must either:

- have a documented command/fixture/workflow that a fresh agent can rerun; or
- when it is inherently a one-time authoring/tool workflow proof rather than a useful continuous CI gate, have the procedure, observed result, and relevant supported tool/runtime/environment recorded in the roadmap/testing documentation when it is accepted.

Do not use unrelated green CI as a substitute for these checks.

If relevant CI exists but its result cannot be retrieved/verified, report it as unverified and keep any CI-dependent roadmap item `[~]`; never infer success from the absence of a visible failure.

---

# Current automated coverage

The following coverage exists now.

## Framework sanity

Confirms the runner/assertion collector execute and report normally.

## Walk-off edge support refresh

Protects against grounded/support state remaining stale for one frame after a collision-free move off an edge.

## Sprint-jump inherited momentum

Protects against airborne movement clamping inherited sprint speed down to ordinary run/air speed.

## Normal step

Protects ordinary grounded step acquisition/crossing using real movement/collision geometry.

## Floating / undercut step

Protects a valid support-to-support step where the blocker does not extend to the source floor.

## Wall-seam unsupported fall

Protects against wall seams/convex contacts cancelling unsupported falling motion or manufacturing ground support.

## Multi-contact fall

Protects against simultaneous wall contacts manufacturing support or cancelling downward motion.

No future-system coverage below should be reported as existing until actually implemented.

---

# Required future fixture strategy

These requirements become active when corresponding systems are implemented.

## Controller behavior-trace fixture

Protect representative locomotion traces for walk/start/stop, sprint, crouch, jump/sprint-jump, representative step, ledge catch/hang/release, and representative shimmy/corner/mantle where deterministic.

Compare semantic results, not private component internals.

Protect accepted mouse-look response separately where needed; do not make event-driven look wait for a gameplay/physics frame simply to fit locomotion trace machinery. Also prove the current event-driven view pose can be sampled/captured coherently at a stable gameplay boundary without changing accepted input response.

## World-session lifetime fixture

Phase 1 proves ownership across startup, pause, stop, teardown, restart, and ordinary replacement:

- BUILDING/non-playing startup produces no ordinary gameplay consequences;
- session becomes PLAYING only through application ownership;
- application can stop/freeze ordinary world gameplay coherently;
- teardown stops/discards world-owned event queues, gameplay timers, registries, and representative deferred work;
- stale callbacks/events/timers from old session cannot mutate replacement;
- restart creates fresh world state;
- pause follows one explicit simulation policy, not only input suppression;
- shared authored/config Resources do not carry mutable runtime state from one world session into another;
- autoload/application owners do not accidentally retain mission-local mutable state after replacement.

Phase 1 does **not** need a simultaneous old/candidate world fixture.

When Phase 4 implements real restore, extend this fixture to the chosen restore topology. If old and restored worlds overlap in memory, prove their mutable world-scoped services/resources remain isolated and they never both produce authoritative gameplay consequences. If restore uses sole-world replacement after prevalidation, prove failure reaches the defined coherent recovery state.

## Gameplay-input-domain fixture

Prove:

- accepted locomotion behavior survives the gameplay-input boundary;
- application ownership suppresses gameplay intent without private locomotion changes;
- interaction/combat/inventory are not forced through locomotion `PlayerCommand`;
- one **gameplay intent** frame maps to one gameplay simulation tick;
- held gameplay state persists only while physically/currently held and permitted;
- pressed/released gameplay intent exists for one frame only;
- pause/UI/cutscene/teardown/world-replacement gating clears transient gameplay edges rather than replaying them;
- a representative edge-dependent gesture (for example hold attack, lose combat-input ownership, release while disabled, resume) is cancelled and requires a fresh initiating press rather than remaining stuck or firing later;
- mouse look retains accepted response/feel and is not inadvertently quantized/delayed by the gameplay-frame refactor;
- world gameplay samples the current input-owned view pose coherently during simulation;
- UI/menu input continues to work when world gameplay simulation is paused.

## Gameplay-time fixture

As timed gameplay appears, prove:

- ordinary gameplay time advances with permitted world simulation;
- pausing for real wall-clock time does not advance guard search, mechanism progress, stagger, deployable arming, delayed mission actions, or other ordinary gameplay durations;
- time spent loading/restoring does not silently advance restored gameplay durations;
- save/restore preserves meaningful stage/progress/remaining simulation time where required;
- no test depends on serializing `Timer` objects or coroutine stacks.

## Persistent-ID/reimport fixture

Prove persistent IDs are unique, ordinary map move/reorder/reimport preserves identity, duplication receives distinct identity, generated/repaired IDs persist to authoritative source, repeated validation does not rewrite valid source or churn IDs, repair does not create import/rewrite loops, stale generated data cannot overwrite newer authored edits, semantic `content_id` duplicates are rejected, and missing semantic references report clearly.

## Gameplay-event / controlled-mutation / stable-boundary fixture

Before mission logic or save capture depends on the path, prove:

- semantic events are current-world-owned;
- emitted events process FIFO at the chosen controlled point;
- the same emitted sequence produces the same handling order;
- nested emissions append rather than recursively reorder dispatch;
- normal dispatch is disabled while BUILDING, RESTORING, and TEARING_DOWN;
- stale events from torn-down worlds cannot affect replacement;
- handlers participating in the current drain finish synchronously and cannot suspend/`await` then later pretend to belong to the completed step;
- an intentionally self-sustaining event/rule loop is caught by a development runaway-cascade guard with a useful trace rather than hanging indefinitely;
- engine callbacks outside the controlled pass cannot directly race durable world-semantic state across the stable boundary; representative callbacks enqueue future semantic work instead;
- input-owned player view pose may change at accepted event cadence without being treated as an alternate world-consequence path;
- a supported mission-script mutation requested from `_process()`/signal/async context is queued/recorded and becomes authoritative only through the controlled pass;
- public event/API data uses supported semantic identity/value boundaries rather than requiring mutable private Node references;
- the current consequence pass completes before the stable gameplay boundary is reported;
- save requested mid-step occurs only after that true stable boundary.

Do not freeze a broad event/scheduler framework; freeze only these semantics.

## Semantic-state ownership fixture

As mission facts/objectives/possession/statistics/vitality/campaign state appear, verify representative facts have one owner:

- door state comes from door ownership, not mirrored generic facts;
- actor life/awareness/vitality comes from actor/perception/vitality ownership as appropriate;
- possession comes from possession/inventory ownership;
- objective state comes from objective ownership;
- run counters come from `MissionRunState`/statistics;
- mission facts hold mission-defined variables/latched meanings rather than generic mirrors;
- before Phase 12, mission facts do not become storage for campaign-persistent truth;
- once introduced, campaign-persistent facts come from `CampaignState`.

Where a derived/latched mission fact intentionally duplicates information, test its distinct semantic meaning instead of treating it as the primary system state.

## Acoustic fixture

Use a tiny authored map with open room, doorway, closed door, separated room, and L-shaped/corner corridor.

Protect accepted deterministic relationships only after the acoustic model is chosen. If topology is authored, include normal mapper edit/reimport proof.

## Gameplay-light fixture

Use a small chamber for dark/partial/full/occluded/edge/multiple-light cases. Automate only accepted objective relationships; subjective correspondence still needs playtest.

## Door integration fixture

The same ordinary door eventually participates in interaction, collision, open/closed/lock state, sight, acoustics, NPC/nav, prop obstruction, semantic events, and save/load.

Avoid separate fake door models per subsystem.

## Thief-style prop fixture

This LOCKED behavior deserves deterministic regression protection.

### Stable edge support

A settled box with valid support may overhang without toppling/rotating/sliding/falling from realistic torque.

### Stable stack

A settled stack remains stationary without wobble/drift/rolling/rotation.

### Support removal

Given `C supported by B`, `B supported by A`, `A supported by world`, removing A causes unsupported objects above to fall until supported without exploding/scattering/toppling merely from unrestricted rigid-body behavior.

### Drop/throw/settle

Held object may be dropped/thrown, collide/move, then returns to settled stationary contract rather than indefinite rolling/sliding/spinning.

### Held ordinary prop interaction contract

Prove a held ordinary prop uses intended first-person held presentation, cannot be freely rotated, and suppresses ordinary world interaction through central interaction/input ownership. Doors/switches/loot should not each need private `is_holding_prop` logic.

### Save/load

Settled/transient representative prop state restores coherently without extra motion.

## Nav/reimport fixture

Imported map → NPC patrol → ordinary door use → map edit/reimport → nav rebuild remains supported.

## Save snapshot/restore transaction fixture

Save/restore is tested as semantic transaction, not dictionary serialization.

### Capture

Prove:

- save request may happen during ordinary active/transient gameplay;
- each pending save request is bound to the `WorldSession` that received it;
- if restart/load/exit stops that source session before its stable-boundary capture, the pending request is cancelled and **does not capture the replacement world**;
- if snapshot capture already completed, its detached file write may finish after source-world teardown without reading live world data;
- capture waits only to the source session's next stable semantic boundary, not world idle;
- current semantic event/consequence processing has drained first;
- every owner plus current input-owned player view pose contributes to one detached in-memory snapshot for the same coherent boundary;
- snapshot contains no live Node/Object/RID/callback/signal/shared mutable runtime Resource references;
- mutable Arrays/Dictionaries/other data in snapshot are not shared with live gameplay state;
- after capture, deliberately mutate corresponding live objects/containers and prove snapshot remains unchanged;
- later encoding/writing consumes only detached snapshot data;
- rapid repeated saves to one slot cannot allow an older requested snapshot to commit over a newer request;
- quickload uses latest fully committed save and ignores in-progress temporary writes.

Use a deterministic fixture where several systems and mouse/view pose change around a save request and prove restored result corresponds to one completed semantic instant without quantizing normal look input to the physics tick.

### Restore

During restore and `after_restore`/world-ready reconciliation, ordinary consequences remain suppressed until validation is complete and gameplay is enabled.

As systems exist, cover:

- header contains `save_format_version`, `mission_id`, `mission_content_revision`;
- unsupported global save-format version refuses clearly when **semantic interpretation** is incompatible even if the serialized structure still parses;
- unsupported mission-content revision refuses clearly;
- an intentionally incompatible structural/spatial mission change is refused when old transforms/state cannot be restored safely;
- mission restart creates fresh state;
- save → restore round trip;
- authored removals before state application to survivors;
- runtime-persistent recreation/registration/reservation before state application;
- player transform/velocity/stance/traversal/view pose;
- door/prop/NPC/objective/fact/script/run-stat state;
- a representative already-resolved random AI/search choice resumes as the same choice rather than rerolling during restore;
- no duplicate one-shot rules/objectives/loot/stats/alarms/dialogue/events;
- `after_restore` cannot emit ordinary gameplay consequences merely because it reconciles state;
- load/restart/mission-transition application operations do not race one another;
- if old/restored worlds overlap, old gameplay is frozen and mutable state/services do not leak;
- if restore uses sole-world replacement, forced deep failure reaches the defined safe recovery state;
- failed partial restore leaves no stale events/timers/deferred work in current/next session;
- failed durable write preserves previous valid save;
- gameplay durations resume from saved simulation progress, not wall-clock time spent loading.

## Removed-authored persistence fixture

Once authored objects can disappear permanently, prove tombstone state, absence after restore, no duplicate loot/value/consequence replay, and no inference of permanent removal merely from current tree absence.

## Runtime-created persistence fixture

Once a runtime-created object must survive save/load, prove:

- runtime identity is distinct from authored identity;
- saved type/spawn provenance uses a stable semantic identifier rather than fragile scene/class filename;
- unknown saved type fails clearly;
- enough provenance exists to recreate correct object;
- semantic state applies only after recreation/registration;
- restored runtime identities are reserved in the new world;
- after restore, creating additional runtime objects cannot reuse/collide with restored identities;
- repeated restore does not duplicate copies;
- lifecycle obeys world teardown/replacement ownership.

When ordinary save-anywhere can occur during an active runtime-created transient—projectile in flight, thrown inventory tool, arming deployable, timed explosive, active area effect, or similar—also prove one representative direct-restore/reconstruct/normalize policy. A restored state must not silently consume inventory/ammo while dropping the corresponding active effect, nor duplicate the effect.

## Actor-state compatibility fixture

Before final combat, prove conscious/unconscious/dead/body behavior retains the same persistent identity/semantic actor reference even if runtime presentation nodes change.

## Crude hostile compatibility fixture

Before stealth architecture hardens, exercise:

```text
attack intent
→ semantic hostile effect
→ actor/life-state consequence
→ gameplay event + gameplay sound
→ relevant AI/perception reaction
→ save
→ restore
```

Protect reuse of gameplay-intent, controlled-mutation, gameplay-time, actor, event, world-session, perception, and persistence contracts without locking combat tuning/feel.

## Combat vitality/damage fixture

When Phase 9 direct combat becomes real, prove the smallest semantic player/actor vitality and damage state is the authoritative combat path and survives save/restore.

Phase 10 healing/gas/water/fire/explosion/tool effects must extend that same vitality/damage boundary rather than introducing a replacement health/damage owner. Include at least one regression showing ordinary combat damage produces the same semantic vitality result before and after effect-system generalization.

## Mission fact/rule/script fixture

Once the rule/script system exists, cover:

- fact type/default/scope validation;
- invalid fact assignment rejection/reporting;
- facts do not become generic mirrors of system-owned truth;
- pre-Phase-12 fact scopes do not provide a hidden campaign-persistent owner;
- deterministic rule ordering relative to event queue;
- one-shot/repeat behavior;
- explicit semantic state for delayed/long-running rules;
- save/load of rule state without coroutine/timer serialization;
- already-resolved random rule/script choices restore without reroll when their result is durable gameplay truth;
- runaway event/rule cascade diagnostics;
- missing entity references report clearly;
- a mutation command invoked from an out-of-pass GDScript callback is queued/applied through the controlled semantic pass rather than changing gameplay immediately;
- public script/event data does not require arbitrary mutable private Node references.

## Mission-run statistics fixture

Once the first run statistic exists, prove one semantic owner supplies counters/results. Loot collection, and later kills/knockouts/alerts/objectives/time, extend the same ownership instead of accumulating private duplicate counters for later UI scraping.

## Campaign completion / durable progression fixture

Once Phase 12 campaign progression exists, prove:

- an in-mission save records/references enough campaign/mission-start baseline to reconstruct the same derived mission variant;
- completing a mission applies campaign consequences exactly once;
- retrying/re-entering the completion path cannot double-apply those consequences;
- durable campaign advancement and mission-completion state cannot be left half-committed by a simulated write/failure path;
- after durable completion, an old in-mission quicksave from that mission instance is either invalidated/removed or clearly refused against the advanced campaign baseline;
- `Continue` cannot ambiguously combine advanced campaign state with a stale in-mission world.

---

# Manual regression policy

Per-item manual acceptance belongs in `DEVELOPMENT_PLAN.md`.

The checklist below is the broad integration pass for changes that could affect accepted player behavior. It is not required after every unrelated docs/gameplay change.

A focused agent handoff must collectively cover every unresolved `Manual:` acceptance criterion for the roadmap item. “Focused” means omit unrelated global checks; it does not mean skip required acceptance cases. A generic user response such as `works` accepts only the cases that were actually included in the handoff.

When `Manual:` requires a specialized validator, name the role explicitly (user/playtester, Windows operator, mapper, writer, cold author, external developer, etc.). The implementing agent may prepare the fixture/procedure but cannot self-certify an independent-human validation requirement.

---

# Player manual regression checklist

## Project load / player scene

- [ ] Project reopens without new missing-script, parser, global-class, UID, or player-code errors.
- [ ] `Player.tscn` loads/spawns normally.
- [ ] No unexpected resource/UID churn appears after normal project rescan.

## Input and look

- [ ] Move in all four directions/diagonally.
- [ ] Mouse look and mouse capture/release retain accepted response/feel after input-router changes.
- [ ] Mouse look does not gain obvious physics-tick quantization/latency merely because gameplay intent is tick-framed.
- [ ] World gameplay reacts to the current view pose coherently despite event-driven look cadence.
- [ ] Combined movement/jump/crouch/sprint does not create stale one-frame states.
- [ ] Pause/UI/cutscene ownership suppresses world gameplay input without breaking UI input or resumed gameplay feel.
- [ ] Interaction/combat/inventory domains, once present, do not alter ordinary locomotion command semantics.
- [ ] Press/release actions performed while their gameplay domain is disabled do not fire later on resume.
- [ ] An armed hold/release gesture cancelled by pause/UI/input-owner change does not remain stuck or fire after resume; a fresh press is required.

## Pause / world ownership / gameplay time

When Phase 1 exists:

- [ ] Pause suppresses ordinary gameplay simulation according to application policy, not only player input.
- [ ] Meaningful gameplay durations do not advance while ordinary world simulation is paused.
- [ ] Resume does not burst stale intents/timers/events.
- [ ] Restart/mission replacement does not receive effects/state from previous world session.
- [ ] Mutable runtime state is not accidentally shared through authored Resources/autoloads across a restart.

## Ground, support, slopes, and falling

- [ ] Move/sprint/start/stop normally on flat ground.
- [ ] Move on representative walkable slopes without unexpected standing slide.
- [ ] Land normally from jumps/longer falls.
- [ ] Narrow beams/edges support capsule when physically valid.
- [ ] Walls/seams/convex edges while falling do not stick/launch/create fake support.

## Steps

- [ ] Climb valid steps straight-on/diagonally/strafe.
- [ ] Strafing along a riser without inward motion does not spuriously step.
- [ ] Wall seams near foot height are not steps.
- [ ] Airborne collision with step geometry does not create airborne step.
- [ ] Representative heights up to configured maximum work.
- [ ] Blocked overhead/crossing routes do not force capsule through geometry.

## Crouch, sprint, jump, and air control

- [ ] Crouch/stand repeatedly; low clearance blocks standing until space exists.
- [ ] Crouch/sprint movement remain distinct.
- [ ] Jump from standstill, movement, sprint.
- [ ] Jump releases support cleanly.
- [ ] Air steering/reversal/landing remain coherent.
- [ ] Held/released jump does not leave stale mantle intent.

## Ledge grab / hang / traversal

- [ ] Grab normal ledge from jump/fall.
- [ ] Hang without unexpected support/step transitions.
- [ ] Shimmy both directions and supported corners.
- [ ] Directional/sprint-directional/no-input hang jumps release cleanly.
- [ ] Suppression prevents illegitimate immediate regrab but later legitimate attempts work.

## Mantle

- [ ] Ground-requested mantle starts from accepted situations.
- [ ] Airborne jump-hold mantle buffering remains accepted.
- [ ] Mantle normal wide/supported thin geometry as accepted.
- [ ] Crouch-clearance cases remain accepted.
- [ ] Successful mantle does not sink/stick/fall/snap/preserve unintended velocity.

## Velocity / collision integration

- [ ] Traversal entry/release leaves no stale locomotion velocity.
- [ ] Valid landings terminate downward controlled velocity only after support validation.
- [ ] Unsupported collision does not produce outsized sideways launch/displacement.

If the user explicitly reopens player movement/traversal behavior, update automated/manual contracts to the newly accepted behavior rather than preserving obsolete rules.

---

# Future integrated manual acceptance

## Acoustic/speech

- [ ] Footsteps/impacts respond intuitively to doors/openings/connected spaces.
- [ ] Stopping/listening gives useful positional information.
- [ ] Typed speech remains visible through visual cover when acoustically audible.
- [ ] Distant/marginal speech fades as intended; inaudible speech is hidden.
- [ ] Mapper-authored acoustic topology, if used, remains low-friction through edit/reimport.

## Gameplay lighting

- [ ] Light gem agrees intuitively with dark/partial/full/occluded cases.
- [ ] Decorative brightness does not accidentally define stealth exposure.
- [ ] Switching/extinguishing gameplay light updates exposure coherently.

## Thief-style props

- [ ] Edge-supported props look intentionally stable.
- [ ] Stacks remain motionless while supported.
- [ ] Removing lower support makes upper supported objects fall without exploding/scattering.
- [ ] Dropped/thrown props settle and stop.
- [ ] Props remain useful for stacking/climbing/door obstruction.
- [ ] Held ordinary props use intended first-person presentation, cannot be freely rotated, and suppress ordinary world interaction without per-object special cases.

## Save/load

- [ ] Quicksave can be requested during ordinary active/transient gameplay without waiting for world idle.
- [ ] A quicksave requested immediately before restart/load/exit is either captured from the original world at an allowed boundary or cancelled; it never silently saves the replacement world.
- [ ] Loaded save reflects one coherent instant including player orientation/view pose rather than mixed before/after state.
- [ ] Representative resolved AI/random choices resume as the same current choice instead of visibly rerolling on load.
- [ ] Representative transient/timed states restore coherently and do not advance merely because real time passed during loading.
- [ ] Loading/`after_restore` does not visibly replay objective/loot/stat/alarm/dialogue consequences.
- [ ] Repeated rapid saves leave the latest requested successfully committed state as the quicksave.
- [ ] Quickload never reads an in-progress temporary save.
- [ ] Application remains coherent when save/load/restart requests happen close together.
- [ ] Incompatible global save semantics or mission-content revision produce clear refusal rather than a partially wrong world.
- [ ] Failed load reaches coherent recovery state for chosen restore topology.
- [ ] Failed save attempt preserves previous valid quicksave.

## Combat

Before combat becomes LOCKED, playtest one guard, two guards, tight corridor, open room, stealth-to-combat transition, lethal assault, nonlethal assault, and retreat/break contact.

Also verify pause/UI/input ownership while a hold/release combat gesture is armed cancels it cleanly rather than leaving a latent attack.

Subjective combat feel is accepted by the user, not inferred from crude architecture proof/tests.

## Campaign progression

When campaign flow exists:

- [ ] Completing a mission advances consequences once even if the completion path is retried/re-entered.
- [ ] Continue after completion resumes from the advanced campaign state, not a stale in-mission quicksave.
- [ ] Attempting to load an invalidated/stale in-mission save after durable campaign advancement gives clear behavior rather than mixing two campaign baselines.

---

# Supported-platform validation

Windows x64 desktop is the supported development/export target. The Ubuntu GitHub Actions environment is a headless automated validation environment, not proof of Windows-specific runtime/export behavior.

Changes that materially affect renderer/rendering-device configuration, Windows-specific APIs, filesystem/path behavior, native/plugin integration, export/startup behavior, executable packaging, or other target-specific behavior require an appropriate Windows x64 check. When the agent cannot execute that check directly, it must hand the user a focused Windows validation instead of treating Linux CI as equivalent.

---

# Performance-testing policy

Do not wait for final representative mission before checking expensive-system scaling.

As systems become real, record representative measurements for:

- gameplay exposure with many relevant lights;
- many guards performing vision checks;
- many semantic sounds/hearing receivers;
- nav/path updates around changing doors;
- mission-event/rule bursts including cascade diagnostics;
- **synchronous detached snapshot capture time**;
- encoded save size and durable-write time separately;
- prop support checks;
- runtime-created persistent objects when real.

Record exact supported Godot/runtime configuration and enough reference-machine information for meaningful comparisons.

If synchronous snapshot capture becomes expensive, optimize semantic state/copying. Do not weaken coherent capture by reading live gameplay asynchronously across multiple ticks.

The later production-scale mission remains the final realistic performance proof.

---

# CI policy

GitHub Actions exists for the deterministic movement barrier.

Under current repository workflow, `test` is the direct-write integration branch. CI on `test` is therefore **post-push integration validation**, not a fictional pre-push gate.

The current CI barrier:

- runs on the pinned `ubuntu-24.04` GitHub-hosted runner;
- installs Godot `4.7.2` without .NET or export templates;
- performs `godot --headless --path . --import` so a clean checkout has generated Godot project metadata/class registration before tests load;
- runs the same authoritative movement command used locally;
- runs on pushes to `test` and on pull requests if they are used;
- fails on a nonzero movement-test exit.

When multiple suites exist, CI calls one all-tests entry point rather than duplicating suite commands in workflow YAML.

A newly uploaded implementation commit is not accepted merely because it reached `test`. Keep roadmap work `[~]` until relevant CI/local automated validation is green and required manual/user validation is accepted.

When job logs are available, validation includes checking for newly introduced parser/script errors, resource/UID/import failures, invalid references, and other meaningful project regressions even if the process exits successfully. Known harmless external/deprecation noise should be distinguished rather than treated as a project failure.

Do not describe a `test` status check as pre-merge/pre-push protection while policy writes directly to `test` and forbids helper branches.

---

# Maintenance

Update this file during authorized repository patches when:

- meaningful automated regression coverage is added/removed/changed;
- authoritative test command changes;
- a new real suite is introduced;
- broad manual regression coverage changes;
- acceptance-evidence strategy for non-CI checks materially changes;
- CI/testing strategy materially changes;
- an OPEN/TARGET system becomes LOCKED and needs permanent verification rules.

Do not turn this file into a line-by-line mirror of test code. It describes verification contracts at the behavior/ownership boundary.
