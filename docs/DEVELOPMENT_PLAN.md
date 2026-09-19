# Vark Development Plan

This document defines the ordered systems-development roadmap for Vark.

The final goal is:

> **Build Vark as a complete immersive-sim game through representative playable missions. Whenever a gameplay or authoring pattern has been proven by real mission use, extract and stabilize only the reusable platform future missions actually need.**

The finished production target remains:

> **A mapper, mission scripter, writer, and artist can create production Vark missions without modifying Vark's core gameplay systems.**

Vark is not built as a speculative general immersive-sim SDK first.

The roadmap follows three rules:

> **Prove ownership early; generalize behavior late.**

> **Keep durable gameplay truth semantic and world-owned; keep engine/runtime machinery transient.**

> **Introduce only the smallest cross-cutting contract that several immediate real systems need.**

`GAME_VISION.md` is authoritative for player-facing behavior and scope. `FOUNDATION_CONTRACT.md` is authoritative for lifecycle, gameplay-input timing, controlled semantic mutation, events, gameplay time, identity, persistence, save transactions, and other cross-cutting invariants. This roadmap schedules and proves those contracts rather than restating competing versions of them.

---

# Status notation

- `[ ]` — not implemented
- `[~]` — implemented/substantial but still awaiting required validation/follow-up
- `[x]` — required automated checks passed and the user accepted relevant manual/playtest behavior

Design state:

- **LOCKED** — accepted behavior/product rule; internal implementation may change
- **TARGET** — intended design requiring prototype/playtest proof
- **OPEN** — known problem whose correct solution should be discovered by a focused spike

Before implementing any nontrivial roadmap item, make completion mechanically checkable with concise acceptance information:

```text
Done when:
Automated:
Manual:
```

These may live directly in the item or be inherited unambiguously from its phase gate, `TESTING.md`, or `FOUNDATION_CONTRACT.md`. Confirm the three acceptance lines before implementation begins or as part of the implementation patch rather than deciding completion after the code already exists. If a check is not warranted, say so explicitly. `[x]` is allowed only after required automated checks pass and required user validation is accepted.

When `Manual:` requires a specific kind of validator, name that role rather than treating every manual criterion as interchangeable. User/playtester, Windows operator, mapper, writer, cold author, and external developer are different acceptance roles. In particular, the implementing agent cannot self-certify the independent-human purpose of 8.7, 11.6, or 15.2; it prepares the workflow and the reported external result closes the criterion.

---

# Current implementation baseline

The project currently contains:

- accepted first-person movement/look behavior
- walking
- sprinting
- crouching
- jumping
- air control
- collision/support handling
- steps
- ledge catching/hanging/traversal
- supported ledge corners
- mantling
- deterministic movement regression tests
- Godot 4.7 project configuration
- Jolt physics
- FuncGodot
- TrenchBroom `.map` import
- existing graybox/test maps
- an application root with explicit current-world/session ownership
- an application-owned gameplay/look input boundary with tick-framed locomotion intent and event-cadence view pose
- application-owned exclusive control modes with coherent world pause and world-session gameplay time
- a minimal application main-menu shell with New Game, curated Development Launch, Quit, and one working look-sensitivity setting
- an initial `missions/playground/` package with authoritative TrenchBroom spatial source and a launchable application-owned world wrapper
- a minimal typed `MissionDefinition` for Playground carrying authored mission ID, world/map references, player-start selection, and content revision
- an accepted authored persistent-ID source/writeback workflow plus project-owned runtime identity wiring, optional author-facing semantic content IDs, fail-closed identity validation, a current-session-owned persistent/content-ID registry, and the first Vark point-entity foundation for player start, semantic marker, and exit
- a minimal player-owned interaction selector with application-owned primary-interaction intent, center-view range/occlusion/state eligibility, central ordinary-interaction availability, and Thief-style fullbright/no-received-shadow target-selection feedback that preserves ordinary cast shadows
- a minimal `WorldSession`-owned semantic gameplay-event route with FIFO consequence draining, nested append semantics, lifecycle/session rejection, detached payloads, cascade diagnostics, and an explicit stable gameplay-boundary serial
- a minimal semantic `gameplay.sound` source fact separated from presentation audio
- a first reusable ordinary-door micro-proof with physical hinge collision/vision behavior, semantic door events/state capture, and narrow acoustic/navigation seams
- an accepted Phase 3.5 ordinary-prop implementation with single-slot carried Junk HUD presentation, F throw / R gentle release, real always-upright dynamic rigid-body translation while moving, frozen settled support/stack behavior, hard-edged external-model shading, dynamic-prop mantle support, and semantic capture/reconcile seams
- a Phase 3.6 authored acoustic-space/portal propagation prototype consuming the existing semantic `gameplay.sound` fact, using the ordinary-door acoustic-openness seam, and exposing deterministic listener evidence without coupling stealth truth to presentation audio
- post-push GitHub Actions validation for the authoritative regression barrier

The accepted player-controller behavior and feel are **LOCKED**.

Its implementation is not frozen. Input sampling, command routing, component ownership, pause/cutscene gating, mouse ownership, scene structure, and other internals may be refactored as needed so long as accepted baseline response/feel remains unchanged.

Later gameplay may deliberately apply explicit contextual modifiers such as carrying a body. Such modifiers must be owned by the gameplay feature that requests them and must not silently rewrite the accepted unmodified locomotion contract.

The project does not yet have the complete production gameplay platform: persistence-backed Continue/campaign flow, generalized production mission loading beyond the minimal Playground definition, final Vark entity library, saveable world state, production interaction/doors, gameplay lighting/exposure, hardened acoustics, NPC/nav/stealth, mission logic, bodies/combat, inventory, campaign state, dialogue presentation, cutscenes, and production authoring/validation.

---

# Development method

## 1. Build vertically

Every major phase must leave behind a playable integrated result.

Do not build many disconnected mechanics and integrate them near the end. The first representative stealth mission appears early, initially tiny and ugly.

## 2. Micro-proof → integrated proof → contract → generalize

For uncertain systems:

1. isolate the smallest fixture that can answer the system's hardest question;
2. prove the dangerous assumption in that fixture;
3. integrate the result into the actual playable path;
4. test/playtest the cross-system behavior;
5. define the accepted behavior/API only after evidence exists;
6. generalize only the patterns that proved reusable.

The isolated proof exists to make failures diagnosable. It does not replace the integrated proof.

## 3. Extract a shared abstraction only for a current shared need

Before introducing a framework, ask:

> **Do at least two real near-term gameplay systems need the same contract now?**

If not, keep the behavior local. If yes, extract the smallest semantic contract that removes real coupling.

Do not create universal entity, action, effect, interaction, AI, time, scheduler, or scripting frameworks around hypothetical future content.

## 4. Authoring develops with gameplay

If a feature is ordinary mission content, its normal authoring path must be developed with it.

- TrenchBroom: structural brush geometry plus placement/configuration of ordinary spatial entities
- external Godot-supported 3D model assets: reusable visual geometry for ordinary objects such as doors/openable windows, furniture, containers, movable props, mechanisms, and loot presentation
- typed Godot Resources/config: reusable non-spatial authored configuration
- GDScript: genuinely procedural or unusual mission behavior through supported APIs
- writer-facing text data: dialogue/narrative content without gameplay-code editing

Structural architecture such as rooms, walls, floors, ceilings, stairs, and major built forms remains natural TrenchBroom brush geometry. Reusable object visuals should use external model assets when that is the natural representation rather than forcing furniture/doors/props into brush geometry.

The Vark gameplay archetype/entity owns semantic behavior, persistent/content identity, interaction/state, and the stable authoring contract. The selected external model is replaceable presentation/configuration and must not become the object's semantic identity or make gameplay depend on fragile mesh/node names. Openable windows are ordinary door/opening variants and reuse the same door behavior/integration contracts; do not create a separate window gameplay subsystem.

Shared authored/configuration Resources are treated as configuration, not mission-local mutable runtime state. Mutable gameplay state belongs to the current world/session or concrete runtime owner.

## 5. Do not create a second programming language

The common rule layer remains:

> event → conditions → actions

Loops, arbitrary locals, unrestricted expression evaluation, nested general control flow, and arbitrary object manipulation belong in GDScript rather than expanding the rule system.

Long-running saveable behavior is explicit semantic state, not a suspended coroutine/timer stack.

## 6. Stable APIs follow proven use

Mission scripts must not depend on private scene-tree paths, guard internals, movement internals, arbitrary internal signals, or undocumented singleton state.

The Phase 7 mission-script surface is **provisional/supportable**, not a production compatibility promise.

Phase 11 may stabilize the **world/gameplay mission API** only after Phase 8–10 have exercised it. Campaign/narrative/application-flow extension surfaces remain provisional until Phases 12–13 exercise them. Do not preserve a bad prototype API merely for compatibility with prototypes.

## 7. Saveability is designed with stateful features; the save coordinator comes later

Every stateful feature added must define, semantically:

```text
capture meaningful state
apply meaningful state
reconcile derived/runtime references after restore
```

Derived/transient data such as nav paths, physics handles, cached queries, runtime object references, engine timers, and coroutine stacks are normally reconstructed rather than serialized.

## 8. Every semantic fact has one authoritative owner

Do not mirror ordinary system state into generic mission facts simply because the rule system can store values.

Examples:

- doors own door state;
- actors own life/awareness/vitality state as those systems become real;
- possession/inventory owns possession;
- objectives own objective state;
- `MissionRunState`/statistics owns run counters;
- mission facts own genuinely mission-defined mission-local variables;
- `CampaignState`, once introduced, owns campaign-persistent facts.

Rules query or react to these owners. A separate mission fact is appropriate only when it has distinct mission-defined meaning.

## 9. Debugging is a production feature

As soon as a system can fail invisibly, add the smallest useful diagnostics.

Examples: entity-ID validation, acoustic path/debug, NPC perception state, nav path, mission-rule trace, event-cascade trace, save/restore warnings.

## 10. Performance is checked incrementally

The representative-scale stress mission remains late, but expensive systems get focused stress fixtures shortly after introduction.

Performance measurements must record the supported tool/runtime/reference environment used so results from different machines are not treated as directly comparable by accident.

---

# Cross-cutting implementation rules used by this roadmap

The full contract lives in `FOUNDATION_CONTRACT.md`. The roadmap depends especially on these rules:

- application owns one authoritative mission-world transition at a time;
- world/session owns mutable mission state and world-scoped work;
- pending world-bound requests, especially save capture, remain bound to their source `WorldSession` and never silently retarget to a replacement;
- gameplay intent edges are tick-owned, while accepted mouse-look/UI cadence need not be forced into the gameplay tick;
- the input-owned player view pose may update at accepted event cadence, while world systems sample it during controlled simulation and save captures it synchronously at the stable boundary;
- disabling a gameplay-input domain clears stale edges **and cancels incomplete gestures whose completion depends on future edges**;
- gameplay durations advance from world simulation time, not wall-clock time;
- durable world-semantic mutation commits through the controlled gameplay step/consequence pass;
- engine callbacks outside that pass may update presentation/input-owned view pose or enqueue future semantic work, not race world gameplay state across the stable boundary;
- mission-script mutation commands use the same boundary rather than directly mutating private gameplay Nodes from arbitrary callbacks;
- semantic events drain FIFO for the emitted sequence, nested emissions append, and event handlers do not suspend inside the current drain;
- resolved random choices that have become gameplay truth restore as the same resolved choices rather than being rerolled;
- one stable gameplay boundary exists after the completed semantic consequence pass;
- persistent identity is authored or runtime-created; authored removal is tombstone state, not a third identity kind;
- a persistent actor remains the same identity through conscious/unconscious/dead/body representation;
- restored runtime-created identities remain reserved so later spawned objects cannot reuse them;
- save capture produces detached value-owned data at the stable boundary;
- restore establishes what exists before applying what state it has and runs reconciliation while ordinary consequences remain suppressed;
- long-running saveable behavior stores explicit semantic progress/state, never an engine timer/coroutine as its sole truth;
- save-slot commits cannot allow an older request to overwrite a newer request;
- `save_format_version` covers the global saved-state schema **and semantic interpretation**, not merely file encoding;
- mission-content revision changes when old saved semantic/spatial state can no longer be reconstructed safely;
- runtime-persistent type/provenance IDs, once introduced, are semantic/stable rather than scene/class-name accidents;
- active runtime-created transients need explicit restore/reconstruct/normalize policy when their disappearance would make a valid save semantically wrong.

These are boundaries, not invitations to build general managers/frameworks.

---

# Identity and persistence model

There are **two persistent identity kinds**:

- authored persistent identity;
- runtime-created persistent identity.

There are **three persistence cases**:

- authored instance present;
- authored instance permanently removed;
- runtime-created persistent instance present.

Mission scripting may additionally use optional author-facing `content_id` values such as `door.vault` or `guard.library`. Persistence identity and semantic author-facing identity are different concerns.

Authored identity must survive ordinary move/reorder/reimport operations and duplication must create a distinct identity. Repair/writeback must persist to the authoritative authored source and be idempotent.

Runtime lookup of current authored identities is world-session-scoped. The current registry resolves validated `persistent_id` values and optional non-empty `content_id` values only for the active world and is discarded with that session.

Runtime persistent identity/provenance is introduced only when the first real runtime-created object must survive save/load.

---

# Save/restore lifecycle target

Support two boot intentions:

```text
FRESH_START
RESTORE_SAVE
```

## Capture

```text
save requested in WorldSession A
→ finish A's current controlled gameplay/event pass
→ A reaches stable gameplay boundary
→ synchronously copy save-owning semantic state + current player view pose into detached value-owned snapshot data
→ gameplay may continue
→ encode/write only from that snapshot
```

A pending save request is cancelled if its source session stops before capture; it never retargets to the replacement session. Once the detached snapshot exists, its file write may finish after the source world has been torn down.

The snapshot contains no live Nodes/RIDs/callbacks/shared mutable gameplay containers or shared mutable runtime Resources. Mutating live gameplay after capture must not mutate the snapshot.

Writes to the same save slot are serialized or generation-ordered so an older request cannot commit after a newer request. Quickload reads the latest fully committed save, never a temporary/in-progress write.

## Restore

The restore contract is semantic/transactional rather than tied to a mandatory dual-world architecture:

```text
stop/freeze current gameplay
→ validate save as far as possible
→ construct the non-playing restore world using the simplest safe topology
→ establish authored removals and runtime-created existence
→ register/reserve restored runtime identities
→ apply semantic state
→ reconcile / after_restore while consequences remain suppressed
→ validate
→ make restored world authoritative
→ enable gameplay time/AI/events/rules/perception
→ PLAYING
```

The implementation may keep a frozen old world while building an isolated candidate if doing so is simple. It may instead tear the old world down after prevalidation and restore the replacement as the sole mission world. Do not build a general multi-world framework merely to preserve the old world after deep restore failure.

Failure must leave one coherent application-owned recovery state and no leaked world-owned work.

---

# Production toolchain

## Supported Phase 0 baseline

The current supported development/test baseline is:

- supported local development/export target: **Windows x64 desktop**;
- Godot `4.7.2`;
- Jolt Physics as the configured 3D physics backend;
- FuncGodot `2025.12`;
- TrenchBroom `2026.2` (`Build v2026.2 Release Win64`) for the currently authored `.map` sources;
- Forward+ as the supported desktop rendering method, with D3D12 configured on Windows;
- Mobile renderer for Godot's mobile rendering-method slot;
- GitHub Actions on the pinned `ubuntu-24.04` hosted runner for clean-checkout headless movement validation.

Windows x64 desktop is the official development/export target. The Ubuntu GitHub Actions environment is an automated headless validation environment only; it does not redefine the supported player-facing/export platform.

## TrenchBroom

Primary spatial authoring tool for brush geometry/materials, routes/rooms, player starts, guards/patrol markers, doors/lights, loot/containers/props, triggers/exits, and ordinary spatial mission objects. TrenchBroom also places/configures model-backed ordinary entities; reusable furniture, doors/openable windows, containers, props, and similar objects do not need to be rebuilt as brushes merely to participate in mission authoring.

