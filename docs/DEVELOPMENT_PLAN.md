# Vark Development Plan

This is the ordered implementation roadmap for Vark. Repository workflow is defined in `AGENTS.md`; testing conventions and current regression coverage live in `docs/TESTING.md`.

Status: `[ ]` not implemented, `[~]` implemented but awaiting required validation/follow-up, `[x]` validated and accepted.

Each item should be implemented as a bounded step. Do not advance a milestone merely because its individual systems exist: its integration result must also be acceptable in play.

The final systems-development goal is not merely that every mechanic exists. Vark is ready to hand to mission developers and plot writers only when those systems form a stable content-authoring platform that can be used without modifying core gameplay code.

---

# Milestone 1 — Close the player-controller foundation

Goal: finish a reliable traversal foundation, then stop expanding movement and shift the main development focus to stealth.

## 1.1 Core locomotion stability `[x]`

**Scope:** walk/run/sprint, crouch, jump, air control, support/collision response, steps, ledge traversal, and mantle foundation.

**Depends:** none.

**Acceptance:** current movement regression suite remains green; broad movement/traversal manual checks remain acceptable.

## 1.2 Local automated movement regression barrier `[x]`

**Scope:** headless Godot runner, failure aggregation, deterministic physics fixtures, nonzero exit on failure.

**Depends:** 1.1.

**Acceptance:** `tests/movement/run_movement_tests.gd` passes locally and its intentional-failure mode exits nonzero.

## 1.3 Mantle landing-surface validity `[ ]` — recommended next

**Scope:** separate broad ledge geometry detection from semantic mantle landing validity. Reject effectively vertical/non-walkable top surfaces as mantle destinations while preserving legitimate hanging and valid mantles.

**Depends:** 1.1, 1.2.

**Acceptance:**
- automated: almost-vertical/invalid mantle landing is rejected and a normal mantle top succeeds; include crouch-only mantle coverage if stance-aware clearance is touched;
- manual: normal platforms, thin supported geometry, awkward wall/top transitions, and crouch-clearance cases still feel reliable and not overly magnetic.

## 1.4 Traversal regression expansion and determinism `[ ]`

**Scope:** cover important ledge/mantle behaviors that are still protected mainly by manual testing and remove timing-dependent assumptions from the movement suite.

**Depends:** 1.3.

**Acceptance:** valid mantle, invalid mantle, crouch-only mantle where relevant, and reproducible ledge/corner regressions have focused deterministic coverage; repeated full-suite runs are consistently green; broad traversal manual checks remain acceptable.

## 1.5 Continuous movement tests in GitHub Actions `[ ]`

**Scope:** pin the project Godot version in CI and run the same authoritative local test command on pushes to `test` and pull requests.

**Depends:** 1.4.

**Acceptance:** normal suite produces a passing CI check; intentional failure makes CI fail; workflow is stable before any required-check/branch-protection decision.

**Milestone gate:** movement/traversal is trustworthy enough that feature work can shift to stealth without continuing to add traversal abilities for their own sake.

---

# Milestone 2 — Build the smallest complete stealth loop

Goal: make Vark recognizably a stealth game in one controlled developer playground before building a production mission.

Target loop: bright/dark space → guard sees or hears player → suspicion/investigation → alert/search → player breaks contact and hides again.

## 2.1 Player light-exposure model `[ ]`

**Scope:** compute a stable gameplay value representing player exposure to relevant light. Keep rendering and gameplay policy separate enough that AI/UI can consume the value.

**Depends:** Milestone 1 foundation.

**Acceptance:**
- automated: fixed dark/bright cases, defined bounds, and deterministic occlusion/non-contribution rules;
- manual: walking through a simple light/dark room produces transitions that correspond to what the player sees.

## 2.2 Light gem `[ ]`

**Scope:** HUD representation of player exposure using deliberately readable states rather than noisy frame-to-frame flicker.

