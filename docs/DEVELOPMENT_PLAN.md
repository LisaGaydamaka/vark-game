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
- post-push GitHub Actions validation for the authoritative regression barrier

The accepted player-controller behavior and feel are **LOCKED**.

Its implementation is not frozen. Input sampling, command routing, component ownership, pause/cutscene gating, mouse ownership, scene structure, and other internals may be refactored as needed so long as accepted baseline response/feel remains unchanged.

Later gameplay may deliberately apply explicit contextual modifiers such as carrying a body. Such modifiers must be owned by the gameplay feature that requests them and must not silently rewrite the accepted unmodified locomotion contract.

The project does not yet have the complete production gameplay platform: application flow, mission loading, stable persistent identities, saveable world state, interaction, doors, gameplay lighting/exposure, acoustic propagation, NPC/nav/stealth, mission logic, bodies/combat, inventory, campaign state, dialogue presentation, cutscenes, and production authoring/validation.

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

- TrenchBroom: geometry and ordinary spatial entities
- typed Godot Resources/config: reusable non-spatial authored configuration
- GDScript: genuinely procedural or unusual mission behavior through supported APIs
- writer-facing text data: dialogue/narrative content without gameplay-code editing

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

A pending save request is cancelled if its source session stops before capture; it never retargets to the replacement session. Once the detached snapshot exists, the write may finish after source-world teardown.

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

Primary spatial authoring tool for brush geometry/materials, routes/rooms, player starts, guards/patrol markers, doors/lights, loot/containers/props, triggers/exits, and ordinary spatial mission objects.

The `.map` file is authored source. Generated/imported geometry must not contain irreplaceable manual edits.

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
        mission.tres
        mission.gd
        dialogue/
        sequences/
        ui/
        assets/
```

`mission.gd` is optional. A simple mission must not require custom GDScript.

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
- tracked `.map.import` sidecars are generated import metadata rather than authored mission truth and must not receive irreplaceable manual edits; keep the current sidecars until the FuncGodot import/reimport workflow explicitly proves they can be removed safely;
- do not blanket-place text `.map` source in Git LFS merely because a map becomes large; evaluate LFS for future large binary assets where Git text diffs are not useful;
- existing `test.map`, `test2.map`, and `test3.map` remain development/graybox source for now;
- `maps/level export2.map` remains tracked and is conservatively classified as authored/development map source. Its filename and roughly 29.5 MB size are not evidence that it is obsolete. Retain it unless a future explicit content-ownership decision deliberately retires/reclassifies it; do not delete, rename, or LFS-migrate it by inference.

No destructive cleanup is implied by the conservative `level export2.map` classification. Future retirement/reclassification of that source is a separate explicit content decision, not unfinished Phase 0 cleanup.

**Done when:** generated recovery/local state is excluded and all remaining tracked map/import files have explicit source/generated ownership. Satisfied by the policy above.

**Automated:** the clean-checkout import/current authoritative movement CI remained green after the repository cleanup already applied; this classification patch does not delete or transform map content.

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

## 1.1 Application root `[~]`

Create stable ownership for game flow, current mission/world session, player, UI, and transitions.

F5 should launch the Vark application rather than an arbitrary development scene.

Top-level load/restart/mission-transition/exit operations have one application owner and cannot race each other as competing subsystem transitions. Future world-bound requests must carry/verify their source session rather than implicitly operating on whatever world happens to be current later.

The project now boots through `res://application/Application.tscn`. The application owns a persistent world host and UI root, installs the current development `VarkTest` world, resolves the current player through a semantic player marker, exposes the current session identity for future source-session checks, and provides one exclusive top-level operation guard. Actual stop/freeze/teardown/replacement mechanics remain Phase 1.2 rather than being pulled into this item.

**Done when:** F5 launches the application root; that root owns the current world, player, persistent UI root, session identity, and exclusive top-level operation state without changing accepted player behavior.

**Automated:** the application regression suite verifies the configured F5 main scene, current world/player/UI ownership, current/stale session identity checks, and rejection of overlapping top-level operations. The authoritative all-tests barrier also runs the existing movement/behavior traces unchanged.

**Manual:** Windows x64 user/playtester — press F5 and confirm the application opens the current `VarkTest` world/player normally and ordinary movement/mouse-look startup and response still feel unchanged.

