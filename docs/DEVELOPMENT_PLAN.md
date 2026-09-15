# Vark Development Plan

This is the ordered implementation roadmap for Vark. Repository workflow is defined in `AGENTS.md`; testing conventions and current regression coverage live in `docs/TESTING.md`.

Status: `[ ]` not implemented, `[~]` implemented but awaiting required validation/follow-up, `[x]` validated and accepted.

Each item should be implemented as a bounded step. Do not advance a milestone merely because its individual systems exist: its integration result must also be acceptable in play.

The final systems-development goal is not merely that every mechanic exists. Vark is ready to hand to mission developers and plot writers only when those systems form a stable content-authoring platform that can be used without modifying core gameplay code.

## Current implementation baseline

The project currently has a substantial accepted player controller, movement regression tests, FuncGodot/TrenchBroom geometry import, static graybox maps, and a movement-oriented test scene. It does not yet have a production game shell, active gameplay-lighting setup, NPCs, navigation, interactable world objects, pickups, inventory, mission runtime, campaign state, combat, menus/game-flow screens, narrative systems, or production content-authoring tools.

Development must therefore grow one playable game vertically rather than building many isolated systems and integrating them at the end.

## Roadmap rules

- The current movement and climbing behavior is frozen. Future systems adapt to it; they do not redesign or retune it unless the user explicitly reopens that scope.
- Introduce temporary UI, audio, debug feedback, and validation when a system first needs them. Final polish may come later, but feedback and diagnosability may not.
- Expose provisional level-authoring hooks as real gameplay entities appear. Milestone 12 stabilizes those interfaces; it must not be the first time designers can place gameplay objects.
- Build generic architecture from concrete needs demonstrated by the playground and vertical-slice missions. Do not build a universal scripting language, giant inventory framework, or custom editor before real content proves it is needed.
- Reuse semantic events/state between gameplay, statistics, missions, campaign consequences, UI, and debugging rather than maintaining duplicate truth.
- Every major milestone ends in an integrated playable result.

---

# Milestone 1 — Freeze the player and establish the real application shell

Goal: protect the accepted player behavior and stop treating a development scene as the whole application.

## 1.1 Existing player locomotion and traversal `[x]`

**Scope:** accept the currently implemented normal locomotion, sprint, crouch, jump/air control, support/collision response, steps, ledge grab/hang/traversal/corners, and mantle behavior as the movement contract.

**Acceptance:** current accepted movement feel remains unchanged.

## 1.2 Local automated movement regression barrier `[x]`

**Scope:** keep the existing headless movement runner, deterministic physics fixtures, failure aggregation, and nonzero failure exit.

**Acceptance:** `tests/movement/run_movement_tests.gd` remains the authoritative current automated barrier and its intentional-failure mode still fails correctly.

## 1.3 Traversal regression protection `[ ]`

**Scope:** add focused deterministic coverage for representative existing ledge grab, hang, shimmy/corner traversal, mantle, release/drop, and regrab-suppression behavior where practical. Tests protect accepted behavior; they do not define new movement behavior.

**Depends:** 1.1–1.2.

**Acceptance:** repeated suite runs are stable and later gameplay changes can detect accidental traversal breakage without requiring movement redesign.

## 1.4 Application bootstrap and game-flow owner `[ ]`

**Scope:** create the actual F5 application root with clear ownership for the current world, player, UI layer, and top-level game-flow transitions. Add a minimal functional main-menu/dev-entry screen so normal application startup no longer depends on running a development scene directly.

**Acceptance:** F5 starts Vark through one stable root; entering and leaving the current gameplay world is controlled by the game-flow layer rather than arbitrary scene scripts.

## 1.5 Pause and input-ownership foundation `[ ]`

**Scope:** establish pause/back behavior, mouse capture/release, and the distinction between gameplay input and UI input. Add a minimal pause screen with Resume and Return-to-Main-Menu behavior; settings may remain a placeholder until real settings exist.

**Depends:** 1.4.

**Acceptance:** opening UI does not continue moving/looking the player, resuming restores input correctly, and leaving gameplay returns through the game-flow owner.

## 1.6 Collision/query conventions `[ ]`

**Scope:** establish the minimum collision/query categories future systems need, such as world, player, NPC, physical/interactable object, and trigger/query-only layers. Do not allocate speculative layers.

**Acceptance:** later interaction, AI vision, triggers, and props can use a documented shared layer contract without changing player movement behavior.

## 1.7 TrenchBroom/map source baseline `[~]`

**Scope:** retain the existing FuncGodot/TrenchBroom pipeline and define ownership conventions: `.map` is authored level geometry source, imported/generated representation is not manually maintained, and development maps are separated conceptually from future production missions.

**Acceptance:** a small source-map edit can be reimported predictably without hand-fixing generated scene content.

## 1.8 Repository/content hygiene `[ ]`

**Scope:** audit tracked autosaves, generated/imported files, large experimental maps, and future binary-asset handling before content production expands. Preserve genuine authored source; remove only files whose ownership is understood.

