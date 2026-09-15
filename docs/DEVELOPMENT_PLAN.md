# Vark Development Plan

This document defines the ordered systems-development roadmap for Vark.

The final goal is not merely to implement all gameplay mechanics.

The final goal is:

> **A mapper, mission scripter, writer, and artist can create production Vark missions without modifying Vark's core gameplay systems.**

A mapper should be able to build ordinary mission geometry and place/configure ordinary gameplay objects primarily in **TrenchBroom**.

A technical mission designer should be able to implement unusual mission logic in **GDScript** through a stable public mission API.

A writer should be able to create and edit dialogue, subtitles, briefings, and narrative content without modifying gameplay code.

Artists should be able to replace placeholder models, textures, animations, sounds, HUD graphics, and menu presentation without changing gameplay rules.

Core programming after handoff should primarily consist of:

- bug fixes
- deliberate new engine capabilities requested by production
- proven performance work
- approved design changes

It should not be required simply to make every new mission function.

---

# Status notation

- `[ ]` — not implemented
- `[~]` — partially implemented or implemented but not yet accepted/stable
- `[x]` — implemented, tested where appropriate, and accepted

---

# Current implementation baseline

The project currently contains:

- an accepted first-person player controller
- walking
- sprinting
- crouching
- jumping
- air control
- collision/support handling
- steps
- ledge catching
- ledge hanging
- ledge traversal
- supported ledge corners
- mantling
- mouse look
- deterministic movement regression tests
- Godot 4.7
- Jolt physics
- FuncGodot
- TrenchBroom `.map` import
- existing graybox/test maps

The accepted player movement and climbing behavior is frozen.

Future systems adapt to the existing player controller. They do not redesign or retune it unless that scope is explicitly reopened.

The project does **not** yet have the production gameplay platform required by the game vision:

- application/game-flow shell
- mission loading
- stable content IDs
- saveable world entities
- interaction system
- doors
- loot
- inventory
- gameplay lighting/exposure
- NPCs
- navigation
- stealth AI
- sound propagation/gameplay noise
- combat
- bodies
- objectives
- mission scripting
- campaign state
- active-mission quicksave
- dialogue system
- cutscene system
- production authoring tools

---

# Development principles

## Build vertically

Do not create many disconnected mechanics and integrate them at the end.

Every major phase must leave behind a playable integrated result.

---

## Authoring is developed together with gameplay

A gameplay feature is not considered complete merely because it works when manually wired inside a Godot test scene.

If the feature is ordinary mission content, it must have an authoring path.

For spatial gameplay content, that normally means TrenchBroom.

For mission data and reusable configuration, that normally means typed Godot Resources.

For unusual mission programming, that means GDScript through the public Vark mission API.

---

## Do not create a new programming language

Vark may provide a simple data-driven:

**event → conditions → actions**

rule system for common mission logic.

This is a convenience layer, not the only possible mission scripting mechanism.

When mission logic becomes genuinely procedural, technical designers use GDScript.

Do not expand the rule system until it becomes a worse programming language.

---

## Core systems expose stable APIs

Mission scripts must not depend on:

- private scene-tree paths
- private guard implementation nodes
- private player movement internals
- arbitrary internal signals
- undocumented autoload state

Mission content should interact with stable systems such as:

- entities
- events
- mission facts
- objectives
- dialogue
- sequences
- inventory
- campaign state
- game flow

---

## Stable identity is fundamental

Anything that mission logic or save/load may reference needs a stable content ID.

Examples:

```text
guard.library
door.vault
loot.idol
trigger.escape
marker.guard_backup
```

Scene-tree paths are not content identities.

Moving or renaming internal Godot nodes must not break mission logic.

---

## Save/load is designed into systems from the beginning

Vark supports F5/F9 quicksave and quickload during ordinary gameplay.

Therefore every stateful gameplay system must be designed so that its meaningful runtime state can be saved and restored.

Do not postpone this until the campaign system.

Every major stateful gameplay item should answer:

> Can this survive a save/load round trip?

---

## Placeholder presentation is acceptable

Gameplay readability is mandatory.

Final art is not.

Temporary:

- meshes
- sounds
- UI
- animations
- text
- icons

are acceptable while systems are being built.

Temporary presentation must still communicate gameplay state clearly.

---

## Debugging is a production feature

Do not wait until the handoff milestone to add diagnostics.

As soon as a system becomes complex enough to fail invisibly, it needs useful inspection.

Mission creators should not have to attach a debugger to understand why a guard cannot reach a patrol point or why a rule did not fire.

---

# Production toolchain

The intended production workflow uses several different tools for different jobs.

## TrenchBroom

Primary tool for:

- brush geometry
- textures/material assignment
- room/route construction
- gameplay entity placement
- player starts
- guards
- patrol points
- doors
- lights
- loot
- containers
- props
- triggers
- exits
- spatial markers
- other spatial mission objects

The `.map` file is authored source.

Generated/imported Godot map geometry is not hand-maintained.

---

## Godot

Primary tool for:

- core game development
- mission configuration
- reusable gameplay resources
- mission definitions
- objectives
- mission rule configuration
- campaign routing
- narrative sequences
- testing
- validation
- debugging
- running missions

---

## GDScript

The programming language for:

- mission-specific behavior
- unusual puzzle logic
- special security systems
- special NPC behavior
- unusual interactables
- unique tools
- bespoke mission events

Mission GDScript must use stable Vark APIs rather than private core internals.

---

## Writer-facing text data

Dialogue and narrative text should use stable IDs and text-oriented files/data where practical.

The exact production format may evolve, but the workflow should support editing text without requiring the writer to understand gameplay code.

Likely formats include:

- CSV
- JSON
- localization tables
- typed Godot narrative Resources where spatial/sequence relationships are required

---

# Intended mission package structure

Production missions should eventually follow a predictable structure similar to:

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

A simple mission should not require custom GDScript.

The exact directory names may change during implementation, but the principle is fixed:

> All files belonging specifically to a mission should have clear ownership and should not be scattered unpredictably through the core project.

---

# Intended mission runtime

The final conceptual mission startup process is:

```text
GameFlow
→ MissionLoader
→ load MissionDefinition
→ load/import mission world
→ instantiate gameplay entities
→ register stable IDs
→ apply campaign-dependent mission setup
→ create MissionState
→ initialize optional mission GDScript
→ start gameplay
```

