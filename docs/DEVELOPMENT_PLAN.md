# Vark Development Plan

This document defines the ordered systems-development roadmap for Vark.

The final goal is:

> **Build Vark as a complete immersive-sim game through representative playable missions. Whenever a gameplay or authoring pattern has been proven by real mission use, extract and stabilize the reusable platform needed for future missions.**

The finished production target remains:

> **A mapper, mission scripter, writer, and artist can create production Vark missions without modifying Vark's core gameplay systems.**

Vark is not built as a speculative general immersive-sim SDK first. Reusability is extracted from systems that have survived actual gameplay integration.

The roadmap therefore follows one rule above all others:

> **Introduce only the smallest cross-cutting contracts that several near-term systems genuinely need; keep everything else local until gameplay proves it reusable.**

---

# Status notation

- `[ ]` — not implemented
- `[~]` — implemented/substantial but still awaiting required validation/follow-up
- `[x]` — required automated checks passed and the user accepted relevant manual/playtest behavior

Design state:

- **LOCKED** — accepted behavior/product rule; internal implementation may change
- **TARGET** — intended design requiring prototype/playtest proof
- **OPEN** — known problem whose correct solution should be discovered by a focused spike

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

The accepted player-controller behavior and feel are **LOCKED**.

Its implementation is not frozen. Input sampling, command routing, component ownership, pause/cutscene gating, mouse ownership, scene structure, and other internals may be refactored as needed so long as the accepted baseline response/feel remains unchanged.

Later gameplay may deliberately apply explicit contextual modifiers such as carrying a body. Such modifiers must be owned by the gameplay feature that requests them and must not silently rewrite the accepted unmodified locomotion contract.

The project does not yet have the complete production gameplay platform: application flow, mission loading, stable persistent identities, saveable world state, interaction, doors, gameplay lighting/exposure, acoustic propagation, NPC/nav/stealth, mission logic, bodies/combat, inventory, campaign state, dialogue presentation, cutscenes, and production authoring/validation.

---

# Development method

## 1. Build vertically

Every major phase must leave behind a playable integrated result.

Do not build many disconnected mechanics and integrate them near the end.

The first representative stealth mission appears early, initially tiny and ugly.

## 2. Micro-proof → integrated proof → contract → generalize

For uncertain systems:

1. isolate the smallest fixture that can answer the system's hardest question;
2. prove the dangerous assumption in that fixture;
3. integrate the result into the actual playable path;
4. test/playtest the cross-system behavior;
5. define the accepted behavior/API only after evidence exists;
6. generalize only the patterns that proved reusable.

The isolated proof exists to make failures diagnosable. It does not replace the integrated proof.

## 3. Extract a shared abstraction only when there is a current shared need

Before introducing a framework, ask:

> **Do at least two real near-term gameplay systems need the same contract now?**

If not, keep the behavior local.

If yes, extract the smallest semantic contract that removes real coupling.

Do not create universal entity, event, effect, interaction, AI, or scripting frameworks around hypothetical future content.

## 4. Authoring develops together with gameplay

If a feature is ordinary mission content, its normal authoring path must be developed with it.

- TrenchBroom: geometry and ordinary spatial entities
- typed Godot Resources/config: reusable non-spatial authored data
- GDScript: genuinely procedural or unusual mission behavior through stable public APIs
- writer-facing text data: dialogue/narrative content without gameplay-code editing

## 5. Do not create a new programming language

The common rule layer remains:

> event → conditions → actions

It is intentionally small.

Loops, arbitrary locals, unrestricted expression evaluation, nested general control flow, and arbitrary object manipulation belong in GDScript rather than expanding the rule system.

## 6. Stable APIs follow proven use

Mission scripts must not depend on private scene-tree paths, guard internals, movement internals, arbitrary internal signals, or undocumented singleton state.

However, do not invent a broad public API before representative mission code needs it.

## 7. Saveability is designed with stateful features; the save framework comes later

Every stateful feature added must define, at the semantic level:

```text
capture meaningful state
apply meaningful state
reconcile derived/runtime references after restore
```

This does **not** mean building the full save service early.

It means a door, prop, NPC, light, objective, or actor must not be designed around unsaveable private runtime state and then retrofitted later.

Derived/transient data such as nav paths, temporary physics handles, caches, and runtime object references should normally be reconstructed rather than serialized blindly.

## 8. Debugging is a production feature

As soon as a system can fail invisibly, add the smallest useful diagnostics.

Examples: entity-ID validation, acoustic path/debug, NPC perception state, nav path, mission-rule trace, save/restore warnings.

## 9. Performance is checked incrementally

The representative-scale stress mission remains late, but expensive systems get focused stress fixtures shortly after introduction.

Do not wait until production scale to discover an architecture is asymptotically wrong.

---

# Minimal cross-cutting contracts

These are the few shared contracts that intentionally arrive before the full systems built on them.

## Application/world lifecycle