**Depends:** 2.1.

**Acceptance:**
- automated: exposure-to-display-state mapping;
- manual: the gem communicates useful stealth information without distracting from the world.

## 2.3 Guard state model `[ ]`

**Scope:** explicit guard state ownership before full perception. Minimum useful states: unaware/patrol, suspicious/investigating, alerted, searching, and recovery as required by the final behavior.

**Depends:** basic NPC scene/movement foundation created as part of this item.

**Acceptance:**
- automated: legal transitions, deterministic timers/decay, and rejected impossible transitions where the model enforces them;
- manual: debug-triggered state changes do not cause movement/animation/state ownership to fight itself.

## 2.4 Guard vision `[ ]`

**Scope:** distance, view direction/FOV, world occlusion, target visibility, and integration with player light exposure. Vision supplies evidence to the guard state model rather than owning all AI behavior directly.

**Depends:** 2.1, 2.3.

**Acceptance:**
- automated: visible, outside-FOV, occluded, out-of-range, and exposure-dependent cases;
- manual: front/side/rear approaches, cover, and bright/dark movement feel explainable and predictable.

## 2.5 Player noise model `[ ]`

**Scope:** gameplay noise events emitted by player actions, beginning with locomotion-relevant noise. Event production stays separate from guard hearing policy.

**Depends:** stable player movement.

**Acceptance:**
- automated: representative actions emit expected noise classes/intensity and silent actions do not emit unintended events;
- manual: walking, sprinting, crouching, landing, and any implemented surface differences produce understandable debug evidence.

## 2.6 Guard hearing `[ ]`

**Scope:** guards receive relevant noise using distance/environment rules and convert it into suspicion/investigation evidence.

**Depends:** 2.3, 2.5.

**Acceptance:**
- automated: audible, inaudible, distance/strength threshold, and any deterministic occlusion/material rules actually implemented;
- manual: noise at several distances produces readable reactions useful for distraction gameplay.

## 2.7 Suspicion, investigation, alert, search, and recovery `[ ]`

**Scope:** combine sight/hearing evidence into coherent guard behavior. Support partial suspicion, investigation, full detection, loss of target, search, and eventual recovery where appropriate.

**Depends:** 2.3, 2.4, 2.6.

**Acceptance:**
- automated: key evidence/state transitions and deterministic recovery rules;
- manual: repeated detection/recovery scenarios have understandable pacing and feedback.

## 2.8 Guard navigation and patrol authoring `[ ]`

**Scope:** establish the first stable content-facing way to make guards move through authored spaces. Support patrol routes, route order/loop behavior, waits or pauses where needed, navigation to investigation/search targets, and clear ownership when AI state interrupts or resumes patrol. Keep the data model minimal and based on real stealth-playground needs rather than designing the final mission-authoring tool in advance.

**Depends:** 2.3 and the navigation/movement foundation needed by guard behavior.

**Acceptance:**
- automated: deterministic route progression/state ownership where practical, including interruption/resume rules and invalid/unreachable target handling that has a stable objective contract;
- manual: a guard follows an authored patrol, leaves it to investigate/search, and returns to sensible behavior without route/state conflicts; navigation failures are observable rather than silently freezing the guard.

## 2.9 Stealth playground vertical slice `[ ]`

**Scope:** one small developer scene combining light, cover, guards, authored patrols, sight, hearing, hiding, investigation, search, and recovery. It is a playtest scene, not production art.

**Depends:** 2.1–2.8.

**Acceptance:** focused subsystem tests stay green; repeated infiltration through different routes and deliberate mistakes already feels like a basic Vark stealth encounter.

**Milestone gate:** the stealth playground is understandable, playable, and accepted as the foundation for world interaction, with guards driven by authored patrol/navigation data rather than hard-coded scene behavior.

---

# Milestone 3 — Interaction backbone

Goal: create one reusable interaction model, then add common world interactions as small implementations of it.