**Acceptance:** repository conventions no longer encourage committing editor autosaves or ambiguous generated content, and large-source handling has an explicit policy.

## 1.9 Continuous tests in GitHub Actions `[ ]`

**Scope:** pin the project Godot version and run the same authoritative local regression command on pushes to `test` and pull requests. Once a second real suite exists, introduce one authoritative `tests/run_all_tests.gd` or equivalent and make both local full-regression and CI use it.

**Depends:** 1.3.

**Acceptance:** normal suite passes in CI; intentional failure proves the workflow fails; the check remains non-required until stable and non-flaky.

**Milestone gate:** Vark starts as an actual application, pause/input ownership works, the accepted player is protected rather than redesigned, and project/map foundations are ready for new gameplay.

---

# Milestone 2 — Build a small real gameplay laboratory

Goal: stop developing future systems against an empty/static movement test environment. Create the smallest lit world with real reusable objects and known scale.

## 2.1 Clean gameplay playground `[ ]`

**Scope:** create a compact purpose-built graybox containing a bright area, dark area, hallway, doorway, cover, a future patrol loop, and a small interaction area. Keep the large movement test scene separate.

**Acceptance:** the new scene is fast to run and easy to modify for gameplay-system tests without disturbing movement regression fixtures.

## 2.2 World scale and clearance metrics `[ ]`

**Scope:** document/prove practical dimensions for ordinary doors, corridors, guard placeholders, cover, and props against the frozen player body and traversal behavior.

**Acceptance:** representative graybox architecture fits the existing player without requiring controller retuning.

## 2.3 Active lighting baseline `[ ]`

**Scope:** add actual visible authored lighting and meaningful darkness using the minimum light types needed by the playground. This is rendering/environment setup, not yet the stealth-exposure calculation.

**Acceptance:** the playground contains clearly readable bright, partially lit, and dark spaces with working shadows/occlusion suitable for later stealth tests.

## 2.4 Reusable static prop `[ ]`

**Scope:** create the first non-map reusable world-object scene with placeholder mesh/material and collision.

**Acceptance:** it can be placed repeatedly without special scene wiring and behaves as ordinary world geometry where intended.

## 2.5 Reusable physical prop `[ ]`

**Scope:** create a simple dynamic physics prop that can fall, collide, settle, and later become pickup/throw content.

**Acceptance:** it remains physically stable around the player and playground geometry without altering locomotion behavior.

## 2.6 Early asset-pipeline spike `[ ]`

**Scope:** prove one representative external model, texture/material, and audio asset can enter the project with intentional import settings. This is a pipeline proof, not production art.

**Acceptance:** future art/audio work has a known import path and scale convention rather than relying only on built-in primitives.

**Milestone gate:** Vark has a small lit gameplay space, known physical scale, reusable props, and a proven basic content-import path.

---

# Milestone 3 — Interaction vertical slice

Goal: establish one reusable player/world interaction language and immediately prove it on several different object types.

## 3.1 Interaction input and focus `[ ]`

**Scope:** add the interaction input and camera-based target selection with range, occlusion, and valid-target filtering.

**Acceptance:** automated focus/range/blocked-target behavior where deterministic; manual targeting is stable at ordinary and awkward viewing angles.

## 3.2 Interactable action contract `[ ]`

**Scope:** define one semantic interface for objects to expose whether they can be used, what action is available, and what happens when activated. Individual objects must not poll raw player input themselves.

**Depends:** 3.1.

**Acceptance:** at least two different object types can use the same interaction dispatch without special cases in the player.

## 3.3 Temporary interaction prompt `[ ]`

**Scope:** add simple functional feedback such as `Open`, `Take`, or `Use` for the currently focused action.

**Acceptance:** prompt truth follows actual focus/action availability and disappears immediately when the target becomes invalid.

## 3.4 Door `[ ]`

**Scope:** create the first reusable door with open/closed state, collision behavior, and interaction through 3.2. Lock/key behavior waits for a concrete need.

**Acceptance:** state transitions are deterministic; manual use from both sides and around edges does not destabilize the player.

## 3.5 Switchable light `[ ]`

**Scope:** create an interactable visible light that can be switched on/off through the same interaction contract.

**Acceptance:** visible lighting state changes reliably and later stealth-light logic has a clean state to consume.

## 3.6 Collectible loot object `[ ]`

**Scope:** create the first collectible world object with stable ownership transfer: world instance → collected/value state → world removal. Keep mission valuables separate from future usable inventory.

**Acceptance:** duplicate collection is impossible, value/ownership changes once, and temporary feedback makes collection observable.

## 3.7 Held physical object: pickup and put-down `[ ]`

**Scope:** let the player take control of a supported physical prop, hold it, and put it down without yet requiring throwing/noise gameplay.

**Acceptance:** world/held ownership is unambiguous and putting objects down near walls/doors does not break the player controller.

## 3.8 Provisional TrenchBroom gameplay exposure `[ ]`