The application owns whether a mission world is allowed to produce gameplay consequences.

A minimal conceptual lifecycle is:

```text
BUILDING
→ RESTORING when loading a save, otherwise READY
→ PLAYING
```

Exact names may change, but the invariant is fixed:

> **A world can be instantiated and reconciled without AI, rules, perception, objectives, gameplay sounds, or other consequences firing merely because nodes became ready.**

Pause/menu/cutscene input ownership is related but is not a substitute for the world lifecycle.

## Semantic player commands

Application input policy is outside locomotion.

```text
Godot Input
→ application/input router
→ semantic PlayerCommand frame
→ accepted player behavior
```

The movement controller owns response to commands; it does not own whether gameplay is currently permitted to receive them.

## Semantic gameplay events

Before a full mission-rule system exists, systems may use a very small internal semantic event envelope for real integration needs.

Conceptually:

```text
GameplayEvent
    type
    source identity when relevant
    minimal typed payload when relevant
```

This is not yet an authoring language and not a giant global signal dump.

Events must describe meaningful gameplay facts such as a door changing state, a gameplay sound occurring, or an actor awareness state changing rather than expose private helper signals.

## Semantic gameplay sounds

The first acoustic spike needs a stable distinction between presentation audio and gameplay-significant sound.

A minimal gameplay sound event should describe only what the spike needs, such as source/origin/category and semantic strength/profile reference.

Propagation, audibility, surfaces, portals/graphs, and tuning are allowed to evolve after the spike.

## Semantic state ownership

Stateful systems expose meaningful state at their ownership boundary rather than asking the save system to inspect arbitrary scene trees.

The save coordinator introduced later orchestrates these contracts; it does not define every system's meaning after the fact.

---

# Identity model

Do not conflate author-facing references with save identity.

## Persistent instance identity

Every saveable concrete authored entity gets a stable internal `persistent_id`.

Requirements:

- unique within the mission/world scope
- stable across ordinary TrenchBroom reimport
- moving an entity does not change it
- entity order does not change it
- renaming internal Godot nodes does not change it
- duplicating an authored entity creates a new identity
- save snapshots use this identity

The identity must be owned by authoritative authored data or another explicitly persistent source-of-truth mechanism. It must **not** be heuristically derived from mutable transform, entity order, generated node path, geometry hash, or similar data.

Mission authors should not manually invent names for every chair, lamp, box, or loot instance merely so save/load works.

The authoring workflow must make missing/duplicate persistent identities easy to generate or repair, and duplicate identity must fail closed rather than silently restoring state to the wrong object.

## Optional semantic content identity

Entities that mission logic needs to address may additionally have an author-facing `content_id`, for example:

```text
door.vault
guard.library
marker.guard_backup
trigger.escape
```

Requirements:

- optional unless content/scripts need semantic reference
- duplicate detection
- clear missing-reference errors
- independent of private Godot paths

Mission scripting uses semantic IDs; persistence uses persistent instance IDs.

---

# Save/restore lifecycle target

Do not restore by fully starting normal gameplay and then overwriting it.

Support two explicit boot intentions:

```text
FRESH_START
RESTORE_SAVE
```

Restore should conceptually perform:

```text
create mission world while non-playing
→ instantiate authored entities
→ register persistent and semantic identities
→ apply raw semantic snapshots
→ restore MissionState
→ restore player semantic state
→ restore mission-script state
→ resolve/reconcile references and derived state
→ mark world ready
→ enable AI, events, rules, perception, and gameplay updates
→ after_restore/world_ready hook
→ resume gameplay
```

During the restore transaction, ordinary consequences must not fire:

- NPC decisions
- objective evaluation
- mission rules
- perception
- gameplay sound emission
- door-change consequences
- loot consequences
- alarm propagation

Loading a save must not itself become gameplay.

---

# Production toolchain

## TrenchBroom

Primary spatial authoring tool for:

- brush geometry/material assignment
- routes/rooms
- player starts
- guards/patrol markers
- doors/lights
- loot/containers/props
- triggers/exits
- other ordinary spatial mission objects

The `.map` file is authored source.

Generated/imported geometry is generated content and must not contain irreplaceable manual edits.

## Godot

Primary tool for:

- core game development
- reusable gameplay resources/configuration
- mission definitions/state
- testing
- validation/debugging
- running missions
- campaign/narrative infrastructure

## GDScript

Used for:

- unusual mission logic
- special puzzles/security
- special NPC behavior
- unique interactables/tools/events

Mission GDScript uses stable Vark APIs.

## Writer-facing text data

Dialogue/subtitles/briefings should use stable text-oriented data where practical. Exact formats may evolve; likely CSV, JSON/localization tables, or typed narrative resources where relationships require them.

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

`mission.gd` is optional.

A simple mission must not require custom GDScript.

---

# Phase 0 — Stabilize the development ground

Goal: prevent repository/tool drift from invalidating the behavior protection used by every later refactor.

