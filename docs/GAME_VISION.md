# Vark Game Vision

This document defines the minimum complete gameplay contract for Vark before production missions, plot, final art, and final presentation are created.

It describes what the finished base game must allow the player to do, how its common systems behave from the player's point of view, and what mission creators must be able to build on top of those systems.

It does not define the setting, story, protagonist, factions, final enemy roster, individual missions, final textures, final UI art, specific mission maps, or other content that belongs to mission designers, writers, and artists.

The goal of systems development is to create Vark itself first and, from gameplay patterns proven in representative missions, stabilize the reusable platform needed for production. The finished platform must let mission creators build campaign content without rewriting core gameplay systems.

---

# Decision-state legend

- **LOCKED** — confirmed product rule or accepted player-facing behavior. Internal code may still change.
- **TARGET** — intended design that must be proven in playable integration before it becomes a permanent contract.
- **OPEN** — the problem is known, but the correct implementation/behavior should be discovered through a focused prototype.

Unless a section says otherwise, explicit product decisions in this vision are requirements. Exact tuning values and algorithms that have not yet been playtested remain TARGET or OPEN.

---

# Core identity — LOCKED

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

Stealth is normally safer. Direct violence is normally faster and easier in the immediate situation, especially against isolated ordinary enemies, but creates more noise, risk, bodies, alerts, and opportunities for campaign consequences.

The intended campaign philosophy is similar to Dishonored: lethal solutions may be tactically easier while restraint and nonlethal solutions may lead to better long-term outcomes.

The core game does not hard-code a particular story or morality system. It records meaningful player actions and exposes them to mission and campaign logic so writers can decide what consequences those actions produce.

Choice is primarily expressed through action rather than dialogue menus.

---

# Player movement — LOCKED behavior, mutable implementation

The existing player controller is the movement/feel contract.

Its **player-facing behavior is frozen**. Its internal implementation is not.

Future work may refactor:

- direct Godot input polling
- command routing
- pause/cutscene/UI input gating
- mouse ownership/capture
- scene/component structure
- internal state ownership
- test input injection

provided the accepted behavior and feel remain unchanged.

The supported movement is whatever the accepted player controller currently implements, including:

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
- mouse look

Future level geometry, props, doors, encounters, AI, and tools must adapt to this behavior.

The game must not add movement abilities simply because a later level would be easier to design around them.

Swimming, ladders, wall dashes, slides, or other traversal systems are not part of the base game unless that scope is deliberately reopened.

Exact movement values live in the controller and accepted regressions rather than being duplicated here.

---

# Basic gameplay rhythm — LOCKED

Vark does not impose one mandatory pace.

A player may spend several minutes listening, observing patrols, manipulating lights, hiding bodies, and waiting for a safe route.

Another player may sprint through the same space, attack guards, use tools, trigger alarms, escape pursuit, and improvise around the resulting chaos.

Both are legitimate gameplay.

The normal sandbox rhythm is:

> observe → choose an approach → act → world/NPCs react → continue or improvise → complete objectives → leave

Detection is normally a change in the situation, not an automatic game-over state.

---

# Stealth model — LOCKED direction

The default player-facing stealth model follows Thief 1 & 2.

Stealth has two primary sensory channels:

1. visibility
2. sound

NPCs accumulate evidence through these senses rather than switching instantly between completely unaware and completely omniscient.

The player must be able to understand why an NPC reacted.

---

# Visibility and darkness — LOCKED outcome, OPEN algorithm

Illumination is a real gameplay property.

The player's current exposure is communicated through a permanent light-gem style HUD indicator.

A dark light gem means the player is difficult to see. A bright light gem means the player is exposed.

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

World geometry and closed opaque doors block vision.

Mission authors may create NPCs with unusual perception, but ordinary guards use the common stealth model.

The exact exposure algorithm is **OPEN** until a representative lighting test space proves it. Rendered brightness and gameplay exposure are related but are not required to be the same computation. Decorative emissives or artistic darkness must not accidentally define stealth rules.

The system must be tested against dark, partially lit, fully lit, occluded, edge-of-light, and multiple-light cases until the light gem and what the player sees agree intuitively.