## 1.2 World-session lifecycle, stop, replacement, and teardown `[ ]`

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

## 1.3 Gameplay-input boundary, domains, view pose, and frame lifetime `[ ]`

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

## 1.4 Pause/UI/cutscene input, simulation, and gameplay-time ownership `[ ]`

Define arbitration between gameplay, pause, inventory/objectives/map, cutscenes/sequences, and menus.

No unintended gameplay input leaks through inactive ownership.

Define one explicit pause simulation policy: ordinary gameplay simulation and gameplay time stop coherently unless an explicit application-owned exception is intentionally allowed to continue.

Do not implement meaningful gameplay durations from wall-clock time. Search durations, mechanism progress, stagger, delayed gameplay actions, and similar future state must be based on simulation-owned time/progress.

Mouse capture/release and resumed gameplay state must restore correctly without stale gameplay edges or partially armed hold/release gestures.

## 1.5 Minimal application/menu shell `[ ]`

Provide functional New Game/development start, Quit, and only settings that actually work.

## 1.6 Development mission launch `[ ]`

Support a fast development route for launching a selected mission/playground without manually opening scenes.

**Phase gate:** application ownership is clear; a world can build non-playing, enter play, stop, tear down, and be replaced without stale work; gameplay time follows world simulation policy; gameplay-input edges and gesture cancellation have deterministic lifetime without changing accepted look/UI cadence; the player view pose can be sampled/captured coherently; and accepted player behavior remains intact.

---

# Phase 2 — Minimal mission, authored identity, and TrenchBroom proof

Goal: prove the real authoring/import/identity path before save/load or broad gameplay systems depend on it.

## 2.1 Mission package convention `[ ]`

Create the initial mission folder ownership convention and a tiny playground mission.

## 2.2 Minimal MissionDefinition `[ ]`

Include only fields currently required to load the playground: mission ID, map/world reference, semantic reference/selection for the map-authored player start, and minimal metadata.

Do not duplicate a player-start transform in `MissionDefinition` when the TrenchBroom map owns it.

Reserve one authoritative mission metadata owner for future `mission_content_revision`.

## 2.3 Persistent identity feasibility and authoring-workflow proof `[ ]`

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

## 2.4 Persistent IDs `[ ]`

Implement the proven authored persistent identity mechanism. Missing/duplicate IDs fail closed with useful diagnostics.

## 2.5 Optional semantic content IDs `[ ]`

Implement author-facing IDs only for entities mission logic actually needs to address.

## 2.6 Minimal registry `[ ]`

Provide world-session-owned registration/lookup with duplicate/missing reporting. Do not force behavior into a giant base entity class.

## 2.7 TrenchBroom Vark entity foundation `[ ]`

Create only the entity vocabulary needed for the playground: player start, generic semantic marker, minimal exit, and spike entities as they arrive.

## 2.8 Reimport stability `[ ]`

Prove `edit .map → save → import/rebuild → run` without unrelated repair and with stable persistent identity.

## 2.9 Basic content validation `[ ]`

Validate duplicates, missing required mission objects, invalid references, and identity errors that exist at this stage.

**Phase gate:** a tiny mission loads from the real package/TrenchBroom path, starts, exits, keeps stable authored identities through representative editing/reimport, and uses an idempotent source-of-truth identity workflow.

---

# Phase 3 — Small contracts, isolated spikes, then the five-minute stealth slice

Goal: answer dangerous subsystem questions independently enough to debug them, then force them to collide in one real playable route before broad frameworks are committed.

The integrated graybox contains one room/corridor arrangement, ordinary door, gameplay light, two footstep surfaces, throwable/stackable prop, simple patrolling guard, primitive vision/hearing, one audible typed NPC line, one objective, and one exit.

## 3.1 Minimal interaction contract `[ ]`

Introduce only enough common behavior for center-view target selection, range/occlusion/state eligibility, one primary interaction command, and minimal highlight/feedback.

The ordinary door and physical prop use the same interaction contract.

Interaction ownership, not every interactable object, decides whether ordinary world interaction is currently available. In particular, later held-prop/body states should not require every door/switch/loot object to know private carrying state.