## 0.1 Existing locomotion/traversal `[x]`

Accepted behavior includes ground movement, sprint, crouch, jump, air movement, support/collision, steps, ledge catch/hang/shimmy/corners, mantle, and mouse look.

**Contract:** accepted baseline behavior/feel is frozen; implementation is not.

## 0.2 Existing movement regression suite `[x]`

Keep the deterministic headless movement suite.

Tests protect accepted behavior, not current internal architecture.

## 0.3 Repository cleanup `[ ]`

Before adding more fixtures/content, review and establish policy for:

- TrenchBroom autosaves
- generated imports
- experimental maps
- large `.map` source files
- future binary assets/LFS
- `.gitignore`
- source vs generated ownership

Current repository state already contains autosave material and a very large map source, so this is first-order development work rather than optional housekeeping.

## 0.4 Tool version contract `[ ]`

Pin/document exact production versions/build expectations for:

- Godot
- Jolt integration implied by that Godot build
- FuncGodot
- TrenchBroom

A physics-sensitive regression suite is not a reliable contract if different machines silently run materially different tool/runtime builds.

## 0.5 Continuous integration for the existing barrier `[ ]`

Once the exact runner environment is defined, run the existing authoritative headless command in CI on `test` pushes and pull requests.

Do not wait for many additional suites before proving the basic CI path.

## 0.6 Traversal regression expansion `[ ]`

Add deterministic coverage where practical for:

- ledge catch
- hang
- shimmy
- supported corners
- mantle
- release
- suppression/regrab

## 0.7 Behavior-trace protection for controller refactors `[ ]`

Before major input/controller plumbing changes, add enough semantic trace coverage to show that equivalent command sequences produce equivalent accepted behavior within intended numeric tolerances.

Do not require byte-for-byte internal state equality.

**Phase gate:** repository ownership/tool versions are controlled, the existing barrier runs in CI, and accepted player behavior is sufficiently protected for application/input refactors.

---

# Phase 1 — Application ownership, lifecycle, and input boundary

Goal: turn the movement project into a controlled application without changing accepted player feel and without baking gameplay side effects into node startup.

## 1.1 Application root `[ ]`

Create stable ownership for:

- game flow
- current mission/world
- player
- UI
- transitions

F5 should launch the Vark application rather than an arbitrary development scene.

## 1.2 Minimal world lifecycle gate `[ ]`

Create the smallest application-owned lifecycle that permits a mission world to exist before normal gameplay consequences are enabled.

It must support future restore without yet implementing serialization.

Prove that systems can be instantiated while the world is non-playing and become active only when the application allows it.

## 1.3 Gameplay input boundary `[ ]`

Refactor the player so locomotion consumes semantic gameplay commands rather than owning application-wide input policy.

Conceptually:

```text
Godot Input
→ input router / gameplay input source
→ PlayerCommand frame
→ existing movement behavior
```

The player controller may be reorganized internally, but its accepted response/feel must remain unchanged.

## 1.4 Pause/UI/cutscene input ownership `[ ]`

Define arbitration between:

- gameplay
- pause
- inventory/objectives/map
- cutscenes/sequences
- menus

No unintended gameplay input leaks through inactive ownership.

Mouse capture/release must restore correctly.

## 1.5 Minimal application/menu shell `[ ]`

Provide functional New Game/development start, Quit, and only settings that actually work.

## 1.6 Development mission launch `[ ]`

Support a fast development route for launching a selected mission/playground without manually opening scenes.

**Phase gate:** application ownership is clear, a mission can exist while gameplay is disabled, and the player behaves identically through the semantic input boundary.

---

# Phase 2 — Minimal mission, authored identity, and TrenchBroom proof

Goal: prove the real authoring/import/identity path before save/load or broad gameplay systems depend on it.

## 2.1 Mission package convention `[ ]`

Create the initial mission folder ownership convention and a tiny playground mission.

## 2.2 Minimal MissionDefinition `[ ]`

Only include fields currently required to load the playground: mission ID, map/world reference, player start, and minimal metadata.

Do not pre-design every future campaign/narrative field.

## 2.3 Persistent identity feasibility proof `[ ]`

Before building a registry/save architecture, prove a concrete authoring workflow can satisfy all of these operations:

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

The original entity must retain its identity through ordinary edits; the duplicate must receive a distinct identity; unrelated edits must not reassign IDs.

Identity may live directly in `.map` entity properties or another explicitly persistent authored source, but the workflow must be simple enough for normal mission production.

Do not proceed by assuming transform/path/order/hash-derived identity will be good enough.

## 2.4 Persistent IDs `[ ]`

Implement the proven authored persistent identity mechanism for saveable authored entities.

Missing/duplicate IDs must be diagnosable and must never silently alias two objects.

## 2.5 Optional semantic content IDs `[ ]`

Implement optional author-facing IDs only for entities mission logic needs to address.

