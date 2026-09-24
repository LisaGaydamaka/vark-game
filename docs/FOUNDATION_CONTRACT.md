# Vark Foundation Contract

This document defines the small set of cross-cutting invariants that must remain true while Vark's gameplay systems evolve.

It is intentionally not a framework specification. It exists to prevent expensive rewrites caused by lifecycle, identity, persistence, event, input, or actor assumptions becoming embedded too early.

`GAME_VISION.md` remains authoritative for player-facing product behavior. `DEVELOPMENT_PLAN.md` remains authoritative for roadmap ordering and feature scope. This document is authoritative for the cross-cutting foundation rules below.

The governing principle is:

> **Discover risk early; generalize architecture late.**

Do not introduce a reusable abstraction merely because a future system might need it. Introduce the smallest semantic contract only when multiple real systems need the same boundary.

---

# 1. World ownership and lifetime

A mission world has explicit application-owned lifetime and scope.

The minimum conceptual lifecycle is:

```text
EMPTY
→ BUILDING
→ RESTORING when loading a save, otherwise READY
→ PLAYING
→ TEARING_DOWN
→ EMPTY
```

Exact names may change. The invariants may not.

## Required invariants

- A world may be instantiated and reconciled without normal gameplay consequences firing.
- AI, rules, perception, objectives, gameplay sounds, timers, and other gameplay consequences are enabled only when the application permits them.
- Registries, event queues, timers, deferred work, async work, and world-owned references belong to one world instance/scope.
- Mission restart, quickload, mission exit, and application transition must stop the previous world's gameplay before a replacement becomes authoritative.
- Stale work from an old world must not affect a new world.
- If generation/session tokens are needed to reject stale deferred work, keep them local to world ownership rather than inventing a global framework.
- Shared authored/configuration `Resource` objects are configuration, not storage for mutable mission-world state. Mutable runtime state belongs to a world/session-owned gameplay owner unless a resource is explicitly duplicated/instantiated as session-owned runtime state.
- Application/autoload objects must not silently become storage for mission-local mutable state merely because they outlive scene changes.

A system is not lifecycle-safe merely because `_ready()` succeeds.

## Quickload replacement rule

A quickload is an application-owned world replacement, not ordinary gameplay running two authoritative worlds at once.

The contract requires transactional correctness, not one mandatory physical topology for restoration. When loading from an active world:

```text
load request
→ stop/freeze ordinary gameplay and gameplay input in the current world
→ validate save header/data as far as possible before destructive transition
→ restore a replacement while ordinary gameplay consequences remain disabled
→ apply/reconcile/validate restored semantic state
→ on success: make the restored world authoritative, then enable gameplay
→ on failure: tear down partial restore and follow one application-owned recovery path
```

The implementation may keep a frozen old world while constructing an isolated non-playing candidate **if that is simple and safe**, or it may tear the old world down after prevalidation and construct the restored world as the sole mission world. Do not build a general multi-world isolation framework merely to preserve a frozen old world after deep restore failure.

If old and replacement worlds overlap in memory, their registries, event queues, timers, deferred work, mutable runtime resources, and other world-scoped services must remain isolated until promotion. They must never both behave as authoritative `PLAYING` worlds.

A failed restore may not leak registrations, events, timers, callbacks, shared mutable resource state, or other work into the current/next world.

Top-level load, restart, mission transition, and exit operations are application-owned and serialized as exclusive world-transition operations rather than competing subsystem actions.

A pending world-bound operation never silently retargets to a replacement world. In particular, a save request is bound to the `WorldSession` that received it: it either captures that same session at an allowed stable boundary before the session stops, or it is cancelled. Once a detached snapshot has been captured, its file write may finish after the source world has been torn down because the write no longer reads live world state.

---

# 2. Input ownership

Raw input has separate application, look, and world-gameplay responsibilities.

Conceptually:

```text
Godot Input
→ application input boundary
    → application/UI input
    → look input
    → gameplay intent frame
        → locomotion
        → interaction
        → combat
        → inventory actions as needed
```

Gameplay objects must not independently decide whether gameplay input is globally permitted.