The `.map` file is authored source. Generated/imported geometry must not contain irreplaceable manual edits. External 3D model assets are authored visual source alongside the map: the map/entity selects a model or variant while Vark's gameplay archetype remains the semantic owner.

## Godot

Primary tool for core development, reusable gameplay configuration, mission definition/state, testing, validation/debugging, running missions, campaign, and narrative infrastructure.

## GDScript

Used for unusual mission logic, special puzzles/security, special NPC behavior, unique interactables/tools/events.

Mission GDScript uses the currently supported Vark API. Save-relevant long-running script behavior must expose explicit semantic state; a suspended `await`, signal wait, or engine timer is not durable mission truth. Supported mutation commands preserve the controlled gameplay boundary even when requested from an arbitrary GDScript callback.

## Writer-facing text data

Dialogue/subtitles/briefings should use stable text-oriented IDs/data where practical. Exact storage evolves with production needs.

---

# Mission package target

Production missions should converge on a predictable structure similar to:

```text
missions/
    mission_id/
        mission.map
        world.tscn
        mission.tres
        mission.gd
        dialogue/
        sequences/
        ui/
        assets/
```

`mission.tres` is the authored `MissionDefinition` metadata owner for a package. `mission.gd` is optional; a simple mission must not require custom mission behavior GDScript. `world.tscn` is the current Godot runtime wrapper around the package's authored spatial source; the exact amount of technical loader glue may shrink as Phase 2 proves the final import/loading workflow. Reusable external models may live in shared project asset locations while mission-specific models may live under the package `assets/` directory; an asset path/filename is presentation configuration, not persistent identity or saved semantic type.

---

# Phase 0 — Stabilize the development ground

Goal: prevent repository/tool drift from invalidating the behavior protection used by every later refactor.

## 0.1 Existing locomotion/traversal `[x]`

Accepted behavior includes ground movement, sprint, crouch, jump, air movement, support/collision, steps, ledge catch/hang/shimmy/corners, mantle, and mouse look.

**Contract:** accepted baseline behavior/feel is frozen; implementation is not.

## 0.2 Existing movement regression suite `[x]`

Keep the deterministic headless movement suite. Tests protect accepted behavior, not current internal architecture.

## 0.3 Repository cleanup `[x]`

Established policy:

- `maps/autosave/` is generated TrenchBroom recovery material, has been removed from tracked content, and is ignored;
- `.godot/` and other current Godot-generated local state remain ignored;
- top-level `maps/*.map` files are treated as authored/development map source unless deliberately retired;
- FuncGodot/Godot `.map.import` sidecars are generated import metadata rather than authored mission truth; Phase 2.8 removed the legacy tracked top-level sidecars after clean import/rebuild proved they are disposable, and all `*.map.import` files are ignored;
- new `missions/**/mission.map` files are authoritative authored source; package-local TrenchBroom autosaves and generated `.map.import` sidecars are ignored rather than becoming mission truth;
- do not blanket-place text `.map` source in Git LFS merely because a map becomes large; evaluate LFS for future large binary assets where Git text diffs are not useful;
- existing `test.map`, `test2.map`, and `test3.map` remain development/graybox source for now;
- `maps/level export2.map` remains tracked and is conservatively classified as authored/development map source. Its filename and roughly 29.5 MB size are not evidence that it is obsolete. Retain it unless a future explicit content-ownership decision deliberately retires/reclassifies it; do not delete, rename, or LFS-migrate it by inference.

No destructive cleanup is implied by the conservative `level export2.map` classification. Future retirement/reclassification of that source is a separate explicit content decision, not unfinished Phase 0 cleanup.

**Done when:** generated recovery/local state is excluded and all remaining tracked map/import files have explicit source/generated ownership. Satisfied by the policy above.

**Automated:** the clean-checkout import/current authoritative movement CI remained green after the repository cleanup already applied; this classification patch does not delete or transform legacy map content.

**Manual:** none. The ambiguous large map is retained rather than destructively changed.

## 0.4 Tool/runtime contract `[x]`

The supported baseline is now explicitly documented: Windows x64 desktop, Godot 4.7.2, Jolt, FuncGodot 2025.12, TrenchBroom 2026.2 Win64, Forward+ desktop/D3D12 on Windows, and the `ubuntu-24.04` CI validation runner.

The platform decision is closed. The project has been successfully opened/run on the declared Windows x64 development target with this baseline. Future tool/runtime upgrades must update this baseline intentionally rather than silently drifting versions.

Do not create a broad platform matrix yet; Windows x64 desktop is the one supported development/export target.

**Done when:** the documented Windows x64 desktop development/export target and material runtime/tool versions are explicit and the project has been successfully opened/run on that declared target.

**Automated:** CI proves Godot 4.7.2 clean-checkout import plus the authoritative movement barrier on the pinned Ubuntu runner.

**Manual:** passed — the user confirmed Godot 4.7.2 opens the project and `VarkTest` runs normally on Windows x64 desktop after this baseline declaration; repeat this check after material runtime/renderer/toolchain changes.

## 0.5 Continuous integration for the existing barrier `[x]`

The authoritative regression barrier runs in GitHub Actions on every `test` push and on pull requests if used. CI performs a clean-checkout Godot import before executing the all-tests entry point, which includes the existing movement barrier.

Under current repository policy, `test` is the direct-write integration branch. CI is post-push validation, not pre-push protection. Newly uploaded implementation work remains `[~]` until relevant CI/local checks pass and required user validation is accepted.

**Done when:** a clean checkout on the pinned runner imports successfully and the movement suite is executed automatically after a `test` push.

**Automated:** the `Regression suite` GitHub Actions job passes; it includes the authoritative movement barrier.

**Manual:** none for CI infrastructure beyond confirming the successful run/report; user confirmation has been received.

## 0.6 Traversal regression expansion `[x]`

Add deterministic coverage where practical for ledge catch, hang, shimmy, supported corners, mantle, release, and suppression/regrab.

Do not invent synthetic geometry merely to make a test convenient if it does not represent accepted player behavior. Build minimal fixtures around the real ledge state machine and real `Player.tscn`.

The authoritative movement barrier now includes a minimal real-physics ledge fixture using the real `Player.tscn`. It protects normal falling catch → stable hang → crouch release, two-way shimmy plus a supported right-angle corner, a no-input hang mantle onto the valid top, and drop/regrab suppression followed by a later legitimate regrab.

**Done when:** representative accepted ledge catch/hang/release, shimmy/corner, mantle, and suppression/regrab behavior has deterministic protection where practical.

**Automated:** the authoritative movement barrier includes those fixtures and remains green in CI.

**Manual:** passed — the user confirmed the focused ledge/mantle checklist after the traversal-regression patch; the protected cases still feel like the accepted controller.

## 0.7 Behavior-trace protection for controller refactors `[x]`

Before major input/controller plumbing changes, add enough semantic trace coverage to show equivalent locomotion command sequences preserve accepted behavior within intended numeric tolerances.

Representative traces should cover walk/start/stop, crouch, ordinary jump/sprint-jump, a step, and representative traversal transitions once 0.6 fixtures exist. Record/assert observable semantic results such as position/velocity/stance/support/traversal state, not private helper call order.

The authoritative movement barrier now drives fixed command sequences through the real `Player.tscn` and samples a read-only semantic movement snapshot containing position, velocity, support class, stance, and traversal state. The trace covers walk startup/sustain/stop, crouch movement and stance transitions, ordinary jump and sprint-jump takeoff, representative step crossing, and ledge catch/hang/shimmy/release/corner/mantle checkpoints with explicit numeric tolerances. It does not quantize or otherwise change mouse-look timing.

Do not force mouse-look timing into a physics-tick trace if doing so would change accepted look response. Protect look behavior and stable-boundary pose capture separately where appropriate.

**Done when:** the Phase 1 input/controller refactor can compare the same semantic command sequences before/after without depending on the current internal component call graph.

**Automated:** passed — representative traces execute through the authoritative barrier with explicit numeric tolerances and completed successfully in post-push CI.

**Manual:** none beyond the movement/traversal manual acceptance already required when a refactor could affect player feel.

**Phase gate:** repository ownership/tool/runtime versions are controlled, the existing barrier runs automatically in CI after `test` pushes, and accepted player behavior is sufficiently protected for application/input refactors.

---

# Phase 1 — Application ownership, world lifetime, and gameplay-input boundary

Goal: turn the movement project into a controlled application without changing accepted player feel and without baking gameplay side effects into node startup/teardown.

## 1.1 Application root `[x]`

Create stable ownership for game flow, current mission/world session, player, UI, and transitions.

F5 should launch the Vark application rather than an arbitrary development scene.

Top-level load/restart/mission-transition/exit operations have one application owner and cannot race each other as competing subsystem transitions. Future world-bound requests must carry/verify their source session rather than implicitly operating on whatever world happens to be current later.

The project boots through `res://application/Application.tscn`. The application owns a persistent world host and UI root, installs and resolves the current development `VarkTest` world/player when gameplay is started, exposes current session identity for future source-session checks, and provides one exclusive top-level operation guard. Phase 1.5 intentionally changes the initial child state from immediate development-world boot to an application-owned main menu; that later product-flow step does not change the 1.1 ownership contract.

**Done when:** F5 launches the application root; when a world is active that root owns the current world, player, persistent UI root, session identity, and exclusive top-level operation state without changing accepted player behavior.

**Automated:** passed — the application regression suite verifies the configured F5 main scene, persistent UI/application ownership, current world/player/session ownership after development start, current/stale session identity checks, and rejection of overlapping top-level operations, and the authoritative all-tests CI barrier remained green.

**Manual:** passed — the user confirmed the application-owned F5 path and ordinary movement/mouse-look startup/response on Windows x64. Phase 1.5 later inserts the intended main-menu step before gameplay.

## 1.2 World-session lifecycle, stop, replacement, and teardown `[x]`

Create the smallest application-owned lifecycle that permits a mission world to exist before normal gameplay consequences are enabled and guarantees old-world work cannot leak into a replacement.

At minimum prove:

- world builds while gameplay consequences are disabled;
- world becomes `PLAYING` only when the application allows it;
- the application can stop/freeze ordinary world gameplay coherently;
- restart/exit tears the old world down before the replacement becomes authoritative;
- registries/event queues/gameplay timers/deferred work belong to one world session;
- representative stale deferred/timer work from a torn-down session cannot affect a replacement;
- shared authored/config Resources do not become mutable cross-session gameplay state;
- application/autoload state does not accidentally retain mission-local mutable state across replacement.

Phase 1 does **not** need to prove simultaneous old/candidate mission worlds or build a multi-world isolation framework. It must provide the stop/teardown/replacement ownership that Phase 4 can use to discover the simplest safe restore topology.

Use a small session/generation token only if needed to reject stale work.

The application now creates a concrete `WorldSession` for each world instance. A session builds in a disabled `READY` state, enters `PLAYING` only through application permission, can be stopped/resumed coherently, and tears its world down synchronously before restart/mission-transition replacement becomes authoritative. Session IDs are monotonic at the application level and stale IDs stop matching immediately after replacement or exit. The persistent application UI remains outside session lifetime.

World-scoped Nodes/services are owned beneath the `WorldSession`, so their timers/deferred callbacks die with the old session. The regression uses representative real `Timer` and deferred work to prove stop freezes session-owned timer processing and teardown prevents both timer/deferred work from the old session firing into the replacement. Phase 1.2 deliberately did not invent empty registry/event/scheduler frameworks; Phase 2.6 now adds the actual session-owned identity registry once authored IDs exist, while the semantic event queue and general gameplay scheduling remain later work. The shared authored `PackedScene` remains configuration while each restart gets a fresh runtime world instance.

**Done when:** the application can build a non-playing world session, explicitly enter/stop/resume play, restart or transition only after tearing down the old session, exit to a coherent no-world state, preserve persistent UI/config ownership, and reject stale session identity/work after replacement.

**Automated:** passed — the application suite covers direct `READY → PLAYING → STOPPED → EMPTY` lifecycle behavior, application-controlled stop/resume, fresh restart and mission transition, synchronous old-session teardown, stale session-ID rejection, session-owned timer/deferred-work cancellation on teardown, fresh runtime state with shared authored configuration, coherent exit, and the authoritative all-tests CI barrier remained green.

**Manual:** passed — the user confirmed on Windows x64 that F5 still starts the current `VarkTest` world normally and ordinary movement/mouse-look startup and response feel unchanged after the session wrapper.

## 1.3 Gameplay-input boundary, domains, view pose, and frame lifetime `[x]`

Refactor so application ownership is outside locomotion.

Conceptually:

```text
Godot Input
→ application input boundary
    → application/UI input
    → look input
    → gameplay intent frame
        → PlayerCommand for locomotion
        → interaction/combat/inventory actions as real systems arrive
```

Do not grow `PlayerCommand` into interaction/combat/inventory ownership.

Define one gameplay intent frame per gameplay simulation tick. Held gameplay state persists only while physically/currently held and permitted; pressed/released edge intent exists for one gameplay frame only. Disabling a gameplay domain clears transient edges **and cancels incomplete edge-dependent gestures** rather than replaying or leaving them armed later.

Mouse look may retain the existing event-driven cadence needed to preserve accepted response/feel. Treat the resulting player view pose as input-owned state: world gameplay samples it during the controlled simulation step, while a stable-boundary save may capture the current pose synchronously with other player state. UI/menu input is application input and need not wait for a gameplay tick.

The F5 path now binds the current player to one persistent application-owned `ApplicationInputBoundary` before the `WorldSession` enters `PLAYING`. The boundary owns whether gameplay and look domains are permitted, produces at most one locomotion `PlayerCommand` per physics frame, and leaves `PlayerCommand` locomotion-only. Standalone player/movement fixtures retain direct sampling only as a focused fixture/development fallback; that fallback is not the production application ownership path.

Continuous movement/sprint may resume from current physical input when the gameplay domain is permitted. Jump/crouch edge-dependent intent is neutral while disabled; an edge-dependent jump gesture held across domain loss remains blocked until release and a fresh press, and the current buffered airborne-mantle intent is explicitly cancelled on gameplay-domain loss. Look remains event-driven through the application boundary rather than physics-tick quantized; Escape remains application input; the current input-owned view pose is exposed as detached value-owned body/head/view transform data. Interaction/combat/inventory action schemas are not pulled forward before those real systems exist.

**Done when:** the production F5 path has one application-owned gameplay/look boundary; locomotion receives at most one semantic command frame per physics tick; disabled gameplay produces neutral intent without stale edge replay and cancels the representative incomplete locomotion gesture; event-driven look remains independent of gameplay-tick cadence; and the application can sample a detached current view pose without changing accepted movement/look behavior.

**Automated:** passed — the application suite verifies production player/boundary binding, one command sample per physics frame, continuous held movement/sprint versus one-frame jump press intent, disabled-domain neutral intent, continuous-state resume without replaying a held edge gesture, release-plus-fresh-press recovery, explicit airborne-mantle gesture cancellation, event-cadence mouse-look routing, independent look gating, detached view-pose sampling, and the authoritative all-tests barrier remained green.

**Manual:** passed — the user confirmed on Windows x64 that F5 locomotion/traversal and mouse-look response remain accepted after the input-boundary refactor and Escape still releases the mouse normally.

## 1.4 Pause/UI/cutscene input, simulation, and gameplay-time ownership `[x]`

Define arbitration between gameplay, pause, inventory/objectives/map, cutscenes/sequences, and menus.

No unintended gameplay input leaks through inactive ownership.

Define one explicit pause simulation policy: ordinary gameplay simulation and gameplay time stop coherently unless an explicit application-owned exception is intentionally allowed to continue.

Do not implement meaningful gameplay durations from wall-clock time. Search durations, mechanism progress, stagger, delayed gameplay actions, and similar future state must be based on simulation-owned time/progress.

Mouse capture/release and resumed gameplay state must restore correctly without stale gameplay edges or partially armed hold/release gestures.