---

# Light sources — LOCKED capabilities

Lights may contribute to both visual presentation and player stealth exposure.

A light may be:

- permanently on
- switchable
- extinguishable
- controlled by mission events

Open flames can be extinguished by appropriate water effects.

A mission may create special lights that cannot be extinguished or that respond to other rules.

The game must clearly distinguish actual gameplay darkness from merely dark-looking decoration.

---

# Sound stealth — LOCKED outcome, OPEN propagation implementation

The player does not need a separate HUD noise meter.

The player should learn how noisy an action is primarily by hearing it and by observing NPC reactions.

Player movement noise depends on both movement and surface.

As a general relationship:

> crouched careful movement < normal movement < sprinting / hard landings

Different materials create meaningfully different footsteps. Soft surfaces are safer. Hard, resonant, or loose surfaces are more dangerous.

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
- NPC speech/reactions when relevant

NPC hearing responds to gameplay-significant sound, not merely speaker volume.

Distance and intervening architecture matter.

Walls and closed doors reduce or block transmission appropriately. Open doorways and connected spaces transmit sound more freely.

A simple distance radius is insufficient as the final stealth model. A single straight ray is also not sufficient for spaces where sound should travel through openings and around connected geometry.

The exact propagation architecture is **OPEN** until proven in a test map containing at minimum:

- one open room
- one separated room
- an open doorway
- a closed door
- an L-shaped/corner corridor

The final solution may use acoustic spaces/portals, zones, an acoustic graph, or another model, but it must produce intuitive Thief-like results.

Objects can be intentionally thrown to create distractions.

NPC movement, interactions, nonverbal vocal reactions, machinery, and other mission-defined sounds should provide useful positional information so that stopping and listening remains a meaningful stealth technique.

---

# NPC awareness — LOCKED behavior shape

Ordinary guards use a predictable escalating awareness model similar to Thief 1 & 2.

The exact hidden numeric values are implementation/tuning details.

## Unaware

The NPC follows ordinary authored behavior: patrol, stand guard, sit, sleep, operate something, or another mission-defined routine.

## Mild suspicion

The NPC has weak evidence: a questionable sound, partial glimpse, or another small irregularity.

It communicates uncertainty but has not confirmed an intruder.

It may briefly react without abandoning its ordinary route.

A `?` indicator and a short nonverbal vocal reaction communicate this state.

If no further evidence appears, suspicion decays.

## Investigation / search

Stronger or repeated evidence causes the NPC to stop normal behavior and investigate.

The NPC moves toward a relevant location, looks around, searches nearby space, and attempts to determine what caused the disturbance.

Search behavior must be spatially related to the evidence. The NPC does not magically know the player's current position.

A search can eventually end if no further evidence is found.

## Confirmed alert

Clear identification of the player causes confirmed alert.

An `!` indicator communicates this state.

An armed hostile NPC may pursue and attack, warn nearby relevant NPCs, and activate mission-defined alarms.

If the player escapes and hides successfully, the NPC searches from the last useful information it had rather than tracking through walls.

Eventually it can return toward a lower alert state.

---

# NPC knowledge — LOCKED

NPC knowledge is local.

NPCs do not automatically share perfect global knowledge.

A guard who has not seen, heard, been warned about, or otherwise received information about the player should not behave as if it knows where the player is.

Mission logic may deliberately spread an alarm or alert through a building, faction, machine, magical system, or another authored mechanism.

That is an event/system, not automatic omniscience.

---

# NPC role — LOCKED direction

Ordinary NPCs are primarily **predictable stealth puzzle pieces**.

Their routes and common behavior should be learnable through observation.

Predictability is more important than simulating every detail of realistic human behavior.

Search behavior may contain enough variation to avoid looking robotic, but normal patrol behavior should not randomly invalidate a plan based on careful observation.

The ordinary guard archetype supplies reusable senses, awareness, navigation, combat, life state, interaction, possessions, and mission-event hooks.

Mission creators may then script behaviors such as:

- conversations and greetings
- sleeping/eating/sitting
- using doors
- operating machinery
- carrying keys/valuables
- reacting to missing valuables/opened containers/extinguished lights/blood
- discovering bodies
- raising alarms

