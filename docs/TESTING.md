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

Systemic features require **integrated proof**, not only isolated unit proof. A door is not complete because it animates; a save system is not complete because it serializes data; an acoustic system is not complete because one distance test passes.

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

Then run the authoritative full regression barrier from project root:

```powershell
godot --headless --path . --script res://tests/run_all_tests.gd
```

Expected result: exit code `0` and `ALL TEST SUITES PASSED`.

The all-tests runner invokes the independent authoring, application, props, acoustics, and movement suites through clean headless Godot subprocesses. The import bootstrap is not required before every ordinary local test run when the project has already been imported successfully; it exists so a clean checkout follows the same reproducible startup path used by CI.

Focused persistent-identity authoring command:

```powershell
godot --headless --path . --script res://tests/authoring/run_authoring_tests.gd
```

Expected result: exit code `0` and `ALL AUTHORING TESTS PASSED`.

Focused application ownership command:

```powershell
godot --headless --path . --script res://tests/application/run_application_tests.gd
```

Expected result: exit code `0` and `ALL APPLICATION TESTS PASSED`.

Focused Thief-style prop command:

```powershell
godot --headless --path . --script res://tests/props/run_prop_tests.gd
```

Expected result: exit code `0` and `ALL PROP TESTS PASSED`.

Focused acoustics command:

```powershell
godot --headless --path . --script res://tests/acoustics/run_acoustic_tests.gd
```

Expected result: exit code `0` and `ALL ACOUSTIC TESTS PASSED`.

Focused movement command:

```powershell
godot --headless --path . --script res://tests/movement/run_movement_tests.gd
```

Expected result: exit code `0` and `ALL MOVEMENT TESTS PASSED`.

Movement harness failure-path check:

```powershell
godot --headless --path . --script res://tests/movement/run_movement_tests.gd -- --intentional-failure
```

Expected result: nonzero exit code and intentional failure reported.

The authoring suite derives temporary identity-workflow fixtures from the real Playground `.map`, verifies the project-owned Vark TrenchBroom FGD/config, exercises source-owned persistent-ID repair through representative edits, reparses through the pinned FuncGodot parser, builds identity-bearing entities through the real Vark FuncGodot map settings, and verifies generated runtime Nodes carry authored persistent IDs plus optional semantic `content_id` values. It preloads both mapper-facing CLI scripts: `persistent_identity_probe.gd` protects the exact `sync-config`/workspace repair route, while `playground_reimport_probe.gd` protects the read-only 2.8 rebuild verifier. It also verifies that each Vark player-start/marker/exit point class directly owns `persistent_id` and `content_id` and emits those fields in its own TrenchBroom FGD block, builds the tracked Playground point entities through the real Vark FuncGodot path, proves `MissionDefinition.player_start_selector` resolves the authored start before play, and proves all three semantic points are present in the current-session registry. Phase 2.8 additionally derives a disposable real-Playground copy, moves only the player start, proves dry identity repair is a byte-for-byte no-op, proves all tracked persistent/content IDs remain stable, proves only the intended point transform changes, rebuilds through the real `WorldSession`, and enters `PLAYING`. Phase 2.9 adds pre-`READY` mission-content coverage: direct session callers cannot bypass `MissionDefinition` load validation, the current player-start selector must resolve through the registry to an authored `vark_player_start`, at least one authored persistent `vark_exit` must exist, and zero or multiple `vark_player` nodes fail cleanly. Useful missing/duplicate persistent-ID diagnostics, optional blank semantic IDs, duplicate non-empty semantic-ID diagnostics, the `WorldSession` fail-closed boundary, and current-session registry lookup/missing/lifetime behavior across teardown and replacement remain covered. Temporary authoring fixtures never mutate the tracked Playground map.

The application suite verifies the configured F5 application entry point, no-world main-menu startup, separate New Game and curated Development Launch flows, selected development-target launch through the real lifecycle/input path, package-local Playground source/build wiring, minimal `MissionDefinition` validation/loading/session configuration, the real look-sensitivity setting across replacement, menu/quit wiring, current development world/player/UI ownership once gameplay starts, current/stale session identity checks, the exclusive top-level-operation guard, non-playing world build, application-controlled play/pause/resume/stop, restart/transition/exit teardown, fresh replacement, stale session-owned timer/deferred-work rejection, the application-owned gameplay/look input boundary, exclusive application control modes, gameplay-time ownership, and the Phase 3.1 interaction contract. The interaction regression launches the real `Interaction Lab` through the production application/session/player path and proves the **F** primary-interaction mapping, center-view first-hit targeting, range and occlusion rejection, target-state eligibility, Thief-style fullbright/no-received-shadow selected surfaces with base-color and ordinary cast-shadow preservation plus normal shaded-surface restoration, one fresh primary-interaction edge with no held repeat, central ordinary-interaction suppression/resume, and stale-edge suppression across gameplay-domain loss. The door-like and prop-like probes both consume the same narrow interactable surface; the fixture does not implement the later door/prop systems. Phase 3.2 coverage runs in this same focused application suite through an isolated real `WorldSession`: it proves emitted-order FIFO, nested append rather than recursive dispatch, deep value-owned payload detachment and per-handler isolation, current-session/lifecycle gating including RESTORING, a late controlled physics drain point, out-of-pass queueing without immediate durable consequence dispatch, synchronous-handler acknowledgement, a bounded runaway-cascade diagnostic/recovery path, teardown cleanup, replacement-session isolation, and stable-boundary publication only after a successful consequence pass. Phase 3.3 extends that already-wired regression with the reserved `gameplay.sound` source fact: only semantic kind/origin/positive relative strength are accepted, stale/non-PLAYING work is rejected through the same session boundary, presentation-audio-shaped payloads cannot enter the reserved event, and valid gameplay sound reaches handlers only at the controlled consequence/stable-boundary point without requiring or creating presentation audio. Phase 3.4 adds a dedicated real `Door Lab` regression through that same production application/session/player path: the ordinary door reuses center-view/F selection, its one physical leaf is both collision and closed-door vision obstruction, opening/closing advances explicit semantic phase/progress, accepted use emits the reserved `door.use` gameplay-sound source fact, completed transitions emit `door.state_changed`, narrow acoustic-openness/navigation-passage seams follow the same door state, and semantic capture/apply restores stable/in-progress state without replaying consequences. The same regression now loads the door leaf from its configured external OBJ model, swaps it to a second compatible external OBJ on the existing door instance, and proves that presentation replacement leaves interaction ownership, collision/vision obstruction, semantic state, highlight material, events, consumer seams, and capture/apply behavior under the unchanged ordinary-door archetype.

Phase 3.5 has a dedicated Props suite wired through the authoritative all-tests barrier. It retains the production-path Prop Lab coverage for outward/hard OBJ normals, normal lit/shadowed presentation, external-model replacement, real `RigidBody3D` ownership, exact dormant/stable settled state with explicit physics promotion, single-slot `carried_junk`, bottom-center HUD presentation, normal locomotion while carrying, central interaction/hand suppression, stale F/R edge suppression, F throw versus R release, semantic sound, detached capture/reconcile, edge support, stable stacks, lower-support fall, no support gap, and no post-rest drift/spin. Ordinary box-like props are now top-up in every semantic state: F/R placement uses the same upright collision volume, moving/restored state normalizes pitch/roll immediately while preserving horizontal yaw, angular solver response remains locked, and real Jolt physics continues to own translation, gravity, collision, linear velocity, slide/bounce, and transferred momentum. Real dynamic contact/support plus low speed transitions directly from `moving` to exact stable `settled`; there is no semantic settling/orientation-correction phase. The synthetic pre-tilted moving-state fixture proves immediate normalization, and the narrow-support fixture proves the prop reaches rest without any intermediate phase. The crate fixture also protects the lighter mass/friction/player-shove tuning. A second focused Phase 3.5 transition regression exercises the cross-system failure boundaries directly: shape-volume-aware release backs away from a world blocker; a valid throw pose intentionally overlapping the player activates a live rigid body whose full throw velocity/displacement is committed through the synchronized direct-body-state callback; the overlap uses a player-only transient collision channel while retaining world/prop collision, and ordinary player collision returns after geometric separation; a stable settled prop is explicitly promoted and physically displaced by a real moving-prop impact; production player locomotion gives one bounded lateral shove at the contact-solver boundary without making standing support a shove; standing support stores and invalidates the exact prop collider RID; catch/hang/corner/mantle state is canceled only when its referenced collider leaves world participation; catch/hang/corner remain stationary-prop attachments, while a production grounded mantle from an angled approach gives the already-moving crate lateral drift through the real contact solver, proves the player stays attachment-relative along the ledge tangent through completion, and proves already-held forward input resumes ordinary locomotion instead of leaving the player stuck on top. The reproduced post-mantle freeze is now protected by a permanent real-player regression at the actual root cause: a positive but sub-tolerance forward remainder with further travel effectively blocked must complete traversal and return ownership to locomotion on the next physics frame. The temporary post-mantle trace and contact-solver snapshot instrumentation were removed after the accepted Windows retest. The authoritative all-tests barrier continues to run the accepted movement suite alongside the Props suite.

The movement runner currently:

- executes real Godot physics;
- uses the real `Player.tscn` where player behavior is under test;
- aggregates failures rather than stopping at first assertion;
- exits `0` on success and nonzero on failure;
- releases simulated input between fixtures.

Every new deterministic regression must be reachable from the appropriate focused suite and the authoritative all-tests barrier so local full-regression and CI actually execute it.

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

## Persistent identity feasibility/source-writeback proof

Phase 2.3 established `persistent_id` as a property of authoritative Valve `.map` entity source. `tools/authoring/persistent_id_source.gd` scans top-level authored entities, ignores `worldspawn` and TrenchBroom structural group/layer records, reports missing/duplicate IDs, and repairs missing IDs or later duplicate occurrences directly in source. The first occurrence of a duplicate remains the source owner. The accepted proof is authoring/source ownership; registry lookup and the final Vark TrenchBroom entity vocabulary remain later Phase 2 work.

The first real Windows mapper pass exposed a missing authoring-schema boundary: the repair tool wrote `persistent_id`, but the then-exported Vark TrenchBroom FGD did not declare that key on `func_detail`, and TrenchBroom dropped it when the entity was moved/saved. Vark now owns project-side FGD resources under `authoring/fgd/`; `VarkTrenchBroom.tres` exports `Vark.fgd`, and its project-owned `func_detail` inherits a `VarkPersistentIdentity` base declaring `persistent_id`. FuncGodot vendor resources remain untouched.

Refreshing the Vark config then exposed an inherited invalid material dependency: the generated GameConfig pointed at non-existent `textures/palette.lmp`. Vark explicitly disables that unused Quake palette with `palette_path = ""`. The authoring regression protects the `textures` material root, PNG support, empty palette, and presence of the representative zebra PNG so a config refresh cannot silently blank the TrenchBroom material browser again.