## 3.1 Interactable focus and action contract `[ ]`

**Scope:** determine the targeted interactable, expose the available action, and dispatch interaction without individual objects reinventing targeting/input logic.

**Depends:** player/camera foundation.

**Acceptance:**
- automated: focus selection, range rejection, blocked/invalid target rejection where designed, and one-time action dispatch;
- manual: targeting nearby objects at awkward angles/ranges is stable and understandable.

## 3.2 Doors and windows `[ ]`

**Scope:** open/close state, collision behavior, and interaction through 3.1. Add lock/key behavior only when a mission needs it.

**Depends:** 3.1.

**Acceptance:** automated state transitions and any introduced lock rule; manually usable from both sides while moving/crouching and around collision edges.

## 3.3 Containers, loot, and gems `[ ]`

**Scope:** open containers, expose/take contents, collect loot/gems, and update inventory/mission totals as appropriate. Introduce only the minimum inventory data model needed.

**Depends:** 3.1.

**Acceptance:** automated ownership/removal/totals/duplicate prevention; manual looting feedback is clear.

## 3.4 Lights and candles `[ ]`

**Scope:** turn supported lights on/off and extinguish candles through the common interaction model; gameplay-relevant changes feed the light-exposure system.

**Depends:** 2.1, 3.1.

**Acceptance:** automated state/contribution changes where deterministic; manual stealth behavior matches the visible lighting change.

## 3.5 Small pickup and throw `[ ]`

**Scope:** pick up, hold, release/throw a small object and generate appropriate physical/noise consequences.

**Depends:** 2.5, 3.1.

**Acceptance:** automated held/world ownership and representative deterministic noise generation; manual thrown-object distraction works in the stealth playground.

## 3.6 Box carry / throw `[ ]`

**Scope:** heavier movable-object interaction only where its physics/gameplay differs meaningfully from small held objects.

**Depends:** 3.1, preferably 3.5.

**Acceptance:** automated ownership/release constraints; manual carrying/placing/throwing around doors, slopes, and routes does not destabilize player collision.

## 3.7 Pickpocket `[ ]`

**Scope:** steal eligible NPC inventory under valid proximity/position/state conditions.

**Depends:** 3.1, NPC foundation, inventory data.

**Acceptance:** automated eligibility/transfer rules; manual use against moving/stationary unaware NPCs is readable and fair.

**Milestone gate:** the player can manipulate the stealth environment through a coherent interaction language rather than one-off scripts.

---

# Milestone 4 — NPC consequences and stealth takedowns

Goal: let stealth actions create persistent local consequences before implementing full combat.

## 4.1 NPC life-state model `[ ]`

**Scope:** conscious, unconscious, dead, required transitions, and AI shutdown/cleanup ownership.

**Depends:** guard foundation.

**Acceptance:** automated legal transitions/state persistence; manual navigation/collision/interaction remain coherent after state changes.

## 4.2 Stealth knockout `[ ]`

**Scope:** fists ready on hold, knockout strike on release, valid stealth-takedown conditions, unconscious result.

**Depends:** 4.1.

**Acceptance:** automated eligibility/hold-release/outcome; manual positioning, moving-target cases, misses, and feel are acceptable.

## 4.3 Body carry / put down `[ ]`

**Scope:** pick up eligible unconscious/dead bodies, carry them, put them down, and keep physics/collision stable.

**Depends:** 3.1, 4.1.

**Acceptance:** automated ownership/state transitions; manual movement through doors, corners, slopes, and hiding spaces remains stable.

## 4.4 Stealth kill `[ ]`

**Scope:** knife variant of the stealth takedown flow with lethal outcome and mission-stat consequence.

**Depends:** 4.1, preferably shared structure from 4.2.

**Acceptance:** automated eligibility/dead outcome and lethal/nonlethal statistics when available; manual lethal/nonlethal feedback is unmistakable.