## 2.6 Minimal registry `[ ]`

Provide owned registration/lookup with duplicate/missing reporting.

Do not force every gameplay behavior into a giant base entity class.

## 2.7 TrenchBroom Vark entity foundation `[ ]`

Create only the entity vocabulary needed for the playground:

- player start
- generic semantic marker
- minimal exit
- initial spike entities as they arrive

## 2.8 Reimport stability `[ ]`

Prove:

```text
edit .map
→ save
→ import/rebuild
→ run
```

without unrelated repair.

Persistent identity must survive ordinary moves/reordering/reimport.

## 2.9 Basic content validation `[ ]`

Validate duplicates, missing required mission objects, invalid references, and identity errors that exist at this stage.

**Phase gate:** a tiny mission loads from the real package/TrenchBroom path, starts, exits, and keeps stable authored identities through representative editing/reimport operations.

---

# Phase 3 — Small contracts, isolated spikes, then the five-minute stealth slice

Goal: answer the dangerous subsystem questions independently enough to debug them, then force them to collide in one real playable route before broad frameworks are committed.

The final integrated graybox contains:

- one room/corridor arrangement
- one ordinary door
- one gameplay light
- at least two footstep surfaces
- one throwable/stackable physical prop
- one very simple patrolling guard
- primitive vision
- primitive hearing
- one audible typed NPC line/reaction
- one simple objective
- one exit

This is not the first production mission. It is an architectural proof mission.

## 3.1 Minimal interaction contract `[ ]`

Introduce only enough common interaction behavior for the spike:

- center-view target selection
- range/occlusion/state eligibility
- one primary interaction command
- minimal feedback/highlight sufficient for debugging/play

Do not build the complete production interaction framework yet.

The ordinary door and physical prop must use this same contract rather than invent separate temporary controls.

## 3.2 Minimal semantic gameplay-event envelope `[ ]`

Add the smallest internal semantic event route needed by the spike.

It should carry meaningful events rather than private subsystem signals and must respect the non-playing/restoring lifecycle.

Do not expose a broad author-facing rule language yet.

## 3.3 Minimal semantic gameplay-sound event `[ ]`

Separate gameplay-significant sound from presentation audio before acoustic propagation is prototyped.

Footsteps, impacts, doors, NPC reactions, and speech should be able to produce one semantic sound representation without committing to the final propagation model.

## 3.4 Ordinary door micro-proof `[ ]`

Implement the smallest ordinary door that can prove:

- interaction
- collision/obstruction
- open/closed visual state
- vision blocking relationship
- acoustic transmission hook
- NPC/nav hook
- semantic events
- semantic state capture/apply

Do not build keys/locks/barred behavior yet unless required by the proof.

## 3.5 Thief-style prop micro-proof `[ ]`

Implement ordinary prop states sufficient to prove:

```text
settled → held → dropped/thrown/unsupported → settling → settled
```

Protect the LOCKED player-facing rules:

- supported props do not topple, spin, roll, or drift;
- edge-supported boxes remain;
- simple supported stacks remain still;
- removing a simple lower support causes the unsupported objects above to fall until supported without uncontrolled rigid-body explosion/scatter;
- settled props become stationary again.

The first implementation does **not** need a universal support-graph theory for bridges, cyclic support, complex multi-support groups, moving supports, or arbitrary group splitting.

Those generalized semantics remain TARGET until real gameplay/fixtures require and prove them.

Do not use unrestricted always-active rigid-body simulation as the default object contract.

## 3.6 Acoustic propagation micro-proof `[ ]`

Use a dedicated test layout with:

- open room
- separated room
- open doorway
- closed door
- L-shaped corridor

Prototype propagation until footsteps, impacts, NPC reactions, and speech audibility behave intuitively.

Choose the architecture only after this experiment. Candidates may include acoustic spaces/portals, zones, or a graph.

## 3.7 Primitive guard/nav micro-proof `[ ]`

One NPC must:

- spawn from authored content
- follow a simple patrol
- navigate imported geometry
- react to the ordinary door
- survive a normal map reimport/nav rebuild workflow

This exists early specifically to expose TrenchBroom/nav feasibility before many systems depend on it.

## 3.8 Gameplay exposure micro-proof `[ ]`

One gameplay light and light-gem/debug readout must be tested against:

- darkness
- partial light
- full light
- occlusion
- light edge
- multiple light contribution when added

Do not freeze the exposure algorithm until visual perception and gameplay value agree intuitively.

## 3.9 Audible world-space speech `[ ]`

NPC words appear above the NPC and remain visible through visual cover when the acoustic system says the player should hear them.

Distance/audibility may control opacity; inaudible speech is hidden.

## 3.10 Simple objective/exit `[ ]`

Add only enough objective state to make the five-minute route have a beginning and end.

It should use semantic state/events rather than reach directly into door/NPC internals.

## 3.11 Actor life-state compatibility proof `[ ]`