The deterministic source-workflow coverage begins from actual `missions/playground/mission.map` text, creates temporary ordinary `func_detail` brush entities, and uses deterministic generated IDs only inside the test. It reparses each edit through the real pinned `FuncGodotParser`. Coverage proves initial missing-ID repair persists into map source/parser properties; moving an entity keeps its ID with no rewrite; reordering unrelated entity blocks keeps semantic probe→ID mappings and source hash; duplicating a source entity initially carrying the same ID repairs only the duplicate to a distinct ID; deleting one entity and creating another gives the replacement a new ID; another validation/parse pass performs no write and no ID churn; and an old source hash cannot write repair text over a newer mapper edit.

The mapper-facing probe uses random 128-bit ID bytes and operates only on ignored `tests/authoring/workspace/mission.map`. `sync-config` exports and validates the current Vark GameConfig/FGD in the machine-specific FuncGodot TrenchBroom folder; `prepare` refuses to overwrite an existing workspace; and `reset` deliberately replaces only the ignored workspace from the real Playground source. When `repair` writes the `.map`, it explicitly tells the mapper to reload/reopen the document before any further edit/save. The accepted Windows run demonstrated why: TrenchBroom preserves IDs it has loaded, but an already-open pre-repair document can overwrite an external repair from stale in-memory state. This reload rule prevents editor/source synchronization from masquerading as identity churn.

The Windows TrenchBroom 2026.2 proof is accepted: materials remained available after config refresh; the original ID survived move/save; unrelated loaded IDs survived ordinary saves; duplication kept the original source owner and received a distinct repaired ID; delete/recreate received a fresh ID; a plain save preserved all three loaded IDs; and the mapper never hand-authored an ID.

## Production authored persistent identity

Phase 2.4 wires the accepted source mechanism into runtime without pulling forward the registry or semantic IDs. `authoring/vark_map_settings.tres` points FuncGodot at the same project-owned Vark FGD used by TrenchBroom; the project default and Playground wrapper both use those settings. The current proof `func_detail` keeps ordinary `StaticBody3D` behavior while its Vark FGD definition attaches `VarkPersistentEntity` and auto-applies the authored `persistent_id` property to the generated runtime node.

`VarkPersistentIdentityValidator` remains a stateless validation boundary rather than a lookup service. It scans only explicitly marked persistent entities, accepts unique non-empty persistent IDs, reports missing IDs with node paths, and reports duplicate IDs with both the duplicate and first-owner paths. `WorldSession.build()` now reaches that same validation through the 2.6 registry build before the session becomes `READY`; invalid identity pushes diagnostics, leaves no partial registry, tears down the candidate world, and returns failure. Worlds with no identity-bearing nodes remain valid.

The authoring regression exercises the real Vark `FuncGodotMapSettings` and `FuncGodotMap` build path. Before repair, mapper-style missing IDs appear as empty runtime persistent IDs and fail validation. After repair, the generated nodes retain `StaticBody3D` behavior and expose the exact authored IDs. A duplicated source ID is visible to runtime validation before repair. Direct validator fixtures assert path-specific missing/duplicate diagnostics, and test-only invalid packed worlds prove `WorldSession` fails closed and returns to `EMPTY` rather than allowing bad persistent identity to reach `READY`.

## Optional semantic content IDs

Phase 2.5 adds `content_id` as an optional author-facing semantic address that is explicitly separate from `persistent_id`. `authoring/fgd/vark_content_addressable_base.tres` declares the mapper-owned field; the Phase-2 `func_detail` proof carrier composes that base so the real TrenchBroom/FuncGodot property path was exercised before actual Vark semantic point entities existed. The Phase 2.7 point roles carry the same `content_id` field directly in each point definition rather than relying on FGD base inheritance, because the Windows TrenchBroom 2026.2 acceptance pass showed inherited point fields appeared only as defaults instead of binding to the existing `.map` keys. `VarkPersistentEntity` carries the optional runtime string, but no semantic ID is generated or repaired automatically and the tracked Playground still does not assign them to ordinary geometry.

Blank semantic IDs are valid and mean “not addressed by mission logic.” Non-empty `content_id` values are validated for uniqueness; the stateless validator reports duplicate semantic IDs with both owner paths and the pre-`READY` `WorldSession` boundary tears the invalid world down. Phase 2.6 consumes those already-validated IDs for current-session lookup. Phase 2.9 now validates the first real authored semantic reference by requiring `MissionDefinition.player_start_selector` to resolve through that registry to an authored player-start role before `READY`.

The focused authoring regression verifies the exported Vark FGD exposes `VarkContentAddressable`/`content_id`, writes a temporary mapper-style `func_detail` carrying `persistent_id = pid-content-probe` and `content_id = door.vault`, builds it with the real Vark FuncGodot map settings, and proves the generated `StaticBody3D` exposes the exact authored semantic ID while persistent validation remains valid. Direct fixtures prove blank semantic IDs are accepted, unique non-empty IDs are accepted, duplicate non-empty IDs report both owners, and a packed duplicate-content-ID world is rejected and torn down by `WorldSession` before `READY`.

## World-session entity registry

Phase 2.6 adds `VarkWorldEntityRegistry` as a small `RefCounted` owned by the current `WorldSession`. Registry construction reuses `VarkPersistentIdentityValidator` as its fail-closed gate and does not retain any indexes unless the full candidate world is valid. A valid registry indexes every authored persistent entity by `persistent_id` and each non-empty optional `content_id`; blank semantic IDs remain intentionally absent from the semantic index.

Lookup returns structured `{ ok, node, error }` data. Valid IDs resolve to the exact Node owned by the current world; blank or absent persistent/content IDs return `node = null` with namespace-specific diagnostics. The registry is not an autoload, authored `Resource`, entity superclass, or mission-script API, and it does not define runtime-created persistence or authored reference schemas.

`WorldSession` creates the registry while the candidate world is still non-playing, exposes narrow persistent/content lookup methods, and clears/discards the registry before freeing the world on teardown. The authoring/runtime regression proves successful lookup/counts, blank/missing diagnostics, no registry after missing/duplicate identity build failure, clearing of a retained old-registry reference across teardown, and replacement isolation where an old-world ID no longer resolves while a replacement-world ID does.

## TrenchBroom Vark entity foundation

Phase 2.7 introduces only the first point roles needed by the Playground: `vark_player_start`, `vark_marker`, and `vark_exit`. They are project-owned FuncGodot/TrenchBroom point classes that directly declare the established `persistent_id` and optional `content_id` fields in their own mapper-facing FGD definitions, build as lightweight `Node3D` instances, and register through the existing current-session registry. The first Windows TrenchBroom 2026.2 acceptance pass showed why the point fields are direct: the inherited-base version built correctly in FuncGodot, but TrenchBroom displayed both identity fields only as empty defaults even though the `.map` contained values. Flattening the mapper-facing point schema fixes that boundary without changing the shared runtime carrier or vendored FuncGodot code. The marker and exit have no gameplay behavior yet; they are semantic endpoints for later systems rather than premature interaction/objective/transition implementations.

The tracked `missions/playground/mission.map` carries one of each point role with stable authored `persistent_id` values and semantic IDs `default`, `marker.playground_reference`, and `exit.default`. After FuncGodot builds, the Playground wrapper resolves `MissionDefinition.player_start_selector` against generated nodes in the `vark_player_start` group. Exactly one match is required; on success, the real Player receives that authored point's global transform before ordinary play. The map therefore owns the start pose rather than duplicating it in `MissionDefinition` or `world.tscn`.

The authoring regression requires each point resource's direct `class_properties` to contain `persistent_id`, `content_id`, and `angle`, requires these three point classes not to depend on FGD base inheritance for mapper-visible identity fields, and inspects each point's own TrenchBroom FGD text for direct `persistent_id(string)` and `content_id(string)` declarations. It then builds the tracked Playground through the real Vark FuncGodot settings, proves one valid persistent/content-addressed `Node3D` exists for each role, and proves the launched Playground resolves the selector and registers all three semantic points. The suite also preloads the mapper-facing CLI probe so parser errors in the exact `sync-config` tool fail CI.

## Reimport stability

Phase 2.8 extends the authoring barrier from identity/source mechanics into the real Playground rebuild/run path. `reimport_stability_regressions.gd` derives a disposable `user://` copy from `missions/playground/mission.map`, moves only `vark_player_start` by 32 source units on X, and verifies both baseline and edited sources through `playground_reimport_probe.gd`.

The probe is read-only with respect to the supplied map: it requires `PersistentIdSource.inspect_source()` to be valid, requires a dry `repair_source()` pass to report no change and reproduce the source/hash exactly, then builds the real Playground wrapper through `WorldSession`, resolves `default`, `marker.playground_reference`, and `exit.default`, applies the authored start to the real Player, and enters `PLAYING`. The regression proves all three persistent/content mappings are unchanged, the start transform changes, marker/exit transforms do not, and verification never rewrites the edited source.

For mapper acceptance, the same probe can be run directly against the tracked source:

```powershell
godot --headless --path . --script res://tools/authoring/playground_reimport_probe.gd
```

It fails rather than repairing authored source. `.map.import` sidecars are generated FuncGodot/Godot metadata; Phase 2.8 removes the four legacy tracked top-level sidecars and `.gitignore` ignores `*.map.import`. Clean-checkout import/CI is the proof that they are recreatable, not source.

## Application root ownership

The real `Application.tscn` is instantiated through the application regression suite. Coverage verifies that F5 is configured to launch the application root, that the persistent application/UI exists before any world session, and that the application owns the current development world/player/session once either New Game or a development target installs gameplay through the same root. Current/stale session identity and one exclusive top-level operation guard remain protected.

## Minimal application/menu shell

The production application starts in `MENU` with no `WorldSession` or player constructed. The application regression drives the actual menu controls: Settings opens/closes inside persistent `UIRoot`, New Game installs the current default `VarkTest` world through the existing lifecycle/input path, and application exit returns to the same no-world menu state. The Quit button and application quit signal are verified as wired; actual operating-system application termination remains a focused manual acceptance because invoking it would intentionally terminate the test process.

The only current exposed setting is look sensitivity. The regression changes the real menu slider, verifies the application-owned value/readout, verifies the value is applied to both the real player's exported sensitivity and current event-cadence `PlayerLook`, restarts the world, and proves the replacement player receives the same application-owned value. The accepted default remains `0.007`; no placeholder settings or fake Continue/difficulty/save entries are treated as implemented.

## Development launch route

The main menu has a separate development-only launch panel backed by curated label/resource-path pairs owned by `VarkApplication`. Production currently exposes raw `VarkTest` plus the real Playground `MissionDefinition`; the loader accepts either a typed mission definition or a deliberately curated raw `PackedScene`, without automatic repository discovery or arbitrary file picking.

For deterministic selection coverage, the application test adds one test-only raw `Alternate Fixture` target before the real application enters the tree. The regression proves all three targets appear in the selector, invalid target indices create no session, an overlapping top-level operation blocks development launch, Playground resolves its owned world through `mission.tres` and launches through the normal `WorldSession`/input path, selecting the alternate target still launches that exact raw `PackedScene` with no invented mission metadata, exit returns to the persistent menu, Back returns to menu actions, and New Game still launches the default `VarkTest` path afterward. All launch targets use the real `Player.tscn` so the launch path exercises the semantic player marker and input binding rather than a fake session API.

