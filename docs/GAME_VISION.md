# Vark Game Vision

This document defines the minimum complete gameplay contract for Vark before production missions, plot, final art, and final presentation are created.

It describes what the finished base game must allow the player to do, how its common systems behave from the player's point of view, and what mission creators must be able to build on top of those systems.

It does not define the setting, story, protagonist, factions, final enemy roster, individual missions, final textures, final UI art, specific mission maps, or other content that belongs to mission designers, writers, and artists.

The goal of systems development is to create a stable, flexible game platform from which those people can build the actual campaign without rewriting the core player, stealth, interaction, combat, mission, or game-flow systems.

---

# Core identity

Vark is a first-person immersive stealth/action game built around authored sandbox missions.

Its basic physical world, stealth model, sound model, interaction philosophy, AI awareness, inventory philosophy, navigation philosophy, and systemic readability follow the tradition of **Thief 1 & 2**.

Its overall pace and choice structure are less restrictive than Thief.

The player may approach the same situation slowly and carefully or quickly and aggressively.

Four broad styles must naturally be possible:

- stealth + nonlethal
- stealth + lethal
- assault + nonlethal
- assault + lethal

These are not menu-selected classes. They emerge from what the player actually does.

Stealth is normally safer.

Direct violence is normally faster and easier in the immediate situation, especially against isolated ordinary enemies, but creates more noise, risk, bodies, alerts, and opportunities for campaign consequences.

The intended campaign philosophy is similar to Dishonored: lethal solutions may be tactically easier while restraint and nonlethal solutions may lead to better long-term outcomes.

The core game does not hard-code a particular story or morality system. It records meaningful player actions and exposes them to mission and campaign logic so writers can decide what consequences those actions produce.

Choice is primarily expressed through action rather than dialogue menus.

---

# Player movement

The existing player controller is the movement contract.

It is already accepted and must not be redesigned, retuned, or expanded as part of normal future gameplay development.

The supported movement is whatever the accepted player controller on the current project implements, including:

- normal ground movement
- sprint
- crouch
- jump
- air control
- step traversal
- ledge grab and hang
- ledge traversal / shimmy
- supported ledge corners
- mantle / climb-up

Future level geometry, props, doors, encounters, AI, and tools must adapt to this controller.

The game must not add movement abilities simply because a later level would be easier to design around them.

Abilities such as swimming, ladders, wall dashes, slides, or other traversal systems are not part of the base game unless that scope is deliberately reopened later.

The exact movement values and behavior live in the player controller and its accepted regression tests rather than being duplicated in this document.

---

# Basic gameplay rhythm

Vark does not impose one mandatory pace.

A player may spend several minutes listening, observing patrols, manipulating lights, hiding bodies, and waiting for a safe route.

Another player may sprint through the same space, attack guards, use tools, trigger alarms, escape pursuit, and improvise around the resulting chaos.

Both are legitimate gameplay.

The normal sandbox rhythm is:

observe the environment → choose an approach → act → world and NPCs react → continue the plan or improvise → complete objectives → leave the mission.

Getting detected is therefore normally a change in the situation, not a game-over state.

---

# Stealth model

The default stealth model follows the player-facing behavior of Thief 1 & 2.

Stealth has two primary sensory channels:

1. visibility
2. sound

NPCs accumulate evidence through these senses rather than switching instantly between completely unaware and completely omniscient.

The player must be able to understand why an NPC reacted.

---

# Visibility and darkness

Illumination is a real gameplay property.

The player's current exposure is communicated through a permanent light-gem style HUD indicator.

A dark light gem means the player is difficult to see.

A bright light gem means the player is exposed.

Visibility depends primarily on:

- how illuminated the player is
- whether the player is moving
- distance from the observer
- observer direction / field of view
- obstruction and line of sight
- the observer's current alertness

Darkness strongly protects the player but is not magical invisibility.

An NPC extremely close to the player, directly facing the player, or otherwise receiving strong visual evidence can still discover the player in darkness.