The application now owns one explicit control mode for gameplay, pause menu, inventory, objectives, map, cutscene, and menu ownership. `GAMEPLAY` is the only mode that permits ordinary `WorldSession` processing plus gameplay/look input. Every current exclusive application-owned mode pauses the session subtree, suppresses gameplay/look input, releases mouse capture through the existing look gate, and leaves persistent application/UI processing and application input live. No special world-simulation exception exists yet; a future sequence may add one only as an explicit application-owned exception when real sequence content proves it is needed.

`WorldSession` now distinguishes `PAUSED` from lifecycle `STOPPED`. It owns monotonic gameplay time in seconds and advances that time only from permitted `PLAYING` physics steps. Pausing therefore freezes player/world processing, session-owned timer work, and gameplay time together without globally pausing the application tree. Resume restores session processing first and then gameplay/look input, so the 1.3 stale-edge/gesture rules remain authoritative across pause ownership changes.

**Done when:** application control ownership can move from gameplay to pause/menu/UI/cutscene modes without leaking world input; ordinary world processing and session gameplay time freeze together while application/UI processing continues; resuming restores world simulation/input coherently without replaying an edge-dependent gesture; and lifecycle stop/restart/transition remains separate from user-facing pause.

**Automated:** passed — the application suite covers direct `WorldSession` `PLAYING ↔ PAUSED` behavior, gameplay-time advancement only while `PLAYING`, all current exclusive control modes mapping to paused world/input ownership, persistent application/UI input and timer work while paused, frozen player pose/session timer/gameplay time during pause, rejection of world-input re-enable while application control is exclusive, held-jump cancellation/no replay on resume, resumed session timer/gameplay time, and the existing lifecycle/input/movement barriers; the authoritative all-tests barrier remained green.

**Manual:** passed — the user confirmed on Windows x64 that normal F5 startup, movement/traversal, and mouse-look response still feel unchanged after pause/time ownership was introduced.

## 1.5 Minimal application/menu shell `[x]`

Provide functional New Game/development start, Quit, and only settings that actually work.

F5 enters a persistent application-owned main menu with no mission world instantiated yet. `New Game` uses the same serialized application lifecycle to instantiate the current default `VarkTest` world and enter normal gameplay. Returning to the no-world state through the application exit path reveals the same menu again rather than leaving the application without player-facing ownership. Phase 1.6 separates the development-target selector from New Game instead of turning New Game into a scene picker.

The shell exposes exactly one current setting: look sensitivity. It keeps the accepted default value, updates the live event-cadence look owner when changed, and remains application-owned so the chosen value is reapplied to replacement players during the same application run. No placeholder Continue, difficulty, save/load, audio, graphics, inventory, objectives, map, or persistence-backed settings are shown before their real systems exist. Quit is wired directly to the application tree quit path.

**Done when:** F5 opens the Vark main menu with no active world; New Game starts the current default world through `VarkApplication`; the only exposed setting changes real look sensitivity and survives ordinary world replacement within the application run; application exit returns to the menu; and Quit closes the application without introducing placeholder product controls.

**Automated:** passed — the application suite verifies no-world `MENU` startup, main-menu/settings/quit wiring, settings-panel navigation, look-sensitivity application to the real player and its event-cadence look owner, retention across world restart, New Game entering the existing lifecycle/input path, exit returning to the menu, and all existing lifecycle/input/pause/movement barriers; the authoritative all-tests barrier remained green.

**Manual:** passed — the user confirmed on Windows x64 that the main menu appears before gameplay, Settings changes real look sensitivity, New Game starts `VarkTest` with accepted movement/traversal/look behavior, and Quit closes the application normally.

## 1.6 Development mission launch `[x]`

Support a fast development route for launching a selected mission/playground without manually opening scenes.

The main menu has a separate development-only launch panel. It reads a small application-owned curated list of display labels and resource paths, lets the developer select a target, and launches that exact target through a serialized `DEVELOPMENT_LAUNCH` top-level operation and the same `_replace_world → WorldSession → application input boundary` path used by normal world ownership. Raw development fixtures may still be `PackedScene` targets; real mission packages may supply a `MissionDefinition` resource that resolves its owned world scene. Exit returns to the persistent main menu, and Back returns from the development panel without creating a world.

The selector remains deliberately curated rather than scanning arbitrary scenes or exposing a filesystem picker. Playground is the first real mission-definition target beside the legacy `VarkTest`; later mission packages can join the same route without bypassing application lifecycle.

**Done when:** F5 offers a development-only selector without requiring scene-editor/manual scene opening; a selected curated target launches through the existing serialized application/world-session/input ownership path; invalid selection or an overlapping top-level operation cannot create a competing session; Back/exit return to coherent menu ownership; and New Game remains a separate default application path.

**Automated:** passed — the application suite verifies curated target presentation, invalid-selection rejection, exclusive-operation blocking, exact selected-target launch through `WorldSession` with gameplay/input ownership, exit/back behavior, separate New Game behavior, and all existing lifecycle/input/pause/movement barriers; the authoritative all-tests barrier remained green.

**Manual:** passed — the user confirmed on Windows x64 that Development Launch shows `VarkTest`, Back returns to the main menu, launching `VarkTest` uses the normal application path, and accepted movement/traversal/mouse-look behavior remains unchanged.

**Phase gate:** application ownership is clear; a world can build non-playing, enter play, stop, tear down, and be replaced without stale work; gameplay time follows world simulation policy; gameplay-input edges and gesture cancellation have deterministic lifetime without changing accepted look/UI cadence; the player view pose can be sampled/captured coherently; and accepted player behavior remains intact.

---

# Phase 2 — Minimal mission, authored identity, and TrenchBroom proof

Goal: prove the real authoring/import/identity path before save/load or broad gameplay systems depend on it.

## 2.1 Mission package convention `[x]`

Create the initial mission folder ownership convention and a tiny playground mission.

The initial package convention is `missions/<mission_id>/`. The first package now contains:

```text
missions/
    playground/
        mission.map
        mission.tres
        world.tscn
        world.gd
```

`mission.map` is the authoritative TrenchBroom spatial source. `world.tscn` is the launchable Godot world wrapper that participates in the existing application/`WorldSession` lifecycle. The tiny `world.gd` is technical development glue that asks FuncGodot to build the package-local map before the session enters ordinary play; it is not the future mission-behavior script surface. Generated `.godot/` data, all `.map.import` sidecars, and TrenchBroom autosaves are not authored mission truth and are ignored. Phase 2.8 retired the former legacy top-level tracked-sidecar exception after the real import/rebuild path proved those sidecars are disposable. `mission.tres` is added by 2.2 as the package's typed metadata owner without changing the 2.1 source/generated boundary.

The Playground contains only a broad zebra floor plus one low reference step and the real `Player.tscn`. It is registered in the existing curated Development Launch route beside `VarkTest`.

**Done when:** one predictable mission package exists under `missions/`; its TrenchBroom `.map` is clearly the authoritative spatial source; its Godot wrapper launches through the application-owned development route and `WorldSession`; the real player is bound through the existing input path; and generated/import recovery metadata has explicit non-source ownership.

**Automated:** passed — the application suite verifies the production Development Launch list includes `Playground`, launches the package through the real session/input path, confirms the package-local map source builds `entity_0_worldspawn`, and the clean-checkout authoritative all-tests CI barrier passed.

**Manual:** passed — the user confirmed on Windows x64 that Development Launch → Playground shows the zebra playground/reference step, spawns the real player normally, and preserves accepted movement/jump/mouse-look behavior.

## 2.2 Minimal MissionDefinition `[x]`

Include only fields currently required to load the playground: mission ID, map/world reference, semantic reference/selection for the map-authored player start, and minimal metadata.

Do not duplicate a player-start transform in `MissionDefinition` when the TrenchBroom map owns it.

Reserve one authoritative mission metadata owner for future `mission_content_revision`.

`res://missions/mission_definition.gd` is now the typed authored metadata resource. The Playground's `mission.tres` contains exactly the current load contract: `mission_id`, `world_scene`, `map_source_path`, `player_start_selector`, and `mission_content_revision`. The content revision starts at `1`, establishing the single metadata owner required by the foundation contract without adding save/load compatibility machinery yet.

Development Launch now points the Playground entry at `mission.tres`. `VarkApplication` validates the definition, resolves its `world_scene`, and passes the same authored resource into `WorldSession` before the wrapper enters the scene tree. The Playground wrapper consumes `map_source_path` from that definition before FuncGodot builds, so the wrapper no longer duplicates the map-source path. Restart creates a fresh world/session while retaining the same authored definition as shared configuration; teardown clears the session reference. Raw development scenes such as `VarkTest` and the alternate fixture still run with no invented mission metadata.

`player_start_selector = &"default"` was introduced here as semantic selection metadata without a duplicated transform. Phase 2.7 now supplies the actual TrenchBroom `vark_player_start` point and resolves that selector after FuncGodot builds; the `.map` owns the selected start transform while `MissionDefinition` continues to own only the semantic selector. `MissionDefinition` contains no player transform/position/rotation fields, so it does not create a second spatial source of truth.

**Done when:** Playground has one loadable authored `MissionDefinition`; the application launches it through that definition; the active session carries the definition as configuration; the definition owns mission ID, world/map references, player-start selection, and content revision without owning a player transform; restart preserves the authored definition while replacing runtime session state; and raw scene development targets still work without fake metadata.

**Automated:** passed — the application suite loads and validates `missions/playground/mission.tres`, verifies all five current fields and the absence of duplicated player-start transform fields, exercises invalid required-field diagnostics, launches Playground through the definition, proves the definition supplies the FuncGodot map path before gameplay, verifies the active world/session carry the same definition across restart, verifies raw scene targets carry no definition, and the clean-checkout authoritative all-tests CI barrier passed.

**Manual:** none — this step changes authored metadata/loading ownership only. The accepted 2.1 Windows Playground playtest covers the unchanged player-facing geometry/start/movement/look behavior; 2.7 owns the later map-authored selector integration check.

## 2.3 Persistent identity feasibility and authoring-workflow proof `[x]`

Prove the real workflow:

```text
create entity
→ import
→ move entity
→ reorder unrelated entities
→ reimport
→ duplicate entity
→ delete/recreate another entity
→ reimport again
```

The original identity must survive ordinary edits; the duplicate must receive a distinct identity; unrelated edits must not reassign IDs.

If tooling generates/repairs IDs, prove the correction persists to the authoritative authored source and repair is idempotent:

- valid source is not rewritten on ordinary validation/import;
- repaired IDs survive another import;
- no endless import/rewrite loop;
- stale generated data cannot overwrite newer authored source edits.

Exercise the workflow from the mapper's point of view. Fragile manual ID bookkeeping is a failed feasibility proof.

The feasibility implementation is deliberately authoring-only. `res://tools/authoring/persistent_id_source.gd` inspects Valve `.map` top-level authored entities, treats `persistent_id` as authored source data, repairs missing IDs, and repairs only later occurrences of duplicate IDs while preserving the first source owner. Repairs are written back to the `.map` source itself, never to generated FuncGodot output. A source SHA-256 token plus an immediate pre-write reread makes stale repair work fail closed instead of overwriting a newer mapper edit. Already-valid source returns without opening it for write, so repeated validation/import does not churn source.

The first Windows mapper pass exposed a real gap in that proof: the repair tool successfully inserted `persistent_id`, but the installed Vark TrenchBroom FGD did not declare the property on `func_detail`; after the entity was moved and saved, TrenchBroom dropped the unknown key and repair assigned a new ID. The fix is project-owned rather than a FuncGodot vendor edit: `authoring/fgd/vark_persistent_identity_base.tres` declares the field, `authoring/fgd/vark_func_detail.tres` composes the ordinary FuncGodot `func_detail` behavior with that Vark base, `authoring/fgd/vark_fgd.tres` is the Vark export set, and `VarkTrenchBroom.tres` exports that `Vark.fgd`.

Refreshing the Vark GameConfig then exposed a second real authoring-config defect: FuncGodot's inherited default exported a non-existent `textures/palette.lmp`, which caused TrenchBroom material loading to fail before it could discover Vark's PNG materials. Vark now explicitly disables that unused palette dependency with `palette_path = ""`; the authoring regression protects the `textures` root, PNG support, empty palette, and representative zebra material.

The accepted Windows mapper run also established an operational rule for external source repair: when `repair` actually changes the `.map` on disk, TrenchBroom must reload/reopen that map before any further edit/save. Otherwise a still-open pre-repair document can overwrite the newly written ID from stale editor memory. The probe now prints this requirement whenever it performs writeback. This is a source-editor synchronization rule, not an identity instability.

The deterministic authoring suite derives a temporary fixture from the real `missions/playground/mission.map`, creates ordinary `func_detail` entities, verifies the Vark TrenchBroom FGD declares `persistent_id`, runs the real FuncGodot parser after each source edit, and covers create/repair, move, source reorder, duplicate repair, delete/recreate, repeated no-op validation, stale-write refusal, and the material config regression. Generated IDs use random 128-bit bytes in the mapper probe; tests inject deterministic IDs only for assertions.

`res://tools/authoring/persistent_identity_probe.gd` provides the mapper-facing proof route. `sync-config` exports and validates the current Vark GameConfig/FGD in the machine-specific FuncGodot TrenchBroom game-config folder; `prepare` copies the real Playground map to ignored `tests/authoring/workspace/mission.map` and refuses to overwrite an existing workspace; `reset` intentionally replaces only that ignored workspace map with a fresh Playground copy; `inspect` reports candidate IDs; and `repair` writes only missing/duplicate ID corrections back to that workspace source and instructs the mapper to reload after any write. The tracked real Playground source therefore remains untouched by the feasibility exercise.

**Done when:** the chosen authored `persistent_id` source/writeback strategy survives create → import → move → unrelated source reorder → reimport → duplicate → delete/recreate → reimport; duplicate repair preserves the original identity and gives the duplicate a distinct identity; repaired IDs persist in `.map` source; valid source is byte-for-byte unchanged by repeat repair; and a stale repair refuses to overwrite newer source. The mapper can exercise the same workflow in TrenchBroom without manually inventing or editing ID strings.

**Automated:** passed — the focused authoring suite verifies the exact Vark TrenchBroom configuration exports a `func_detail` definition containing `persistent_id`, validates the material config has a `textures` PNG root with no missing palette dependency, derives its fixture from the real Playground map, exercises the edit sequence through source repair plus the pinned FuncGodot parser, asserts identity preservation/distinct duplication/recreated identity, proves repeat repair is a no-op with an unchanged source hash, proves stale expected-hash writeback is refused while preserving the newer edit, and passed in the authoritative post-push `Regression suite`.

**Manual:** passed — the Windows mapper/user completed the TrenchBroom 2026.2 proof using the ignored workspace and refreshed Vark config. After each external repair write the map was reloaded before more mapper edits. The original ID survived move/save; unrelated entities preserved their loaded IDs; duplication preserved the source-first original and repair assigned the duplicate a distinct ID; delete/recreate received a fresh ID; a plain TrenchBroom save preserved all loaded IDs; the zebra materials remained available; and no `persistent_id` value was hand-authored.

## 2.4 Persistent IDs `[x]`

Implement the proven authored persistent identity mechanism. Missing/duplicate IDs fail closed with useful diagnostics.

Vark now has a project-owned `FuncGodotMapSettings` resource that uses the same project-owned Vark FGD exported to TrenchBroom, and the project default plus Playground wrapper both use it. The current identity-bearing proof `func_detail` attaches the small `VarkPersistentEntity` script while retaining its existing `StaticBody3D` behavior; FuncGodot automatically applies the authored `persistent_id` string to that runtime node. At 2.4 this established the production identity carrier/boundary without pulling forward the registry, semantic IDs, or the later Vark point-entity vocabulary.

`VarkPersistentIdentityValidator` is deliberately stateless: it scans only nodes explicitly carrying the Vark persistent-entity marker, reports missing IDs with node paths, reports duplicates with both owner paths, and discards its temporary seen-ID table after validation. `WorldSession.build()` runs this validation after synchronous world/FuncGodot construction but before the session can become `READY`; invalid authored identity tears the candidate world down and returns failure. Worlds with no persistent entities remain valid, so raw development scenes do not gain invented persistence requirements.