## Mission package and minimal MissionDefinition

`missions/playground/` is the first real mission package. `mission.map` is the authoritative TrenchBroom spatial source; `mission.tres` is the typed authored `MissionDefinition`; `world.tscn` is the current launchable Godot wrapper; and `world.gd` is technical bootstrap glue that consumes the definition's map path, asks FuncGodot to build, and resolves the authored player-start selector before the session enters ordinary play. All `.map.import` sidecars and TrenchBroom autosaves are generated/non-source and ignored. Phase 2.8 removed the legacy tracked top-level sidecars after clean import/rebuild proved generated import metadata is recreatable; `.map` remains source truth.

The current `MissionDefinition` has exactly the load metadata needed now: `mission_id`, `world_scene`, `map_source_path`, `player_start_selector`, and `mission_content_revision`. Playground starts at content revision `1`. There is deliberately no player-start transform/position/rotation field: `player_start_selector = &"default"` resolves the map-authored `vark_player_start`, and the wrapper applies that point's transform to the real Player before play. The `.map` remains the single spatial source of truth. Phase 2.8 proves representative edit/save/rebuild/run stability, and Phase 2.9 now enforces the current authored player-start reference plus required mission-exit/player objects before `READY`.

The application regression loads and validates `missions/playground/mission.tres`, verifies all five fields and missing-field diagnostics, proves no duplicated player-start transform exists, launches Playground through the definition, verifies the same authored resource reaches `WorldSession` and the wrapper before FuncGodot builds the package-local map, restarts into a fresh session/world while retaining the same authored definition as configuration, and confirms raw development scenes carry no definition. The authoring regression supplies the additional point-entity/player-start resolution and reimport-stability proof.

## World-session lifecycle and replacement

The production `WorldSession` path is exercised directly and through the application. A session builds with processing disabled in `READY`, enters `PLAYING` only through explicit permission, may enter explicit `PAUSED` without becoming lifecycle-stopped, stops coherently in `STOPPED`, and tears down to `EMPTY` with world/player/session/registry references invalidated. Before `READY`, the session registry build rejects missing/duplicate persistent IDs and duplicate non-empty semantic `content_id` values on explicitly identity-bearing authored runtime nodes, leaving no partial registry and tearing the invalid world down. Typed mission sessions then validate current mission content: required definition metadata is rechecked, `player_start_selector` must resolve to an authored player-start role, at least one persistent mission exit must exist, and the runtime world must expose exactly one `vark_player`. A valid build owns the current-world registry for its lifetime. The application can pause/resume the current session, stop/start it for lifecycle work, restart or mission-transition through stop/teardown/fresh replacement, and exit to a coherent no-world state while persistent UI remains application-owned.

The lifecycle regression attaches representative `Timer` and deferred work beneath the real session owner. A stopped session freezes the timer; restarting tears the old session down before yielding, and neither the old timer nor deferred callback can fire afterward. The identity regression additionally retains an old registry reference across teardown and proves its indexes were cleared before world destruction; a replacement session cannot resolve an old-world identity. A control probe under the current replacement proves ordinary session-owned work executes normally while its session is alive. The replacement receives a fresh runtime world instance, session ID, and entity registry while reusing authored `PackedScene`/`MissionDefinition` resources only as configuration, so runtime metadata/state does not leak through shared authored resources or the persistent application owner.

The production entity registry is now the first real mutable world-scoped service. No semantic event queue or general scheduler is invented by this fixture; those systems remain future roadmap work and must follow the same current-`WorldSession` ownership boundary when introduced.

## Phase 4.1 save coordinator and transactional shell restore

The application regression suite now exercises the first save/restore ownership seam without pulling Phase 4.2 semantic-system snapshots or Phase 4.6 durable disk format forward. `VarkSaveCoordinator` runs capture after the `WorldSession` stable-boundary consequence pass, binds every request to its source session/target boundary, and copies only detached value data: source/boundary provenance, gameplay simulation time, rebuild resource paths, and the input-owned player view pose. A later application-frame commit stage models post-capture encoding/writer ordering while remaining in-memory for 4.1.

`save_coordinator_regressions.gd`, wired through the authoritative Application suite and therefore `tests/run_all_tests.gd`, proves: a restart cancels a still-pending source request rather than retargeting it; capture occurs at the requested next stable serial and includes current event-cadence look; later live/caller mutation cannot alter the stored snapshot; captured data can commit after its source session is destroyed; a newer request supersedes an older captured generation for the same slot; committed reads are detached; quickload ignores a newer in-progress request and consumes only the last fully committed slot; and the sole-world restore path rebuilds a disabled candidate, restores gameplay time/view orientation, then resumes exactly one authoritative PLAYING session with gameplay/look input enabled. No manual acceptance is required for this infrastructure-only item; durable filesystem behavior and broad semantic/transient restoration remain later Phase 4 coverage.


## Phase 4.2 semantic snapshots and ordered reconstruction

The Application suite now wires `tests/application/semantic_snapshot_regressions.gd` against the real Integrated Slice. It extends the 4.1 detached quicksave envelope with explicit semantic ownership rather than a node-tree dump: object-existence sections, persistent-entity snapshots keyed by persistent ID, player semantic state, stable non-entity semantic owners, and an explicit mission-script section.

The current slice assigns persistent IDs to its ordinary door, both ordinary props, gameplay light, and existing guard. Door/prop implementations reuse their established semantic capture/apply seams; gameplay light persists enabled/visible truth; the guard persists life state, spatial state, and the current resolved patrol-goal semantic ID. Player semantic capture covers body transform/velocity while the 4.1 input-owned view pose stays separate. Objective/fact state, objective/exit attempt/completion counters, one-shot route-trigger arming/counts, and guard-awareness history use stable semantic-save-owner IDs. No current slice system owns independent mission-script state.

The regression deliberately captures a non-default coherent world: partial door progress, moved settled prop, disabled gameplay light, changed player/view pose, a guard whose patrol goal has already changed from its initial choice, completed objective plus an earlier blocked-exit statistic, a consumed one-shot objective trigger, and real guard visual-awareness history. It then mutates those live owners after capture and quickloads. The replacement must be a fresh world, must reconstruct the saved values by stable identity while `RESTORING`, must have no queued restore-time semantic gameplay events when play begins, and must retain the resolved guard goal after the slice's deferred navigation rebuild.

Object existence is explicit even though the current slice has no permanent authored removals or runtime-created persistent entities: both sections must be empty, and unexpected non-empty data fails closed instead of being skipped. `mission_script_state` is likewise explicitly empty because no current save-owning mission script exists. This is coverage of the ordering seam, not an implementation of future tombstones/runtime-spawn persistence. Player traversal restore policy remains Phase 4.3; representative moving door/prop/alert/body transient policies remain Phase 4.4; compatibility/durable filesystem behavior remains Phase 4.6.


## Phase 4.3 player transient/traversal restore policy

`tests/application/player_restore_policy_regressions.gd` is wired into the Application suite and uses the existing sprint/jump and ledge-traversal fixtures through the production application/session restore path. Player snapshots now declare source stance/traversal plus their restore policy instead of attempting to serialize live ledge candidates, collider RIDs, mantle/corner route objects, timers, or continuations.

Standing/moving, fully crouched, and ordinary unsupported airborne states restore directly. Crouch restore reconstructs the fresh player's requested stance endpoint immediately so capsule, head, visual geometry, and ledge-detector body geometry agree before gameplay resumes. A mid-transition stance is normalized to its already-requested standing/crouched endpoint.

Catching, hanging, cornering, and mantling are intentionally normalized to ordinary airborne at the captured collision-safe body transform with zero traversal-owned velocity. The fresh player discards all ledge runtime candidates/routes and applies a six-physics-frame traversal re-entry guard; gravity can move the body away before normal hang/mantle acquisition resumes. These states remain save-requestable—the policy is normalization on load, not a save lockout.

WorldSession validation remains exact for every non-player semantic owner. The only policy-aware exception is the player snapshot: `validate_restored_semantic_state()` must prove the restored transform, velocity, stance endpoint, normal traversal state, and (for normalized traversal) active short re-entry guard before the candidate can leave `RESTORING`.


## Phase 4.4 other transient-state save policy

`tests/application/transient_state_restore_regressions.gd` is wired into the Application suite and runs against the real Integrated Slice through production Application/WorldSession capture and replacement.

Door motion is semantic phase + open fraction, not an engine animation/timer. The regression saves a door while opening, stops the source session and allows application frames to pass, then restores the exact saved fraction/gameplay time and proves progress resumes only on later world physics frames. Obstruction blocker identity remains transient and is reacquired by ordinary sweep logic.

Thrown/falling ordinary props restore semantic motion kind, upright transform, and linear velocity. Physics-server direct state, contact/rest bookkeeping, impact callbacks, angular response, and temporary player-collision-ignore state are not serialized; a restored moving prop is reactivated and continues under ordinary rigid-body simulation.

The Integrated Slice guard's current investigation/alert equivalents are `heard_noise` and `saw_player`. The regression reaches `heard_noise` through the real semantic `gameplay.sound` → acoustic propagation → listener path, and reaches `saw_player` through the existing exposure/vision path. Both restore their semantic awareness/counters without replaying the source sound or visual consequence.

Unconscious and dead remain life states of the same registry-addressable guard actor/body. The regression drives the existing queued semantic life-state transition path, moves the non-conscious body, saves/restores it, and verifies life state/body transform survive while navigation remains inactive. There is no separate corpse entity.

The current slice has no other save-owning gameplay duration such as investigation decay, stun, bleedout, or animation callback. Door transition fraction is therefore the representative long-running duration proof: saved semantic progress plus authored duration determines remaining simulation work, and paused/load wall-clock time does not advance it.


## Phase 4.5 snapshot coherence, restore suppression, ordering, and failure safety

`tests/application/snapshot_coherence_regressions.gd` is wired into the Application suite. It queues an exit attempt, objective completion, and gameplay sound before one requested save boundary while also starting door motion and applying immediate event-driven mouse look. The save coordinator may capture only after the next WorldSession stable consequence pass. The captured snapshot must therefore contain the ordered blocked-exit statistic + completed objective + consumed one-shot trigger + heard-noise awareness + in-progress door together, while its input-owned view pose and player transform match the same already-applied request-side orientation.

The regression then mutates live owners and restores the snapshot through the normal sole-world replacement path. The old session must be gone, exactly one replacement session may remain, semantic owners must equal the captured values, and the replacement event queue must be empty. This is the explicit restore/`after_restore` suppression proof for the current slice; no source objective/sound consequence is replayed. Loot tombstones, alarms, and broader rule owners do not exist yet and must extend this same contract when introduced.

Source-session binding is exercised across mission transition and exit in addition to the restart/load coverage already present in `save_coordinator_regressions.gd`. A manually held top-level operation must block load, restart, mission transition, exit, and new save requests without changing the current session. The existing same-slot generation regression remains the authority that a captured older save becomes superseded when a newer request exists and cannot overwrite that newer request.

