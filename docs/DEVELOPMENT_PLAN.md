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

When `Manual:` requires a specific kind of validator, name that role rather than treating every manual criterion as interchangeable. User/playtester, Windows operator, mapper, writer, cold author, and external developer are different acceptance roles. In particular, the implementing agent cannot self-certify the independent-human purpose of 8.8, 11.6, or 15.2; it prepares the workflow and the reported external result closes the criterion.

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

## 3.7 Primitive guard/nav micro-proof `[x]`

The first real guard/navigation consumer is deliberately small. TrenchBroom now exposes `vark_guard` and `vark_patrol_point` point entities. The authored guard references two patrol IDs plus one ordinary `door_id`; it is a reusable `CharacterBody3D` guard seed with a `NavigationAgent3D`, not a test-only fake actor. It knows no awareness, investigation, combat, dialogue, save policy, or final animation yet.

A development mission-package **Guard/Nav Lab** builds its structural floor/wall/offset doorway from the real FuncGodot `.map` source, then bakes a Godot `NavigationMesh` from the imported static collision geometry using the Godot 4.7 source-geometry → bake API. The authored A/B points lie on opposite sides of a wall while the only opening is deliberately offset, so a valid route must bend through imported architecture rather than moving directly between coordinates. The 1.30 m ordinary visual leaf closes exactly between the authored jambs with no side voids. The shared ordinary-door collision contract remains full-width; only this exact-fit development fixture duplicates that leaf collision and leaves 4 cm of physical sweep clearance at each vertical edge so mapper-fit tolerance does not become a global door change. The guard's authored 2.0 m door-use distance is only a relevance cap for its configured ordinary door, not an automatic OPEN trigger. While APPROACHING, the safe sweep boundary only limits how close the guard may get before stopping; it does not define whether the door is blocking. The guard samples its real collision capsule along the near-future NavigationAgent path against the ordinary door's **current collider transform**. Only when that route is physically blocked **and** the next step reaches the safe stop boundary does it enter WAITING_OPEN and send the existing idempotent `request_open()` intent. WAITING_OPEN repeats the same physical route query every physics frame and releases immediately once the current leaf angle leaves enough room, even while the semantic door phase is still OPENING or CLOSING. Temporary physical obstruction may latch an OPEN request, but while the passage is still required the guard retries that OPEN intent; once the blocker leaves and the door opens, patrol resumes. Door traversal is explicit and local to this primitive consumer: **APPROACHING → WAITING_OPEN → CROSSING → CLEAR**. The ordinary door owns the physical passage-occupancy query. While APPROACHING, a non-open door may continue closing in front of the guard without an immediate counter-request as long as the current leaf does not intersect its route. Once WAITING_OPEN has started, the same idempotent OPEN intent is retried only while that physical route remains blocked; a partially open leaf that becomes passable releases movement before terminal OPEN. Once the guard's real body occupies the passage, CROSSING suppresses OPEN counter-requests **until real physical contact**. If the player-commanded close reaches the guard and the ordinary sweep latches specifically on that guard body, the guard reuses the same logical door interaction to request OPEN, keeps physically trying to cross, and clears the doorway as soon as the current gap fits without waiting for terminal OPEN. After the guard exits, CLEAR prevents reopening a door that merely closes behind it. Player `interact()` remains the ordinary toggle. There is no guard-specific door or second navigation truth.

The focused reimport regression edits one authored patrol point in a disposable copy of the map, rebuilds the same mission world through `WorldSession`, rebakes navigation from the newly imported geometry, and proves the changed point, patrol, and ordinary-door use still work. This establishes the reimport/nav seam without claiming a production nav baking policy; Phase 5 hardening may cache/prebake or otherwise optimize the proven contract.

**Done when:** one guard is spawned through the Vark TrenchBroom/FuncGodot authoring path; two authored patrol markers drive a deterministic A↔B patrol; its NavigationAgent route is shaped by imported structural geometry rather than straight coordinate interpolation; the same ordinary door is opened only through the existing door-side navigation seam and physical door state; a temporary blocker cannot permanently strand the guard once the opening becomes clear; a player may close a door in front of an approaching guard without an immediate AI reopen; the guard requests OPEN only when the current leaf physically intersects its near-future route at the safe stop boundary, and resumes as soon as the leaf becomes physically passable without waiting for terminal OPEN; player closing against a guard already in the frame reaches physical contact before any counter-request; that confirmed guard-caused blockage then reverses the same ordinary door toward OPEN, and the guard continues as soon as the physical gap fits rather than remaining pinned or waiting for terminal OPEN; the closed 1.30 m leaf fits the authored doorway without left/right voids; a representative map edit/reimport produces a fresh usable navigation mesh and updated patrol target; useful navigation/route diagnostics exist; and no awareness/search/combat/dialogue/final-animation framework is pulled forward.

**Automated:** passed — the Navigation suite is wired into `tests/run_all_tests.gd` and proves FGD export of the real guard/patrol entities and the 2.0 m authored door relevance cap, exact 1.30 m Guard/Nav Lab visual jamb spacing around the ordinary leaf, fixture-local physical sweep clearance without changing the shared ordinary-door collision leaf, launch through the production mission/session path, nonempty runtime navmesh baking from imported FuncGodot static geometry, a route that detours through the authored offset opening, a guard request/wait triggered only when the current leaf physically blocks the near-future guard route at the safe stop boundary, a complete A↔B patrol, one logical ordinary-door use, a player-close window in front of an approaching guard with no immediate AI reopen, release from WAITING_OPEN before terminal OPEN once the physical route clears, a deliberately 85%-open CLOSING leaf that remains passable without any AI door use, player-commanded closing against a CROSSING guard advancing to real guard contact before a contact-triggered OPEN request, followed by guard clearance while the door is still OPENING, real-player obstruction followed by guard OPEN retry/recovery, and a disposable authored patrol-point edit followed by fresh mission rebuild/nav bake/patrol/door traversal. The Application door regression separately proves the shared full-width leaf plus `request_open()` idempotence across blocked opening recovery without toggle reversal or duplicate use sound. Exact accepted head `fcf3f9b9d509cd617840fbdd7ac5a32945a8a741` passed Godot 4.7.2 GitHub Actions Test run #230 with `ALL NAVIGATION TESTS PASSED` and `ALL TEST SUITES PASSED`.

**Manual:** passed — validator: **Windows x64 user/playtester**. The user confirmed the final Guard/Nav Lab traversal behavior: a partly closed but physically passable door is simply traversed; a genuinely blocking door is requested OPEN and movement resumes before terminal OPEN once the gap fits; a player close against a CROSSING guard reaches real contact before the guard requests OPEN, reverses cleanly, and lets the guard continue without twitching, clipping, or a permanent stall. Earlier patrol, detour, exact-fit doorway, guard opening, real-player opening obstruction/retry, recovery, and normal movement/look checks were also reported working.

## 3.8 Gameplay exposure micro-proof `[x]`

A development-only **Exposure Lab** launches through the real application/session/player path and adds the smallest inspectable gameplay-exposure owner. Two actual shadow-casting `OmniLight3D` nodes also carry explicit provisional gameplay strengths. The world-owned exposure owner derives three vertical sample points from the real player's `CapsuleShape3D`, ray-tests each sample against world collision for occlusion, applies a simple distance falloff using each light's real `omni_range`, averages each light across the body samples, adds multiple-light contributions, then clamps the current exposure to 0–1.

This is deliberately a **prototype measurement**, not the frozen stealth-visibility algorithm. Rendered light and gameplay exposure share the same actual light transforms/ranges and should feel related, but gameplay strength remains explicit so decorative rendering choices do not silently become stealth truth. A development light-gem/debug HUD shows the current scalar plus per-light contributions. The lab provides labeled **DARK**, **LIGHT EDGE**, **PARTIAL**, **FULL**, **TWO LIGHTS**, and **OCCLUDED** positions around real geometry so tuning can be judged against what the player actually sees before any guard perception system consumes this value.

**Done when:** the same real player produces a near-zero dark reading, a sensible low edge reading, a stronger partial reading, a strong full-light reading, near-zero exposure behind representative opaque geometry, and additive exposure where two gameplay lights overlap; the debug light gem updates continuously from the one world-owned exposure value; headless tests can diagnose source/sample contributions; the player-facing visual/readout relationship feels intuitive in the development lab; and no observer/FOV/alertness/movement-visibility framework or final HUD art is pulled forward.

**Automated:** passed — the Visibility suite is wired into `tests/run_all_tests.gd`. It launches Exposure Lab through the production application/session path, verifies the sources are real shadow-casting `OmniLight3D` nodes, exercises the real player capsule at all six labeled fixture positions, asserts deterministic dark < edge < partial < full relationships, proves opaque world geometry occludes all representative body samples, proves two lights contribute additively before 0–1 clamping, and verifies the stepped development light-gem/debug HUD is driven by the live world-owned exposure summary. Exact accepted head `c50bed2fe1fda9c08e22ab7e4778fdb9f5801f00` passed Godot 4.7.2 GitHub Actions Test run #232 with `ALL VISIBILITY TESTS PASSED` and `ALL TEST SUITES PASSED`. The exact formula remains a replaceable gameplay-exposure implementation rather than a promise that rendered brightness and stealth truth are mathematically identical.

**Manual:** passed — validator: **Windows x64 user/playtester**. The user walked the **DARK / LIGHT EDGE / PARTIAL / FULL / OCCLUDED / TWO LIGHTS** positions and reported that the development light-gem/readout tracked the visible lighting intuitively enough for this micro-proof. This accepts the current Phase 3 exposure seam without freezing the exact falloff/sampling formula as final production tuning.

## 3.9 Audible world-space speech `[x]`

A development-only **Speech Lab** reuses the accepted Phase 3.6 acoustic authority instead of inventing subtitle distance/LOS rules. The placeholder NPC speaker owns a tiny `VarkSpeechLine` Resource with stable `line_id`, typed world-space text, semantic `sound_kind`, gameplay sound strength, and a short presentation lifetime. Speaking a line first hides any previous text, then queues **one** existing `gameplay.sound` fact through the authoritative `WorldSession`. That semantic event remains the one hearing/AI consequence. Once that event has crossed the session's stable consequence boundary, the still-active utterance continuously re-evaluates the existing acoustic propagation from the speaker's current world position to the player's normal `VarkAcousticListener` position every physics frame; presentation movement does not emit another semantic sound.

The words are a billboarded world-space `Label3D` above the speaker with depth testing disabled. Visual cover therefore does not erase words an active utterance is currently carrying acoustically to the player. Opacity is a continuous smoothstep-shaped function of live propagated strength above hearing threshold; the same alpha drives both text fill and outline, and the fade eases to zero at the inaudible boundary.

Structural cover is represented by the same acoustic topology used by ordinary gameplay sound. Speech Lab uses two acoustic spaces separated by the wall plus one full-transmission `portal.cover_edge` at the open edge. **OPENING / LOUDER** and **BEHIND COVER / MUFFLED** are deliberately near the same direct speaker distance, but behind cover the acoustic route must travel through the opening and is longer, so propagated strength and text opacity fall without any speech-specific wall multiplier. **NEAR / MARGINAL / INAUDIBLE** extend the same live proof.

**Done when:** a line cannot appear before its one semantic `gameplay.sound` event crosses the controlled acoustic consequence boundary; structural cover changes propagated strength through the ordinary spaces/portals route rather than a private speech LOS rule; during the same active utterance the whole glyph continuously fades as current propagated strength falls, disappears at/below hearing threshold, and can reappear if the player returns to audible space before expiry, all without another semantic sound event; expiry clears stale text; source text/lifetime comes through the tiny line-ID/data Resource rather than guard AI; diagnostics distinguish semantic queued/heard counts from live propagation; and no conversation tree, writer tooling, localization framework, voice playback authority, awareness behavior, generic intra-space obstacle occlusion, or Phase 12 dialogue system is pulled forward.

**Automated:** passed — exact accepted head `4cb87267ad05f9c1eb74284611cb5aafe02f99b3` passed Godot 4.7.2 GitHub Actions Test run #236 with the structural-cover route proof, same-utterance attenuation, synchronized fill/outline fade, smooth near-threshold tail, `ALL SPEECH TESTS PASSED`, and `ALL TEST SUITES PASSED`.

**Manual:** accepted for roadmap continuation — validator: **Windows x64 user/playtester**. After the structural-cover correction was uploaded/verified and its changed test topology was reviewed, the user explicitly requested the next roadmap step. This records acceptance of the current 3.9 micro-proof; that acceptance message supplied no additional tuning notes.

## 3.10 Simple objective/exit `[x]`

A development-only **Objective Lab** adds only enough authoritative objective state to give the future five-minute route a beginning and an end. One `VarkSimpleObjectiveState` owns a single objective ID, one exit ID, objective-complete truth, exit attempt counts, and route-complete truth. It exposes small public semantic queries for objective and exit state; callers do not read private door, NPC, trigger, or owner fields.

Two dumb `VarkSemanticRouteTrigger` areas demonstrate the world-facing seam. The objective marker queues `objective.complete_requested { objective_id }` once when the real player crosses it. The exit queues `mission.exit_requested { exit_id }` on each entry. The triggers know only the semantic event name/key/ID and the authoritative `WorldSession`; they do not know whether the objective is complete.

The objective owner handles those facts synchronously during the existing stable semantic consequence pass. An exit attempt before the objective is recorded but remains blocked. Completing the objective changes the public objective query to `complete` and the exit query to `unlocked`. A later exit attempt marks the route complete and appends exactly one detached `mission.completed { objective_id, exit_id }` semantic fact. Further exit attempts remain idempotent and cannot duplicate mission completion.

This is deliberately not a mission-rule system, objective list framework, campaign state, save implementation, mission transition, score/stat system, or production UI. The existing authored `vark_exit` point remains spatial/content identity until production mission binding is proven; 3.10 proves the gameplay semantics separately.

**Done when:** Objective Lab launches through the production Application → WorldSession → Player path; the initial public queries report one active objective and locked exit; entering the exit first emits a semantic attempt but cannot complete the route; crossing the objective marker changes authoritative state only through the semantic event drain and unlocks the exit query; entering the exit afterward marks route completion and emits exactly one detached `mission.completed` event; repeated exit attempts do not duplicate completion; unknown query IDs fail closed; triggers contain only semantic IDs/event configuration and never inspect private objective/door/NPC internals; and diagnostics expose objective completion, exit attempts/blocks, and mission completion count.

**Automated:** passed — exact accepted head `2935a1fca9268e0e2b6c2f450391827c0cc7dcf3` passed Godot 4.7.2 GitHub Actions Test run #237 with blocked-before-objective, stable-boundary objective completion, exactly-once `mission.completed`, repeated-exit idempotence, `ALL OBJECTIVE TESTS PASSED`, and `ALL TEST SUITES PASSED`.

**Manual:** passed — validator: **Windows x64 user/playtester**. The user completed the handed-off Objective Lab sequence — EXIT first remains locked, OBJECTIVE unlocks EXIT, returning to EXIT completes the route, and the repeated-entry idempotence check showed no reported problem — and reported “all good.”

## 3.11 Actor life-state and identity compatibility proof `[x]`

The existing primitive `VarkGuard` is the smallest actor/life-state compatibility owner rather than spawning a separate knockout/corpse identity. The guard root carries authored `persistent_id` and optional semantic `content_id` in addition to its existing `guard_id`; Guard/Nav Lab authors those IDs on the same mapper-created guard. The current-world registry therefore resolves both persistent and semantic actor addresses to the same `CharacterBody3D` root before and after life-state changes.

The actor owns three semantic life states: `conscious`, `unconscious`, and `dead`. Ordinary gameplay changes are requested through `actor.life_state_requested { persistent_id, actor_id, target_state }` and applied only during the existing controlled semantic event drain. Accepted runtime transitions are intentionally monotonic for this proof: conscious may become unconscious or dead; unconscious may become dead; dead is terminal. Each accepted transition appends one detached `actor.life_state_changed { persistent_id, actor_id, from_state, to_state }` event.

Life state gates activity without changing ownership. Conscious actors remain eligible for future awareness work and use the existing configured navigation. Unconscious/dead actors immediately stop locomotion and door-use retries, report awareness ineligible/navigation inactive, but retain the same guard root, collision body, configured patrol ownership, `NavigationAgent3D`, persistent ID, semantic actor ID, and registry reference. Non-conscious actors may be repositioned externally as body-compatible world state without identity churn; this does **not** implement dragging/ragdolls/corpse physics yet.

The guard exposes detached `capture_semantic_state()` and quiet `apply_semantic_state(snapshot)` as a compatibility proof for future save/restore. Restore-style apply is rejected while the session is PLAYING, validates actor identity/state, may reconstruct any valid saved life state while non-playing, and emits no ordinary gameplay transition event. This is not the Phase 4 save coordinator and does not serialize navigation paths, engine callbacks, or body physics.

**Done when:** the real Guard/Nav actor is registry-addressable by persistent/content identity; conscious patrol/navigation still functions; a requested unconscious transition does not mutate before the controlled consequence pass; after the pass the same registry node and same `NavigationAgent3D` remain while awareness eligibility/navigation activity are gated off and locomotion stops; body-compatible repositioning preserves the same actor identity/reference; gameplay cannot wake/resurrect through this monotonic seam; unconscious → dead likewise waits for the consequence pass and preserves identity/ownership; detached semantic capture cannot share mutable truth with runtime state; restore-style application is refused while PLAYING, applies valid saved life state while non-playing, rejects another actor's snapshot, preserves the same registry/navigation owner, and emits no gameplay consequence.

**Automated:** passed — exact accepted head `d5172daca3bfc5b4f6dfa531e75a006a503285e5` passed Godot 4.7.2 GitHub Actions Test run #238. The Actors suite proved one registry-addressable actor root, conscious navigation, queued-vs-drained unconscious/dead transitions, same-node/same-`NavigationAgent3D` ownership, non-conscious body-compatible movement, detached capture, and quiet non-playing restore application; CI reported `ALL ACTOR TESTS PASSED` and `ALL TEST SUITES PASSED`.

**Manual:** none — accepted from deterministic coverage because 3.11 deliberately adds no player-facing knockout/combat interaction, dragging/ragdoll behavior, tuning, or subjective presentation contract.

## 3.12 Integrated five-minute stealth slice `[x]`

A development-only **Integrated Slice** forces the accepted Phase 3 implementations to coexist in one ugly playable route instead of remaining isolated labs. It uses the production Application → WorldSession → Player path and one compact two-room graybox separated by the real ordinary door. The north room contains structural cover, a dedicated low **CROUCH COVER**, and one real shadow-casting `VarkGameplayLight`; the south room is the start/exit side. The corrective visual-lighting pass removes the previous decorative shadow-casting `DirectionalLight3D`: neutral environment ambient remains only as a low readability floor, while every gameplay-world rendered shadow light in this slice is now also a gameplay exposure source. One real `VarkGuard` patrols between the rooms on a runtime-baked `NavigationMesh`, detours through the single doorway, and uses the same ordinary-door navigation seam proven in 3.7.

The same door also controls the single acoustic portal between authored south/north acoustic spaces. The player and guard each carry normal `VarkAcousticListener` nodes, so opening/closing the door changes the same propagated-strength route used for gameplay sound and typed speech. Two real `VarkOrdinaryProp` crates use the accepted Junk carry/throw/release/impact implementation inside that world.

The historical slice-local proof has since been promoted into the Phase 5 shared three-tier surface system. The current Integrated Slice uses carpet 0.09, stone 0.21, and tile 0.90 source strengths, with the shared 0.75 crouched multiplier and 1.35 sprint/landing multiplier. The emitter still queues only semantic `gameplay.sound` facts and owns no presentation audio.

NPC reaction is likewise thin integration glue rather than the future awareness system. A slice-local guard reaction adapter consumes the guard's real acoustic-listener evidence for `footstep.*` and `prop.impact`. The first heard player noise turns the guard toward the source, exposes a development reaction label, and asks the existing `VarkWorldSpeechSpeaker` to say one resource-authored **“What was that?”** line. That response is itself the normal semantic speech sound and only appears to the player through the existing live acoustic presentation path.

Primitive slice vision combines the accepted world-owned player exposure scalar, guard facing/range, and one physical LOS ray. The LOS target is now the player's live `Head` transform (with a live-capsule fallback), so the existing crouch implementation physically lowers the sight target instead of vision aiming at a fixed `player + 0.75 m` point. Losing current LOS clears the slice-only **PLAYER SEEN** diagnostic rather than leaving stale visual evidence. The dedicated low cover is sized so an exposed standing head can be visible while the same fully crouched player is physically occluded even though gameplay exposure remains above the vision threshold. Exposure sampling already follows the live player capsule, so crouching can also change which body samples are illuminated/occluded without an arbitrary stance visibility multiplier. This remains an integration probe only, not durable awareness/search/detection state.

The accepted 3.10 `VarkSimpleObjectiveState` and semantic route triggers provide the beginning/end: the north objective unlocks the south exit, and returning to the exit completes the route. The top-left exposure/light-gem readout remains development presentation. The route intentionally has no final mission UI, final guard awareness/search behavior, presentation audio, combat/knockout action, production footstep-material framework, or save coordinator.

**Done when:** Integrated Slice launches from Development Launch through the normal application/session/player path; its only gameplay-world rendered shadow light is a `VarkGameplayLight` sampled by the exposure owner; runtime navigation is nonempty and the real guard moves/uses the same door; the guard remains registry-addressable by the accepted persistent/content identity; the acoustic graph contains the two spaces, one door portal, player listener, and guard listener; the same door materially changes propagated strength across the rooms; loud-stone and quiet-carpet surfaces emit semantic footstep strengths without presentation audio; fully crouched footsteps are semantically quieter than standing footsteps while preserving their surface identity; one loud real player step can be heard by the guard and cause exactly one resource-backed world-space spoken reaction that is itself acoustically gated for the player; real Junk can still be picked up/thrown in the same world; the existing exposure owner plus live crouch geometry/LOS can produce standing-visible versus crouched-behind-low-cover behavior without a fixed-height sight target; the objective/exit contract still blocks early exit, unlocks after objective, and completes afterward; and none of those integrations introduce a replacement door, sound, nav, actor identity, speech, exposure, prop, movement, or objective truth.

**Automated:** accepted — exact implementation head `12541ef6447f18e41ba7047094db8ed4dd415e22` passed Godot 4.7.2 GitHub Actions Test run #242. The wired Phase 3 Integration suite passed the real application/session launch, single gameplay-world shadow light, baked navigation plus ordinary-door use, door-dependent acoustic route, standing versus crouched semantic footstep hearing, typed acoustic speech, crouch-cover live-head LOS while still gameplay-lit, Junk carry/throw coexistence, and objective/exit path; CI ended with `ALL PHASE 3 INTEGRATION TESTS PASSED` and `ALL TEST SUITES PASSED`.

**Manual:** accepted — Windows x64 user/playtester reported the corrective Integrated Slice pass **all good**: lighting/exposure coherence, crouch hearing and low-cover visibility, ordinary movement, guard/door traversal, acoustics/speech, Junk interaction, and objective/exit completion had no reported regression.

**Phase gate:** passed — the dangerous Phase 3 assumptions have isolated proofs, durable semantic mutation/event/lifecycle timing exposes one stable gameplay boundary, actor identity survives life-state changes, and the accepted integrated route exercises the same implementations together without an architectural contradiction.

---

# Phase 4 — Coherent transactional save/restore and hostile-architecture compatibility

Goal: turn the semantic state contracts and lifecycle used by the slice into ordinary-gameplay quicksave/restore, then prove the same ownership model survives one crude hostile interaction before stealth APIs are hardened.

## 4.1 Save coordinator, detached snapshot capture, and transactional replacement `[x]`

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

The first implementation is deliberately an **in-memory logical quicksave slot**, not the Phase 4.6 durable file format. A persistent application-owned `VarkSaveCoordinator` accepts a quicksave request only from the current PLAYING/PAUSED `WorldSession`, records that exact source session and its next stable-boundary serial, then captures synchronously after the existing semantic consequence pass. The captured value-owned envelope currently contains source/boundary provenance, gameplay simulation time, resource paths needed to rebuild the same world package, and the input-owned player view pose. Phase 4.2 extends this snapshot with gameplay-system semantic owners; 4.6 replaces the logical commit with validated durable temporary/new-file replacement without changing capture ownership.