These are capabilities, not mandatory behavior for every NPC.

---

# Dialogue and NPC communication — LOCKED

Vark does not use conventional fully voiced dialogue.

Normal character speech is displayed as typed text **above the speaking NPC in world space**.

The text is intentionally allowed to remain visible through walls, doors, props, and other visual cover **when the player is supposed to hear that speech**. Dialogue readability is governed by audibility, not visual line of sight.

Therefore:

- clearly audible speech appears normally;
- marginal/distant speech may appear partially transparent;
- speech outside the player's intended audible range is not displayed;
- visual occlusion by itself does not hide audible speech text.

The speech presentation should remain anchored to the speaking NPC even when that NPC is behind cover, because the text substitutes for the informational content that voiced guard barks would otherwise provide.

Actual words may include:

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

Suspicion and confirmed detection are also reinforced visually with `?` and `!`.

The acoustic/hearing system determines whether speech is audible enough to display. This means dialogue-through-walls must use the same spatial sound logic as stealth listening rather than a separate arbitrary visibility rule.

---

# Interaction model — LOCKED

The world uses one consistent interaction language.

There is one primary world-interaction button. The default keyboard binding is **F**.

The object targeted near the center of the player's view can become interactable when:

- it is within range
- it is not blocked
- the current state allows interaction

Interactable objects use a Thief 1 & 2-style fullbright selection highlight: while targeted they keep their authored color and ordinary cast shadow, but the object's own visible surface is unshaded and receives no scene shadowing; normal shaded surface response returns immediately when selection is lost.

There is no permanent central crosshair.

Interaction should manipulate actual world state rather than abstract menu actions wherever a physical interaction can reasonably exist.

Examples include doors, drawers, containers, switches, loot, keys, inventory items, extinguishable lights, movable props, and bodies.

---

# Reusable modeled world objects — LOCKED authoring direction

Major structural architecture such as rooms, walls, floors, ceilings, stairs, and other built forms may remain brush-authored through TrenchBroom.

Reusable ordinary objects use external Godot-supported 3D model assets when that is the natural representation. This includes doors/openable windows, furniture, containers, movable props, mechanisms, loot presentation, and other repeated modeled world objects.

The gameplay archetype/entity and the visual model are separate concerns. The Vark archetype owns gameplay behavior, semantic/persistent identity, interaction/state, and cross-system integration. A model asset supplies replaceable presentation/configuration and must not become semantic identity or require gameplay code to depend on fragile imported mesh/node names.

Different compatible visual models should therefore be able to reuse the same gameplay archetype—for example wooden, metal, and ornate door models using ordinary door behavior, or chair/crate/vase models using ordinary prop behavior.

Openable windows are treated as ordinary door/opening variants. They reuse the same interaction, movement/open-state, collision/vision/acoustic/navigation/save integration as appropriate and do **not** require a separate window gameplay subsystem. A purely static/decorative window may simply be ordinary architecture/model presentation.

Final art replacement must preserve these gameplay contracts rather than forcing gameplay rewrites.

---

# Doors — LOCKED capabilities, integration spine

The base door archetype supports:

- unlocked doors
- locked doors
- keys
- barred/externally restricted doors
- NPC use
- open and closed states

Lockpicking is not part of the base game.

The normal base door is not destructible.

Doors physically animate between open and closed states. The player does not need a special mechanic for holding a normal door at an arbitrary partial angle. Compatible external model variants provide the visible door/openable-window presentation without replacing the shared ordinary-door gameplay contract.

There is no keyhole-peeking mode.

Closed opaque doors block vision.

Doors affect sound transmission intuitively.

Using a door produces appropriate audible feedback/gameplay noise.

Ordinary NPCs can use doors when authored behavior requires it.

NPCs do not automatically treat an ordinary open door as suspicious, though a mission may make door state meaningful.

Physical objects may obstruct doors. Suitable props can therefore wedge/hold a doorway.

Because doors touch interaction, collision, sound, vision, navigation, NPC use, save/load, mission events, and physical obstruction, the ordinary door is a core integration spine for system development.