The strict one-frame-per-tick rule applies to **world gameplay intent**, not to every form of input. One gameplay intent frame belongs to one gameplay simulation tick. Continuous gameplay state such as movement direction or `block_held` may remain true across frames while physically held and permitted. Edge intent such as `interact_pressed`, `attack_pressed`, or `attack_released` exists for that gameplay frame only.

Look input may retain the existing event-driven cadence where required to preserve accepted look response/feel. The player view pose produced by that input is input-owned state and may update at that accepted cadence; world gameplay systems sample the current pose during the controlled simulation step, and a stable-boundary operation such as save capture may synchronously capture the current player view pose with the rest of player state. Preserving this accepted view cadence is not permission for arbitrary world/gameplay consequences to mutate outside the controlled gameplay pass.

Menus/UI may likewise process application input independently of whether the mission world is currently simulating. Application ownership still decides whether look or gameplay domains are currently permitted.

When a gameplay-intent domain becomes disabled because of pause, UI ownership, a sequence, teardown, or world replacement, transient edge intent for that domain is cleared rather than stored and replayed later. Any incomplete gesture whose completion depends on a future edge in that disabled domain is cancelled; resuming requires a fresh initiating press. This prevents hold/release interactions such as charged attacks from becoming stuck or firing from an edge that occurred while the domain was inactive.

Do not force every future action into one ever-growing locomotion command object.

Accepted movement/look/traversal behavior remains unchanged by this refactor.

---

# 3. Gameplay-event semantics and stable simulation boundary

Vark uses semantic gameplay facts rather than private implementation signals for cross-system consequences.

Before mission scripting depends on the event path, the implementation must define and test these semantics:

- dispatch timing;
- deterministic ordering for a given emitted sequence;
- nested/re-entrant emission behavior;
- world ownership/scope;
- whether dispatch is permitted in each world lifecycle state.

The simple default model is preferred unless real integration disproves it:

```text
system emits semantic event
→ event is queued for the current world
→ queue is processed FIFO at a controlled gameplay point
→ events emitted while processing append to the queue
→ normal gameplay dispatch is disabled during BUILDING, RESTORING, and TEARING_DOWN
```

FIFO defines handling order **after emission order exists**. It does not promise that unrelated physics contacts, engine callbacks, or other discoveries are globally ordered unless gameplay explicitly defines a semantic tie-breaker for that case.

Event/consequence handlers participating in the current drain finish synchronously. They may enqueue more semantic work, but they must not suspend/`await` inside the current drain and later resume as if they were still part of that completed semantic step.

Before author-facing rules depend on event cascades, add a development-only runaway-event/cascade guard that reports the trace and fails loudly instead of allowing an accidental self-sustaining semantic loop to hang a gameplay tick. The guard is diagnostic, not gameplay design.

Phase 7.1 exposes this proven dispatcher to mission authors through one world-scoped `VarkMissionEventBus` owned by the current `WorldSession`. It is only a narrow wrapper over the same queue/handlers: authors may subscribe synchronously, emit detached semantic facts, inspect a bounded detached recent trace, and query a useful vocabulary of already-proven event names. Mission-defined event names remain allowed. The wrapper does not expose private subsystem signals, arbitrary mutable Nodes, a second scheduler, or an alternate consequence path. Retained bus references are invalidated at teardown and cannot target a replacement world.

The recent trace is diagnostic state, not gameplay truth and not save state. It records enough detached information to identify sequence/name/payload/session/handler count and the controlled consequence pass that processed an event, including recent events leading into a guarded failure. Trace storage is bounded and reset with world lifetime.

## Controlled semantic mutation

Durable world consequences and simulation-owned semantic state become authoritative only through the controlled gameplay step/consequence pass.

Engine/runtime callbacks that occur outside that controlled pass—such as arbitrary signal callbacks, `Timer.timeout`, `call_deferred()`, async continuations, animation callbacks, or `_process()` work—must not independently commit world gameplay truth in a way that can race the stable boundary. They may update transient presentation/input-owned view state or enqueue/record semantic work to be consumed by the next controlled gameplay step.