**Done when:** the runtime FuncGodot path uses the Vark FGD rather than the vendor default; an authored identity-bearing entity receives its `.map` `persistent_id` on the generated runtime Node; unique identity validates; missing/duplicate identity prevents the world session from reaching `READY` with path-specific diagnostics; and no registry, semantic `content_id`, runtime-created identity, or final Vark entity library is pulled forward.

**Automated:** passed — the authoring suite builds mapper-style `func_detail` fixtures through the real Vark `FuncGodotMapSettings`, proves authored IDs land on generated `StaticBody3D` nodes, proves missing/duplicate IDs are visible to runtime validation with useful diagnostics, uses test-only invalid worlds to prove `WorldSession` fails closed and tears down before `READY`, and the exact-head post-push `Regression suite` passed.

**Manual:** none — 2.3 already accepted the Windows mapper/source-writeback workflow; 2.4 adds deterministic runtime wiring/validation without changing player-facing behavior. Full ordinary map edit → import/rebuild → run stability remains the dedicated 2.8 proof.

## 2.5 Optional semantic content IDs `[x]`

Implement author-facing IDs only for entities mission logic actually needs to address.

Vark defines a separate project-owned `VarkContentAddressable` FGD base with optional `content_id`. The Phase-2 `func_detail` proof carrier composes that base so the real TrenchBroom → FuncGodot property path was proven before actual Vark semantic point entities existed; 2.7 now reuses the same base for the first player-start, marker, and exit roles. The tracked Playground still does not assign semantic IDs to ordinary geometry. `VarkPersistentEntity` carries the optional runtime string alongside `persistent_id`, but the two concepts remain distinct: persistent identity is generated/repaired durable instance identity, while `content_id` is a mapper-chosen semantic name such as `door.vault` and is never auto-generated.

Blank `content_id` is valid and means the entity is not addressed by mission logic. Non-empty semantic IDs must be unique within the built world so future mission references cannot become ambiguous. The existing pre-`READY` stateless identity validation reports a duplicate `content_id` with both owner paths and causes `WorldSession` to tear down the invalid candidate. 2.5 itself added validation/property propagation only; 2.6 consumes the validated IDs for current-session lookup, 2.7 chooses the first real point roles that are semantically addressable, and reference-schema validation remains 2.9.

**Done when:** the Vark TrenchBroom FGD exposes optional `content_id` separately from generated `persistent_id`; the real FuncGodot path carries an authored semantic ID onto the runtime entity; blank semantic IDs remain valid; duplicate non-empty semantic IDs fail closed with both owner paths before `READY`; no semantic ID is auto-generated; and no lookup/registry/final entity vocabulary is introduced.

**Automated:** passed — the focused authoring suite verifies the exported Vark FGD contains the separate content-addressable schema, builds a temporary mapper-style `func_detail` with both IDs through the real Vark FuncGodot settings, proves the runtime `StaticBody3D` receives the exact authored `content_id`, proves blank semantic IDs validate, proves duplicate non-empty IDs report both owners, proves `WorldSession` rejects a duplicate-content-ID packed world, and the exact-head post-push `Regression suite` passed.

**Manual:** none — this step adds deterministic authoring/runtime metadata and failure validation only. Phase 2.7 now uses the same semantic-addressing contract for the first real point entities; full edit/import/run stability remains 2.8.

## 2.6 Minimal registry `[x]`

Provide world-session-owned registration/lookup with duplicate/missing reporting. Do not force behavior into a giant base entity class.

`VarkWorldEntityRegistry` is the smallest runtime lookup owner for the identities already proven in 2.4–2.5. It is a `RefCounted` created by the current `WorldSession` during build, reuses `VarkPersistentIdentityValidator` as the fail-closed gate, and only retains indexes after the whole world validates. It indexes every validated authored `persistent_id` and each non-empty optional `content_id`; it does not introduce a second entity hierarchy, registration callback protocol, autoload, or mutable authored `Resource` state.

Lookups return a structured `{ ok, node, error }` result. Valid persistent/content IDs resolve to the exact current-world Node; blank or absent IDs return `node = null` with a useful namespace-specific diagnostic instead of silently returning another object. `WorldSession` owns the registry reference, clears it before freeing the world, and discards it on teardown or failed build, so a retained old registry cannot resolve stale Nodes and a replacement session contains only its own registrations.

This step intentionally does not define authored references, required semantic IDs, point-entity classes, runtime-created persistence registration, or mission-script APIs. 2.7 supplies the first real Vark semantic entities; 2.9 validates real authored references once such references exist; runtime-created registration remains deferred until the first real runtime-persistent object requires it.

**Done when:** a successful `WorldSession` build owns exactly one registry for its validated world; persistent and non-empty semantic IDs resolve to exact current-world Nodes; blank/missing lookups report useful failure without returning a Node; invalid identity cannot leave a partial registry; teardown clears/discards registrations before world destruction; a replacement session cannot resolve IDs from the old world; and no global registry/entity base/reference system is pulled forward.

**Automated:** passed — the focused authoring/runtime regression builds valid registry fixtures through the real `WorldSession`, verifies persistent/content lookup and counts, verifies blank/missing diagnostics, verifies missing/duplicate identity failures leave no registry, retains an old registry reference across teardown to prove it is cleared, rebuilds a replacement session to prove stale IDs do not resolve, and the exact-head post-push `Regression suite` completed successfully. The later 2.7 exact-head regression also remained green over the same registry coverage.

**Manual:** none — this is deterministic runtime ownership/lookup plumbing with no mapper workflow or player-facing behavior change. 2.7/2.8 own the next author-facing entity/reimport checks.

## 2.7 TrenchBroom Vark entity foundation `[x]`

Create only the entity vocabulary needed for the playground: player start, generic semantic marker, minimal exit, and spike entities as they arrive.

Vark owns three project-side FuncGodot/TrenchBroom point classes: `vark_player_start`, `vark_marker`, and `vark_exit`. Each directly declares the already-proven `persistent_id`, optional `content_id`, and angle fields in its own mapper-facing definition, builds as a lightweight `Node3D`, attaches the shared Vark persistent runtime carrier, and participates in the current `WorldSession` registry. TrenchBroom 2026.2 required the identity fields to be flattened onto the point definitions rather than supplied only through FGD base inheritance; no vendor FuncGodot resources are modified. The marker and exit are semantic endpoints only at this stage; they do not pull forward interaction, mission objectives, transitions, or the Phase 3 gameplay-event system. Additional spike-specific entity roles are added only when a real later spike needs them rather than being invented here.

The tracked Playground `.map` contains one of each role with stable authored `persistent_id` values and semantic IDs `default`, `marker.playground_reference`, and `exit.default`. `MissionDefinition.player_start_selector = &"default"` resolves exactly one generated `vark_player_start` after FuncGodot builds. The Playground wrapper then copies that authored point's global transform to the real Player before ordinary play, so the `.map` owns start position/orientation and `world.tscn` no longer carries a competing start transform.

`persistent_identity_probe.gd -- sync-config` verifies the exported Vark FGD contains all three point roles in addition to the existing identity/content/material checks. This keeps the mapper installation/config refresh route aligned with the runtime FGD rather than creating a second entity schema.

**Done when:** the exported Vark FGD exposes `vark_player_start`, `vark_marker`, and `vark_exit`; the tracked Playground can author/build one valid persistent and semantically addressed runtime point for each role; `MissionDefinition.player_start_selector` resolves exactly one map-authored start and places the real Player from that source without a scene-owned transform; all three points register through the existing current-session registry; the mapper can see/use the refreshed vocabulary; and no full 2.8 edit/reimport-stability proof, 2.9 authored-reference validator, or future gameplay behavior is pulled forward.

**Automated:** passed — the exact-head Godot 4.7.2 post-push `Regression suite` verifies the exported Vark FGD point vocabulary, builds the tracked Playground source and finds one valid persistent/content-addressed `Node3D` per point role, proves the Playground resolves `player_start_selector` to the map-authored start and registers all three semantic points, keeps the earlier content-ID/registry regressions green, and finishes with `ALL AUTHORING TESTS PASSED`, `ALL APPLICATION TESTS PASSED`, `ALL MOVEMENT TESTS PASSED`, and `ALL TEST SUITES PASSED`.

**Manual:** passed — the Windows mapper/user refreshed the Vark config, explicitly reopened the authoritative Playground document, confirmed `vark_player_start`, `vark_marker`, and `vark_exit` expose `angle`, `classname`, `content_id`, `origin`, and `persistent_id` with **Show default properties OFF**, confirmed semantic IDs `default`, `marker.playground_reference`, and `exit.default` plus the existing non-empty `vark_...` persistent IDs, and confirmed Development Launch → Playground uses the authored start with normal movement/mouse look. During diagnosis, a stale already-open TrenchBroom document initially exposed only `classname`/`origin`; a fresh copy parsed all five properties, and closing the stale document without saving then explicitly reopening the authoritative path restored the correct property set. That editor-state issue did not modify the clean `.map` source.

## 2.8 Reimport stability `[x]`

Prove `edit .map → save → import/rebuild → run` without unrelated repair and with stable persistent identity.

The deterministic authoring regression now clones the real Playground source into `user://`, makes one representative move of the authored `vark_player_start`, and verifies both the baseline and edited sources through the same read-only reimport verifier. The verifier requires valid authored identities, requires a dry `PersistentIdSource.repair_source()` pass to be byte-for-byte unchanged, builds the real Playground wrapper through `WorldSession`, resolves all three semantic points, applies the authored player start to the real Player, and enters `PLAYING`. The regression compares the two builds to prove all three `persistent_id`/`content_id` mappings remain stable, the edited start transform changes, and the marker/exit transforms do not churn.

`tools/authoring/playground_reimport_probe.gd` exposes the same read-only verification against the tracked Playground source for the Windows mapper handoff. It never repairs or writes the authoritative `.map`; a source that would need repair fails instead. Phase 2.8 also closes the deferred generated-sidecar policy: `.map` remains authored source, all `*.map.import` files are generated FuncGodot/Godot metadata and are ignored, and the four legacy tracked top-level sidecars are removed. Clean-checkout Godot import/CI is the authority that this generated metadata can be recreated rather than versioned.

**Done when:** an ordinary TrenchBroom move/save of the tracked Playground player start preserves all existing persistent and semantic IDs, the real Godot/FuncGodot wrapper rebuild consumes the edited transform and reaches `PLAYING` without identity repair, restoring the start to its original authored pose produces a clean source diff, and no tracked `.map.import` metadata is required as source truth.

**Automated:** passed — the focused authoring suite exercises the temporary representative edit, byte-for-byte no-op identity-repair check, stable identity/content mappings, intended-only point-transform change, real `WorldSession` rebuild, and `READY → PLAYING` transition; the authoritative clean-checkout all-tests CI passed on the accepted implementation head, also proving removed `.map.import` sidecars are regenerable/non-source.

**Manual:** passed — validator: **Windows mapper/user with TrenchBroom 2026.2 (`Build v2026.2 Release Win64`)**. The mapper explicitly reopened `missions/playground/mission.map` from disk, preserved the existing player-start `persistent_id` and `content_id = default`, moved `vark_player_start` exactly +32 mapper units on X, saved, and verified the read-only probe reached the real Playground `PLAYING` path without identity repair while the moved authored start was consumed with normal movement/look. The point was restored exactly, the probe/Playground path was rerun, and the final `git diff -- missions/playground/mission.map` was empty. The first acceptance attempt exposed only TrenchBroom normalization of repository-added descriptive comments; the tracked map was canonicalized to TrenchBroom's save-normalized form before the final clean round trip. No `persistent_id` was hand-edited.

## 2.9 Basic content validation `[x]`

Add the first content-specific pre-`READY` validation boundary without inventing a general mission-reference framework or Phase 3 gameplay.

`VarkMissionContentValidator` runs only for typed `MissionDefinition` sessions after FuncGodot construction and the current-world entity registry succeed. The existing identity validator/registry remain authoritative for missing/duplicate `persistent_id` values and duplicate non-empty `content_id` values. 2.9 adds only the checks real content can express now: `MissionDefinition.player_start_selector` must resolve through the current registry to a persistent `Node3D` in `vark_player_start`, and the built mission must contain at least one persistent `vark_mission_exit`. Multiple distinct starts and multiple exits remain valid; the selector chooses one start. Raw `PackedScene` development targets do not gain mission-content requirements.

`WorldSession` also rechecks `MissionDefinition.get_load_errors()` for direct session callers, so the reimport probe and future non-application build paths cannot bypass required metadata validation. Its existing exactly-one-player assumption now fails closed with diagnostics for zero or multiple `vark_player` nodes instead of a silent missing-player failure or assertion. Any definition, identity/semantic-ID, required-object, or current authored-reference failure keeps the candidate session from `READY` and tears down world/registry state as appropriate.

**Done when:** a valid Playground still reaches `READY`/`PLAYING`; typed mission sessions cannot bypass static `MissionDefinition` load validation; missing/duplicate persistent or non-empty semantic IDs remain fail-closed through the existing registry gate; a missing or wrong-role `player_start_selector` fails before `READY`; a built mission with no authored `vark_exit` fails before `READY`; zero or multiple runtime `vark_player` nodes fail cleanly with useful diagnostics; raw scene targets with one player remain unaffected; and no Phase 3 interaction/objective/transition/reference framework is introduced.

**Automated:** passed — the focused authoring suite and authoritative all-tests/CI barrier exercise the real Playground valid path, empty static selector rejection, missing and wrong-role player-start references, a disposable real-Playground map with the exit role removed, and zero/two-player world fixtures while retaining the identity/content-duplicate regressions and 2.8 reimport-to-`PLAYING` proof. Exact implementation head `82fd934c9239cafbb5dac23deef3b5be79fc2ed8` passed Godot 4.7.2 `Regression suite` run #54 with `ALL AUTHORING TESTS PASSED`, `ALL APPLICATION TESTS PASSED`, `ALL MOVEMENT TESTS PASSED`, and `ALL TEST SUITES PASSED`.

**Manual:** none — this is deterministic fail-closed validation and does not change TrenchBroom schema, mapper workflow, mission geometry, or player-facing behavior. The accepted 2.7/2.8 Windows mapper runs already cover the unchanged authoring/edit/reimport/run path.

**Phase gate:** a tiny mission loads from the real package/TrenchBroom path, starts, exits, keeps stable authored identities through representative editing/reimport, and uses an idempotent source-of-truth identity workflow.

---

# Phase 3 — Small contracts, isolated spikes, then the five-minute stealth slice

Goal: answer dangerous subsystem questions independently enough to debug them, then force them to collide in one real playable route before broad frameworks are committed.

The integrated graybox contains one room/corridor arrangement, ordinary door, gameplay light, two footstep surfaces, throwable/stackable prop, simple patrolling guard, primitive vision/hearing, one audible typed NPC line, one objective, and one exit.

## 3.1 Minimal interaction contract `[x]`

Introduce only enough common behavior for center-view target selection, range/occlusion/state eligibility, one primary interaction command, and the locked Thief-style fullbright/no-received-shadow selection feedback while preserving ordinary cast shadows.

The ordinary door and physical prop use the same interaction contract.

Interaction ownership, not every interactable object, decides whether ordinary world interaction is currently available. In particular, later carried-Junk/body states should not require every door/switch/loot object to know private carrying state.

The first implementation keeps interaction intent separate from locomotion `PlayerCommand`. `ApplicationInputBoundary` owns one fresh `interact` edge per gameplay physics frame, suppresses a held interaction across gameplay-domain loss until release, and publishes gameplay-domain availability to the bound player. `PlayerInteraction` is a small player-owned selector that casts from the real view camera center to a configurable short range, treats the first physics hit as the occlusion boundary, asks only the hit `vark_interactable` whether its current state is eligible, and owns target highlight changes. A separate `world_interaction_available` gate gives later held-prop/body ownership one central place to suppress ordinary interaction without checks copied into every interactable. The default keyboard mapping for the primary interaction action is **F**. Selection feedback does not tint or emissively recolor the target: the target keeps its base color and ordinary cast-shadow behavior, while its own visible surface renders unshaded/fullbright and receives no scene shadows until selection clears, at which point ordinary shaded surface response is restored.