Before stealth NPC/save/event architecture is treated as stable, prove the actor model can represent at minimum:

```text
conscious
unconscious
dead
```

This is **not** the final combat system and does not lock combat feel.

A debug/test action is sufficient if it proves that life-state changes can:

- coexist with awareness/navigation ownership;
- emit meaningful semantic events;
- expose saveable semantic state;
- stop/alter ordinary AI activity correctly;
- later become bodies without requiring a completely different actor architecture.

## 3.12 Integrated five-minute stealth slice `[ ]`

Combine the actual micro-proof implementations into one ugly playable route.

The player must be able to sneak through while door, props, light, sound, nav, NPC reaction, typed speech, objective, and exit interact through the intended shared contracts.

Do not accept isolated fixture success as the phase gate.

**Phase gate:** the dangerous technical assumptions have isolated proofs, and the same implementations work together in a playable five-minute stealth slice without obvious architectural contradiction.

---

# Phase 4 — Real save/restore architecture on the proven slice

Goal: turn the semantic state contracts and lifecycle already used by the slice into real ordinary-gameplay quicksave/restore.

## 4.1 Save coordinator over the existing lifecycle `[ ]`

Use the Phase 1 world lifecycle rather than inventing a separate restore-only startup path.

Support explicit fresh-start vs restore-start boot intentions.

No ordinary gameplay consequences fire while snapshot state is being applied/reconciled.

## 4.2 Semantic snapshots `[ ]`

Persist meaningful state, not arbitrary live node graphs.

At this stage cover:

- mission ID/state
- player transform/orientation/velocity/stance and accepted saveable traversal state
- door state/open fraction/lock state if present
- prop state/transform/transient velocity/support state as needed
- guard awareness/goal/life semantic state
- gameplay light state
- objective/fact state
- mission-script state if the spike uses any

## 4.3 Player transient/traversal restore policy `[ ]`

Do not assume runtime traversal objects, physics RIDs, collision handles, ledge candidates, nav paths, or similar ephemeral references can be serialized safely.

Classify representative player states into:

- directly restorable stable semantic states;
- reconstructable transient states;
- states that must normalize to a safe equivalent;
- only if genuinely necessary, very short states where saving is intentionally unavailable.

Explicitly prove at minimum:

- standing/moving
- crouched
- airborne
- hanging
- mantle/corner/catch behavior according to the chosen policy

The player-facing save-anywhere goal remains fundamental, but the implementation must prefer coherent semantic restoration over pretending ephemeral physics references are durable save data.

## 4.4 Other transient-state save policy `[ ]`

Explicitly test or define behavior when saving during:

- door movement
- prop falling/thrown
- guard investigating/alert
- actor unconscious/dead
- any transient state actually present in the slice

Do not silently assume quicksave happens only while idle.

## 4.5 Restore event suppression `[ ]`

Regression coverage must prove restore does not duplicate one-shot events, objective transitions, loot/stat changes, alarms, dialogue, or rule execution.

## 4.6 Versioned save foundation `[ ]`

Introduce a version field and clear unsupported-version error path.

Do not overbuild migration machinery before a real version change exists.

**Phase gate:** F5/F9-equivalent developer quicksave/restore can round-trip the integrated slice through representative stable and transient states without corruption or duplicate consequences.

---

# Phase 5 — Harden the stealth core

Goal: turn spike implementations into reliable Vark systems only after their actual interactions and save semantics are known.

## 5.1 Surface profiles and gameplay noise `[ ]`

Generalize the minimal semantic gameplay-sound contract only as far as the slice proved necessary.

Define reusable authored surface/noise profiles and semantic noise events.

## 5.2 Acoustic model `[ ]`

Stabilize the propagation architecture chosen by the spike.

Doors/openings must affect transmission consistently.

Add debug visualization/inspection.

## 5.3 Gameplay lighting/exposure `[ ]`

Stabilize gameplay-light contract and exposure computation proven by the spike.

Add light gem and useful debug readout.

## 5.4 NPC perception/awareness `[ ]`

Implement:

- unaware
- mild suspicion
- investigation/search
- confirmed alert/pursuit
- loss/recovery

Vision and hearing feed evidence without global omniscience.

## 5.5 NPC communication/local knowledge `[ ]`

Implement explicit information sharing/alarm behavior without granting automatic global player knowledge.

## 5.6 Door/nav/perception integration `[ ]`

Opening/closing the same ordinary door must correctly affect:

- traversal/navigation
- sight
- acoustic transmission
- NPC use
- save/load

## 5.7 Early stress fixtures `[ ]`

Measure representative cost for:

- multiple guards performing vision checks
- many relevant sounds/hearing receivers
- multiple gameplay lights/exposure checks
- nav updates around doors

Set warnings/budgets only after measurement, not arbitrary speculation.

**Phase gate:** the five-minute slice supports understandable darkness- and sound-based stealth with predictable guard behavior and stable save/reload semantics.

---