---

# Containers and physical searching — LOCKED

Containers may physically open and expose their contents.

Drawers, lids, cabinets, and similar mechanisms should visibly change state where the content uses such an object.

Loot or inventory items inside can then be taken normally.

Mission authors may create simpler containers when a full moving mechanism is unnecessary.

---

# Loot — LOCKED

Loot is an abstract collected resource once taken.

When collected, the world object disappears and its value/count is recorded.

Its meaning between missions—score, purchasing power, objective resource, campaign resource, etc.—is content policy.

The core game supports Thief-style loot collection and mission statistics.

---

# Physical objects — LOCKED Thief-style contract

Settled movable props follow **Thief 1 & 2-style object behavior** while still responding physically to explicit contact. A genuinely resting prop uses an exact dormant/stable state so authored edge placements and stacks do not drift from background solver stabilization. A meaningful moving-prop impact, deliberate lateral player shove, or support removal explicitly promotes that same `RigidBody3D` back into dynamic motion; from that point gravity, friction, bounce/slide, transferred momentum, and solid collision response are resolved by the physics engine until it settles again.

The intended rule is deliberately stylized:

> **Supported objects stay exactly where they are. Unsupported objects fall until supported.**

A settled object does not:

- topple because its center of mass is near an edge;
- slowly slide on a slope;
- roll;
- spin;
- wobble;
- drift;
- react to background physics merely because a realistic rigid body would.

A meaningful **explicit** physical contact is different from background drift. A thrown/moving prop can transfer momentum into a resting ordinary prop, and walking laterally into a suitable prop can give it a clear physical shove. Ordinary box-like Junk is intentionally lightweight and readily movable by deliberate player pressure and prop-on-prop impacts. Those contacts promote the same rigid body into active motion and may translate it, but angular motion remains locked instead of tumbling freely.

A box may visibly overhang an edge and remain there if it still has valid support. Realistic torque is not a gameplay rule.

Supported physical objects:

- can be picked up
- can be dropped
- can be thrown
- can strike objects or actors
- can create impact sounds
- can obstruct spaces
- can be stacked
- can be climbed on where suitable

An object remains where the mission creator placed it until something explicitly acts on it or its support disappears. Explicit action includes pickup/throw/release, another physical object striking it, or the player deliberately pushing into it.

Ordinary furniture/prop archetypes may use different reusable external 3D model assets without changing these physical rules. Visual model choice is presentation/configuration, not a separate physics behavior or persistent identity. Ordinary hard-edged prop models must provide outward-facing geometry and hard/explicit face normals where appropriate so unselected props receive normal lighting and scene shadows; the temporary interaction highlight must not become their permanent render mode.

## Support and stacks

Settled objects maintain meaningful support relationships.

Example:

```text
Box C supported by Box B
Box B supported by Box A
Box A supported by World
```

If Box A is removed, the unsupported stack above it falls until support is found.

The stack should not explode, topple, scatter, or break apart merely because the lower support vanished. Where practical, an unsupported connected stack/group falls while preserving its relative arrangement until it lands/supports again, matching the simple visual behavior expected from Thief-like props.

Removing support is therefore different from applying a violent explicit impact/effect.

## Carried Junk, thrown, released, unsupported, and settled states

The implementation should behave conceptually like:

```text
settled/world
→ carried_junk
→ thrown or released
→ moving/unsupported
→ settling
→ settled/world
```

**Carried Junk** is a single-slot physical-object carry state, not ordinary inventory possession and not a world-space prop attached to the camera.

When an eligible highlighted ordinary prop is targeted in range, **F/Frob** picks it up immediately. The prop keeps the same semantic/persistent identity, but its physical world presentation and collision are inactive while carried. It therefore does not visibly hover in front of the player and cannot clip or collide with walls, doors, or other world geometry while in the carried state.

The player may carry exactly one Junk object at a time. Carried Junk is represented at the **bottom-center of the HUD**. Ordinary locomotion, turning, crouching, jumping, and traversal remain available unless a different explicit gameplay rule says otherwise.