Mission creators should not have to manually reproduce this process.

---

# Milestone 1 — Protect the existing player and establish project discipline

Goal: freeze the accepted movement implementation and make the repository safe to build the rest of the game on.

## 1.1 Existing player locomotion and traversal `[x]`

Accepted systems include:

- ground movement
- sprint
- crouch
- jump
- air movement
- support/collision behavior
- steps
- ledge catch
- hang
- shimmy/traversal
- supported corners
- mantle

**Rule:** future gameplay work must not change accepted movement merely for convenience.

---

## 1.2 Existing movement regression tests `[x]`

Keep the existing deterministic headless movement regression suite.

Tests protect accepted behavior.

Tests do not redefine the intended feel.

---

## 1.3 Traversal regression expansion `[ ]`

Add focused protection for representative existing behavior:

- ledge catch
- hang
- shimmy
- corner traversal
- mantle
- release
- suppression/regrab behavior

Only deterministic behavior that can be tested reliably should be automated.

---

## 1.4 Repository cleanup `[ ]`

Clean production-hostile repository state before content volume grows.

Review:

- TrenchBroom autosaves
- generated import files
- experimental maps
- extremely large source maps
- future binary asset policy
- `.gitignore`

Do not delete authored source whose ownership is unclear.

---

## 1.5 Tool version contract `[ ]`

Explicitly pin/document the production versions of:

- Godot
- FuncGodot
- TrenchBroom

Mission production should not depend on everyone independently guessing compatible versions.

---

## 1.6 Continuous integration `[ ]`

Once the test runner is stable, run the authoritative test entry point in CI.

When multiple test suites exist, introduce one full-regression runner.

---

**Milestone gate:** movement is protected, tools are versioned, and repository conventions will not collapse once content production begins.

---

# Milestone 2 — Application shell and runtime ownership

Goal: turn the project from a movement scene into an actual game application.

## 2.1 Application root `[ ]`

Create one stable root responsible for:

- game flow
- current mission/world
- player
- UI
- transitions

F5 launches the actual Vark application rather than an arbitrary development scene.

---

## 2.2 Main menu development shell `[ ]`

Minimal functional screen:

- New Game / development start
- Continue placeholder if persistence does not yet exist
- Quit
- settings only when settings actually function

Final visual design comes later.

---

## 2.3 Pause and input ownership `[ ]`

Define clear ownership between:

- gameplay
- pause UI
- inventory/objectives screens
- cutscenes
- menus

Opening UI must not continue processing unintended gameplay input.

Mouse capture and restoration must be reliable.

---

## 2.4 Collision/query layer contract `[ ]`

Define only the layers actually needed:

- world
- player
- NPC
- physical/interactable objects
- gameplay queries
- triggers

Avoid speculative layer allocation.

---

## 2.5 Development mission launch `[ ]`

Add a convenient development route for starting a particular mission/playground without manually opening scenes.

Eventually support something equivalent to:

```text
--mission playground
```

and, if useful later:

```text
--spawn marker_id
```

Fast iteration is a production feature.

---

**Milestone gate:** Vark starts and exits through controlled application flow and future gameplay systems have stable runtime ownership.

---

# Milestone 3 — Mission/content foundation

Goal: establish the mission architecture before large amounts of gameplay are built.

This milestone moves concepts that previously appeared much later into the beginning of development.

## 3.1 Stable content ID type `[ ]`

Every mission-referenceable entity can have a stable semantic ID.

Requirements:

- explicit author-assigned ID where needed
- duplicate detection
- missing-ID reporting
- IDs independent of internal Godot paths

---

## 3.2 Runtime entity registry `[ ]`

Create one owned service capable of:

```text
get entity by stable ID
check whether entity exists
register entity
unregister entity
```

Mission code must not search arbitrary scene trees for important content.

---

## 3.3 Base Vark mission entity contract `[ ]`

Define the minimum common interface for mission-addressable objects.

Likely responsibilities:

- stable ID
- registration lifecycle
- enabled/disabled state where appropriate
- semantic events
- optional save-state participation
- debug description

Avoid forcing unrelated gameplay behavior into one giant base class.

Composition is preferred where appropriate.

---

## 3.4 MissionDefinition `[ ]`

Create authored mission configuration separate from runtime mission state.

MissionDefinition should own things such as:

- mission ID
- map/world reference
- optional mission script
- mission metadata
- initial objectives
- initial equipment where relevant
- briefing reference
- mission map reference
- campaign routing data when later implemented

---

## 3.5 MissionState `[ ]`

Create mutable mission-local runtime state.

At minimum:

- mission facts
- objective states
- mission statistics
- rule runtime state as later required

Restarting a mission must create fresh MissionState from the same authored MissionDefinition.

---

## 3.6 Mission loader `[ ]`

Create the standard path that:

1. receives a MissionDefinition
2. loads the mission world
3. creates runtime state
4. initializes mission services
5. spawns the player
6. starts gameplay

No mission should implement its own top-level loading architecture.

---

## 3.7 Mission package convention `[ ]`

Adopt an initial mission-folder convention.

Create:

```text
missions/_template/
missions/playground/
```

The template may initially contain very little.

Its purpose is to establish ownership early.

---

## 3.8 Minimal mission exit `[ ]`

Add an authorable mission exit/end object capable of telling the mission runtime that completion has been requested.

Objective requirements may still be simple at this point.

---

**Milestone gate:** a minimal mission exists as a real package with stable identity, load/start/exit behavior, rather than simply as a Godot scene.

---

# Milestone 4 — Production TrenchBroom integration

Goal: make TrenchBroom the real spatial authoring tool before many gameplay entity types exist.

## 4.1 Vark FGD/entity library foundation `[ ]`

Create Vark-specific TrenchBroom entity definitions rather than relying only on generic FuncGodot definitions.

Initial entity vocabulary may be tiny.

---

## 4.2 Player start entity `[ ]`

A mapper places a player-start entity in TrenchBroom.

Mission loading uses it.

No private Godot scene setup is required.

---

## 4.3 Generic marker entity `[ ]`

Create a non-rendered semantic point marker with a stable ID.

This becomes reusable later for:

- patrol destinations
- scripted movement
- cutscene positions
- spawn points
- look targets
- mission scripting

---