**Milestone gate:** the player can remove NPCs lethally or nonlethally and deal with bodies without requiring full combat.

---

# Milestone 5 — One complete micro-mission

Goal: prove the whole game loop with one short 5–10 minute mission before adding many extra mechanics, and prove that mission behavior can be assembled from reusable data/events rather than mission-specific core-code branches.

## 5.1 Objective model `[ ]`

**Scope:** explicit objectives, completion/failure as needed, and optional objectives where useful.

**Depends:** interaction and basic stealth loop.

**Acceptance:** automated objective transitions and duplicate-event safety; manual valid completion orders work where the mission permits them.

## 5.2 Mission start, exit, and completion `[ ]`

**Scope:** mission start/gameplay state, valid exit/completion condition, and transition to results.

**Depends:** 5.1.

**Acceptance:** automated prevention of premature completion and successful completion when requirements are met; manual entry/exit works across relevant objective states.

## 5.3 Mission statistics / end screen `[ ]`

**Scope:** record/display useful first statistics such as loot, kills, knockouts, alerts/detections, and objectives.

**Depends:** 4.x as relevant, 5.2.

**Acceptance:** automated counters/final snapshot; manual deliberately different playthroughs produce truthful results.

## 5.4 Mission event / condition / action model `[ ]`

**Scope:** create a deliberately small data-driven way for authored gameplay events to react to mission state without requiring bespoke core gameplay code for every story beat. Start only with event sources, conditions, and actions required by the micro-mission. Examples may include trigger entered, objective completed, item taken, NPC life state, or campaign fact as conditions/events, and objective updates, fact changes, actor enable/disable, dialogue/cutscene requests, or mission completion as actions. Do not build a general-purpose scripting language.

**Depends:** 5.1–5.3 and the relevant systems being referenced.

**Acceptance:**
- automated: deterministic condition evaluation/action dispatch, one-shot/repeat semantics where configured, invalid-reference handling, and duplicate-event safety;
- manual: at least one optional micro-mission consequence and one presentation/gameplay response are authored through the generic model rather than a mission-specific code branch.

## 5.5 First micro-mission `[ ]`

**Scope:** one deliberately small mission with an infiltration route, guard problem, valuable objective, optional action/consequence, and exit. Use the real mission/objective/event interfaces rather than temporary one-off scripting wherever those interfaces exist.

**Depends:** 2.x, enough of 3.x/4.x, and 5.1–5.4.

**Acceptance:** subsystem/mission-state tests stay green; the mission can be completed several different ways and feels like a coherent short stealth game from start to results; its optional consequence demonstrates the reusable event model.

**Milestone gate:** the project functions as a tiny complete game, not just a collection of systems, and the first real mission logic is assembled from reusable mission-facing contracts.

---

# Milestone 6 — Cross-mission state and campaign structure

Goal: let later missions change because of player actions.

## 6.1 Persistent consequence model `[ ]`

**Scope:** named campaign facts such as NPC alive/dead, important object taken/not taken, optional actions, and other explicit consequences. Use stable content-facing identifiers rather than fragile scene-tree paths for facts intended to survive mission edits.

**Depends:** 5.5.

**Acceptance:** automated set/read and deterministic branch conditions; manual different micro-mission outcomes produce the expected campaign facts.

## 6.2 Save/load `[ ]`

**Scope:** persist campaign facts plus the minimum other state needed by mission structure. In-mission save design is a separate later decision if required.

**Depends:** 6.1.

**Acceptance:** automated round-trip and chosen missing/versioned-data behavior; manual process restart preserves intended consequences.

## 6.3 Briefing / mission selection flow `[ ]`

**Scope:** pre-mission video briefing and transition into a mission; expand to multiple missions only when content exists.

**Depends:** mission framework.

**Acceptance:** deterministic state/selection logic is covered where useful; manually run briefing → mission → results → next step.