Carrying Junk occupies the player's hands. While it is carried, ordinary world interaction plus hand-occupying attack and normal inventory-item use are unavailable through central interaction/input ownership rather than checks copied into every interactable, weapon, or item.

The ordinary-prop controls are:

- **F/Frob** on an eligible world prop while empty-handed: pick it up as the single carried Junk object;
- **F/Frob** while carrying Junk: throw it forward in the current view direction;
- **R** while carrying Junk: gently release/drop it using the current view for placement.

Throw and release restore the same prop to ordinary world participation with collision enabled. Throw applies substantial forward velocity. Release is deliberately gentler and should normally create less impact/noise than throwing.

Release placement uses the prop's real collision volume. World geometry and other physical objects remain solid blockers, but the placement search deliberately ignores the releasing player's capsule so cramped spaces may choose a world-clear pose that initially overlaps the player. Player, world, and ordinary props live on distinct physics collision channels. A carried prop that is released into player overlap uses a fourth transient filtering channel for that prop only: the player does not scan it and the prop does not scan the player, while the prop continues to scan world and ordinary-prop channels. The prop is therefore a normal live rigid body from the first moving physics tick with the complete throw or gentle-release velocity. The carry→world handoff is staged by gameplay and committed atomically through the body's synchronized `PhysicsDirectBodyState3D` callback so mode/filter/pose/velocity cannot be split across stale physics-server state; there is no frozen/manual escape translation. As soon as the actual prop and player collision volumes are geometrically separated, the prop returns to its ordinary prop layer/mask and collides with the player normally again. This overlap filter is derived transient physics state, not a timer, arbitrary travel-distance expiry, global collision shutdown, collision-exception cache workaround, or saved semantic state.

A prop that leaves world participation also invalidates player state derived from that exact collider. Standing support and active catch/hang/corner/mantle attachment cannot outlive a prop that has been picked up as carried Junk.

Catch, hang, and corner attachment to an ordinary prop require that prop to be semantically settled. Mantle keeps the same accepted motion whether entered from grounded contact or airborne contact, including when a light prop has just been shoved into motion. Because ledge candidates begin as world-space samples, a prop-backed mantle binds the sampled edge/route to the exact collider transform that produced it and updates that geometry as the rigid body translates, instead of converting the request into a jump or completing against a stale prop position. If the tracked collider disappears or ceases to be the same physical attachment, the mantle releases to ordinary airborne control.

The release point is derived from the player's current view rather than from a fixed world-space hand position. Looking downward and pressing **R** should place the object's center predictably beneath/in front of the player, approximately along the center-view release line, so deliberate crate stacking is practical.

Throw and gentle release enter world physics with the ordinary box already **top-up**, using the current view only to choose horizontal yaw and placement direction. Thrown/released/unsupported/disturbed objects then use real rigid-body translation while moving: gravity and collisions may change their position, linear velocity, slide, and bounce. Ordinary box-like Junk keeps angular motion locked, so hitting a floor, wall, prop, or actor does **not** rotate the box in flight and the object does not continuously track later camera turns. Because normal F/R carry release is already upright, ordinary settling preserves that exact orientation and only re-seats the body onto detected support; it must not perform a second face-changing roll after translation stops. A genuinely pre-tilted unsupported/restored prop may still use the short smooth pitch/roll correction to return top-up while preserving yaw. Completion returns the same rigid body to exact dormant/stable state. A later explicit impact, player shove, or support loss promotes it back into dynamic motion. Settling must never rotate a particular side toward world north or any other global compass direction.

Genuine dynamic rest is recognized from the rigid body's actual support/contact state rather than guessed proximity samples. This keeps edge/corner box-on-box contacts eligible to finish settling when the physics solver is already holding the object at rest.

Once motion resolves and the smooth top-up alignment completes, the object becomes exactly settled/stable again. Supported props then resume the ordinary stylized support rules above, but a later meaningful impact or lateral player shove can explicitly promote them back into disturbed rigid motion.

Physical props can be used as:

- distractions
- improvised weapons
- obstacles
- climbing aids
- door obstructions
- mission-specific puzzle elements

Special mission-specific objects may deliberately implement different physical behavior, but ordinary props obey this contract.