## 3.2 Minimal semantic gameplay-event queue and stable boundary `[ ]`

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
- engine callbacks outside the controlled pass may update presentation/input-owned view state or queue future semantic work but cannot race durable world state across that boundary.

Do not create a general scheduler or author-facing rule language here.

## 3.3 Minimal semantic gameplay-sound event `[ ]`

Separate gameplay-significant sound from presentation audio before acoustic propagation is prototyped.

## 3.4 Ordinary door micro-proof `[ ]`

Prove interaction, collision/obstruction, open/closed presentation, vision-blocking relationship, acoustic integration seam, NPC/navigation integration seam, semantic events, and semantic state capture/apply.

At this step, prove the **door-side contracts/seams** needed by later acoustics and NPC/navigation use. Do not pull the primitive guard/navigation implementation from 3.7 into 3.4 merely to exercise that future consumer. The first real guard/nav proof in 3.7 must exercise this same ordinary door seam; if that integration exposes a defect, correct the seam rather than inventing a second door/nav model.

Do not build keys/locks/barred behavior yet unless required by the proof.

## 3.5 Thief-style prop micro-proof `[ ]`

Implement ordinary prop states sufficient to prove:

```text
settled → held → dropped/thrown/unsupported → settling → settled
```

Protect the LOCKED rules:

- supported props do not topple/spin/roll/drift;
- edge-supported boxes remain;
- simple supported stacks remain still;
- removing a simple lower support causes unsupported objects above to fall until supported without uncontrolled explosion/scatter;
- settled props become stationary again;
- a held ordinary prop uses the intended first-person held presentation;
- the player cannot freely rotate a held ordinary prop;
- ordinary world interaction is unavailable while carrying an ordinary prop, enforced at interaction/input ownership rather than by checks copied into every interactable.

Do not build a universal support-graph engine. If the small fixture appears to require one, reconsider the concrete representation.

## 3.6 Acoustic propagation micro-proof `[ ]`

Use a test layout with open room, separated room, open doorway, closed door, and L-shaped corridor.

Prototype until footsteps, impacts, NPC reactions, and speech audibility behave intuitively. If the model needs authored topology, include the normal TrenchBroom edit/reimport workflow and mapper authoring cost in the proof.

## 3.7 Primitive guard/nav micro-proof `[ ]`

One NPC spawns from authored content, follows a simple patrol, navigates imported geometry, reacts to the ordinary door through the door-side NPC/navigation seam established in 3.4, and survives normal map reimport/nav rebuild.

This step is the first real consumer proof of the 3.4 door/nav seam. Reuse the same ordinary door contract; do not add a second guard-specific door model merely to make navigation work.

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

Use one serialized writer per logical slot or a monotonic save generation so an older request cannot commit after a newer one. F9-equivalent load reads the latest fully committed save, never a temporary/in-progress write.

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

Keys/locks/barred restrictions, authoring properties, obstruction behavior, NPC use, events, save state.

## 6.3 Loot, keys, minimal possession, and run-stat ownership `[ ]`

Collected loot becomes abstract recorded value/count.

Introduce only minimal semantic possession needed now, such as owns key/content item X, loot possession/value, and small abstract mission-item ownership when genuinely needed.

Doors/mission logic query semantic possession rather than depending on future inventory UI/selection.

When the first mission statistic becomes real (loot is likely first), introduce a tiny semantic `MissionRunState`/statistics owner for run counters rather than letting each subsystem keep duplicated counters or making the future results UI scrape private state. Later kills/knockouts/alerts/time extend the same owner as they become real.

Because collecting authored loot removes an authored world instance, implement the minimal removed-authored tombstone representation and prove collected loot remains absent after restore without replaying collection/stat consequences.

## 6.4 Containers `[ ]`

Physical opening/exposed contents where appropriate.

## 6.5 Switches and switchable/extinguishable lights `[ ]`

Integrate with gameplay light state, sound/events, and saves.

## 6.6 Physical prop completion `[ ]`

Expand support relationships, stacking/climbing, held presentation, drop/throw, impacts/noise, obstruction, and save state only as real content needs them.

Preserve the Phase 3 held-prop interaction restrictions through central interaction/input ownership.

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