# Phase 6 — Complete the world interaction grammar

Goal: expand the minimal interaction contract proven in Phase 3 without changing its fundamental language.

## 6.1 Interaction targeting/highlight completion `[ ]`

Harden center-view targeting, range/occlusion/state checks, highlight, and one primary world-interaction input.

The Phase 3 door/prop must continue to use the same contract.

## 6.2 Door completion `[ ]`

Keys/locks/barred restrictions, authoring properties, obstruction behavior, NPC use, events, save state.

## 6.3 Loot and keys `[ ]`

Collected loot becomes abstract recorded value/count. Keys/items use the appropriate inventory model.

## 6.4 Containers `[ ]`

Physical opening/exposed contents where appropriate.

## 6.5 Switches and switchable/extinguishable lights `[ ]`

Integrate with gameplay light state, sound/events, and saves.

## 6.6 Physical prop completion `[ ]`

Expand support relationships, stacking/climbing, held presentation, drop/throw, impacts/noise, obstruction, and save state only as real content needs them.

Complex support/group semantics discovered here must be defined by representative fixtures before becoming LOCKED implementation rules.

## 6.7 Configured breakables/effects `[ ]`

Only explicitly authored damageable/breakable objects respond. No universal destruction/fire simulation.

**Phase gate:** the player can manipulate a convincing systemic environment without unrealistic always-active rigid-body behavior or disconnected interaction rules.

---

# Phase 7 — Mission logic and authoring API

Goal: promote the internal semantic contracts proven by the slice into a small author-facing mission logic system.

## 7.1 Author-facing semantic event bus `[ ]`

Promote the useful Phase 3 gameplay-event vocabulary into a documented event surface for mission logic.

Do not expose private subsystem signals merely because they exist internally.

## 7.2 Typed mission facts `[ ]`

Define fact declarations with:

- key
- type
- default
- scope

Reject invalid/unknown assignments where practical.

## 7.3 Objective system `[ ]`

Active/completed/failed, optional/dynamic objective support.

## 7.4 Small data rule system `[ ]`

Support event → conditions → actions for common declarative mission behavior.

Do not add general-purpose language features.

## 7.5 Public VarkMissionScript API `[ ]`

Provide narrow query/command APIs needed by the real mission.

Avoid exposing mutable global `campaign` or `game_flow` internals directly.

## 7.6 Deterministic rule ordering and save state `[ ]`

Define repeat/one-shot behavior and restore semantics.

## 7.7 Mission logic debugger `[ ]`

Provide rule/event/fact inspection sufficient to answer "why did/didn't this fire?"

**Phase gate:** ordinary mission reactions work without core edits, and genuinely procedural behavior can live in GDScript without private-system reach-through.

---

# Phase 8 — First proper 10–15 minute stealth mission

Goal: test the authoring workflow and system architecture with an actual small mission rather than another isolated technology demo.

The mission must be built through the intended production path and use:

- real TrenchBroom geometry/entities
- multiple routes where practical
- doors/keys
- darkness/light
- different surfaces
- throwable props
- guard patrol/investigation
- typed audible speech
- loot/container interaction
- objectives
- at least one declarative rule
- at least one mission-specific GDScript example where genuinely useful
- quicksave/quickload
- restart/results

## 8.1 Mapper workflow proof `[ ]`

A mapper should not need hand-edits in generated map output.

## 8.2 Reimport proof `[ ]`

Normal geometry/entity iteration must preserve persistent IDs and saveability assumptions.

## 8.3 Rule proof `[ ]`

Common logic uses the small data rule grammar.

## 8.4 GDScript extension proof `[ ]`

One unusual behavior proves the public mission API without expanding the data grammar into a language.

## 8.5 Save/load proof `[ ]`

Representative save points throughout the mission restore coherently.

## 8.6 Authoring/debug feedback `[ ]`

Fix tooling/diagnostics gaps exposed by actually building the mission.

## 8.7 Cold-author review `[ ]`

Have a developer familiar with Godot/TrenchBroom but not the relevant Vark internals attempt a small edit/addition using the intended workflow.

This is an early usability test, not the final external handoff.

Fix cheap structural authoring problems now instead of discovering them after production APIs are frozen.

**Phase gate:** a real small stealth mission is understandable enough to expose genuine production problems, its ordinary content can be authored through intended tools, and the workflow makes sense to someone other than the system's author.

---

# Phase 9 — Bodies and combat prototype

Goal: establish the full four-playstyle foundation while keeping combat TARGET until play proves it.

The Phase 3 actor life-state proof prevents this phase from requiring an entirely new actor/save/event model, but combat feel and body interaction are still intentionally discovered here.

## 9.1 Bodies and life-state completion `[ ]`

Complete conscious/unconscious/dead behavior, carry/hide, body discovery hooks, and save state.

Contextual body-carry movement restrictions must be implemented as explicit gameplay modifiers rather than silent changes to the accepted unencumbered controller behavior.