**Scope:** expose the real gameplay objects that already exist—at minimum door, switchable light, basic prop, and loot—through provisional Vark/TrenchBroom authoring conventions. Add validation for the properties actually required now.

**Acceptance:** a small map can place/configure these objects without manual private-node wiring in Godot. The contract may still evolve before production lock.

**Milestone gate:** a graybox level can contain authored gameplay objects that the player can understand and manipulate through one interaction system.

---

# Milestone 4 — NPC and stealth vertical slice

Goal: create the first real guard and the smallest complete stealth loop inside the playground.

## 4.1 Placeholder NPC actor `[ ]`

**Scope:** create a reusable NPC scene with primitive/placeholder visuals, obvious facing direction, collision, stable actor identity, and visual presentation separated from gameplay ownership.

**Acceptance:** the actor can exist idle in the playground without player/NPC collision instability.

## 4.2 Navigation foundation `[ ]`

**Scope:** create the navigation environment and NPC movement layer needed to receive a destination, turn/move, stop, report arrival, and report unreachable targets.

**Depends:** 4.1.

**Acceptance:** deterministic navigation-state behavior is covered where practical; the NPC can reach representative playground destinations without guard-state logic.

## 4.3 Patrol route `[ ]`

**Scope:** support authored route points, order/loop behavior, waits where needed, and clear interruption/resume ownership. Expose the provisional patrol authoring path alongside the NPC.

**Acceptance:** one NPC follows a placed patrol repeatedly and reports invalid/unreachable route data rather than silently freezing.

## 4.4 Guard state and evidence model `[ ]`

**Scope:** establish explicit ownership for unaware/patrol, suspicious, investigating, alerted, searching, and recovery behavior. Perception systems produce evidence; they do not directly own all AI behavior.

**Acceptance:** key transitions/timers are deterministic and debug-driven state changes do not cause movement/state systems to fight each other.

## 4.5 Gameplay-light source and player exposure `[ ]`

**Scope:** define which visible lights contribute to stealth gameplay and compute a stable player-exposure value from contribution, range/distance, enabled state, and world occlusion. Keep rendering from being the sole source of gameplay truth.

**Depends:** 2.3, 3.5.

**Acceptance:** fixed bright/dark/occluded cases are deterministic; manual movement through the playground roughly matches what the player sees.

## 4.6 Temporary light gem `[ ]`

**Scope:** show player exposure immediately through a simple readable HUD representation. Final art comes later.

**Acceptance:** mapping from exposure to displayed state is deterministic and useful during playtesting.

## 4.7 Guard vision `[ ]`

**Scope:** implement range, FOV, world occlusion, semantic player visibility targets, and exposure-dependent evidence.

**Depends:** 4.4–4.5.

**Acceptance:** visible, outside-FOV, occluded, out-of-range, and exposure-dependent cases are covered; manual approaches feel explainable.

## 4.8 Player gameplay-noise model `[ ]`

**Scope:** emit semantic noise from the accepted player behavior—normal movement, sprint, landing, and later extendable actions—without changing locomotion to make noise easier to implement.

**Acceptance:** representative actions emit expected semantic noise and silent/non-triggering cases do not create unintended events.

## 4.9 Placeholder movement audio `[ ]`

**Scope:** add audible placeholder feedback for movement/noise-relevant actions. Audible SFX and AI gameplay-noise strength are separate systems but should correspond intelligibly.

**Acceptance:** the player can hear the broad difference between relevant movement events while AI tuning remains based on semantic noise data.

## 4.10 Guard hearing `[ ]`

**Scope:** convert relevant gameplay-noise events into hearing evidence using distance and only the environmental rules actually needed now.

**Depends:** 4.4, 4.8.

**Acceptance:** audible/inaudible and distance/strength cases are deterministic; manual distraction behavior is understandable.

## 4.11 Investigation, alert/pursuit, search, and recovery `[ ]`

**Scope:** turn sight/hearing evidence into coherent action: investigate evidence, react to confirmed detection, pursue while contact is valid, search last-known areas after losing the player, and recover when appropriate. Until health/combat exists, detection may use a temporary caught/failure outcome where needed.

**Depends:** 4.2–4.4, 4.7, 4.10.

**Acceptance:** repeated detection/loss/recovery scenarios have understandable state ownership and pacing.

## 4.12 Guard debugging/inspection `[ ]`

**Scope:** provide development-only visibility into current guard state, evidence, perception results, navigation target/failure, and patrol state. Build diagnostics now rather than waiting for production handoff.

**Acceptance:** common failures such as `did not see`, `did not hear`, or `cannot reach target` can be diagnosed without stepping through core AI code.

## 4.13 Basic multi-guard communication `[ ]`

**Scope:** after one guard works, add the minimum understandable communication needed for several guards to coexist without magical global knowledge.

**Acceptance:** a confirmed alert can influence another nearby/relevant guard according to explicit rules while isolated guards remain ignorant when they should.

## 4.14 Stealth-playground vertical slice `[ ]`