## 4.4 Mission exit entity `[ ]`

Expose mission exit placement/configuration in TrenchBroom.

---

## 4.5 Map source ownership `[ ]`

Document and enforce:

- `.map` is source
- generated geometry is generated
- generated map content must not contain irreplaceable manual edits

---

## 4.6 Reimport workflow `[ ]`

A mapper must be able to:

1. edit `.map`
2. save
3. reimport/rebuild
4. run the mission

without repairing unrelated Godot data.

---

## 4.7 Content validation foundation `[ ]`

Introduce the first validation pass.

Initially check only what exists:

- duplicate entity IDs
- missing required mission entities
- invalid basic references

Validation expands continuously with future entity types.

---

**Milestone gate:** the normal spatial content workflow is already TrenchBroom → Vark mission, before doors, guards, or missions become complicated.

---

# Milestone 5 — Save-state architecture

Goal: establish active-mission save/load architecture before many stateful gameplay systems exist.

This does not yet require a complete player-facing save menu.

## 5.1 Saveable entity interface `[ ]`

Define how stateful mission entities describe and restore their meaningful state.

The interface must be semantic, not a raw scene-tree serialization mechanism.

---

## 5.2 Mission save snapshot `[ ]`

A snapshot can contain:

- mission ID
- MissionState
- player state
- saveable entity states by stable ID
- mission-script custom state where applicable

---

## 5.3 Fresh-load then restore model `[ ]`

The intended restoration model is:

```text
load mission normally
→ create authored entities
→ resolve stable IDs
→ apply saved entity state
→ restore MissionState
→ restore player state
→ restore mission script state
→ resume gameplay
```

Do not serialize arbitrary live Godot nodes.

---

## 5.4 Versioned save format foundation `[ ]`

The save format has an explicit version from the beginning.

Migration support can remain simple until actual format changes occur.

---

## 5.5 Save/load test fixture `[ ]`

Build a trivial mission containing a few stateful dummy entities.

Prove:

```text
change state
→ save
→ destroy/reload mission
→ restore
→ state matches
```

This establishes the contract future systems must obey.

---

**Milestone gate:** every future door, guard, loot item, body, objective, or mission script can be built against an existing save-state model rather than retrofitted later.

---

# Milestone 6 — Interaction platform

Goal: establish the universal player/world interaction language.

## 6.1 Interaction input `[ ]`

Add the primary interaction input without modifying locomotion ownership.

---

## 6.2 Focus query `[ ]`

Camera-centered targeting with:

- range
- occlusion
- valid interaction target
- no permanent crosshair

---

## 6.3 Interactable contract `[ ]`

An interactable can report:

- whether interaction is currently possible
- appropriate interaction feedback
- what happens when used

The player should not contain object-type-specific branches such as:

```text
if door
if loot
if candle
```

---

## 6.4 Highlight/prompt feedback `[ ]`

Focused interactable objects visibly highlight.

Temporary UI communicates the active interaction.

Final presentation comes later.

---

## 6.5 Generic switch `[ ]`

First very simple world interactable.

Use it to prove the interaction contract.

---

## 6.6 TrenchBroom exposure `[ ]`

The switch can be placed/configured through the normal mission-authoring route.

---

## 6.7 Save/load integration `[ ]`

Its state survives a save/load round trip.

This acceptance requirement applies to every future stateful entity.

---

**Milestone gate:** the project has one reusable interaction language proven through the real mission-authoring and save-state architecture.

---

# Milestone 7 — Basic world-object grammar

Goal: implement the ordinary environmental archetypes mission makers need.

Each entity must support:

- authoring
- stable IDs when referenceable
- events
- validation
- save/load
- debugging where appropriate

## 7.1 Door `[ ]`

Base features:

- open
- closed
- locked
- unlocked
- key-based unlocking
- nonbreakable base behavior
- NPC-compatible future use
- physical sound/visibility blocking behavior

No lockpicking.

---

## 7.2 Key `[ ]`

Reusable key identity and player ownership.

A key can unlock compatible doors.

---

## 7.3 Loot `[ ]`

World object → collected value/state → removal.

Must emit a semantic loot event.

---

## 7.4 Container `[ ]`

Physical open/closed presentation with authorable contents.

---

## 7.5 Switchable light `[ ]`

Visible enabled/disabled light state.

Gameplay exposure integration comes later.

---

## 7.6 Stationary movable prop `[ ]`

Implement the intended Thief-like object model.

Ordinary supported props:

- do not fall by themselves
- do not move by themselves
- can be picked up
- can be dropped
- can be thrown
- can hit world/actors
- can create impact sounds
- can obstruct
- can be stacked

Do not use a permanently active ordinary rigid-body model that causes props to topple/fall on their own.

---

## 7.7 Held-object state `[ ]`

Held object:

- displayed in first person
- cannot be freely rotated
- prevents ordinary interaction while carried
- can be dropped or thrown

---

## 7.8 Throwing `[ ]`

Thrown objects receive deliberate motion, collide, then settle into a stationary world-object state.

---

## 7.9 Basic damageable/breakable extension `[ ]`

Create a reusable optional response for objects that missions deliberately configure as damageable/breakable.

Do not make all world geometry destructible.

---

**Milestone gate:** ordinary mission-space interaction resembles a minimal immersive-sim world rather than static geometry.

---

# Milestone 8 — Surface and gameplay-audio model

Goal: establish the sensory data needed for Thief-like sound gameplay.

## 8.1 SurfaceProfile resource `[ ]`

Create semantic surface categories/configuration separate from visual texture identity.

Examples:

- stone
- wood
- metal
- carpet
- grass
- gravel
- water

Mission content can define additional profiles.

---

## 8.2 Map/material surface assignment `[ ]`

A mapper or asset creator can associate world surfaces with a SurfaceProfile without changing player code.

---

## 8.3 Semantic gameplay-noise event `[ ]`

Create a gameplay event describing a meaningful noise.

Possible data:

- origin
- strength
- category
- source entity
- optional propagation metadata

Audible SFX and AI hearing values are related but are not the same system.

---

## 8.4 Player movement noise `[ ]`

Existing locomotion emits noise based on accepted player movement and contacted surface.

Do not change locomotion merely to simplify sound logic.

---

## 8.5 Landing noise `[ ]`

Landing behavior contributes appropriate gameplay noise.