---

# World reaction rules — LOCKED direction

Vark does not require a universal simulation for every physical phenomenon.

Instead it provides a small set of reusable behaviors from which mission creators can build special cases.

## Destruction

The world is not universally destructible.

Only explicitly damageable/breakable objects break.

Normal architecture and normal doors are not assumed breakable.

## Fire

There is no mandatory global fire-spreading simulation.

Fire can damage/activate authored responders.

Open flames may be extinguished by water effects.

## Gas

Gas is an area effect rather than full fluid simulation.

It occupies an understandable region and can reach valid targets through connected open space. Closed solid geometry prevents inappropriate transmission.

## Explosions

Explosions create strong sound and spatial effects such as damage.

They can affect configured breakable/damageable objects.

Normal nonbreakable doors do not automatically explode apart.

## Mines and deployables

A mine or similar deployable exists physically in the world after use, can be placed on a suitable surface, arm, and react when trigger conditions are met.

## Physical obstruction

Props may obstruct doors, actors, projectiles, and paths where collision naturally does so.

NPCs do not have a generic "trip over loose object" behavior.

---

# Inventory and usable items — LOCKED direction

World props, carried Junk, loot, and usable inventory items are distinct concepts. The one-slot carried-Junk state temporarily stores one physical world prop and does not turn that prop into a normal inventory item.

The game supports Thief-style inventory selection/use without requiring every carried inventory item to remain physically simulated.

The item grammar must be flexible enough for:

- keys
- mission items
- consumables
- healing items
- thrown tools
- projectiles
- deployable tools/traps
- area-effect tools
- mission-authored special tools

Specific item lists belong to campaign/mission content.

A campaign may decide starting equipment, quantities, availability, purchasing, persistence, and carryover.

---

# Bodies and life states — LOCKED

Characters have at minimum:

- conscious
- unconscious
- dead

Unconscious/dead characters become body objects that can be interacted with and moved.

The player can pick up, carry, put down, and hide bodies.

Carrying a body reduces mobility somewhat but does not completely immobilize the player.

An unconscious character remains unconscious for the mission unless special content defines an exception.

Ordinary NPCs do not wake unconscious NPCs by default.

Bodies may be detected by perception and may influence searches, alarms, objectives, statistics, or campaign consequences when authored.

---

# Combat — TARGET until validated in play

Combat supports lethal and nonlethal play.

The current intended grammar is a **TARGET**, not yet a LOCKED accepted-feel contract.

One ordinary guard should be manageable in direct combat; two should be substantially harder; larger groups increasingly dangerous.

The player can run away and break contact. Escaping does not erase NPC awareness, and combat produces enough noise to attract relevant nearby NPCs.

## Target stealth knockout

No blackjack. In a valid stealth-takedown context, hold attack to ready a fist; release to strike and immediately knock out an eligible unaware ordinary NPC.

## Target stealth kill

Same basic hold/release interaction with knife; release in a valid stealth context to immediately kill an eligible unaware ordinary NPC.

## Target block/parry/stagger grammar

- holding block stops ordinary blockable attacks;
- pressing block shortly before impact parries;
- successful parry staggers the attacker;
- a non-staggered ordinary NPC defends against normal player knife/blunt attacks;
- knife against staggered NPC = instant kill;
- blunt against staggered NPC = successful hit; several successful hits produce knockout;
- taking damage does not require mandatory player stagger.

Exact timings, health, damage, stagger duration, and blunt-hit count are balance values.

Before this combat grammar becomes LOCKED it must be playtested against:

- one guard
- two guards
- tight corridor
- open room
- actively attacking enemies
- lethal assault
- nonlethal assault
- transition from stealth into open combat

If the target grammar does not produce good play in those situations, it should be revised before being frozen.

---

# Mission structure — LOCKED

Vark consists of authored missions rather than one mandatory open world.

A mission is a self-contained playable sandbox with objectives, an entry state, world state, and one or more possible completion/exit conditions.

A mission may contain brush geometry, external 3D model assets/variants, lighting, surfaces, NPCs, patrols, routines, doors/openable windows, containers, furniture/props, loot, keys, items, mechanisms, triggers, objectives, narrative events, cutscenes, hazards, rules, exits, statistics, and campaign consequences.

