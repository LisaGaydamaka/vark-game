# Vark Development Plan

This is the ordered implementation roadmap for Vark. The purpose is to make development incremental: pick one numbered item, implement only that bounded item, run objective tests, play it, tune or fix it from playtest feedback, then move to the next item.

`GAME_VISION.md` is the design north star. `REGRESSION_TEST_PLAN.md` defines the automated safety net.

## Working method

For normal development, use this loop:

1. Pick the next roadmap item.
2. Ask for that item only, for example: `implement 2.4 upload to gh`.
3. Implementation should include the minimum architecture needed for that item, not speculative systems for distant features.
4. Add or update automated tests for objective behavior when appropriate.
5. Run the relevant automated suite locally.
6. Play the feature in Godot and judge feel, readability, and usefulness.
7. Report what feels wrong in chat. Treat the feedback as a bug, tuning change, missing behavior, or design change as appropriate.
8. Repeat until accepted.
9. Move to the next roadmap item.

Do not bundle neighboring roadmap items unless explicitly requested. A technically passing feature is not complete until the manual playtest criteria are also acceptable.

## Status legend

- `[x]` implemented and locally validated
- `[~]` implemented but still needs planned validation / follow-up
- `[ ]` not implemented

## Global definition of done for an implementation item

An item is done when:

- its stated scope works without requiring unrelated future systems
- relevant existing regression tests still pass
- new objective behavior has automated coverage where practical
- there are no known parser/runtime errors introduced by the item
- the manual playtest checklist for the item is acceptable
- the implementation does not violate `GAME_VISION.md`
- any intentionally changed baseline behavior is reflected in the tests/documentation

---

# Milestone 1 — Close the player-controller foundation

Goal: finish the reliable traversal foundation before shifting the main development focus to stealth. Do not keep expanding movement indefinitely.

## 1.1 Core locomotion stability `[x]`

**Scope:** walk/run/sprint, crouch, jump, air control, stable support, collision response, steps, ledge traversal, mantle foundation.

**Dependencies:** none.

**Automated:** current movement suite protects walk-off support, sprint-jump momentum, normal steps, floating/undercut steps, wall-seam falling, and multi-contact falling.

**Manual:** use `docs/player_movement_regression_checklist.md` after player-controller changes.

**Done when:** current movement baseline remains stable enough to build stealth gameplay on top of it.

## 1.2 Local automated movement regression barrier `[x]`

**Scope:** headless Godot runner, failure aggregation, deterministic physics fixtures, nonzero exit on failure.

**Dependencies:** 1.1.

**Automated:** `tests/movement/run_movement_tests.gd`.

**Manual:** run the suite from the project root and confirm all movement tests pass.

**Done when:** already achieved locally.

## 1.3 Mantle landing-surface validity `[ ]` — recommended next

**Scope:** separate broad ledge geometry detection from semantic mantle landing validity. Reject effectively vertical / non-walkable top surfaces as mantle destinations while preserving legitimate ledge detection and hanging behavior.

**Dependencies:** 1.1, 1.2.

**Automated:** add at minimum a fixture where an almost-vertical candidate top is rejected and a normal mantle top succeeds. Include crouch-only mantle success if the change touches stance-aware clearance.

**Manual:** mantle normal platforms, thin geometry already supported by the controller, awkward wall/top transitions, and crouch-clearance cases. Confirm valid mantles do not become harder or more magnetic.

**Done when:** mantle acceptance is based on meaningful landing semantics rather than an arbitrary tiny upward-normal threshold, with regressions covered.

## 1.4 Traversal regression expansion and determinism `[ ]`

**Scope:** add focused tests for important ledge/mantle behavior that is currently protected mainly by manual testing. Run the suite repeatedly and remove timing-dependent assumptions.

**Dependencies:** 1.3.

**Automated:** valid mantle, invalid mantle, crouch-only mantle, and any ledge/corner bug that has previously been reproducible. Run the full movement suite repeatedly without intermittent failures.