**Milestone gate:** campaign flow can carry meaningful player consequences between missions using stable mission/campaign identifiers rather than scene-specific implementation details.

---

# Milestone 7 — Full combat

Goal: add direct combat after stealth works so combat supports rather than defines the game.

## 7.1 Basic melee exchange `[ ]`

**Scope:** fist hit, knife hit, incoming NPC attack, health/damage/reaction foundation.

**Depends:** NPC life state, player health.

**Acceptance:** automated damage/outcome and duplicate-hit/invulnerability rules if present; manual one-on-one combat is readable and coherent.

## 7.2 Block `[ ]`

**Scope:** hold block to prevent supported attacks according to final combat rules.

**Depends:** 7.1.

**Acceptance:** automated blockable/non-blockable outcomes where relevant; manual timing and feedback are clear.

## 7.3 Parry `[ ]`

**Scope:** pressing block shortly before an incoming attack produces the designed parry result.

**Depends:** 7.2.

**Acceptance:** automate the chosen timing-window boundaries only after tuning makes them intentional; manually the parry is learnable and distinct from holding block.

**Milestone gate:** direct combat is functional without becoming the dominant or easiest answer to every stealth problem.

---

# Milestone 8 — Inventory items and tools

Goal: establish one reusable item architecture, then implement tactical tools individually.

## 8.1 Inventory/item architecture `[ ]`

**Scope:** item data, acquisition, selection, quantity/use rules, and selected-item HUD integration.

**Depends:** loot/inventory foundation from Milestone 3 may be extended here.

**Acceptance:** automated add/remove/select/use/quantity rules; manual acquisition and cycling work during ordinary movement.

## 8.2 Healing potion `[ ]`

**Scope:** consume item and restore health according to chosen rules.

**Depends:** 7.1, 8.1.

**Acceptance:** automated consumption/health clamp; manual use at different health values has clear feedback.

## 8.3 Flashbang `[ ]`

**Scope:** thrown/deployed flash effect and affected NPC response.

**Depends:** 8.1, guard state model.

**Acceptance:** deterministic effect eligibility/radius/line-of-effect rules are automated; manual use across representative guard states creates a useful tactical escape/disruption tool.

## 8.4 Bomb and mine `[ ]`

**Scope:** explosive direct-use and placed variants using shared effect/damage foundations.

**Depends:** 8.1, combat/damage.

**Acceptance:** automated placement/trigger/effect rules; manual behavior around geometry, NPCs, and player is predictable.

## 8.5 Gas bomb and gas mine `[ ]`

**Scope:** gas direct-use and placed variants using shared status/area-effect logic.

**Depends:** 8.1, NPC state model.

**Acceptance:** deterministic area/status eligibility/duration rules are automated; manual use has a clear tactical role distinct from explosives.

**Milestone gate:** tools expand stealth tactics through one coherent inventory/effect architecture.

---

# Milestone 9 — Remaining traversal only when level design needs it

Do not build these simply to complete a feature list. Implement them when an actual route or confirmed production requirement needs them. Before final content handoff, explicitly decide which of these abilities are part of the supported authoring palette; any still-deferred ability is out of scope for mission developers until implemented and validated.

## 9.1 Slide `[ ]`

**Scope:** final behavior specified when a real route needs slide traversal.

**Depends:** locomotion/crouch foundation and a level-design need.

**Acceptance:** automate chosen state/collision/velocity invariants; manual route-specific playtest proves the move serves the level.

## 9.2 Ladders `[ ]`

**Scope:** enter, climb, stop, exit top/bottom, and ledge interaction as needed.

**Depends:** a level needing ladders.

**Acceptance:** automated enter/exit/state ownership and representative blocked-exit cases; manual approaches/transitions at both ends are predictable.

## 9.3 Swimming `[ ]`

**Scope:** water entry/exit and swimming movement; breath/underwater systems only if later design requires them.

**Depends:** a level needing water traversal.

