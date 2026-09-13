# Vark Game Vision

This document is the compact product and design north star for Vark. It is intentionally not an implementation plan. When code, tuning, or feature ideas conflict with this document, preserve the vision unless the design is explicitly changed.

## Core identity

Vark is a first-person stealth game in the tradition of Thief 1 & 2. The player infiltrates authored missions, observes spaces and NPC behavior, uses movement and environmental interaction to stay unseen, and makes meaningful choices through actions rather than dialogue menus.

The game should feel systemic enough that the player can form a plan, improvise when the plan fails, and understand why the world reacted.

## Design pillars

### 1. Stealth is the center of the game

Detection, light, sound, patrols, suspicion, hiding, route choice, distraction, and recovery from mistakes are more important than combat spectacle. Movement, interaction, combat, tools, UI, and level design should support stealth first.

### 2. Player choice happens through action

There are no dialogue-choice branches as the main decision mechanism. Choices are expressed through behavior such as killing or sparing someone, taking or leaving an object, being detected or remaining unseen, and completing optional actions. Later missions may change because of those actions.

### 3. Missions are authored stealth sandboxes

The game is divided into missions. A mission should provide multiple useful routes, readable spaces, opportunities for observation, stealth problems, optional actions, and consequences. Briefings, in-mission events, mission completion, statistics, and cross-mission state form the larger structure.

### 4. Movement serves infiltration

Movement should feel responsive, predictable, and physically trustworthy. The target movement set is:

- walk
- run
- sprint
- crouch
- slide
- jump
- ledge grab
- ledge shimmy / ledge traversal
- mantle / climb up from ledges
- ladders
- swimming

Wall dash is not part of the planned movement set.

Traversal should create routes and recovery options without turning the game into a high-speed movement game. Collision behavior should be stable enough that the player can trust narrow ledges, steps, walls, and drops.

### 5. The world should be readable, stylized, and low-fi

Environment direction:

- Thief 1 & 2 style world construction
- TrenchBroom-based level workflow
- low-resolution tiling textures
- hand-drawn / cartoon texture treatment
- deliberate sky texture and strong atmosphere

Character direction:

- low-poly solid models
- PS1-era simplicity, but cartoon proportions rather than realism
- hand-drawn textures
- 2D facial animation

The low-fi presentation is an art direction, not an excuse for unclear gameplay information.

## World and aesthetic identity

The city is happy, sunlit, and culturally centered on worship of the sun. Its visual language uses gold, pressed ornaments, decorative solar imagery, and bright civic presentation.

The protagonist is in conflict with that culture and adopts a contrasting moon-associated identity. The sun/moon contrast should be visible in architecture, decoration, color relationships, symbols, UI motifs where appropriate, and character presentation without overwhelming gameplay readability.

## Narrative presentation

### Dialogue

Dialogue is presented as typed lines above characters rather than conventional dialogue-choice UI. Suspicious or alerted enemies communicate state with a grunt and a visible question or exclamation mark.

### Cutscenes

In-mission cutscenes remain first-person. Player input is blocked during the cutscene, black bars appear at the top and bottom, and subtitles are shown in the lower bar.

### Mission structure

The intended larger loop is:

1. pre-mission video briefing
2. mission gameplay
3. possible in-mission cutscenes/events
4. mission completion
5. end screen with statistics
6. persistent consequences affecting later missions where applicable

## Core gameplay systems

### Stealth

The stealth model should eventually include at minimum:

- player light exposure and a light gem
- NPC vision
- player-generated noise
- NPC hearing
- suspicion / investigation
- alert / pursuit / search
- recovery back toward lower alert states when appropriate

The player should be able to understand the reason for detection through consistent visual, audio, and behavioral feedback.

### Interaction

Planned interactions include:

- open containers
- open doors
- open windows
- pick up loot / gems
- pick up small objects
- throw small objects
- pick up / throw boxes
- pickpocket
- pick up / put down bodies
- turn lights on/off
- extinguish candles

These should share a common interaction foundation rather than becoming unrelated one-off systems.

### Combat and takedowns

Planned combat behaviors include:

- stealth knockout with fists: hold to ready, release to strike
- stealth kill with knife: same basic stealth attack structure, lethal outcome
- block: hold to block attacks
- parry: press block shortly before an incoming hit
- knife hit: lethal
- fist strikes: multiple hits leading to knockout

Combat should remain compatible with the stealth-first identity. It should be a consequence-management and player-expression system, not the dominant solution to every mission.

### Items / tools

Planned items include:

- flashbang
- bomb
- mine
- gas bomb
- gas mine
- healing potion

Tools should create understandable tactical effects that interact with stealth, NPC state, space, and mission consequences.

## UI target

In-game HUD target:

- light gem
- health
- currently selected inventory item
- 3D weapon / held object in hand where appropriate

Menu targets include:

- objectives
- map
- gems / inventory
- alignment
- statistics
- possible glossary or related supporting information if later confirmed useful

UI should expose information the player needs for stealth decisions without becoming visually dominant.

## Development guardrails

- Prefer a small complete stealth loop over a large collection of disconnected mechanics.
- Build generic foundations before adding many individual variants: one interaction framework before many interactables, one item architecture before many tools, one mission-state model before many consequences.
- Do not add movement abilities merely because they could be interesting; add them because the game or a level needs them.
- Objective behavior should be protected by automated regression tests when practical.
- Subjective feel is decided by playtesting, not by tests.
- When a reproducible gameplay bug is fixed, add a regression test if the behavior can reasonably be automated.
- Preserve systemic clarity: the player should be able to learn why an action succeeded or failed.

## Source-of-truth rule

`DEVELOPMENT_PLAN.md` decides what to build next. `REGRESSION_TEST_PLAN.md` decides what objective behavior must remain protected. This document decides what the game is trying to become.