Captured generations enter a later application-frame writer/commit stage. The coordinator keeps the previous fully committed slot readable while a newer request is only pending/captured, rejects an older captured generation once a newer request exists for that slot, and removes the live source-session reference immediately after capture. Application teardown explicitly cancels still-pending requests for that source session, so restart/load/exit can never retarget them. A captured detached generation remains eligible to commit after its source world is gone.

Restore uses the simple sole-world topology already permitted by the foundation contract. `VarkApplication` prevalidates the detached snapshot and resource paths while the current world is untouched; after that it disables input, tears down the old session, builds one processing-disabled candidate, enters `RESTORING`, reapplies the session envelope and input-owned view orientation, completes restore to `READY`, then publishes/binds/enables exactly one replacement `PLAYING` session. Failure after destructive transition discards the partial candidate and returns to the coherent application menu state. This item does not yet claim door/prop/guard/objective/traversal semantic restoration or save compatibility/durable disk I/O.

**Done when:** a request is bound to one source `WorldSession` and captures only at that session's next successful stable boundary; the detached snapshot cannot change when live state or caller-owned copies change; a pending request cancels instead of migrating across teardown; a captured generation can finish committing after source teardown; newer logical-slot requests cannot be overwritten by older commits; quickload reads the latest fully committed snapshot rather than an in-progress newer request; and restore replaces the old world through one non-playing `RESTORING` candidate before gameplay/input resume.

**Automated:** accepted — exact implementation head `2930ab90614602ee706989e7a3696b2e678071a5` passed Godot 4.7.2 GitHub Actions Test run #243. `save_coordinator_regressions.gd` passed source-session cancellation across restart, stable-boundary serial/view-pose capture, detached-copy behavior, post-teardown commit, same-slot generation ordering, latest-committed reads, in-progress-newer-save exclusion during load, fresh-session replacement, restored gameplay time/view orientation, and return to one authoritative PLAYING/input-enabled application state. The run ended with `ALL APPLICATION TESTS PASSED` and `ALL TEST SUITES PASSED`, with no new parser/resource/UID/load failures.

**Manual:** none — 4.1 is accepted from deterministic application/session ownership coverage. It deliberately does not expose a user-facing quicksave key, durable filesystem write, broad gameplay semantic restore, or target-platform filesystem behavior; later Phase 4 items own those surfaces.


## 4.2 Semantic snapshots, resolved choices, long-running state, and object-existence order `[x]`

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

The first 4.2 implementation extends the 4.1 detached envelope with an explicit `world_state` ownership structure rather than serializing live Nodes:

```text
object_existence
persistent_entities
player
semantic_owners
mission_script_state
```

The current Integrated Slice has no permanent authored removals and no runtime-created persistent objects, so `authored_tombstones` and `runtime_entities` are explicitly captured as empty arrays and non-empty values fail closed instead of being silently ignored. The slice likewise has no independent save-owning mission script, so `mission_script_state` is explicitly empty. Future gameplay that introduces those cases must extend the corresponding ownership section rather than bypassing object-existence order.

The real slice door, both ordinary props, gameplay light, and guard now participate in the existing persistent-identity registry with stable slice IDs. Their snapshots use their existing semantic state seams; the guard additionally persists transform/velocity plus its already-resolved current patrol-goal semantic ID so restore resumes the current choice rather than selecting the default goal again. The player snapshot currently owns body transform/velocity while the already-separated 4.1 view pose remains input-owned. Detailed standing/crouched/airborne/hang/mantle/corner/catch policy remains 4.3, and door/prop/guard transient-policy stress remains 4.4.

Objective/fact state, one-shot route-trigger arming/counters, and Integrated Slice guard-awareness history use stable semantic-save-owner IDs rather than fabricated persistent world entities. These owners capture/apply their own facts and current mission-run statistics; restore refreshes derived labels/presentation from semantic truth without re-emitting objective, alarm, dialogue, or other gameplay events.

Restore now performs the bounded 4.2 order while the candidate is processing-disabled in `RESTORING`: validate object-existence sections → resolve/apply persistent-entity snapshots by persistent ID → apply player state → apply stable semantic-owner snapshots → accept the explicit empty mission-script section → reconcile derived/reference state → run optional `after_restore` hooks → recapture and compare the complete semantic world state → only then allow `complete_restore()` to return the candidate to `READY`. Ordinary semantic event queueing remains unavailable until the application later enters `PLAYING`.

**Done when:** the current Integrated Slice quicksave contains detached semantic state for its player, ordinary door, both props, guard life/current goal, gameplay light, objective/fact state, present mission-run counters, one-shot route state, and guard-awareness state; current unsupported tombstone/runtime-persistent/mission-script sections are explicit and fail closed if unexpectedly populated; a fresh quickload resolves owners by stable identity, applies/reconciles/validates them while non-playing, preserves a resolved guard goal, and reaches PLAYING without restore-time semantic event replay.

**Automated:** accepted — the 4.2 implementation plus prop-API compatibility fix at exact `test` head `9b36b0eed36809c2b3f6b79d9116a0e063686f17` passed Godot 4.7.2 GitHub Actions Test run #245. `semantic_snapshot_regressions.gd` passed the real Integrated Slice ownership/reconstruction path, the existing carried-Junk reconciliation regression passed with its preserved explicit-holder API, every authoritative suite passed, and CI ended with `ALL TEST SUITES PASSED`.

**Manual:** none — 4.2 is accepted from deterministic semantic ownership/order coverage. It exposes no new player-facing save key, durable filesystem behavior, traversal/transient policy, or subjective save/load presentation; those remain owned by later Phase 4 items.

## 4.3 Player transient/traversal restore policy `[x]`

Classify representative player states into directly restorable semantic states, reconstructable transient states, or states normalized to a safe semantic equivalent.

Prove standing/moving, crouched, airborne, hanging, and mantle/corner/catch behavior according to the chosen policy.

Ordinary traversal/gameplay states must not gain routine save lockouts merely because direct runtime restoration is difficult.

The bounded 4.3 policy is explicit and intentionally avoids serializing detector candidates, collider RIDs, `await` continuations, mantle route objects, or other traversal-runtime implementation detail:

- ordinary standing/moving with no ledge traversal owner: **direct restore** of body transform, velocity, standing stance, and the separate input-owned view pose;
- fully crouched: **direct semantic restore** of body transform/velocity plus the requested crouched endpoint, snapping the fresh candidate's live capsule/head/visual geometry to the crouched semantic stance before play resumes;
- ordinary unsupported airborne with no ledge traversal owner: **direct restore** of body transform and ballistic velocity;
- a mid-height standing↔crouched transition: normalize only the stance transition to its already-requested endpoint; the body transform/velocity remain the directly restored truth;
- `catching`, `hanging`, `cornering`, and `mantling`: **normalize to ordinary airborne** at the same collision-safe body transform, zero traversal-owned velocity, preserve the requested stance endpoint and input-owned view orientation, discard live traversal candidates/routes, and suppress fresh mantle/hang acquisition for six physics frames so the discarded transition is not immediately recreated before gravity can separate the body from the ledge.

The player snapshot records both the source semantic state and the declared restore policy. Restore validation is policy-aware only for the player: the player must prove that its restored stance/traversal/pose/velocity satisfy the captured policy, while every non-player 4.2 owner still recaptures exactly. This does not loosen general world-state validation.

**Done when:** ordinary moving, fully crouched, and ordinary airborne states restore directly through the real Application/WorldSession replacement path; exact captures made during catching, hanging, cornering, and mantling remain saveable instead of being rejected; those traversal-runtime states load as ordinary airborne at the same safe pose with zero traversal-owned velocity and do not instantly reacquire the discarded traversal; no save lockout is introduced for these representative player states.

**Automated:** accepted — exact `test` head `b5172f0bb1af8031bc0aae0b0cf6e625a72ddc38` passed Godot 4.7.2 GitHub Actions Test run #250. `player_restore_policy_regressions.gd` passed direct standing/moving, crouched, and ordinary-airborne restoration plus catching/hanging/cornering/mantling saveability, normalized-airborne reconstruction, and traversal re-entry suppression. The unchanged Movement suite also passed, and CI ended with `ALL APPLICATION TESTS PASSED`, `ALL MOVEMENT TESTS PASSED`, and `ALL TEST SUITES PASSED`.

**Manual:** none — 4.3 is accepted from deterministic save/load reconstruction coverage. It introduces no player-facing save control or subjective presentation; target-platform/user-facing save validation remains later Phase 4 work.


## 4.4 Other transient-state save policy `[x]`

Explicitly test/define saving during door movement, prop falling/thrown, guard investigating/alert, actor unconscious/dead/body, and any other transient state present in the slice.

Gameplay durations restore from world-simulation semantic progress, not elapsed wall-clock time during pause/load.

The bounded 4.4 policy reuses the semantic owners established in 4.2 rather than serializing physics/nav runtime machinery:

- ordinary door `opening`/`closing`: **direct restore** of semantic phase, normalized `open_fraction`, and the obstruction latch. Blocker object identity is transient physical context and is intentionally discarded; future motion performs fresh physical sweeps. Remaining transition duration is derived from authored `transition_seconds` and saved fraction, so only resumed world-simulation steps advance it;
- moving ordinary props, including a thrown prop in unsupported fall: **direct restore** of semantic motion kind, upright transform, and linear velocity. Jolt direct-body state, contact/rest counters, pending impact callbacks, angular solver response, and temporary player-collision-ignore bookkeeping are reconstructed/cleared rather than serialized;
- carried Junk remains the already-proven semantic carried phase from the prop/player ownership seam; restore reconciliation re-adopts the prop through the player rather than serializing a holder pointer;
- guard investigation/alert equivalents currently present in the slice (`heard_noise` and `saw_player`): **direct restore** of awareness state, counters, and last resolved evidence. The source gameplay sound/vision consequence is not replayed on restore;
- guard actor `unconscious` and `dead`: **direct restore** on the same persistent actor/body identity, including transform/velocity and life state. Navigation ownership remains structurally present but inactive; there is no separate corpse identity;
- guard door-use/request/path solver transients are **reconstructed/normalized** from the restored persistent transform, resolved patrol goal, authored door identity, and fresh navigation rebuild rather than persisted as callback/request state.

The current slice has no separate timed investigation/search decay, stun timer, bleedout timer, animation callback, or other gameplay-duration owner beyond door transition progress and world-session gameplay time. New timed gameplay must persist semantic stage/progress/remaining simulation time under the 4.2 rule; elapsed wall-clock/application time during pause/load is never semantic progress.

**Done when:** the real Integrated Slice can capture/restore a partially moving door without wall-clock progress, a physically falling thrown prop with its motion/velocity intact, heard-noise investigation and confirmed visual alert without replaying the source consequence, and unconscious/dead body states on the same persistent guard identity. Each representative transient remains save-requestable, resumes or normalizes according to the policy above, and no engine timer/callback/solver continuation becomes save truth.

**Automated:** accepted — exact `test` head `808e9ab6e9b29c07d8d3002c3daad7305494902b` passed Godot 4.7.2 GitHub Actions Test run #252. `transient_state_restore_regressions.gd` passed moving-door semantic progress/simulation-time resume, falling thrown-prop reconstruction/continued simulation, real heard-noise investigation restore, confirmed visual-alert restore, and unconscious/dead body restoration. Existing Props, Actors, Movement, and Application suites all passed, and CI ended with `ALL TEST SUITES PASSED`.

**Manual:** none — 4.4 is accepted from deterministic transient save/load coverage. No user-facing save binding, durable file behavior, migration/compatibility UI, or subjective presentation is introduced here.


## 4.5 Snapshot coherence, restore suppression, operation ordering, and failure safety `[x]`

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

The bounded 4.5 proof uses the existing sole-world replacement topology and strengthens the already-present 4.1 coordinator/order coverage instead of adding a second transaction system:

- a save request is bound to the source `WorldSession` and its next stable gameplay-boundary serial; queued semantic consequences must drain before capture can succeed;
- the coordinator captures session semantic state and the current input-owned view pose synchronously in one physics callback after that boundary. Look remains event-driven before the physics tick; the captured player transform and view pose must describe the same already-applied request-side orientation;
- pending saves are cancelled when restart, load, mission transition, or exit tears down their source session. Captured detached snapshots may finish their logical slot commit after source teardown because they no longer reference live world objects;
- one application-owned top-level operation excludes load/restart/transition/exit and new save requests until its owner finishes;
- restore runs while the replacement session is `RESTORING`, where semantic event enqueue is unavailable. Reconciliation/`after_restore` must reproduce the captured semantic owners without replaying one-shot objective/stat/awareness consequences;
- successful restore is sole-world replacement: the old session is torn down, one fresh candidate is restored/validated while non-playing, then only that candidate becomes PLAYING;
- malformed snapshots rejected by coordinator validation do not tear down the source world. If a structurally valid snapshot fails deeper semantic reconstruction after sole-world teardown, the candidate is discarded and the application owns a coherent menu/no-world recovery state with gameplay/look disabled; a fresh launch must still work;
- same-slot save generations retain the existing 4.1 newest-request-wins rule, so a captured older request cannot overwrite a newer request.

The current slice has no collected-loot tombstone or alarm/rule subsystem yet. Restore-suppression coverage therefore uses the real one-shot objective trigger, blocked-exit run statistic, acoustic guard-awareness consequence, door semantic state, and the existing semantic event queue. Later content owners must use the same suppressed RESTORING/after-restore contract.

**Done when:** one regression demonstrates a multi-system queued consequence boundary captured coherently with immediate input-owned view pose; restore reproduces that boundary with zero queued gameplay events and no duplicated one-shot/stat/awareness effects; transition/exit source binding and direct top-level exclusion are proven; invalid restore paths leave either the original source authoritative or a coherent menu/no-world recovery state; and the existing save-coordinator ordering regressions remain green.

**Automated:** accepted — exact `test` head `416e82409a3494daeeb3427c69bcf8528427f525` passed Godot 4.7.2 GitHub Actions Test run #254. The formerly flaky 4.4 visual-alert fixture was stabilized, every 4.5 coherence/suppression/source-binding/operation-exclusion/failure-recovery assertion passed, and CI ended with `ALL APPLICATION TESTS PASSED`, `ALL PROP TESTS PASSED`, `ALL ACTOR TESTS PASSED`, `ALL MOVEMENT TESTS PASSED`, and `ALL TEST SUITES PASSED`.

**Manual:** none — 4.5 is accepted from deterministic ownership, suppression, ordering, and failure-state coverage. Durable filesystem behavior and compatibility/revision ownership remain 4.6.


## 4.6 Save compatibility, content revision ownership, and durable write `[x]`

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

The bounded 4.6 implementation introduces one global `SaveFormat.CURRENT_VERSION` and records `save_format_version`, `mission_id`, and `mission_content_revision` as separate fields in every WorldSession save envelope.

For authored missions, `MissionDefinition.mission_id` and `MissionDefinition.mission_content_revision` are the compatibility authority. Restore prevalidation reloads the installed MissionDefinition, confirms it still owns the saved world scene, and rejects mismatched mission identity or content revision before destructive replacement. The current development-only raw-scene launch path has no MissionDefinition by design; those fixtures receive an explicit synthetic `dev_scene:<world_scene_path>` identity and revision 1 so existing focused save regressions continue to exercise persistence without inventing authored mission metadata.

`save_format_version` is global schema/meaning ownership, not a content revision. This item supports only the current version; unsupported global versions and mission revisions fail closed with explicit "No migration is available" errors. No migration framework is introduced.

Committed quicksaves are durable under `user://vark/saves/<slot>.varksave`. The coordinator serializes only the already-detached snapshot Variant with object decoding disabled. A durable commit writes `<slot>.varksave.new`, closes/flushes it, reopens and validates the complete snapshot (including installed compatibility) and exact round-trip value, then performs one same-filesystem rename over the previous slot. The prior valid slot is not replaced until the new file has validated. A leftover `.new` file is never treated as committed truth; if a valid final slot exists it is discarded, while a valid temp may be promoted only when no final exists.

The in-memory committed-slot cache remains an optimization, not persistence truth. A fresh Application/SaveCoordinator with an empty cache can discover the durable slot and quickload it through the same ordinary restore path. Loading an incompatible/corrupt durable file leaves a clear coordinator/application save error instead of silently migrating or interpreting it.

**Done when:** a real MissionDefinition-backed Playground save records all three compatibility fields; format, mission-id, and content-revision mismatches are rejected before replacing the current world with clear errors; a committed quicksave produces one validated durable slot without a committed temp artifact; a later valid save replaces that slot only after temp validation; and a completely fresh Application instance can quickload the latest durable snapshot from disk while ignoring an uncommitted stale temp.

**Automated:** accepted — exact `test` head `d85fcba936781f7680309fbeff0882d087b83bdb` passed Godot 4.7.2 GitHub Actions Test run #256. All 4.6 compatibility metadata, unsupported-format/mission/revision rejection, validated durable replacement, stale-temp handling, and fresh-Application disk quickload assertions passed. CI ended with `ALL APPLICATION TESTS PASSED`, `ALL PROP TESTS PASSED`, `ALL ACTOR TESTS PASSED`, `ALL MOVEMENT TESTS PASSED`, and `ALL TEST SUITES PASSED`.

**Manual:** none — 4.6 is accepted from deterministic durability/compatibility coverage. It still introduces no player-facing save/load controls, slot UI, migration UX, or subjective presentation.


## 4.7 Crude hostile-interaction compatibility proof `[x]`

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


The bounded 4.7 implementation adds only the smallest hostile seam needed to exercise the existing architecture:

- project input declares an intentionally unbound development `attack` action. `ApplicationInputBoundary.sample_attack_pressed()` gives it the same one-physics-frame edge, held-across-domain-loss suppression, and cancellation semantics already used by interaction;
- `PlayerHostileInteraction` performs one short center-view raycast only on a fresh attack edge and only while ordinary hand actions are available. A conscious `VarkGuard` hit queues detached `combat.crude_hostile_effect` semantic work with stable target IDs; it does not mutate the guard directly;
- the target guard handles only the current crude `knockout` effect. During the controlled semantic drain it queues `gameplay.sound(kind=combat.hostile_impact)` first, then uses the existing `actor.life_state_requested` path for conscious→unconscious. FIFO ordering lets conscious acoustic listeners resolve the impact before the actor becomes inactive;
- the Integrated Slice guard reaction recognizes the hostile-impact gameplay sound through the existing acoustic listener path. The reaction evidence (`heard_count`/last heard kind) remains semantic save state even after the unconscious guard's current reaction state normalizes to `inactive`;
- no new hostile-specific persistence format exists. Guard life state/body state and reaction evidence are captured by the already-established actor and semantic-owner snapshots, then restored through ordinary quickload without replaying attack, sound, or life-state events.

There is deliberately no physical attack animation, weapon selection, health/damage arithmetic, hit-stop, stamina, block/parry, lethal tuning, AI pursuit logic, or final control binding here. Those belong to later combat/stealth phases.

**Done when:** the real Integrated Slice accepts one fresh application-owned attack edge, resolves one center-view guard hit through queued semantic hostility → gameplay sound/perception → existing life-state transition, proves a held attack does not create a second edge, saves the resulting unconscious actor plus resolved reaction evidence, mutates the live actor away from that state, then quickloads a fresh world whose actor/awareness state matches the save with an empty semantic event queue and no replayed consequences.

**Automated:** accepted — exact `test` head `9fe4002b8207bdd51e77a5a3f7aceb9cb2555edf` passed Godot 4.7.2 GitHub Actions Test run #257. Every hostile compatibility assertion passed: fresh attack edge, FIFO hostile→sound→life-state consequences, held-edge expiry, detached hostile save truth, quickload without replay, and stable resumed simulation. CI ended with `ALL APPLICATION TESTS PASSED`, `ALL PROP TESTS PASSED`, `ALL ACTOR TESTS PASSED`, `ALL MOVEMENT TESTS PASSED`, and `ALL TEST SUITES PASSED`.

**Manual:** none for 4.7 — accepted as an architecture compatibility proof. The development attack action remains physically unbound and there is no subjective combat timing/animation/feedback contract yet.

**Phase gate:** passed — developer quicksave/restore captures detached coherent semantic state/view pose during ordinary/transient play, keeps pending captures bound to their source session, commits saves in correct request order, restores through a simple transactional topology without gameplay side effects, handles global/mission compatibility failures coherently, and proves crude active hostility survives the same architecture without replacement.

---

# Phase 5 — Harden the stealth core

Goal: turn spike implementations into reliable Vark systems only after their interactions, save semantics, and hostile compatibility are known.

## 5.1 Surface profiles and gameplay noise `[x]`

Generalize the proven semantic gameplay-sound contract only as far as real use requires.

The Phase 3 footstep proof is promoted out of the Integrated Slice into reusable gameplay ownership without broadening the acoustic model:

- `VarkSurfaceProfile` is an authored Resource that owns the stable semantic `surface_id` plus exactly one of three authored loudness tiers: `quiet`, `normal`, or `loud`. Canonical footstep strengths are derived from the tier (`0.09`, `0.35`, `0.90`) rather than freely authored per surface. The current sound kind remains derived as `footstep.<surface_id>`; there is no duplicate authored kind or strength field;
- `VarkFootstepSurface` is a reusable Area3D that references one profile and exposes only profile-derived semantic summary data. Invalid/missing profiles fail closed;
- `VarkPlayerFootstepEmitter` is the reusable player/world emitter. It preserves the proven distance-based step cadence and stance scaling, resolves the current overlapping reusable footstep surface, and queues the same three-field `gameplay.sound` source fact through WorldSession. Grounded cadence progress pauses rather than resets when movement drops below the minimum speed, so repeated short WASD bursts cannot erase accumulated step distance and remain indefinitely silent. A normal airborne → grounded transition from a jump or fall emits one landing sound on the current surface at exactly the running loudness multiplier and replaces any same-frame cadence footstep. Mantling suppresses ordinary distance cadence while traversal owns the body; successful grounded mantle completion emits one stance-scaled ordinary step (crouched/sneaking if crouched, walking if standing), while a mantle cancelled into actual airborne motion falls back to the normal running-strength landing rule;
- the Integrated Slice keeps its old script paths as compatibility wrappers but moves behavior into `gameplay/noise`. Carpet, stone, and tile reference authored reusable profiles at `gameplay/noise/profiles/carpet.tres`, `stone.tres`, and `tile.tres`, and the slice contains non-overlapping labeled floor regions for all three tiers;
- carpet is `quiet` at 0.09, stone is `normal` at 0.35, and tile is `loud` at 0.90. Crouch uses a 0.45 source multiplier, standing movement 1.0, and sprint/landing 1.35. The slice guard keeps its 0.16 physical hearing floor and 0.30 footstep investigation source floor. Carpet stays below hearing even at sprint/landing strength; crouched stone remains 0.1575 and stays just below the physical hearing floor; standing stone is 0.35 and running/landing stone is 0.4725, so both are more audible and investigation-capable when actually heard; tile remains investigation-capable even while crouched at 0.405. Engaged/searching state no longer lowers hearing or footstep interpretation floors;

Door use, prop impact, speech, and crude hostile-impact sounds continue using the same semantic `gameplay.sound` contract directly. 5.1 does not introduce material physics, audio playback assets, per-shoe modifiers, sprint-specific tuning, random footstep variation, or propagation changes.

**Done when:** authored surface profiles remain exactly `quiet`, `normal`, or `loud`; carpet remains effectively unhearable, crouched stone remains below hearing, nearby standing/running stone can trigger investigation, tile remains investigation-capable even while crouched, and landing/mantle contact rules remain unchanged. All three still route through the existing gameplay-sound/acoustic-listener path.

**Automated:** accepted on exact `test` head `582cea86cf0e07d175e08607129a6a770b20017b` in GitHub Actions run #35731899121. Gameplay Noise verifies carpet 0.09 / stone 0.35 / tile 0.90, the 0.45 crouch multiplier, 0.16 physical hearing floor, 0.30 footstep investigation floor, the carpet/stone/tile reaction matrix, and landing/mantle contact behavior. The full regression barrier passed.

**Manual:** accepted by the user/playtester on tuned `test` head `7b0002a808a9cd2ce5a999eac1f0d286781095b7` after the Phase 5 stealth playtest. The accepted behavior covers hearing reach and the carpet/stone/tile matrix, repeated weak stone-sneak behavior, landing strength, standing/crouched mantle contact strength, and cancelled-mantle fall landing.


## 5.2 Acoustic model `[x]`

Stabilize the propagation architecture chosen by the spike. Doors/openings affect transmission consistently. Add debug visualization/inspection.