**Manual:** run the existing movement regression checklist once after test stabilization.

**Done when:** traversal tests are deterministic and repeated local runs are consistently green.

## 1.5 Continuous movement tests in GitHub Actions `[ ]`

**Scope:** pin the project’s Godot version in CI and run the same headless movement suite on pushes to `test` and pull requests.

**Dependencies:** 1.4.

**Automated:** the CI job itself must fail when the local suite would fail.

**Manual:** intentionally trigger the runner’s failure mode once while validating the workflow, then restore normal behavior.

**Done when:** the repository automatically reports pass/fail for the movement suite. Branch protection can be considered only after the check is stable.

---

# Milestone 2 — Build the smallest complete stealth loop

Goal: make Vark recognizably a stealth game as early as possible. Use one ugly, controlled stealth playground rather than a real mission.

Target loop: player moves through bright/dark space → guard sees or hears player → suspicion changes → guard investigates / alerts / searches → player can break contact and hide again.

## 2.1 Player light-exposure model `[ ]`

**Scope:** compute a stable gameplay value representing how exposed the player is to relevant light. Keep rendering and gameplay policy separate enough that the value can be tested and consumed by AI/UI.

**Dependencies:** Milestone 1 foundation.

**Automated:** fixed dark/bright test cases, bounds of exposure value, occluded/non-contributing light cases where deterministic.

**Manual:** walk through a simple light/dark test room and verify transitions correspond to what the player sees.

**Done when:** exposure is stable, understandable, and suitable as input for guard vision and the light gem.

## 2.2 Light gem `[ ]`

**Scope:** HUD representation of player light exposure with deliberately coarse, readable states rather than noisy frame-to-frame flicker.

**Dependencies:** 2.1.

**Automated:** exposure-to-display-state mapping.

**Manual:** move through the stealth playground and verify the gem communicates useful stealth information without distracting from the world.

**Done when:** the player can use the light gem to make meaningful hiding decisions.

## 2.3 Guard state model `[ ]`

**Scope:** establish explicit guard states and transition ownership before adding full perception. Minimum useful states: unaware/patrol, suspicious/investigating, alerted, searching, and recovery as needed by the final behavior.

**Dependencies:** none beyond basic NPC scene/movement foundation created as part of this item.

**Automated:** legal state transitions, timers/decay where deterministic, no impossible direct transitions unless explicitly designed.

**Manual:** use debug triggers in a test room to step through states and confirm animation/movement hooks do not fight state ownership.

**Done when:** perception systems can report evidence to a clear state machine rather than directly scripting guard behavior ad hoc.

## 2.4 Guard vision `[ ]`

**Scope:** distance, view direction / field of view, world occlusion, target visibility, and integration with player light exposure. Vision should provide evidence to the guard state model rather than instantly owning all AI behavior.

**Dependencies:** 2.1, 2.3.

**Automated:** visible target, outside-FOV target, occluded target, out-of-range target, and exposure-dependent detection progression.

**Manual:** approach a guard from front/side/behind, use cover, move between dark and bright areas, and verify detection feels explainable rather than arbitrary.

**Done when:** guard sight is predictable enough that the player can intentionally exploit darkness, cover, distance, and facing.

## 2.5 Player noise model `[ ]`

**Scope:** define gameplay noise events emitted by player actions. Start with locomotion-relevant noise; keep event production separate from guard hearing policy.

**Dependencies:** stable player movement.

**Automated:** representative actions emit the expected noise class/intensity and silent actions do not emit unintended events.

**Manual:** inspect/debug noise while walking, running/sprinting, crouching, landing, and interacting with representative surfaces if surface differences are introduced.

**Done when:** player actions produce consistent, inspectable sound evidence for AI.

## 2.6 Guard hearing `[ ]`

**Scope:** guards receive relevant noise events using distance/environment rules and convert them into suspicion/investigation evidence.