## 9.2 Stealth knockout prototype `[ ]`

Held/released fist behavior in valid stealth context.

## 9.3 Stealth kill prototype `[ ]`

Held/released knife behavior in valid stealth context.

## 9.4 Block/parry/stagger prototype `[ ]`

Implement the current TARGET grammar only far enough to evaluate it.

## 9.5 Lethal/nonlethal direct combat `[ ]`

Knife/blunt follow-up behavior and guard attack loop.

## 9.6 Required combat validation `[ ]`

Playtest:

- one guard
- two guards
- corridor
- open room
- lethal assault
- nonlethal assault
- transition from stealth failure into combat
- retreat/break contact

Revise the TARGET grammar if needed. Mark combat LOCKED only after user acceptance.

## 9.7 Combat perception/noise/body integration `[ ]`

Combat must create appropriate gameplay noise, awareness, bodies, statistics, semantic events, and save state.

**Phase gate:** stealth/nonlethal, stealth/lethal, assault/nonlethal, and assault/lethal are all genuinely possible enough to evaluate.

---

# Phase 10 — Inventory, effects, and complete gameplay vertical slice

Goal: prove Vark's main gameplay grammar together before broad platform generalization.

## 10.1 Inventory framework `[ ]`

Selection/use model for keys, consumables, thrown tools, projectiles, deployables, area effects, and mission items.

## 10.2 Reusable effect grammar `[ ]`

Damage/heal/gas/water/fire/explosion-like effects only to the degree real items/content need them.

## 10.3 Scripted NPC routines `[ ]`

Conversations, sitting/sleeping/operating, routine interruptions/resumption where required by the slice.

## 10.4 Complete representative slice `[ ]`

One mission segment combines stealth, combat, bodies, interaction, mission logic, save/load, and inventory.

## 10.5 Performance checks `[ ]`

Measure slice-scale perception, acoustics, lighting, rule traffic, nav, and save performance.

**Phase gate:** Vark's gameplay identity exists as one integrated vertical slice rather than a collection of promises.

---

# Phase 11 — Generalize proven systems for production

Goal: extract stable production APIs from patterns the vertical slice actually used.

## 11.1 Clean public APIs `[ ]`

Stabilize only interfaces proven by mission use.

## 11.2 Vark TrenchBroom entity library `[ ]`

Promote ordinary entities/fields proven in real mission authoring.

## 11.3 Validation suite `[ ]`

Add duplicate IDs, missing references, impossible configuration, and other real production errors discovered during mission building.

## 11.4 Debug tooling `[ ]`

Perception, acoustics, nav, entity lookup, mission rules, objectives, and save-state inspection.

## 11.5 Mission template `[ ]`

Create a template only after the first proper mission shows what a real mission actually needs.

## 11.6 Second cold-author test `[ ]`

Have another developer create or substantially modify a small mission using the now-generalized APIs/template.

Use this to catch APIs that only make sense to their original implementer before campaign/content scale increases.

**Phase gate:** reusable systems represent proven Vark patterns, not hypothetical engine features, and at least one non-author can use the generalized workflow successfully.

---

# Phase 12 — Campaign and narrative layer

Goal: support multi-mission consequences and writer-facing production.

## 12.1 CampaignState `[ ]`

Separate persistent campaign facts from mission-local state.

## 12.2 Cross-mission variation `[ ]`

Later mission setup may alter NPCs, routes, objectives, security, resources, dialogue, etc. from campaign facts.

## 12.3 Writer workflow `[ ]`

Stable text IDs/data for world-space NPC dialogue, briefings, subtitles, and narrative content.

## 12.4 First-person sequences `[ ]`

Input ownership, camera control, actor actions/dialogue, save restrictions where appropriate, safe return to gameplay.

## 12.5 Narrative save/campaign integration `[ ]`

Persistence and transitions must be explicit and testable.

**Phase gate:** two missions can demonstrate a meaningful prior-choice consequence without private-core edits.

---

# Phase 13 — Player-facing product flow

Goal: convert developer functionality into complete player-facing flow.

## 13.1 Finalized quicksave/quickload UX `[ ]`

F5/F9 work during ordinary gameplay with understandable feedback/error handling.

## 13.2 Main menu / Continue / New Game `[ ]`

Connect real persistence/campaign flow.

## 13.3 Pause/objectives/map/inventory/settings `[ ]`

Complete input ownership and presentation.

## 13.4 Mission results/statistics `[ ]`

Loot, kills, knockouts, detections/alerts, objectives, time, and mission-specific stats.

## 13.5 Failure/death/recovery flow `[ ]`

Return to valid load/recovery state without checkpoint-only design.

**Phase gate:** the complete intended player loop is usable without developer shortcuts.

---

# Phase 14 — Production scaling and replacement architecture

Goal: prove the systems at representative content scale and allow art/audio replacement without gameplay rewrites.