The Phase 3 space/portal model remains the propagation authority. This Thief-like tuning pass keeps the architecture but deliberately retunes ordinary closed-door transmission:

- every `VarkAcousticPortal` continues to connect exactly two authored acoustic spaces. A portal with no `door_id` is a constant authored opening and uses its configured `open_transmission`; a portal with a `door_id` resolves the matching world object through the existing `get_acoustic_openness()` seam and linearly interpolates `closed_transmission → open_transmission` from the same live 0–1 openness;
- topology configuration already fails closed for duplicate/missing spaces and invalid transmission. 5.2 explicitly protects missing door/opening references as an authoring error rather than silently treating them as open or closed;
- the accepted distance model remains `strength * exp(-path_cost)`, with path cost built from authored portal-route distance plus `-log(transmission)`. Same-space sound remains direct distance attenuation; disconnected spaces remain unreachable. No raycast-wall absorption, material-frequency model, reverberation, diffraction solver, or alternate door path is introduced;
- propagation now exposes detached debug inspection: current topology summary, sorted portal states (spaces, linked door, live openness, closed/open/current transmission), and the last semantic sound's per-listener heard/muted result, threshold, propagated strength, path distance/cost, and portal route;
- a reusable `VarkAcousticDebugInspector` renders that inspection to a development Label3D. The Acoustic Lab includes the inspector so opening/closing the ordinary door and emitting probe sounds visibly updates the same values used by gameplay.

Debug state is observational only and is not save state or gameplay truth.

**Done when:** malformed topology with a missing door reference fails closed; the Acoustic Lab proves its constant opening portal remains at authored transmission while the door-linked portal reports 0.40 at closed, 0.70 at half-open, and 1.0 at open from the existing ordinary-door openness; and after a semantic sound, debug inspection identifies the exact source kind plus per-listener heard/muted route results, including the direct, door, corner, and disconnected cases.

**Automated:** accepted on exact `test` head `582cea86cf0e07d175e08607129a6a770b20017b` in GitHub Actions run #35731899121. The Acoustics suite passes exact 0.40/0.70/1.00 closed/half/open transmission while preserving the same topology, path-cost math, diagnostics, and failure behavior.

**Manual:** accepted by the user/playtester on tuned `test` head `7b0002a808a9cd2ce5a999eac1f0d286781095b7` during the Phase 5 stealth playtest. Closed/half-open/open transmission was accepted as clearly ordered and readable without treating a closed ordinary door as near-total acoustic isolation.


## 5.3 Gameplay lighting/exposure `[x]`

Stabilize the gameplay-light/exposure contract proven by the spike. Add light gem and useful debug readout.

The Phase 3 visibility model remains the gameplay authority and keeps its accepted tuning:

- only explicit `VarkGameplayLight` nodes are exposure sources. Ordinary/decorative rendered `Light3D` nodes do not enter stealth exposure merely because they are visually bright;
- each gameplay light owns semantic enable/visible state, stable gameplay-light identity, gameplay strength, range, and occlusion mask. The existing save contract continues to persist `gameplay_enabled` and rendered `visible` state;
- `VarkGameplayExposure` remains one world-owned semantic sampler. It keeps the existing three vertical real-player body samples, per-sample physics occlusion, linear in-range distance weight, additive light contributions, and final 0–1 clamp. 5.3 does not retune sample positions, source strengths, ranges, occlusion masks, or guard vision thresholds;
- the exposure owner no longer owns HUD widgets. It exposes detached numeric/source diagnostics and emits a detached `exposure_sampled` observation after each sample. Source summaries distinguish total authored gameplay-light count from currently active gameplay lights and include enabled/visible/strength/range plus visible-sample/contribution data;
- reusable `VarkLightGem` observes exposure and renders the existing 10-step numeric gem plus useful per-source diagnostics. Exposure Lab and the real Integrated Slice both use this observer, so UI presentation no longer participates in semantic exposure calculation;
- the Exposure Lab adds a brighter decorative-only OmniLight3D fixture to prove visual rendering and stealth truth are intentionally separate. It also exercises live `gameplay_enabled` and `visible` changes on the real gameplay light and verifies exposure returns to the same accepted value when restored.

**Done when:** the existing dark/edge/partial/full, occluded, and two-light relationships remain unchanged; a bright decorative-only light contributes zero gameplay exposure and does not appear as a gameplay-light source; disabling or hiding the key gameplay light immediately removes its contribution while the debug summary marks it inactive; restoring the state reproduces the prior exposure; and the reusable light gem in both Exposure Lab and Integrated Slice matches the semantic exposure value and reports source state/visible sample diagnostics.

**Automated:** accepted — exact `test` head `3f51749a6e5cbd878ac3aaa84de21d785ab22bb9` passed Godot 4.7.2 GitHub Actions Test run #261. The Visibility suite passed decorative-only exclusion, gameplay-light enable/visible state changes, source/active diagnostics, and reusable light-gem agreement while retaining the existing dark/edge/partial/full, occlusion, and additive barriers. Phase 3 Integration also remained green, and CI completed successfully.

**Manual:** none — 5.3 is accepted because it intentionally preserves the Phase 3 exposure strengths, ranges, sample positions, occlusion behavior, and guard thresholds. The light-gem refactor/debug detail is deterministic presentation of unchanged semantic truth. A later change that retunes darkness/partial/full readability or final gem presentation must stop for a focused user playtest.


## 5.4 NPC perception/awareness `[x]`

Implement unaware, mild suspicion, investigation/search, confirmed alert/pursuit, and loss/recovery. Vision/hearing feed evidence without global omniscience.

Meaningful durations/decay use world simulation time. If search/patrol behavior uses randomness, once a choice becomes current gameplay truth it must survive save/restore as that resolved choice rather than being rerolled by restore.

5.4 promotes the Integrated Slice reaction spike into reusable `gameplay/npc/guard_awareness.gd` semantics while preserving the existing local hearing/vision sensors:

- semantic awareness states are `unaware`, `suspicious`, `investigating`, `searching`, `alerted`, `recovering`, and `inactive`. The old Phase 3 debug `state` field remains a compatibility-only presentation alias; `awareness_state` and the saved semantic state are authoritative;
- hearing evidence is strictly local to the guard's existing acoustic listener. Heard gameplay sound increments local evidence; weak heard evidence creates mild suspicion, while sufficiently strong heard evidence creates an investigation target at the resolved sound origin. A newly heard suspicious cue from unaware/suspicious/recovering immediately applies a navigation-independent observation pause, turns to the evidence, and holds without inventing a route. Observation patience is bounded: production allows at most two stare freezes in one rapidly repeated cue chain and replenishes the allowance after 12.0 gameplay seconds without another stare-worthy cue. Once the allowance is exhausted, stronger evidence immediately commits/recenters investigation instead of restarting another full stare; weaker evidence can still orient the guard but cannot indefinitely pin patrol in place. The chain count/reset remainder are semantic save truth. Investigating/searching guards derive heightened attention from their existing awareness state: the propagated-strength investigation threshold and footstep source floor remain at 1.00× the calm baseline, so engagement does not make a weak footstep semantically stronger. No global alert or player-position lookup is introduced;
- vision uses gameplay exposure, range, facing, and physics occlusion checks, but non-alert sight no longer confirms in one sample. A 0–1 visual-suspicion value accumulates continuously in gameplay time; the growth rate is derived from current exposure (production 0.10/s at the low edge up to 2.00/s at full exposure), and it decays at 0.08/s whenever useful sight is lost, including during an observation hold. Investigating/searching attention scales the minimum useful exposure threshold to 0.90 of baseline and the resulting suspicion growth rate to 1.25×; geometry, range, facing, LOS, and actual gameplay exposure remain mandatory. Crossing 0.40 makes the evidence worth investigating; reaching 1.0 confirms alert/pursuit. The 0.44 field is retained as the minimum effective exposure used by the point-blank darkness exception, so even an unobstructed player within 1.50 m/direct-facing dot 0.75 must accumulate suspicion rather than instantly alerting the guard;
- confirmed vision loss does not instantly erase knowledge. A short alert-loss grace uses WorldSession gameplay time, then transitions to `searching` at the saved last-seen position. Search expires into `recovering`, then returns to `unaware`;
- suspicion, investigation, search, alert-loss, and recovery durations are explicit semantic remaining seconds advanced only from `WorldSession.gameplay_time_seconds`. No engine Timer or wall clock owns awareness truth;
- `VarkGuard` keeps the narrow awareness-navigation override seam but locomotion now exposes exactly three semantic speeds from the existing feel values: walking/patrol 1.20 m/s (below the player crouch/sneak speed of 2.00), investigating/search 0.72 m/s (the previous slowest search speed), and running/pursuit 2.64 m/s (the previous fastest pursuit speed). Unaware patrol always uses walking, now deliberately much slower than player sneak; investigation and search cannot inject arbitrary fourth speeds through the motion-profile seam;
- current search behavior is deterministic and uses the resolved evidence/last-seen position directly; 5.4 introduces no random search-point selection. The resolved target and remaining stage duration are persisted in the awareness semantic snapshot and restored before ordinary simulation resumes;
- actor unconscious/dead state still forces awareness `inactive` and clears the temporary awareness navigation target.

The current implementation does not add guard-to-guard communication, alarm broadcasting, omniscient player tracking, combat decision-making, multiple search waypoints, or randomized search patterns. Advanced local search behavior belongs explicitly to 5.5; communication and combat decision-making remain later work.

**Done when:** a newly heard suspicious cue from unaware/suspicious/recovering can immediately stop/turn into a resolved 1.50–3.50 s observation hold without inventing an investigation route, but repeated cues cannot freeze the guard indefinitely: at most two stare freezes occur in one active chain, subsequent strong evidence commits immediately to investigation, subsequent weak evidence does not restart another freeze, and the allowance returns after the 12.0 s quiet interval. Investigation-worthy hearing from unaware/suspicious/investigating/search/recovery otherwise uses the same immediate stop/turn gate before investigating speed; visual suspicion grows continuously at an exposure-dependent rate instead of instant confirmation, with high exposure filling faster than low exposure and suspicion still allowed to decay during an observation hold when sight is lost; investigating/searching state raises evidence salience without extending sensors or adding hidden knowledge; the same pre-investigation hold occurs when visual suspicion first becomes worth investigating; confirmed pursuit and its contact-grace/last-known submodes do not enter this distraction stare; confirmed pursuit uses running speed while unaware patrol uses walking speed; current suspicion/stare/observation-patience truth is saveable; loss/recovery/search still preserve local knowledge; and existing Phase 3/4/5 regressions remain compatible.

**Automated:** the authoritative Awareness suite now additionally proves the production 10.0 m base vision range, the three-speed relationship (walk 1.20 < player sneak 2.00, investigate/search 0.72, run/pursuit 2.64), the 1.50–3.50 s production observation range, weak heard suspicion immediately pauses/orients without creating a navigation route, the first two rapid investigation-worthy cues may use the observation gate but a third cannot restart it and instead continues immediately toward the newest evidence, the allowance replenishes after the shortened test quiet interval, observation-patience state is included in semantic save truth, visual suspicion can decay while a hold remains active, bright sight accumulates suspicion faster than the point-blank darkness override, neither path alerts on the first sample, visual evidence passes through the hold threshold before confirmation, search attention lowers only evidence-interpretation thresholds/rates enough for a very close stone-sneak-strength cue to become actionable after prior stronger evidence, and ALERTED visible/lost pursuit remains exempt from the stop-stare distraction behavior. The Navigation suite also validates authored patrol-point dwell semantics and launches the real Vertical Stealth Lab, requiring its 24×28 floor, multi-level climb route, elevated objective, long patrol, and 2.5/4.0 s endpoint waits. Existing pursuit/loss/search/save/door regressions remain the compatibility barrier.

**Manual:** accepted by the user/playtester on tuned `test` head `7b0002a808a9cd2ce5a999eac1f0d286781095b7` after the Phase 5 stealth playtest. The accepted feel covers the current 10 m visual range, exposure/FOV/occlusion behavior, authored patrol waits, immediate weak-cue stop/orient, 1.50–3.50 s source-facing holds, bounded repeat staring, suspicion decay, vertical visibility, investigation/search evidence response, and confirmed/lost-pursuit exemption from distraction stares.


## 5.5 Advanced search / local investigation `[x]`

Replace the temporary single-point stationary search with believable local investigation while preserving the 5.4 information model: guards search from what they actually heard/saw, never from hidden current player position.

This is **TARGET** behavior until integrated play proves the final search cadence and spatial pattern. The production direction is an evidence-driven uncertainty search rather than a fixed waypoint script. Preserve the existing ownership split: perception creates local evidence, awareness owns knowledge/search state, and `VarkGuard` executes navigation/facing without gaining hidden-player knowledge.

The player-facing contract is:

- search begins from the resolved heard location or last-seen position already owned by awareness;
- awareness owns an explicit search anchor, uncertainty/search radius, confidence/age, resolved search plan, current progress, and visited locations; the hidden current player position is not part of search state;
- generate several reachable, plausible candidate points from the navigation space around the evidence. Candidate scoring may prefer evidence proximity, useful spatial separation, unsearched space, reasonable path cost, and later mission-proven spatial features such as room transitions/corners, but must never score against the hidden player's actual position;
- use controlled deterministic variation so repeated searches need not expose the exact same visible point order. Any pseudo-random seed/choice must derive from stable semantic inputs such as guard identity plus the evidence instance, and once candidates/order become resolved gameplay truth they are saved directly rather than regenerated on restore;
- move between several search points instead of standing indefinitely at one destination;
- treat each reached point as investigation: stop, visibly scan/look around/listen briefly, then continue. Ordinary vision/hearing remain live throughout the stop and movement;
- immediately after strong/visual evidence, search close to the anchor while confidence is high. If nothing is found, uncertainty may expand outward while confidence decays; both radius and total duration stay bounded;
- new local evidence may interrupt/recenter/reseed the search and collapse uncertainty around the new useful evidence;
- exhausting active search enters a meaningful residual-alert/recovery period rather than instant amnesia. During recovery the guard may resume its ordinary route while remaining temporarily easier to re-alert before decaying fully to unaware;
- do not query the hidden player's current position, choose cover because the player is actually behind it, or otherwise manufacture omniscient search choices.

Current Thief-like production tuning keeps the existing locomotion and state machine but extends persistence: suspicion 4 s, investigation 12 s, search 25 s, lost-pursuit budget 30 s, recovery 8 s, and observation-repeat reset 12 s. Search confidence decays at 0.02/s. Search stops use one or two looks with 2.0–2.8 s held gazes plus shorter turn/arrival/between/departure pauses.

Do not turn this item into room-clearing combat tactics, squad coordination, alarm broadcasting, or combat decision-making. Those remain separate later work.

The production-target implementation now keeps the same anti-omniscience foundation while replacing the first fixed-radius proof:

- `guard_awareness.gd` owns explicit search anchor, stable semantic seed, stage, uncertainty radius, confidence, gameplay-time age, resolved current candidate order, visited positions, scan progress, and residual recovery alertness;
- `VarkGuard.resolve_local_search_points()` samples the local navigation map, scores candidates only from evidence proximity, vertical agreement with the evidence, separation from searched locations, path cost, and stable deterministic variation, and never receives a player reference/position. Production search now starts at a 2.8 m uncertainty radius, can expand to 6.0 m, and enforces a 1.4 m minimum horizontal separation between resolved stops when navigation space permits;
- exhausting a local candidate stage expands the bounded uncertainty radius and lowers confidence; new evidence recenters the search at stage zero with high confidence;
- resolved candidate order remains direct save truth; stable seed/stage/uncertainty/confidence/visited positions also persist so later expansion after restore is deterministic rather than rerolled;
- active search keeps the Thief-style stop/look cadence, but locomotion now uses the single fixed investigating speed (0.72 m/s in the Integrated Slice) rather than resolving extra per-leg movement speeds. Arrival still resolves deterministic varied pause → directed turn → held look → optional additional look(s) → departure pause; the old sinusoidal in-place sweep is removed;
- search timing variation is derived from the stable semantic search seed/action index, so pauses and look holds feel irregular without becoming save/load nondeterminism. Production search duration is intentionally long enough to spend meaningful time walking cautiously and trying to see into darkness rather than checking a few nodes and immediately leaving;
- locomotion now has exactly three player-readable modes: walking for unaware patrol, investigating for investigation/search, and running for confirmed pursuit. The investigating mode reuses the previous slowest search pace; running preserves the previous fastest pursuit pace;
- active search keeps ordinary senses live during movement, pauses, turns, and held looks. Investigating/searching awareness now carries explicit heightened evidence salience: locally heard investigation strength and footstep source floors use 0.80× calm thresholds, minimum useful visual exposure uses 0.75× baseline, and visual suspicion accumulation uses 1.50× the normal rate. This never changes acoustic propagation, vision geometry/occlusion, or hidden knowledge. New investigation-worthy evidence interrupts the current action immediately, enters the longer source-facing observation hold, and only then navigates/reseeds. Vision separates horizontal body facing from vertical attention: unaware guards use the normal vertical field, suspicion/recovery widen it, ordinary investigation travel uses an intermediate field, and searching/alerted guards check steeply above and below while still requiring real range, LOS, and gameplay exposure. A source-facing pre-investigation stare temporarily retains the wide engaged field so a guard cannot notice an elevated source during search and lose the same source merely by entering the stare state. Elevated evidence keeps its true height, while search navigation accepts only reachable nav points and can also sample the guard's current floor when evidence is on another level;
- confirmed alert now owns an internal pursuit mode rather than equating ALERTED with same-frame LOS. Visible contact records last confirmed position, observed velocity, an attention direction, and one resolved reachable pursuit approach. A missed sample enters only a short contact-grace period; grace expiry remains ALERTED and runs to/checks the last useful approach. Search begins only after that check fails or a bounded lost-pursuit timeout expires. Strong local sound can update the trail only after visual contact has been lost; visible confirmed pursuit ignores distraction navigation. The pursuit approach uses only last observed position/velocity and navigation reachability, so ledges, walls, jumps, corners, doors, darkness flicker, temporary occlusion, and off-nav observed positions no longer imply instant search or hidden-player tracking;
- recovery immediately releases awareness navigation back to patrol and carries a simulation-time residual-alert value for 8.0 s before returning to unaware; default hearing thresholds remain unchanged during recovery.

No cover prediction, hidden-player scoring, room-clearing tactics, or squad behavior is introduced. Spatial scoring can grow later only from concrete mission-proven needs.

**Done when:** after losing confirmed sight or investigating a strong sound, the guard searches from explicit local evidence/uncertainty rather than hidden player truth; brief/routine LOS loss during a confirmed chase does not itself end ALERTED pursuit; the guard follows a reachable approach derived only from its last observed position/velocity, checks that last-known region, and only then hands off to search if reacquisition fails; visible pursuit outranks distraction sounds while lost pursuit may use strong new local evidence; approaches search locations at a visibly cautious speed distinct from fast confirmed pursuit; repeatedly stops, pauses, makes one or more directed human-scale looks with held gazes rather than spinning, and waits before moving again; spends a meaningfully long period searching; selects reachable plausible locations with controlled non-robotic spatial/timing variation and materially separated stops; preserves useful above/below evidence without selecting unreachable floors; can detect or reacquire a clearly exposed climbing player above or below with state-appropriate vertical attention while real occlusion still blocks sight; expands/decays uncertainty in a bounded way; new evidence recenters immediately; active search ends into temporary residual alert/recovery before full unaware patrol; and save/load restores both spatial search truth and the currently resolved movement/pause/look/pursuit action without rerolling.

**Automated:** implemented in the authoritative Awareness suite. In addition to the uncertainty barriers, it proves production search uses the widened radius/separation baseline, resolved stops respect the configured minimum spacing in the real Integrated Slice, search locomotion is slower than base patrol movement, confirmed pursuit is faster, current pursuit mode/goal survive quicksave/quickload, a visible confirmed chase ignores unrelated distraction navigation, first vision loss enters contact grace without dropping ALERTED, grace expiry continues reachable last-known pursuit rather than starting search, strong sound updates only an already-lost pursuit trail, search begins from the latest explicit evidence after pursuit failure, elevated visible lateral motion updates a reachable pursuit approach without losing alert, search reaches explicit stationary pause/look actions with navigation motion actually paused, action timing/remaining duration and resolved movement speed survive quickload, hidden-player movement cannot alter resolved search truth, uncertainty expands/reseeds correctly, multiple stops remain reachable, elevated evidence remains explicit while navigation stays reachable, steep elevated-player vision is rejected while unaware but reacquired during search/alert vertical attention, and residual alert/re-alert/decay remain intact. Exact human feel, total search patience, pursuit persistence, look timing, speed ratios, and final vertical-attention feel remain manual TARGET acceptance.

**Manual:** accepted by the user/playtester on tuned `test` head `7b0002a808a9cd2ce5a999eac1f0d286781095b7` after the Phase 5 stealth playtest. The accepted search/pursuit feel covers last-known pursuit before search, distraction priority, cautious search movement, spaced stops and held looks, long bounded search patience, non-omniscient local evidence, immediate real-evidence response, recovery, and elevated/lowered pursuit/search behavior with real occlusion.

## 5.6 NPC communication/local knowledge `[x]`

Implement explicit information sharing/alarm behavior without automatic global player knowledge.

The first bounded implementation keeps the accepted 5.4/5.5 perception/search values unchanged and adds only explicit knowledge-transfer seams:

- `VarkGuardCommunication` listens for a guard's **new local confirmed visual alert**. The first transition into confirmed ALERTED queues one `npc.local_warning` semantic report containing reporter identity/faction, reporter origin, authored warning strength, and the reporter's last confirmed evidence position. Continued same-contact vision does not rebroadcast every frame;
- local warnings are not global knowledge. A potential receiver must be conscious, share the explicit faction, and be able to hear the warning through the existing acoustic topology at its real listener position/threshold. Closed doors/spaces therefore affect warning transfer through the same propagation math as other gameplay-significant sound. The separate `npc.warning` gameplay-sound fact contains only origin/strength and does not smuggle the evidence position through the sound API;
- an accepted local warning gives second-hand **investigation** knowledge at the reported evidence position. It never queries or follows the hidden current player position. A guard already in confirmed ALERTED pursuit keeps its stronger local trail instead of accepting weaker shared knowledge;
- `VarkAlarmChannel` is an explicit authored/mission-facing alarm seam. Raising an alarm queues `npc.alarm_raised` with an alarm-channel ID, audience faction, source actor ID, evidence position, and serial. Only guards subscribed to that alarm channel/faction accept it. Alarm reception begins **search** around the reported evidence location; it does not turn recipients into confirmed pursuit or reveal current player position;
- ordinary confirmed detection automatically warns only through the local acoustic rule. It does **not** automatically raise a building/faction alarm. Mission logic, a switch, machine, script, or future rule action must explicitly call the authored alarm channel when broad propagation is intended;
- active alarm channel state (active flag, last evidence/source, raise serial) is semantic save truth. Recipient investigation/search truth is already owned by guard awareness. Restore reinstates those states without replaying warning/alarm events, preserving the foundation rule that loading a save must not itself become gameplay;
- the Communication Lab uses two real guards, the real acoustic spaces/ordinary door, real awareness/navigation, one local-warning pair, and one explicit building alarm. It is a development proof fixture rather than a new mission rule language or dialogue system.

This item does not implement squad tactics, radio networks, body discovery, mission-rule authoring, alarm switches/sirens, combat coordination, faction diplomacy, or omniscient global alert. Those remain later content/system work.

**Done when:** newly confirmed local sight emits one explicit local report instead of a per-frame broadcast; wrong-faction or acoustically inaudible guards gain no knowledge; an audible same-faction receiver investigates exactly the reported last-confirmed position and does not track later hidden player motion; an explicitly raised authored alarm reaches only subscribed faction/channel recipients and starts local search from the alarm evidence position without granting confirmed pursuit; current confirmed pursuit cannot be overwritten by second-hand reports; active alarm plus recipient knowledge survive save/load without communication replay; malformed communication payloads fail closed; and existing stealth/search/save/event regressions remain green.

**Automated:** accepted on exact implementation head `8aa547217c2fe37f7804a8e4ad32064895277146` in GitHub Actions run #352. The dedicated Communication suite launched the real Communication Lab through Application/WorldSession and proved exact local-warning payload shape/no current-player field, one report per confirmed-alert transition, closed-door acoustic rejection, faction rejection, same-faction nearby acceptance, fixed reported-position knowledge despite later player movement, explicit alarm subscription, alarm search without confirmed pursuit, and quicksave/quickload of alarm + recipient search with zero replayed communication events. Application, Acoustics, Awareness, Navigation, Phase 3 Integration, and the authoritative all-tests barrier all remained green.