**Dependencies:** 2.3, 2.5.

**Automated:** audible in-range event, inaudible event, distance falloff/threshold, and any deterministic occlusion/material rule that is actually part of the design.

**Manual:** create noise behind/in front of a guard at several distances and confirm reactions are readable and useful for distraction gameplay.

**Done when:** hearing complements vision and can drive investigation without feeling like omniscience.

## 2.7 Suspicion, investigation, alert, search, and recovery `[ ]`

**Scope:** combine sight/hearing evidence into coherent guard behavior. The player should be able to cause partial suspicion, trigger investigation, become fully detected, break line of sight, and eventually escape a search when appropriate.

**Dependencies:** 2.3, 2.4, 2.6.

**Automated:** key state/evidence transitions and decay/recovery rules.

**Manual:** play repeated detection/recovery scenarios and tune pacing from feedback; verify state indicators and audio cues communicate what the guard believes.

**Done when:** one guard can support a complete stealth encounter rather than binary seen/not-seen behavior.

## 2.8 Stealth playground vertical slice `[ ]`

**Scope:** one small developer scene combining light, cover, one or more guards, patrol, sight, hearing, hiding, and search. This is a playtest scene, not production level art.

**Dependencies:** 2.1–2.7.

**Automated:** no new monolithic scene test required; rely on focused subsystem tests.

**Manual:** repeatedly infiltrate the room using different routes and deliberate mistakes. Evaluate whether information and guard behavior are understandable.

**Done when:** Vark already feels like a basic stealth game in an ugly test room.

---

# Milestone 3 — Interaction backbone

Goal: create one reusable interaction model, then add common world interactions as small implementations of it.

## 3.1 Interactable focus and action contract `[ ]`

**Scope:** determine what the player is targeting, expose available interaction, perform the action, and keep interaction ownership independent from individual object types.

**Dependencies:** player/camera foundation.

**Automated:** focus selection, out-of-range rejection, blocked target rejection where applicable, and action dispatch.

**Manual:** target nearby objects at awkward angles/ranges and verify interaction selection is stable and understandable.

**Done when:** new interactables do not need to reinvent player targeting/input logic.

## 3.2 Doors and windows `[ ]`

**Scope:** open/close state, blocked movement behavior as needed, and interaction through 3.1. Lock/key behavior should be added only when a mission requires it.

**Dependencies:** 3.1.

**Automated:** state transitions and any lock rule introduced.

**Manual:** interact from both sides, while moving/crouching, and around collision edges.

**Done when:** doors/windows are reliable stealth-space elements rather than scripted props.

## 3.3 Containers, loot, and gems `[ ]`

**Scope:** open container, expose/take contents, collect loot/gems, update inventory/mission totals as appropriate.

**Dependencies:** 3.1; minimal inventory data model may be introduced here.

**Automated:** pickup ownership, removal from world, totals, duplicate-prevention.

**Manual:** loot several objects/containers and verify feedback is clear.

**Done when:** stealing objects can become a mission objective/statistic.

## 3.4 Lights and candles `[ ]`

**Scope:** turn supported lights on/off and extinguish candles through the common interaction model; changes must feed the gameplay light-exposure system where relevant.

**Dependencies:** 2.1, 3.1.

**Automated:** state change and resulting gameplay-light contribution where deterministic.

**Manual:** alter lighting while hiding near guards and verify the stealth result matches visible changes.

**Done when:** manipulating light is a real stealth tool.

## 3.5 Small pickup and throw `[ ]`

**Scope:** pick up a small object, hold it, throw it, and generate appropriate physical/noise consequences.

**Dependencies:** 2.5, 3.1.

**Automated:** held/world state transitions and noise event generation on representative impacts if deterministic.

**Manual:** use thrown objects to distract a guard in the stealth playground.

**Done when:** small objects form a usable distraction loop.

## 3.6 Box carry / throw `[ ]`

**Scope:** heavier movable-object interaction distinct from small held items only where physics/gameplay requires it.