The mission uses real TrenchBroom geometry/entities, multiple routes where practical, doors/keys, darkness/light, surfaces, throwable props, guard patrol/investigation, typed audible speech, loot/container interaction, objectives, one declarative rule, one mission-specific GDScript example where useful, quicksave/load, restart, and minimal results/run-stat inspection.

Full polished results UI remains Phase 13; Phase 8 must consume the real semantic `MissionRunState` rather than create a temporary scraper/counter system.

## 8.1 Mapper workflow proof `[ ]`

A mapper should not need hand-edits in generated output.

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

Promote ordinary entities/fields proven in real mission authoring.

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

Models/textures/animations/HUD/menu assets can be replaced without changing gameplay rules.

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

Exercise create/move/reorder/duplicate/delete/reimport plus idempotent source writeback/repair.

## Gameplay-event/stable boundary

Prove FIFO for emitted order, nested append, lifecycle suppression, stale-world rejection, synchronous event drain, runaway-cascade detection, controlled semantic mutation, supported script-command routing, and one true stable boundary.

## Door / acoustic / lighting / prop / nav integration

Keep small representative fixtures and progressively use the same ordinary gameplay objects rather than subsystem-specific fakes.

The prop fixture includes locked held-prop presentation/no-free-rotation/no-ordinary-interaction behavior.

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
- coherent stable-boundary capture of event-driven player view pose;
- controlled semantic mutation and stable-boundary semantics, including mission-script commands requested out of pass;
- event FIFO/re-entrant/lifecycle behavior and runaway-cascade failure diagnostics;
- resolved random-choice persistence when choices have become gameplay truth;
- persistent-ID uniqueness/editing/reimport/repair/writeback/idempotence;
- semantic-ID duplicate/missing-reference errors;
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

1. Finish `1.1` by confirming the post-push `Regression suite` is green and running the focused Windows F5 startup/player check; after acceptance, mark it `[x]` during the next authorized patch.
2. Implement `1.2` world-session lifecycle, stop/freeze, teardown/replacement ownership, and stale-work rejection without building save candidate infrastructure.
3. Implement `1.3` gameplay-input boundary/view-pose ownership and gesture cancellation, then `1.4` pause/gameplay-time ownership.
4. Complete the minimal application/menu and development-launch work in `1.5`–`1.6` only after those ownership boundaries are proven.
5. Phase 2 minimal mission + persistent-identity feasibility/idempotent writeback + TrenchBroom reimport stability.
6. Phase 3 interaction/event/sound contracts + controlled semantic mutation + true stable gameplay boundary.
7. Phase 3 door/prop/acoustic/nav/light proofs and integrated stealth slice + actor identity proof.
8. Phase 4 source-session-bound detached snapshot capture + coherent view pose + save-slot ordering + resolved-choice restore + simplest proven transactional restore topology + global/mission compatibility policy.
9. Phase 4 crude hostile compatibility.
10. Phase 5 harden stealth, preserving resolved AI choices through save/load.
11. Phase 6 minimal possession + semantic `MissionRunState` + removed-authored persistence.
12. Phase 7–8 mission logic/provisional script API + first proper mission; mission-local fact scopes only; supported commands preserve controlled mutation; explicit semantic long-running state; pull runtime persistence forward only if real content needs it.
13. early cold-author review.
14. Phase 9 establish real vitality/damage ownership while prototyping combat.
15. Phase 10 inventory/effects extend that vitality boundary + stable runtime IDs + active-runtime-transient save proof + complete vertical slice.
16. Phase 11 stabilize **world/gameplay** production APIs only.
17. Phase 12 prove/stabilize campaign/narrative boundaries + exactly-once durable mission completion.
18. Phase 13 complete player flow/application boundaries and final extension-surface stabilization, including coherent Continue/stale-save behavior.
19. production scaling/handoff.

The most important sequencing rules are:

> **Do not build the reusable immersive-sim platform first and hope Vark fits it later. Build Vark in playable slices and let the platform emerge from proven needs.**

> **Durable gameplay truth is explicit semantic state. Engine callbacks, timers, Resources, coroutines, and scene topology are implementation machinery, not alternate sources of truth. Input-owned view pose is the narrow accepted exception in cadence, not an alternate path for world consequences.**

> **Do not stabilize an abstraction after proving it against only one side of a future cross-cutting requirement. Prove the boundary with the systems that actually depend on it, then freeze only that proven surface.**