---

## 8.6 Object-impact noise `[ ]`

Thrown/dropped object impacts emit semantic noise.

---

## 8.7 Placeholder positional audio `[ ]`

Add enough sound feedback for the player to understand:

- movement
- material differences
- object impacts
- doors

---

**Milestone gate:** sound has become actual gameplay data, and map/material authoring already controls surface behavior.

---

# Milestone 9 — Gameplay lighting and visibility

Goal: create the player-facing light/dark stealth model.

## 9.1 Gameplay-light contract `[ ]`

Rendering light and gameplay exposure are intentionally connected but gameplay visibility is not derived blindly from arbitrary rendered pixels.

Define which authored lights contribute to gameplay exposure.

---

## 9.2 Player exposure calculation `[ ]`

Compute stable exposure based on relevant factors including:

- active lights
- range
- occlusion
- player position
- configured contribution

---

## 9.3 Light gem `[ ]`

Temporary but functional HUD.

It displays gameplay exposure clearly.

---

## 9.4 Extinguishable light archetype `[ ]`

Create a candle/open-light specialization whose world and gameplay-light state change together.

---

## 9.5 Water/extinguish effect hook `[ ]`

Provide the reusable effect behavior required for appropriate water effects to extinguish eligible flames.

No global fluid simulation.

---

## 9.6 Lighting debug view `[ ]`

Developers/designers can inspect:

- current player exposure
- contributing lights
- occlusion/result

---

**Milestone gate:** darkness is a real readable stealth property before guard AI depends on it.

---

# Milestone 10 — NPC platform

Goal: build one flexible ordinary humanoid actor platform before special enemies.

## 10.1 Base NPC actor `[ ]`

Responsibilities include clear ownership for:

- actor identity
- navigation
- life state
- awareness
- perception
- combat hooks
- possessions
- dialogue hooks
- animation/presentation hooks
- save-state participation

Avoid one monolithic script where practical.

---

## 10.2 Navigation `[ ]`

NPC can:

- receive destination
- move
- stop
- report arrival
- report failure

---

## 10.3 Navigation build workflow `[ ]`

Define what happens after a mapper changes geometry.

Mission build/reimport must reliably regenerate or update navigation as required.

---

## 10.4 Patrol route authoring `[ ]`

TrenchBroom-authorable:

- route/patrol points
- ordering
- looping
- waiting
- stable route identity

---

## 10.5 Ordinary NPC routine state `[ ]`

The NPC platform supports authored idle/routine behavior.

Initial requirement:

- standing
- patrol

Later scripted routine actions can build on this.

---

## 10.6 NPC debug inspection `[ ]`

Inspect:

- state
- navigation goal
- current patrol point
- failure reason
- stable ID

---

## 10.7 Save/load `[ ]`

NPC transform, routine state, and other currently meaningful state survives save/load.

---

**Milestone gate:** mission creators can place an ordinary NPC and patrol in TrenchBroom and diagnose navigation problems without editing AI code.

---

# Milestone 11 — Thief-style perception and awareness

Goal: implement the ordinary stealth puzzle-piece guard.

## 11.1 Awareness state model `[ ]`

Support behavior equivalent to:

- unaware
- mild suspicion
- investigating
- alerted
- pursuit
- searching
- recovery

Perception generates evidence.

The awareness/behavior layer decides what to do with it.

---

## 11.2 Guard vision `[ ]`

Vision considers:

- FOV
- distance
- occlusion
- player exposure
- movement where appropriate
- current alertness

Behavior should match the intended Thief 1 & 2 model.

---

## 11.3 Guard hearing `[ ]`

Gameplay-noise events become hearing evidence according to:

- strength
- distance
- intervening world/door behavior
- current guard state

---

## 11.4 Suspicion feedback `[ ]`

NPC state feedback includes:

- `?`
- typed overhead reactions
- nonverbal audio where available

---

## 11.5 Detection feedback `[ ]`

Confirmed alert includes:

- `!`
- typed overhead reaction where appropriate
- alarm grunt/nonverbal feedback

---

## 11.6 Investigation `[ ]`

Guard travels toward relevant evidence rather than magically locating the player.

---

## 11.7 Pursuit `[ ]`

Confirmed player contact produces pursuit.

---

## 11.8 Search and recovery `[ ]`

After losing contact:

- guard uses last useful information
- searches
- eventually recovers

Guard does not track player through walls.

---

## 11.9 Multi-guard communication `[ ]`

Add explicit limited communication.

Avoid magical global awareness.

---

## 11.10 Perception debugger `[ ]`

Designer-facing debug information:

- vision result
- hearing events
- evidence values
- awareness state
- target/last known player information
- search state

---

## 11.11 Save/load `[ ]`

Awareness and search state survive quicksave where meaningful.

---

**Milestone gate:** Vark is recognizably a Thief-like stealth game using production-authorable NPCs and world data.

---

# Milestone 12 — Mission logic platform

Goal: prove that missions can actually be scripted without modifying core systems.

## 12.1 Semantic gameplay event bus `[ ]`

Systems publish meaningful events such as:

```text
loot_taken
door_opened
trigger_entered
guard_alerted
npc_died
npc_knocked_out
light_changed
objective_changed
```

Events use semantic data and stable IDs.

---

## 12.2 Mission facts `[ ]`

Mission scripts/rules can store stable mission-local facts.

Example:

```text
vault_opened = true
warden_suspicious = true
```

Mission facts are not automatically persistent between missions.

---

## 12.3 Objective model `[ ]`

Objectives have stable IDs and states:

- inactive
- active
- completed
- failed

Objective behavior should not require a class for every possible objective type.

---

## 12.4 Trigger volumes `[ ]`

Reusable TrenchBroom-authored spatial triggers.

Support stable IDs and semantic events.

---

## 12.5 Data-defined mission rules `[ ]`

Implement the convenience rule model:

```text
EVENT
+ optional CONDITIONS
→ ACTIONS
```

Initial vocabulary should remain deliberately small.

Possible initial conditions:

- mission fact
- objective state
- entity state

Possible actions:

- set mission fact
- activate objective
- complete objective
- fail objective
- enable/disable entity
- request mission completion

Do not add functionality simply because it might someday be useful.

---

## 12.6 Rule execution guarantees `[ ]`

Define:

- deterministic action order
- once/repeat behavior
- no recursive half-mutated execution
- clear invalid-reference errors

---

## 12.7 Public VarkMissionScript API `[ ]`

Create the GDScript escape hatch for procedural mission logic.

Conceptual interface should expose stable systems such as:

```text
entities
events
objectives
facts
inventory
dialogue
sequences
campaign
game_flow
```

Mission scripts must not reach directly into private player/AI implementation.

---

## 12.8 Mission script lifecycle `[ ]`

Support clear hooks such as:

```text
mission initialized
mission started
before save
after load
mission ending
```

Exact method names may differ.

---

## 12.9 Mission-script save state `[ ]`

Custom mission GDScript can contribute explicit serializable state.

Do not attempt to serialize arbitrary script internals automatically.

---

## 12.10 Mission logic debugger `[ ]`

Inspect:

- recent gameplay events
- mission facts
- objective states
- rules triggered
- conditions evaluated
- actions executed

---

**Milestone gate:** simple mission logic requires no programming, while genuinely special behavior can be implemented cleanly in GDScript without changing core engine code.

---

# Milestone 13 — First real vertical-slice mission

Goal: prove the entire production workflow before adding combat and large numbers of systems.

Build a 10–15 minute graybox mission through the same authoring process intended for production.

## Required content

The mission must contain:

- TrenchBroom-authored geometry
- player start
- multiple routes
- bright and dark spaces
- multiple sound surfaces
- doors
- key
- loot
- container
- movable/throwable props
- switchable/extinguishable light
- several guards
- patrols
- distraction opportunities
- objective
- optional objective or optional action
- trigger-based mission logic
- mission exit
- results snapshot

---

## 13.1 Data-only logic proof `[ ]`

At least one meaningful mission event is implemented entirely through the data rule system.

---

## 13.2 GDScript logic proof `[ ]`

At least one intentionally nontrivial mission behavior is implemented through `VarkMissionScript`.

The test is not that arbitrary code is possible.

The test is that it can be done without accessing private core internals.

---

## 13.3 Save/load proof `[ ]`

Quick-save during multiple world states:

- open/closed door
- extinguished light
- guard suspicious/searching
- collected loot
- changed objective
- changed mission fact

Reload and verify consistency.

---

## 13.4 Mission restart `[ ]`

Restart produces a clean mission from authored data.

No runtime state leaks between attempts.

---

## 13.5 Results `[ ]`

Provide functional temporary results display using real MissionState/statistics.

---

**Milestone gate:** the project is a small complete stealth game produced through the intended mission pipeline.

---

# Milestone 14 — Life states, bodies, and stealth takedowns

Goal: add NPC removal systems without breaking the established stealth/mission architecture.

## 14.1 NPC life-state model `[ ]`

Required states:

- conscious
- unconscious
- dead

---

## 14.2 Unconscious state `[ ]`

Unconscious NPC:

- stops active AI
- remains unconscious
- participates as body
- can be referenced by mission systems
- survives save/load

---

## 14.3 Dead state `[ ]`

Dead NPC:

- remains dead
- participates as body
- produces lethal statistics/events
- survives save/load

---

## 14.4 Body world representation `[ ]`

Bodies support:

- world collision
- pick up
- carry
- put down
- hiding

Body behavior follows the intended game rules rather than a chaotic continuous ragdoll simulation unless a presentation system later deliberately provides one.

---

## 14.5 Body discovery `[ ]`

Guard perception can discover bodies through normal perception architecture.

Response is configurable by mission behavior.

---

## 14.6 Stealth knockout `[ ]`

No blackjack.

Player holds attack to raise a clenched fist.

Release performs the strike.

Valid unaware target from the correct stealth context is immediately knocked unconscious.

---

## 14.7 Stealth kill `[ ]`

Same hold/release structure with knife.

Valid unaware ordinary human target is killed immediately.

---

## 14.8 Statistics/events `[ ]`

Emit semantic:

- knockout
- kill
- body discovered

events for mission/campaign use.

---

**Milestone gate:** lethal/nonlethal stealth removal and body management integrate with mission logic and save/load.

---

# Milestone 15 — Direct combat

Goal: implement the small fixed combat grammar from GAME_VISION.

## 15.1 Health/damage foundation `[ ]`

Player/NPC damage ownership with no duplicate logical hits.

---

## 15.2 Player health HUD `[ ]`

Temporary readable health feedback.

---

## 15.3 Guard combat ownership `[ ]`

Alerted ordinary guard can transition coherently from pursuit/navigation into combat.

---

## 15.4 Block `[ ]`

Holding block protects against ordinary blockable attacks.

---

## 15.5 Parry `[ ]`

Pressing block shortly before the NPC strike lands performs a parry.

Successful parry staggers the NPC.

---

## 15.6 NPC defense `[ ]`

Non-staggered ordinary NPC blocks or parries normal player melee attacks.

---

## 15.7 Knife hit `[ ]`

- non-staggered NPC → blocks/parries
- staggered NPC → instant kill

---

## 15.8 Blunt/fist hit `[ ]`

- non-staggered NPC → blocks/parries
- staggered NPC → receives one hit
- several successful blunt hits → knockout

---

## 15.9 Multi-guard combat `[ ]`

Several guards can pressure/surround the player without navigation/combat state fighting internally.

---

## 15.10 Combat noise `[ ]`

Combat creates gameplay noise and attracts nearby relevant guards.

---

## 15.11 Escape from combat `[ ]`

Player may break contact and run.

NPCs transition back into search behavior rather than forgetting the encounter.

---

## 15.12 Player death `[ ]`

Player death leads to load/save recovery.

No unrelated checkpoint-only design.

---

**Milestone gate:** assault is a viable but riskier alternative to stealth, using the fixed parry/stagger combat grammar.

---

# Milestone 16 — Generic inventory and effects

Goal: create flexible archetypes, not a hard-coded campaign equipment list.

## 16.1 ItemDefinition `[ ]`

Stable reusable item data.

Potential data:

- ID
- name/text key
- icon
- stackability
- use behavior
- presentation reference

---

## 16.2 Inventory runtime `[ ]`

Support:

- add
- remove
- quantity
- select
- use

Loot remains conceptually separate from usable inventory.

---

## 16.3 Inventory HUD/screen `[ ]`

Functional temporary presentation.