**Scope:** integrate active lighting, patrols, cover, sight, hearing, investigation, detection, loss of sight, search, and recovery with several routes.

**Acceptance:** the player can deliberately hide, make noise, cause investigation, get spotted, break contact, hide again, and observe a readable search/recovery loop.

**Milestone gate:** Vark is recognizably a stealth game before mission/campaign complexity is added.

---

# Milestone 5 — Mission framework and first true vertical slice

Goal: prove mission architecture early, before takedowns, combat, and many tools make the system harder to change.

## 5.1 Stable content IDs `[ ]`

**Scope:** give mission-referenceable actors/objects semantic IDs independent of scene-tree paths and detect duplicates clearly.

**Acceptance:** moving/renaming private scene nodes does not break mission references; duplicate IDs fail validation explicitly.

## 5.2 Runtime content registry `[ ]`

**Scope:** resolve stable IDs to live runtime objects through one owned interface rather than ad-hoc scene searches.

**Depends:** 5.1.

**Acceptance:** valid/invalid lookup behavior is deterministic and missing references are diagnosable.

## 5.3 MissionDefinition and MissionState `[ ]`

**Scope:** separate authored mission configuration from mutable runtime state. MissionDefinition contains stable mission metadata/configuration; MissionState owns active objectives, mission-local facts, and other mission-scoped runtime truth.

**Acceptance:** restarting a mission creates fresh runtime state from the same definition without mutating authored resources.

## 5.4 Generic objective model `[ ]`

**Scope:** represent objectives as stable named state—such as inactive, active, completed, failed—rather than making a subclass for every goal type.

**Depends:** 5.3.

**Acceptance:** objective transitions and duplicate completion/failure handling are deterministic.

## 5.5 Authorable trigger volumes `[ ]`

**Scope:** add reusable spatial triggers with stable IDs and provisional TrenchBroom authoring support.

**Acceptance:** player/NPC entry behavior is deterministic and trigger references validate cleanly.

## 5.6 Semantic gameplay event stream `[ ]`

**Scope:** publish meaningful events from real systems, such as loot taken, trigger entered, door opened, guard alerted, and objective changed. Gameplay objects report what happened; they do not know which mission objective cares.

**Acceptance:** event payloads use semantic IDs/data and duplicate/one-frame ownership is explicit.

## 5.7 Event → condition → action mission rules `[ ]`

**Scope:** create a deliberately constrained typed rule system: one triggering event, optional read-only conditions, and queued actions that change mission/world state. Start only with vocabulary required by the first mission. No arbitrary method calls and no general-purpose scripting language.

**Depends:** 5.1–5.6.

**Acceptance:** deterministic matching/condition/action order, explicit once/repeatable behavior, invalid-reference reporting, and no recursive half-updated state during rule execution.

## 5.8 Mission lifecycle: start, exit, completion `[ ]`

**Scope:** establish mission entry, active gameplay, valid exit/completion conditions, and transition to results through the top-level game-flow owner.

**Acceptance:** premature exit is rejected where required and successful completion produces exactly one final mission outcome.

## 5.9 Mission statistics and results snapshot `[ ]`

**Scope:** track the meaningful statistics currently available—initially loot, alerts/detections, objectives, and later extensible kills/knockouts—preferably from the same semantic events used elsewhere.

**Acceptance:** deliberately different playthroughs produce truthful final snapshots without UI maintaining separate state.

## 5.10 Functional objectives and results screens `[ ]`

**Scope:** add an in-mission objectives screen and a simple mission-results screen now. These are functional development UI, not final presentation.

**Acceptance:** opening objectives pauses/takes input according to the screen policy; results display the actual finalized mission state/statistics.

## 5.11 First 5–10 minute graybox mission `[ ]`

**Scope:** build one small mission using only systems that really exist: multiple infiltration routes, light/dark stealth, patrol guards, a door, loot/objective, optional route/action where useful, and an exit. Use stable IDs, objective state, triggers/events/rules, and results rather than a mission-specific gameplay script.

**Acceptance:** start → briefing placeholder/dev entry → mission → objective → exit → results works repeatedly; the mission can be completed through more than one reasonable stealth route and feels like a coherent tiny game.

**Milestone gate:** the project is a complete small stealth game and the mission architecture has been proven before larger feature expansion.

---

# Milestone 6 — Deepen the stealth sandbox through the real mission

Goal: add the environmental and NPC-consequence systems that make a Thief-like sandbox richer, integrating each one into the existing mission instead of building disconnected demos.

## 6.1 Guard-door integration `[ ]`

**Scope:** guards can traverse/use supported doors during patrol, investigation, pursuit, and recovery without navigation/state conflicts.

**Acceptance:** representative patrol/investigation routes through doors remain reliable for both player and guard use.

## 6.2 Physical-object throwing `[ ]`

**Scope:** extend held props with deliberate throw/release behavior.

**Acceptance:** ownership transfers cleanly, throw behavior is physically stable, and player collision remains unaffected after release.

## 6.3 Object-impact noise and audio `[ ]`