**Acceptance:** automated medium transition/core state rules; manual varied water-edge entry/exit is stable and feels appropriate.

---

# Milestone 10 — Presentation systems and production foundations

These may be prototyped earlier when necessary, but full production work follows proof of the core loop. The goal is to make the proven systems presentable and expose the content-facing hooks that Milestone 11 will stabilize for production authors.

## 10.1 Core HUD `[ ]`

Light gem, health, selected inventory item, and first-person held weapon/object presentation.

## 10.2 Objectives/map/inventory/alignment/statistics menus `[ ]`

Implement only data that actually exists; avoid empty speculative menu systems.

## 10.3 Overhead dialogue and guard state indicators `[ ]`

Typed lines over heads, suspicion/alert grunts, and question/exclamation feedback driven by actual AI state. Keep dialogue content separable from the presentation implementation so later writer-facing authoring does not require editing the UI code.

## 10.4 First-person cutscene framework `[ ]`

Block input, preserve first-person POV, show black top/bottom bars, and render subtitles in the lower bar. Cutscene content/sequencing should be invokable through stable content-facing identifiers rather than requiring mission code to manipulate presentation internals directly.

## 10.5 Final environment/character art pipeline `[ ]`

Apply the low-poly, hand-drawn, low-resolution, sun/moon visual direction to production assets and establish the real import/export conventions that content production will use.

**Milestone gate:** presentation supports the proven game and exposes clean hooks for authored dialogue/cutscenes/assets rather than substituting for an unproven core loop.

---

# Milestone 11 — Content-production handoff

Goal: turn the completed gameplay systems into a stable authoring platform for mission developers and plot writers. The project is not considered systems-complete until a person who did not build the core gameplay code can author a representative mission and narrative content without modifying core system scripts.

Do not build this milestone as a speculative editor framework early in development. Its interfaces should be extracted from the systems and micro-mission that already exist.

## 11.1 Stable mission-authoring contract `[ ]`

**Scope:** define and stabilize the content-facing structure of a mission: stable mission ID, player start, objectives, exits, statistics, relevant NPC/content IDs, briefing/results metadata, persistent consequences, and transition targets. Internal implementation may continue to evolve, but authored missions should not depend on fragile scene paths, private nodes, or undocumented signal wiring.

**Depends:** Milestones 5–6 and the core systems that production missions will use.

**Acceptance:**
- automated: stable-ID/reference behavior and deterministic mission-state contracts are covered where practical;
- manual: create a second tiny mission shell from scratch using only supported content-facing interfaces, without copying hidden implementation wiring from the first micro-mission.

## 11.2 TrenchBroom gameplay entity and placement pipeline `[ ]`

**Scope:** expose the gameplay objects mission developers actually need through consistent TrenchBroom/Godot authoring conventions. The supported set should be based on the real production palette and may include player starts, mission exits, doors/windows, lights, loot/containers, NPC spawns, patrol points/routes, triggers, objective-related markers, and other proven interactables. Properties should be understandable and validated rather than requiring scene-tree surgery or knowledge of private gameplay nodes.

**Depends:** 11.1 and the implemented gameplay systems being exposed.

**Acceptance:**
- automated/tooling validation where practical for imported properties and required references;
- manual: a mission developer can place and configure the representative gameplay entities in a fresh map and obtain the intended runtime behavior without editing core gameplay scripts.

## 11.3 Narrative and authored-event interface `[ ]`

**Scope:** stabilize the writer/content-facing representation for briefing content, overhead dialogue, subtitles, first-person cutscene sequences, conditional story events, and persistent narrative consequences. Reuse the mission event/condition/action model rather than creating a second disconnected scripting path. Use stable dialogue/event/fact identifiers suitable for later localization/content editing.

**Depends:** 5.4, Milestone 6, 10.3, and 10.4.