**Manual:** none for this bounded architecture item. Final warning dialogue/nonverbal presentation, alarm audio/visual presentation, authored alarm switches, and mission-specific propagation feel are later player-facing/content work; this step's knowledge ownership, locality, event ordering, and persistence are deterministic.

## 5.7 Door/nav/perception integration `[x]`

The same ordinary door coherently affects traversal/navigation, sight, acoustics, NPC use, and save/load.

This step does not introduce a second door state or retune any accepted stealth parameter. The existing Integrated Slice `slice.door` / `door.slice` remains the single semantic owner and now has one explicit cross-system proof:

- navigation continues to carve the ordinary doorway out of the baked region and reconnect it only through the door-owned `NavigationLink3D`; the real patrol guard must request/use that same door to traverse the route;
- the door leaf remains the actual collision/vision occluder at every opening fraction. CLOSED blocks through the doorway; OPEN clears the doorway opening but the rotated open leaf still blocks sight if it is physically between guard and player, including when both are in the same room; partial OPENING/CLOSING fractions likewise occlude at the leaf's current angle. Perception does not maintain a parallel "door visibility" flag;
- the existing `portal.slice.door` acoustic portal resolves the same `door.slice` owner. CLOSED uses the muffled transmission, OPEN uses full transmission, and propagation remains route/topology based;
- the same semantic CLOSED/OPEN state exposes the matching narrow navigation-passage and acoustic-openness seams; NPC use, player interaction, sight, acoustics, and navigation therefore cannot independently disagree about which door is open;
- quicksave stores only the semantic door owner. Quickload creates a fresh world, restores the saved phase/open fraction, rebuilds navigation/link state, rebinds the acoustic portal, and lets the physical leaf immediately produce the correct LOS result. Restore must not queue a new door-use/state event;
- `IntegratedSlice.get_door_integration_debug_summary()` provides one read-only diagnostic view over persistent/semantic door identity, phase/fraction, navigation link/passage, guard door-use state, acoustic portal/openness, and the guard's most recent LOS obstruction. It does not become a second owner of any of those values.

**Done when:** one real Integrated Slice run proves the guard uses the door-owned navigation link, CLOSED and OPEN produce matching nav-passage/straight-through-LOS/acoustic states on the exact same `slice.door` instance, fully open and partial rotated leaves still block production guard LOS when physically between guard/player, the acoustic portal and guard both identify `door.slice`, saving OPEN then mutating the source door CLOSED and quickloading reconstructs OPEN nav/LOS/acoustic truth in a fresh world with no pending restore-time semantic consequences, existing dedicated Door/Navigation/Acoustics/Awareness/Application-save suites remain green, and the focused player-facing check confirms the door is understandable in ordinary play.

**Automated:** accepted — exact pre-5.8 `test` head `d5b2681585d3b4410777d086a0f9d7ce34d7b6f1` passed GitHub Actions Test run #360. The dedicated Door/Nav/Perception Integration suite launched the real Integrated Slice through Application/WorldSession, observed real guard use of the door-owned navigation link, proved CLOSED/OPEN nav/straight-through-LOS/acoustic coherence on the same semantic door owner, proved the fully open and partially open physical leaf still blocks production guard LOS when actually interposed, and passed open-door save/mutate/quickload reconstruction with no replayed semantic consequences. Existing Door, Navigation, Acoustics, Awareness, Phase 3 Integration, Application/save, and the authoritative all-tests barrier remained green.

**Manual:** accepted for roadmap continuation under the fresh-chat reconciliation rule in `AGENTS.md`. The user explicitly requested continuation to the next roadmap work after the exact 5.7 implementation head and its authoritative CI were green, and reported no 5.7 failure. This closes the ordinary player-facing door-coherence check without inventing any new tuning or changing the accepted Phase 5 stealth baseline.

## 5.8 Early stress fixtures `[x]`

Measure representative cost for multiple guards/vision, sounds/hearing, gameplay lights/exposure, and nav updates around doors. Record the reference environment.

The bounded early fixture is `tests/performance/run_phase5_stress_tests.gd`. It launches the real Integrated Slice through Application/WorldSession, leaves all accepted Phase 5 gameplay tuning unchanged, and adds only runtime test load that is discarded with the fixture:

- 12 real `VarkGuard` / production awareness owners perform 32 explicit vision samples each (384 production guard-vision checks total) against the real player/exposure/physics world;
- the real acoustic topology is refreshed with those guards' hearing listeners, then 48 semantic sound facts are propagated synchronously across every discovered receiver;
- 24 additional real `VarkGameplayLight` sources are attached to the same world and the production exposure owner performs 48 complete three-body-point exposure samples;
- 64 alternating CLOSED/OPEN semantic door changes are paired with synchronous `NavigationServer3D.map_get_path()` queries across the real baked patrol route and door-owned navigation link.

The suite records wall-clock observation time with `Time.get_ticks_usec()`, operation counts, receiver/source counts, and a reference-environment record containing Godot version, OS, processor name/count, and GitHub runner OS/architecture when present. Timing values are deliberately observational at this stage: shared CI hardware is not a stable performance budget. The test fails on malformed workload/state, missing real consumers, failed path resolution, or non-executed work—not on a guessed millisecond threshold.

**Done when:** one authoritative early-stress fixture exercises all four currently real Phase 5 expensive-system categories at explicit representative counts; every workload proves it actually reached the production implementation and preserves coherent door/navigation state; the suite prints detached environment + timing records suitable for comparison; the suite is wired into the authoritative all-tests barrier; and a successful exact-head run records the first reference baseline without changing stealth semantics to make the numbers look better.

**Automated:** accepted — exact implementation head `01e16311d02523e65df9fcb971b2ba5e4d2ec3d3` passed GitHub Actions Test run #361 and the authoritative all-tests barrier. The stress suite reported the fixed workload and reference environment without parser/resource/reference failures. Reference runtime: Godot `4.7.2-stable (official)`, Linux/X64 GitHub-hosted runner, AMD EPYC 7763, 4 exposed processors. Observed totals: 384 vision checks = 6.570 ms; 48 semantic sounds across 13 listeners = 624 receiver evaluations = 21.875 ms; 48 exposure samples with 25 gameplay lights = 49.559 ms; 64 alternating door/nav path cycles = 0.567 ms with 64/64 paths resolved. These are comparison observations, not CI budgets.

**Manual:** none — this item measures existing deterministic/headless system cost and adds no player-facing behavior or target-specific runtime integration.

**Phase gate:** the five-minute slice supports understandable darkness- and sound-based stealth with predictable guard behavior, stable save/reload semantics including resolved AI choices, and no architecture known to require replacement when active hostility expands later.

---

# Phase 6 — Complete the world interaction grammar

Goal: expand the minimal interaction contract without changing its fundamental language.

## 6.1 Interaction targeting/highlight completion `[x]`

Harden center-view targeting, range/occlusion/state checks, highlight, and one primary world-interaction input. The Phase 3 door/prop keep using the same contract.

The established `PlayerInteraction` owner remains the single ordinary world-selection path. Each permitted gameplay physics tick samples the current production camera's exact center-forward ray, bounded by the player's authored `interaction_range`. Only physical bodies participate in this generic selector: ordinary trigger/sensor `Area3D` nodes are neither interaction targets nor occluders, so mission/acoustic/surface sensors cannot accidentally steal the first hit. The first physical body still owns occlusion; the selector never skips through a wall, prop, inactive interactable, or malformed grouped object to reach another target behind it.

A physical hit becomes selected only when its node/ancestor carries the existing `vark_interactable` group and implements `can_interact(interactor) -> bool`, `interact(interactor)`, and `set_interaction_highlighted(bool)`. Missing methods or a non-boolean eligibility result fail closed. A valid `false` eligibility result also fails closed without searching through that physical object. The shared selector owns only selection; each target continues to own its current eligibility, interaction consequence, and Thief-style fullbright selection presentation.

The default primary world-interaction input remains **F** and continues through the application-owned one-physics-frame gameplay edge. Holding F never repeats an ordinary use. Losing gameplay/interaction ownership clears target highlight and blocked/stale input edges remain suppressed on resume. Carried Junk keeps its existing higher-priority F ownership and centrally suppresses ordinary world selection until carry ends.

`Player.get_interaction_debug_summary()` exposes observational selection status (`targeted`, `no_hit`, `blocked`, `ineligible`, `invalid_contract`, or unavailable/invalid-view), first physical hit/candidate name, hit distance, range, and the sensor-area policy. This is diagnosis only and is not save state or a second interaction owner.

**Done when:** Interaction Lab proves exact center-view selection, range rejection, physical first-hit occlusion, non-blocking generic sensor Areas, target-owned current-state rejection, fail-closed malformed target contracts, immediate highlight restoration/clearing, and one fresh F edge per ordinary use; central interaction suppression clears selection and resumes cleanly; existing real ordinary-door and ordinary-prop interaction/highlight regressions remain green through the unchanged shared contract; and the user/playtester confirms the targeting/highlight behavior remains understandable in ordinary play.

**Automated:** the existing Application interaction regression is expanded around the real Application → WorldSession → Player path and the 6.1 sensor fixture. The authoritative all-tests barrier must also keep the dedicated real Door and Props suites green so hardening the selector cannot silently fork their interaction behavior.

**Manual:** accepted by the user on exact implementation head `220bdd1d6d9db257b975c71198e2b531117ae763` after GitHub Actions Test run #363 passed. Interaction Lab targeting, non-blocking sensor behavior, physical occlusion, range/highlight clearing, fresh-F use, state invalidation, and ordinary movement/look all passed the requested player-facing check.

## 6.2 Door completion `[x]`

Keys/locks/barred restrictions, authoring properties, obstruction behavior, NPC use, events, save state. Complete the mapper-facing external-model/variant authoring path so wooden, metal, ornate, window-like, or other compatible opening presentations can reuse the same ordinary door/opening gameplay archetype. Openable windows are variants of this system, not a separate gameplay subsystem.

The existing `VarkOrdinaryDoor` remains the single ordinary opening owner. Its previously proven physical leaf, obstruction latch/reversal, vision blocking, acoustic openness, door-owned navigation link, NPC smart-link traversal, interaction highlight, use sound, terminal state events, and direct semantic restore remain unchanged for unrestricted doors.

6.2 adds semantic restriction state directly to that owner:

- `locked` and `barred` are saved runtime truth. A restricted opening must be stably closed; restore rejects impossible open/moving restricted snapshots.
- `required_key_id` is authored configuration. A locked door asks the requester for `has_semantic_possession(required_key_id) -> bool`; a successful key query clears the lock without consuming possession. The door does not implement inventory, key pickup, selection, or ownership; 6.3 will make player/NPC possession real through this narrow query.
- a locked door with no usable key stays locked until world/mission logic calls the semantic lock setter. A barred opening ignores keys and stays closed until explicitly unbarred.
- ordinary player interaction on a restricted door remains targetable and emits one detached `door.access_denied` fact rather than disappearing from selection. Lock/bar changes emit `door.restriction_changed`; physical terminal motion continues to emit `door.state_changed`. Restore emits none of these consequences.
- the door-owned `NavigationLink3D` is disabled while locked/barred and re-enabled from the same restriction truth after unlock/unbar. A late NPC open request that is denied returns `false`; the guard aborts the local smart-link traversal instead of retrying the door forever. Unrestricted guard use remains the existing path.

The new TrenchBroom/FuncGodot point class is `vark_opening`. It instantiates the real `OrdinaryDoor.tscn`, directly exposes required `persistent_id`/`door_id`, `opening_variant`, `visual_model_path`, tint/motion/noise properties, starting lock/key/bar configuration, and mapper yaw, and applies them onto that same scene instance. `visual_model_path` accepts a compatible Godot `Mesh` resource path; `opening_variant` is descriptive presentation/content metadata only. Wooden, metal, ornate, window-like, or other compatible presentations therefore do not create new gameplay classes. The scene-owned collision/gameplay leaf remains authoritative, so a replacement model must be compatible with the authored opening volume.

Door snapshots now capture `phase`, `open_fraction`, `motion_blocked`, `locked`, and `barred`. The loader also accepts the previous three-field snapshot as safely unrestricted, so this additive capability does not require a global save-format bump. Authored mission changes that make an old in-mission save semantically unsafe still use the existing mission-content revision rule.

**Done when:** the real Door Lab and authoring suites prove unlocked/locked/keyed/barred behavior, restriction/denial/state events, physical obstruction/reversal, unrestricted NPC use plus fail-closed denied NPC requests, persistent restriction quicksave/quickload with no restore-time event replay, legacy unrestricted snapshot compatibility, external model-path/variant reuse on the same archetype, and real FuncGodot construction of `vark_opening`; existing Door/Nav/Perception and Integrated Slice regressions stay green; and the user confirms the restricted/unrestricted player-facing door behavior is understandable.

**Automated:** accepted on exact fix-forward implementation head `d8b6c52e9acbb2d7cb31c790da2501cdd1ac259d` by GitHub Actions Test run #365. The real Authoring suite exported and built `vark_opening` through Vark's FGD/FuncGodot path; Door Lab passed locked denial, semantic-key unlock, barred/unbar behavior, detached restriction/denial events, obstruction/reversal, model-path variants, legacy/new snapshots, and application quicksave/quickload with no restore replay. Existing Navigation and Door/Nav/Perception integration suites remained green, and the authoritative run ended with `ALL TEST SUITES PASSED`.

**Manual:** accepted by the user on current 6.2 implementation/docs lineage after exact-head GitHub Actions run #366 was green. Door Lab preserved ordinary open/close, obstruction/reversal, highlighting and controls; locked and barred openings remained targetable but refused repeated F without opening.

## 6.3 Loot, keys, minimal possession, and run-stat ownership `[x]`

Collected loot becomes abstract recorded value/count.

Introduce only minimal semantic possession needed now, such as owns key/content item X, loot possession/value, and small abstract mission-item ownership when genuinely needed.

Doors/mission logic query semantic possession rather than depending on future inventory UI/selection.

When the first mission statistic becomes real (loot is likely first), introduce a tiny semantic `MissionRunState`/statistics owner for run counters rather than letting each subsystem keep duplicated counters or making the future results UI scrape private state. Later kills/knockouts/alerts/time extend the same owner as they become real.

Because collecting authored loot removes an authored world instance, implement the minimal removed-authored tombstone representation and prove collected loot remains absent after restore without replaying collection/stat consequences.

The bounded 6.3 grammar is intentionally smaller than the later inventory system:

- `PlayerSemanticPossession` owns only a sorted set of semantic possession IDs. The player exposes `has_semantic_possession(id)` for doors/mission logic and `grant_semantic_possession(id)` for collected keys or small mission items. There is no selection, equipped slot, quantity UI, consumption, purchase/carryover, or general inventory menu in this item.
- player possession is embedded in the existing player semantic snapshot. New snapshots add `semantic_possession`; pre-6.3 six-field player snapshots remain valid and restore as empty possession. Player restore validation explicitly checks the possession set so traversal normalization cannot mask a lost key.
- `VarkMissionRunState` is the single mission-run statistics owner introduced with exactly `loot_count` and `loot_value`. `WorldSession` owns it and exposes a detached summary; later statistics extend this owner instead of duplicating counters in loot, objectives, or results UI.
- `VarkCollectible` is the minimal physical authored pickup archetype for `key`, `mission_item`, and `loot`. Every ordinary collectible requires a reusable `VarkCollectibleAsset` backed by an imported `.obj`/`.glb`/`.gltf` model plus authored collision/label offsets; the old universal generated pickup block is not a content fallback. Each asset also authors a larger optional interaction-proxy box independent of physical collision; the selector queries these proxies on a dedicated non-solid physics layer while preserving real-body first-hit blocking. The gameplay archetype reuses center-view/F interaction and the accepted fullbright highlight. Keys/mission items become semantic possession IDs; loot becomes only abstract MissionRunState count/value.
- collection is one session-owned cross-system mutation: validate the authored persistent pickup, remove it from the entity registry, grant possession or record loot, add its persistent ID to authored tombstones, disable/remove its world presentation, then queue one detached `pickup.collected` fact. Collection never turns loot into a carried rigid body or a temporary inventory object.
- `object_existence.authored_tombstones` is now the supported representation for permanently removed authored entities. Tombstones are unique non-empty persistent IDs. Save validation accepts them, runtime-created persistent entities remain unsupported, and restore removes the matching authored instances **before** semantic snapshots are applied. A tombstoned ID may not also have a persistent snapshot.
- the new `mission_run_state` world-state section is optional for backward compatibility: pre-6.3 saves restore zero loot; new saves capture the run owner directly. No global save-format bump is required because older supported snapshots retain unambiguous default meaning.

The focused fixture is **Development Launch → Loot/Key Lab**. It contains the real player, an imported-model brass `key.lab`, imported-model loot worth 25 and 75, and the real 6.2 locked ordinary door requiring `key.lab`. The fixture also guards representative item scale against the removed 55 cm placeholder-block mistake. A world-space diagnostic label shows whether the key is owned and the current abstract loot count/value.

**Done when:** the production F interaction collects the authored key into semantic possession; the real locked door unlocks by querying that possession; two authored loot pickups disappear and produce exactly 2 / 100 on one MissionRunState; collection queues detached semantic facts once; quicksave contains possession, run stats, and tombstones; quickload reconstructs a fresh world with the three collected authored pickups still absent, restored key/loot truth, no transient post-save mutation, and no replayed collection consequences; pre-6.3 player/run-state saves remain supported; existing persistence/door/interaction suites remain green; and the user confirms the player-facing key/loot/door behavior is understandable without inventory UI.

**Automated:** accepted through interaction-proxy implementation head `e30fe3d219f83c99d569bd4c2cae4a0a525140a8` by GitHub Actions Test run #384. The authoritative Application suite preserved realistically scaled imported brass-key/gold-cup/silver-candlestick presentation, proved each tiny item can expose a materially larger non-solid interaction-only proxy, and deliberately aimed 11 cm beside the brass key so the center ray missed its real 14 cm physical box but still selected the key through the proxy. The existing generic sensor-Area pass also remained green, proving arbitrary sensors still do not steal selection. Collection, semantic possession, keyed-door unlock, 2 / 100 run stats, tombstones, generation-specific quicksave/quickload, and no consequence replay all remained green. The run ended with `ALL APPLICATION TESTS PASSED` and `ALL TEST SUITES PASSED`.

**Manual:** accepted by the user after the imported-item scale and forgiving interaction-proxy follow-up. The user confirmed the Loot/Key Lab presentation/aiming behavior was good on the run #385 lineage.

## 6.4 Containers `[x]`

Physical opening/exposed contents where appropriate. Ordinary cabinets, chests, drawers, and furniture-like containers use reusable imported model assets rather than requiring bespoke gameplay code per visual model.

The corrected 6.4 architecture keeps one `VarkOrdinaryContainer` semantic/gameplay owner but removes the generic generated-furniture system. Each reusable `VarkContainerAsset` scene owns the physical/content-specific contract:

- imported static/body mesh;
- imported moving-part mesh;
- authored static and moving collision;
- authored mechanism pivot and closed pose;
- authored `OpenPose` transform;
- authored `ContentsAnchor`, parented to the moving mechanism or stationary body according to the real furniture;
- asset-specific presentation/material defaults and model identity.

The gameplay container owns only persistent identity, center-view/F interaction, highlight routing, `closed / opening / open / closing` phase, normalized progress, semantic sound/state events, and save/restore. It interpolates the asset's authored closed/open mechanism transforms; it does **not** calculate furniture size, panel dimensions, hinge positions, drawer depth, or an open transform from a universal box.

The focused **Development Launch → Container Lab** uses three representative imported assets at human scale:

- a roughly 0.85 m-wide desk/drawer carcass with an imported full drawer tray whose contents anchor moves with it;
- a roughly 0.90 m-wide chest whose imported lid rotates around an authored rear hinge while contents stay in the base;
- a roughly 0.75 m-wide / 1.35 m-tall cabinet whose imported door rotates around an authored side hinge while contents stay on the shelf.

Container contents are ordinary imported-model `VarkCollectible` objects. There is no container-owned item list and no universal generated pickup block.

Save ownership stays compositional. The container snapshot stores only mechanism phase/progress. Individual contents retain their own persistent IDs; collected contents use the existing tombstone/possession/MissionRunState owners.

**Done when:** the Container Lab proves all three variants are imported-model asset scenes with authored pivots/open poses/collision/contents anchors; representative closed visual bounds remain plausible relative to the 1.49 m player; the closed drawer physically blocks access to contents; F moves the full imported drawer tray rather than a floating front plate; its imported contents move with it and become independently targetable; chest/cabinet open through real rear/side hinge rotation; imported loot collects through 6.3; quicksave/quickload preserves open state and child tombstones without replay; existing door/prop/interaction/save suites remain green; and the user confirms scale and movement read as real furniture rather than oversized sliding panels.

**Automated:** accepted on imported-asset implementation head `abf4d770345dbfb4431987e23b73fd45ed2e9280` by GitHub Actions Test run #382. The authoritative Application suite proved all three container variants use imported body/mechanism asset scenes rather than generated furniture, enforced human-scale visual bounds relative to the 1.49 m player, enforced handheld imported collectible scale, proved closed-drawer occlusion, full-tray movement with a moving contents anchor, rear-lid and side-door hinge rotation from authored pivots/open poses, imported-loot collection, semantic events, and save/restore with child tombstones/no replay. Existing full regression coverage remained green; the run ended with `ALL APPLICATION TESTS PASSED` and `ALL TEST SUITES PASSED`.

**Manual:** accepted by the user after the imported-model container replacement and collectible interaction-proxy follow-up. Scale, drawer/chest/cabinet motion, exposed contents, and normal interaction were confirmed good on the run #385 lineage.

## 6.5 Switches and switchable/extinguishable lights `[x]`

Integrate with gameplay light state, sound/events, saves, and the mapper-facing TrenchBroom workflow.

The mapper contract is intentionally semantic rather than node-path based:

- `vark_gameplay_light` is a TrenchBroom point entity backed by the real `VarkGameplayLight` scene. It owns `persistent_id`, unique `gameplay_light_id`, shared author-facing `control_id`, initial on/off state, gameplay exposure strength, rendered child-emitter range/energy/color/shadows, a reusable imported fixture-asset scene, and optional direct extinguish interaction. The mapper entity origin places the fixture; the fixture asset owns an explicit `EmitterAnchor` inside the luminous part plus authored solid collision.
- `vark_switch` is a TrenchBroom point entity backed by one reusable imported-model switch scene. It owns only `switch_id`, `control_id`, presentation/model paths, lever poses/timing, and use-sound strength. It is not a second persistent truth owner.
- Any number of lights may share one `control_id`. A switch with the same `control_id` toggles the full group. Mappers do not wire Godot signals, NodePaths, or per-light target slots.
- The saved gameplay-light objects remain the authoritative on/off state. Each switch derives its lever pose from those lights every runtime frame, so quickload/restart cannot restore a contradictory switch pose.
- `VarkGameplayLight.set_enabled_state()` never hides the fixture object. ON/OFF drives semantic gameplay exposure, actual world-emitter energy, and only the fixture asset's authored lit-surface appearance. The fixture body keeps its imported/authored PBR materials unchanged across ON/OFF. The fixture's coarse player collision remains excluded from its own exposure rays so the luminous glass volume does not self-block, while a separate private physics-layer occluder generated from the opaque body mesh restores metal/frame shadowing to semantic exposure. Because the real shadow-casting emitter sits inside the fixture and can self-shadow its frame, each fixture may provide a small unshadowed visual-only self-fill at the same `EmitterAnchor`; that helper is restricted to a private render layer carried only by the fixture body, so it illuminates the lamp itself without lighting the room or contributing gameplay exposure. ON enables world emitter + self-fill + bright/emissive glass/flame; OFF zeros both emitters and changes only the designated lit surface to its dark/hidden-off appearance while the body remains normally shadeable by other scene lights. It emits detached `light.state_changed` facts. `vark_switch` uses that same operation and emits `switch.used`; direct extinguish uses the same operation with source `direct`.
- A directly extinguishable light enables the existing dedicated non-solid interaction-proxy layer around its fixture. While targeted, the **entire visible fixture** follows the same accepted Thief-style interaction highlight as doors/containers/pickups: body and lit surface become unshaded/fullbright and receive no scene shadows, while authored body albedo/emission and ordinary cast-shadow behavior remain unchanged. Losing target restores authored PBR shading immediately. Ordinary non-interactable gameplay lights do not participate in center-view interaction.