Failure safety covers both sides of the sole-world topology. A malformed snapshot rejected by coordinator validation leaves the current PLAYING source session and input domains untouched. A structurally valid but semantically invalid player snapshot is allowed to enter replacement, must fail closed during RESTORING, discard the candidate, and leave the application in one coherent menu/no-world state with input disabled and no active top-level operation. The same application must then be able to launch a fresh world successfully.


## Phase 4.6 compatibility metadata and durable quicksave

`application/save_format.gd` owns the current global save-format version. Every WorldSession save envelope records that version separately from `mission_id` and `mission_content_revision`. MissionDefinition-backed worlds take mission identity/revision directly from the authored definition; raw scene development fixtures use the explicit `dev_scene:<world_scene_path>` compatibility identity with revision 1 and remain non-mission development targets.

SaveCoordinator validation performs installed-content compatibility checks before Application replacement. Unsupported global versions, changed mission IDs, and changed MissionDefinition revisions fail closed with explicit no-migration errors. WorldSession repeats the same compatibility check against the actual non-playing restore candidate before applying semantic world state.

Committed quicksaves are binary detached-Variant files under `user://vark/saves`. Object serialization/deserialization is disabled. Commit writes a `.new` file, flushes/closes it, rereads and validates the complete snapshot plus exact value round trip, and only then promotes it over the existing final slot with one same-filesystem rename. A final slot is therefore the commit point. A stale temp beside an existing final is discarded; a valid temp can only recover into an absent final.

`tests/application/save_compatibility_regressions.gd` uses an isolated test directory and the real authored Playground MissionDefinition. It proves the three compatibility fields, pre-destructive version/mission/revision rejection and error text, validated durable replacement, no leftover committed temp, and durable quickload after destroying the entire source Application. The fresh coordinator must select the valid final snapshot rather than an uncommitted temp artifact and restore the expected player/mission state through the ordinary Application/WorldSession path.


## Phase 4.7 crude hostile-interaction compatibility proof

The project declares an unbound development `attack` InputMap action. `ApplicationInputBoundary` samples it as a separate one-frame gameplay edge with the same domain-loss/held-until-release behavior as interaction; the input-boundary regression covers first-frame, same-frame cached, held-next-frame, disabled, resume-while-held, release, fresh re-press, and edge-expiry behavior.

`PlayerHostileInteraction` is a deliberately tiny RefCounted player component. On a fresh attack edge, while ordinary hand actions are available, it center-raycasts within the crude hostile range. A conscious guard hit queues detached `combat.crude_hostile_effect` data addressed by persistent/actor IDs. It never directly mutates actor state.

`VarkGuard` registers the crude hostile event alongside its existing actor life-state event. For the only supported development effect (`knockout`), its synchronous semantic handler queues `gameplay.sound` with kind `combat.hostile_impact` and then queues the existing unconscious life-state request. Because nested events append FIFO, the acoustic event reaches conscious listeners before the actor life-state transition is consumed. The Integrated Slice reaction accepts that sound kind through its existing acoustic-listener callback; after the guard becomes unconscious, current awareness normalizes to `inactive` while the resolved heard evidence remains in the reaction semantic snapshot.

`tests/application/hostile_compatibility_regressions.gd` positions the real Integrated Slice player for a deterministic center-view guard hit, drives the application-owned attack action, checks the transient heard-noise evidence and final unconscious/inactive state, holds attack for a second frame to prove no replay edge, commits an isolated quicksave, changes the live guard to dead, and quickloads. The fresh replacement must restore unconscious body state, inactive awareness with exactly one hostile-impact evidence record, zero pending semantic events, and remain stable over resumed simulation.

This is not combat implementation. It intentionally adds no player-facing attack binding, animation, weapon/inventory model, health/damage numbers, timing/tuning, block/parry, hit feedback, or combat AI.


## Phase 5.1 surface profiles and gameplay noise

`gameplay/noise/surface_profile.gd` defines the reusable authored surface-noise Resource. A valid profile has a non-empty semantic `surface_id` and positive finite base footstep strength. Footstep sound identity is derived as `footstep.<surface_id>` so authoring cannot accidentally disagree about the surface ID and semantic sound kind.

`VarkFootstepSurface` references a profile instead of owning duplicated mission-local ID/strength fields. `VarkPlayerFootstepEmitter` contains the Integrated Slice footstep behavior: grounded horizontal-distance cadence, current-surface lookup, and WorldSession `queue_gameplay_sound`. Movement modifies the authored surface source strength through the player's existing semantic movement state: crouch uses the accepted 0.45 scale, ordinary standing movement uses 1.0, and locomotion's real sprint intent uses a 1.35 scale, preserving the locked `crouched < normal < sprinting` relationship without deriving stealth truth from presentation audio or guessed velocity.

`VarkPlayerFootstepEmitter` also emits a detached observational `gameplay_noise_emitted` signal after a semantic step is successfully queued. `VarkNoiseMeter` is a development-only observer directly below the Integrated Slice exposure panel: it displays the exact emitted semantic footstep source strength/kind/gait for a short presentation pulse. It does not own hearing truth, propagation, or a production player noise HUD; `GAME_VISION.md` still requires sound readability primarily through hearing and NPC reactions.

`tests/noise/run_noise_tests.gd` is an authoritative top-level suite. It validates profile authoring and fail-closed invalid data, reusable surface/profile composition, then launches the real Integrated Slice through Application/WorldSession. It verifies stone and carpet use the authored profile resources, standing footsteps emit the expected semantic kind/base strength and reach the real guard acoustic listener, crouch changes only emitted strength while retaining carpet identity/kind, and sprinting on the same carpet produces 0.27 versus 0.20 walking while crouched carpet remains 0.09. The development loudness meter must show those same source values/gaits rather than inventing parallel noise truth.

The existing Phase 3 Integration suite continues to protect the accepted cross-system route, but now reads the surface strength from the profile-derived semantic summary. Prop impacts, doors, speech, and hostile-impact sounds remain direct users of the same three-field `gameplay.sound` contract; 5.1 does not change propagation or hearing thresholds.


## Phase 5.2 acoustic model hardening and inspection

The established acoustic model remains authored spaces connected by portals. Same-space propagation uses distance attenuation directly; cross-space propagation chooses the minimum-cost authored portal route where distance contributes `DISTANCE_DECAY_PER_METER * meters` and each portal contributes `-log(transmission)`. Disconnected spaces remain unreachable.

`VarkAcousticPortal` has one transmission rule for openings. Unlinked portals are constant openings at their authored `open_transmission`. Door-linked portals query only the ordinary world object's `get_acoustic_openness()` value and interpolate from configured closed to open transmission. The Acoustic suite proves the real ordinary door produces the existing 0.08 / 0.54 / 1.00 transmission values at closed / half-open / open; no separate acoustic door state exists.

`VarkAcousticPropagation.get_debug_inspection()` exposes detached observational data: topology counts/errors, current portal states, and the most recently handled semantic sound with each listener's heard/muted result, source/propagated strength, threshold, path distance/cost, and authored portal route. This data is not persisted and does not influence route selection.

`VarkAcousticDebugInspector` formats that inspection into a development Label3D. The Acoustic Lab includes it alongside the existing listener markers. The authoritative Acoustics suite verifies the readout reflects constant openings, live ordinary-door openness/transmission, and the last impact's door/corner listener routes. Missing door IDs referenced by authored portals are explicitly validated as topology errors.


## Phase 5.3 gameplay lighting/exposure and light gem

`VarkGameplayLight` remains the explicit semantic stealth-light source. Its visual OmniLight3D properties can make the world bright, but only nodes carrying the gameplay-light contract participate in exposure. Each sample now also returns detached debug state (enabled, visible, semantic strength/range, active flag) alongside distance/occlusion/contribution.

`VarkGameplayExposure` owns gameplay truth only. It keeps the accepted three vertical player-body sample points, physics-ray occlusion, linear distance weighting, additive source contribution, and 0–1 clamp. It reports `source_count` separately from `active_light_count`, includes per-light state/visible-sample diagnostics, and emits a detached `exposure_sampled` observation. It no longer owns Label/ProgressBar nodes.

`VarkLightGem` is the reusable observer/UI seam. It reads the exposure owner's detached summary, renders the existing ten-segment numeric gem, updates the ProgressBar, and prints source state, contribution, and visible sample counts. Both Exposure Lab and Integrated Slice attach the same light-gem script.

The Visibility suite keeps the established dark/edge/partial/full, all-samples-occluded, and two-light-additive barriers. It adds a brighter decorative-only OmniLight3D at a separate marker and proves exposure stays dark with only the two explicit gameplay sources listed. It also disables and hides the key gameplay light independently, proves contribution/active-state removal and recovery, then verifies the reusable light gem exactly matches current semantic exposure. Phase 3 Integration additionally checks the Integrated Slice light gem observes the same crouched exposure used by guard vision.


## Phase 5.4 NPC perception/awareness

`gameplay/npc/guard_awareness.gd` is the reusable guard-awareness owner. The Integrated Slice's historical `guard_reaction.gd` path is now a compatibility wrapper so existing authored scene references remain stable. The semantic state machine is unaware → suspicious/investigating → searching → recovering, with confirmed vision entering alerted/pursuit and actor life-state forcing inactive.

All awareness durations are remaining gameplay-simulation seconds advanced from `WorldSession.gameplay_time_seconds`. Weak locally propagated hearing can create suspicion; stronger heard evidence records an investigation target at the acoustic event origin. Vision resolves range, facing, and physical LOS before exposure rejection. Ordinary confirmation still uses the existing 0.28 exposure threshold, while a narrow locked-design darkness exception confirms an unobstructed player within 1.50 m when the guard's facing dot is at least 0.75; darkness remains protective outside that point-blank direct-facing case. Confirmed vision updates a local last-seen target and temporarily owns guard navigation through the awareness-target seam. Lost confirmed sight starts an alert-loss grace; expiration searches the persisted last-seen position. No random search choice exists yet, so there is nothing to reroll on restore.

The awareness semantic snapshot stores state, evidence counters, last heard/vision diagnostics, resolved last-seen/investigation target, target-present flag, remaining state duration, and remaining alert-loss duration. Restore reapplies the same temporary navigation ownership before play resumes. The old debug `state` key remains only for Phase 3/4 fixture compatibility; new work must read `awareness_state`.

`tests/awareness/run_awareness_tests.gd` is an authoritative top-level suite using the real Integrated Slice. It proves weak suspicion/decay, strong investigation/search, deterministic target preservation, save/quickload of search stage + remaining simulation duration, point-blank direct-facing confirmation at effectively zero gameplay exposure, ordinary exposed visual pursuit, lost-sight grace, last-seen search, recovery, and return of navigation ownership to patrol. The suite uses shortened exported durations only to keep CI fast; production defaults remain longer.

