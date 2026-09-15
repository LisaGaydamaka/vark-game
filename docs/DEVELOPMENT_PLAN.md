# Vark Development Plan

This document defines the ordered systems-development roadmap for Vark.

The final goal is:

> **Build Vark as a complete immersive-sim game through representative playable missions. Whenever a gameplay or authoring pattern has been proven by real mission use, extract and stabilize the reusable platform needed for future missions.**

The finished production target remains:

> **A mapper, mission scripter, writer, and artist can create production Vark missions without modifying Vark's core gameplay systems.**

The difference is development order: Vark is not built as a speculative general immersive-sim SDK first. Reusability is extracted from systems that have already survived actual gameplay integration.

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

The accepted player-controller **behavior and feel are LOCKED**.

Its implementation is not frozen. Input sampling, command routing, component ownership, pause/cutscene gating, mouse ownership, scene structure, and other internals may be refactored as needed so long as player-facing behavior remains unchanged.

The project does not yet have the complete production gameplay platform: application flow, mission loading, stable persistent identities, saveable world state, interaction, doors, gameplay lighting/exposure, acoustic propagation, NPC/nav/stealth, mission logic, bodies/combat, inventory, campaign state, dialogue presentation, cutscenes, and production authoring/validation.

---

# Development method

## 1. Build vertically

Every major phase must leave behind a playable integrated result.

Do not build many disconnected mechanics and integrate them near the end.

The first representative stealth mission appears early, initially tiny and ugly.

## 2. Spike → integrate → validate → contract → generalize

For uncertain systems:

1. build the smallest representative use that can answer the hard question;
2. integrate it into the actual playable path;
3. test/playtest it against representative edge cases;
4. define the accepted behavior/API only after evidence exists;
5. generalize only the patterns that proved reusable.

Do not begin by designing a universal subsystem around hypothetical future content.

## 3. Authoring develops together with gameplay

If a feature is ordinary mission content, its normal authoring path must be developed with it.

- TrenchBroom: geometry and ordinary spatial entities
- typed Godot Resources/config: reusable non-spatial authored data
- GDScript: genuinely procedural or unusual mission behavior through stable public APIs
- writer-facing text data: dialogue/narrative content without gameplay-code editing

## 4. Do not create a new programming language

The common rule layer remains:

> event → conditions → actions

It is intentionally small.

Loops, arbitrary locals, unrestricted expression evaluation, nested general control flow, and arbitrary object manipulation belong in GDScript rather than expanding the rule system.

## 5. Stable APIs follow proven use

Mission scripts must not depend on private scene-tree paths, guard internals, movement internals, arbitrary internal signals, or undocumented singleton state.

However, do not invent a broad public API before representative mission code needs it.

## 6. Save/load is a cross-cutting requirement

F5/F9 ordinary-gameplay save/load is fundamental.

Every stateful feature added must define semantic snapshot/restore behavior and transient-state policy while that feature is still small.

## 7. Debugging is a production feature

As soon as a system can fail invisibly, add the smallest useful diagnostics.

Examples: entity-ID validation, acoustic path/debug, NPC perception state, nav path, mission-rule trace, save/restore warnings.

## 8. Performance is checked incrementally

The representative-scale stress mission remains late, but expensive systems get focused stress fixtures shortly after introduction.

Do not wait until production scale to discover an architecture is asymptotically wrong.

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

Mission authors normally should not manually name every chair, lamp, box, or loot instance merely so save/load works.

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

# Save/restore lifecycle

Do not restore by fully starting normal gameplay and then overwriting it.

Support two explicit boot intentions:

```text
FRESH_START
RESTORE_SAVE
```

Restore should conceptually perform:

```text
create mission world in dormant state
→ instantiate authored entities
→ register persistent and semantic identities
→ apply raw entity snapshots
→ restore MissionState
→ restore player semantic state
→ restore mission-script state
→ resolve/reconcile references and derived state
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
- door-change events
- loot events
- alarm propagation

Loading a save must not itself become gameplay.

Derived/transient data such as nav paths should normally be recomputed from restored semantic state rather than serialized blindly.

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

# Phase 0 — Protect existing behavior and repository discipline

Goal: make the current accepted player behavior safe to refactor around and prevent repository/tooling problems from compounding.

## 0.1 Existing locomotion/traversal `[x]`

Accepted behavior includes ground movement, sprint, crouch, jump, air movement, support/collision, steps, ledge catch/hang/shimmy/corners, mantle, and mouse look.

**Contract:** behavior/feel is frozen; implementation is not.

## 0.2 Existing movement regression suite `[x]`

Keep the deterministic headless movement suite.

Tests protect accepted behavior, not current internal architecture.

## 0.3 Traversal regression expansion `[ ]`

Add deterministic coverage where practical for:

- ledge catch
- hang
- shimmy
- supported corners
- mantle
- release
- suppression/regrab

## 0.4 Behavior-trace protection for controller refactors `[ ]`

Before major input/controller plumbing changes, add enough semantic trace coverage to show that equivalent command sequences produce equivalent accepted behavior within intended numeric tolerances.

Do not require byte-for-byte internal state equality.

## 0.5 Repository cleanup `[ ]`

Before content volume grows, review and establish policy for:

- TrenchBroom autosaves
- generated imports
- experimental maps
- large `.map` source files
- future binary assets/LFS
- `.gitignore`
- source vs generated ownership

Current repository state already contains autosave material and a very large map source, so this is an early requirement rather than optional housekeeping.

## 0.6 Tool version contract `[ ]`

Pin/document exact production versions for:

- Godot
- FuncGodot
- TrenchBroom

## 0.7 Continuous integration `[ ]`

Once the runner is stable, run the authoritative headless command in CI on `test` pushes and pull requests.

**Phase gate:** accepted player behavior is protected, repository ownership is clean enough for production growth, and tools are versioned.

---

# Phase 1 — Application shell and input ownership

Goal: turn the movement project into a controlled application without changing how the player feels.

## 1.1 Application root `[ ]`

Create stable ownership for:

- game flow
- current mission/world
- player
- UI
- transitions

F5 should launch the Vark application rather than an arbitrary development scene.

## 1.2 Gameplay input boundary `[ ]`

Refactor the player so locomotion consumes semantic gameplay commands rather than owning application-wide input policy.

Conceptually:

```text
Godot Input
→ input router / gameplay input source
→ player command frame
→ existing movement behavior
```

The player controller may be reorganized internally, but its accepted response/feel must remain unchanged.

## 1.3 Pause/UI/cutscene input ownership `[ ]`

Define arbitration between:

- gameplay
- pause
- inventory/objectives/map
- cutscenes/sequences
- menus

No unintended gameplay input leaks through inactive ownership.

Mouse capture/release must restore correctly.

## 1.4 Minimal application/menu shell `[ ]`

Provide functional New Game/development start, Quit, and only settings that actually work.

## 1.5 Development mission launch `[ ]`

Support a fast development route for launching a selected mission/playground without manually opening scenes.

**Phase gate:** application ownership is clear and the player behaves identically through the new input boundary.

---

# Phase 2 — Minimal mission and TrenchBroom substrate

Goal: load one tiny real mission package through the intended authoring path before building broad gameplay architecture.

## 2.1 Mission package convention `[ ]`

Create the initial mission folder ownership convention and a tiny playground mission.

## 2.2 Minimal MissionDefinition `[ ]`

Only include fields currently required to load the playground: mission ID, map/world reference, player start, and minimal metadata.

Do not pre-design every future campaign/narrative field.

## 2.3 Persistent IDs `[ ]`

Implement stable persistent instance identity for authored saveable entities.

## 2.4 Optional semantic content IDs `[ ]`

Implement optional author-facing IDs only for entities mission logic needs to address.

## 2.5 Minimal registry `[ ]`

Provide owned registration/lookup with duplicate/missing reporting.

Do not force every gameplay behavior into a giant base entity class.

## 2.6 TrenchBroom Vark entity foundation `[ ]`

Create only the entity vocabulary needed for the playground:

- player start
- generic semantic marker
- minimal exit
- initial spike entities as they arrive

## 2.7 Reimport stability `[ ]`

Prove:

```text
edit .map
→ save
→ import/rebuild
→ run
```

without unrelated repair.

Persistent identity must survive ordinary moves/reordering/reimport.

## 2.8 Basic content validation `[ ]`

Validate duplicates, missing required mission objects, and invalid references that exist at this stage.

**Phase gate:** a tiny mission loads from the real package/TrenchBroom path, starts, exits, and keeps stable identities through reimport.

---

# Phase 3 — Five-minute integrated stealth spike

Goal: force the hardest systems to collide before general frameworks are committed.

Build one intentionally ugly graybox containing:

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

## 3.1 One ordinary door `[ ]`

Implement the smallest door that can participate in interaction, obstruction, vision, sound, NPC/nav use, events, and later save/load.

Use the door as an integration spine rather than building a broad door framework in isolation.

## 3.2 Thief-style prop spike `[ ]`

Implement ordinary prop states sufficient to prove:

```text
settled → held → dropped/thrown/unsupported → settling → settled
```

Prove these LOCKED rules:

- supported props do not topple, spin, roll, or drift;
- edge-supported boxes remain;
- stacked props remain still;
- removing lower support causes the unsupported stack/group above to fall until supported without exploding/scattering;
- settled props become stationary again.

Do not use unrestricted always-active rigid-body simulation as the default object contract.

## 3.3 Acoustic propagation spike `[ ]`

Use a dedicated test layout with:

- open room
- separated room
- open doorway
- closed door
- L-shaped corridor

Prototype propagation until footsteps, impacts, NPC reactions, and speech audibility behave intuitively.

Choose the architecture only after this experiment. Candidates may include acoustic spaces/portals, zones, or a graph.

## 3.4 Primitive guard/nav spike `[ ]`

One NPC must:

- spawn from authored content
- follow a simple patrol
- navigate imported geometry
- react to the ordinary door
- survive a normal map reimport/nav rebuild workflow

This exists early specifically to expose TrenchBroom/nav feasibility before many systems depend on it.

## 3.5 Gameplay exposure spike `[ ]`

One gameplay light and light-gem/debug readout must be tested against:

- darkness
- partial light
- full light
- occlusion
- light edge
- multiple light contribution when added

Do not freeze the exposure algorithm until visual perception and gameplay value agree intuitively.

## 3.6 Audible world-space speech `[ ]`

NPC words appear above the NPC and remain visible through visual cover when the acoustic system says the player should hear them.

Distance/audibility may control opacity; inaudible speech is hidden.

## 3.7 Simple objective/exit `[ ]`

Add only enough objective state to make the five-minute route have a beginning and end.

**Phase gate:** the player can actually sneak through a tiny mission and door, props, light, sound, nav, NPC reaction, typed speech, objective, and exit interact without obvious architectural contradiction.

---

# Phase 4 — Real save/restore architecture on the spike

Goal: prove ordinary-gameplay quicksave against actual interacting systems, not against empty infrastructure.

## 4.1 Dormant restore lifecycle `[ ]`

Implement explicit fresh-start vs restore-start lifecycle.

No ordinary gameplay consequences fire while snapshot state is being applied.

## 4.2 Semantic snapshots `[ ]`

Persist meaningful state, not arbitrary live node graphs.

At this stage cover:

- mission ID/state
- player transform/orientation/velocity/stance/relevant traversal state
- door state/open fraction/lock state
- prop state/transform/transient velocity/support state as needed
- guard semantic state
- gameplay light state
- objective/fact state
- mission-script state if the spike uses any

## 4.3 Transient-state save policy `[ ]`

Explicitly test or define behavior when saving during representative transient states:

- player airborne
- player crouched
- player hanging/mantling where technically feasible
- door moving
- prop falling/thrown
- guard investigating/alert if available

Do not silently assume quicksave happens only while idle.

## 4.4 Restore event suppression `[ ]`

Regression coverage must prove restore does not duplicate one-shot events, objective transitions, loot/stat changes, alarms, dialogue, or rule execution.

## 4.5 Versioned save foundation `[ ]`

Introduce a version field and clear unsupported-version error path. Do not overbuild migration machinery before a real version change exists.

**Phase gate:** F5/F9-equivalent developer quicksave/restore can round-trip the integrated spike without corruption or duplicate consequences.

---

# Phase 5 — Harden the stealth core

Goal: turn spike implementations into reliable Vark systems only after their actual interactions are known.

## 5.1 Surface profiles and gameplay noise `[ ]`

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

**Phase gate:** the five-minute mission supports understandable darkness- and sound-based stealth with predictable guard behavior.

---

# Phase 6 — World interaction grammar

Goal: expand the proven world model without changing its fundamental semantics.

## 6.1 Interaction targeting/highlight `[ ]`

Center-view targeting, range/occlusion/state checks, highlight, one primary world-interaction input.

## 6.2 Door completion `[ ]`

Keys/locks/barred restrictions, authoring properties, obstruction behavior, NPC use, events, save state.

## 6.3 Loot and keys `[ ]`

Collected loot becomes abstract recorded value/count. Keys/items use the appropriate inventory model.

## 6.4 Containers `[ ]`

Physical opening/exposed contents where appropriate.

## 6.5 Switches and switchable/extinguishable lights `[ ]`

Integrate with gameplay light state, sound/events, and saves.

## 6.6 Physical prop completion `[ ]`

Complete Thief-style support relationships, stacking/climbing, held presentation, drop/throw, impacts/noise, obstruction, and save state.

## 6.7 Configured breakables/effects `[ ]`

Only explicitly authored damageable/breakable objects respond. No universal destruction/fire simulation.

**Phase gate:** the player can manipulate a convincing systemic environment without unrealistic rigid-body behavior or disconnected interaction rules.

---

# Phase 7 — Mission logic and authoring API

Goal: let the spike/prototype mission express ordinary reactions without core edits.

## 7.1 Semantic event bus `[ ]`

Expose a small set of meaningful gameplay events rather than private internal signals.

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

**Phase gate:** a real small stealth mission is fun/understandable enough to expose genuine production problems, and its ordinary content can be authored through intended tools.

---

# Phase 9 — Bodies and combat prototype

Goal: establish the remaining four-playstyle foundation, but keep combat TARGET until play proves it.

## 9.1 Life states and bodies `[ ]`

Conscious/unconscious/dead, carry/hide, body discovery hooks, save state.

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

Combat must create appropriate noise, awareness, bodies, statistics, and save state.

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

**Phase gate:** reusable systems represent proven Vark patterns, not hypothetical engine features.

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

# Phase 15 — External handoff

Goal: verify the platform is usable by someone who did not build its internals.

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

## Door integration

The ordinary door must eventually participate coherently in:

- interaction
- player/NPC collision
- NPC traversal/nav
- sight obstruction
- acoustic transmission
- lock/key state
- mission events
- save/load
- prop obstruction

Do not implement each subsystem in a way that later forces a different door model.

## Acoustic fixture

Maintain a tiny map that tests an open room, doorway, closed door, separated room, and corner corridor.

## Lighting fixture

Maintain a tiny chamber that tests dark/partial/full/occluded/edge/multiple-light exposure.

## Prop fixture

Maintain deterministic scenarios for edge support, stable stacks, support removal, falling groups, drop/throw, settling, and save/load.

## Nav/reimport fixture

Imported map → NPC patrol → ordinary door interaction → map edit/reimport → nav rebuild must remain a supported workflow.

## Restore fixture

A populated small mission save must prove dormant restoration and no duplicate gameplay consequences.

---

# Testing requirements added as systems arrive

Automate deterministic objective behavior where valuable, including:

- persistent-ID uniqueness and reimport stability
- semantic-ID duplicate/missing-reference errors
- mission restart freshness
- save round trips
- restore event suppression
- transient-state restore where deterministic
- mission fact typing/defaults
- deterministic rule ordering/one-shot behavior
- Thief-style prop support/fall invariants
- door state persistence
- acoustic propagation fixtures where deterministic
- NPC local-knowledge/perception invariants where deterministic

Subjective feel remains user playtest territory.

---

# Immediate recommended sequence

Do not proceed directly into broad mission/save frameworks.

The current next order is:

1. `0.3` traversal regression expansion
2. `0.4` controller behavior-trace protection
3. `0.5` repository cleanup
4. `0.6` tool version contract
5. `0.7` CI once deterministic
6. Phase 1 application/input ownership
7. Phase 2 minimal mission + identity + TrenchBroom substrate
8. Phase 3 five-minute integrated stealth spike
9. Phase 4 save/restore on that actual spike
10. Phase 5 harden stealth architecture from what the spike taught
11. continue through world grammar and the first proper 10–15 minute mission

The most important sequencing rule is:

> **Do not build the reusable immersive-sim platform first and hope Vark fits it later. Build Vark in playable slices and let the platform emerge from proven needs.**