**Acceptance:**
- automated: deterministic event/condition references and missing/invalid content identifiers are covered where practical;
- manual: a writer/content developer can add a dialogue exchange, subtitle/cutscene sequence, and one conditional consequence using supported data/interfaces without editing guard, player, mission-state, or presentation-system code.

## 11.4 Designer debugging and inspection tools `[ ]`

**Scope:** provide development-only inspection that lets content authors answer why gameplay did or did not react. Include the systems that actually need debugging at production scale, such as player light exposure, emitted noise, guard state/evidence/target, vision/hearing information, patrol/navigation target or failure, objective state, mission/campaign facts, and trigger/event activation.

**Depends:** the corresponding systems already exist.

**Acceptance:** a mission developer can diagnose representative failures—guard cannot reach patrol point, player is unexpectedly visible, trigger did not fire, objective/fact has wrong state—using in-game/editor diagnostics without opening the core AI/player implementation.

## 11.5 Content validation and failure reporting `[ ]`

**Scope:** detect common authoring mistakes early and report them clearly. Validate the real content contracts introduced by 11.1–11.3, such as duplicate stable IDs, missing objective/actor/dialogue references, invalid mission transition targets, malformed patrol definitions, unresolved campaign facts where the format requires declaration, and required entity properties. Prefer explicit validation errors over silent runtime failure.

**Depends:** 11.1–11.3.

**Acceptance:** representative deliberately broken content produces actionable validation errors that identify the offending mission/entity/reference; valid content passes without noise.

## 11.6 Representative-scale integration and performance `[ ]`

**Scope:** build an intentionally ugly production-scale integration/stress level containing representative amounts of guards, navigation, lights, interactables, loot, objectives, triggers/events, and mission geometry. Profile the real bottlenecks rather than optimizing hypothetical ones. Verify that perception, navigation, physics, mission state, and debugging tools remain usable at expected production scale.

**Depends:** the core gameplay systems and 11.1–11.5 authoring interfaces.

**Acceptance:**
- automated regression barrier remains green;
- no known systemic correctness failure appears only at representative scale;
- performance is measured and acceptable for the intended target or concrete bottlenecks are fixed before handoff;
- mission-authoring/debug workflows remain responsive enough for normal production work.

## 11.7 Template mission, authoring guide, and handoff exercise `[ ]`

**Scope:** create one clean template/example mission that demonstrates the supported production grammar and, only now that the interfaces are real, create `docs/CONTENT_AUTHORING.md` for mission developers and writers. The guide should document actual stable workflows, supported entities/data, debugging/validation, and extension boundaries; it must not become a duplicate implementation manual.

**Depends:** 11.1–11.6.

**Acceptance:** perform the final handoff exercise with a fresh representative mission. A developer familiar with Godot/TrenchBroom but not Vark's core code must be able to author, using supported tools/data:
- player start and valid mission exit;
- multiple infiltration routes;
- light/dark stealth space;
- multiple guards with authored patrols;
- doors/interactables and loot;
- required and optional objective/consequence behavior;
- dialogue or another narrative event;
- mission results/statistics;
- a persistent fact that can affect later content;
without modifying core gameplay scripts.

A writer/content developer must be able to add or change briefing text/content references, dialogue, subtitles, conditional narrative events, cutscene content supported by the framework, and persistent narrative consequences without needing to understand player locomotion, perception internals, or guard-state implementation.

**Milestone gate — systems development complete:** mission developers and plot writers can begin real production work against stable authoring contracts. New core programming after this point should primarily be bug fixes, deliberate new capabilities requested by content needs, performance work, or explicitly approved design changes—not routine bespoke code required to make each mission function.

---

# Recommended immediate sequence

1. `1.3 Mantle landing-surface validity`
2. `1.4 Traversal regression expansion and determinism`
3. `1.5 Continuous movement tests in GitHub Actions`
4. Move to Milestone 2 instead of adding more traversal features.

The long-term endpoint is Milestone 11: a proven, validated content-authoring platform ready for mission and plot production.