Phase 5.4 manual acceptance is complete. After the green implementation/fix-forward runs, the user iterated door traversal, darkness/point-blank sight, movement-noise readability, pursuit/loss, and recovery, then explicitly advanced to the immediate dependent 5.5 item. The old single-point stationary search presentation is intentionally superseded by 5.5 rather than treated as a reason to keep 5.4 open.


## Phase 5.5 advanced search / local investigation

The production-target search remains TARGET for subjective feel but now uses explicit evidence uncertainty instead of the first fixed-radius waypoint proof. `guard_awareness.gd` owns the evidence anchor, stable search seed, stage, current uncertainty radius, confidence, gameplay-time age, resolved point array/index, visited locations, scan state, and residual recovery alertness. None of those fields contains hidden player position.

`VarkGuard.resolve_local_search_points(anchor, radius, count, variation_key, excluded_points)` samples/project candidates on the synchronized navigation map and scores them only from evidence proximity, separation from already searched positions, route/path cost, and a stable deterministic variation term. The variation key is derived from stable semantic evidence inputs; the resolved candidate array is then saved directly. Search stages expand radius only after exhausting their current candidates, lowering confidence as uncertainty grows. New heard/seen evidence recenters the process at high confidence rather than extending stale knowledge.

Search execution now has a separate semantic cadence layered over the spatial planner. Patrol movement remains the base speed; investigation uses a slightly cautious profile, each search leg resolves a slower confidence-sensitive speed with stable variation, and confirmed pursuit uses a substantially faster profile. At a search destination the navigation goal remains intact but locomotion is paused. The guard resolves an arrival pause, one-to-three directed look turns, held gazes, pauses between looks, and a departure pause. Timings, look count, direction, and per-leg speed come from the stable search seed/action serial. The previous sinusoidal in-place sweep is removed. Ordinary hearing/vision remain live during every action, and new evidence interrupts immediately.

Production active-search duration is now intentionally long enough for cautious movement and observation to dominate the behavior rather than rapid waypoint traversal. Active search remains bounded by uncertainty radius and gameplay time. Entering recovery releases navigation ownership to patrol immediately but leaves a gameplay-time residual-alert value. While that value remains high, the same locally heard sound can cross a temporarily reduced investigation threshold; the bonus decays to zero before fully unaware behavior.

The awareness semantic snapshot now stores the resolved candidate order plus stable seed, stage, uncertainty radius, confidence, search age, visited positions, current search action, action duration/remaining time, look directions/count, resolved movement-speed scale, and residual alertness. The authoritative Awareness suite proves hidden-player motion cannot change resolved truth, confidence/uncertainty progression is simulation-time based, search locomotion is slower than patrol while pursuit is faster, stationary search actions actually pause navigation motion, quickload restores the already-resolved action instead of rerolling timing/pose, and residual alert still decays/re-alerts correctly. Exact cadence, patience, look presentation, and speed ratios remain focused user playtest territory.

## Gameplay input boundary and view pose

The production application path binds the current real player to one persistent application-owned input boundary before the session enters ordinary play. That boundary owns gameplay/look permission and supplies locomotion with at most one `PlayerCommand` snapshot per physics frame. Standalone `Player.tscn` movement fixtures retain direct sampling only as a focused non-application fallback so the pre-existing real-player behavior traces remain usable; that fallback is not the production ownership path.

The application regression proves continuous movement/sprint state can remain held across gameplay frames while fresh jump and primary-interaction presses exist for one gameplay frame only. A disabled gameplay domain produces neutral locomotion and interaction intent; on resume, continuous movement/sprint reflects current physical state while jump/interaction gestures held across domain loss remain suppressed until release and a fresh press. Domain loss also clears the player's representative buffered airborne-mantle gesture and disables the bound player's interaction selector so highlight cannot remain stale under application/UI ownership. Interaction remains a separate sampler rather than expanding locomotion `PlayerCommand`; future combat/inventory actions with meaningful pressed/released semantics must extend this same one-frame edge/cancellation contract through their own domains.

Look input remains event-driven through the application boundary and is not delayed to the physics tick. The regression applies mouse motion and observes the input-owned view pose immediately, verifies disabling the look domain prevents view mutation, and verifies application view-pose sampling returns detached value-owned data. Escape remains application input for the accepted mouse-release behavior. Existing movement/traversal traces remain the objective behavior barrier for unchanged controller response.

## Minimal interaction contract

Phase 3.1 uses the real player camera and Godot physics query rather than a synthetic target list. `PlayerInteraction` selects only the first center-view physics hit within its short range, climbs only that hit to a `vark_interactable`, asks the object for current-state eligibility, and owns highlight changes. The application input boundary supplies the separate one-frame primary-interaction edge and disables the selector with the gameplay domain. A second player-owned availability gate is the deliberate future seam for carrying/body ownership; tests can suppress and restore ordinary interaction without modifying either probe.

`scenes/InteractionLab.tscn` is a development fixture, not a production door/prop implementation. Its Door Contract Probe and Prop Contract Probe implement the same three-method contract, while a divider gives deterministic occlusion coverage and the prop can become ineligible after use. The focused application regression launches that scene through `VarkApplication`/`WorldSession`, verifies center target/highlight, range, occlusion, state eligibility, one-use-per-fresh-press, central availability, and input-domain stale-edge behavior. The visual readability of highlight/no-crosshair feedback and unchanged accepted movement/look feel remain focused user playtest territory.

## Application control arbitration and gameplay time

The application exposes explicit exclusive control modes for gameplay, pause menu, inventory, objectives, map, cutscene, and menu ownership. The regression drives every non-gameplay mode through the real application/session/input path and proves they all place the current session in `PAUSED`, disable gameplay/look input, prevent manual re-enabling of those world domains, and leave the world subtree unable to process. Returning to `GAMEPLAY` resumes the same session before restoring gameplay/look input.

Application/UI input remains live outside the paused session: the input boundary delivers application events while gameplay/look are disabled, and a representative timer under persistent `UIRoot` completes while an equivalent session-owned timer remains frozen. The fixture also proves player pose and the world-session gameplay-time counter remain unchanged across multiple paused physics frames. After resume, gameplay time and the paused session timer continue normally. A jump held across the ownership change remains suppressed on resume, reusing the 1.3 gesture-cancellation contract rather than inventing a pause-specific input path.

`WorldSession.gameplay_time_seconds` is the current minimal simulation-time owner. It advances only during `PLAYING` physics steps and resets with fresh session lifetime. No gameplay system yet uses a wall-clock duration, scheduler, or serialized engine `Timer` as semantic truth. Future timed gameplay extends this owner/contract rather than adding independent clocks.

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

## Ledge catch / hang / release

A real `Player.tscn` falls into an ordinary wide ledge, enters the production catch transition, settles into a stable unsupported hang, and drops cleanly through the normal crouch release path.

## Shimmy / supported corner

The same real-player fixture shimmies in both directions and deliberately releases/re-presses endpoint intent to traverse a supported physical right-angle corner, finishing attached to the adjoining ledge face.

## Mantle

From the real hanging state, a no-direction jump request traverses the production mantle path onto the valid ledge top and finishes grounded without stale traversal velocity.

## Drop/regrab suppression

Dropping from a hang cannot immediately recatch the same local ledge while the player remains in its suppression region. After leaving that region, returning to the same approach permits a later legitimate catch/hang again.

## Controller behavior traces

The authoritative movement barrier also drives fixed real-player command sequences and samples one read-only semantic movement snapshot instead of private controller/component call order. The traces protect representative walk startup/sustain/stop, crouch movement and stance changes, ordinary jump and sprint-jump takeoff, a real step crossing, and ledge catch/hang/shimmy/release/corner/mantle transitions. Checkpoints assert position, velocity, support class, stance, and traversal state with explicit numeric tolerances where physics requires them.

Mouse look is deliberately not quantized into these physics traces; accepted event-driven look cadence is exercised separately through the application input-boundary regression.

No future-system coverage below should be reported as existing until actually implemented.

---

# Required future fixture strategy

These requirements become active when corresponding systems are implemented.

## World-session lifetime fixture

Phase 1.1–1.6 now prove application boot/menu ownership, current session identity once gameplay starts, one exclusive top-level-operation guard, non-playing build, explicit entry to play, explicit pause/resume distinct from lifecycle stop, synchronous teardown, restart/ordinary replacement, exit back to the application menu, fresh runtime state, stale-work rejection, separation between persistent application/authored configuration and session runtime state, application-owned gameplay/look input permission with stale intent/gesture cancellation, exclusive application/UI/cutscene ownership, world-session gameplay-time pause semantics, an application-owned setting surviving world replacement, and curated development-target selection through the same lifecycle/input path.

Phase 2.1 adds one package-local TrenchBroom source/wrapper to that already-proven lifetime path. Phase 2.2 adds the authored `MissionDefinition` configuration boundary: a mission session carries the definition that selected its world/map, restart reuses that authored configuration while creating fresh runtime state, and teardown clears the session reference. Phase 2.4 adds pre-`READY` authored persistent-identity validation, Phase 2.5 extends that boundary to duplicate non-empty semantic `content_id` values, and Phase 2.6 adds the first real mutable world-scoped service: a current-session entity registry that is cleared before teardown and rebuilt only from the replacement world. Phase 2.7 adds the first real semantic point roles without changing that ownership. Phase 2.8 proves representative source edit/rebuild/run through the same wrapper/session path. Raw development worlds continue to have no invented mission definition or persistence requirement. Future semantic event queues, gameplay timers, deferred/async work, and other mutable services must remain current-session-owned as those real systems arrive. Phase 1 does **not** need a simultaneous old/candidate world fixture.

When Phase 4 implements real restore, extend this fixture to the chosen restore topology. If old and restored worlds overlap in memory, prove their mutable world-scoped services/resources remain isolated and they never both produce authoritative gameplay consequences. If restore uses sole-world replacement after prevalidation, prove failure reaches the defined coherent recovery state.

## Gameplay-input-domain fixture

Phase 1.3–1.6 now prove for the real production player/application path:

- application ownership supplies/suppresses current locomotion gameplay intent rather than leaving global permission inside locomotion;
- one locomotion gameplay command frame is sampled at most once per physics tick;
- continuous movement/sprint held state persists while physically held and permitted;
- the existing jump pressed edge lasts one gameplay frame;
- disabled gameplay produces neutral current intent;
- domain loss prevents stale held jump intent from replaying, cancels the representative buffered mantle gesture, and requires release plus a fresh press before that edge-dependent gesture can begin again;
- mouse look retains event-driven cadence and can be gated independently without physics-tick quantization;
- the application can sample detached current input-owned view pose data;
- pause/menu/inventory/objectives/map/cutscene ownership disables world gameplay/look input while application/UI input remains live;
- resuming gameplay through application ownership keeps the held-jump gesture blocked rather than replaying it;
- the main-menu shell begins without a world/input owner, and both New Game and curated Development Launch enter the same proven input boundary rather than a direct scene/polling path;
- the existing movement/traversal behavior traces remain green through the same authoritative all-tests barrier.

As real interaction/combat/inventory action domains arrive, extend this fixture to prove:

- interaction/combat/inventory are not forced through locomotion `PlayerCommand`;
- their pressed/released edges each exist for one gameplay frame only;
- a real hold/release action loses ownership cleanly and requires a fresh initiating press rather than firing after resume;
- pause/UI/cutscene gating clears their transient intent while application/UI input continues to operate;
- world gameplay samples the current input-owned view pose coherently at the controlled simulation/stable boundary used by those systems.

## Gameplay-time fixture

Phase 1.4 now proves the foundational clock/pause boundary:

- `WorldSession` owns gameplay time for its lifetime;
- gameplay time advances during permitted `PLAYING` physics steps;
- application-owned pause modes stop the whole ordinary world subtree and leave gameplay time unchanged across paused physics frames;
- persistent application/UI processing continues while the mission world and its session-owned timer work are paused;
- resume continues gameplay time from the same semantic value rather than adding elapsed paused wall-clock time.

As real timed gameplay appears, extend this fixture to prove guard search, mechanism progress, stagger, deployable arming, delayed mission actions, and other meaningful durations consume simulation-owned progress rather than wall-clock deadlines. Loading/restoring must not silently advance those durations; save/restore preserves meaningful stage/progress/remaining simulation time where required; no test should depend on serializing `Timer` objects or coroutine stacks as gameplay truth.

## Persistent-ID/reimport fixture

Phase 2.3 uses the real `missions/playground/mission.map` as the base source for a temporary authoring fixture and proves the source/writeback mechanics before production entities depend on them: the Vark TrenchBroom FGD explicitly declares `persistent_id` on the mapper-facing `func_detail` proof entity, move/reorder preserves existing IDs, duplication is repaired to a distinct ID while the first source owner stays stable, delete/recreate gets a new ID, generated/repaired IDs survive real FuncGodot parsing, valid source is not rewritten, repeat repair is idempotent, stale source hashes cannot overwrite newer mapper text, the refreshed mapper config has a valid PNG material path, and any external repair write requires a TrenchBroom reload before further edits.

Phase 2.4 wires the same Vark FGD into runtime FuncGodot map settings, carries authored persistent IDs onto generated nodes, and makes missing/duplicate persistent IDs fail closed at `WorldSession` build with useful paths. Phase 2.5 adds optional mapper-owned `content_id`, proves it survives the real FuncGodot path, treats blank as unaddressed, and makes duplicate non-empty semantic IDs fail closed with both owner paths. Phase 2.6 registers those validated persistent/non-empty semantic IDs in the current `WorldSession`, proves successful/missing lookup plus teardown/replacement isolation, and still does not define authored reference schemas. Phase 2.7 adds the mapper/runtime vocabulary for player start, generic marker, and exit and directly declares both identity fields in each point's own FGD block so TrenchBroom treats the on-disk point keys as real entity properties; the tracked Playground proves those points build and register. Phase 2.8 adds an automated representative player-start edit on a disposable real-Playground copy, read-only no-repair verification, real wrapper rebuild to `PLAYING`, stable persistent/content IDs, and an intended-only transform change. Phase 2.9 closes the first real authored-reference/required-object boundary by validating the player-start selector through the current registry, requiring an authored persistent exit, rechecking typed mission metadata, and failing cleanly on zero or multiple runtime players before `READY`. The accepted Windows mapper run also proves the actual TrenchBroom save/reopen/edit loop, including a clean source diff after restoring the authored start.

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

Phase 3.6 currently prototypes an authored acoustic space/portal graph rather than radius-only or single-ray hearing.

The focused Acoustics suite protects:

- same-space world-distance attenuation without a portal hop;
- no route/no hearing for a nearby but disconnected authored space;
- multi-portal routing through an L-shaped/corner connection whose path is longer than the straight source-listener distance;
- continuous transmission through the **same ordinary door** using its existing `get_acoustic_openness()` seam;
- semantic `gameplay.sound` delivery only at the accepted WorldSession consequence point;
- representative threshold relationships for footstep, speech, and impact source strengths without presentation-audio authority;
- malformed duplicate/missing topology failing closed with useful diagnostics;
- TrenchBroom FGD export with `vark_acoustic_space` as a native solid/brush class and `vark_acoustic_portal` as a point class; the regression explicitly rejects the superseded mapper-half-extent/display-model path;
- real FuncGodot import of two rectangular acoustic-space brushes plus portal IDs/links/transmission tuning, with no generated visual mesh and zero collision layer/mask on the runtime acoustic helper;
- explicit protection that the current authoritative map scale is 32 mapper units per Vark world meter and that representative mapper brush dimensions import to the expected Vark world-space half-extents.

The development Acoustic Lab supplies the focused player-facing proof with an open room, door-separated room, disconnected room, and two-portal corner route. The Windows user/playtester accepted its acoustic intuition, and the Windows TrenchBroom 2026.2 mapper pass accepted the native acoustic-space brush plus portal edit/save/reopen/reimport workflow. The first TrenchBroom 2026.2 mapper pass failed because acoustic-space extents were editable but visually invisible, and the following display-model attempts still produced a square/cube rather than a trustworthy independently editable volume. The root correction is architectural: the pinned 2026.2 manual distinguishes point entities from brush entities and documents creating brush entities by selecting brushes and converting them through the context menu. `vark_acoustic_space` therefore uses the native brush-entity workflow now; the actual rectangular mapper brush is the visible volume, while FuncGodot derives the runtime acoustic box from that brush and imports no presentation mesh. The exact manual snapshot supplied during this diagnosis is versioned at `docs/reference/trenchbroom-2026.2-reference-manual.html`. Phase 3.6 remains pending until a Windows TrenchBroom 2026.2 save/reopen/reimport pass confirms this native brush workflow is low-friction. Do not stabilize the Phase 5 production acoustic API or tuning from the deterministic spike alone.

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

### Drop/throw/rest

Held object may be dropped/thrown, collide/move while remaining top-up, then return directly to the settled stationary contract rather than indefinite rolling/sliding/spinning or an intermediate orientation-correction phase.

### Held ordinary prop interaction contract

Prove a held ordinary prop uses intended first-person held presentation, cannot be freely rotated, and suppresses ordinary world interaction through central interaction/input ownership. Doors/switches/loot should not each need private `is_holding_prop` logic.

### Save/load

Settled/transient representative prop state restores coherently without extra motion or non-upright orientation.

## Nav/reimport fixture

Phase 3.7 still owns the mapper/reimport proof, while the 5.4 fix-forward hardens the same ordinary-door navigation seam:

- `vark_guard` and `vark_patrol_point` remain authored through the normal Vark FGD/FuncGodot path; patrol/search/pursuit continue to provide only semantic destinations;
- Guard/Nav Lab and the Integrated Slice still runtime-bake their tiny proof NavigationMeshes from real static world geometry. These two proof worlds explicitly use synchronous map/region iterations so headless and interactive runs observe the same deterministic graph barrier;
- each ordinary door configures one fixed, top-level `NavigationLink3D`. Before baking, the door contributes a carved obstruction covering the complete controlled approach/crossing lane, so ordinary navmesh movement cannot cut diagonally through the moving leaf;
- after the carved region synchronizes, the door projects both link endpoints onto the actual polygons on opposite doorway sides, binds/enables the link, and the world waits for the finalized map iteration before configuring the guard;
- the guard enables full path metadata and reacts only to `NavigationAgent3D.link_reached` for its configured door. Nearby leaf collision, distance, search beside a door, and the door's current angle do not create door intent;
- a local traversal has only WAITING_OPEN and CROSSING behavior. If the entry-to-exit capsule corridor is already clear, the guard crosses without touching door state. Otherwise it retries idempotent OPEN until the real corridor fits, then crosses the reserved link lane and resumes the current semantic destination;
- there is no AI close/reposition/reopen recovery. An already-open door therefore stays open during a required traversal, including the former open-leaf side-approach case;
- player CLOSE may still physically contact a guard that is already crossing. That active traversal may request OPEN again after real contact without creating a second logical traversal;
- a player may obstruct an opening sweep; the door remains physically safe and the same traversal retries OPEN after the blocker leaves;
- local link metadata/traversal failure is diagnostic and nonfatal. It must never clear the guard's configured navigation state or discard patrol/awareness truth;
- a disposable mapper edit still rebuilds the same mission package, rebakes the carved region/link graph, and proves patrol plus ordinary-door traversal continue after reimport.

The Navigation suite owns this contract. It proves synchronized link setup, closed-door opening, passive already-open crossing, same-side door indifference, crossing contact recovery, blocked-opening retry, nonfatal local traversal failure, and map edit/reimport. Diagnostics include guard traversal state/counters plus the door link's configured/map-bound/iteration/end-point summary.

The Application door regression continues to own physical ordinary-door behavior and save semantics: idempotent OPEN, safe sweep obstruction, semantic phase/fraction restore, and blocker handling. The explicit traversal layer consumes those physical facts but does not serialize engine path/link runtime state.

This remains a micro-proof rather than the final production nav-bake policy. Cached/prebaked/background navigation may replace these tiny synchronous runtime bakes later without changing the explicit door-link traversal contract.


## Exposure/light-gem fixture

Phase 3.8 owns the first concrete gameplay-exposure proof:

- **Exposure Lab** launches through the real Application → WorldSession → Player path and exposes one world-owned gameplay-exposure owner plus a development-only top-left light-gem/debug readout;
- gameplay-light sources are actual shadow-casting `OmniLight3D` nodes. Their rendered transform/range is shared with the gameplay query, while an explicit provisional `gameplay_strength` remains separate from presentation energy so decorative brightness does not silently become stealth truth;
- the owner derives three vertical samples from the real player's `CapsuleShape3D` (lower body, torso, upper body), rather than using a fake point target;
- each source ray-tests those samples against world collision for occlusion, uses a simple provisional distance falloff from the light's real `omni_range`, averages visible body-sample contribution for that light, adds contributions from multiple lights, then clamps the final exposure to 0–1;
- the fixture has labeled **DARK**, **LIGHT EDGE**, **PARTIAL**, **FULL**, **TWO LIGHTS**, and **OCCLUDED** positions. The occluded position is behind real StaticBody3D geometry rather than a test-only boolean;
- headless acceptance is relational rather than a frozen tuning table: dark is near zero; edge is positive but lower than partial; partial is meaningfully below full; opaque occlusion removes the representative key-light samples; both sources contribute at the overlap point; the live HUD is driven by the same owner summary;
- manual acceptance confirmed that the current DARK / LIGHT EDGE / PARTIAL / FULL / OCCLUDED / TWO LIGHTS relationship is intuitive enough for the Phase 3 proof. Exact falloff, sampling positions/weights, strength tuning, and final light-gem art remain replaceable production tuning rather than being frozen by that acceptance;
- this phase does **not** add observer FOV, distance-to-observer, alertness, motion visibility, guard perception, light switching/extinguishing logic, or final production HUD architecture.

The Visibility suite is the automated owner of this fixture. Keep diagnostics useful enough to identify per-light contribution, body-sample visibility, total/raw exposure, and whether the failure is falloff, occlusion, overlap, or HUD propagation rather than only reporting one final scalar.