The focused **Development Launch → Switch/Light Lab** contains two persistent room lights sharing `control_id = lab.room`, one imported wall switch with the same control ID, and one separately persistent directly extinguishable lamp. The real gameplay-exposure/light-gem path makes the stealth consequence visible.

**Done when:** the exported Vark TrenchBroom FGD exposes `vark_gameplay_light` and `vark_switch`; a real FuncGodot build of mapper-style source creates two lights and one switch with the authored IDs/control group/model properties and no Godot-side wiring; fresh F on the lab switch turns both room lights off together, changes actual gameplay exposure, moves the lever to the derived off pose, emits semantic state/use events, and does not create separate switch save state; fresh F on the extinguishable fixture turns off that same persistent gameplay-light truth; quicksave captures all three light states; deliberate post-save re-enable can diverge; quickload reconstructs all three lights off, derives the fresh switch pose from restored lights, and replays no switch/light consequences; existing exposure, interaction, persistence, authoring, and full regression suites stay green; and the user confirms the mapper/player-facing behavior.

**Automated:** accepted on fixture-shadow exposure implementation head `d8e9e85bbb09480d66ec4567fc486acda6c94b32` by GitHub Actions Test run #407. The Application suite proves the coarse player-solid fixture collision remains excluded so the luminous volume does not self-occlude, a private exposure-only trimesh generated from the opaque body blocks semantic exposure through metal/frame geometry while leaving a real opening unblocked, and nonzero fixture-only self-fill contributes zero gameplay exposure. The switch/exposure regression now probes a known open emission path rather than the lamp's deliberately shadowed opaque-front direction. Existing interaction highlight, emitter/glass ON/OFF, save/load, TrenchBroom control-ID authoring, visibility, movement, and the full regression suite remained green; the run ended with `ALL TEST SUITES PASSED`. The Application suite proved the fixture keeps the accepted authored emitter position and solid collision, adds a private unshadowed render-only self-fill that illuminates only the normally shaded fixture body, and keeps that body on the ordinary render layer so other scene lights can still illuminate it. The ON/OFF regression proves the body material instance, albedo, and shading mode remain unchanged; only the designated glass/emitter state changes, while both the real world emitter and fixture-only self-fill go to zero when OFF. Existing gameplay exposure, save/load, TrenchBroom control-ID authoring, visibility, and all full regression suites remained green. The run ended with `ALL APPLICATION TESTS PASSED`, `ALL VISIBILITY TESTS PASSED`, and `ALL TEST SUITES PASSED`.

**Manual:** accepted — user/playtester. After the fixture-shadow exposure correction passed automated validation, the user reported the Switch/Light Lab behavior all good. Development Launch → **Switch/Light Lab**. With the lamps ON, stand directly in a visible shadow cast by a lamp's opaque body/frame, especially on the wall/mount side: the light gem/exposure must drop instead of reporting strong exposure through the metal fixture. Move back into a visibly illuminated path and confirm exposure rises again. Stand facing the wall switch: it should highlight normally. Press F once; both room emitters must disappear and the light gem/exposure must fall, while each lamp object remains visible with its glass/lit surface visibly dark and the imported lever moves to its off pose. Compare the metal/frame before and after: its base colors/material must not switch with the light state; when ON it should instead be illuminated naturally by the lamp's own fixture-local light and any other scene lights. Press F again to restore both. Walk to the separate right-hand lamp; confirm you cannot walk through its housing, then aim at its fixture: the whole lamp, not only the glass, must become fullbright with no received shadows while retaining its body colors. Press F to extinguish it directly. It must stop contributing visible/gameplay light through the same state, not leave a visually dark but gameplay-bright mismatch. Movement/look and ordinary interaction must remain normal.

## 6.6 Physical prop completion `[x]`

Complete the accepted Phase 3 ordinary-prop contract rather than replacing it. Support relationships, exact settled stacks, moving/support-loss behavior, prop-backed traversal, single-slot carried-Junk HUD ownership, view-derived F throw / R gentle release, semantic impact noise, always-top-up rigid translation, and carried/moving semantic save state remain shared `VarkOrdinaryProp` behavior.

The production-completion additions are deliberately narrow:

- TrenchBroom exposes one `vark_prop` point entity backed by `OrdinaryProp.tscn`. It owns stable `persistent_id` + unique `prop_id`, a presentation-only `prop_variant` label, compatible external `visual_model_path`, authored box `collision_size`, base color, and the small throw/impact tuning values already owned by the shared prop. Variant/model choice never selects a second gameplay class.
- `VarkOrdinaryProp` resolves mapper-authored external Mesh paths at runtime with the scene's default Mesh as fallback, preserves the accepted shared default box shape when authored dimensions are unchanged and localizes the shape only for real per-instance size variants, and keeps model/collision configuration out of semantic save snapshots because the authored world rebuild owns configuration while semantic snapshots own runtime phase/transform/velocity.
- Prop Lab now includes both standard/tall compatible imported variants and the real ordinary door. A settled prop must be real walkable support and must stop the same physical door sweep; removing the blocker lets that door continue. No door-side prop special case or prop-specific obstruction subsystem is introduced.
- The Phase 3 central ownership rule remains unchanged: carried Junk suppresses ordinary world/hand-occupying actions centrally while locomotion/traversal remain available.

**Done when:** exported Vark FGD contains `vark_prop`; a real FuncGodot build creates standard and tall ordinary props with distinct stable IDs/model paths/collision dimensions but the same gameplay script; compatible model replacement preserves semantic identity; edge-supported props and stacks remain exact while settled; stacked props provide real player support/climbing utility; removing support activates the upper prop without scatter/tumble; F/R preserve the accepted carried-Junk HUD/view-derived throw-release/noise behavior; a side-positioned settled prop blocks the shared ordinary-door physical sweep and removal resumes it, while a crate resting on the door's top edge yields into unsupported physics instead of pinning the leaf; carried and moving prop save/restore policies remain green; and the user accepts the focused Prop Lab behavior.

**Automated:** accepted on corrected support-motion implementation head `a26d0045a322d1ec5248fb596514532688710dab` by GitHub Actions Test run #420. The Props suite proves both sides of the door/prop contract: a side-positioned settled crate still latches the shared ordinary-door sweep as an obstruction, while a crate genuinely supported on the leaf's top edge is identified through RID-based prop support ownership, released into the existing `unsupported` rigid-body path, and no longer pins the door. The same run also kept the accepted edge-support, dynamic-rest, carry/release/throw, moving-prop mantle/support-invalidation, Authoring, Application, Movement, and full regression suites green, ending with `ALL TEST SUITES PASSED`.

**Manual:** accepted — user/playtester. After the top-supported-crate correction and green run #421, the user reported the Prop Lab behavior all good. Development Launch → **Prop Lab**. Confirm the standard and tall crates both behave as the same ordinary Junk class despite different model/collision dimensions. Stack/use crates as walkable climbing aids; settled stacks should stay still. Remove a lower support and confirm the upper crate drops without tumbling/scattering. Carry a crate: bottom-center Junk presentation appears, ordinary world/hand interaction is suppressed, movement remains normal, F throws and R gently releases along the current view with R materially gentler/quieter. Open the lab door, place a crate in its side swing, and close it: the door must stop on the crate; remove the crate and the same door must finish closing. Then balance/place a crate on the door's top edge and operate the door: the leaf must move, the crate must release/fall through ordinary prop physics, and the door must not remain pinned merely because it was supporting the crate. Quicksave/quickload representative carried and moving props should preserve their existing semantic behavior.

## 6.7 Configured breakables/effects `[x]`

Only explicitly authored damageable/breakable objects respond. No universal destruction/fire simulation.

The first production slice is intentionally small and responder-driven:

- `VarkConfiguredBreakable` is an authored persistent world object with stable `persistent_id` + mission-facing `content_id`, one accepted `effect_id`, a numeric break threshold, authored collision dimensions, and optional compatible external-model presentation. It alone exposes `apply_gameplay_effect(effect_id, strength, source_position)`.
- Ordinary physical-prop impacts reuse the existing rigid-body contact/impulse path and call the breakable's `receive_prop_impact()`, which converts real contact impulse magnitude into the generic `impact` effect. No global collision callback scans the world for damageability.
- Effects are fail-closed: wrong effect IDs or sub-threshold strengths do nothing. Once broken, the authored object becomes non-solid/non-visible, emits exactly one detached `breakable.broken` semantic event with stable IDs/effect data, and repeated effects are idempotent.
- Broken state is persistent semantic truth. Save capture stores only `{"broken": bool}`; restore derives collision/presentation and replays no break consequence. Authored configuration remains mission content rather than duplicated save truth.
- Normal architecture and ordinary doors expose no damage/effect responder seam, so they do not become destructible merely because an effect exists.
- TrenchBroom exposes one `vark_breakable` point entity backed by `ConfiguredBreakable.tscn`. Mapper properties cover persistent/content identity, accepted effect, threshold, optional model path, collision size, and base presentation color.

The focused **Development Launch → Breakable Lab** contains one loose ordinary Junk prop, one configured red breakable panel, and one ordinary door control. The player can pick up the loose prop and F-throw it into the panel through the real carried-Junk/rigid-impact path; only the configured panel should break.

**Done when:** exported Vark FGD contains `vark_breakable`; a real FuncGodot build constructs the configured responder with authored identity/effect/threshold/collision values; wrong/sub-threshold effects leave it intact; a real thrown ordinary prop crosses the configured threshold and breaks it through physical contact; the broken state removes only that object's world collision/presentation, emits one detached semantic event, is idempotent, and is captured/restored without consequence replay; an ordinary door remains nonbreakable; existing props/doors/save/application/authoring regressions remain green; and the user accepts the focused Breakable Lab behavior.

**Automated:** accepted on configured-breakable implementation head `94952f96e382fe1e0a2734d230d21d8afaaa2437` by GitHub Actions Test run #437. The Authoring suite proves `vark_breakable` exports through the Vark FGD and a real FuncGodot build applies authored persistent/content identity, accepted effect, threshold, and collision dimensions. The Application suite proves wrong/sub-threshold effects fail closed, a real carried-Junk F throw breaks the configured panel through ordinary rigid-body contact impulse, an ordinary door exposes no effect/damage responder, exactly one detached `breakable.broken` event carries stable IDs/effect data, repeated effects are idempotent, and broken semantic state is captured/restored without consequence replay. Existing props, doors, save/application, authoring, movement, and the full regression suite remained green; the run ended with `ALL TEST SUITES PASSED`.

**Manual:** accepted — user/playtester. After green exact-head run #438, the user reported the focused Breakable Lab behavior good. Development Launch → **Breakable Lab**. Pick up the loose crate with F and throw it with F into the red panel. The panel should disappear/stop blocking after a sufficiently strong hit. The ordinary door beside it must remain an ordinary nonbreakable door. Restart the lab and use R/gentle handling or weak incidental contact: the panel should not break from a clearly weak touch; a committed F throw should. Movement, carried-Junk behavior, and unrelated door interaction must remain normal.

**Phase gate:** systemic world interaction works without disconnected controls or unrealistic always-active rigid bodies; key/loot possession works without a temporary inventory architecture; mission-run counters have one owner; and permanently removed authored content restores correctly.

---

# Phase 7 — Mission logic and provisional authoring API

Goal: promote proven internal semantic contracts into a small mission logic system and a provisional script surface.

## 7.1 Author-facing semantic event bus `[x]`

Promote the already-proven world-owned semantic queue instead of introducing a second dispatcher. `WorldSession` owns one fresh `VarkMissionEventBus` per world lifetime; teardown invalidates retained bus references and replacement creates a distinct instance.

The author-facing bus deliberately exposes only:

- `subscribe(event_name, handler)` / `unsubscribe(...)` for synchronous consequence handlers participating in the current semantic drain;
- `emit(event_name, detached_payload)` for mission-defined or promoted semantic facts, still subject to the current `PLAYING` lifecycle/session boundary;
- `get_known_event_names()` as useful documented vocabulary for proven facts such as gameplay sound, pickup collection, door/container/light/switch changes, breakage, guard communication/alarm, objective-completion request, mission-exit request, and mission completion;
- `get_recent_trace()` as a bounded detached diagnostic history containing sequence, name, payload, current session identity, handler count, and the controlled consequence pass that processed the event.

This wrapper does **not** expose private subsystem signals, mutable gameplay Nodes, a scheduler, arbitrary delayed callbacks, or an alternate mutation path. Mission-defined event names remain permitted; payloads still fail closed on live `Object`/`Callable`/`Signal`/`RID` values. The existing FIFO order, re-entrant append, late controlled physics drain, synchronous-handler acknowledgement, lifecycle gating, replacement-world isolation, stable-boundary publication, and runaway-cascade guard remain authoritative inside `WorldSession`.

Long-running reactions are still explicit semantic state advanced on future gameplay ticks; they do not suspend/await inside a current event drain.

**Done when:** a READY world owns one bus but cannot emit ordinary semantic work until PLAYING; authors can subscribe before play, then emit a detached mission-defined fact that reaches handlers only at the controlled pass; source payload mutation and handler-local payload mutation cannot alter the queued/trace copies; nested author emission preserves FIFO append; the promoted known vocabulary contains representative current facts without private signals; trace history is detached/bounded/useful and survives a guarded failure for diagnosis; teardown invalidates a retained old bus; replacement creates a fresh isolated bus; existing internal event users and all save/stable-boundary regressions remain green.

**Automated:** accepted on author-facing event-bus implementation head `eb8e16efbb507181b4ef97f5b0ab0abf128a3ebe` by GitHub Actions Test run #451. The focused Application regression proves one world-scoped `VarkMissionEventBus`, READY subscription with PLAYING-only emission, representative known vocabulary, mission-defined event names, detached source/handler/trace values, nested FIFO append, live-object payload rejection, bounded diagnostic trace, teardown invalidation, and fresh replacement isolation. The existing Phase 3.2 regression additionally proves the trace remains available after the runaway-cascade guard fires without publishing a false stable boundary. Existing semantic-event ordering/lifecycle, save/stable-boundary, application, authoring, gameplay, and full regression suites remained green; the run ended with `ALL TEST SUITES PASSED`.

**Manual:** none required for this architecture-only step. No player-facing control or feel changes are intended.

## 7.2 Typed mission facts `[x]`

`MissionDefinition` now owns explicit `mission_fact_declarations`. Every declaration contains exactly `key`, `type`, `default`, and `scope`; duplicate/blank keys, unsupported types/scopes, and default/type mismatches fail mission-definition validation before the world becomes authoritative.

The supported value types are deliberately small: `bool`, `int`, `float`, and `string`. The only scopes before Phase 12 are:

- `mission` — durable mission-defined truth captured in active-gameplay save state and restored into a fresh world;
- `runtime` — current-world mission-defined working state that starts from its declared default on build/replacement/restore and is intentionally absent from save snapshots.

`VarkMissionFacts` is one world-scoped semantic owner. Unknown or wrong-type assignment requests fail before they enter the semantic queue. Valid requests go through `WorldSession.queue_mission_fact_set()` and the existing `mission.fact_set_requested` semantic consequence path; the owner changes only during the controlled drain. A real change appends one detached `mission.fact_changed` fact carrying key/value/scope. Assigning the existing value is idempotent and emits no false change event.

Mission facts represent genuinely mission-defined variables. They do not mirror door open state, actor life/awareness, possession, objective state, run statistics, or other system-owned truth unless a mission deliberately declares a separate derived/latched meaning with distinct semantics. There is no campaign scope; attempting to declare one fails closed rather than turning `MissionFacts` into temporary campaign storage.

Save capture stores only mission-scope key/value truth under the detached `mission_facts` section. Runtime-scope values are reset from declarations in the fresh restore world. Missing pre-7.2 `mission_facts` sections resolve to the declaration defaults, preserving backward compatibility for existing missions whose declarations are empty; semantically incompatible authored declaration changes still belong under the existing `mission_content_revision` policy.

**Done when:** valid typed declarations build from `MissionDefinition`; invalid duplicate/campaign/wrong-default declarations fail closed; one READY world exposes defaults but cannot mutate them through normal gameplay dispatch; unknown/wrong-type requests are rejected before queueing; valid requests become authoritative only at the controlled consequence pass and emit ordered `mission.fact_changed` facts; idempotent writes emit no false event; save capture includes only mission-scope facts; fresh restore reapplies mission-scope truth while runtime facts remain at defaults; malformed saved fact snapshots reject unknown/type-invalid data; teardown clears the owner; and existing event/save/application/gameplay regressions remain green.

**Automated:** accepted on typed-mission-facts implementation head `9d5e92517a254be9ff11c8ba5adf1c084effe877` by GitHub Actions Test run #467. The focused Application regression proves valid declaration/default construction; duplicate key, campaign-scope, and default/type mismatch rejection; unknown/wrong-type assignment rejection before queueing; PLAYING-only controlled mutation; ordered detached `mission.fact_changed` emission; idempotent no-change writes; mission-scope-only save capture; fresh-world restore of mission truth with runtime facts reset to defaults; malformed saved fact rejection; and teardown lifetime cleanup. Existing semantic event, snapshot/restore, compatibility, application, gameplay, authoring, movement, and full regression suites remained green; the run ended with `ALL TEST SUITES PASSED`.

**Manual:** none required for this architecture-only step. No player-facing behavior is intended.

## 7.3 Objective system `[x]`

Extend the accepted Phase 3.10 owner instead of introducing a second objective authority. One `VarkSimpleObjectiveState` still owns route objective truth, exit gating/counters, mission-complete truth, save state, and public objective/exit queries; 7.3 generalizes that same owner to multiple declared objectives.

Each authored `objective_declarations` entry contains exactly `objective_id`, `text`, `optional`, and `initial_state`. The primary legacy `objective_id` must still be present. Initial state is `active` or `inactive`; runtime objective state is one of `inactive`, `active`, `complete`, or `failed`.

Supported transitions remain explicit semantic consequences:

- `objective.activate_requested { objective_id }`: inactive → active;
- `objective.complete_requested { objective_id }`: active → complete;
- `objective.fail_requested { objective_id }`: active → failed;
- each real transition appends one detached `objective.state_changed { objective_id, from_state, to_state, optional }`;
- terminal/invalid/idempotent transition requests do not manufacture extra changes.

"Dynamic" in this phase means a declared inactive objective can become active later through the semantic event path. 7.3 does not add arbitrary runtime-created objective definitions; Phase 8 can pull that forward only if a real mission requires it.

Exit gating is derived from objective ownership, not mirrored mission facts: every non-optional objective must be complete. Optional objectives may remain inactive, active, complete, or failed without blocking route completion. A failed required objective keeps the exit locked but does not yet invent a universal mission-failure transition; mission fail conditions remain later rule/content work.

The existing single-objective contract remains backward compatible. Empty declarations synthesize the original required active `objective_id`; existing `query_objective()`, `query_exit()`, objective-complete snapshots, exactly-once `mission.completed`, and Phase 3/4 save fixtures remain valid. New snapshots additionally carry the complete objective-state table plus activation/failure counters while preserving the established primary-objective completion counter; restore accepts the old eight-field single-objective snapshot form for compatibility.

Objective Lab now declares one required active route objective, one initially inactive optional objective, and one initially active optional objective. It also exposes OPTIONAL START/OPTIONAL COMPLETE semantic trigger pads so dynamic activation is visible in the focused fixture.

**Done when:** required/optional declarations build under one existing objective owner; public queries expose inactive/active/complete/failed plus optional state and still fail closed for unknown IDs; queued activation/failure/completion do not mutate before the controlled consequence pass; real transitions emit ordered detached `objective.state_changed` facts; optional completion/failure never becomes exit authority; the required objective alone can unlock the current lab exit; repeated/invalid terminal transitions are idempotent; the expanded semantic snapshot restores all objective states/counters without event replay while old single-objective snapshots remain accepted; existing Integrated Slice objective/save behavior stays green; and the user accepts the focused Objective Lab presentation/flow.

**Automated:** accepted on corrected objective-lifecycle implementation head `0dececd840b536339d142f12f6aed610f6ccc0b2` by GitHub Actions Test run #476. The Objectives suite retains the Phase 3.10 early-exit, required-objective completion, exactly-once `mission.completed`, unknown-query, and semantic-trigger proofs while additionally proving declared inactive/active optional objectives, controlled activation/failure/completion, ordered detached `objective.state_changed` events, and optional non-gating. The initial run exposed that the established `objective_completion_count` specifically meant primary route-objective completion; the fix-forward preserves that meaning instead of counting optional completions. Existing Integrated Slice/Application semantic snapshot restore, save compatibility, event, gameplay, authoring, movement, and the full regression suite remained green; the run ended with `ALL TEST SUITES PASSED`.

**Manual:** accepted — user/playtester. After green exact-head run #477, the user reported the extended Objective Lab flow all good: required EXIT gating remained intact while OPTIONAL START/OPTIONAL COMPLETE exposed the optional lifecycle without taking exit authority.

## 7.4 Small data rule system `[x]`

`MissionDefinition.mission_rule_declarations` now owns a deliberately small declarative grammar. Each rule contains exactly `rule_id`, `event_name`, `conditions`, and `actions`. Rule IDs are stable authored diagnostic identity; duplicate/blank IDs and blank source event names fail definition validation.

The supported conditions are intentionally finite:

- `event_payload_equals { key, value }` — compare one detached literal against the triggering event payload;
- `fact_equals { key, value }` — compare one typed literal against an already-declared `MissionFacts` key.

The supported actions are intentionally finite:

- `set_fact { key, value }` — queue the existing typed mission-fact mutation request;
- `emit_event { event_name, payload }` — append one detached semantic event through the existing world-owned event bus.

This is enough to express common event → conditions → actions reactions and to request existing objective/door/etc. semantic behavior by emitting their public request events. There is no expression language, arithmetic, loops, arbitrary method calls, Node access, callback storage, script snippets, reflection, implicit entity mutation, or author-facing scheduler.

`VarkMissionRules` is one stateless world-lifetime rule layer owned by `WorldSession`. It subscribes to authored source events through the existing `VarkMissionEventBus`, evaluates current event payload + typed fact truth synchronously during that same controlled semantic drain, and **queues** actions back into the existing event cascade. A matching rule therefore cannot mutate durable truth before the current controlled consequence pass reaches its queued actions.

7.4 deliberately does not define one-shot/repeat policy, cross-rule priority, rule persistence, delayed actions, or long-running behavior; those remain Phase 7.6. The current 7.4 rules are immediate/stateless every-match reactions. If content needs delay or multi-step progress before 7.6, that progress must be explicit semantic fact/objective stage driven by later ordinary gameplay events—not an `await`, timer continuation, hidden coroutine, or suspended callback.

Rule validation cross-checks fact conditions/actions against the already-declared typed facts and rejects unknown facts or wrong literal types. `emit_event` payloads must be detached rule data. Unsupported condition/action kinds fail closed instead of growing the grammar opportunistically.

**Done when:** valid rule declarations build with one world-scoped rule owner; invalid unknown-fact/arbitrary-action/duplicate-ID/wrong-type declarations fail MissionDefinition validation; fact and event-payload conditions can independently prevent a match; a matching rule does not mutate before the controlled consequence pass; one matched rule can queue both a typed fact change and detached semantic event through the existing cascade; handler-local event mutation cannot alter authored rule data; the stateless rule layer introduces no hidden save section/continuation state; teardown invalidates it with the old world; and existing event/fact/save/gameplay regressions remain green.

**Automated:** accepted on small-rule-system implementation head `3c93e6e1465476e20ca6665cc222db119f9a2d66` by GitHub Actions Test run #485. The focused Application regression proves valid rule construction; rejection of unknown facts, arbitrary action kinds, duplicate rule IDs, and wrong typed literals; independent fact/payload condition misses; no pre-drain mutation; one matched rule queuing both typed `set_fact` and detached `emit_event` actions through the existing semantic cascade; authored payload detachment; absence of hidden `mission_rules`/continuation save state; and teardown invalidation. Existing semantic event/cascade/runaway-guard, typed-fact, save/restore, gameplay, authoring, movement, and full regression suites remained green; the run ended with `ALL TEST SUITES PASSED`.