Movement makes a partially visible player easier to notice than remaining still.

Visual exposure should change smoothly enough that the player can deliberately move between safe darkness, partial exposure, and obvious illumination.

World geometry blocks vision.

Doors, walls, large props, and other opaque objects can therefore be used as visual cover.

Mission authors may create NPCs with unusual perception, but ordinary guards use the common stealth model.

---

# Light sources

Lights can contribute to both visual presentation and player stealth exposure.

A light may be:

- permanently on
- switchable
- extinguishable
- controlled by mission events

Open flames can be extinguished by appropriate water effects.

A mission may create special lights that cannot be extinguished or that respond to other rules.

The game must clearly distinguish actual gameplay darkness from merely dark-looking decoration.

---

# Sound stealth

Sound follows the same basic role as in Thief 1 & 2.

The player does not need a separate HUD noise meter.

The player should learn how noisy an action is primarily by hearing it and by observing NPC reactions.

Player movement noise depends on both movement and surface.

As a general relationship:

crouched careful movement < normal movement < sprinting / hard landings.

Different materials create meaningfully different footsteps.

Soft surfaces are safer.

Hard, resonant, or loose surfaces are more dangerous.

Examples of surface categories may include carpet, grass, wood, stone, tile, metal, gravel, water, or any mission-specific material.

Mission authors may assign appropriate noise behavior to new surface types.

Other actions can also generate gameplay noise, including:

- jumping and landing
- thrown-object impacts
- dropped objects
- doors and mechanisms
- combat
- explosions
- tools
- alarms
- scripted machinery

NPC hearing responds to the gameplay significance of the sound, not merely the volume coming from the player's speakers.

Distance and intervening architecture matter.

Walls and closed doors reduce or block sound appropriately.

Open doorways and connected spaces allow sound to propagate more freely.

Objects can therefore be intentionally thrown to create distractions.

NPCs themselves make useful positional sounds through movement, interactions, grunts, machinery, and other mission-defined activity so that careful listening reveals information about spaces the player cannot currently see.

Audio must remain important enough that stopping and listening is a meaningful stealth technique.

---

# NPC awareness

Ordinary guards use a predictable escalating awareness model similar to Thief 1 & 2.

The exact hidden numeric values are implementation details. The player-facing behavior is what matters.

## Unaware

The NPC follows its ordinary authored behavior.

It may patrol, stand guard, sit, sleep, operate something, or perform another mission-defined routine.

## Mild suspicion

The NPC has received weak evidence: a questionable sound, a partial glimpse, or another small irregularity.

The NPC communicates uncertainty but has not confirmed an intruder.

It may briefly react without abandoning its ordinary route.

A `?` indicator and a short nonverbal vocal reaction communicate this state.

Any actual words are displayed as text above the NPC rather than spoken aloud.

If no further evidence appears, suspicion decays.

## Investigation / search

Stronger or repeated evidence causes the NPC to stop normal behavior and investigate.

The NPC moves toward a relevant location, looks around, searches nearby space, and attempts to determine what caused the disturbance.

Search behavior must be understandable and spatially related to the evidence.

The NPC does not magically know the player's current location.

A search can eventually end if no further evidence is found.

## Confirmed alert

Clear identification of the player causes a confirmed alert.

An `!` indicator communicates this state.

An armed hostile NPC can pursue and attack.

It may call or otherwise alert nearby relevant NPCs and may activate a mission-defined alarm.

If the player escapes, breaks contact, and hides successfully, the NPC searches based on the last useful information it had rather than tracking the player through walls.

Eventually it can return toward a lower alert state.

---

# NPC knowledge

NPC knowledge is local.

NPCs do not automatically share perfect global knowledge.

A guard who has not seen, heard, been warned about, or otherwise received information about the player should not behave as if it knows where the player is.

Mission logic may deliberately spread an alarm or alert through a building, faction, machine, magical system, or other mechanism when the mission calls for it.

That is an authored event, not automatic omniscience.

---

# NPC role

Ordinary NPCs are primarily **predictable stealth puzzle pieces**.