Supported mission-script mutation APIs must preserve the same boundary. Read/query APIs may inspect supported semantic state, but a command requested from `_process()`, a signal callback, an async continuation, or another out-of-pass context queues/records semantic work for a controlled gameplay pass rather than mutating private gameplay Nodes immediately. Event payloads and public APIs should prefer stable semantic IDs and detached typed values over arbitrary mutable Node references.

Do not build a general scheduler to enforce this. Keep the rule semantic: presentation/input sampling may be asynchronous; durable world gameplay truth has one controlled mutation boundary.

## Gameplay time

Gameplay durations advance from world simulation time, not wall-clock time.

World simulation time advances only while the application permits that world to simulate. Pausing the ordinary mission world, freezing it for replacement, loading, or spending real-world time outside gameplay does not silently advance guard searches, stagger, mechanisms, mine arming, delayed mission actions, or similar gameplay durations.

When a duration must survive save/load, persist the meaningful semantic progress/remaining duration needed by its owner. Do not serialize engine `Timer` objects, coroutine stacks, signal waits, or wall-clock deadlines as gameplay truth.

## Resolved decisions and randomness

Randomness is allowed where gameplay calls for variation, but restore must not reroll decisions that were already part of gameplay truth when the save was captured.

Once a random choice becomes authoritative state—for example a chosen search point, route variation, or other resolved behavior—save the resolved result or enough semantic state to reconstruct that same result. Future choices that had not yet occurred at the captured boundary may be randomized normally after restore. Deterministic tests may inject a fixed choice/RNG source where useful; Vark does not require a universal replay/RNG framework.

## Single authoritative state owner

Every semantic fact has one authoritative owner.

Examples:

- a door owns its open/closed/lock state;
- an actor owns life/awareness state;
- possession/inventory owns item possession;
- the objective system owns objective state;
- mission-run statistics own run counters;
- mission facts own genuinely mission-defined variables;
- campaign state, once introduced, owns campaign-persistent facts.

Mission facts/rules may query or react to system-owned state, but should not create generic mirrors of state already authoritatively owned elsewhere unless a mission deliberately needs a separate latched/derived fact with distinct meaning. Before a real `CampaignState` exists, mission facts must not quietly become a second temporary owner for campaign-persistent truth.

Phase 7.2 makes that owner explicit: `MissionDefinition` declares each mission fact by key, supported primitive type, default, and scope. The only pre-campaign scopes are `mission` and `runtime`. Mission scope is detached/saveable current-mission truth; runtime scope is current-world working state that resets from its declaration on replacement/restore and is not serialized. Unknown keys, wrong types, duplicate declarations, and any attempted campaign scope fail closed. Durable fact mutation enters through the existing semantic consequence queue; direct author callbacks do not bypass the controlled mutation boundary.

Phase 7.3 likewise keeps objective truth in one objective owner rather than mirroring it into mission facts. Declared objectives own their own inactive/active/complete/failed state plus optional/required meaning. Dynamic objective behavior in this phase is activation of an already-declared inactive objective, not runtime creation of a second ad-hoc state owner. Required-objective completion derives exit gating; optional state does not. Objective transitions enter through the same controlled semantic consequence path and publish detached state-change facts for later rules/scripts.

The canonical semantic simulation boundary is conceptually:

```text
consume one gameplay intent frame
→ perform the controlled gameplay/physics step
→ enqueue semantic gameplay facts
→ drain the current semantic event/consequence pass deterministically
→ reach STABLE GAMEPLAY BOUNDARY
```

A stable gameplay boundary means the durable semantic consequences belonging to that completed step have been processed according to the event contract and no uncontrolled callback is allowed to mutate world gameplay truth between that boundary and a boundary-owned operation such as save capture.

Save snapshot capture and other operations that require one coherent instant occur only at this boundary. Input-owned view pose that intentionally updates at event cadence is sampled synchronously as part of the boundary-owned capture rather than being treated as an uncontrolled world consequence.

This does not require a general scheduler or new gameplay framework. It is a timing/ownership rule so saves, events, rules, and later combat cannot disagree about which gameplay instant they represent.

This is not an author-facing programming language. The later mission-rule system consumes proven semantic events rather than replacing this foundation.

---

# 4. Persistent identity

Persistence identity is not a node path, transform, import order, generated name, or geometry hash.