The interactable surface is intentionally narrow and concrete: an object joins `vark_interactable` and implements `can_interact(interactor)`, `interact(interactor)`, and `set_interaction_highlighted(highlighted)`. The development-only `Interaction Lab` contains door-like and prop-like probes that both use that exact contract, including an occluder and a one-shot state-ineligible probe. They are contract probes only; actual door state/navigation/acoustics and Thief-style prop carrying/support remain 3.4/3.5, and no 3.2 semantic event queue/stable-boundary framework is pulled forward.

**Done when:** the production player can select only the first center-view interactable within range and clear line of sight; target-owned current state can reject selection; one primary interaction press is a one-frame application-owned gameplay edge that cannot replay after domain loss; Thief-style fullbright/no-received-shadow selection follows the eligible current target while preserving ordinary cast-shadow behavior, clears on loss, and restores ordinary shaded surface response; ordinary world interaction can be centrally disabled/resumed without interactables knowing the private reason; the door-like and prop-like probes consume the same contract; locomotion `PlayerCommand` remains interaction-free; and no door/prop/event/objective framework is introduced.

**Automated:** passed — deterministic coverage is wired into the focused application suite and authoritative all-tests barrier. It exercises the real application/session/player path in `Interaction Lab`, the **F** input mapping, center targeting, out-of-range rejection, first-hit occlusion, state eligibility, fullbright/no-received-shadow selected surfaces with preserved cast shadows plus normal shaded-surface restoration, fresh-edge/no-hold-repeat behavior, central availability suppression/resume, and application-domain stale-edge suppression while retaining all existing application/input/movement coverage. Exact accepted implementation head `7da6b969e90a507163f931b2820062e07d58299a` passed Godot 4.7.2 `Regression suite` run #68 with `ALL AUTHORING TESTS PASSED`, `ALL APPLICATION TESTS PASSED`, `ALL MOVEMENT TESTS PASSED`, and `ALL TEST SUITES PASSED`.

**Manual:** passed — validator: **Windows x64 user/playtester**. The user accepted the final `Interaction Lab` behavior: no permanent central crosshair; Door and Prop probes select only when centered/in range/unobstructed; selected surfaces become fully unshaded/fullbright with no received/self-shadow-style darkening or tint while preserving their ordinary cast shadows; normal surface shading returns when selection clears; **F** is the primary interaction key with no held-repeat; the one-shot prop becomes `INACTIVE` and clears selection; and ordinary walk/jump/crouch/sprint/mouse-look remain accepted.

## 3.2 Minimal semantic gameplay-event queue and stable boundary `[x]`

Add the smallest world-session-owned semantic event route needed by the spike.

Before mission/objective/save logic depends on it, prove:

- FIFO processing at one controlled gameplay point for a given emitted sequence;
- deterministic ordering for that sequence without pretending unrelated physics discovery is globally ordered;
- nested emissions append rather than recurse into undefined call order;
- world-session ownership/stale-world rejection;
- no normal dispatch while BUILDING, RESTORING, or TEARING_DOWN;
- participating handlers finish synchronously and do not `await` inside the current drain;
- a development runaway/cascade guard reports an accidental self-sustaining event loop instead of hanging forever;
- one stable gameplay boundary after the current controlled semantic consequence pass has drained;
- engine callbacks outside the controlled pass may update presentation/input-owned view state or queue future semantic work but cannot race durable world state across the stable boundary.

Do not create a general scheduler or author-facing rule language here.

The implementation is deliberately session-local rather than a new manager layer. `WorldSession` accepts detached value-owned semantic payloads only from its current `PLAYING` session identity, queues them FIFO, and drains them at a late controlled physics priority after ordinary default-priority gameplay physics. Ordered handlers must return `true` synchronously; nested emissions append to the same queue rather than recursing. The session publishes only a monotonically increasing stable-boundary serial after a successful drain, so later save capture can bind to that boundary without exposing an arbitrary callback scheduler. BUILDING, RESTORING, READY, PAUSED, STOPPED, TEARING_DOWN, stale-session, and live-Object payload attempts do not enter normal dispatch. A bounded development cascade guard clears and reports a trace instead of hanging on a self-sustaining loop. Teardown discards queue, handlers, sequence, diagnostics, and boundary state with the old world.

**Done when:** a given emitted sequence drains FIFO at one controlled world-session gameplay point; nested emissions append after already-registered handlers for the current event; detached payloads cannot retain live world objects or be mutated through the emitter/another handler; stale/foreign sessions and non-`PLAYING` lifecycle states cannot enter normal dispatch; participating handlers must acknowledge synchronous completion; a runaway cascade is bounded and reported; ordinary out-of-pass callers can only queue future semantic work; teardown prevents old-world event state from reaching a replacement; and the stable-boundary serial advances only after a successful consequence drain. No global physics-order promise, general scheduler, mission-rule language, sound event, door behavior, or save system is introduced.

**Automated:** passed — deterministic 3.2 coverage is wired into the focused application suite and authoritative all-tests barrier. It covers explicit BUILDING/RESTORING/TEARING_DOWN/READY rejection, stale-session rejection, live-Object payload rejection, deep payload detachment and per-handler isolation, emitted-order FIFO, nested append rather than recursion, a default-priority physics emitter draining at the later session point, out-of-pass queue-without-immediate-mutation behavior, synchronous-handler acknowledgement failure withholding the stable boundary, bounded runaway-loop diagnostics/recovery, teardown cleanup, and replacement-session isolation. Exact implementation verification head `9a37d0589456a2abe3ebcc3064a605586494ef5a` passed Godot 4.7.2 `Regression suite` run #72 with the new 3.2 cases plus `ALL AUTHORING TESTS PASSED`, `ALL APPLICATION TESTS PASSED`, `ALL MOVEMENT TESTS PASSED`, and `ALL TEST SUITES PASSED`.

**Manual:** none — accepted from deterministic automated coverage because 3.2 establishes internal timing/ownership semantics and intentionally adds no new player-facing behavior.

## 3.3 Minimal semantic gameplay-sound event `[x]`

Separate gameplay-significant sound from presentation audio before acoustic propagation is prototyped.

The first contract is one reserved world-session semantic fact, `gameplay.sound`. Its payload contains exactly `kind: StringName`, `origin: Vector3`, and a finite positive `strength`. `strength` is only a relative source-strength input for later acoustics; it does **not** define a radius, decibel model, attenuation curve, portal/zone model, or final hearing threshold. Presentation details such as `AudioStream`, audio bus, volume dB, pitch, and `AudioStreamPlayer` ownership are deliberately absent. A gameplay sound can therefore exist and be tested headlessly even when no presentation sound is played, and presentation audio cannot become stealth truth merely by being loud.

`WorldSession.queue_gameplay_sound()` validates and queues this fact through the accepted 3.2 FIFO/stable-boundary route. The reserved event name is validated even when a caller uses the generic semantic-event entry point, so ad-hoc presentation-shaped payloads cannot bypass the sound contract. This step does not propagate sound, decide who hears it, play audio, define a sound taxonomy framework, or add footsteps/door/prop/speech emitters; those real consumers arrive in their scheduled micro-proofs.

**Done when:** the current `PLAYING` world session can queue a gameplay-significant sound as only semantic kind/origin/relative-strength data; stale/foreign or non-`PLAYING` session work is rejected through the existing event boundary; empty kinds, nonpositive/non-finite strength, and presentation-audio-shaped payloads are rejected; valid sounds dispatch only at the controlled semantic consequence point and advance the stable boundary normally; no presentation audio is required or created; and no acoustic propagation, hearing reaction, radius/attenuation model, general sound taxonomy, or concrete door/prop/footstep/speech emitter is pulled forward.

**Automated:** passed — deterministic 3.3 coverage is wired into the existing focused application semantic-event regression and authoritative all-tests barrier. It checks READY rejection, stale-session rejection, empty/nonpositive semantic validation, rejection of a reserved `gameplay.sound` payload carrying presentation `volume_db`, queue-without-immediate-dispatch behavior, exact detached semantic payload shape, and stable-boundary delivery through the accepted 3.2 route. Exact implementation verification head `35297d21e864d08c1e8192ceee666cc6d63c3361` passed Godot 4.7.2 `Regression suite` run #76 with the 3.3 cases plus `ALL AUTHORING TESTS PASSED`, `ALL APPLICATION TESTS PASSED`, `ALL MOVEMENT TESTS PASSED`, and `ALL TEST SUITES PASSED`.

**Manual:** none — 3.3 establishes an internal semantic separation and intentionally plays no audible sound or other player-facing presentation.

## 3.4 Ordinary door micro-proof `[x]`

Prove interaction, collision/obstruction, open/closed presentation, vision-blocking relationship, acoustic integration seam, NPC/navigation integration seam, semantic events, and semantic state capture/apply.

At this step, prove the **door-side contracts/seams** needed by later acoustics and NPC/navigation use. Do not pull the primitive guard/navigation implementation from 3.7 into 3.4 merely to exercise that future consumer. The first real guard/nav proof in 3.7 must exercise this same ordinary door seam; if that integration exposes a defect, correct the seam rather than inventing a second door/nav model.

Do not build keys/locks/barred behavior yet unless required by the proof.

The first ordinary door is a reusable `AnimatableBody3D` hinge leaf rather than the 3.1 door-like probe. It consumes the same `vark_interactable` surface and Thief-style selection presentation, owns explicit `closed/opening/open/closing` semantic phase plus `open_fraction`, and advances its physical hinge transform from gameplay physics rather than a tween/coroutine as durable truth. A completed transition emits `door.state_changed`; each accepted use emits the 3.3 `gameplay.sound` source fact with kind `door.use`. The physical leaf collider is also the closed-door vision obstruction, so opening clears the actual doorway rather than toggling a separate invisible blocker.

The 3.4 implementation keeps the visible leaf behind an exported `Mesh` presentation seam. `OrdinaryDoor.tscn` selects a project-authored external OBJ model by default, and the Door Lab regression swaps that presentation to a second compatible OBJ while retaining the same ordinary-door instance, interaction target, collider/vision obstruction, semantic state, events, and save-state behavior. The model remains presentation/configuration rather than semantic identity. An openable window is simply a door/opening variant using this same archetype/integration path; no separate window subsystem is planned. Phase 3.4 is accepted after the required automated barrier and focused Windows manual validation both passed.

Two deliberately narrow consumer seams are exposed for later proofs: `get_acoustic_openness()` reports only the door-side 0..1 opening state for 3.6 to interpret through whatever propagation model proves correct, and `is_navigation_passage_open()` reports whether the leaf is fully open for the first 3.7 guard/nav consumer. The door does not implement propagation, hearing, a nav framework, or guard logic. `capture_semantic_state()` / `apply_semantic_state()` preserve phase, progress, and the latched blocked-motion state, then rebuild the derived hinge pose without replaying sound or state-change consequences.

A development-only `Door Lab` launches through the normal application/session/input path with a framed doorway and a visible target behind it so closed/open collision and straight-through vision behavior are legible. The accepted 3.1 Interaction Lab remains unchanged as the narrow selector/highlight fixture.

**Done when:** one real ordinary door uses the accepted center-view/F interaction contract and selection feedback; its visible leaf comes from a replaceable external 3D model asset while the ordinary-door archetype remains the semantic/gameplay owner; interaction visibly animates one physical collision leaf between explicit closed/open states; the closed leaf blocks the doorway and straight-through vision while the fully open leaf clears both; accepted use emits one semantic `door.use` gameplay sound and completed transitions emit one semantic door-state event through the current world session; acoustic openness and navigation-passage state are exposed only as door-side source-state seams; semantic capture/apply preserves stable and in-progress state without serializing/replaying runtime continuation machinery; swapping a compatible visual model does not require changing gameplay rules; and no keys/locks/barred behavior, separate window subsystem, acoustic propagation, hearing consumer, guard AI, or general navigation framework is introduced.

**Automated:** passed — the focused Application regression covers the ordinary-door behavior seams through `Door Lab`, including external OBJ instantiation/model replacement without changing semantic ownership, interaction, collision/vision obstruction, state, highlighting, events, consumer seams, or restore behavior. It also proves the accepted frame fit and Thief-style obstacle behavior: a moving leaf stops before entering the real player body, remains latched while blocked, preserves that stopped semantic state through capture/apply, reverses on the next interaction, and can subsequently complete normal motion. Exact implementation head `75500104ac79c0f3ceef0d52f154d82ce35e0b96` passed Godot 4.7.2 GitHub Actions `Test` run #83 and the authoritative all-tests barrier.

**Manual:** passed — validator: **Windows x64 user/playtester**. The user accepted the corrected near-frame door fit, normal visible opening/closing and passage/vision behavior, and Thief-style obstacle handling: a closing door stops instead of moving through the player, stays stopped, reverses to opening on the next **F** interaction, and closes normally again once clear. No ghost collision, presentation detachment, or locomotion/mouse-look regression was reported. No audible door clip is expected in 3.4—the accepted sound proof here remains the semantic gameplay-sound fact, not presentation audio.

## 3.5 Thief-style prop micro-proof `[x]`

The carried-Junk micro-proof is accepted. Its dependency order remains explicit:

1. **Release/throw collision transaction.** Release placement uses the prop's real collision volume against world/other-prop blockers while deliberately allowing the chosen pose to overlap the releasing player's capsule when space is cramped. Physics categories are distinct (`world`, `player`, `ordinary_prop`, and one transient `ordinary_prop_player_overlap` filter channel), so once Junk leaves the carried slot it is immediately a live rigid body with ordinary world/prop collision and the full F-throw or R-release velocity. While the prop's actual shape still overlaps the releasing player, only that prop is moved to the transient channel that the player does not scan and its own mask excludes the player; world and prop channels remain active. Geometric separation restores the ordinary prop layer/mask. The carry→world launch itself is committed through the rigid body's synchronized `PhysicsDirectBodyState3D` boundary (`_integrate_forces`): the release callback stages the intended pose/velocity and wakes the body, then the first active solver step atomically receives transform, filter and full F/R velocity. Do not freeze/kinematically translate the prop, zero global collision participation, use a timer/distance guess, or rely on a cached pairwise exception as the launch mechanism.
2. **Player dependency invalidation.** Picking up a prop immediately invalidates standing support and active catch/hang/corner/mantle state derived from that exact collider RID. Unrelated support/traversal state remains untouched.
3. **Explicit lightweight world-physics promotion.** A settled ordinary prop remains in exact dormant/stable state so authored edge placements and stacks cannot drift from background contact stabilization. Ordinary crates use lighter mass/friction and stronger bounded response tuning so deliberate player pressure moves them readily and prop-on-prop impacts transfer visibly more motion. A meaningful moving-prop impact promotes the struck prop into real dynamic Jolt motion; lateral player locomotion contact applies one bounded shove at the production contact-solver boundary; standing on a prop does not count as a shove. Support removal also promotes the prop into unsupported motion. Angular motion remains locked, so these explicit disturbances translate boxes without introducing free tumble.
4. **Always-upright dynamic/rest authority.** F throw and R gentle release choose placement from the current view but normalize the box top-up before the carry→world rigid-body handoff, preserving horizontal yaw. The placement query uses that same upright collision volume. Ordinary props stay top-up in settled, carried, thrown/released, unsupported/disturbed, and restored semantic states. Jolt continues to own translation and linear velocity while moving, but angular solver response is locked and any tilted incoming/restored basis is normalized top-up immediately. Dynamic contact state determines real support/rest; once supported low-speed rest is proven for the required contact frames, the body transitions directly `moving → settled`. There is no semantic settling phase, gravity suspension, multi-frame pitch/roll interpolation, or orientation-reseating stage.
5. **Dynamic-prop traversal ownership.** Catch/hang/corner keep requiring an exact settled prop, but mantle preserves the already-accepted traversal motion for both grounded and airborne contact. A prop-backed mantle records the collider transform that produced its world-space ledge sample and keeps the mantle edge/route bound to that same collider while it translates. Lift and forward phases keep chasing the refreshed route, while source translation along the ledge tangent is inherited through collision-resolved player motion so an angled shove cannot slide the moving top sideways out from under the player or double-apply route motion. A light crate that was just shoved therefore still mantles through the normal `PlayerMantle` path instead of falling through to jump or finishing against stale geometry; loss or blockage of the tracked attachment releases cleanly to air.
6. **Post-mantle ownership handoff.** The reproduced intermittent freeze was traced to a tolerance mismatch in the real `PlayerMantle` forward phase: collision/progress logic accepted a small route remainder while completion still required exact crossing of the mathematical plane. A capsule stopped a millimeter or two short could therefore remain in `MANTLING` forever. Forward completion now accepts the same route-progress tolerance, and the permanent regression places the real Player at a positive sub-tolerance remainder with further forward travel effectively blocked, then requires traversal ownership to return to locomotion on the next physics frame. The temporary freeze trace and its solver-only snapshots were removed after the corrected Windows retest.
7. **Acceptance.** Keep the existing carried-Junk HUD, F throw, R gentle release, hard-edged rendering, real rigid translation, stable authored edge/stack rest, semantic sound/capture/reconcile seams, and accepted player movement feel unchanged.