## 14.1 Art replacement paths `[ ]`

Models/textures/animations/HUD/menu assets can be replaced without changing gameplay rules.

## 14.2 Audio replacement paths `[ ]`

Final audio can replace placeholders without altering semantic gameplay noise.

## 14.3 Representative-scale production mission `[ ]`

Build a much larger mission to stress real content volume.

## 14.4 Performance budgets and optimization `[ ]`

Profile:

- NPC vision/hearing
- acoustic graph/portals
- gameplay exposure
- nav
- mission events/rules
- save size/time
- prop support checks

Optimize proven bottlenecks.

## 14.5 Build/content validation `[ ]`

Production validation must catch common authoring errors before shipping.

**Phase gate:** architecture holds up under representative mission complexity and content volume.

---

# Phase 15 — Final external handoff

Goal: verify the platform is usable by someone who did not build its internals after the earlier cold-author checks have already removed obvious workflow traps.

## 15.1 Production template/docs `[ ]`

Document only the workflows and extension points that survived real production use.

## 15.2 External mapper/scripter test `[ ]`

A developer familiar with Godot/TrenchBroom but not Vark internals builds a small mission.

## 15.3 Handoff gap fixes `[ ]`

Fix unclear APIs, missing validation, undocumented ownership, or tooling problems discovered by the external creator.

**Phase gate:** a new creator can build ordinary Vark mission content without modifying core gameplay systems and can add special scripted content through supported APIs.

---

# Required early integration tests

These are architecture proofs, not optional polish.

## Persistent identity editing fixture

Exercise create/move/reorder/duplicate/delete/reimport operations and prove identity remains stable where intended and distinct on duplication.

Silent identity aliasing is a release-blocking correctness failure for saveable authored content.

## Door integration

The ordinary door must eventually participate coherently in:

- interaction
- player/NPC collision
- NPC traversal/nav
- sight obstruction
- acoustic transmission
- lock/key state
- semantic mission events
- save/load
- prop obstruction

Do not implement each subsystem in a way that later forces a different door model.

## Acoustic fixture

Maintain a tiny map that tests an open room, doorway, closed door, separated room, and corner corridor.

## Lighting fixture

Maintain a tiny chamber that tests dark/partial/full/occluded/edge/multiple-light exposure.

## Prop fixture

Start with deterministic scenarios for edge support, a simple stable stack, simple support removal, drop/throw, settling, and save/load.

Expand support-graph cases only when the gameplay contract for those cases is actually defined.

## Nav/reimport fixture

Imported map → NPC patrol → ordinary door interaction → map edit/reimport → nav rebuild must remain a supported workflow.

## Restore fixture

A populated small mission save must prove non-playing/dormant restoration and no duplicate gameplay consequences.

## Actor-state compatibility fixture

Before final combat exists, prove conscious/unconscious/dead states do not require replacing the guard identity/event/save model.

---

# Testing requirements added as systems arrive

Automate deterministic objective behavior where valuable, including:

- persistent-ID uniqueness and editing/reimport stability
- duplicate persistent-ID failure/repair behavior
- semantic-ID duplicate/missing-reference errors
- mission restart freshness
- save round trips
- restore event suppression
- transient-state restore according to explicit policy
- mission fact typing/defaults
- deterministic rule ordering/one-shot behavior
- Thief-style prop support/fall invariants that have actually been defined
- door state persistence
- acoustic propagation fixtures where deterministic
- NPC local-knowledge/perception invariants where deterministic
- actor life-state persistence/integration

Subjective feel remains user playtest territory.

---

# Immediate recommended sequence

Do not proceed directly into broad mission/save frameworks.

The current next order is:

1. `0.3` repository cleanup
2. `0.4` exact tool-version contract
3. `0.5` CI for the existing movement barrier
4. `0.6` traversal regression expansion
5. `0.7` behavior-trace protection
6. Phase 1 application root + world lifecycle + semantic input boundary
7. Phase 2 minimal mission + persistent-identity feasibility proof + TrenchBroom reimport stability
8. Phase 3 minimal interaction/event/sound contracts
9. Phase 3 isolated door/prop/acoustic/nav/light proofs
10. Phase 3 integrated five-minute stealth slice + actor life-state compatibility proof
11. Phase 4 real save/restore on that proven slice
12. Phase 5 harden stealth architecture from what the integrated/save proof taught
13. Phase 6–8 expand world grammar, mission logic, and build the first proper 10–15 minute mission
14. perform the early cold-author review before production APIs are treated as mature
15. continue through full combat/inventory vertical slice and generalize only afterward

The most important sequencing rules are:

> **Do not build the reusable immersive-sim platform first and hope Vark fits it later. Build Vark in playable slices and let the platform emerge from proven needs.**

and:

> **Do not stabilize an abstraction after proving it against only one side of a future cross-cutting requirement. Identity, lifecycle, save state, events, and actor state must be proven early enough that later systems extend them rather than replace them.**