**Dependencies:** 3.1, preferably 3.5.

**Automated:** ownership/release state and any deterministic constraints.

**Manual:** carry, place, throw, block routes, and verify player collision remains stable.

**Done when:** boxes can be intentionally manipulated without destabilizing locomotion.

## 3.7 Pickpocket `[ ]`

**Scope:** steal eligible inventory from an NPC under valid proximity/position/state conditions.

**Dependencies:** 3.1, NPC foundation, inventory data.

**Automated:** eligibility and transfer rules.

**Manual:** approach moving/stationary unaware NPCs and verify the interaction is readable and fair.

**Done when:** pickpocketing is a stealth action, not a generic front-facing loot prompt.

---

# Milestone 4 — NPC consequences and stealth takedowns

Goal: let stealth actions create persistent local consequences before implementing full combat.

## 4.1 NPC life-state model `[ ]`

**Scope:** conscious, unconscious, dead, plus required transitions and AI shutdown/cleanup rules.

**Dependencies:** guard foundation.

**Automated:** legal transitions and state persistence in-session.

**Manual:** transition guards between states and verify navigation/collision/interaction remain coherent.

**Done when:** takedowns and bodies can rely on explicit state rather than destroying/replacing NPCs ad hoc.

## 4.2 Stealth knockout `[ ]`

**Scope:** fists ready on hold, knockout strike on release, valid stealth-takedown conditions, unconscious result.

**Dependencies:** 4.1.

**Automated:** eligibility, hold/release action semantics, unconscious outcome.

**Manual:** approach from intended positions, mistime attempts, test moving guards, and tune feel.

**Done when:** nonlethal stealth removal is reliable and readable.

## 4.3 Body carry / put down `[ ]`

**Scope:** pick up eligible unconscious/dead bodies, carry them, put them down, and keep physics/collision stable.

**Dependencies:** 3.1, 4.1.

**Automated:** body ownership/state transitions.

**Manual:** move bodies through doors, around corners, onto slopes, and into hiding places.

**Done when:** hiding the consequence of a takedown becomes valid gameplay.

## 4.4 Stealth kill `[ ]`

**Scope:** knife variant of the stealth takedown flow with lethal outcome and mission-stat consequence.

**Dependencies:** 4.1, preferably 4.2 for shared attack structure.

**Automated:** eligibility and dead outcome; lethal/nonlethal stats once available.

**Manual:** compare positioning/feedback with knockout and ensure the distinction is always clear.

**Done when:** lethal choice is mechanically clear and recordable as a consequence.

---

# Milestone 5 — One complete micro-mission

Goal: prove the whole game loop with a short 5–10 minute mission before adding lots of extra mechanics.

## 5.1 Objective model `[ ]`

**Scope:** explicit objectives, completion/failure state as needed, optional objectives where useful.

**Dependencies:** interaction and basic stealth loop.

**Automated:** objective state transitions and duplicate-event safety.

**Manual:** complete objectives in different valid orders if the mission permits it.

**Done when:** mission progress is data-driven enough to support a real level.

## 5.2 Mission start, exit, and completion `[ ]`

**Scope:** start state, gameplay state, valid exit/completion condition, transition to results.

**Dependencies:** 5.1.

**Automated:** cannot complete before requirements; can complete when requirements are satisfied.

**Manual:** enter/exit under several objective states.

**Done when:** one mission has a full playable beginning and ending.

## 5.3 Mission statistics / end screen `[ ]`

**Scope:** record and display the first useful statistics: loot, kills, knockouts, detection/alerts, objectives, plus other metrics only when meaningful.

**Dependencies:** 4.x as relevant, 5.2.

**Automated:** statistic counters and final snapshot.

**Manual:** intentionally produce different mission outcomes and verify the results screen tells the truth.

**Done when:** end-of-mission behavior can communicate how the player acted.

## 5.4 First micro-mission `[ ]`