Their routes and common behavior should be learnable through observation.

Predictability is more important than attempting to simulate every detail of realistic human behavior.

Search behavior may contain enough variation to avoid looking robotic, but normal patrol behavior should not randomly invalidate a plan that was based on careful observation.

The ordinary guard archetype supplies the reusable senses, awareness, navigation, combat, life state, interaction, possessions, and mission-event hooks.

Mission creators may then script additional behavior.

Supported scripted behaviors must be capable of including things such as:

- conversations
- greetings
- sleeping
- eating
- sitting
- using doors
- operating machinery
- carrying keys or valuables
- responding to missing valuables
- responding to opened containers
- responding to extinguished lights
- responding to blood
- discovering bodies
- raising alarms

These behaviors are capabilities available to mission authors. They do not all need to run on every NPC in every mission.

---

# Dialogue and NPC communication

Vark does not use conventional fully voiced dialogue.

Normal character speech is displayed as typed text above the speaking character.

This includes:

- conversations
- greetings
- idle remarks
- suspicious remarks
- combat remarks
- scripted mission dialogue

Voice acting is minimal and primarily nonverbal:

- grunts
- effort sounds
- pain sounds
- surprise
- alarm sounds
- other short vocal reactions

Suspicion and confirmed detection are also reinforced visually with `?` and `!` indicators.

The player should therefore receive the informational function of Thief-style guard barks without requiring large amounts of recorded dialogue.

---

# Interaction model

The world uses one consistent interaction language.

There is one primary world-interaction button.

The object currently targeted near the center of the player's view can become interactable when:

- it is within range
- it is not blocked
- the current state allows interaction

Interactable objects visibly highlight.

There is no permanent central crosshair.

Interaction should manipulate the actual world state rather than merely showing abstract menu actions wherever a physical interaction can reasonably exist.

Examples include:

- opening a door
- opening a drawer
- opening a container
- pressing a switch
- taking loot
- taking a key
- taking an inventory item
- extinguishing a candle
- picking up an object
- picking up a body

---

# Doors

The base door archetype supports:

- unlocked doors
- locked doors
- keys
- barred or otherwise externally restricted doors
- NPC use
- open and closed states

Lockpicking is not part of the base game.

The normal base door is not destructible.

Special breakable doors can be created by a mission as special content using the general world/effect systems, but destructibility is not a property every normal door needs.

Doors physically animate between open and closed states.

The player does not control the exact opening speed or deliberately hold a normal door at an arbitrary partial angle as a special stealth mechanic.

The player may see through any actual geometric opening around or through a door.

There is no special keyhole-peeking mode.

Closed opaque doors block vision.

Doors affect sound transmission in the same intuitive way as other separating architecture.

Using a door produces appropriate audible feedback and may produce gameplay noise where appropriate.

Ordinary NPCs can use doors when their authored behavior requires it.

NPCs do not automatically treat an ordinary open door as suspicious.

A mission can specifically make door state meaningful if desired.

Physical objects may obstruct a door.

Doors should respect relevant physical obstruction rather than universally ignoring props.

This allows situations such as holding or wedging a doorway with a suitable physical object.

---

# Containers and physical searching

Containers may physically open and expose their contents.

Drawers, lids, cabinets, and similar mechanisms should visibly change state when opened where the content uses such an object.

Loot or inventory items inside them can then be taken normally.

Mission authors are free to create simpler containers when a full moving mechanism is unnecessary.

---

# Loot

Loot is an abstract collected resource once taken.

When the player successfully picks up a loot object, the world object disappears and its value/count is recorded.

Loot does not need to remain as a physical object in the player's hands after collection.

The meaning of loot between missions—score, purchasing power, an objective requirement, campaign resource, or something else—is campaign/content policy rather than a fundamental world rule.

The core game must nevertheless support Thief-style loot collection and mission statistics.

---

# Physical objects

Supported movable objects exist as physical world objects while placed in the mission.