---

## 16.4 Consumable effect archetype `[ ]`

Prove with a simple healing item.

The healing item is a reference implementation, not mandatory campaign content.

---

## 16.5 Throwable item archetype `[ ]`

Generic item use that creates/throws a mission/world effect object.

---

## 16.6 Area effect archetype `[ ]`

Reusable spatial effect support.

Examples later may include:

- flash
- gas
- explosion
- noise

---

## 16.7 Deployable/triggered item archetype `[ ]`

Reusable basis for things such as:

- mines
- traps
- noise devices

---

## 16.8 Damage effect `[ ]`

Reusable effect capable of damaging eligible targets.

---

## 16.9 Status effect `[ ]`

Reusable temporary actor-effect mechanism where justified.

---

## 16.10 Reference tools `[ ]`

Create only enough example items to prove the grammar.

Do not build every possible campaign item before handoff.

---

**Milestone gate:** content creators can define a useful range of tools from reusable item/effect primitives without the core player knowing every item type.

---

# Milestone 17 — NPC scripted routines

Goal: support mission-authored ordinary behavior while keeping NPCs predictable stealth puzzle pieces.

## 17.1 NPC command/routine API `[ ]`

Support reusable high-level actions such as:

- walk to marker
- wait
- face marker/entity
- sit
- stand
- sleep
- use entity
- operate mechanism
- show dialogue line

Only implement commands as real mission content needs them.

---

## 17.2 Routine interruption/resumption `[ ]`

Suspicion/combat can interrupt routines coherently.

Mission-defined policy controls whether/how routine resumes.

---

## 17.3 Door use `[ ]`

NPCs can use ordinary supported doors while patrolling/investigating/chasing.

---

## 17.4 Possessions `[ ]`

NPCs can carry:

- keys
- loot
- mission items

---

## 17.5 Pickpocket `[ ]`

Steal eligible carried items from unaware targets according to clear positional rules.

---

## 17.6 World-evidence hooks `[ ]`

Mission scripting can opt NPCs into authored responses such as:

- missing valuables
- opened containers
- extinguished lights
- blood
- alarms

Do not force every guard to react to every possible evidence type globally.

---

**Milestone gate:** mission creators can author believable but predictable routines without writing custom AI for every guard.

---

# Milestone 18 — Campaign state and mission variation

Goal: support a real multi-mission game where later missions can change because of previous choices.

## 18.1 CampaignState `[ ]`

Persistent named facts separate from MissionState.

Example:

```text
warden_alive
prisoner_rescued
idol_stolen
mission_03_alarm
```

---

## 18.2 Campaign persistence `[ ]`

Save/load campaign facts across process restart.

---

## 18.3 Campaign routing `[ ]`

Choose next mission through authored campaign logic.

Do not assume linearity or free mission selection unless content requires it.

---

## 18.4 Campaign-aware MissionDefinition `[ ]`

Mission startup can conditionally alter:

- enabled NPCs
- patrols
- doors/routes
- items
- objectives
- dialogue
- scripted events
- initial mission facts

based on CampaignState.

---

## 18.5 Campaign actions from mission logic `[ ]`

Mission rule system and mission GDScript can intentionally set campaign facts.

Avoid a second separate narrative scripting architecture.

---

## 18.6 No difficulty system `[ ]`

Ensure campaign/missions contain no difficulty-selection infrastructure.

Variation in challenge comes from:

- authored mission design
- campaign consequences
- player approach

---

## 18.7 Two-mission branching proof `[ ]`

Build Mission A and Mission B.

At least one action in Mission A must visibly change Mission B after quitting/restarting the game.

---

**Milestone gate:** the game supports authored consequences rather than a fixed sequence of disconnected missions.

---

# Milestone 19 — Narrative and writer workflow

Goal: separate writing from programming.

## 19.1 Stable text IDs `[ ]`

Narrative text is identified by stable keys rather than embedded unpredictably inside gameplay scripts.

---

## 19.2 Dialogue text source `[ ]`

Choose and prove a writer-friendly source format.

Likely:

- localization CSV/table
- or equivalent text-first format

Writers should not need GDScript for normal dialogue editing.

---

## 19.3 Overhead dialogue `[ ]`

NPC speech appears above the character.

---

## 19.4 Nonverbal vocal layer `[ ]`

Support minimal:

- grunts
- pain
- effort
- surprise
- alarm

No assumption of fully voiced dialogue.

---

## 19.5 Conversation sequence resource `[ ]`

Allow authored ordered exchanges between actors.

Keep this presentation-focused.

Do not turn it into a general programming language.

---

## 19.6 Conditional dialogue `[ ]`

Mission rules/GDScript determine when a dialogue/conversation sequence starts.

The narrative content itself does not need to own gameplay condition logic.

---

## 19.7 Subtitle system `[ ]`

For cutscenes/other content requiring lower-screen subtitles.

---

## 19.8 Briefing data model `[ ]`

Writer/content-facing mission briefing content separate from game flow code.

---

## 19.9 Writer validation `[ ]`

Detect:

- missing text IDs
- duplicate IDs
- missing speakers where required
- invalid conversation references

---

**Milestone gate:** a writer can substantially rewrite mission dialogue and briefing content without touching gameplay scripts.

---

# Milestone 20 — First-person scripted sequences

Goal: provide the presentation timeline required for cutscenes without creating another gameplay scripting language.

## 20.1 Sequence resource `[ ]`

A content-addressable ordered sequence of presentation actions.

---

## 20.2 Player input control `[ ]`

Sequence can temporarily take/release gameplay input safely.

---

## 20.3 Cinematic presentation `[ ]`

Support:

- first-person viewpoint
- letterbox bars
- subtitle presentation

---

## 20.4 Basic actor sequence actions `[ ]`

Only as required:

- move actor to marker
- face target
- wait
- display line
- trigger animation/presentation
- set simple presentation state

---

## 20.5 Mission logic integration `[ ]`

Rules/GDScript can start sequences.

Sequences do not become responsible for complicated branching mission logic.

---

## 20.6 Save restrictions/recovery `[ ]`

Define save/load behavior during noninteractive sequences.

Ordinary gameplay quicksave remains available outside appropriate restricted states.

---

**Milestone gate:** mission creators can author first-person narrative sequences without hard-coding cutscene logic inside game-flow systems.