**Scope:** physical impacts create appropriate semantic gameplay-noise events plus audible placeholder SFX.

**Depends:** 4.10, 6.2.

**Acceptance:** thrown-object distraction works in the real mission and guard reactions remain explainable.

## 6.4 Containers `[ ]`

**Scope:** reusable openable containers that expose/take contents through the interaction/loot systems.

**Acceptance:** contents cannot be duplicated/lost through repeated open/close/use cycles.

## 6.5 Candles / extinguishable lights `[ ]`

**Scope:** create the first extinguishable-light specialization and feed its state into visible lighting and gameplay exposure.

**Acceptance:** extinguishing produces consistent rendering, exposure, and interaction state.

## 6.6 NPC possessions and pickpocket `[ ]`

**Scope:** give NPCs eligible carried valuables/items and allow stealing them under deliberate proximity/position/state rules.

**Acceptance:** transfer eligibility and ownership are deterministic; manual use against moving/stationary unaware guards is readable and fair.

## 6.7 NPC life-state model `[ ]`

**Scope:** conscious, unconscious, and dead state with explicit AI shutdown, collision, interaction, and later statistics ownership.

**Acceptance:** legal transitions are deterministic and state persists correctly after navigation/AI stops.

## 6.8 Stealth knockout `[ ]`

**Scope:** implement the intended hold-to-ready/release fist stealth knockout flow using 6.7.

**Acceptance:** eligibility/outcome is deterministic; manual positioning and moving-target cases are understandable.

## 6.9 Body physics and carry/put-down `[ ]`

**Scope:** make unconscious/dead bodies coherent world objects and allow carrying/putting them down through the established interaction ownership model.

**Acceptance:** doors, corners, slopes, and hiding spaces do not destabilize player/body collision.

## 6.10 Stealth kill `[ ]`

**Scope:** knife stealth-takedown variant with lethal outcome and semantic/statistics events.

**Acceptance:** lethal/nonlethal outcomes are unmistakable and share common eligibility/state architecture where appropriate.

## 6.11 Body discovery and guard response `[ ]`

**Scope:** guards can perceive relevant bodies and convert discovery into the same evidence/state architecture rather than bespoke AI branches.

**Acceptance:** visible body discovery causes the intended reaction; hidden/occluded bodies do not produce magical knowledge.

## 6.12 Re-integrate the vertical-slice mission `[ ]`

**Scope:** update the existing mission to exercise throwing/distraction, environmental light control, loot/containers, pickpocket, takedowns, and body consequences where they improve the level.

**Acceptance:** new systems are added through reusable interfaces/rules without turning the mission into custom core-code glue.

**Milestone gate:** the core stealth sandbox supports environmental manipulation, valuables, nonlethal/lethal removal, bodies, and guard consequences in one mission.

---

# Milestone 7 — Campaign state, persistence, and campaign screens

Goal: connect missions into a real campaign flow only after one complete mission exists.

## 7.1 Persistence-scope decision `[ ]`

**Scope:** explicitly decide which implemented state survives between missions/process restarts—campaign facts, mission outcomes, usable inventory/tools, health, loot totals, and any other real systems. Do not design save data for features that do not exist yet.

**Acceptance:** every persisted field has one clear owner and reason to survive.

## 7.2 CampaignState and persistent facts `[ ]`

**Scope:** create cross-mission state separate from MissionState, using stable named facts for meaningful outcomes.

**Acceptance:** set/read/branch semantics are deterministic and mission-local facts cannot accidentally leak into campaign state.

## 7.3 Mission progression / routing `[ ]`

**Scope:** represent current/next mission and conditional progression. Add mission selection only if the actual campaign structure needs free selection.

**Acceptance:** progression resolves deterministically from campaign state and invalid destinations are reported clearly.

## 7.4 Campaign-aware mission rules `[ ]`

**Scope:** extend the existing rule vocabulary with only the campaign-state conditions/actions now required, such as reading or setting a campaign fact.

**Acceptance:** no second narrative/campaign scripting path is introduced.

## 7.5 Versioned safe save/load `[ ]`

**Scope:** serialize the decided campaign/persistent state with a versioned format, defined missing/invalid-data behavior, and safe write strategy.

**Acceptance:** automated round trip; manual process restart preserves intended consequences; corrupt/missing data follows the chosen recovery policy.

## 7.6 New Game / Continue / reset flow `[ ]`

**Scope:** evolve the early main menu into functional New Game and Continue behavior using the real persistence layer.

**Acceptance:** New Game creates clean campaign state, Continue loads valid state, and reset/return-to-menu behavior does not retain stale runtime mission data.

## 7.7 Functional mission-briefing screen `[ ]`

**Scope:** add the campaign transition from results/progression into a briefing screen and then into the next mission. Use placeholder media/content initially; final video presentation comes later.

**Acceptance:** results → campaign update → briefing → mission works through the game-flow owner with correct input/mouse state.

## 7.8 Two-mission consequence proof `[ ]`