Their ordinary behavior follows the object model of Thief 1 & 2 rather than a continuously active rigid-body simulation.

Supported physical objects:

- do not fall by themselves
- do not begin moving by themselves
- can be picked up
- can be dropped
- can be thrown
- can strike other objects or actors
- can create impact sounds
- can obstruct spaces
- can be stacked

An object remains where the mission creator placed it until something explicitly acts on it.

The player can deliberately move an object by picking it up, dropping it, or throwing it.

Thrown objects travel through the world and can collide with actors or geometry.

Thrown objects can injure characters when the impact is sufficient.

Physical objects can therefore be used as:

- distractions
- improvised weapons
- obstacles
- climbing aids
- door obstructions
- mission-specific puzzle elements

Boxes and other suitable props can be stacked and climbed on.

This is intentional emergent gameplay, not an exploit that should be prevented.

Large carried objects are presented in a first-person held position on the same presentation plane as the player's hands rather than appearing as freely simulated objects floating in the world in front of the camera.

The player cannot freely rotate a held world object.

The player cannot use ordinary world interactions while carrying a physical object.

Dropping or throwing the object returns it to its world-object state at its resulting position.

Objects do not subsequently roll, slide, topple, fall, or otherwise move merely because of continuous background physics unless a particular mission-specific object explicitly implements such behavior.

---

# World reaction rules

Vark does not require a universal simulation for every imaginable physical phenomenon.

Instead, it provides a small set of reusable world behaviors from which mission creators can build special cases.

## Destruction

The world is not universally destructible.

Only objects explicitly designed to take damage or break do so.

Normal architecture and normal doors are not assumed to be breakable.

Explosions and impacts can affect actors and objects that are configured to respond to them.

This allows mission authors to create breakable windows, special doors, machinery, lamps, or other destructible objects without making the entire world destructible.

## Fire

There is no mandatory global fire-spreading simulation.

Fire can damage or activate objects that are authored to respond to it.

Open flames may be extinguished by water effects.

Mission-specific flammable or spreading-fire behavior may be created when required.

## Gas

Gas is an area effect rather than a full fluid simulation.

A gas effect occupies an understandable region of space and can reach valid targets through connected open space, including open doorways.

Closed solid geometry prevents inappropriate magical transmission.

## Explosions

Explosions create strong sound and spatial effects such as damage.

They can affect configured breakable/damageable objects.

Normal nonbreakable doors do not automatically explode apart.

## Mines and deployables

A mine or similar deployable exists physically in the world after being used.

It can be placed on a suitable surface, arm, and react when its trigger conditions are met.

Mission-specific deployables can reuse the same basic behavior.

## Physical obstruction

Props may obstruct doors, actors, projectiles, and paths where their collision naturally does so.

NPCs do not have a generic "trip over loose object" behavior.

Special stumbling or trap behavior can be scripted for a mission if desired.

---

# Inventory and usable items

World props, loot, and usable inventory items are distinct concepts.

The game supports Thief-style inventory selection and use without requiring every carried item to remain physically simulated in the world.

The basic item grammar must be flexible enough to support:

- keys
- mission items
- consumables
- healing items
- thrown tools
- projectiles
- deployable tools / traps
- area-effect tools
- special mission-authored tools

The core game does not need to declare a permanent universal list of bombs, arrows, gadgets, potions, or supernatural abilities.

Specific items belong to campaign and mission content.

The underlying item/effect system must be flexible enough that common Thief-like or immersive-sim tools can be created without rewriting the player or inventory system.

A mission or campaign may decide:

- starting equipment
- item quantities
- which items are available
- whether equipment can be purchased
- whether unused equipment persists
- whether items carry between missions

Those are content-level rules.

---

# Bodies and life states

Characters have at minimum three meaningful life states:

- conscious
- unconscious
- dead

Unconscious and dead characters become body objects that can be interacted with and moved.

The player can:

- pick up a body
- carry it
- put it down
- hide it

Carrying a body reduces player mobility somewhat, but does not completely immobilize the player.