**Scope:** build one deliberately small mission using existing systems. Include at least an infiltration route, guard problem, valuable objective, optional action/consequence, and exit.

**Dependencies:** 2.x, enough of 3.x/4.x, 5.1–5.3.

**Automated:** rely primarily on subsystem tests; add mission-state tests for objective/stat logic.

**Manual:** complete the mission several different ways. Record feel feedback in chat rather than a repository playtest-notes document.

**Done when:** the game can be played as a coherent short stealth experience from start to results screen.

---

# Milestone 6 — Cross-mission state and campaign structure

Goal: support the design principle that later missions can change because of player actions.

## 6.1 Persistent consequence model `[ ]`

**Scope:** named campaign facts such as NPC alive/dead, important object taken/not taken, optional action completed, and other explicit consequences.

**Dependencies:** 5.4.

**Automated:** set/read facts, serialize/deserialize once persistence exists, and deterministic branch conditions.

**Manual:** finish the micro-mission with different outcomes and inspect the resulting campaign state.

**Done when:** later content can query player actions without hard-coding previous scene internals.

## 6.2 Save/load `[ ]`

**Scope:** persist campaign facts plus the minimum other state needed by the mission structure. In-mission save design should be decided separately if required.

**Dependencies:** 6.1.

**Automated:** round-trip save/load and missing/versioned data behavior as the format evolves.

**Manual:** restart the game and verify the next mission receives the intended prior consequences.

**Done when:** consequences survive process restarts reliably.

## 6.3 Briefing / mission selection flow `[ ]`

**Scope:** pre-mission video briefing and transition into a mission. Expand to multiple missions only when content exists.

**Dependencies:** mission framework.

**Automated:** state/selection logic where useful.

**Manual:** run the entire briefing → mission → results → next-step flow.

**Done when:** campaign structure exists around the gameplay scenes.

---

# Milestone 7 — Full combat

Goal: add direct combat after stealth already works, so combat supports rather than defines the game.

## 7.1 Basic melee exchange `[ ]`

**Scope:** fist hit, knife hit, incoming NPC attack, health/damage/reaction foundation.

**Dependencies:** NPC life state, player health.

**Automated:** damage/outcome rules and invulnerability/duplicate-hit rules if present.

**Manual:** fight one NPC repeatedly and tune timing/readability.

**Done when:** direct combat has a coherent minimal loop.

## 7.2 Block `[ ]`

**Scope:** hold block to prevent supported attacks according to final combat rules.

**Dependencies:** 7.1.

**Automated:** blockable vs non-blockable outcomes if such distinction exists.

**Manual:** test timing and feedback against representative attacks.

**Done when:** holding block behaves consistently and communicates success/failure.

## 7.3 Parry `[ ]`

**Scope:** pressing block shortly before an incoming attack produces the designed parry result.

**Dependencies:** 7.2.

**Automated:** timing-window boundary behavior using deterministic combat events.

**Manual:** tune the window from playtest feel; do not encode subjective timing as a test until the chosen value is intentional.

**Done when:** parry is learnable and distinct from holding block.

---

# Milestone 8 — Inventory items and tools

Goal: establish one reusable item architecture, then implement tactical tools individually.

## 8.1 Inventory/item architecture `[ ]`

**Scope:** item data, acquisition, selection, quantity/use rules, HUD-selected-item integration.

**Dependencies:** loot/inventory foundation from Milestone 3 may be extended here.

**Automated:** add/remove/select/use state and quantity rules.

**Manual:** acquire and cycle representative items during normal movement.

**Done when:** new tools do not each implement their own inventory system.

## 8.2 Healing potion `[ ]`

**Scope:** consume item and restore health according to chosen rules.

**Dependencies:** 7.1, 8.1.

**Automated:** consumption and health clamp.

**Manual:** use at different health values and verify feedback.

**Done when:** first consumable validates the item architecture.

## 8.3 Flashbang `[ ]`