There are **two identity kinds**:

1. authored persistent identity;
2. runtime-created persistent identity.

There are **three persistence cases**:

1. authored instance is present;
2. authored instance has been permanently removed;
3. runtime-created persistent instance exists.

A removed-authored tombstone is state about an authored identity, not a third identity namespace.

## Authored instances

Every saveable concrete authored instance has a stable `persistent_id` owned by authoritative authored data or another explicitly persistent authored source.

The ID must survive ordinary move/reorder/reimport operations.

Duplicating an authored entity must create a distinct ID.

If an ID is generated or repaired, the corrected identity must be persisted back to the authoritative source. Repairing only generated/imported output is insufficient because the next reimport would reproduce the error.

Identity writeback/repair must be idempotent: a valid authored source is not rewritten merely because it was imported again. The workflow must not create import/rewrite loops or overwrite newer authored edits with stale generated data.

Missing or duplicate IDs fail closed with useful diagnostics.

## Runtime-created instances

Runtime-created persistent gameplay objects must not pretend to be authored entities.

If a runtime-created object must survive save/load, its save representation needs:

- a runtime persistent identity;
- enough spawn provenance/type data to recreate the correct gameplay object;
- semantic state owned by that object.

When the first real runtime-persistent object establishes a saved type/spawn identifier, that identifier must be semantic and stable across ordinary code/scene renames. An unknown/unsupported saved runtime type fails clearly rather than silently spawning a different object.

Restoring runtime-created persistent objects also reserves their restored identities in that world. Any later runtime-created object must receive an identity that cannot collide with an already-restored or already-allocated runtime identity. A UUID-like/generated identity is sufficient; do not build a global allocator framework merely to satisfy this rule.

Examples may eventually include deployables, mines, projectiles that intentionally persist, or mission-spawned actors/items.

Do not build a universal spawn framework before a real runtime-persistent object exists. The first such object proves the minimum contract.

## Removed authored instances

If an authored object can be permanently collected, destroyed, consumed, or otherwise absent after save/load, persistence must represent that absence explicitly rather than relying on the object simply not being found.

A tombstone/removed-ID representation is sufficient until real content proves a richer model necessary.

## Actor life-state identity

A persistent actor does not become a new persistent entity merely because its life state changes.

A guard transitioning among `conscious`, `unconscious`, and `dead`, including presentation/runtime changes needed to behave as a movable body, keeps the same authored/runtime persistent identity and semantic actor identity.

An implementation may replace or reorganize runtime nodes for presentation/physics if later proven useful, but that is an internal detail: mission references, statistics, save state, body discovery, and life-state events still refer to the same persistent actor.

---

# 5. Semantic save ownership and transactions

Stateful systems own their meaningful save state.

Each stateful boundary supports the conceptual operations:

```text
capture meaningful state
apply meaningful state
reconcile derived/runtime state
```

The save coordinator orchestrates these boundaries. It does not serialize arbitrary live scene trees.

Normally reconstruct rather than serialize:

- node paths;
- RIDs/physics handles;
- nav paths;
- signal connections;
- cached queries;
- temporary contacts;
- transient engine object references;
- coroutine/`await` continuation stacks;
- engine timers.

A save contains enough information to answer three questions:

```text
which mission/content revision is this?
which persistent instances exist or are removed?
what meaningful state does each owner have?
```

## Coherent snapshot capture

A save request made during ordinary active gameplay is fulfilled at the next stable gameplay boundary defined by the event/simulation contract.

The request belongs to the source `WorldSession`. If that session is stopped or replaced before capture, the request is cancelled rather than retargeted to another world. If capture already completed, the detached snapshot may continue through encoding/durable write after source-world teardown.

Conceptually:

```text
player requests save in WorldSession A
→ finish A's current semantic simulation/event pass
→ reach A's stable gameplay boundary
→ synchronously capture all save-owning semantic state and current player view pose into one detached in-memory snapshot
→ resume ordinary gameplay
→ encode/write that detached snapshot
```

The snapshot must represent one coherent semantic instant. Do not let individual systems capture opportunistically across different gameplay ticks while the world continues to mutate.