An unconscious character remains unconscious for the rest of the mission unless a particular mission deliberately defines a special exception.

Ordinary NPCs do not wake unconscious NPCs by default.

Dead characters remain dead.

Bodies may be detected by NPC perception when that evidence response is enabled for the mission.

A mission can make discovered bodies influence searches, alarms, objectives, statistics, or campaign consequences.

---

# Combat

Combat supports both lethal and nonlethal play.

The player can enter combat deliberately or reach it as a consequence of failed stealth.

One ordinary guard is generally manageable in direct combat.

Two guards are substantially more difficult because they can pressure the player at the same time.

Larger groups become increasingly dangerous.

The player can attempt to run away and break contact.

Escaping combat does not erase NPC awareness. Alerted NPCs continue searching afterward.

Combat produces enough noise to attract other nearby NPCs.

The core combat rules are deliberately small and consistent.

---

# Stealth knockout

There is no blackjack.

The player performs a stealth knockout with her fists.

While the attack button is held in the appropriate stealth-takedown context, the character raises a clenched fist and holds it ready.

When the player releases the attack, she strikes the NPC with the fist.

Against an eligible unaware ordinary NPC from a valid stealth position, the hit immediately knocks the NPC unconscious.

The result is nonlethal.

---

# Stealth kill

The stealth kill uses the same basic hold-and-release interaction as the stealth knockout.

Instead of raising a fist, the player readies the knife.

When the attack is released against an eligible unaware ordinary NPC from a valid stealth position, the player strikes with the knife and immediately kills the NPC.

---

# Block

Holding the block input blocks all ordinary incoming attacks that can be blocked.

The player can continue holding block instead of timing each incoming attack individually.

Blocking protects the player but does not create the offensive opening produced by a parry.

---

# Parry

Pressing block shortly before an incoming NPC attack connects performs a parry.

A successful parry makes the attacking NPC stagger.

The stagger creates an opening during which the NPC cannot successfully block or parry the player's follow-up attack.

---

# Knife hit

A normal knife attack against an NPC who is **not staggered** is defended against.

The NPC blocks or parries the knife attack.

A knife attack against a **staggered** NPC is an instant kill.

The intended direct lethal combat rhythm is therefore:

enemy attacks → player parries → enemy staggers → player uses knife → enemy dies.

---

# Blunt hit

A normal blunt/fist attack against an NPC who is **not staggered** is defended against.

The NPC blocks or parries the attack.

A blunt attack against a **staggered** NPC lands successfully.

A successful blunt hit does not immediately knock the NPC unconscious.

After several successful blunt hits, the NPC is knocked unconscious.

The intended direct nonlethal combat rhythm is therefore:

enemy attacks → player parries → enemy staggers → player lands blunt hit → repeat until knockout.

---

# Combat states

The important ordinary combat distinction is therefore:

**not staggered**

- NPC can attack
- NPC can block
- NPC can parry
- ordinary player knife/blunt attacks do not simply land

**staggered**

- NPC temporarily cannot block or parry effectively
- knife hit causes immediate death
- blunt hit lands and contributes toward knockout

The exact stagger duration, number of blunt hits required for knockout, attack timing, player health, and enemy damage are balance values rather than defining product rules.

They should be tuned without changing this basic combat grammar.

Taking damage does not produce a mandatory player stagger.

---

# Weapon presentation

The player's active combat option remains visibly presented in first person rather than being automatically hidden after every action.

First-person hands, knife, and held objects are presentation elements tied to real gameplay state.

Final meshes, textures, animations, and art may be replaced later without changing the underlying rules.

---

# Lethal and nonlethal play

Lethality and aggression are separate decisions.

The player can:

- silently kill isolated targets
- silently knock targets out
- openly fight lethally
- openly fight nonlethally
- avoid targets entirely

The game systems must record relevant outcomes such as kills and knockouts so mission and campaign content can react.

The baseline design should generally make lethal force more immediately convenient than achieving the same result nonlethally.

The cost of that convenience is primarily systemic and narrative rather than an arbitrary immediate punishment.