**Done when:** world/prop blockers remain solid during release placement; F and R enter world physics with the box top already up and ordinary props remain top-up throughout moving/restored state with no settling/orientation-correction phase; an initially player-overlapping throw retains its intended impulse and restores normal player collision after separation; picking up the exact supporting/traversal prop ends that dependency immediately; grounded contact with a recently shoved prop enters the same mantle motion as airborne contact, stays attachment-relative when an angled shove gives that collider lateral motion, and returns ordinary locomotion from already-held input instead of becoming a jump or stuck state; catch/hang/corner do not retain moving-prop snapshots; settled props remain exactly stable without drifting but are clearly easier to move by deliberate player pressure and react more strongly to another prop impact; a pre-tilted restored/moving semantic state is normalized top-up immediately and can reach stable rest without an intermediate semantic phase; no-gap/no-free-tumble behavior remains; post-mantle traversal hands ownership back to ordinary locomotion even when the final forward remainder is positive but within the accepted route tolerance; and the authoritative all-tests barrier plus Windows x64 user acceptance pass.

**Automated:** passed — the dedicated Props suite remains in the authoritative all-tests barrier and covers upright F/R carry→world orientation, shape-aware placement, transient player-overlap filtering, exact support/traversal invalidation, moving-prop mantle ownership, lighter push/impact tuning, direct moving→settled rest, always-upright restore/motion, and the permanent real-player mantle-completion tolerance regression. Exact fix head `6c180e73e4d372c7c3f8c8dfe0b7105110c54ed1` passed Godot 4.7.2 GitHub Actions Test run #208.

**Manual:** passed — validator: **Windows x64 user/playtester**. After the tolerance fix, the user retested the moving-crate mantle and reported the previously reproduced post-mantle freeze resolved, then explicitly advanced development to the next roadmap step. The accepted Prop Lab behavior remains F throw materially stronger than R release, top-up boxes through carry/throw/fall/collision/rest/restore, lightweight deliberate shove/prop-impact motion without tumble, exact stable rest, moving-crate mantle tracking, and immediate return to ordinary locomotion from already-held input.
## 3.6 Acoustic propagation micro-proof `[x]`

Use a test layout with open room, separated room, open doorway, closed door, and L-shaped corridor.

The focused spike now chooses **authored acoustic spaces plus portals** as the current propagation prototype. This is a prototype result, not a production-stable Phase 5 API. A world-owned `VarkAcousticPropagation` consumes the already-accepted semantic `gameplay.sound` event synchronously inside the current `WorldSession` consequence pass. Source and listener positions resolve into authored box spaces; propagation searches connected portal routes using accumulated world-space distance attenuation plus per-portal transmission cost. A nearby disconnected room therefore has no route, while an L-shaped connection can carry sound around architecture without pretending a straight source-listener ray is sufficient.

The ordinary door remains the integration spine. A portal may reference its existing `door_id`; transmission continuously interpolates from authored closed to open transmission using the same `get_acoustic_openness()` seam proven in 3.4. No second acoustic door model exists. `VarkAcousticListener` is only the minimal hearing-consumer seam needed to expose propagated strength, route, source kind, and a thresholded heard/muted result. It is deliberately not guard awareness, investigation, or navigation; 3.7 and later perception work consume this evidence rather than being pulled into the acoustic spike.

TrenchBroom gets one native brush entity, `vark_acoustic_space`, plus the point entity `vark_acoustic_portal`. The user-supplied TrenchBroom 2026.2 manual is pinned at `docs/reference/trenchbroom-2026.2-reference-manual.html`; its brush-entity workflow is now the version-specific authoring reference for this spike. A mapper creates/resizes one ordinary axis-aligned rectangular brush and converts that brush to `vark_acoustic_space`, so the brush itself is the visible/editable acoustic boundary instead of a point entity pretending to be a volume through duplicate numeric extents and a display model. FuncGodot imports that solid class as a non-visual convex `Area3D` helper with zero collision layers/masks; `VarkAcousticSpace` derives its runtime box half-extents from the imported brush geometry and fails closed on multi-brush, rotated, wedge, or otherwise non-box authoring. The current 32-units-per-world-meter map-scale contract therefore applies through normal FuncGodot brush import rather than custom mapper extent properties. Portals continue to author stable acoustic IDs, connected space IDs, optional ordinary-door ID, and closed/open transmission. This is the explicit mapper cost of the chosen prototype; no automatic room inference or geometry scanning is hidden behind the workflow.

A development-only **Acoustic Lab** uses the real application/session/player path and exposes three semantic source probes (representative footstep, speech, and impact strengths), four listener markers, the real ordinary door, a disconnected room, and a two-portal corner route. Listener labels/debug output show HEARD/MUTED, propagated strength, and the selected portal route. Presentation audio is intentionally unnecessary; gameplay-significant audibility remains semantic and headless-testable.

**Done when:** one world-owned propagation owner consumes `gameplay.sound` only through the accepted session event route; same-space distance attenuation, connected portal routing, disconnected-space rejection, and multi-portal corner routing are deterministic; the real ordinary door continuously changes the same portal's transmission; representative footstep/speech/impact source strengths produce useful listener evidence without coupling to AudioStream volume; malformed duplicate/missing topology fails closed with useful diagnostics; TrenchBroom exports the acoustic-space brush class plus portal point class, the acoustic-space volume is the mapper's actual editable rectangular brush, and real FuncGodot import proves that brush dimensions become the expected Vark world-space box without presentation geometry or gameplay collision; the mapper cost is explicit; and no guard AI, awareness state, nav framework, presentation-audio authority, or generalized production acoustic framework is pulled forward.

**Automated:** passed — the Acoustics suite is wired into `tests/run_all_tests.gd` and proves FGD export of the native acoustic-space solid class and portal point class, authoritative 32:1 map-scale alignment, real FuncGodot import of rectangular acoustic-space brush geometry/topology, rejection of the superseded display-model/mapper-extent path, duplicate/missing-link failure diagnostics, Acoustic Lab launch through the production application/session path, same-room attenuation, disconnected-room rejection, two-portal corner routing, continuous ordinary-door transmission, queued semantic-event timing, and representative thresholded footstep/speech/impact hearing relationships. Exact correction head `bbe9e58ccfd5d509955ee83ad6b5bb586080432a` passed Godot 4.7.2 GitHub Actions Test run #214 with `ALL ACOUSTIC TESTS PASSED` and `ALL TEST SUITES PASSED`.

**Manual:** passed — validators: **Windows x64 user/playtester** and **Windows mapper/user with TrenchBroom 2026.2**. The user completed the Acoustic Lab acoustic-intuition pass and then confirmed the corrected native `vark_acoustic_space` brush workflow, independent rectangular resizing, save/reopen persistence, `vark_acoustic_portal` editing/persistence, clean FuncGodot import, and focused Acoustics regression all behaved correctly. This closes the two earlier mapper failures (invisible point-entity extents and the square/cube display-model workaround) in favor of the native brush-entity authoring contract.

## 3.7 Primitive guard/nav micro-proof `[~]`

The first real guard/navigation consumer is deliberately small. TrenchBroom now exposes `vark_guard` and `vark_patrol_point` point entities. The authored guard references two patrol IDs plus one ordinary `door_id`; it is a reusable `CharacterBody3D` guard seed with a `NavigationAgent3D`, not a test-only fake actor. It knows no awareness, investigation, combat, dialogue, save policy, or final animation yet.

A development mission-package **Guard/Nav Lab** builds its structural floor/wall/offset doorway from the real FuncGodot `.map` source, then bakes a Godot `NavigationMesh` from the imported static collision geometry using the Godot 4.7 source-geometry → bake API. The authored A/B points lie on opposite sides of a wall while the only opening is deliberately offset, so a valid route must bend through imported architecture rather than moving directly between coordinates. When the route reaches the configured closed ordinary door, the guard stops, reads the existing `is_navigation_passage_open()` seam, uses that same `VarkOrdinaryDoor`, waits for its authoritative OPEN state, and continues. There is no guard-specific door or second navigation truth.

The focused reimport regression edits one authored patrol point in a disposable copy of the map, rebuilds the same mission world through `WorldSession`, rebakes navigation from the newly imported geometry, and proves the changed point, patrol, and ordinary-door use still work. This establishes the reimport/nav seam without claiming a production nav baking policy; Phase 5 hardening may cache/prebake or otherwise optimize the proven contract.

**Done when:** one guard is spawned through the Vark TrenchBroom/FuncGodot authoring path; two authored patrol markers drive a deterministic A↔B patrol; its NavigationAgent route is shaped by imported structural geometry rather than straight coordinate interpolation; the same ordinary door is opened only through the existing door-side navigation seam and physical door state; a representative map edit/reimport produces a fresh usable navigation mesh and updated patrol target; useful navigation/route diagnostics exist; and no awareness/search/combat/dialogue/final-animation framework is pulled forward.

**Automated:** required — the Navigation suite is wired into `tests/run_all_tests.gd`. It must prove FGD export of the real guard/patrol entities, Guard/Nav Lab launch through the production mission/session path, nonempty runtime navmesh baking from imported FuncGodot static geometry, a route that detours through the authored offset opening, a complete A↔B patrol, exactly one request to open the existing ordinary door, and a disposable authored patrol-point edit followed by fresh mission rebuild/nav bake/patrol/door traversal. Existing authoring/application/props/acoustics/movement suites remain authoritative.

**Manual:** pending — validator: **Windows x64 user/playtester**. Launch **Development Launch → Guard/Nav Lab**. The red primitive guard must repeatedly patrol between the two sides of the imported wall, visibly detour to the offset doorway instead of walking through the wall, stop for the initially closed ordinary door, open that same door, pass through it, and continue the return leg without clipping/stalling. Normal player movement/look should remain intact. This is a navigation/door authoring proof only; no suspicion, pursuit, combat, voiced dialogue, or finished guard presentation is expected.

## 3.8 Gameplay exposure micro-proof `[ ]`

Test one gameplay light/light-gem/debug readout against darkness, partial/full light, occlusion, light edge, and multiple contributions when added. Do not freeze the algorithm before visual perception and gameplay value agree intuitively.

## 3.9 Audible world-space speech `[ ]`

NPC words appear above the NPC and remain visible through visual cover when acoustics says the player should hear them. Marginal/distant speech may fade; inaudible speech is hidden.

Use a tiny speech-line ID/data boundary rather than hardcoding production dialogue directly into guard AI, without pulling the Phase 12 writer system forward.

## 3.10 Simple objective/exit `[ ]`

Add only enough objective state to give the five-minute route a beginning/end. Objective state uses semantic events/queries rather than private door/NPC internals.

## 3.11 Actor life-state and identity compatibility proof `[ ]`

Prove at minimum `conscious`, `unconscious`, and `dead` semantic states can coexist with awareness/navigation ownership, events, saveable state, and future movable-body behavior while preserving the same persistent actor identity/reference.

This is not final combat and does not replace the Phase 4 hostile-interaction proof.

## 3.12 Integrated five-minute stealth slice `[ ]`

Combine the actual micro-proof implementations into one ugly playable route. Door, props, light, sound, nav, NPC reaction, typed speech, objective, and exit must collide through the intended contracts.

**Phase gate:** the dangerous assumptions have isolated proofs, durable semantic mutation/event/lifecycle timing exposes one genuine stable gameplay boundary, actor identity survives life-state changes, and the same implementations work together without obvious architectural contradiction.

---

# Phase 4 — Coherent transactional save/restore and hostile-architecture compatibility

Goal: turn the semantic state contracts and lifecycle used by the slice into ordinary-gameplay quicksave/restore, then prove the same ownership model survives one crude hostile interaction before stealth APIs are hardened.

## 4.1 Save coordinator, detached snapshot capture, and transactional replacement `[ ]`

Use the Phase 1 world-session ownership and Phase 3 stable gameplay boundary rather than adding save-only clocks/startup paths.

### Capture

A save request may occur during any ordinary supported gameplay state. Bind that request to the `WorldSession` that received it and fulfill it only at that same session's next stable boundary after the controlled simulation/event consequence pass. If the source session stops before capture, cancel the pending request rather than retargeting it to a replacement.

Synchronously copy all save-owning semantic state **and the current input-owned player view pose** into detached value-owned snapshot data. Gameplay may continue after that copy. Encoding/writing afterward may read only the detached snapshot, and a captured snapshot may finish writing after its source world has been torn down.

Snapshot data must not retain live Nodes/Objects/RIDs/callbacks/signals/shared mutable runtime Resources or mutable containers shared with live gameplay. A regression must mutate the live world after capture and prove the captured snapshot does not change.

### Save-slot ordering

Use one serialized writer per logical slot or a monotonic save generation so an older request cannot commit after a newer request. F9-equivalent load reads the latest fully committed save, never a temporary/in-progress write.

### Restore topology

When loading from an active world:

- stop/freeze ordinary gameplay/input;
- validate save compatibility/data as far as possible before destructive transition;
- use the **simplest safe restore topology actually supported by Godot/project ownership**;
- apply/reconcile/validate while ordinary gameplay consequences remain disabled;
- on success, make the restored world authoritative then enable gameplay;
- on failure, tear down partial restore and enter one coherent application-owned recovery state.

Keeping a frozen old world while building an isolated candidate is allowed if simple. It is **not required** if it would force a general dual-world isolation framework; after prevalidation the old world may be torn down and the replacement restored as the sole mission world.

If worlds overlap in memory, their mutable resources/registries/events/timers/deferred work remain isolated and they never both act authoritative.

## 4.2 Semantic snapshots, resolved choices, long-running state, and object-existence order `[ ]`

Persist meaningful state, not arbitrary live node graphs.

At this stage cover player semantic state/view pose, door state, prop state, guard awareness/goal/life state, gameplay light state, objective/fact state, mission-run statistics present so far, and mission-script state if used.

If a random choice has already become gameplay truth at the captured boundary—for example an NPC's selected search point—persist the resolved choice/state needed to resume it rather than rerunning the choice during restore. Future choices not yet made may remain random after load.

Restore establishes what exists before what state it has:

```text
instantiate/register authored entities
→ apply authored removals/tombstones
→ recreate/register runtime-persistent entities if present
→ reserve restored runtime identities
→ apply semantic snapshots
→ restore player/MissionState/mission-script state
→ reconcile references/derived state
→ after_restore while consequences remain suppressed
→ validate
→ enable ordinary gameplay
```

Long-running saveable behavior stores explicit semantic stage/progress/remaining simulation time. Engine timers, `await` stacks, pending signal continuations, and animation callbacks are reconstructed from that state rather than serialized as truth.

## 4.3 Player transient/traversal restore policy `[ ]`

Classify representative player states into directly restorable semantic states, reconstructable transient states, or states normalized to a safe semantic equivalent.

Prove standing/moving, crouched, airborne, hanging, and mantle/corner/catch behavior according to the chosen policy.