**Manual:** none required for this architecture-only grammar step. Phase 8 will provide the first player-facing authored-rule proof.

## 7.5 Provisional VarkMissionScript API `[x]`

`WorldSession` now owns one fresh `VarkMissionScript` per world lifetime. Mission-authored GDScript can resolve that surface from a node in the current world with `VarkMissionScript.resolve(node)`; teardown invalidates retained references and replacement creates a distinct instance.

The provisional surface is deliberately limited to semantic/value ownership already proven before Phase 8:

- `query_fact()` / `get_fact()` expose declared typed mission-fact value/type/scope without exposing the `VarkMissionFacts` owner;
- `query_objective()`, `query_objectives()`, and `query_exit()` return detached snapshots from the existing single objective owner when present;
- `get_run_summary()` and `get_gameplay_time_seconds()` expose detached run statistics and current world simulation time;
- `get_event_bus()` reuses the accepted author-facing event bus, while `emit_event()` is a convenience over that same semantic queue;
- `set_fact()` and `activate_objective()` / `complete_objective()` / `fail_objective()` queue the existing typed fact/objective request events.

The API does **not** expose `WorldSession.world`, arbitrary mutable Nodes, persistent/content registry lookup, private door/light/guard methods, campaign state, application/top-level flow, timers, deferred callbacks, reflection, or a second scheduler. If Phase 8 discovers a real special behavior that needs another supported command/query, extend this provisional surface only at that proven semantic seam rather than adding generic reach-through.

Mutation timing remains the foundation contract: commands issued from `_process()`, arbitrary signal callbacks, resumed async code, or any other out-of-pass context can only queue semantic work. Durable truth changes during the later controlled consequence pass. Objective/fact/event identifiers and payloads remain stable semantic IDs plus detached typed values.

**Done when:** one READY world owns an active resolvable provisional API while ordinary commands remain lifecycle-rejected until PLAYING; fact/objective/exit/run/time queries return detached value data and unknown semantic IDs fail closed; `_process()`, signal-callback, and resumed-async mutation calls demonstrably leave authoritative truth unchanged until the next controlled consequence pass; custom event emission reuses the existing detached FIFO event path; objective commands reuse the existing objective request events; the public surface exposes no arbitrary Node/entity/application reach-through; save capture gains no hidden mission-script/continuation state; teardown invalidates retained references and replacement creates a fresh API; and existing event/fact/rule/objective/save/application/gameplay regressions remain green.

**Automated:** accepted on stabilized provisional mission-script implementation head `f41b755d066a83849b045c4f48a02df9e1980763` by GitHub Actions Test run #489. The focused Application regression proves READY/PLAYING lifecycle gating, safe world-node resolution and lifetime invalidation, detached typed fact/run/objective/exit queries, no generic mutable entity/world reach-through, `_process()` + arbitrary signal + resumed async/out-of-pass mutation requests remaining non-authoritative until the controlled consequence pass, detached custom event emission through the existing bus, queued objective activation through the existing request event, no independent mission-script/continuation save state, and fresh replacement isolation. The same full barrier kept event/fact/rule/objective/save/restore, awareness, gameplay, authoring, movement, and all other regression suites green; the run ended with `ALL TEST SUITES PASSED`. The fix-forward also retained section/persistent-ID restore mismatch diagnostics for future save-state failures without altering successful restore semantics.

**Manual:** none required for this architecture-only provisional surface. Phase 8.5 will provide the first player-facing/author-facing mission-specific GDScript proof.

## 7.6 Deterministic rule ordering and save state `[x]`

Rule ordering now stays inside the existing semantic event contract rather than adding a priority/scheduler layer:

- source events are processed in existing FIFO sequence order;
- rules subscribed to the same source event are evaluated in their `MissionDefinition.mission_rule_declarations` declaration order;
- all same-source rule conditions observe the semantic fact state that exists while that source event handler is running; actions from an earlier rule are only queued and therefore cannot mutate fact truth underneath a later declaration;
- each matched rule queues its actions in authored action order, so actions from rule A are appended before actions from later matching rule B;
- the entire resulting cascade still completes before `WorldSession` publishes the next stable gameplay boundary.

The only new execution policy is optional `repeat: bool`. Omitted `repeat` preserves 7.4 behavior and normalizes to `true`; `repeat = false` creates a one-shot rule. There is no numeric priority, expression language, timer, delayed callback, coroutine continuation, or hidden scheduler.

One-shot completion is world-semantic state. `VarkMissionRules` records only the stable IDs of configured one-shot rules that have successfully queued all of their actions. Stable save capture stores those IDs under a dedicated `mission_rules` section. Restore applies that state in the fresh non-playing world without replaying actions; a fired one-shot remains suppressed while repeating rules continue normally. Pre-7.6 snapshots with no `mission_rules` section restore as “no one-shots fired.” Unknown/duplicate/non-one-shot saved IDs fail closed, so changing rule identity/policy incompatibly remains subject to the existing `mission_content_revision` discipline.

Long-running or delayed mission behavior remains explicit facts/objective stages advanced by later ordinary semantic events. 7.6 does not add saveable runtime continuations.

**Done when:** same-event rules deterministically evaluate in declaration order against trigger-time fact truth; queued actions appear in FIFO declaration/action order and complete before the stable boundary; omitted `repeat` retains legacy repeating behavior; explicit repeating rules can fire again while one-shot rules execute once; fired one-shot IDs are detached save truth; fresh restore suppresses already-fired one-shots without consequence replay while repeating rules continue; malformed/unknown saved rule IDs fail closed; pre-7.6 saves without a rule section resolve to default unfired state; teardown/replacement isolate rule state with the world lifetime; and existing event/fact/script/objective/save/gameplay regressions remain green.

**Automated:** accepted on deterministic rule-state implementation head `b194bab98ce8e160c0e2d13f01f0a40d58b69c0d` by GitHub Actions Test run #491. The focused Application regression proves same-source declaration-order evaluation, authored action FIFO append order, trigger-time fact semantics despite earlier queued `set_fact`, legacy omitted-`repeat` compatibility, explicit repeat vs one-shot behavior, stable-boundary publication after the full cascade, detached fired-one-shot save state, unknown saved rule-ID rejection, fresh restore with no consequence replay, and restored one-shot suppression while repeating rules continue. The full barrier remained green with `ALL APPLICATION TESTS PASSED` and `ALL TEST SUITES PASSED`. Successful-run script-error signatures were unchanged from the preceding green run #490 and belong to existing deliberate failed-restore fixtures rather than 7.6.

**Manual:** none required for this architecture-only ordering/persistence step. Phase 8.3 will provide the first player-facing authored-rule proof.

## 7.7 Mission logic debugger `[x]`

`WorldSession` now owns one read-only `VarkMissionLogicDebugger` per world lifetime. A developer/mission author can resolve it from a node in the current world with `VarkMissionLogicDebugger.resolve(node)` and inspect one detached snapshot instead of reaching through private owners.

The debugger combines the existing semantic sources of truth rather than creating another gameplay system:

- current declared mission facts are shown as key/type/scope/default/current value;
- rule declarations are shown in authored declaration order with source event, repeat policy, conditions/actions, and current one-shot-fired state;
- `VarkMissionRules` keeps a bounded recent evaluation trace keyed by source event sequence + rule ID. Each evaluation says matched, skipped, condition-failed, or error; condition failures record the exact condition index/kind/key plus expected and trigger-time actual value/reason;
- the existing bounded mission-event trace remains the cascade authority, including sequence, payload, handler count, and consequence-pass serial;
- `inspect_rule(rule_id)` gathers the selected declaration, current fact view, that rule's recent evaluations, and recent occurrences of its source event so “the event never happened,” “payload/fact condition differed,” “one-shot already fired,” and “it matched and queued N actions” are distinguishable.

Diagnostic history is bounded world-lifetime state only. It is not saved/restored, cannot emit events or mutate facts/rules, and retained debugger references invalidate at teardown. Replacement worlds start with fresh histories over their own semantic truth.

**Done when:** a READY/PLAYING world exposes one resolvable read-only debugger; fact and rule inspection is detached and complete enough to understand current inputs/policy; deliberate payload and fact misses report condition/reason/expected/actual; successful and already-fired one-shot outcomes are distinguishable; rule evaluations correlate to the existing event sequence/consequence-pass trace so FIFO cascades can be reconstructed; histories are bounded; unknown rule inspection fails closed; no debugger state enters saves; teardown invalidates retained references and replacement starts fresh; and existing event/fact/rule/script/save/gameplay regressions remain green.

**Automated:** accepted on mission-logic-debugger implementation head `e9ba8325eb3493402bdd55695cc67333d5c3de9b` by GitHub Actions Test run #493. The focused Application regression proves detached fact/rule inspection, no mutation surface, closed failure for unknown rule IDs, payload/fact mismatch reasons with trigger-time expected/actual values, successful and already-fired one-shot outcomes, event-sequence + consequence-pass correlation with the existing FIFO event trace, direct per-rule inspection, bounded rule/event histories, absence from semantic save truth, teardown invalidation, and fresh replacement isolation. The full barrier ended with `ALL APPLICATION TESTS PASSED` and `ALL TEST SUITES PASSED`; successful-run script-error signatures were identical to the preceding green run #492 and remain existing deliberate failed-restore fixture noise rather than a 7.7 regression.

**Manual:** none required for this architecture-only diagnostic surface. Phase 8.7 will use it against real authored mission problems and may expose presentation/workflow improvements without changing this semantic diagnostic contract.

**Phase gate:** ordinary mission reactions work without core edits, procedural behavior can live in GDScript without private reach-through or bypassing controlled semantic mutation, long-running behavior is saveable semantic state rather than runtime continuation state, mission facts have not become premature campaign storage, and the API is useful but explicitly provisional.

---

# Phase 8 — First proper 10–15 minute stealth mission

Goal: test authoring workflow/system architecture with an actual small mission.

The mission uses real TrenchBroom geometry/entities, multiple routes where practical, reusable external-model-backed doors/openings and furniture/props, doors/keys, darkness/light, surfaces, throwable props, guard patrol/investigation, typed audible speech, loot/container interaction, objectives, one declarative rule, one mission-specific GDScript example where useful, quicksave/load, restart, and minimal results/run-stat inspection.

Full polished results UI remains Phase 13; Phase 8 must consume the real semantic `MissionRunState` rather than create a temporary scraper/counter system.

## 8.1 Mapper workflow proof `[x]`

The first Phase 8 authoring proof stays on the existing source/import ownership path rather than creating the real mission content prematurely. The ordinary mapper workflow is now:

- place the existing `vark_opening` / `vark_prop` point entities in TrenchBroom and configure semantic fields there;
- choose the currently proven compatible `opening_variant` / `prop_variant` from real FGD `choices` fields rather than typing an arbitrary presentation label;
- leave `visual_model_path` blank for those known variants so the shared `OrdinaryDoor` / `OrdinaryProp` owner resolves the compatible external model automatically; the Tall crate choice also resolves its proven compatible collision dimensions when the collision remains at the shared default;
- retain `visual_model_path` and `collision_size` as explicit advanced overrides for future compatible/custom assets, so this proof does not turn current variants into separate gameplay scenes or remove the existing external-model seam;
- let the existing persistent-ID source repair write only authoritative `.map` source, reload TrenchBroom after any repair write, and never hand-edit generated FuncGodot/Godot output.

`tools/authoring/mapper_workflow_probe.gd` is a read-only verifier for the ignored mapper workspace. It builds the actual saved `.map` through the project-owned Vark FuncGodot settings and checks one semantic proof opening (`door_id = phase8.workflow.door`) plus one proof prop (`prop_id = phase8.workflow.prop`). The probe verifies the selected Narrow/Tall choices resolved onto the existing production gameplay owners, compatible model paths/collision, valid persistent identity, and no source rewrite.

**Done when:** project-owned Vark FGD exports mapper-visible choices for the proven ordinary/narrow opening and standard/tall prop variants while preserving optional raw model-path overrides; a real mapper-style `.map` build can select Narrow/Tall only through authored entity properties and resolves the compatible production model/collision defaults on the shared gameplay scenes; the workflow requires no Godot scene/code/generated-output edit; existing explicit model/collision overrides still work; persistent identity remains source-owned/fail-closed; the read-only proof does not rewrite source; existing authoring/application/gameplay regressions remain green; and a Windows mapper/user confirms the actual TrenchBroom UI/save/repair/verify workflow.

**Automated:** accepted after fix-forward on head `284c9ea508d6e10f0138027349e24aa21cefd381` by GitHub Actions Test run #498. The Windows mapper pass exposed that `vark_prop.prop_id` was absent because FuncGodot does not export a `StringName` FGD default. Run #497 then proved that changing only the FGD side to `String` was insufficient because FuncGodot's assembler requires an exact matching generated-node property type. The root correction therefore uses ordinary `String` on both the project-owned FGD property and `VarkOrdinaryProp.prop_id`; its semantic content-ID API was already string-valued, so save/gameplay identity behavior is unchanged. The Authoring suite now requires exported `prop_id(string)`, and real FuncGodot builds successfully apply standard/tall authored prop IDs on the production `OrdinaryProp` owner. The same run passed all three focused 8.1 assertions, ended with `ALL AUTHORING TESTS PASSED`, `ALL APPLICATION TESTS PASSED`, and `ALL TEST SUITES PASSED`, and introduced no new script-error signature relative to the prior green baseline #496. A full audit of project-owned `authoring/fgd/*.tres` found no other mapper-facing `StringName` defaults.

**Manual:** accepted on Windows with TrenchBroom 2026.2 after the `prop_id` fix. The mapper refreshed the installed Vark GameConfig/FGD and the sync probe confirmed `vark_opening`, `vark_prop`, `opening_variant(choices)`, `prop_variant(choices)`, and `prop_id(string)`. In the ignored workspace, the mapper placed/configured the proof opening and prop through normal entity properties, ran source-owned persistent-ID repair, reloaded the map after the repair write, and then ran the read-only mapper-workflow verifier. The verifier passed with `door_id = phase8.workflow.door` / `variant = narrow` resolving `ordinary_door_leaf_narrow.obj`, and `prop_id = phase8.workflow.prop` / `variant = tall_crate` resolving `ordinary_crate_tall.obj` with collision `(0.5, 0.7, 0.5)`; it also confirmed the `.map` source was unchanged. No generated output, gameplay scene, or gameplay script hand-edit was required.

## 8.2 Reimport proof `[x]`

Normal mapper iteration is now proven against the persistence boundary established earlier rather than only against imported transforms.

`tools/authoring/phase8_reimport_probe.gd` uses the already-ignored mapper workspace and has three narrow commands:

- `snapshot` captures the current source/brush-geometry fingerprints, the accepted 8.1 proof opening/prop persistent IDs + authored transforms, and one real stable-boundary semantic save envelope;
- `verify` rebuilds the edited `.map`, requires world brush geometry plus both proof entity transforms to have changed, requires the same persistent IDs to resolve through the production registry, captures a fresh save containing both owners, and then restores the **pre-edit** semantic save into a fresh build of the edited world;
- `clear` removes only the ignored binary baseline sidecar.

The verifier does not repair or rewrite the mapper source. Identity must already be valid; an ordinary move/geometry edit must therefore require no persistent-ID repair. The pre-edit restore proof is intentionally limited to **identity/saveability continuity** under a benign reimport with the same mission revision: authored world geometry remains the edited content, while persistent semantic owner state resolves by stable ID. Phase 8.6 still owns proving that genuinely incompatible semantic/spatial mission edits bump `mission_content_revision` and refuse stale saves.

**Done when:** a real mapper-style baseline containing the accepted 8.1 opening/prop can capture a stable semantic save; an ordinary brush edit plus ordinary movement of both model-backed entities rebuilds successfully without changing either authored persistent ID or requiring source repair; fresh save capture after reimport still contains both persistent owners; a pre-edit save resolves/restores through those same IDs in a fresh edited-world build; the verifier leaves `.map` source byte-for-byte unchanged; deterministic CI exercises the same real FuncGodot/WorldSession/save/restore path on a disposable map; existing Phase 2.8 reimport, 8.1 mapper, persistence, save/load, authoring, application, and gameplay regressions remain green; and a Windows mapper/user confirms the real TrenchBroom save/reimport workflow.

**Automated:** accepted on reimport/saveability implementation head `e4694ed368036e754f26e19ec75118b8fd6273cc` by GitHub Actions Test run #501. The focused Authoring regression reads the tracked Playground source, composes the accepted 8.1-style opening/prop baseline, captures stable proof identities plus a real stable-boundary semantic save, shifts one real world brush and both proof entities without changing IDs, verifies dry identity repair is still a no-op, rebuilds through the production Playground wrapper, proves both persistent owners remain present in a fresh save, restores the pre-edit envelope into a fresh edited-world build, verifies exact restored persistent-owner snapshots, and confirms the verifier leaves edited mapper source byte-for-byte unchanged. All six 8.2 assertions passed; the same run ended with `ALL AUTHORING TESTS PASSED`, `ALL APPLICATION TESTS PASSED`, and `ALL TEST SUITES PASSED`. Successful-run script-error signatures were identical to the preceding green run #500 and remain existing deliberate failed-restore fixture noise rather than an 8.2 regression.

**Manual:** accepted on Windows with TrenchBroom 2026.2. Starting from the accepted 8.1 ignored workspace, the mapper captured the Phase 8.2 baseline, moved one world brush plus both proof entities, saved, and ran source-owned identity repair. Repair reported `No persistent-ID repair needed; valid source was left byte-for-byte unchanged.` with both accepted opening/prop IDs preserved and `missing=0, duplicate=0`. The read-only verifier then passed: world geometry and both proof transforms changed, fresh save capture retained both persistent owners, the pre-edit semantic save restored into the reimported world, and the mapper source remained byte-for-byte unchanged.

## 8.3 Rule proof `[x]`

A real development mission package at `missions/rule_proof/` now provides the first player-facing authored-rule proof without adding mission-specific GDScript.

The map is ordinary TrenchBroom/FuncGodot content: one player start, one saved gameplay light, and one reusable switch. The world reuses the existing mission-map wrapper plus the generic objective owner/status presentation. `MissionDefinition` owns the common mission logic:

- mission fact `security_cut: bool` is a **latched mission meaning**, not a mirror of the switch/light's current subsystem-owned state;
- one one-shot rule observes the real `switch.used` event for `phase8.rule.switch` turning the controlled light group off and queues `security_cut = true`;
- a second one-shot rule observes the resulting `mission.fact_changed` event, confirms the typed fact is true, and emits the existing `objective.activate_requested` semantic command for `objective.security_cut`;
- no arithmetic, arbitrary calls, Node reach-through, timers, delayed callbacks, or script snippets are added to the data grammar.

The intended player-visible result is deliberately simple: the mission starts with the rule objective visibly **INACTIVE**; using the real switch turns the room light off immediately through light ownership, then the controlled semantic consequence pass latches the mission fact and changes the generic objective display to **ACTIVE**. Later switch toggles continue to control the light but cannot replay the one-shot mission consequences.

**Done when:** the Rule Proof is launchable through the normal Development Launch MissionDefinition path; its authoritative `.map` supplies the real switch/light/player content; its common mission reaction is represented entirely by declared fact/rule data and generic semantic owners rather than mission-specific GDScript; immediate switch-owned light state remains distinct from delayed controlled rule consequences; the authored FIFO chain is `switch.used → mission.fact_set_requested → mission.fact_changed → objective.activate_requested → objective.state_changed`; both rules fire once, repeated switch use does not reactivate the objective, stable save captures the mission fact + fired rule IDs + objective/light state, restore reapplies them without consequence replay, and post-restore switch use remains ordinary while one-shots stay suppressed; existing rule/fact/objective/light/save/application/gameplay regressions remain green; and a user/playtester confirms the visible switch-to-objective behavior in the launched mission.

**Automated:** accepted after fix-forward on head `a659d5c82144f4b0e2c25d59c81b1914f9ce6b6d` by GitHub Actions Test run #504. The initial implementation run #503 correctly failed the existing mission-content gate because the new real mission omitted the required authored `vark_exit`; the fix-forward added `exit.rule_proof` to authoritative `.map` source. The focused Application regression then passed all eleven 8.3 assertions: curated Development Launch target + valid MissionDefinition, real imported switch/light content with the shared wrapper/generic objective owner, inactive/default starting state, immediate switch-owned light truth versus controlled fact/objective timing, exact FIFO `switch.used → mission.fact_set_requested → mission.fact_changed → objective.activate_requested → objective.state_changed` ordering, latched fact + active objective + both fired one-shot IDs, no replay on repeated use, stable save truth, fresh restore without consequence replay, and restored one-shot suppression while ordinary switch gameplay continues. The same run ended with `ALL AUTHORING TESTS PASSED`, `ALL APPLICATION TESTS PASSED`, and `ALL TEST SUITES PASSED`; successful-run script-error signatures were identical to the preceding green baseline #502.

**Manual:** accepted by user/playtester on the final 8.3 build. Development Launch → **Rule Proof** started with `OBJECTIVE INACTIVE` and the gameplay light on; the first **F** use on the labeled switch turned the light off and changed the status to `OBJECTIVE ACTIVE`; two further switch uses continued to toggle the light normally while the objective remained active without resetting or visibly replaying the authored mission reaction. No debugger/console mutation, generated-file edit, or mission-specific script was needed.

## 8.4 Representative stealth mission construction `[ ]`

Build the actual Phase-8 mission promised by this phase. The 8.1–8.3 proof fixtures remain useful regression content, but they are **not** a substitute for this mission.

The mission must be one dedicated `MissionDefinition` package with authoritative TrenchBroom `.map` source and ordinary reusable gameplay owners. It should target roughly 10–15 minutes for a first informed playthrough and contain, at minimum:

- one valid player start and mission exit;
- at least two meaningfully different useful approaches through the space, not merely two adjacent doorways;
- real model-backed opening/door content plus at least one locked/key-gated interaction and a viable alternate route;
- darkness/light interaction using the proven gameplay-light path, including at least one switchable/extinguishable light state that matters to stealth;
- quiet/normal/loud authored surfaces used in traversal rather than decorative-only patches;
- throwable ordinary props, with at least one placement where a prop can be used as traversal/route assistance or a deliberate distraction;
- at least one guard with a patrol containing wait points, plus investigation/search behavior that the player can actually provoke and evade;
- typed audible NPC speech through the existing speech path;
- loot, at least one container/furniture interaction, and semantic mission-run accounting through `MissionRunState` rather than a mission-local counter;
- one objective/exit relationship and at least one declarative mission reaction using the Phase-7/8.3 fact/rule path;
- restart and ordinary quicksave/quickload available through the production application path.

Do not add a new subsystem merely to make the mission look complete. If existing systems cannot author or express a required piece cleanly, record the concrete gap for 8.5–8.7 rather than bypassing ownership with mission-local core edits.

**Done when:** the dedicated mission loads through Development Launch as a real `MissionDefinition`; all required authored references/IDs validate; the mission can be played from start to successful exit using the existing production systems; at least two useful routes are actually viable; the required stealth/interaction/loot/guard/light/surface/prop/objective content is present; mission-run loot/stat truth comes from semantic owners; no generated output or core gameplay file must be hand-edited to author ordinary content; and any remaining authoring/API/debug gaps are explicitly identified rather than hidden.

**Automated:** add a focused mission-content regression that loads the real package, validates `MissionDefinition` + persistent/content IDs + required roles, builds the authoritative `.map` through the production wrapper, reaches `PLAYING`, resolves the key authored semantic references, proves the mission-run owner and objective/exit owners are present, and fails if required representative entities disappear or duplicate. Keep subjective route quality/pacing out of deterministic assertions.

**Manual:** required — user/playtester. Play the real mission end-to-end at least twice using materially different approaches. Confirm it feels like a small stealth mission rather than a lab, the alternate route is genuinely useful, darkness/surfaces/props/guards/loot/objective interactions all matter in ordinary play, restart/quicksave/quickload remain usable, and note concrete authoring/gameplay friction for later Phase-8 items.

## 8.5 GDScript extension proof `[ ]`

Use the real 8.4 mission to prove **one** genuinely unusual behavior through the provisional `VarkMissionScript` API without expanding the declarative rule grammar into a programming language.