## Audible world-space speech fixture

Phase 3.9 reuses the existing semantic acoustic authority rather than adding subtitle-only hearing rules:

- **Speech Lab** launches through the real Application → WorldSession → Player path with one ordinary `VarkAcousticPropagation` owner and a normal `VarkAcousticListener` attached to the player;
- each utterance is authored through a tiny `VarkSpeechLine` Resource carrying stable `line_id`, text, semantic `sound_kind`, gameplay sound strength, and presentation lifetime. The placeholder speaker does not hardcode production dialogue or know guard AI state;
- beginning an utterance hides any previous text and queues exactly one existing `gameplay.sound` source fact through `WorldSession`. That one semantic event remains the hearing/AI consequence; presentation movement must never enqueue repeated gameplay sounds;
- text cannot appear until that queued sound has crossed the same stable semantic consequence boundary used by ordinary hearing. During the remainder of the active utterance, the speaker continuously calls the existing acoustic propagation with its current source position and the player's current listener position;
- the text is a billboarded world-space `Label3D` above the source with `no_depth_test` enabled. Therefore visual cover alone does not erase currently audible words; hearing truth remains owned by the acoustic graph rather than by a direct subtitle LOS ray;
- opacity is a continuous live function of propagated strength above hearing threshold: exactly zero at/below threshold, using a smoothstep fade whose slope eases to zero at the inaudible boundary. The same alpha must drive both `Label3D.modulate.a` and the independent `Label3D.outline_modulate.a`; movement or acoustic-route changes during one utterance must immediately fade/hide/reveal the whole glyph without another semantic event, and utterance expiry always clears stale words;
- the fixture uses two structural acoustic spaces separated by a real `StaticBody3D` wall and one full-transmission `VarkAcousticPortal` at the open edge. **OPENING / LOUDER** and **BEHIND COVER / MUFFLED** have approximately equal direct source distance, but the exposed ray is clear while the cover ray hits the wall; both acoustic paths route through `portal.cover_edge`, and moving behind the wall must lower propagated strength because the listener is farther along that authored route rather than because speech performs a private raycast; **NEAR / MARGINAL / INAUDIBLE** extend the same topology proof;
- automated timing proves text remains hidden before the controlled semantic consequence pass. A single active utterance starts near the cover-edge portal, then moves progressively behind the wall: live propagated strength and fill/outline alpha must decrease monotonically while semantic queued/heard counts remain unchanged. Continuing farther must preserve the whole-glyph fade, five closely spaced near-threshold samples must each decrease by less than 0.04 alpha and approach effectively zero before the inaudible boundary, the same utterance reaches hidden at the inaudible marker, and it becomes visible again after returning to audible cover range; a short line proves lifetime expiry clears the text;
- this micro-proof does **not** introduce conversation trees, bark selection AI, writer tooling, localization, voice playback authority, subtitle UI ownership, awareness changes, or the Phase 12 dialogue system.

The Speech suite owns this fixture and should keep diagnostics for semantic queued/heard counts, active/remaining utterance lifetime, presentation update count, current propagated strength/threshold ratio, label visibility/alpha, and last event/live acoustic results so failures distinguish data, event timing, live acoustics, and presentation.

## Simple objective/exit fixture

Phase 3.10 proves only the semantic beginning/end seam needed by the future integrated slice:

- **Objective Lab** launches through the normal Application → WorldSession → Player path;
- one `VarkSimpleObjectiveState` owns `objective.route`, `exit.route`, objective completion, exit attempt/block counts, and route completion;
- public `query_objective(id)` and `query_exit(id)` return detached semantic snapshots and fail closed for unknown IDs; consumers do not read the owner's private fields;
- `VarkSemanticRouteTrigger` areas are intentionally dumb. The objective trigger queues `objective.complete_requested { objective_id }` once; the exit queues `mission.exit_requested { exit_id }` per entry. Trigger configuration contains semantic IDs only and has no objective/door/NPC reference;
- the owner handles both requests in the ordinary controlled semantic consequence pass. An early exit attempt increments attempt/block state but cannot complete the mission;
- after the objective event drains, the objective query reports `complete` and the exit query reports `unlocked`;
- a later exit request changes route truth once and queues exactly one detached `mission.completed { objective_id, exit_id }` event during the same deterministic event cascade;
- later exit requests remain idempotent: attempt count may increase, but `mission.completed` and mission-completion count must remain one;
- the lab status `Label3D` is development presentation only. This proof does not establish production objective HUD, mission-rule authoring, save/restore, campaign facts, scoring, or mission transitions;
- the existing authored `vark_exit` entity remains an addressable spatial/content endpoint only until a production mission proves the binding from authored exit content to this semantic contract.

The Objectives suite owns this fixture. Failures should distinguish trigger emission, stable-boundary event handling, objective query state, exit gating, completion-event duplication, and presentation status.

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

Phase 3.11 uses the existing Guard/Nav actor instead of a synthetic corpse/knockout entity:

- authored `vark_guard` now exposes `persistent_id` and optional `content_id`; the Guard/Nav source carries `vark_guard_nav_guard` / `guard.nav_probe`, and the current-world registry must resolve both IDs to the same `VarkGuard` root;
- the actor root owns semantic `conscious`, `unconscious`, and `dead` life states. Ordinary requests queue `actor.life_state_requested` and accepted changes append `actor.life_state_changed` through the existing deterministic semantic event drain;
- runtime transitions are monotonic for this proof: conscious → unconscious/dead and unconscious → dead. Wake/resurrection is not gameplay behavior yet;
- life state gates activity, not identity. Conscious retains the existing configured patrol/navigation behavior; unconscious/dead stop locomotion/door retries and report awareness ineligible/navigation inactive while keeping the same `CharacterBody3D`, collision leaf, `NavigationAgent3D`, configured patrol ownership, persistent/content/guard IDs, and registry reference;
- an external transform change while non-conscious is allowed to represent future body-moving ownership without introducing a corpse identity. This fixture does not claim ragdoll, dragging, carry, or final body physics;
- `capture_semantic_state()` returns detached actor identity/life-state value data. `apply_semantic_state()` is restore-only compatibility: it rejects PLAYING sessions, wrong actor identity, and invalid life state; while non-playing it quietly reconstructs valid saved life state on the same actor and emits no ordinary life-state event;
- the Actors suite launches the real Guard/Nav mission, proves the conscious actor actually moves, checks queued-vs-drained timing for unconscious/dead transitions, verifies the same registry node and exact `NavigationAgent3D` survive, proves locomotion stops and body-compatible repositioning preserves identity, verifies wake/resurrection requests are rejected, mutates a captured dictionary to prove runtime truth is detached, and exercises quiet non-playing restore application;
- no vitality/damage model, attack intent, knockout interaction, body dragging, ragdoll, awareness implementation, save coordinator, or final combat behavior is introduced here. Those remain later roadmap work.

This fixture protects the actor/persistence/navigation/event seam that Phase 4 save/hostile proofs and later combat must reuse.

## Phase 3 integrated-slice fixture

Phase 3.12 is the collision test for the accepted micro-proofs. **Integrated Slice** is a development graybox, not a production mission or hardened stealth API:

- it launches through the normal Application → WorldSession → Player path and contains the real `VarkGuard`, `VarkOrdinaryDoor`, two `VarkOrdinaryProp` crates, `VarkAcousticPropagation`, `VarkGameplayExposure`, `VarkWorldSpeechSpeaker`, and `VarkSimpleObjectiveState`;
- the slice must not contain a decorative shadow-casting light that exposure ignores. Its gameplay-world visible rendered `Light3D` set is intentionally one node: `NorthGameplayLight`, a shadow-casting `VarkGameplayLight` sampled by the exposure owner. Low environment ambient is permitted only as a non-shadowing readability floor;
- scene static collision is baked into one runtime `NavigationMesh`; the guard patrols A↔B across the room divider and must use the same ordinary door rather than a test-only passage;
- south/north acoustic spaces connect through one portal bound to that door's existing acoustic-openness seam. The player speech listener and guard hearing listener are ordinary `VarkAcousticListener` consumers of the same graph;
- two slice-local `Area3D` footstep surfaces label south stone (0.52 source strength) and north carpet (0.20). A tiny distance-step emitter queues only semantic `gameplay.sound` facts. It reads the player's public movement semantic stance and applies a provisional 0.45 source-strength scale only when fully crouched, preserving the surface sound kind while making crouch materially quieter. It establishes neither presentation audio nor a production material/surface database;
- the slice-local guard-reaction adapter listens only to the guard's actual heard `footstep.*` / `prop.impact` evidence. Its first heard player noise may turn the guard and invoke the existing world-space speech speaker once. It does not own persistent awareness/search state;
- primitive slice vision uses the existing world-owned exposure scalar plus guard facing/range and a physical LOS ray to the player's **live head position** (live-capsule fallback), never a fixed standing-height point. If current LOS is lost, the slice-only `PLAYER SEEN` diagnostic clears. `Geometry/CrouchCover` is the deterministic stance proof: standing target clears its top, while the real crouch transition lowers the target enough for the same cover to block LOS while exposure remains above threshold;
- exposure itself continues sampling the live capsule's lower/torso/upper points, so stance can change occlusion geometry without a universal crouch exposure multiplier;
- the objective/exit nodes are the accepted 3.10 semantic owner/triggers. No parallel route-completion truth exists;
- the automated Phase 3 Integration suite must verify the complete component set/stable actor registry identity, exactly one gameplay-world rendered shadow light, nonempty nav plus real guard door use, door-dependent acoustic strength, standing loud-stone footstep → guard hearing → one acoustically gated typed response, same-position crouched stone step → reduced semantic strength/muted hearing, real player Junk carry→throw coexistence, standing-visible versus crouched-low-cover blocked LOS while still gameplay-lit, and early-exit → objective → final-exit semantics in the same loaded world. After real patrol/door behavior is proven, the deterministic low-cover comparison pauses only guard locomotion so the multi-frame player crouch transition cannot move the observation geometry; failures print measured exposure, LOS blocker/state, target positions, and actor positions;
- the focused Windows manual pass owns coherence/feel only: visual shadow lighting must agree with the exposure source set; crouch must materially help through quieter steps and lower physical sightline/cover use; normal movement must remain intact; guard/door must not stall/clip; room/door hearing, world-space speech, Junk interaction, light-gem relation, and objective/exit completion must remain coherent. It does not approve final stealth thresholds, search behavior, sound presentation, combat, or mission art.

Keep this fixture narrow. A failure here should be fixed at the existing ownership seam when possible rather than by adding slice-specific replacement truths.

## Crude hostile compatibility fixture

Before stealth architecture hardens, exercise:

```text
attack intent
→ semantic hostile effect on guard
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

A focused agent handoff must collectively cover every unresolved `Manual:` acceptance criterion for the roadmap item. “Focused” means omit irrelevant global checks; it does not mean skip required acceptance cases. A generic user response such as `works` accepts only the cases that were actually included in the handoff.

When `Manual:` requires a specific kind of validator, name that role rather than treating every manual criterion as interchangeable. User/playtester, Windows operator, mapper, writer, cold author, and external developer are different acceptance roles. In particular, the implementing agent cannot self-certify the independent-human purpose of 8.7, 11.6, or 15.2; it prepares the workflow and the reported external result closes the criterion.

## Phase 2.3 mapper persistent-identity feasibility check — accepted

Validator: **Windows mapper/user with TrenchBroom 2026.2 (`Build v2026.2 Release Win64`)**.

The accepted proof exposed and corrected two real configuration failures before identity became a runtime dependency: the installed Vark FGD originally did not declare `persistent_id` on `func_detail`, and the refreshed GameConfig originally inherited a non-existent `textures/palette.lmp` that blanked the material browser. The current project-owned Vark FGD declares the property, and `VarkTrenchBroom.tres` disables the unused palette while retaining `textures` PNG discovery.

For a fresh machine or future regression rerun, close TrenchBroom and refresh the installed Vark configuration from project root:

```powershell
godot --headless --path . --script res://tools/authoring/persistent_identity_probe.gd -- sync-config
```

`sync-config` uses the machine-specific FuncGodot **TrenchBroom Game Config Folder**, exports `GameConfig.cfg` plus project-owned `Vark.fgd`, verifies the FGD contains `persistent_id` and the optional `content_id` schema, and validates the material root/PNG/empty-palette contract. If no folder is configured, set it in `res://addons/func_godot/func_godot_local_config.tres`, use its **Export func_godot settings** control, then rerun `sync-config`.

With TrenchBroom still closed, replace only the disposable ignored proof map with a fresh copy of the real Playground source:

```powershell
godot --headless --path . --script res://tools/authoring/persistent_identity_probe.gd -- reset
```

`reset` intentionally replaces only `tests/authoring/workspace/mission.map`; it never touches the tracked Playground source. `prepare` remains available for a first non-destructive workspace creation and still refuses to overwrite mapper work.

Then reopen TrenchBroom with the refreshed **Vark** game configuration and use normal mapper operations only:

1. Open `tests/authoring/workspace/mission.map` and confirm normal zebra materials are visible.
2. Create a small brush and convert it to an ordinary `func_detail` entity; save the map.
3. Run:

```powershell
godot --headless --path . --script res://tools/authoring/persistent_identity_probe.gd -- repair
godot --headless --path . --script res://tools/authoring/persistent_identity_probe.gd -- inspect
```

4. **Whenever `repair` reports that it wrote source, reload/reopen the map in TrenchBroom before any further edit or save.** This is mandatory: an already-open pre-repair document can otherwise save stale in-memory entity properties over the external repair.
5. Confirm the generated `persistent_id` is visible after reload. Do not type or edit the ID manually.
6. Move that entity, save, run `repair` then `inspect`; its ID must remain unchanged and repair should be a no-op.
7. Add another unrelated `func_detail`, save, repair/inspect, then reload because repair assigned the new entity's ID. The existing entity must keep its ID.
8. Duplicate the original entity using TrenchBroom, move the duplicate, save, then repair/inspect; the original must retain its ID and the duplicate must receive a different ID. Reload after this repair write before more edits.
9. Delete the unrelated entity and create a replacement `func_detail`, save, repair/inspect; the replacement must receive a new ID rather than inheriting the deleted entity's identity.

The completed Windows run satisfied these cases. Source-order reordering and stale expected-hash write races remain deterministic file/tool concerns covered automatically rather than mapper UI operations.

## Phase 2.7 TrenchBroom point-entity foundation check — accepted

Validator: **Windows mapper/user with TrenchBroom 2026.2 (`Build v2026.2 Release Win64`)**.

The accepted 2.7 run confirmed the three point classes and the real authored player-start path. The first pass exposed an authoring-schema defect: with identity fields supplied only by FGD base inheritance, TrenchBroom showed them as empty defaults. After the point definitions were flattened, a second diagnostic found a stale already-open document still exposing only `classname` and `origin`; a fresh copy of the same `.map` bytes showed all five properties, and closing that stale document without saving then explicitly reopening `missions/playground/mission.map` restored the correct in-memory property set with no source diff.

For a fresh machine or future regression rerun:

1. Close TrenchBroom and refresh the installed Vark config from project root:

```powershell
godot --headless --path . --script res://tools/authoring/persistent_identity_probe.gd -- sync-config
```

2. Reopen TrenchBroom using the **Vark** game configuration and explicitly open `missions/playground/mission.map` from disk rather than relying on an already-open stale document.
3. Confirm the point classes `vark_player_start`, `vark_marker`, and `vark_exit` are available in the entity browser.
4. Select each tracked point individually, turn **Show default properties OFF**, and confirm `angle`, `classname`, `content_id`, `origin`, and `persistent_id` are visible. Do not hand-edit or replace any `persistent_id`.
5. Confirm the semantic IDs are `default`, `marker.playground_reference`, and `exit.default` respectively; each `persistent_id` should remain its existing non-empty `vark_...` value.
6. Run Vark and use **Development Launch → Playground**.
7. Confirm the real Player starts from the authored `vark_player_start` location/orientation and ordinary movement/mouse-look behavior is normal.

The completed Windows run satisfied these cases and accepted the mapper-visible vocabulary, actual identity/content properties, authored selector/start result, and ordinary movement/look behavior.

## Phase 2.8 TrenchBroom reimport-stability check — accepted

Validator: **Windows mapper/user with TrenchBroom 2026.2 (`Build v2026.2 Release Win64`)**.

This check proves an actual mapper edit/save/rebuild/run cycle rather than another schema-only inspection. Because the 2.7 diagnosis demonstrated stale document state, close any already-open Playground document first and explicitly open the authoritative path from disk; do not rely on an old tab or Recent-document state.

1. Pull the latest `test` branch.
2. Close TrenchBroom and refresh the installed Vark config:

```powershell
godot --headless --path . --script res://tools/authoring/persistent_identity_probe.gd -- sync-config
```

3. Reopen TrenchBroom with the **Vark** game configuration and explicitly **File → Open** `missions/playground/mission.map`.
4. Select only `vark_player_start`, turn **Show default properties OFF**, and record its existing non-empty `persistent_id` plus `content_id = default`.
5. Move `vark_player_start` exactly **+32 mapper units on X**. Do not edit either identity field. Save the map.
6. From the project root run:

```powershell
godot --headless --path . --script res://tools/authoring/playground_reimport_probe.gd
```

Expected: verification passes, reports no persistent-ID repair, prints the same tracked IDs, and reports that the real Playground wrapper reached `PLAYING`.
7. Run Vark → **Development Launch → Playground**. Confirm the real Player starts at the moved authored point and ordinary movement/mouse-look behavior remains normal.
8. In TrenchBroom move the same player start exactly back to its original authored transform and save.
9. Rerun `playground_reimport_probe.gd` and Development Launch → Playground; the same IDs must remain and the Player must be back at the original start.
10. Run:

```powershell
git diff -- missions/playground/mission.map
```

Expected: no output. If a diff remains, report it rather than hand-normalizing or editing identity values.

The completed Windows run satisfied these cases. The first round trip exposed only TrenchBroom normalization of repository-added descriptive comments; entity data, identities, transforms, and brush geometry were unchanged. The tracked Playground map was then committed in TrenchBroom's save-normalized form and the stale comment-dependent authoring assertion was removed. Exact-head CI returned green, and the accepted rerun preserved the IDs and moved/restored start behavior while ending with an empty `git diff -- missions/playground/mission.map`; the mapper never hand-edited `persistent_id`.

---

# Player manual regression checklist

## Project load / player scene

- [ ] Project reopens without new missing-script, parser, global-class, UID, or player-code errors.
- [ ] `Player.tscn` loads/spawns normally after application start.
- [ ] No unexpected resource/UID churn appears after normal project rescan.

## Application/menu shell

- [ ] F5 opens the application main menu before constructing a development world.
- [ ] Settings exposes only working controls; current Look Sensitivity visibly changes mouse-look response after gameplay start.
- [ ] New Game enters the current default development world normally.
- [ ] Development Launch opens the curated target selector and launching the selected target enters gameplay through the same application-owned world path.
- [ ] Development Launch → Playground loads the package-local zebra floor/reference step and real Player normally.
- [ ] Returning to the application no-world state shows the menu coherently rather than leaving an input/world orphan.
- [ ] Quit from the main menu closes the application normally on the supported Windows x64 target.

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

## Interaction (Phase 3.1)

- [ ] F5 → Development Launch includes **Interaction Lab** and launches it through normal gameplay ownership.
- [ ] There is no permanent central crosshair.
- [ ] Center the Door Contract Probe while close and unobstructed: it visibly highlights; look away or back out of range and the highlight clears.
- [ ] The Prop Contract Probe does not highlight through the divider; move around the divider until the center view has a clear line and it highlights.
- [ ] Press **E** on the highlighted Door Contract Probe: its `uses` count increments once; holding E does not repeatedly increment it; release and press again increments once more.
- [ ] Press **E** once on the Prop Contract Probe: it changes to `INACTIVE` and immediately loses interaction highlight, demonstrating current-state eligibility.
- [ ] Walking, sprinting, jumping, crouching, and mouse look remain accepted while using the interaction lab.

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
- [ ] Dropped/thrown props remain top-up, move physically, then stop directly in stable rest with no visible orientation-correction phase.
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

GitHub Actions exists for the authoritative regression barrier.

Under current repository workflow, `test` is the direct-write integration branch. CI on `test` is therefore **post-push integration validation**, not a fictional pre-push gate.

The current CI barrier:

- runs on the pinned `ubuntu-24.04` GitHub-hosted runner;
- installs Godot `4.7.2` without .NET or export templates;
- performs `godot --headless --path . --import` so a clean checkout has generated Godot project metadata/class registration before tests load; this clean import is also the authority that ignored/removed `.map.import` sidecars are generated metadata rather than source;
- runs `godot --headless --path . --script res://tests/run_all_tests.gd`, the same authoritative full-regression command used locally;
- executes the independent authoring, application menu/development-launch/mission-package/definition/ownership/lifecycle/input/pause-time/save-snapshot, props, acoustics, and movement suites through that entry point;
- runs on pushes to `test` and on pull requests if they are used;
- fails when the all-tests process returns nonzero.

The GitHub Actions job is named `Regression suite`. Focused suite commands remain available for diagnosis, but CI uses the single all-tests entry point rather than duplicating suite commands in workflow YAML.

A newly uploaded implementation commit is not accepted merely because it reached `test`. Keep roadmap work `[~]` until relevant CI/local automated validation is green and required manual/user validation is accepted.

When job logs are available, validation includes checking for newly introduced parser/script errors, resource/UID/import failures, invalid references, or other meaningful project regressions even if the process exits successfully. The deliberate missing/duplicate persistent-identity, duplicate-content-ID, invalid mission-content/reference, and zero/multiple-player fixtures emit expected error diagnostics while asserting that the session fails closed; those messages are test evidence, not unexpected project-load failures. Known harmless external/deprecation noise should likewise be distinguished rather than treated as a project failure.

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