**Scope:** build a second tiny graybox mission and prove that an action/outcome in Mission A changes Mission B after quitting and restarting the executable.

**Acceptance:** cross-mission difference comes from persistent campaign state, not hand-coded knowledge of the previous scene.

## 7.9 Alignment decision `[ ]`

**Scope:** decide whether `alignment` is a real gameplay/campaign system. If yes, define its semantics and ownership before UI. If no, remove it from the product target rather than building an empty screen.

**Milestone gate:** Vark supports a coherent multi-mission loop with persistence, New Game/Continue, briefing transitions, and at least one proven cross-mission consequence.

---

# Milestone 8 — Usable inventory and first tactical tool

Goal: establish usable inventory separately from valuables, prove it with one stealth-focused tool, and introduce its UI at the same time.

## 8.1 Inventory/item data model `[ ]`

**Scope:** stable item definition, acquisition, quantity, removal, and ownership for usable items. Mission loot/value remains a separate concept.

**Acceptance:** add/remove/quantity behavior is deterministic and duplicate ownership rules are explicit.

## 8.2 Selection/equip/use lifecycle `[ ]`

**Scope:** player can cycle/select a usable item and invoke its supported use behavior without individual items owning raw input.

**Acceptance:** selection remains valid as quantities change and zero-quantity items follow the chosen rule consistently.

## 8.3 Selected-item HUD and functional inventory screen `[ ]`

**Scope:** add a small gameplay HUD element for the current item and an inventory overlay/screen driven by the same inventory data.

**Acceptance:** opening inventory follows pause/input-ownership rules and HUD/screen never maintain duplicate item truth.

## 8.4 Throwable/deployable item foundation `[ ]`

**Scope:** create the shared use/throw/deploy/effect hooks needed by tactical tools, reusing physical/object systems where appropriate.

**Acceptance:** the framework has one concrete user before further abstraction.

## 8.5 Flashbang `[ ]`

**Scope:** implement the first complete tactical inventory tool and relevant guard response.

**Acceptance:** deterministic eligibility/radius/line-of-effect rules where applicable; manual use creates a useful stealth escape/disruption option in the vertical-slice mission.

**Milestone gate:** usable inventory is real, understandable through UI, and proven by one meaningful stealth tool.

---

# Milestone 9 — Health, direct combat, death flow, and combat balance

Goal: add combat after stealth works so combat becomes a consequence-management option rather than the foundation of the game.

## 9.1 Health and damage contract `[ ]`

**Scope:** establish player/NPC health/damage ownership, hit outcomes, and life-state integration where relevant.

**Acceptance:** deterministic damage/clamp/death-or-knockout outcomes and no duplicate damage from one logical hit.

## 9.2 Temporary/finalizable health HUD `[ ]`

**Scope:** expose player health immediately through functional HUD feedback; final art waits for presentation polish.

**Acceptance:** HUD reflects gameplay health state rather than storing its own value.

## 9.3 Death/recovery game-flow `[ ]`

**Scope:** define what happens when the player dies using the actual save/retry policy. Add a functional death screen and valid recovery/return path without inventing an unrelated checkpoint system.

**Depends:** 7.5, 9.1.

**Acceptance:** death takes input ownership correctly and recovery cannot resume stale half-dead mission state.

## 9.4 Basic melee attack foundation `[ ]`

**Scope:** attack input/state, hit validation, attack ownership, and duplicate-hit protection.

**Acceptance:** one attack produces at most the intended hit outcome and misses remain misses.

## 9.5 Ordinary fist combat `[ ]`

**Scope:** direct fist strikes with the intended multi-hit-to-knockout behavior, distinct from stealth knockout.

**Acceptance:** deterministic hit/outcome rules; manual exchange remains readable.

## 9.6 Knife combat `[ ]`

**Scope:** direct lethal knife attack, distinct from stealth kill.

**Acceptance:** lethal outcome/statistics are consistent across combat and stealth paths.

## 9.7 Guard combat behavior `[ ]`

**Scope:** connect alert/pursuit to actual NPC attack behavior, spacing, and recovery without replacing the existing stealth state model.

**Acceptance:** one-on-one combat is coherent and guards do not oscillate between navigation/attack owners.

## 9.8 Block `[ ]`

**Scope:** held block prevents supported attacks according to final combat rules.

**Acceptance:** blockable/non-blockable outcomes are deterministic; feedback is readable.

## 9.9 Parry `[ ]`

**Scope:** timed block produces the designed parry result. Do not freeze subjective timing into regression tests until tuned and accepted.

**Acceptance:** final accepted timing boundaries are automated only after playtesting makes them intentional.

## 9.10 Rebalance the vertical-slice mission `[ ]`

**Scope:** replay the real mission with combat available and adjust encounter/system balance only where needed so stealth remains the preferred core problem-solving language.

**Acceptance:** direct combat works but does not trivially invalidate stealth routes, light, sound, distractions, or guard consequences.