**Scope:** thrown/deployed flash effect and affected NPC response.

**Dependencies:** 8.1, guard state model.

**Automated:** effect eligibility/radius/line-of-effect rules that are deterministic.

**Manual:** use during unaware, suspicious, and alerted guard states.

**Done when:** flashbang creates a useful stealth/combat escape opportunity.

## 8.4 Bomb and mine `[ ]`

**Scope:** explosive direct-use and placed variants using shared effect/damage foundations.

**Dependencies:** 8.1, combat/damage.

**Automated:** placement/trigger/effect rules.

**Manual:** test around geometry, NPCs, and the player.

**Done when:** explosive tools are predictable and do not require separate ad hoc systems.

## 8.5 Gas bomb and gas mine `[ ]`

**Scope:** gas direct-use and placed variants using shared status/area-effect logic.

**Dependencies:** 8.1, NPC state model.

**Automated:** area/status eligibility and duration rules where deterministic.

**Manual:** test against representative guard states and spaces.

**Done when:** gas tools have a clear tactical role distinct from explosives.

---

# Milestone 9 — Remaining traversal only when level design needs it

Do not build these just to complete a feature checklist. Introduce them when a real level route requires them.

## 9.1 Slide `[ ]`

**Scope:** final design to be specified when a level needs slide traversal.

**Dependencies:** current locomotion/crouch foundation.

**Automated:** state transition, collision/clearance, velocity invariants chosen by the design.

**Manual:** route-specific feel testing.

**Done when:** slide enables a real level-design purpose and remains stable around collision geometry.

## 9.2 Ladders `[ ]`

**Scope:** enter, climb, stop, exit top/bottom, and interaction with ledges as needed.

**Dependencies:** level needing ladders.

**Automated:** enter/exit/state ownership and representative blocked-exit cases.

**Manual:** climb from multiple approaches and transition at both ends.

**Done when:** ladders are predictable traversal rather than special-case teleporting.

## 9.3 Swimming `[ ]`

**Scope:** water entry/exit and swimming movement; breath/underwater systems only if the design later requires them.

**Dependencies:** level needing water traversal.

**Automated:** medium transition and core movement-state rules.

**Manual:** enter/exit water around varied edges and tune feel.

**Done when:** swimming supports a real mission route without destabilizing ordinary locomotion.

---

# Milestone 10 — Presentation systems and content production

These can be prototyped earlier when necessary, but full production work should follow proof of the core loop.

## 10.1 Core HUD `[ ]`

Light gem, health, selected inventory item, and first-person held weapon/object presentation.

## 10.2 Objectives/map/inventory/alignment/statistics menus `[ ]`

Implement only the data that exists; avoid empty speculative menu systems.

## 10.3 Overhead dialogue and guard state indicators `[ ]`

Typed lines over heads, suspicion/alert grunts, and question/exclamation feedback integrated with actual AI state.

## 10.4 First-person cutscene framework `[ ]`

Block input, preserve first-person POV, show black top/bottom bars, and render subtitles in the lower bar.

## 10.5 Final environment/character art pipeline `[ ]`

Apply the low-poly, hand-drawn, low-resolution, sun/moon visual direction to production assets and missions.

---

# Planning rules for future additions

When a new desired mechanic is proposed:

1. Decide which existing milestone it serves.
2. Prefer inserting it after its dependencies rather than appending it randomly.
3. Define observable behavior before implementation.
4. Decide which parts are objective/testable and which parts require playtest judgment.
5. Avoid designing speculative architecture for more than the current item plus clear immediate dependencies.
6. If a feature is removed from the game vision, remove it from this roadmap rather than leaving a dormant implementation task.

# Recommended immediate next item

`1.3 Mantle landing-surface validity`, followed by `1.4 Traversal regression expansion and determinism`, then `1.5 Continuous movement tests in GitHub Actions`.

After that, shift the main development focus to Milestone 2 rather than adding more traversal features.