The selected behavior must be named explicitly in the implementation patch and must satisfy all of these criteria: it is useful in the real mission; expressing it in the small rule grammar would require inappropriate general control flow/object manipulation; it can use supported semantic queries/commands rather than private Node reach-through; and any save-relevant progress can be represented as explicit facts/objective/stage state rather than a suspended coroutine/timer continuation. Prefer a need actually exposed by 8.4. If no real need exists, use the smallest representative scripted sequence that still exercises these boundaries and document why it is intentionally script-owned.

Script commands requested outside the controlled consequence pass must queue through the existing semantic boundary. Authored persistent objects may be manipulated only through supported commands/events. Genuinely transient script-created presentation/effects may exist without persistence; if the chosen behavior creates a gameplay object that must survive save/load, pull forward only the minimum runtime-persistence proof instead of silently making it non-saveable.

**Done when:** one real mission behavior exists only in mission-specific GDScript; the script resolves only the supported provisional API; out-of-pass mutation is queued rather than immediate; save-relevant progress is explicit semantic state; teardown/replacement invalidates stale script/API references; no private core reach-through or arbitrary rule-language expansion is introduced; and the behavior is understandable in ordinary play.

**Automated:** exercise the real scripted behavior through its production event/API path, prove the immediate state does not mutate before the controlled consequence pass, prove the queued consequence then applies in FIFO order, prove the explicit progress state captures/restores without replaying resolved consequences, and prove stale retained API/script references cannot affect a replacement world.

**Manual:** required — user/playtester. Trigger the scripted behavior in the 8.4 mission, confirm its visible result and any staged progression are coherent, save/load at the documented representative point if the behavior has save-relevant progress, and confirm no duplicate/replayed consequence appears after load.

## 8.6 Representative save/load and compatibility proof `[ ]`

Exercise save/load against the **real Phase-8 mission**, not another generic save fixture. Phase 4 already proved the general transaction; this item proves that the representative authored mission obeys it under real mission content.

Use representative save points that cover the semantic states actually present in the mission. At minimum include: a guard investigation/search state, a door or other explicit long-running semantic transition if present, a post-loot/objective/rule state, and the save-relevant 8.5 scripted stage when applicable. The exact set may expand if 8.4 introduces another important state, but do not invent unrelated systems only for coverage.

Compatibility coverage must include a **meaningful mission-content incompatibility** derived from the real mission: change authoritative semantic/spatial content in a way that would make an old snapshot unsafe, bump `mission_content_revision`, and prove the old save is refused before destructive world replacement. The test may derive a disposable candidate from tracked mission source; it must not pretend that merely changing a serialized integer is a content edit.

Also exercise the global `save_format_version` semantic gate with a structurally valid legacy/incompatible semantic fixture. Do not bump the shipping format version solely to manufacture a test when no actual global semantic change occurred; the fixture must document the incompatible interpretation it represents and prove the current loader refuses it before restore.

**Done when:** every required representative save point round-trips through one detached stable-boundary snapshot with no consequence replay; the real mission's rule/script/objective/run-state truth restores coherently; a meaningful mission-content revision mismatch fails closed before replacement; an incompatible global semantic version fails closed; and ordinary current-version/current-revision saves still load after those rejection tests.

**Automated:** add focused real-mission save/restore coverage for the named states, exact pending-event suppression at resume, mission-content revision refusal based on a substantive disposable mission edit, global semantic-version refusal, and failure safety proving the currently valid world/save state is not destroyed by an incompatible candidate.

**Manual:** required — user/playtester for normal-play save feel only. Quicksave/quickload at the documented mission points, including during active stealth pressure, and confirm position/world/guard/objective/loot/script state feels coherent. Compatibility-refusal internals are automated and do not require the user to hand-edit saves.

## 8.7 Authoring/debug gap closure `[ ]`

Close only the concrete workflow, validation, and diagnostic gaps exposed while building/debugging 8.4–8.6. This is **not** a license for speculative tooling or a second editor framework.

At the start of this item, enumerate the observed gaps in this roadmap entry or implementation notes. Classify each as: authoring friction, validation failure quality, missing read-only diagnostic, documentation/workflow confusion, or genuine API gap. Fix the smallest root cause. If no material gap remains, this item may be completed as a documented audit with no manufactured code change.

Build on the existing persistent-identity tools, mission logic debugger, event trace, registry diagnostics, perception/acoustic/nav debug surfaces, and TrenchBroom workflow rather than reimplementing them.

**Done when:** every material Phase-8 gap has either a concrete fix or an explicit deferral with rationale; mapper/runtime errors identify the authored source/semantic owner clearly enough to act on; no diagnostic path mutates gameplay truth; and ordinary mission iteration no longer requires undocumented core/generated-file workarounds.

**Automated:** every deterministic bug/tooling fix receives regression coverage on the production path it protects; deliberately invalid representative content produces the intended actionable failure where practical; the full barrier remains green. If the audit finds no code defect, automated acceptance is the existing relevant validation suites plus a documented no-gap result.

**Manual:** required when the fixes change mapper/debug workflow — user/mapper repeats the exact previously troublesome action and confirms the issue is resolved. `Manual: none` is allowed only when the audit/fixes are wholly machine-verifiable and no human workflow changed.

## 8.8 Cold-author review `[ ]`

Have a Godot/TrenchBroom-capable developer who is unfamiliar with the relevant Vark internals make a small but real modification through the intended workflow without core-gameplay assistance.

The cold-author task must start from a clean checkout plus the documented Vark TrenchBroom setup and require at least: one geometry edit/addition; one reusable model-backed gameplay entity or light; one semantic content edit such as loot/objective/rule/patrol configuration; normal persistent-ID workflow; build/validation; and launching the modified mission. The reviewer may read project docs and normal tooltips/errors, but should not be coached through private implementation details or asked to edit generated Godot output/core scenes/scripts.

**Done when:** the reviewer completes the task using intended source files/tools, can explain where ordinary spatial vs semantic configuration belongs, encounters no undocumented mandatory core edit, and reports the workflow/friction. Any blocking flaw is fixed and the relevant portion of the cold task is repeated before Phase 8 closes.

**Automated:** no substitute for the independent-human purpose. Normal CI/content validation must remain green for any fixes resulting from the review.

**Manual:** required — independent cold author, not the implementing agent and not merely the usual playtester role. Record whether the task succeeded, what documentation/tooling was insufficient, and whether any core/generated-file workaround was attempted.

**Phase gate:** one actual 10–15 minute stealth mission, not only proof labs, has exercised the authoring stack; ordinary content is authorable through intended tools; one procedural behavior proves the provisional script API without bypassing controlled mutation; representative save/load and compatibility refusal work on the real mission; run statistics/results data comes from semantic ownership rather than temporary scraping; concrete authoring/debug problems have been closed or explicitly deferred; runtime-persistent scripted objects cannot silently bypass persistence; and an independent developer can make a small mission change through the documented workflow.

---

# Phase 9 — Bodies and combat prototype

Goal: establish the four-playstyle foundation while combat remains TARGET until play proves it. Reuse the existing crude hostility/life-state/input/event/save boundaries; do not build a parallel combat architecture.

## 9.1 Body handling and body discovery `[ ]`

Complete the LOCKED conscious/unconscious/dead body contract on the existing persistent actor identity. Add player carry/drop/place/hide behavior for unconscious/dead actors, explicit mobility modifiers while carrying, and a semantic body-discovery hook that perception/mission logic/statistics can observe.

Do not reimplement life states or replace the existing guard actor with a corpse entity. Body carry must use central hand/action ownership and must not change accepted unencumbered locomotion behavior.

**Done when:** the same persistent guard identity transitions to unconscious/dead body state, can be picked up/carried/dropped/hidden, cannot navigate/act while a body, restores coherently through save/load, and body discovery emits one semantic observation suitable for awareness/mission/stat owners without hard-coding a universal mission failure.

**Automated:** cover identity preservation, hand/input suppression, movement modifier application/removal, save/restore while body-carried and after drop, no duplicate actor/corpse identity, discovery event de-duplication, and teardown/replacement isolation.

**Manual:** required — user/playtester validates carry/drop/hide feel and that the mobility penalty is noticeable but does not make body carrying unusable.

## 9.2 Combat intent and prototype loadout seam `[ ]`

Extend the existing gameplay-input boundary for combat gestures before implementing combat feel. Attack must expose the pressed/held/released semantics needed by takedowns, and block must expose its required held/edge semantics through the same application-owned domain/cancellation rules.

Phase 9 may use a **small prototype combat-mode/loadout seam** (`unarmed`, `knife`, `blunt`) supplied by development content/fixture configuration so individual combat behaviors can be tested before Phase 10 inventory exists. This is not a second inventory system: no quantities, item UI, campaign persistence, purchasing, or separate input polling. Phase 10 may later drive the same combat-use semantic choice from real inventory ownership.

**Done when:** combat input is tick-framed through the existing boundary; attack/block gesture state clears on domain loss/pause/world replacement and requires a fresh initiating press after resume; hand occupancy from carried Junk/body suppresses hand combat centrally; and development fixtures can select the intended prototype combat mode without adding general inventory.

**Automated:** protect one-tick edges, held/released lifetime, cancellation on domain loss, stale-input suppression, current-world ownership, carry/body hand suppression, and preservation of accepted locomotion/look behavior.

**Manual:** none for feel yet; later combat items own player-facing validation.

## 9.3 Stealth knockout prototype `[ ]`

Replace the crude press-to-knockout compatibility behavior with the TARGET hold/release fist takedown in `unarmed` mode.

The valid stealth context must be an explicit predicate over real semantic state: target is a conscious eligible ordinary NPC, within the takedown range/angle, the player's hands are available, and the target is not currently in a state that counts as having detected/engaged the player. Exact angle/range/readiness timing are TARGET tuning values, not LOCKED until playtest.

**Done when:** holding attack arms the takedown only in valid context; releasing while still valid produces one semantic knockout through the existing actor life-state path; losing context or combat-input ownership cancels the armed gesture; invalid/repeated releases do nothing; and the same actor becomes the ordinary unconscious body from 9.1.

**Automated:** cover arm/release/cancel edges, context loss, pause/domain loss, stale release suppression, one semantic life-state transition, awareness/noise integration hooks, and save truth after the knockout.

**Manual:** required — user/playtester tunes/read-validates range, behind/unaware readability, hold/release feel, and transition into body interaction.

## 9.4 Stealth kill prototype `[ ]`

Add the TARGET knife stealth kill using the same 9.2 gesture/context foundation in `knife` mode rather than a separate attack path.

**Done when:** the same valid stealth-context rules and cancellation behavior apply; release produces one semantic transition to `dead`; the persistent actor becomes the ordinary dead body; lethal/nonlethal outcome identity is visible to statistics/mission logic; and no inventory system is invented merely to select the knife in Phase 9.

**Automated:** mirror the takedown gesture/cancellation coverage, prove dead rather than unconscious life state, single consequence/stat hook, persistence, and body interaction compatibility.

**Manual:** required — user/playtester validates stealth-kill readability/feel and that lethal/nonlethal choices are clearly distinguishable.

## 9.5 Vitality/damage ownership and guard attack loop `[ ]`

Establish the **smallest real semantic vitality/damage ownership** before block/parry/direct-combat tuning. This moves the old 9.5 responsibility earlier because real incoming attacks cannot be evaluated coherently without a player damage owner.

Player vitality and any guard damage accumulation required by direct combat must be semantic save truth owned by the relevant actor/player system. Ordinary combat damage uses controlled semantic events/commands and the same life-state actor identity; Phase 10 effects will extend this boundary rather than replace it.

Add the smallest ordinary guard attack loop needed for later defense tests: approach/attack opportunity, telegraphed attack timing in gameplay simulation time, one controlled damage consequence on an unblocked hit, and coherent cancellation when actor/world/input ownership makes the attack invalid.

**Done when:** player damage/health and required guard damage state have one owner each, survive save/load, a guard can perform a repeatable ordinary attack through semantic timing/consequence ownership, unblocked impact changes vitality exactly once, and no temporary combat-only health path exists.

**Automated:** cover damage ownership/validation, save round-trip, gameplay-time attack timing/pause, no wall-clock advancement, one-hit consequence ordering, dead/unconscious attacker suppression, world replacement isolation, and failure on malformed vitality state.

**Manual:** required — user/playtester checks attack telegraph/readability and that a single guard's baseline attack cadence is understandable enough for defense prototyping. Exact balance remains TARGET.

## 9.6 Block/parry/stagger prototype `[ ]`

Implement the TARGET defense grammar on top of 9.2 input and 9.5 real attack/vitality ownership:

- held block stops ordinary blockable damage while valid;
- a fresh block press inside a short pre-impact window parries;
- successful parry produces one semantic stagger on the attacker;
- stagger duration uses gameplay simulation time;
- losing combat-input ownership cancels held/armed defense state and requires fresh input after resume.

**Done when:** ordinary guard attacks can be unblocked, blocked, or parried through the same attack consequence path; parry timing is deterministic in gameplay time; stagger suppresses/changes the attacker's combat availability without replacing actor awareness/life state; and save/load uses an explicit direct/reconstruct/normalize policy for any active stagger/timing state.

**Automated:** deterministic timing-window boundary tests, block/parry exclusivity, damage suppression, one stagger consequence, gameplay-time pause behavior, input-domain cancellation, and save/restore policy.

**Manual:** required — user/playtester evaluates block readability, parry timing, stagger duration, and whether one-guard defense feels learnable. Values stay TARGET.

## 9.7 Direct lethal/nonlethal combat prototype `[ ]`

Complete the TARGET direct-combat grammar using the already-proven input/vitality/block/parry/stagger owners.

A non-staggered ordinary NPC may defend against normal knife/blunt attacks. Knife against a valid staggered NPC can produce lethal resolution; blunt against a valid staggered NPC produces nonlethal damage/progress and eventually knockout according to TARGET tuning. Do not bypass vitality/life-state ownership with weapon-local kill counters.

**Done when:** both lethal and nonlethal direct assault are possible against the same ordinary guard; defender/parry/stagger/vitality/life-state interactions are coherent; retreat can break physical contact without erasing awareness; and all combat state required after save/load has explicit semantic ownership/policy.

**Automated:** cover defended attacks, stagger openings, lethal resolution, multi-hit nonlethal progress, life-state transitions, save round-trip, and no duplicate damage/consequences across restore.

**Manual:** required — user/playtester evaluates one-guard lethal/nonlethal assault and identifies tuning/grammar problems without treating TARGET numbers as frozen.

## 9.8 Required combat validation `[ ]`

Playtest the full TARGET grammar before locking it. Required scenarios: one guard, two guards, tight corridor, open room, actively attacking enemies, lethal assault, nonlethal assault, stealth failure into open combat, and retreat/break contact.

Revise 9.3–9.7 behavior/tuning if the target grammar fails these scenarios. This item may legitimately require multiple user loops; do not mark combat LOCKED merely because deterministic tests pass.

**Done when:** the user accepts a coherent combat grammar for the required scenarios, one guard is manageable, two are materially harder, escape remains viable, lethal/nonlethal routes both work, and any rejected TARGET rule has been revised in code/docs/tests.

**Automated:** regression suites protect objective invariants after each tuning revision but do not encode subjective timing/feel as permanent values unless explicitly accepted.

**Manual:** required — user/playtester; all named scenarios must be exercised. Combat becomes LOCKED only after this acceptance.

## 9.9 Combat perception/noise/body/stat/save integration `[ ]`

Close the Phase-9 integration after the combat grammar is accepted. Combat must produce appropriate gameplay noise/awareness, body discovery opportunities, semantic mission-run statistics, life/vitality save truth, and reusable events through existing owners.

**Done when:** attacks/blocks/impacts generate the intended semantic sound/awareness consequences; kills/knockouts/detections significant to results are recorded once by semantic owners; bodies from combat use 9.1 behavior; save/load during/after representative combat restores coherent actor/vitality/awareness/body state without replay; and no combat subsystem has its own parallel event/time/persistence path.

**Automated:** integrated combat→noise→awareness, combat→life/body, combat→statistics, representative save/restore, duplicate-consequence suppression, and mission/world replacement coverage.

**Manual:** required — user/playtester performs one representative stealth-to-combat-to-retreat sequence and confirms sound/AI/body/stat outcomes are believable and consistent with accepted combat.

**Phase gate:** all four broad styles are genuinely possible enough to evaluate; bodies are ordinary persistent actor states; real vitality/damage ownership exists before effect generalization; combat uses the established gameplay-input, controlled semantic event, gameplay-time, perception, statistics, and save boundaries; and the TARGET combat grammar has explicit user acceptance rather than being frozen by implementation alone.

---

# Phase 10 — Inventory, effects, and complete gameplay vertical slice

Goal: add real usable inventory and runtime-created gameplay on top of Phase 6 possession and Phase 9 vitality, then prove the whole gameplay grammar in one complete slice.

## 10.1 Inventory ownership, selection, quantities, and one real consumable `[ ]`

Build the core Thief-style selectable/usable inventory on top of existing semantic possession instead of replacing it. Keep carried Junk separate.

The first implementation must establish one authoritative inventory owner, stable item type IDs/data, quantities where appropriate, deterministic selection/order, use/consume semantics, save state, and central hand/input availability. Include keys/mission items as non-consumable semantic holdings plus **one real usable consumable** (preferably a healing item now that Phase 9 vitality exists) so the framework is exercised by gameplay rather than only data.

Do not add projectiles/deployables/area effects or runtime-object persistence to this item; 10.2–10.3 own those expansions.

**Done when:** inventory can own/select/use the representative items; quantity/consumption is semantic save truth; ordinary key/mission possession remains compatible; item use respects hand/input ownership; carried Junk remains distinct; and Phase 9 combat/vitality does not gain a second item-specific truth path.

**Automated:** item ID/type validation, selection/order, quantity mutation, consume-once behavior, healing through the real vitality boundary, hand/domain suppression, save/restore, unknown item failure, and compatibility with existing key/loot possession.

**Manual:** required — user/playtester validates basic selection/use feedback and that inventory does not interfere with carried Junk or ordinary interaction.

## 10.2 Representative thrown tool and runtime-persistent identity `[ ]`

Introduce the first real runtime-created gameplay object through **one representative thrown tool** (for example a noise-making throwable) so runtime persistence is proven by actual content rather than a generic spawn framework.

The runtime object needs: a collision-safe runtime persistent ID; a stable semantic type/provenance ID that is not a scene/class filename accident; creation through the current world/session lifetime; explicit semantic state sufficient to recreate it; and restored-ID reservation so a later runtime spawn cannot collide with restored identity.

Because ordinary gameplay saving is allowed, include a save while the tool is active/in flight or otherwise not yet resolved. Choose and document its direct-restore/reconstruct/normalize policy; consumed inventory must not reappear while the corresponding active tool silently disappears or duplicates.

**Done when:** using the inventory item creates exactly one runtime object and consumes the correct inventory quantity; save/load during its active state reconstructs the documented gameplay truth; unknown runtime type IDs fail closed; duplicate/restored ID collisions are rejected; and a post-restore new spawn receives a distinct identity.

**Automated:** runtime type registry/provenance validation, ID uniqueness/reservation, active-transient save/restore, inventory↔runtime-object exactly-once coupling, unknown type refusal, teardown cleanup, and post-restore spawn non-collision.

**Manual:** required — user/playtester throws/uses the tool, quicksaves while it is active, quickloads, and confirms there is neither a duplicated inventory item nor a missing/duplicated world effect.

## 10.3 Reusable gameplay-effect grammar `[ ]`

Generalize only the effects demanded by real Phase-9/10 content. Extend the **already-real Phase-9 vitality/damage ownership** rather than replacing it.

At minimum prove two distinct effect families through real content: the 10.1 heal/vitality effect and one additional representative tool/world effect selected by the slice (for example gas, water, fire, explosion, or a non-vitality utility effect). Effect descriptors may carry typed parameters but must not become an unrestricted scripting language.

**Done when:** multiple items/world sources can route through one small typed effect surface; ordinary combat damage/healing still resolves through the same vitality owner; effect source/target attribution is sufficient for semantic events/statistics; save policy for any long-running effect is explicit; and unsupported effect IDs fail clearly.

**Automated:** effect validation/dispatch, combat-vitality compatibility, one non-vitality/area effect, source attribution, save/restore policy where applicable, and unsupported/malformed effect failure.

**Manual:** required only for player-visible effect readability/feel; user validates the chosen representative effects in the slice.

## 10.4 One interruptible scripted NPC routine `[ ]`

Prove NPC routine content with **one** representative authored routine rather than implementing a universal schedule system. The routine must have at least two meaningful stages (for example patrol ↔ sit/sleep/operate), can be interrupted by existing investigation/combat awareness, and resumes or resolves according to explicit semantic state.

Save-relevant routine stage/progress and already-resolved choices are semantic data. Do not serialize a coroutine stack, animation callback, or reroll the routine choice on restore.

**Done when:** one real NPC routine starts from authored content, visibly performs its stages, yields to awareness/combat, resumes or resolves deterministically, and round-trips save/load without duplicate actions or hidden continuations.

**Automated:** stage transitions, interruption priority, gameplay-time timing, save/restore of explicit progress, no replay, and teardown isolation.

**Manual:** required — user/playtester confirms the routine reads as intentional behavior and interruption/resumption feels believable.

## 10.5 Complete representative gameplay slice `[ ]`

Build one integrated segment combining stealth, combat, bodies, interaction, mission logic/script, save/load, inventory, the representative runtime-persistent tool, effects, NPC routine, objectives, loot/statistics, and multiple routes.

Exercise the provisional mission API against the complete grammar and correct accidental boundaries now. If another runtime-created transient appears, document and test its save policy rather than assuming the 10.2 tool covers every class.

**Done when:** the slice is playable end-to-end through stealth, lethal combat, nonlethal combat, and mixed-tool approaches; all present persistence cases have explicit owners/policies; runtime identities remain unique across restore + later spawn; inventory naturally drives existing combat/effect semantics; and no subsystem requires a duplicate input/event/time/save path.

**Automated:** integrated smoke/content validation plus cross-system regressions for representative stealth→combat, inventory→runtime tool/effect, body/statistics, mission logic, active transient restore, and post-restore runtime identity uniqueness.

**Manual:** required — user/playtester completes the slice using at least two substantially different playstyles and specifically tests one save/load while an active runtime transient exists.

## 10.6 Performance/reference baseline `[ ]`

Measure the complete slice before production API stabilization. Record the exact supported Windows x64 reference environment and measure: frame/runtime cost for perception, acoustics, lighting/exposure, rules/events, nav, combat, runtime-persistent objects; **synchronous detached snapshot-capture cost**; encoded save size; and durable write time separately.

Do not weaken snapshot coherence to hide a capture hitch. Optimize state collection/copying only when measurement proves a material problem.

**Done when:** repeatable measurement commands/scenarios and the reference environment are documented; baseline numbers are recorded; any obvious regression-level bottleneck has either been fixed or explicitly carried into Phase 14; and no correctness contract was weakened for performance.

**Automated:** deterministic micro/perf counters where stable enough plus regression guards for egregious cost/size growth when practical. CI is not treated as the Windows performance reference.

**Manual:** required — Windows operator runs the documented reference measurement and records results.

**Phase gate:** Vark's gameplay identity exists as one integrated vertical slice; real inventory extends Phase-6 possession without replacing carried Junk; Phase-10 effects extend Phase-9 vitality/damage ownership; at least one runtime-persistent object and one active-transient save policy are proven with unique IDs across restore + later spawn; NPC routine state is explicit; the provisional world/gameplay mission API has survived the complete grammar; and a measured reference baseline exists before stabilization.

---

# Phase 11 — Generalize proven world/gameplay systems for production

## 11.1 Stabilize proven world/gameplay APIs `[ ]`

Audit the provisional/supportable world/gameplay surfaces actually used by Phases 8–10. Promote only interfaces with real repeated use; remove/rename/correct accidental abstractions rather than preserving bad shapes for prototype compatibility.

Campaign/narrative/application-flow extension surfaces remain provisional until Phases 12–13 exercise them.

**Done when:** the promoted API list is explicit, each promoted call/event/type has at least two real use sites or one compelling cross-system use, deprecated prototype-only surfaces are removed/migrated, private core reach-through is absent from ordinary mission content, and ownership/lifetime/error contracts are documented.

**Automated:** full regression plus focused compatibility tests for promoted APIs, stale-world rejection, malformed requests, and teardown/replacement ownership.

**Manual:** none unless an API change alters authoring workflow; then the affected mapper/scripter workflow must be rechecked.

## 11.2 Vark TrenchBroom entity/preset library `[ ]`