**Milestone gate:** health, death/recovery, fist/knife combat, guard attacks, block, and parry work inside the existing stealth game without becoming its dominant solution.

---

# Milestone 10 — Remaining planned tools and shared effects

Goal: complete the planned item set by extending proven inventory/effect foundations rather than creating one-off scripts.

## 10.1 Healing potion `[ ]`

**Scope:** consume an inventory item and restore player health according to chosen rules.

**Acceptance:** consumption/quantity/health clamp are deterministic and feedback is clear.

## 10.2 Explosion effect foundation `[ ]`

**Scope:** shared spatial damage/noise/effect behavior required by explosive tools.

**Acceptance:** radius/line-of-effect/self-effect rules are deterministic where intended.

## 10.3 Bomb `[ ]`

**Scope:** direct/deployed explosive tool using 10.2.

**Acceptance:** predictable behavior around geometry, player, and NPCs.

## 10.4 Mine placement/trigger foundation and mine `[ ]`

**Scope:** reusable placed-item ownership/arming/trigger behavior, proven with the explosive mine.

**Acceptance:** placement/trigger/cleanup are deterministic and do not duplicate effects.

## 10.5 Gas/status-effect foundation `[ ]`

**Scope:** shared area/status behavior needed by gas tools, integrated with NPC life/state ownership.

**Acceptance:** eligibility/duration/cleanup rules are deterministic where gameplay contracts require them.

## 10.6 Gas bomb and gas mine `[ ]`

**Scope:** implement the direct and placed gas variants using the shared inventory, area/status, and mine foundations.

**Acceptance:** they have a clear tactical role distinct from explosive tools and do not bypass state ownership.

## 10.7 Tool integration pass `[ ]`

**Scope:** exercise all implemented tools in the vertical-slice mission and verify inventory UI, guard reactions, mission statistics/consequences, and audio/debug feedback remain coherent.

**Milestone gate:** the planned tool set expands stealth tactics through common architecture rather than isolated item scripts.

---

# Milestone 11 — Product UX, narrative presentation, audio, and art-production foundations

Goal: finish the player-facing product around systems that already work. Functional UI/feedback already exists from earlier milestones; this milestone stabilizes and presents it as a coherent game.

## 11.1 UI navigation/style framework `[ ]`

**Scope:** unify focus/navigation, screen stacking, transitions, controller/keyboard behavior as relevant, and shared visual conventions without changing the established game-flow ownership.

## 11.2 Final main menu, pause, and settings `[ ]`

**Scope:** finish main-menu and pause UX and implement only settings that actually function, such as audio, mouse sensitivity, display/video, and controls as supported.

**Acceptance:** settings are reachable from appropriate contexts and do not contain dead controls.

## 11.3 Final gameplay HUD `[ ]`

**Scope:** integrate light gem, health, selected item, interaction feedback, and held-object/weapon presentation into one readable HUD.

## 11.4 Objectives, inventory, and statistics screens `[ ]`

**Scope:** replace development UI with coherent production screens driven by the existing objective/inventory/statistics state.

## 11.5 Mission-map contract and screen `[ ]`

**Scope:** decide what a Vark mission map actually is—authored image/data, floors, player/objective markers as appropriate—and define what mission content must provide.

**Acceptance:** at least one real mission supplies and displays its map through the content contract.

## 11.6 Alignment presentation `[ ]`

**Scope:** only if 7.9 retained alignment as a real system. Otherwise this item is removed rather than implemented as empty UI.

## 11.7 Production audio foundation/pass `[ ]`

**Scope:** establish audio buses/categories and replace/extend placeholders for footsteps/movement, object impacts, doors/interactions, guard vocals, combat/tools, ambience, UI, and dialogue/voice where used. Gameplay noise remains separate from audible presentation.

## 11.8 Overhead dialogue and guard-state indicators `[ ]`

**Scope:** typed lines above characters plus suspicion/alert grunts and `?` / `!` feedback driven by actual AI state.

## 11.9 Subtitle and first-person cutscene framework `[ ]`

**Scope:** keep the mission world loaded, take input ownership, preserve first-person POV, show cinematic bars/subtitles, play a content-addressable sequence, and restore gameplay safely.

## 11.10 Final briefing presentation `[ ]`

**Scope:** upgrade the functional briefing screen to the intended pre-mission video/content presentation while preserving established campaign flow.

## 11.11 Character visual/animation contract `[ ]`

**Scope:** separate gameplay actor state from replaceable visual models/animation. Add hooks for movement, guard states, combat, unconscious/dead state, interactions, and first-person held items without animation owning gameplay truth.

## 11.12 2D facial-animation framework `[ ]`

**Scope:** establish the intended character-face presentation in a way compatible with dialogue/cutscenes and low-poly character assets.

## 11.13 Environment/character production asset pipeline `[ ]`

**Scope:** finalize the low-poly, hand-drawn, low-resolution material/model/import conventions and TrenchBroom environment workflow that art/content production will actually use.

**Milestone gate:** the proven gameplay is presented as a coherent product, all required screens/states exist, and artists/writers can supply content without changing core gameplay ownership.