A good mission usually offers multiple useful approaches, but the core systems do not prescribe exact entrances, paths, enemies, objectives, or solutions.

---

# Mission variation and campaign state — LOCKED

Persistent campaign state may alter later missions, including:

- NPC presence/allegiance
- patrols/security
- routes/entrances
- equipment
- world objects
- objectives
- dialogue
- scripted events/cutscenes
- starting/ending conditions
- mission order/endings

These are authored consequences, not a difficulty system.

Mission-local state and campaign-persistent state are separate.

---

# No difficulty setting — LOCKED

Vark has no Easy / Normal / Hard selection.

Stealth, combat, movement, interaction, and world rules do not change through a difficulty option.

Challenge comes from authored content, resources, consequences, and the player's approach.

Optional constraints are mission content, not difficulty presets.

---

# Mission rules — LOCKED scope, TARGET grammar

Mission creators need a convenient way to express:

> when an event happens, optionally check conditions, then perform actions

The data rule layer may react to semantic events such as area entry, door state change, item/loot collection, NPC awareness/life-state changes, body discovery, alarms, light changes, objective changes, interactions, and fact changes.

It may change objectives/facts/world state, activate entities, influence NPC behavior, start sequences/dialogue, trigger alarms, gate exits, finish/fail missions, and record campaign consequences.

The grammar must remain intentionally small.

It must **not** grow into a second programming language with arbitrary loops, locals, nested general control flow, or unrestricted object manipulation.

The finished production game exposes procedural/unusual mission logic through stable public mission extension APIs. During systems development, the roadmap may keep those APIs provisional/supportable until representative mission use proves them; mission content must not depend on private core internals in the meantime.

Mission facts should be declared with a simple schema containing at least key, type, default, and scope so typos and implicit incompatible values do not silently become game logic.

---

# Special mission behavior — LOCKED extensibility goal

Special enemies, cameras, security systems, traps, machinery, hazards, unique tools, and unusual NPC behavior are mission content rather than mandatory universal systems.

The core game should provide enough generic interaction, perception, damage/effect, event, mission-rule, and actor hooks that special content can be implemented without rewriting unrelated core systems.

---

# Objectives and failure — LOCKED

Objectives have active, completed, and failed states.

Objectives may exist from mission start, appear later, become optional, complete/fail through world events, and depend on campaign state.

Detection, alarms, civilian kills, or killing an objective target do not automatically fail every mission.

Any of those may fail a specific mission/objective if that mission explicitly says so.

---

# Saving and loading — LOCKED player-facing rule

The player can save during ordinary active gameplay.

F5/F9 quicksave/quickload are fundamental tools.

Saving/loading may be unavailable only in states where restoring arbitrary gameplay state is intentionally inappropriate, such as an active noninteractive cutscene or top-level transition.

The game does not shame or restrict frequent saving/loading.

The base game is not checkpoint-only.

Because ordinary gameplay quicksave is fundamental, each stateful system must define meaningful restore semantics for transient states rather than assuming saves only occur while everything is idle.

---

# Navigation and mission maps — LOCKED

Mission maps are authored content, not universal automatically generated GPS.

The core game does not require exact live position, enemy markers, objective arrows, or route guidance.

A mission may provide no map, a sketch, floor plan(s), annotated plans, or specialized map content.

Navigation remains primarily spatial and observational.

---

# Statistics — LOCKED

The mission results screen records what happened rather than assigning one mandatory global grade.

Core statistics include:

- loot collected/available
- kills
- knockouts
- detections/significant alerts
- objectives completed
- mission time

Missions may add other statistics/facts.

---

# Game flow — LOCKED direction

The basic campaign flow is:

1. main menu
2. New Game / Continue
3. pre-mission briefing
4. mission gameplay
5. optional in-mission scripted sequences/cutscenes
6. mission completion
7. mission results/statistics
8. campaign consequences/progression
9. next briefing/campaign state

The game also supports pause, objectives, map, inventory, settings, and save/load.

There is no difficulty-selection screen.