“Detached” means value-owned serialization data. A captured snapshot must not retain live `Node`/`Object`/RID references, live callbacks/signals, shared mutable gameplay `Resource` objects, or mutable Arrays/Dictionaries/objects that remain shared with live gameplay state. Mutating the live world after capture must not mutate the captured snapshot.

File serialization/write latency must not require keeping the whole gameplay world frozen after the detached snapshot has been captured. Background/deferred encoding is allowed only if it consumes the detached snapshot rather than live gameplay objects.

Pending semantic gameplay facts that belong to the completed simulation step must not be silently lost between state capture and event consequences. Capture after the current deterministic consequence pass has drained rather than serializing an arbitrary half-processed event queue.

Long-running saveable behavior must expose explicit semantic progress/state. A suspended coroutine, pending engine signal, `SceneTreeTimer`, animation callback, or similar runtime continuation is never the sole durable representation of gameplay that must resume correctly after restore.

Once a random/resolved decision is gameplay truth, its resolved semantic result is part of meaningful state when needed for coherent restoration; restore must not reroll it merely because the code that originally chose it runs again.

## Save-slot commit ordering

Durable save-file writes use a temporary/new file and replace the previous valid save only after the new write is complete and validated enough to commit. A failed/interrupted write must not destroy the last valid quicksave.

Multiple valid writes to the same logical save slot must not commit out of request order. Use the smallest sufficient mechanism, such as one serialized writer per slot or a monotonically increasing save generation where only the newest eligible generation may commit.

Quickload reads the latest **fully committed** save for the slot, never an in-progress temporary write.

## Restore object-existence order

Restore establishes **what exists** before applying **what state it has**.

The default semantic order is:

```text
validate save header/content compatibility
→ create the non-playing restore world according to the chosen application topology
→ instantiate authored entities
→ register authored persistent/semantic identities
→ apply removed-authored tombstones/removal set
→ recreate runtime-persistent instances
→ register and reserve runtime persistent/semantic identities
→ apply semantic snapshots to surviving/recreated owners
→ restore player/MissionState/mission-script state
→ resolve/reconcile references and derived state
→ after_restore/world_ready reconciliation while ordinary consequences remain suppressed
→ validate restored world
→ make restored world authoritative
→ enable AI, events, rules, perception, gameplay time, and gameplay updates
→ resume gameplay
```

If validation, state application, or reconciliation fails, the partially restored world does not enter `PLAYING`; it is torn down cleanly and a useful error is reported. A failed load must not leave a half-restored authoritative world.

During restore and `after_restore` reconciliation, ordinary consequences must not fire merely because state is being reconstructed:

- NPC decisions;
- objective evaluation;
- mission rules;
- perception;
- gameplay sound emission;
- door-change consequences;
- loot consequences;
- alarm propagation.

Loading a save must not itself become gameplay.

---

# 6. Save compatibility

Save-format version and mission-content revision are separate compatibility concerns.

A save must eventually record at minimum:

```text
save_format_version
mission_id
mission_content_revision
```

`save_format_version` identifies the global Vark save-state schema **and semantic interpretation contract**, not merely the byte/file encoding. Increment/refuse it when globally saved state would otherwise parse successfully but be interpreted with incompatible meaning—for example if the semantic meaning of saved actor, inventory, prop, combat, or other global gameplay state changes incompatibly.

`mission_content_revision` describes the authored mission content against which persistent IDs, semantic references, and restorable spatial/gameplay assumptions were saved.

`MissionDefinition` owns the mission's explicit `mission_content_revision` (or an equivalent single authoritative mission metadata field).

Increment the content revision when an authored-content change makes existing in-mission saves semantically unsafe, including representative cases such as:

- changing/removing persistent entity identities in a way old snapshots cannot resolve safely;
- changing the meaning of save-relevant semantic/content IDs;
- changing authored save-state assumptions so old state would be interpreted incorrectly;
- structural/spatial changes that make previously saved player/actor/prop transforms or other semantic world state impossible or meaningfully wrong to restore and are not covered by an explicit safe reconciliation/normalization policy.

Ordinary art, geometry, text, or tuning edits that remain semantically save-compatible do not require a revision bump merely because a file changed.

During development, the correct simple policy is acceptable:

```text
same supported save format + mission revision → load
unsupported global save format or mission revision → clear warning/refusal
```

Do not build migration machinery before a real migration is required.

---

# 7. Save-anywhere policy

Ordinary active gameplay quicksave/quickload is a fundamental Vark behavior.

A save request may wait until the next stable gameplay boundary—normally the next completed semantic simulation tick—without violating save-anywhere. The player is not required to wait for doors, AI, traversal, combat, or props to become idle.

Transient implementation details must not become broad save restrictions.

For traversal, doors, props, AI, combat, projectiles, thrown tools, active area effects, deployable arming, and similar transient states, choose explicitly among:

- direct semantic restoration;
- reconstruction from semantic state;
- normalization to a safe equivalent on restore.

A runtime-created object/effect does not avoid restore design merely because it is expected to be short-lived. If it is active at a valid save boundary and its disappearance would make the restored gameplay state semantically wrong—for example consumed ammo with a missing projectile/effect—it needs an explicit restoration/reconstruction/normalization policy.

Disabling save is reserved for states where arbitrary gameplay restoration is genuinely inappropriate, such as a top-level mission transition or deliberately noninteractive sequence. It must not become the routine solution for difficult gameplay-state restoration.

---

# 8. Presentation and animation ownership

Gameplay state is authoritative; presentation follows it.

Animation, first-person hands/weapons/held objects, door presentation, NPC presentation, and audio must not become the sole source of gameplay truth.

Gameplay code should not depend on arbitrary animation-player track names, private scene-tree paths, or presentation callbacks when a semantic state boundary can own the result.

Presentation callbacks may request/enqueue semantic work when needed, but must not bypass the controlled semantic mutation boundary for durable gameplay truth.

Introduce a dedicated presentation/animation adapter only when at least two real integrations need the same boundary.

---

# 9. Early architecture stress playground

Before stealth architecture is treated as hardened, one small integrated playground must force the same real objects through multiple systems.

The playground should eventually contain at minimum:

- one ordinary door;
- one guard;
- one gameplay light;
- two representative footstep surfaces;
- one throwable/stackable prop;
- one objective/exit;
- one runtime-created persistent object once such objects exist;
- one deliberately crude hostile/combat compatibility path.

Do not create separate fake doors, guards, or props for each subsystem.

The same ordinary door should progressively survive interaction, collision, sight, acoustics, NPC traversal, persistence, and prop obstruction.

The same guard should progressively survive perception, navigation, life state/body presentation, events, persistence, and crude hostile interaction **without changing persistent identity when life state changes**.

---

# 10. Combat compatibility before hardening

Full combat remains TARGET until later playtesting. Final combat feel, timings, animation, weapon balance, and detailed hit rules are not pulled forward.

However, before the stealth actor/event/save architecture is considered hardened, perform one intentionally crude compatibility proof:

```text
player produces an attack intent
→ guard receives a semantic hostile effect
→ guard can transition through relevant life state
→ event/gameplay sound consequences occur
→ other AI can react where applicable
→ resulting state survives save/restore
```

A crude block/defense action may be added only if needed to prove input/actor ownership.

This proof exists only to answer:

> **Can the same actor, input, event, perception, and persistence architecture support active hostile interaction without replacement?**

If not, correct the architecture before stealth APIs are hardened.

---

# 11. Prop-physics scope

The LOCKED player-facing Thief-style prop behavior remains authoritative.

The early implementation must solve only the supported cases currently needed by gameplay and fixtures.

Do not generalize early into arbitrary support graphs, bridge structures, cyclic supports, complex multi-support groups, moving support networks, or unrestricted rigid-body simulation.

Complex cases remain TARGET/OPEN until representative gameplay needs them and a fixture defines the intended behavior.

---

# 12. Tool/runtime contract

Before gameplay lighting, navigation, physics, or CI results are treated as portable contracts, Phase 0 must pin the runtime assumptions that materially affect them.

At minimum document the supported development configuration for:

- Godot version/build;
- physics backend;
- FuncGodot version;
- TrenchBroom version;
- renderer/rendering method used as the supported development target;
- supported development OS/export target relevant to current testing;
- CI runtime environment.