Writers and mission creators determine the actual consequences.

---

# Mission structure

Vark consists of authored missions rather than one mandatory open world.

A mission is a self-contained playable sandbox with objectives, an entry state, world state, and one or more possible completion/exit conditions.

A mission may contain any combination of:

- geometry
- lights and darkness
- NPCs
- patrols
- scripted NPC routines
- doors
- containers
- movable props
- loot
- keys
- inventory items
- environmental mechanisms
- triggers
- objectives
- optional objectives
- narrative events
- cutscenes
- mission-specific hazards
- mission-specific rules
- exits
- statistics
- campaign consequences

A good mission usually offers multiple useful ways of approaching its problems, but the core systems must not prescribe an exact number of entrances, paths, enemies, objectives, or solutions.

Mission design determines those things.

---

# Mission variation from previous choices

Missions are allowed to change according to actions and outcomes from previous missions.

Two players reaching the same nominal mission do not necessarily need to receive an identical version of it.

Persistent campaign state may alter things such as:

- which NPCs are alive or present
- which NPCs are friendly or hostile
- available patrols
- amount or placement of security
- open or closed routes
- available entrances
- available equipment
- world objects
- objectives
- optional objectives
- dialogue
- scripted events
- cutscenes
- available information
- mission starting conditions
- mission ending conditions

These variations are authored by mission creators.

They are not a separate "difficulty" system.

The mission changes because of what happened in the campaign, not because the player selected an easier or harder mode.

---

# No difficulty setting

Vark has **no difficulty setting**.

There is no Easy / Normal / Hard selection.

The player does not choose a difficulty when starting the campaign or a mission.

The intended rules of stealth, combat, movement, interaction, and the physical world are part of the game itself and do not change according to a difficulty option.

Challenge comes from:

- mission design
- enemy placement
- patrols
- geometry
- lighting
- sound-producing surfaces
- available resources
- objectives
- consequences of earlier choices
- the player's chosen approach

Individual missions may naturally be easier or harder than other missions.

A mission may also become easier, harder, or simply different because of campaign state.

Mission creators are free to make optional objectives or unusual constraints, but these are actual mission content rather than difficulty presets.

---

# Mission rules

Mission creators need a general way to express:

**when something happens, optionally check some conditions, then cause one or more things to happen.**

The game world must expose meaningful events such as:

- player enters an area
- door changes state
- item is taken
- loot is collected
- NPC changes awareness
- NPC dies
- NPC is knocked out
- body is discovered
- alarm is raised
- light changes state
- objective changes
- interaction occurs
- mission fact changes

Mission rules must be able to use those events to:

- change objectives
- change mission facts
- alter the world
- activate or disable entities
- change NPC behavior
- start scripted sequences
- display dialogue
- begin a cutscene
- trigger an alarm
- allow or prevent an exit
- finish or fail a mission
- record a campaign consequence

The exact technical representation of these rules is outside the scope of this document.

From a mission creator's perspective they should be practical to author without changing the core systems.

---

# Special mission behavior

Not every possible immersive-sim feature must exist in every mission or in the base entity set.

Things such as:

- unusual enemy types
- monsters
- cameras
- automated security
- turrets
- magical sensors
- special traps
- unusual machinery
- unique puzzle devices
- mission-specific environmental hazards
- unique weapons or tools
- special NPC behaviors

are mission content rather than mandatory global systems.

The core game should provide enough generic interaction, perception, damage/effect, event, mission-rule, and actor hooks that a mission programmer can implement a special feature when required.

Special mission code may extend the game.

It should not require rewriting the player controller, ordinary guard AI, inventory, mission lifecycle, or other core systems.

---

# Objectives and failure

Objectives have clear active, completed, and failed states.

Objectives may:

- exist from mission start
- appear during the mission
- become optional
- complete through world events
- fail through world events
- depend on campaign state

Detection does not automatically fail a mission.

An alarm does not automatically fail a mission.

Killing a civilian does not automatically fail a mission.