Ordinary traversal/gameplay states must not gain routine save lockouts merely because direct runtime restoration is difficult.

## 4.4 Other transient-state save policy `[ ]`

Explicitly test/define saving during door movement, prop falling/thrown, guard investigating/alert, actor unconscious/dead/body, and any other transient state present in the slice.

Gameplay durations restore from world-simulation semantic progress, not elapsed wall-clock time during pause/load.

## 4.5 Snapshot coherence, restore suppression, operation ordering, and failure safety `[ ]`

Regression coverage proves:

- several systems changing around a save request restore to one completed stable semantic boundary;
- the captured player view pose matches the coherent player/world snapshot without adding physics-tick latency to normal mouse look;
- a pending save cannot migrate from its source world to a replacement during restart/load/exit;
- restore/`after_restore` does not duplicate one-shot events, objectives, loot/stat changes, alarms, dialogue, or rules;
- top-level load/restart/transition requests cannot race as simultaneous application operations;
- if old/restored worlds overlap, old gameplay is frozen and world-scoped mutable state cannot leak across them;
- if restore uses sole-world replacement instead, failure still leaves a coherent application-owned recovery state;
- deliberately invalid/incompatible restore fails closed;
- rapid repeated saves cannot let an older snapshot overwrite a newer request.

## 4.6 Save compatibility, content revision ownership, and durable write `[ ]`

Record separately:

```text
save_format_version
mission_id
mission_content_revision
```

`save_format_version` covers the global saved-state schema **and its semantic interpretation**. Bump/refuse it when globally saved state would still parse but would be interpreted incompatibly because Vark changed the meaning of actor, inventory, prop, combat, or other saved gameplay state.

`MissionDefinition` owns the content revision.

Bump `mission_content_revision` when old in-mission saves are no longer semantically safe, including incompatible persistent/semantic identity changes, changed save-state meaning tied to authored content, or structural/spatial changes that make previously saved player/actor/prop transforms or other world state invalid and are not covered by a defined safe reconciliation/normalization policy.

Do not bump merely because compatible art/geometry/text/tuning changed.

Provide clear unsupported-format/revision errors. Do not build migrations before a real migration is needed.

Durable writes use temporary/new files and only replace the previous valid save after successful completion/validation.

## 4.7 Crude hostile-interaction compatibility proof `[ ]`

Exercise one intentionally crude path through the same architecture:

```text
player attack intent
→ semantic hostile effect on guard
→ actor/life-state consequence
→ gameplay event + gameplay sound
→ relevant AI reaction
→ save
→ restore
→ coherent actor/awareness/state
```

Use the same gameplay-intent timing, actor identity, controlled mutation, event, gameplay-time, perception, world ownership, and persistence contracts. Do not pull final Phase 9 combat feel/tuning forward.

**Phase gate:** developer quicksave/restore captures detached coherent semantic state/view pose during ordinary/transient play, keeps pending captures bound to their source session, commits saves in correct request order, restores through a simple transactional topology without gameplay side effects, handles global/mission compatibility failures coherently, and proves crude active hostility survives the same architecture without replacement.

---

# Phase 5 — Harden the stealth core

Goal: turn spike implementations into reliable Vark systems only after their interactions, save semantics, and hostile compatibility are known.

## 5.1 Surface profiles and gameplay noise `[ ]`

Generalize the proven semantic gameplay-sound contract only as far as real use requires.

## 5.2 Acoustic model `[ ]`

Stabilize the propagation architecture chosen by the spike. Doors/openings affect transmission consistently. Add debug visualization/inspection.

## 5.3 Gameplay lighting/exposure `[ ]`

Stabilize the gameplay-light/exposure contract proven by the spike. Add light gem and useful debug readout.

## 5.4 NPC perception/awareness `[ ]`

Implement unaware, mild suspicion, investigation/search, confirmed alert/pursuit, and loss/recovery. Vision/hearing feed evidence without global omniscience.

Meaningful durations/decay use world simulation time. If search/patrol behavior uses randomness, once a choice becomes current gameplay truth it must survive save/restore as that resolved choice rather than being rerolled by restore.

## 5.5 NPC communication/local knowledge `[ ]`

Implement explicit information sharing/alarm behavior without automatic global player knowledge.

## 5.6 Door/nav/perception integration `[ ]`

The same ordinary door coherently affects traversal/navigation, sight, acoustics, NPC use, and save/load.

## 5.7 Early stress fixtures `[ ]`

Measure representative cost for multiple guards/vision, sounds/hearing, gameplay lights/exposure, and nav updates around doors. Record the reference environment.

**Phase gate:** the five-minute slice supports understandable darkness- and sound-based stealth with predictable guard behavior, stable save/reload semantics including resolved AI choices, and no architecture known to require replacement when active hostility expands later.

---

# Phase 6 — Complete the world interaction grammar

Goal: expand the minimal interaction contract without changing its fundamental language.

## 6.1 Interaction targeting/highlight completion `[ ]`

Harden center-view targeting, range/occlusion/state checks, highlight, and one primary world-interaction input. The Phase 3 door/prop keep using the same contract.

## 6.2 Door completion `[ ]`

Keys/locks/barred restrictions, authoring properties, obstruction behavior, NPC use, events, save state. Complete the mapper-facing external-model/variant authoring path so wooden, metal, ornate, window-like, or other compatible opening presentations can reuse the same ordinary door/opening gameplay archetype. Openable windows are variants of this system, not a separate gameplay subsystem.

## 6.3 Loot, keys, minimal possession, and run-stat ownership `[ ]`

Collected loot becomes abstract recorded value/count.

Introduce only minimal semantic possession needed now, such as owns key/content item X, loot possession/value, and small abstract mission-item ownership when genuinely needed.

Doors/mission logic query semantic possession rather than depending on future inventory UI/selection.

When the first mission statistic becomes real (loot is likely first), introduce a tiny semantic `MissionRunState`/statistics owner for run counters rather than letting each subsystem keep duplicated counters or making the future results UI scrape private state. Later kills/knockouts/alerts/time extend the same owner as they become real.

Because collecting authored loot removes an authored world instance, implement the minimal removed-authored tombstone representation and prove collected loot remains absent after restore without replaying collection/stat consequences.

## 6.4 Containers `[ ]`

Physical opening/exposed contents where appropriate. Ordinary cabinets, chests, drawers, and furniture-like containers use reusable external model assets/variants where appropriate rather than requiring bespoke brush geometry or gameplay code per visual model.

## 6.5 Switches and switchable/extinguishable lights `[ ]`

Integrate with gameplay light state, sound/events, and saves.

## 6.6 Physical prop completion `[ ]`

Expand support relationships, stacking/climbing, carried-Junk HUD presentation, view-derived gentle release/throw, impacts/noise, obstruction, save state, and reusable external-model presentation/variant authoring only as real content needs them. Furniture/prop visual replacement must not require rewriting the shared physical-prop gameplay rules.

Preserve the Phase 3 carried-Junk hand/world-action restrictions through central interaction/input ownership.

## 6.7 Configured breakables/effects `[ ]`

Only explicitly authored damageable/breakable objects respond. No universal destruction/fire simulation.

**Phase gate:** systemic world interaction works without disconnected controls or unrealistic always-active rigid bodies; key/loot possession works without a temporary inventory architecture; mission-run counters have one owner; and permanently removed authored content restores correctly.

---

# Phase 7 — Mission logic and provisional authoring API

Goal: promote proven internal semantic contracts into a small mission logic system and a provisional script surface.

## 7.1 Author-facing semantic event bus `[ ]`

Promote useful gameplay-event vocabulary while preserving proven world ownership, FIFO/re-entrant append, controlled semantic mutation, stable-boundary, and lifecycle semantics.

Do not expose private subsystem signals. Mission event handlers participating in the current semantic drain are synchronous; long-running reactions become explicit semantic state advanced on future gameplay ticks.

Keep the development runaway-event/cascade guard and provide a useful event trace.

## 7.2 Typed mission facts `[ ]`

Define fact declarations with key, type, default, and scope. Reject invalid/unknown assignments where practical.

Mission facts represent genuinely mission-defined variables. Do not mirror door open state, actor life/awareness, possession, objective state, or other system-owned truth into generic facts unless the mission requires a separate derived/latched meaning.

Before Phase 12 introduces the real `CampaignState`, fact scopes remain mission/runtime scopes only; do **not** use `MissionFacts` as a temporary owner for campaign-persistent truth that would later need migration.

## 7.3 Objective system `[ ]`

Active/completed/failed, optional/dynamic objective support.

## 7.4 Small data rule system `[ ]`

Support event → conditions → actions for common declarative behavior. No general-purpose language features.

Delayed/long-running rules are explicit semantic stages/timing state rather than hidden suspended callbacks/coroutines.

## 7.5 Provisional VarkMissionScript API `[ ]`

Provide narrow query/command APIs needed by the real mission. Avoid mutable global campaign/game-flow internals and arbitrary mutable Node access.

Query APIs may read supported semantic state. Mutation commands preserve the controlled gameplay boundary: when requested from `_process()`, an arbitrary signal, async continuation, or another out-of-pass context, queue/record the semantic command for the controlled gameplay pass instead of mutating private gameplay Nodes immediately. Prefer stable semantic IDs and detached typed values in the public surface.

Document this as provisional/supportable. Phase 11 may stabilize only the world/gameplay mission surface proven by Phase 8–10; later campaign/narrative/application-flow surfaces remain provisional until exercised.

## 7.6 Deterministic rule ordering and save state `[ ]`

Define rule ordering relative to the event queue/stable boundary, repeat/one-shot behavior, and restore semantics.

## 7.7 Mission logic debugger `[ ]`

Provide rule/event/fact inspection sufficient to answer why a rule did/didn't fire and diagnose event cascades.

**Phase gate:** ordinary mission reactions work without core edits, procedural behavior can live in GDScript without private reach-through or bypassing controlled semantic mutation, long-running behavior is saveable semantic state rather than runtime continuation state, mission facts have not become premature campaign storage, and the API is useful but explicitly provisional.

---

# Phase 8 — First proper 10–15 minute stealth mission

Goal: test authoring workflow/system architecture with an actual small mission.

The mission uses real TrenchBroom geometry/entities, multiple routes where practical, reusable external-model-backed doors/openings and furniture/props, doors/keys, darkness/light, surfaces, throwable props, guard patrol/investigation, typed audible speech, loot/container interaction, objectives, one declarative rule, one mission-specific GDScript example where useful, quicksave/load, restart, and minimal results/run-stat inspection.

Full polished results UI remains Phase 13; Phase 8 must consume the real semantic `MissionRunState` rather than create a temporary scraper/counter system.

## 8.1 Mapper workflow proof `[ ]`

A mapper should not need hand-edits in generated output. The ordinary workflow includes placing/configuring model-backed gameplay entities and selecting compatible reusable model variants without editing core gameplay scenes/code.

## 8.2 Reimport proof `[ ]`

Normal geometry/entity iteration preserves persistent IDs/saveability assumptions.

## 8.3 Rule proof `[ ]`

Common logic uses the small data rule grammar.

## 8.4 GDScript extension proof `[ ]`

One unusual behavior proves the provisional mission API without expanding the data grammar into a language.

Until runtime-created persistence is proven, mission scripts may manipulate authored persistent objects through supported commands and create genuinely transient effects/objects. If a script-created gameplay object must survive save/load, pull the minimum runtime-persistence proof forward.

Do not rely on suspended `await`/timer continuation as saveable mission behavior; save-relevant progress is explicit semantic state. Prove an out-of-pass script command is queued/applied through the supported semantic boundary rather than mutating gameplay immediately.

## 8.5 Save/load proof `[ ]`

Representative save points restore from one detached stable-boundary snapshot.

Exercise real `mission_content_revision` refusal by changing authoritative mission metadata. Include at least one incompatibility that is semantically/spatially meaningful rather than only faking a serialized number.

Also exercise an intentionally incompatible **global saved-state semantic interpretation** through `save_format_version`, not only a byte-layout failure.

## 8.6 Authoring/debug feedback `[ ]`

Fix tooling/diagnostics gaps exposed by building the mission.

## 8.7 Cold-author review `[ ]`

Have a Godot/TrenchBroom-capable developer unfamiliar with the relevant Vark internals make a small edit/addition through the intended workflow.

**Phase gate:** a real small stealth mission exposes genuine production problems; ordinary content is authorable through intended tools; run statistics/results draw from semantic ownership rather than temporary scraping; unsupported global/mission save compatibility fails safely; runtime-persistent scripted objects cannot bypass persistence; supported script mutation cannot bypass the semantic boundary; and the workflow makes sense to a second developer.

---

# Phase 9 — Bodies and combat prototype

Goal: establish the four-playstyle foundation while combat remains TARGET until play proves it.

## 9.1 Bodies and life-state completion `[ ]`

Complete conscious/unconscious/dead behavior, carry/hide, body discovery hooks, and save state.

The body remains the same persistent actor identity. Body-carry movement restrictions are explicit gameplay modifiers, not changes to unencumbered controller behavior.

## 9.2 Stealth knockout prototype `[ ]`

Held/released fist behavior in valid stealth context.

Losing combat-input ownership while a hold/release takedown is armed cancels the gesture; resume requires a fresh initiating press.

## 9.3 Stealth kill prototype `[ ]`

Held/released knife behavior in valid stealth context with the same cancellation rule.

## 9.4 Block/parry/stagger prototype `[ ]`

Implement the TARGET grammar only far enough to evaluate it. Combat uses the proven gameplay-intent tick semantics for pressed/held/released/block intent rather than a second polling path.

Stagger/attack timing uses world simulation time.

## 9.5 Lethal/nonlethal direct combat and vitality ownership `[ ]`

Implement knife/blunt follow-up behavior and guard attack loop using the **smallest real semantic vitality/damage ownership needed by combat**, including player health/damage and any actor damage state that must survive save/load.

Do not create a temporary Phase 9 health/damage path that Phase 10 effects must replace. Phase 10 may generalize healing/gas/water/fire/explosion/tool effects around this proven vitality/damage boundary, but ordinary combat damage remains the same semantic ownership.

## 9.6 Required combat validation `[ ]`

Playtest one guard, two guards, corridor, open room, lethal assault, nonlethal assault, stealth-failure transition, and retreat/break contact. Revise the TARGET grammar if needed. Combat becomes LOCKED only after user acceptance.

## 9.7 Combat perception/noise/body integration `[ ]`

Combat creates appropriate gameplay noise, awareness, bodies, run statistics, semantic events, vitality/damage state, and save state through the existing contracts.

**Phase gate:** all four broad styles are genuinely possible enough to evaluate without replacing gameplay-input timing, controlled semantic mutation, actor identity, event timing, gameplay time, vitality/damage ownership, or persistence ownership.

---

# Phase 10 — Inventory, effects, and complete gameplay vertical slice

Goal: prove Vark's main gameplay grammar together before broad platform generalization.

## 10.1 Inventory framework `[ ]`

Build selectable/usable inventory on top of Phase 6 possession rather than replacing it.

Add selection/use for real consumables, thrown tools, projectiles, deployables, area effects, and mission items.

When the first runtime-created object must survive save/load, implement only the minimum runtime-persistence representation:

- runtime persistent identity;
- stable semantic type/spawn provenance sufficient to recreate it;
- semantic state.

The saved type/provenance identifier must not be a fragile class/scene filename accident. Unknown saved types fail clearly. Restored runtime identities are reserved so later runtime-created objects cannot reuse/collide with them; a UUID-like strategy is sufficient and no global spawn framework is required.

## 10.2 Reusable effect grammar `[ ]`

Extend the **already-real Phase 9 vitality/damage ownership** with damage/heal/gas/water/fire/explosion-like effects only to the degree real items/content need them. Do not replace ordinary combat health/damage semantics with a second effect-owned truth.

## 10.3 Scripted NPC routines `[ ]`

Conversations, sitting/sleeping/operating, routine interruptions/resumption where required by the slice. Save-relevant routine progress and already-resolved choices are semantic state, not a coroutine stack or rerolled restore-time decision.

## 10.4 Complete representative slice `[ ]`