---

# Milestone 21 — Full quicksave/quickload

Goal: turn the save architecture built earlier into the real player-facing F5/F9 system.

## 21.1 Player runtime state `[ ]`

Save/restore at least:

- transform
- health
- inventory
- selected/equipped state
- other required non-locomotion gameplay state

---

## 21.2 World entity coverage `[ ]`

Verify state restoration for:

- doors
- lights
- containers
- loot
- props
- bodies
- NPCs
- objectives
- mission facts
- campaign-safe state
- rule state
- mission script custom state

---

## 21.3 AI save stress `[ ]`

Test saving/loading during:

- patrol
- suspicion
- investigation
- pursuit
- search
- combat

---

## 21.4 Quick save F5 `[ ]`

Available during ordinary gameplay.

---

## 21.5 Quick load F9 `[ ]`

Reloads correctly and safely.

---

## 21.6 Manual save/load interface `[ ]`

If desired for final product, build on the same save architecture.

---

## 21.7 Save corruption/recovery policy `[ ]`

Define safe behavior for:

- missing save
- corrupt save
- incompatible save version

---

**Milestone gate:** quicksave is trustworthy enough that players can use it constantly without accumulating broken mission states.

---

# Milestone 22 — Production game flow and UI

Goal: surround the now-functional game systems with the complete product shell.

## 22.1 New Game `[ ]`

Creates clean CampaignState and starts campaign flow.

---

## 22.2 Continue `[ ]`

Loads current persistent campaign/save state.

---

## 22.3 Mission briefing screen `[ ]`

Uses real mission narrative data.

---

## 22.4 Objectives screen `[ ]`

Driven directly by MissionState.

---

## 22.5 Mission map screen `[ ]`

Mission supplies authored map content.

No universal GPS requirement.

---

## 22.6 Inventory screen `[ ]`

Driven by actual inventory state.

---

## 22.7 Mission results `[ ]`

At minimum supports available statistics such as:

- loot
- kills
- knockouts
- alerts/detections
- objectives
- mission time

Mission-specific statistics may extend this.

---

## 22.8 Pause `[ ]`

Production-ready pause behavior.

---

## 22.9 Settings `[ ]`

Only real settings.

Possible categories:

- mouse sensitivity
- audio
- display/video
- controls

No difficulty option.

---

## 22.10 Final game-flow transitions `[ ]`

Ensure:

```text
menu
→ briefing
→ mission
→ results
→ campaign update
→ next briefing/mission
```

is one coherent flow.

---

**Milestone gate:** the systems function as an actual multi-mission video game rather than a collection of developer-accessed scenes.

---

# Milestone 23 — Art/audio replacement architecture

Goal: guarantee that production art can replace placeholders without changing gameplay logic.

## 23.1 NPC presentation separation `[ ]`

Gameplay actor state remains separate from:

- visual model
- skeleton
- animations
- face presentation

---

## 23.2 First-person presentation separation `[ ]`

Hands/weapons/carried items can be replaced without changing gameplay logic.

---

## 23.3 Animation state hooks `[ ]`

Expose semantic states such as:

- walking
- attacking
- blocking
- staggered
- unconscious
- dead
- interacting

Animation does not determine gameplay truth.

---

## 23.4 2D facial-animation support `[ ]`

Implement the desired replaceable face presentation.

---

## 23.5 Audio buses `[ ]`

Production audio categories such as:

- world
- footsteps
- NPC
- combat
- ambience
- UI
- music

Gameplay noise remains separate from audible volume.

---

## 23.6 Production asset import conventions `[ ]`

Document/prove:

- models
- textures
- materials
- animation
- sounds
- scale
- low-resolution filtering

---

**Milestone gate:** art production can proceed without systems programmers needing to rewrite gameplay around final assets.

---

# Milestone 24 — Mission build and validation tools

Goal: make authoring errors obvious before external production begins.

## 24.1 Build Mission operation `[ ]`

Provide one understandable development action that performs whatever current mission preparation requires:

- import/reimport
- entity assembly
- navigation update
- validation
- other generated preparation

---

## 24.2 Validation expansion `[ ]`

Detect representative content errors including:

- duplicate IDs
- missing references
- invalid door keys
- missing patrol markers
- malformed patrol routes
- invalid objective references
- invalid rule references
- invalid campaign destination
- missing dialogue IDs
- missing sequence IDs
- invalid custom entity setup

---

## 24.3 Actionable errors `[ ]`

Errors identify:

- mission
- entity ID
- relevant property/reference
- what is wrong

Avoid generic runtime null-reference failures.

---

## 24.4 Designer debug overlay/panel `[ ]`

Provide coherent access to:

- player exposure
- current surface
- emitted gameplay noise
- interaction target
- guard awareness/evidence
- navigation
- objectives
- mission facts
- campaign facts
- event stream
- rule execution

---

## 24.5 Run from marker `[ ]`

If implementation proves practical, allow developers to quickly test a selected area/marker without traversing the whole mission.

Must not create a special state incompatible with real mission behavior.

---

**Milestone gate:** normal mission-development failures can be understood without inspecting private core code.

---

# Milestone 25 — Custom mission extension API

Goal: make unusual mission content possible without core-system modification.

## 25.1 Custom entity contract `[ ]`

Mission-specific Godot scenes/scripts can register as normal Vark mission entities.

---

## 25.2 Custom TrenchBroom entity exposure `[ ]`

Provide a supported path for mission-specific entities to become placeable/configurable through the map workflow where appropriate.

---

## 25.3 Public gameplay APIs `[ ]`

Document/stabilize extension points for:

- interaction
- damage/effects
- events
- NPC commands
- mission facts
- objectives
- dialogue/sequences
- campaign facts
- save/load

---

## 25.4 Extension-boundary test `[ ]`

Implement at least one intentionally unusual feature only in a mission package.

For example:

- special machinery
- unique trap
- unusual security device
- bespoke puzzle object

It must integrate with:

- interaction
- events
- save/load
- mission logic

without requiring changes to unrelated core systems.

---

**Milestone gate:** mission programmers can create genuine mission-specific mechanics instead of asking the core programmer to special-case every unusual idea.

---

# Milestone 26 — Production template and documentation

Goal: package all stable workflows into something another person can actually use.

## 26.1 Clean template mission `[ ]`

Create:

```text
missions/_template/
```

No story content.

It demonstrates the expected structure.

---

## 26.2 Reference mission `[ ]`

Create one non-story example showing common combinations:

- guards
- patrol
- doors
- key
- loot
- light
- surface sound
- trigger
- objectives
- mission rules
- dialogue
- sequence
- exit
- campaign fact

---

## 26.3 `docs/CONTENT_AUTHORING.md` `[ ]`

Document workflows from the mission creator's perspective.

Include:

- required software
- project setup
- creating a mission package
- creating/editing maps
- Vark TrenchBroom entities
- stable IDs
- objectives
- mission facts
- event-condition-action rules
- GDScript mission API
- dialogue
- sequences
- campaign consequences
- saving requirements
- custom entities
- build/validation
- debugging
- common failures

Do not make the author read core implementation details.

---

## 26.4 Entity reference `[ ]`

Every production entity documents:

- purpose
- TrenchBroom classname
- properties
- required fields
- emitted events
- relevant save behavior

---

## 26.5 Mission API reference `[ ]`

Document the supported public GDScript API.

Private core functions are explicitly not part of the mission contract.

---

**Milestone gate:** the production workflow is learnable without tribal knowledge.

---

# Milestone 27 — Representative-scale production mission

Goal: discover scaling problems before real campaign production starts.

Build an intentionally utilitarian mission approximating production complexity.

It should include:

- realistically sized brush geometry
- multiple floors/areas
- multiple routes
- representative guard count
- many patrol points
- many lights
- multiple surface types
- doors
- containers
- loot
- props
- bodies
- combat
- tools
- objectives
- triggers
- mission rules
- dialogue
- sequences
- custom mission script
- campaign variation

---

## 27.1 Navigation stress `[ ]`

Verify normal authoring and runtime performance.

---

## 27.2 Perception stress `[ ]`

Profile sight/hearing behavior under representative guard counts.

---

## 27.3 Gameplay-light stress `[ ]`

Profile exposure calculation under representative lighting.

---

## 27.4 Save/load stress `[ ]`

Stress quicksave with representative world state.

---

## 27.5 Mission-rule stress `[ ]`

Ensure event/rule architecture remains understandable and performant.

---

## 27.6 Authoring usability review `[ ]`

Identify:

- excessive repetitive fields
- painful linking workflows
- unclear errors
- unnecessary Godot work
- TrenchBroom limitations
- missing debug information

Improve proven pain points.

---

## 27.7 Performance pass `[ ]`

Optimize measured bottlenecks only.

Avoid speculative optimization.

---

**Milestone gate:** the architecture works at actual mission scale rather than only in tiny demonstration maps.

---

# Milestone 28 — External handoff test

Goal: prove that Vark is actually ready for people who did not build its core systems.

This is the final systems-development test.

## Mapper handoff

A mapper familiar with TrenchBroom but unfamiliar with Vark internals must create a fresh level containing:

- geometry
- multiple routes
- different surfaces
- lights/darkness
- doors
- loot
- props
- guards
- patrols
- triggers
- exit

without editing private core Godot scenes.

---

## Mission designer handoff

A mission designer familiar with Godot/GDScript but unfamiliar with Vark internals must add:

- objectives
- mission facts
- rules
- scripted mission behavior
- at least one unusual custom mission feature
- mission completion
- campaign consequence

without modifying core gameplay scripts.

---

## Writer handoff

A writer/content developer must add/change:

- overhead dialogue
- conversation content
- subtitles
- briefing
- narrative sequence content
- conditional narrative variants

without learning player, AI, combat, or mission-runtime internals.

---

## Cross-mission proof

The handoff content must include at least two missions.

A player action in the first must change the second through CampaignState.

---

## Save/load proof

The externally created mission must work correctly with F5/F9 across representative gameplay states.

---

## Handoff acceptance

Systems development is complete only when the external creators can finish the exercise using:

- documented tools
- documented APIs
- normal debug tools
- actionable validation

without undocumented help that amounts to explaining private engine implementation.

---

# Definition of systems-development complete

Vark is ready for production mission development when all of the following are true:

### A mapper can:

- create brush-built environments in TrenchBroom
- assign gameplay surfaces
- place/configure ordinary gameplay entities
- place/configure guards and patrols
- place triggers/markers
- rebuild and test the mission quickly

### A mission designer can:

- configure objectives
- create common event/condition/action rules
- write unusual behavior in GDScript
- reference entities by stable ID
- create mission-specific entities
- create cross-mission consequences
- debug gameplay state
- validate the mission

### A writer can:

- edit dialogue
- create conversations
- edit briefings
- add subtitles
- author narrative sequences
- create conditional narrative variants

without modifying gameplay code.

### An artist can:

- replace environment assets
- replace NPC visuals
- replace first-person visuals
- replace animations
- replace sounds
- replace UI presentation

without redefining gameplay state.

### The game supports:

- frozen player movement
- Thief-style visibility/darkness
- Thief-style sound stealth
- predictable guard awareness
- interaction
- doors/keys
- loot
- containers
- physical props
- light manipulation
- guards/patrols
- bodies
- stealth knockout
- stealth kill
- direct combat
- inventory/effect archetypes
- objectives
- mission scripting
- campaign consequences
- dialogue
- cutscenes
- mission maps
- statistics/results
- F5/F9 quicksave/load
- mission-specific extensions

At this point, a normal new mission should primarily require **content creation**, not new engine programming.

---

# Recommended immediate sequence from the current repository state

The next work should be:

1. `1.3` — expand traversal regression protection where worthwhile.
2. `1.4–1.6` — repository cleanup, tool-version contract, CI foundation.
3. `2.1–2.5` — application root, menu/dev flow, pause/input ownership, collision conventions, quick mission launch.
4. **Then stop feature development briefly and build Milestone 3.**
5. Create stable content IDs, MissionDefinition, MissionState, registry, loader, and mission package structure.
6. Build the Vark TrenchBroom entity library in Milestone 4.
7. Establish save-state architecture in Milestone 5.
8. Only then begin doors, interaction, guards, stealth, combat, inventory, and narrative systems.

The key ordering rule is:

> **Do not build a large amount of gameplay before Vark knows what a mission is, how mission content is identified, how it is authored, and how its state is saved.**

That is the foundation the rest of the game should grow from.