Do not add a broad platform matrix before Vark actually needs one.

---

# 13. Mission-authoring single sources of truth

Avoid duplicate authored ownership.

If the TrenchBroom map owns a player-start transform, `MissionDefinition` should reference/select that authored start rather than independently owning a second transform that can drift.

Apply the same rule to future authored spatial entities: choose one authoritative source and reference it semantically elsewhere.

Persistent-ID repair/writeback must respect the same principle: update the authoritative authored source through an idempotent workflow; never treat generated/imported output as the durable source and never allow an import cycle to repeatedly rewrite a valid map.

---

# 14. Acceptance contract

A roadmap item is not complete merely because code exists.

Every nontrivial item being implemented must have enough acceptance detail to answer these three questions **before implementation begins or as part of the implementation patch**:

```text
Done when:
Automated:
Manual:
```

These may be concise and may live directly in the roadmap item or be unambiguously inherited from its phase gate/testing contract.

- **Done when** describes observable completion conditions.
- **Automated** names deterministic checks that must pass, or explicitly says none are warranted.
- **Manual** names required user/playtest validation, or explicitly says none is warranted.

`[x]` is allowed only after required automated checks pass and required user validation is accepted.

---

# 15. Sequencing gates

The numbered roadmap remains authoritative, but the following gates prevent later phases from hardening around incomplete assumptions.

Before Phase 4 save/restore is considered complete, prove:

- authored identity survives the real create/duplicate/reimport workflow and repair/writeback is idempotent;
- runtime-persistent identity exists if the current slice creates persistent runtime objects;
- removed authored objects can be represented if the slice permits permanent removal/collection;
- actor life-state/body representation does not change persistent actor identity;
- world teardown/restart/quickload does not leave stale ownership regardless of the chosen restore topology;
- a pending save request cannot retarget from its source `WorldSession` to a replacement session;
- overlapping old/restored worlds, if used, cannot both act authoritative or share mutable world state;
- one gameplay-intent frame has deterministic tick/edge lifetime without forcing accepted look/UI cadence into that tick model;
- losing an input domain cancels incomplete edge-dependent gestures rather than leaving them armed/stuck;
- event-driven player view pose and controlled world-semantic mutation coexist without changing accepted look feel;
- durable semantic mutation, gameplay-time ownership, event ordering/lifecycle semantics, and the stable gameplay boundary are defined;
- semantic state has one authoritative owner rather than generic mirrored facts;
- save capture produces one coherent detached snapshot at that boundary and remains unchanged when live state mutates afterward;
- save-slot commit ordering cannot let an older quicksave overwrite a newer request;
- restore establishes object existence/removal/runtime recreation before semantic state application;
- restore reconciliation/`after_restore` completes while ordinary gameplay consequences remain suppressed;
- save-format compatibility covers incompatible global semantic interpretation changes;
- mission content revision ownership/bump/refusal policy includes incompatible spatial/semantic changes.

Before Phase 5 stealth hardening is considered complete, additionally prove the crude combat compatibility path against the same actor/input/event/perception/save architecture.

Before Phase 8 production authoring is considered complete, ordinary authored spatial values must have one source of truth, mission scripts must route supported mutation through the controlled gameplay boundary, and the cold-author workflow must exercise identity/reimport validation.

Before broad production generalization, inventory/deployables/runtime-created persistent objects must have exercised the persistence model if those features are part of the representative slice, including non-colliding runtime identity after restore and at least one active runtime-created transient when real gameplay can save during it.

---

# 16. Anti-framework rule

When considering a new abstraction, ask in order:

1. Can the current feature be implemented correctly without it?
2. Do at least two existing or immediate real systems require the same behavior?
3. What is the smallest semantic contract they actually share?

If the first answer is yes, do not build the abstraction yet.

If the second answer is no, keep the behavior local.

If the second answer is yes, build only the answer to the third question.

Healthy foundation ownership should remain boring and small: application/world ownership, gameplay-input routing, entity identity/registry, semantic events, explicit state ownership, save coordination, and concrete gameplay systems.

Avoid speculative universal entity/action/effect/actor/gameplay/time/scheduler frameworks until real integrated use proves they are necessary.