One segment combines stealth, combat, bodies, interaction, mission logic, save/load, inventory, and any real runtime-persistent objects.

Exercise the provisional mission API against combat/body/inventory/effect needs and correct bad boundaries now.

If the slice contains runtime-created transient gameplay such as a projectile in flight, thrown tool, arming deployable, timed grenade, or active area effect, include at least one save during that active transient and prove its explicit direct-restore/reconstruct/normalize policy. Do not let consumed inventory/ammo restore into a world where the corresponding active effect silently vanished or duplicated.

After restoring persistent runtime-created objects, create another runtime object and prove its identity cannot collide with restored identities.

## 10.5 Performance checks `[ ]`

Measure perception, acoustics, lighting, rule traffic, nav, **synchronous detached snapshot-capture cost**, encoded size/write time separately, and runtime-persistent overhead present. Record reference environment.

Do not weaken snapshot coherence to remove a capture hitch; optimize state/copying if measurement proves capture expensive.

**Phase gate:** Vark's gameplay identity exists as one integrated vertical slice; every persistence case and active runtime transient present is proven; runtime identities remain unique across restore plus later spawn; possession extends naturally into inventory; Phase 10 effects extend rather than replace Phase 9 vitality/damage ownership; and the provisional world/gameplay mission API has survived the complete gameplay grammar.

---

# Phase 11 — Generalize proven world/gameplay systems for production

Goal: extract stable **world/gameplay mission APIs** from patterns the complete gameplay slice actually used.

## 11.1 Stabilize world/gameplay production APIs `[ ]`

Promote only interfaces proven by Phase 8 and Phase 9–10 world/gameplay integrations from provisional/supportable status.

Campaign/narrative/application-flow extension surfaces are **not** declared production-stable here; Phases 12–13 must exercise them first.

Remove/correct accidental abstractions rather than preserving bad Phase 7 shapes for prototype compatibility.

## 11.2 Vark TrenchBroom entity library `[ ]`

Promote ordinary entities/fields proven in real mission authoring, including the stable model/variant-facing fields needed for reusable model-backed doors/openings, containers/furniture, props, and other ordinary modeled world objects. Do not expose fragile imported mesh hierarchy as gameplay API.

## 11.3 Validation suite `[ ]`

Add duplicate IDs, missing references, impossible configuration, detectable revision-policy errors, unsupported runtime-persistence type IDs when applicable, and real production errors discovered during mission building.

## 11.4 Debug tooling `[ ]`

Perception, acoustics, nav, entity lookup, mission rules, objectives, semantic state ownership, and save-state inspection.

## 11.5 Mission template `[ ]`

Create a template only after the first proper mission shows what a real mission needs.

## 11.6 Second cold-author test `[ ]`

Have another developer create/substantially modify a small mission using the generalized world/gameplay APIs/template.

**Phase gate:** reusable world/gameplay systems represent proven Vark patterns, not hypothetical engine features; their production API has survived the complete gameplay slice; and a non-author can use the workflow. Campaign/narrative/application extension stability remains to be proven.

---

# Phase 12 — Campaign and narrative layer

Goal: support multi-mission consequences and writer-facing production.

## 12.1 CampaignState `[ ]`

Introduce the authoritative owner for campaign-persistent facts, separate from mission-local state. Campaign state must not become a mutable global catch-all for mission runtime state, and Phase 7 mission facts must not be retroactively treated as its storage layer.

## 12.2 Cross-mission variation `[ ]`

Later mission setup may alter NPCs, routes, objectives, security, resources, dialogue, and other authored starting conditions from campaign facts.

## 12.3 Writer workflow `[ ]`

Stable text IDs/data for world-space NPC dialogue, briefings, subtitles, and narrative content.

## 12.4 First-person sequences `[ ]`

Input ownership, camera control, actor actions/dialogue, exceptional save restrictions where appropriate, safe return to gameplay.

Save-relevant sequence progress is explicit semantic state if arbitrary restoration is supported; suspended animation/coroutine state is not durable truth.

## 12.5 Narrative save/campaign integration and completion transaction `[ ]`

An in-mission save reconstructs the same campaign-derived mission variant that existed when captured, not whatever campaign state happens to be current at load time.

Choose the smallest explicit representation proven by content: relevant campaign snapshot/input or a resolved mission-start configuration/revision.

Mission completion advances campaign state **exactly once**. Applying mission results/consequences and committing the new durable campaign snapshot is one application-owned completion transaction; retry/crash/re-entry must not apply the same completion consequences twice.

An in-mission save is tied to the campaign/mission-start instance it came from. Once campaign progression has durably advanced past that mission instance, an old in-mission save must not silently resume against the advanced campaign state. The implementation may invalidate/delete that quicksave on successful completion or refuse it using the saved campaign/run baseline identity—choose the smallest proven policy when this flow exists.

Exercise and stabilize the campaign/narrative extension API only after these real flows prove it.

**Phase gate:** two missions demonstrate a meaningful prior-choice consequence; in-mission save recreates the same campaign-derived starting variant; mission completion advances campaign state exactly once and leaves no ambiguous stale-save/advanced-campaign combination; and campaign/narrative extension boundaries are proven rather than guessed.

---

# Phase 13 — Player-facing product flow and application API completion

Goal: convert developer functionality into complete player-facing flow and finish application-level extension boundaries.

## 13.1 Finalized quicksave/quickload UX `[ ]`

F5/F9 work during ordinary gameplay with understandable feedback/error handling while retaining source-session-bound stable capture, latest-committed-slot semantics, and transactional replacement.

Define visible behavior for rapid/repeated save/load requests, a save request cancelled by world transition before capture, save-in-progress cases, and attempts to load an in-mission save whose campaign/run baseline is no longer valid after durable mission completion. Application operations must not race.

## 13.2 Main menu / Continue / New Game `[ ]`

Connect real persistence/campaign flow. `Continue` chooses a coherent durable state rather than ambiguously mixing an advanced campaign snapshot with a stale in-mission quicksave.

## 13.3 Pause/objectives/map/inventory/settings `[ ]`

Complete presentation around Phase 1 input/simulation/gameplay-time ownership rather than inventing a second pause policy.

## 13.4 Mission results/statistics `[ ]`

Build final presentation over the semantic `MissionRunState`/statistics owner already exercised by gameplay: loot, kills, knockouts, detections/alerts, objectives, time, and mission-specific stats.

## 13.5 Failure/death/recovery flow `[ ]`

Return to valid load/recovery state without checkpoint-only design.

**Phase gate:** complete intended player flow is usable without developer shortcuts, campaign/narrative/application-flow extension boundaries and exactly-once progression have been exercised, and the whole production extension surface may now be treated as stable where proven.

---

# Phase 14 — Production scaling and replacement architecture

Goal: prove systems at representative content scale and allow art/audio replacement without gameplay rewrites.

## 14.1 Art replacement paths `[ ]`

Models/textures/animations/HUD/menu assets can be replaced without changing gameplay rules. This phase hardens production replacement at scale; it is **not** the first proof of model-backed world objects. Doors/openable windows, containers/furniture, and representative props must already have used replaceable external 3D model presentation through their earlier gameplay/authoring proofs.

## 14.2 Audio replacement paths `[ ]`

Final audio can replace placeholders without altering semantic gameplay noise.

## 14.3 Representative-scale production mission `[ ]`

Build a much larger mission to stress real content volume.

## 14.4 Performance budgets and optimization `[ ]`

Profile on a recorded supported reference environment:

- NPC vision/hearing;
- acoustic graph/portals;
- gameplay exposure;
- nav;
- mission events/rules;
- synchronous save snapshot capture;
- encoded save size/durable-write time;
- prop support checks.

Optimize proven bottlenecks without weakening semantic correctness.

## 14.5 Build/content validation `[ ]`

Production validation catches common authoring errors before shipping.

**Phase gate:** architecture holds under representative mission complexity/content volume.

---

# Phase 15 — Final external handoff

Goal: verify the platform is usable by someone who did not build its internals.

## 15.1 Production template/docs `[ ]`

Document only workflows/extension points that survived production use.

## 15.2 External mapper/scripter test `[ ]`

A developer familiar with Godot/TrenchBroom but not Vark internals builds a small mission.

## 15.3 Handoff gap fixes `[ ]`

Fix unclear APIs, missing validation, undocumented ownership, or tooling problems discovered by the external creator.

**Phase gate:** a new creator can build ordinary Vark content without modifying core gameplay and can add special scripted content through supported APIs.

---

# Required early integration proofs

Detailed fixture requirements live in `TESTING.md`. These proofs are architecture gates, not optional polish.

## World-session lifetime/replacement

Prove non-playing build, application-controlled entry to play, coherent stop/pause, teardown, fresh replacement, stale-work rejection, and no shared mutable runtime Resource/autoload state leaking between sessions.

Phase 1 proves stop/teardown/replacement ownership. Phase 4 proves the actual restore topology once real save/load exists; a simultaneous candidate world is not a Phase 1 requirement.

## Gameplay-input frame/view lifetime

Protect accepted locomotion through the gameplay-input boundary, one-tick gameplay edge lifetime, cancellation of incomplete edge-dependent gestures on domain loss, stale-edge clearing, separation from look/UI cadence, and coherent sampling/capture of the input-owned player view pose.

## Gameplay time

Prove ordinary gameplay durations stop with world simulation/pause and do not advance from wall-clock time spent paused/loading.

## Persistent identity editing

Exercise create/move/reorder/duplicate/delete/reimport plus idempotent source writeback/repair. Runtime validation must reject missing/duplicate authored persistent IDs and duplicate non-empty semantic `content_id` values before a world session becomes ready. The current-session registry must resolve validated persistent/content IDs, report blank/missing lookup, and be cleared across teardown/replacement. The first Vark point roles must use that same identity/addressing path rather than a separate authoring schema.

## Gameplay-event/stable boundary

Prove FIFO for emitted order, nested append, lifecycle suppression, stale-world rejection, synchronous event drain, runaway-cascade detection, controlled semantic mutation, supported script-command routing, and one true stable boundary.

## Door / acoustic / lighting / prop / nav integration

Keep small representative fixtures and progressively use the same ordinary gameplay objects rather than subsystem-specific fakes.

Prove the external-model presentation seam early on those real objects: the ordinary door/opening and representative prop use replaceable model assets while gameplay identity/state/collision/integration remain owned by their Vark archetypes. An openable window reuses the ordinary door/opening path rather than creating a parallel subsystem.

The prop fixture includes the locked one-slot carried-Junk HUD/no-world-collision contract, F throw / R gentle release, view-derived placement, central hand/world-action suppression, and always-upright dynamic/rest behavior with no semantic settling phase.

## Save snapshot/restore transaction

Prove source-session-bound detached snapshot capture at one stable boundary, deep ownership/no live-reference mutation, coherent view-pose capture, latest-save commit ordering, transactional restore with suppressed reconciliation hooks, resolved-choice restoration, failure safety for the chosen topology, explicit long-running semantic state, global/mission compatibility refusal, and no duplicate consequences.

## Removed-authored persistence

When permanent authored removal exists, prove tombstone state prevents reappearance/duplicate consequences.

## Runtime-created persistence

When first needed, prove runtime identity, stable semantic type/provenance, recreation before state application, restored-ID reservation/non-collision, duplicate prevention, and world-lifetime ownership. If valid saves can occur while a runtime transient is active, prove at least one real direct-restore/reconstruct/normalize policy.

## Actor identity / crude hostility

Prove life-state/body changes retain actor identity, then prove one crude active-hostility path survives the same gameplay-input/event/perception/save contracts. Phase 9 then turns crude damage into real vitality/damage ownership before Phase 10 generalizes effects.

## Campaign completion

When campaign progression exists, prove mission completion applies consequences exactly once, commits a coherent durable campaign state, and does not leave an old in-mission save silently loadable against an already-advanced campaign baseline.

---

# Testing requirements added as systems arrive

Automate deterministic objective behavior where valuable, including:

- world-session stop/teardown/replacement freshness and stale-work rejection;
- source-session binding/cancellation for pending save capture;
- mutable Resource/autoload isolation across world sessions;
- pause/gameplay-time ownership;
- gameplay-intent one-tick edge lifetime, domain-loss gesture cancellation, and no look/input-feel drift;
- center-view interaction range/first-hit occlusion/current-state eligibility, one-frame primary-interaction intent, highlight clearing, and central ordinary-interaction availability;
- coherent stable-boundary capture of event-driven player view pose;
- controlled semantic mutation and stable-boundary semantics, including mission-script commands requested out of pass;
- event FIFO/re-entrant/lifecycle behavior and runaway-cascade failure diagnostics;
- resolved random-choice persistence when choices have become gameplay truth;
- persistent-ID uniqueness/editing/reimport/repair/writeback/idempotence and fail-closed runtime validation;
- current-session persistent/content-ID registry ownership, lookup, missing diagnostics, and teardown/replacement isolation;
- semantic-ID uniqueness plus current player-start reference, required-exit, and required-player validation before `READY`;
- mission restart freshness;
- detached save snapshot capture that cannot mutate after live state changes;
- save-slot request/commit ordering and latest-committed load behavior;
- save round trips and restore consequence suppression including `after_restore`;
- restore failure safety for the chosen topology;
- global save-format **semantic** compatibility refusal plus mission-content-revision refusal including incompatible spatial edits;
- long-running transient restore from explicit semantic timing/progress;
- actor identity across conscious/unconscious/dead/body;
- Phase 9 vitality/damage persistence before Phase 10 effect generalization;
- removed-authored tombstones;
- runtime-created recreation/stable type IDs/restored-ID non-collision and active transient policy when such content exists;
- mission-fact ownership/typing/defaults without generic state mirroring or premature campaign storage;
- deterministic rule ordering/one-shot behavior;
- defined Thief-style prop invariants;
- door persistence;
- acoustic/perception invariants where deterministic;
- crude hostile compatibility;
- exactly-once campaign completion and stale in-mission save handling once campaign progression exists.

Subjective feel remains user playtest territory.

---

# Immediate recommended sequence

1. Complete the current 3.6 acoustic propagation micro-proof through exact-head automated validation plus focused Windows playtest/TrenchBroom mapper acceptance before moving to 3.7.
2. Phase 3 interaction/event/sound contracts + controlled semantic mutation + true stable gameplay boundary.
3. Phase 3 door/prop/acoustic/nav/light proofs and integrated stealth slice + actor identity proof.
4. Phase 4 source-session-bound detached snapshot capture + coherent view pose + save-slot ordering + resolved-choice restore + simplest proven transactional restore topology + global/mission compatibility policy.
5. Phase 4 crude hostile compatibility.
6. Phase 5 harden stealth, preserving resolved AI choices through save/load.
7. Phase 6 minimal possession + semantic `MissionRunState` + removed-authored persistence.
8. Phase 7–8 mission logic/provisional script API + first proper mission; mission-local fact scopes only; supported commands preserve controlled mutation; explicit semantic long-running state; pull runtime persistence forward only if real content needs it.
9. early cold-author review.
10. Phase 9 establish real vitality/damage ownership while prototyping combat.
11. Phase 10 inventory/effects extend that vitality boundary + stable runtime IDs + active-runtime-transient save proof + complete vertical slice.
12. Phase 11 stabilize **world/gameplay** production APIs only.
13. Phase 12 prove/stabilize campaign/narrative boundaries + exactly-once durable mission completion.
14. Phase 13 complete player flow/application boundaries and final extension-surface stabilization, including coherent Continue/stale-save behavior.
15. production scaling/handoff.

The most important sequencing rules are:

> **Do not build the reusable immersive-sim platform first and hope Vark fits it later. Build Vark in playable slices and let the platform emerge from proven needs.**

> **Durable gameplay truth is explicit semantic state. Engine callbacks, timers, Resources, coroutines, and scene topology are implementation machinery, not alternate sources of truth. Input-owned view pose is the narrow accepted exception in cadence, not an alternate path for world consequences.**

> **Do not stabilize an abstraction after proving it against only one side of a future cross-cutting requirement. Prove the boundary with the systems that actually depend on it, then freeze only that proven surface.**