---

# Milestone 12 — Production authoring handoff

Goal: stabilize the systems into a reliable platform for mission developers and plot writers. This milestone consolidates interfaces proven earlier; it is not the first time gameplay entities or mission rules are authored.

## 12.1 Stable mission package contract `[ ]`

**Scope:** define the production structure and ownership of a mission: source map, MissionDefinition, mission-specific narrative data/references, map presentation data, assets, metadata, and transition information.

**Acceptance:** a fresh mission shell can be created without copying undocumented private wiring from the first vertical slice.

## 12.2 Production TrenchBroom gameplay entity set `[ ]`

**Scope:** stabilize the provisional entities accumulated during development—player start, mission exit, guard, patrol point/route, doors/windows, lights/candles, loot/containers, props, triggers, and other proven interactables—with understandable properties and validation.

**Acceptance:** representative gameplay can be placed/configured in a fresh map without editing private Godot scene internals.

## 12.3 Mission-rule/data authoring UX `[ ]`

**Scope:** make objectives, events, conditions, actions, mission facts, and stable references practical to author. Start from typed Godot Resources/Inspector workflows already proven; build custom editor tooling only where real use shows the default workflow is inadequate.

## 12.4 Narrative authoring model `[ ]`

**Scope:** stabilize writer/content-facing data for briefing content, overhead dialogue, subtitles, cutscene sequences, conditional narrative events, and persistent consequences. Reuse the mission/campaign event architecture and stable localization-friendly identifiers rather than a second story scripting system.

**Acceptance:** a writer/content developer can add/change representative narrative content without editing player, guard, mission-state, or presentation-system code.

## 12.5 Consolidated designer debugging tools `[ ]`

**Scope:** provide coherent development inspection for player exposure, gameplay noise, guard state/evidence/target, vision/hearing, patrol/navigation, interaction focus, objectives, mission facts, campaign facts, and event/rule execution.

**Acceptance:** representative authoring failures can be diagnosed without opening core AI/player code.

## 12.6 Content validation and failure reporting `[ ]`

**Scope:** validate duplicate stable IDs, missing actor/objective/dialogue references, invalid mission transitions, malformed patrols, missing required entity properties, and other real content contracts. Prefer actionable errors over silent runtime failure.

**Acceptance:** deliberately broken representative content identifies the offending mission/entity/reference; valid content passes without noisy false positives.

## 12.7 Representative-scale integration/stress mission `[ ]`

**Scope:** build an intentionally utilitarian production-scale mission containing representative guard count, navigation, lights, props/interactables, loot, objectives, triggers/events, UI/narrative hooks, and realistic geometry size.

**Acceptance:** no known systemic correctness issue appears only at representative scale and authoring/debug workflows remain usable.

## 12.8 Performance pass `[ ]`

**Scope:** profile the representative-scale mission and fix demonstrated bottlenecks in perception, navigation, physics, lighting/gameplay exposure, mission state, or presentation. Do not optimize hypothetical problems earlier.

**Acceptance:** measured performance is acceptable for the intended target or remaining blockers are explicitly resolved before handoff.

## 12.9 Template mission `[ ]`

**Scope:** create one clean non-story reference mission demonstrating the supported production grammar and intended combinations of systems.

## 12.10 `docs/CONTENT_AUTHORING.md` `[ ]`

**Scope:** only now document the stable workflows, supported entities/data, mission/narrative authoring, debugging, validation, map/UI content, and extension boundaries. Do not duplicate implementation internals.

## 12.11 External handoff exercise `[ ]`

**Scope:** a developer familiar with Godot/TrenchBroom but not Vark's core code creates a fresh representative mission using supported tools/data, including multiple routes, light/dark stealth, several guards/patrols, doors/interactables, loot, objectives, an optional consequence, narrative event, exit, results/statistics, and a persistent cross-mission consequence. A writer/content developer adds or changes briefing, dialogue, subtitles, cutscene content, conditional narrative events, and persistent narrative consequences without learning player/AI internals.

**Acceptance:** the representative mission/narrative work is completed without modifying core gameplay scripts or relying on undocumented signal/node wiring.

**Milestone gate — systems development complete:** mission developers and plot writers can begin production against stable authoring contracts. New core programming after this point should primarily be bug fixes, proven performance needs, deliberate capabilities requested by content, or explicitly approved design changes—not routine bespoke code required to make every mission work.

---

# Recommended immediate sequence

1. `1.3 Traversal regression protection` — protect the accepted controller without changing its behavior.
2. `1.4 Application bootstrap and game-flow owner`.
3. `1.5 Pause and input-ownership foundation`.
4. `1.6 Collision/query conventions`.
5. `1.7–1.8 TrenchBroom/source and repository hygiene`.
6. `1.9 CI` once the protected movement suite is deterministic.
7. Build Milestone 2's small lit gameplay laboratory.
8. Continue vertically through interaction → NPC/stealth → first real mission rather than returning to movement feature work.