---

# First-person cutscenes — LOCKED direction

In-mission cutscenes remain in the first-person mission world.

The game temporarily owns input.

Cinematic black bars and lower-area subtitles may appear.

The camera may be sequence-controlled while preserving first-person perspective.

Normal gameplay resumes safely afterward.

---

# HUD — LOCKED direction

The permanent gameplay HUD is restrained.

Core presentation includes:

- light gem / visibility
- health
- selected usable item
- interaction feedback when relevant
- first-person weapon/hands presentation
- bottom-center carried-Junk presentation for the one carried physical prop

There is no permanent crosshair.

Mission-specific HUD elements may be added when genuinely necessary.

---

# Audio presentation — LOCKED

Sound is a core gameplay information channel.

Audio must support useful positional understanding of footsteps, NPC movement, impacts, doors, machinery, combat, tools, alarms, and ambient sources.

Surface differences and distance must be audible enough to be useful.

Music/ambience must not obscure critical stealth information.

Full spoken dialogue is not normal presentation; typed world-space speech carries the words.

Final sound assets may be replaced without changing gameplay noise semantics.

---

# Visual presentation — LOCKED direction

The game uses a readable low-fi first-person visual language inspired by Thief 1 & 2 and compatible with brush-based TrenchBroom construction. Structural spaces can remain brush-authored while reusable doors/openable windows, furniture, containers, props, mechanisms, and similar world objects use replaceable external 3D model assets through their gameplay archetypes.

Gameplay-important distinctions must remain clear:

- bright vs dark
- interactable vs non-interactable
- conscious vs unconscious/dead
- ordinary vs suspicious/alert NPC
- usable doors/mechanisms
- carried-Junk/equipped state

Final textures, characters, architecture theme, UI art, setting, and atmosphere belong to production content.

Replacing presentation assets must not require redesigning gameplay systems.

---

# Content intentionally left undefined

The systems vision deliberately does not define the protagonist/story, setting/period, factions, plot, individual missions, exact architecture, final enemy roster, exact equipment list, mission-specific security, final maps/textures/characters/UI/music, exact briefings/cutscenes, or endings.

Those are production content.

---

# Things not required as default core features

The following do not need to exist universally merely because a future mission might want something similar:

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
- traversal abilities beyond the accepted controller
- unusual enemy archetypes

Mission-specific code may add special versions.

---

# Mission-author freedom — LOCKED goal

Within stable core rules, mission creators should be able to decide:

- geometry/routes
- lighting/surfaces
- loot/objectives/fail conditions
- NPC placement/patrols/routines/dialogue
- keys/doors/openable-window variants/containers/furniture/props and their reusable external model variants
- tools/alarms/reactions
- cutscenes/maps/briefings/statistics
- mission/campaign consequences
- variations from previous choices
- special programmed content

The core game provides the grammar. The mission creator writes the sentence.

---

# Systems-development completion target

Vark is ready to hand to mission creators when a developer who understands Godot and TrenchBroom but does not understand Vark's private core code can create a new mission containing, at minimum:

- player start and brush-built navigable environment
- bright/dark spaces
- different sound-producing surfaces
- ordinary guards/patrols
- suspicion, investigation, detection, pursuit, search, recovery
- NPC state feedback
- reusable external-model doors/openable-window variants/keys/containers/furniture
- switchable/extinguishable lights
- loot
- Thief-style movable/throwable physical objects
- stealth knockouts/kills
- direct lethal/nonlethal combat
- blocking/parrying/stagger
- bodies
- inventory items
- objectives/triggers/mission reactions
- typed audible NPC dialogue
- first-person scripted sequences
- mission map
- completion/exit/results
- active-gameplay saving/loading
- persistent campaign facts
- a later mission changed by a previous player choice

and do so without modifying core player behavior, movement, stealth, ordinary NPC, inventory, mission-state, campaign-state, or game-flow systems.

The same creator must be able to add mission-specific scripted objects, NPC behavior, hazards, puzzles, security systems, or tools through stable extension APIs.

At that point Vark is a reusable immersive-sim game platform ready for full mission, plot, art, and campaign production.