Promote the ordinary mapper-facing entities/fields proven by real mission authoring into a clear ready-to-place library. This is where the mapper should see meaningful choices such as ordinary/tall crate and compatible door/opening variants instead of reconstructing common objects from raw fields.

Include only proven ordinary roles/fields: player start/exit/markers, model-backed openings/doors, props, proven container/furniture forms, gameplay lights/switches, guard/patrol authoring, pickups/loot/keys, surfaces, and any other Phase-8–10 entity that survived real use. Keep advanced compatible model/collision overrides available where proven, but do not expose imported mesh hierarchy as gameplay API.

**Done when:** common objects can be placed/configured from TrenchBroom without Godot core-scene edits; preset/variant labels map to compatible shared gameplay archetypes; identity/source ownership remains intact; and the catalog is documented from the mapper's perspective.

**Automated:** FGD/config export/schema checks plus representative real-map builds for every promoted category/variant and compatibility override path.

**Manual:** required — mapper/user builds a small room using only the promoted library and confirms the object palette/properties are understandable and no common object requires manual scene construction.

## 11.3 Production content-validation suite `[ ]`

Consolidate validation for errors actually encountered by Phases 8–10: duplicate/missing IDs, missing/wrong-role references, impossible configuration, invalid variant/model combinations, rule/fact/objective mistakes, revision-policy errors detectable statically, unsupported runtime-persistence type IDs/provenance, and other proven authoring failures.

**Done when:** common invalid content fails before `READY`/shipping build with source-oriented actionable diagnostics; valid representative missions remain accepted; and the validator does not encode subjective design/tuning as errors.

**Automated:** deliberate invalid fixtures for every supported error class plus valid real-mission controls.

**Manual:** none unless error presentation is changed in mapper-facing workflow; then a mapper confirms the diagnostic points to the actionable source.

## 11.4 Debug-tooling audit and closure `[ ]`

Audit and close the remaining diagnostic gaps instead of pretending debug tooling starts here. Build on existing mission-rule debugger/event trace, registry/identity tools, perception/acoustics/nav/exposure debug surfaces, save-state inspection, and Phase-8 gap closure.

Required production-useful coverage: perception/awareness, acoustics, nav/door traversal, entity lookup/identity, mission facts/rules/objectives, semantic ownership/events, vitality/combat where needed, runtime-persistent objects, and save-state/compatibility inspection.

**Done when:** each major proven gameplay owner has a read-only way to answer 'what does the system currently believe and why?' without mutating state, histories are bounded, stale-world references invalidate, and no duplicate diagnostic truth store exists.

**Automated:** parser/lifetime/no-mutation/bounded-history coverage for new tooling plus the existing relevant diagnostic regressions.

**Manual:** developer/mapper spot-checks the tools against one real mission problem if any new presentation/workflow was added.

## 11.5 Mission template `[ ]`

Create a template only from the needs proven by the proper Phase-8 mission and complete Phase-10 slice. It must not contain hidden editor-local/generated state or copy mission-specific content accidentally.

**Done when:** a fresh mission package can be created from the template with its own IDs/definition/map, passes validation, launches, and makes clear where map source, semantic definition/rules, optional script, and ordinary assets belong.

**Automated:** instantiate/copy a disposable template mission in CI, assign new semantic identity, validate/build/enter play, and prove no copied persistent/content IDs collide with the source template.

**Manual:** required — mapper/developer creates one tiny mission from the template using only documented steps.

## 11.6 Second cold-author test `[ ]`

Have another developer create or substantially modify a small mission using the stabilized APIs, entity library, validation, debug tools, and template.

The task must include spatial editing, at least one guard/perception element, model-backed world content, objective/rule logic, inventory/tool or combat-relevant content from the complete slice, validation, and a playable launch. No core gameplay modification is part of ordinary success.

**Done when:** the cold author completes the task without private implementation coaching, can diagnose at least one intentional authoring error using production tools, and reports no blocking undocumented core-edit dependency. Any blocking gap is fixed and retested before Phase 11 closes.

**Automated:** normal CI/validation for resulting fixes; no automated substitute for the independent-human test.

**Manual:** required — independent developer unfamiliar with relevant Vark internals.

**Phase gate:** reusable world/gameplay systems represent proven Vark patterns rather than hypothetical engine features; the complete gameplay slice has exercised them; common objects are ready-to-place through the mapper workflow; production validation/debugging are actionable; and a non-author can create meaningful content. Campaign/narrative/application extension stability remains intentionally unproven.

---

# Phase 12 — Campaign and narrative layer

## 12.1 Typed durable CampaignState `[ ]`

Introduce an application-owned authoritative `CampaignState` for facts that persist **between** missions. It is separate from mission-local `VarkMissionFacts` and must not become a mutable global catch-all for current world runtime state.

Use an explicit typed schema/defaults/validation comparable in discipline to mission facts. Define one durable serialized snapshot owner and clear application-lifetime mutation APIs; mission worlds consume campaign-derived inputs rather than directly owning/mutating the durable object.

**Done when:** campaign facts have typed declared identity/default/value, durable save/load, application ownership across world replacement, no accidental storage of mission runtime owners, and invalid/unknown campaign data fails clearly.

**Automated:** lifecycle isolation, typed validation, durable round-trip, malformed/unknown fact rejection, and proof that mission-local fact mutation does not silently mutate campaign state.

**Manual:** none for this ownership-only step.

## 12.2 One meaningful cross-mission variation `[ ]`

Prove campaign consequence with **two real missions** and one clearly player-visible prior-choice effect. Choose the smallest meaningful content variation supported by the missions (for example guard/security presence, route/entrance availability, objective setup, resources, or dialogue). Do not build every possible variation type.

Resolve the later mission's starting configuration from CampaignState before play and keep the resolved start stable for that run.

**Done when:** completing/choosing the relevant condition in mission A changes campaign truth and mission B visibly starts differently; the variation is authored through supported content/API rather than core conditionals; restarting mission B preserves its resolved variant; unrelated campaign facts do not leak into mission-local state.

**Automated:** two campaign-state variants launch mission B with deterministic differing semantic setup, restart consistency, validation of missing/invalid variation references, and world-lifetime isolation.

**Manual:** required — user/playtester completes/sets both branches and confirms the later mission difference is clear and meaningful.

## 12.3 Writer text/data workflow `[ ]`

Create the smallest stable writer-facing text-data workflow for typed world-space dialogue, briefings, subtitles/sequence text, objective/narrative strings, and other narrative content actually used by the two-mission proof.

Text uses stable semantic IDs/data resources rather than NodePaths or duplicated inline script constants. Keep localization-friendly identity separation where cheap, but do not build a full localization product unless required.

**Done when:** a writer can find/edit/add representative dialogue + briefing text without touching gameplay code; missing/duplicate text IDs fail clearly; runtime speakers/sequences/objectives resolve the intended text; and text identity survives scene refactors.

**Automated:** text-ID uniqueness/reference validation and representative runtime resolution.

**Manual:** required — writer/user edits one dialogue/briefing entry through the intended workflow and confirms the change appears in game without code edits.

## 12.4 First-person sequence proof `[ ]`

Implement one real first-person in-mission sequence using the established input/world/session ownership: temporary gameplay-input restriction, camera/player-control policy, actor actions and typed dialogue, explicit completion/cancellation, then safe return to ordinary gameplay.

The sequence's save policy must be explicit. If arbitrary mid-sequence save is supported, save-relevant stage/progress is semantic state; suspended animation/coroutine continuation is not durable truth. If saving is exceptionally disallowed during the short sequence, that restriction must be narrow, visible, and justified rather than becoming a checkpoint policy.

**Done when:** the sequence enters/exits without orphaning input/camera/world ownership, cannot leak stale callbacks across restart/load/transition, dialogue/actor actions resolve through supported APIs, and its documented save policy is coherent.

**Automated:** input-domain ownership, stale-work cancellation, stage/event ordering, restore/restart behavior per chosen policy, and return-to-play invariants.

**Manual:** required — user/playtester validates first-person presentation, control handoff, readability, and the chosen save behavior.

## 12.5 Campaign-derived mission save provenance `[ ]`

An in-mission save must reconstruct the **same campaign-derived starting variant** that existed when the run began, not whatever CampaignState happens to contain later.

Choose the smallest explicit representation proven by 12.2 content: either the relevant campaign input snapshot or a resolved mission-start configuration/revision/baseline identity. Store enough provenance in the save to rebuild/validate the same run without copying arbitrary campaign globals into mission state.

**Done when:** save/load of both mission-B variants recreates the same starting variant even after live CampaignState is deliberately changed; incompatible/missing campaign/run baseline metadata fails closed before destructive restore; and restart within the current run uses the resolved run baseline rather than rereading changed campaign truth.

**Automated:** variant A/B quicksave round-trips with mutated live campaign state, provenance validation/refusal, restart consistency, and no campaign-owner mutation during restore.

**Manual:** none beyond the later integrated campaign playthrough.

## 12.6 Exactly-once mission completion transaction `[ ]`

Mission completion must apply mission results/consequences and commit the new durable CampaignState **exactly once** through one application-owned completion transaction.

Define an explicit mission/run completion identity so retry, duplicate exit events, crash/re-entry simulation, or UI re-entry cannot apply the same consequence twice. Results/statistics consumed by the transaction come from semantic mission owners, not temporary scene scraping.

**Done when:** a successful mission completion produces one durable campaign advancement + one results snapshot; duplicate completion attempts are idempotently rejected/recognized; a failure before durable commit does not leave half-applied campaign truth; and a completed run cannot mutate the destroyed world afterward.

**Automated:** duplicate/reentrant completion, simulated pre/post-commit failure boundaries, durable reload after completion, results integrity, and world/session teardown ordering.

**Manual:** required only for end-to-end flow presentation once Phase 13 UI consumes it.

## 12.7 Stale in-mission save policy and campaign/narrative integration `[ ]`

Resolve the remaining ambiguity between an advanced campaign and an old in-mission quicksave. Choose the smallest proven policy: invalidate/delete the run's quicksave on successful completion, or retain it but refuse it through saved campaign/run-baseline identity. Do not allow silent resume of an already-completed old run against advanced campaign state.

Then exercise the combined two-mission flow: briefing/text → mission variant → optional sequence → save/load → completion transaction → campaign consequence → next mission variant.

**Done when:** the stale-save policy is explicit and user-understandable; no valid application state mixes an advanced durable campaign with a silently resumable obsolete run; the two-mission narrative/campaign path survives restart/relaunch; and the campaign/narrative extension API surfaces actually needed by content are identified for later stabilization.

**Automated:** stale-save refusal/deletion, durable relaunch/Continue candidate integrity, exactly-once progression across process-owner recreation, and two-mission integration.

**Manual:** required — user/playtester runs the representative two-mission flow and confirms prior-choice consequence, save/load continuity, completion progression, and stale-save behavior make sense.

**Phase gate:** two missions demonstrate a meaningful prior-choice consequence; writer/sequence workflows are usable; in-mission save recreates the same campaign-derived run variant; mission completion advances durable campaign state exactly once; stale in-mission saves cannot silently contradict advanced campaign state; and campaign/narrative extension boundaries have been exercised rather than guessed.

---

# Phase 13 — Player-facing product flow and application API completion

## 13.1 Finalized quicksave/quickload UX `[ ]`

Turn the already-proven save transaction into final ordinary-game feedback while retaining source-session-bound stable capture, latest-committed-slot semantics, compatibility refusal, and transactional replacement.

Define visible behavior for: successful F5/F9, rapid/repeated save/load requests, a save cancelled by world transition before capture, save-in-progress/load-in-progress ownership, incompatible/corrupt save, and an in-mission save invalid under the Phase-12 campaign/run baseline policy.

**Done when:** F5/F9 during ordinary gameplay produce clear non-blocking status/error feedback, application operations cannot race, invalid/stale saves explain why they cannot load, and no UX path changes underlying save truth/ordering.

**Automated:** application operation/state-machine coverage for every named outcome plus feedback state lifecycle.

**Manual:** required — user validates feedback clarity and repeated rapid save/load behavior on Windows.

## 13.2 Main menu / Continue / New Game `[ ]`

Connect the real durable CampaignState and valid in-mission save policy. `Continue` must choose one coherent durable state rather than ambiguously combining an advanced campaign snapshot with a stale quicksave.

**Done when:** New Game creates/reset the intended campaign baseline, Continue deterministically selects the valid continuation (current in-mission run when valid, otherwise campaign progression entry), no valid state offers an obsolete run, and menu actions cannot race world operations.

**Automated:** new campaign/reset, valid quicksave Continue, post-completion Continue, stale/corrupt save handling, durable process restart, and operation exclusion.

**Manual:** required — user exercises New Game/Continue before, during, and after one mission completion.

## 13.3 Pause, objectives, and settings presentation completion `[ ]`

Complete the existing pause/settings ownership and add final objectives presentation around the established mission/objective APIs. Do not invent a second pause/input-time policy.

**Done when:** pause reliably owns input/simulation/UI, settings that are actually supported persist/apply coherently, active/completed/failed/optional objectives are readable, and returning to play restores correct world/input state.

**Automated:** pause/input/time ownership, settings persistence/application, objective view-model state, and world replacement/menu transitions.

**Manual:** required — user validates readability/navigation and no pause/resume control leakage.

## 13.4 Inventory presentation `[ ]`

Build final player-facing inventory selection/use UI over the Phase-10 inventory owner. The UI does not become a second inventory store and must coexist with carried Junk/body hand ownership.

**Done when:** item selection, quantities, usable/unusable state, keys/mission items, and use feedback reflect semantic inventory truth; mouse/keyboard/controller focus ownership does not leak gameplay actions; and save/load/menu transitions rebuild UI from owner state.

**Automated:** UI↔owner synchronization, selection/use routing, disabled-hand states, stale-view rebuild after restore/world replacement, and input-domain isolation.

**Manual:** required — user validates selection speed/readability in stealth/combat contexts.

## 13.5 Mission map presentation — `OPEN` `[ ]`

The product requires a mission map, but its exact presentation/data source is not yet LOCKED. Resolve this with a focused spike rather than silently choosing a complex map subsystem.

Before implementation, compare the smallest viable options supported by real mission content (for example an authored static/annotated map versus a simple derived top-down representation) and choose one with the user. Do not require live omniscient geometry/NPC tracking unless explicitly adopted.

**Done when:** one accepted map presentation can be opened/closed through normal UI input ownership, represents the mission clearly enough for navigation, has an explicit authored/generated source-of-truth policy, and does not leak hidden gameplay information beyond the adopted design.

**Automated:** only objective UI/input/source validation appropriate to the chosen design.

**Manual:** required — user chooses/accepts the map presentation and validates usefulness on a representative mission.

## 13.6 Mission results/statistics `[ ]`

Build final results presentation over semantic `MissionRunState`/statistics already produced by gameplay: loot collected/available, kills, knockouts, detections/significant alerts, objectives, mission time, and mission-specific stats.

**Done when:** results are a detached snapshot of the completed run used by the Phase-12 completion transaction, no destroyed scene is scraped, totals reconcile with gameplay semantic owners, and returning/continuing campaign flow cannot mutate already-presented results.

**Automated:** statistic aggregation/invariants, completion snapshot detachment, duplicate-completion idempotence, and UI view-model reconstruction.

**Manual:** required — user checks a known playthrough's results against what actually happened.

## 13.7 Failure/death/recovery flow `[ ]`

Define final player death/failure recovery without checkpoint-only design. Recovery must choose among valid durable states already supported by the application (latest valid quicksave, campaign/menu state, or explicit restart) and must respect campaign/run baseline compatibility.

**Done when:** player death/failure cannot leave a half-alive session/input owner; recovery options are understandable; invalid/stale saves are not offered as successful recovery; restart/load/menu choices use existing transactional world replacement; and no automatic checkpoint system is introduced.

**Automated:** death/failure transition ownership, valid/invalid recovery candidate selection, load/restart/menu replacement, and stale-save/campaign compatibility.

**Manual:** required — user validates death/failure feedback and recovery choices in a mission with and without a valid quicksave.

**Phase gate:** the complete intended player flow is usable without developer shortcuts; save/menu/pause/objective/inventory/map/results/death UX consumes the established semantic/application owners rather than duplicating them; campaign/narrative/application-flow boundaries and exactly-once progression have been exercised; and only the extension surfaces proven by this complete flow are candidates for final stabilization.

---

# Phase 14 — Production scaling and replacement architecture

## 14.1 Art replacement hardening `[ ]`

Prove at production scale that models/textures/animations/HUD/menu assets can be replaced without changing gameplay rules. This hardens seams already proven by model-backed doors/props/lights; it is not the first asset-replacement proof.

**Done when:** representative world objects/characters/UI can swap final-quality assets while semantic identity, collision/interaction ownership, save state, light/exposure rules, and authored variants remain unchanged; fragile imported hierarchy is not gameplay API.

**Automated:** resource/variant validation and representative replacement fixtures where deterministic.

**Manual:** required — artist/user spot-checks final replacement workflow and visual/collision alignment.

## 14.2 Audio replacement hardening `[ ]`

Replace representative placeholder audio while preserving semantic gameplay-noise identity/strength/propagation.

**Done when:** final audio asset swaps do not change AI-hearing/gameplay-noise truth, positional playback remains useful, and missing/bad audio references fail without corrupting semantic sound events.

**Automated:** semantic sound invariance and asset-reference validation.

**Manual:** required — user validates positional/readability mix without changing gameplay hearing balance.

## 14.3 Representative-scale production mission `[ ]`

Build a substantially larger mission to stress real content volume. Before implementation, record target content counts relative to the Phase-10 slice (area/rooms, guards, lights, doors, props, loot, acoustic zones, rules/events, runtime objects) and make the mission materially larger across the systems that actually drive cost.

Do not choose arbitrary huge counts unrelated to intended game content; the target should approximate a plausible production mission while being at least a clear multi-fold stress increase over the vertical slice for key systems.

**Done when:** the mission is playable end-to-end through normal tooling, validates without core-edit workarounds, stresses all major world/gameplay systems concurrently, and exposes any scale-specific authoring/runtime problems for 14.4–14.5.

**Automated:** content-validation/load smoke plus deterministic scale counters and targeted regressions for failures discovered.

**Manual:** required — user/playtester validates that the large mission remains playable and representative rather than a synthetic benchmark room.

## 14.4 Performance budgets and optimization `[ ]`

Profile the 14.3 mission on a recorded supported Windows reference environment. Before optimization, set explicit acceptable budgets/targets for frame time and the expensive subsystems actually observed.

Measure at least: NPC vision/hearing, acoustic graph/portals, gameplay exposure, nav, mission events/rules, combat where active, runtime persistence, synchronous save snapshot capture, encoded save size/durable-write time, and prop support checks.

Optimize proven bottlenecks without weakening semantic correctness or stable-boundary snapshot coherence.

**Done when:** repeatable captures show the representative mission meets the adopted budgets or every remaining miss is explicitly accepted/scoped; optimizations retain behavioral regressions; and budget/reference-environment data is documented.

**Automated:** micro/perf regression guards only where stable; full deterministic correctness suite remains the gate for optimization changes.

**Manual:** required — Windows operator records final reference measurements; user validates no obvious gameplay/visual regression from optimization.

## 14.5 Shipping-oriented build/content validation `[ ]`

Extend production validation with common scale/shipping errors discovered through 14.1–14.4: missing replacement assets, broken references/variants, duplicate IDs, unsupported persistence types, invalid campaign/text content, budget-threatening pathological authoring detectable statically, and other real production mistakes.

**Done when:** a clean production content validation command catches the supported error classes before shipping/export, reports source-oriented diagnostics, and passes the representative-scale mission.

**Automated:** invalid fixture coverage for every production validation rule plus the full real-content validation command in CI where practical.

**Manual:** none unless the validator has target-specific Windows/export behavior; then Windows operator confirms it.

**Phase gate:** architecture and tooling hold under representative mission complexity/content volume; asset/audio replacement does not alter gameplay semantics; adopted performance budgets are measured on a supported reference environment; and common production authoring failures are caught before shipping.

---

# Phase 15 — Final external handoff

## 15.1 Production template/docs `[ ]`

Document only workflows and extension points that survived production use. Consolidate mapper, mission logic/script, inventory/effect, campaign/narrative, save compatibility, validation/debug, asset replacement, build/test, and troubleshooting workflows without duplicating living sources of truth.

**Done when:** a fresh developer can follow the docs from checkout/tool setup through creating/validating/running content, understands source vs generated ownership and supported extension boundaries, and no documented command/path is stale.

**Automated:** documentation link/path/command checks where practical plus clean-checkout CI.

**Manual:** required — someone other than the primary implementer follows the setup/create/run path before 15.2.

## 15.2 External mapper/scripter test `[ ]`

A developer familiar with Godot/TrenchBroom but not Vark internals builds a small mission using the production template/docs. The brief must require ordinary mapping plus one special scripted behavior through the supported mission API, at least one guard/stealth interaction, ordinary model-backed objects/lights, objective/exit logic, and validation/run.

The external creator may use documented APIs/tools and normal diagnostics, but ordinary success must not require modifying core gameplay, generated FuncGodot output, private WorldSession internals, or undocumented asset hierarchy.

**Done when:** the external creator completes the playable task, can debug at least one intentional content mistake using supported tooling, and independently identifies the correct extension path for the special scripted behavior.

**Automated:** normal CI/content validation for the produced/fixed content; no automated substitute for the external-human purpose.

**Manual:** required — external developer unfamiliar with Vark internals.

## 15.3 Handoff gap fixes `[ ]`

Fix unclear APIs, missing validation, undocumented ownership, template problems, or tooling gaps actually discovered by 15.2. Do not invent cleanup work to justify the step; if the external test exposes no material gap, record that result and complete the item without a manufactured refactor.

**Done when:** every blocking/significant handoff issue has a root-cause fix or explicit accepted deferral, docs/template/tooling match the final behavior, and the external creator can repeat the previously blocked operation successfully.

**Automated:** regression/validation coverage for deterministic fixes plus full CI.

**Manual:** required only for externally observed workflow problems — the external creator or equivalent cold developer repeats the affected task.

**Phase gate:** a new creator can build ordinary Vark content without modifying core gameplay, can add special scripted content through supported APIs, can diagnose common mistakes with documented tools, and the production handoff no longer depends on private tribal knowledge.

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

1. **8.4** build the actual 10–15 minute representative stealth mission from already-proven ordinary systems; record concrete gaps instead of bypassing them.
2. **8.5** prove one genuinely unusual mission-specific GDScript behavior through the provisional semantic API.
3. **8.6** exercise representative real-mission save/load plus meaningful mission-revision and global semantic-version refusal.
4. **8.7** close only the concrete authoring/validation/debug gaps exposed by the mission.
5. **8.8** run the independent cold-author modification test before declaring Phase 8 complete.
6. **Phase 9** finish body handling, establish combat input/loadout and real vitality/damage ownership **before** block/parry/direct-combat tuning, then validate the TARGET grammar with the required scenario matrix.
7. **Phase 10** add real inventory, prove one runtime-persistent thrown tool + active-transient save policy, extend effects around Phase-9 vitality, prove one interruptible NPC routine, and integrate everything in the complete slice.
8. **Phase 11** stabilize only the world/gameplay APIs and mapper presets proven by Phases 8–10; then validate with a second cold author.
9. **Phase 12** add typed durable campaign state, one real cross-mission consequence, writer/sequence workflow, run-provenance saving, exactly-once completion, and stale-save policy.
10. **Phase 13** finish player-facing save/menu/pause/objective/inventory/map/results/death flow; keep the exact mission-map presentation OPEN until its focused user decision.
11. **Phase 14** harden asset/audio replacement, stress a representative-scale mission, adopt/measured performance budgets, and close shipping validation.
12. **Phase 15** produce final docs/template, run the external mapper/scripter handoff, and fix only gaps that handoff actually exposes.
The most important sequencing rules are:

> **Do not build the reusable immersive-sim platform first and hope Vark fits it later. Build Vark in playable slices and let the platform emerge from proven needs.**

> **Durable gameplay truth is explicit semantic state. Engine callbacks, timers, Resources, coroutines, and scene topology are implementation machinery, not alternate sources of truth. Input-owned view pose is the narrow accepted exception in cadence, not an alternate path for world consequences.**

> **Do not stabilize an abstraction after proving it against only one side of a future cross-cutting requirement. Prove the boundary with the systems that actually depend on it, then freeze only that proven surface.**