Killing an objective target does not automatically fail a mission.

Any of those things can fail a specific mission or objective if that mission explicitly says so.

If the player makes an objective impossible, the game may continue until the mission's rules declare failure or the player chooses to reload.

This allows mission designers to decide which actions matter instead of imposing universal failure rules.

---

# Saving and loading

The player can save during ordinary active gameplay.

Quick save and quick load are fundamental tools and are available through F5/F9 during normal gameplay.

Saving/loading may be temporarily unavailable during states where restoring arbitrary gameplay state would be inappropriate, such as an active noninteractive cutscene or a top-level transition.

The game does not shame or restrict the player for using quick save and quick load frequently.

Whether the player improvises through mistakes or reloads for a cleaner result is the player's choice.

Player death leads to loading a save or otherwise returning to a valid recovery/load state.

The base game does not use a checkpoint-only philosophy.

---

# Navigation and mission maps

Navigation follows the philosophy of Thief 1 & 2.

A mission can provide an authored map through the map screen.

The map is mission content rather than a universal automatically generated GPS system.

The core game does not require:

- automatic complete mapping
- exact live player position
- enemy markers
- objective arrows
- route guidance

Mission creators decide what their map contains and how accurate or incomplete it is.

A mission can provide no useful map, a rough sketch, a floor plan, multiple floor images, annotated plans, or a more specialized map if the content calls for it.

Navigation should remain primarily spatial and observational rather than waypoint-driven.

---

# Statistics

The mission results screen records what actually happened rather than judging the player with one mandatory global score.

The core statistics system must support common Thief-style facts such as:

- loot collected and available
- kills
- knockouts
- detections / significant alerts
- objectives completed
- mission time

Missions may add additional useful statistics such as secrets, bodies discovered, alarms, pockets picked, optional objectives, special collectibles, or other mission-specific facts.

Campaign logic can use statistics and mission facts where appropriate.

A universal letter grade or playstyle rank is not required.

---

# Campaign state and consequences

Mission-local state and campaign-persistent state are separate.

The campaign can remember meaningful actions and outcomes from earlier missions.

Examples include:

- a person being alive or dead
- a person being rescued or abandoned
- an object being stolen or left behind
- a faction being helped or harmed
- an optional action being completed
- a lethal or nonlethal outcome
- an alarm or major event occurring
- some other mission-specific fact

Later missions may read those facts and change:

- objectives
- NPC presence
- patrols
- dialogue
- available routes
- security
- resources
- mission events
- narrative scenes
- mission starting state
- mission order
- endings

The core platform supplies the memory and branching capability.

Writers and mission creators decide which facts matter and exactly how strongly later content reacts.

---

# Game flow

The basic campaign flow is:

1. main menu
2. New Game / Continue
3. pre-mission briefing
4. mission gameplay
5. optional in-mission scripted sequences or cutscenes
6. mission completion
7. mission results / statistics
8. campaign consequences and progression
9. next briefing or next campaign state

The game must also support:

- pause
- objectives
- map
- inventory
- statistics where useful
- settings
- save/load

There is no difficulty-selection screen or difficulty option.

---

# Cutscenes

In-mission cutscenes remain inside the first-person mission world.

The game temporarily takes input control.

Cinematic black bars appear.

Subtitles appear in the lower presentation area.

The camera may be controlled by the sequence while retaining the sense that this is the player's first-person viewpoint.

Afterward normal gameplay resumes safely.

A mission creator can determine what actors, actions, dialogue, animation, and events occur during the sequence.

---

# HUD

The permanent gameplay HUD should remain restrained.

The base HUD needs to communicate gameplay information that the player cannot reliably obtain otherwise.

The core HUD includes:

- light gem / visibility
- health
- currently selected usable item
- interaction feedback when relevant
- first-person weapon / hands / held-object presentation

There is no permanent crosshair.

Mission-specific HUD elements may be added when genuinely necessary.

---

# Audio presentation

Sound is a core gameplay information channel.

The audio presentation must support strong positional understanding of:

- footsteps
- NPC movement
- object impacts
- doors
- machinery
- combat
- tools
- alarms
- ambient sources

Surface differences and distance must be audible enough to be useful.

A player listening carefully should often be able to infer the location or movement of an NPC without seeing it.

Music and ambience may support atmosphere but must not obscure important stealth information.

Full spoken dialogue is not part of the normal presentation.

Final sound assets may be replaced later without changing the gameplay noise model.

---

# Visual presentation

The game world uses a readable low-fi first-person visual language inspired by Thief 1 & 2.

The environment is fundamentally compatible with brush-based TrenchBroom level construction.

Gameplay-important distinctions must remain visually clear:

- bright versus dark areas
- interactable versus non-interactable objects
- conscious versus unconscious/dead actors
- ordinary versus suspicious/alert NPC state
- usable doors and mechanisms
- relevant held/equipped items

Exact final textures, character models, architectural theme, menu artwork, UI sprites, setting, and atmosphere belong to later art/content production.

Replacing those assets must not require redesigning gameplay systems.

Placeholder presentation is acceptable during systems development as long as the necessary gameplay information is readable.

---

# Content intentionally left undefined

This systems vision deliberately does not define:

- the protagonist's story
- the world or historical period
- factions
- plot
- individual missions
- exact architecture
- final enemy roster
- specific special enemies
- exact equipment list
- mission-specific security systems
- final map artwork
- final textures
- final character designs
- final menu artwork
- final UI styling
- final music
- exact briefing content
- exact cutscene content
- exact endings

Those are production content.

The systems must be flexible enough to support them.

---

# Things not required as default core features

The following do not need to exist as universal default systems merely because a future mission might want something similar:

- special security devices
- cameras
- robots
- monsters
- magical powers
- complex environmental hazards
- global fire propagation
- universal destructibility
- breakable normal doors
- lockpicking
- procedural missions
- special traversal abilities beyond the accepted player controller
- unusual enemy archetypes

A mission programmer may create special versions when a mission requires them.

The important requirement is that the core platform makes extension possible without forcing changes to unrelated systems.

---

# Mission-author freedom

A mission creator owns the content of the mission.

Within the stable core rules they should be able to decide:

- level geometry
- routes
- lighting
- surface materials
- loot placement
- objectives
- fail conditions
- NPC placement
- patrol routes
- NPC routines
- dialogue
- keys
- door states
- containers
- props
- available tools
- alarms
- scripted reactions
- cutscenes
- map
- briefing
- statistics
- mission consequences
- campaign consequences
- variations caused by previous campaign choices
- special programmed content

The core game provides the grammar.

The mission creator writes the sentence.

---

# Systems-development completion target

Vark is ready to hand to mission creators when a developer who understands Godot and TrenchBroom but does not understand Vark's private core code can create a new mission containing, at minimum:

- a player start
- a brush-built navigable environment
- bright and dark spaces
- different sound-producing surfaces
- ordinary guards
- patrols
- suspicion, investigation, detection, pursuit, search, and recovery
- NPC state feedback
- doors
- keys
- containers
- switchable/extinguishable lights
- loot
- movable and throwable physical objects
- stealth knockouts
- stealth kills
- direct lethal combat
- direct nonlethal combat
- blocking
- parrying
- stagger
- bodies
- inventory items
- objectives
- triggers and mission reactions
- typed NPC dialogue
- first-person scripted sequences
- a mission map
- mission completion and exit
- end statistics
- saving and loading
- persistent campaign facts
- a later mission whose content changes because of a previous player choice

and can do so without modifying the core player, movement, stealth, ordinary NPC, inventory, mission-state, campaign-state, or game-flow code.

The same creator must also be able to add a mission-specific scripted object, unusual NPC behavior, hazard, puzzle, security system, or tool when necessary while interacting cleanly with the existing world and mission rules.

At that point Vark is no longer a collection of mechanics.

It is a reusable immersive-sim game platform ready for missions, plot, art, and campaign production.
