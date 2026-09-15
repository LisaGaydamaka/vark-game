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
- Mission restart, quickload, mission exit, and application transition must tear the previous world down before the replacement world becomes authoritative.
- Stale work from an old world must not affect a new world.
- If generation/session tokens are needed to reject stale deferred work, keep them local to world ownership rather than inventing a global framework.

A system is not lifecycle-safe merely because `_ready()` succeeds.

## Quickload replacement rule

A quickload is an application-owned world replacement, not ordinary gameplay running two worlds at once.

When loading from an active world:

```text
load request
→ stop/freeze ordinary gameplay and gameplay input in the current world
→ validate save compatibility
→ build and restore an isolated non-playing candidate world
→ validate/reconcile candidate
→ on success: tear down old world, then promote candidate
→ on failure: tear down candidate and follow one application-owned recovery path
```

Candidate registries, event queues, timers, deferred work, and other world-scoped services remain candidate-local until promotion. The old world and candidate must never both behave as authoritative `PLAYING` worlds.

A failed candidate may not leak registrations, events, timers, callbacks, or other state into the old/current/next world.

---

# 2. Input ownership

Godot input is sampled at the application/input boundary, then converted into semantic gameplay intent.

Conceptually:

```text
Godot Input
→ application input router
→ semantic input frame
→ current gameplay owners
```

Gameplay objects must not independently decide whether gameplay input is globally permitted.

The semantic frame may contain small domains such as locomotion, look, interaction, combat, and inventory. Do not force every future action into one ever-growing locomotion command object.

Pause, UI, menus, sequences, and gameplay explicitly arbitrate which domains currently receive input.

One semantic input frame belongs to one gameplay simulation tick. Continuous state such as movement direction or `block_held` may remain true across frames while physically held. Edge intent such as `interact_pressed`, `attack_pressed`, or `attack_released` exists for that semantic frame only.

When an input domain becomes disabled because of pause, UI ownership, a sequence, teardown, or world replacement, transient edge intent for that domain is cleared rather than stored and replayed later. Resuming gameplay must not produce ghost presses/releases from an inactive period.

Accepted movement/look/traversal behavior remains unchanged by this refactor.

---

# 3. Gameplay-event semantics and stable simulation boundary

Vark uses semantic gameplay facts rather than private implementation signals for cross-system consequences.

Before mission scripting depends on the event path, the implementation must define and test these semantics:

- dispatch timing;
- deterministic ordering;
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

The canonical semantic simulation boundary is conceptually:

```text
consume one semantic input frame
→ perform the gameplay/physics step
→ enqueue semantic gameplay facts
→ drain the current semantic event/consequence pass deterministically
→ reach STABLE GAMEPLAY BOUNDARY
```

A stable gameplay boundary means the semantic consequences belonging to that completed step have been processed according to the event contract. Save snapshot capture and other operations that require one coherent instant occur only at this boundary.

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
- transient engine object references.

A save contains enough information to answer three questions:

```text
which mission/content revision is this?
which persistent instances exist or are removed?
what meaningful state does each owner have?
```

## Coherent snapshot capture

A save request made during ordinary active gameplay is fulfilled at the next stable gameplay boundary defined by the event/simulation contract.

Conceptually:

```text
player requests save at any ordinary gameplay time
→ finish the current semantic simulation/event pass
→ reach stable gameplay boundary
→ synchronously capture all save-owning semantic state into one immutable in-memory snapshot
→ resume ordinary gameplay
→ encode/write that immutable snapshot
```

The snapshot must represent one coherent semantic instant. Do not let individual systems capture opportunistically across different gameplay ticks while the world continues to mutate.

File serialization/write latency must not require keeping the whole gameplay world frozen after the immutable snapshot has been captured. Background/deferred encoding is allowed only if it consumes the immutable snapshot rather than live gameplay objects.

Pending semantic gameplay facts that belong to the completed simulation step must not be silently lost between state capture and event consequences. Prefer capturing after the current deterministic event pass has drained rather than serializing an arbitrary half-processed event queue.

## Restore object-existence order

Restore establishes **what exists** before applying **what state it has**.

The default conceptual order is:

```text
validate save header/content compatibility
→ create isolated candidate mission world while non-playing
→ instantiate authored entities
→ register authored persistent/semantic identities
→ apply removed-authored tombstones/removal set
→ recreate runtime-persistent instances
→ register runtime persistent/semantic identities
→ apply semantic snapshots to surviving/recreated owners
→ restore player/MissionState/mission-script state
→ resolve/reconcile references and derived state
→ validate restored candidate
→ mark candidate ready
→ tear down old world if one exists
→ atomically promote candidate as authoritative
→ enable AI, events, rules, perception, and gameplay updates
→ after_restore/world_ready hook
→ resume gameplay
```

If validation, state application, or reconciliation fails, the candidate does not enter `PLAYING`; it is torn down cleanly and a useful error is reported. A failed load must not leave a half-restored authoritative world.

During restore, ordinary consequences must not fire merely because state is being reconstructed:

- NPC decisions;
- objective evaluation;
- mission rules;
- perception;
- gameplay sound emission;
- door-change consequences;
- loot consequences;
- alarm propagation.

Loading a save must not itself become gameplay.

Durable save-file writes should use a temporary/new file and replace the previous valid save only after the new write is complete and validated enough to commit. A failed/interrupted write should not destroy the last valid quicksave.

---

# 6. Save compatibility

Save-format version and mission-content revision are separate compatibility concerns.

A save must eventually record at minimum:

```text
save_format_version
mission_id
mission_content_revision
```

`save_format_version` describes the serialization contract.

`mission_content_revision` describes the authored mission content against which persistent IDs and semantic references were saved.

`MissionDefinition` owns the mission's explicit `mission_content_revision` (or an equivalent single authoritative mission metadata field).

Increment the content revision when an authored-content change makes existing in-mission saves semantically unsafe, including representative cases such as:

- changing/removing persistent entity identities in a way old snapshots cannot resolve safely;
- changing the meaning of save-relevant semantic/content IDs;
- changing authored save-state assumptions so old state would be interpreted incorrectly.

Ordinary art, geometry, text, or tuning edits that remain semantically save-compatible do not require a revision bump merely because a file changed.

During development, the correct simple policy is acceptable:

```text
same supported mission revision → load
different unsupported mission revision → clear warning/refusal
```

Do not build migration machinery before a real migration is required.

---

# 7. Save-anywhere policy

Ordinary active gameplay quicksave/quickload is a fundamental Vark behavior.

A save request may wait until the next stable gameplay boundary—normally the next completed semantic simulation tick—without violating save-anywhere. The player is not required to wait for doors, AI, traversal, combat, or props to become idle.

Transient implementation details must not become broad save restrictions.

For traversal, doors, props, AI, combat, and similar transient states, choose explicitly among:

- direct semantic restoration;
- reconstruction from semantic state;
- normalization to a safe equivalent on restore.

Disabling save is reserved for states where arbitrary gameplay restoration is genuinely inappropriate, such as a top-level mission transition or deliberately noninteractive sequence. It must not become the routine solution for difficult gameplay-state restoration.

---

# 8. Presentation and animation ownership

Gameplay state is authoritative; presentation follows it.

Animation, first-person hands/weapons/held objects, door presentation, NPC presentation, and audio must not become the sole source of gameplay truth.

Gameplay code should not depend on arbitrary animation-player track names, private scene-tree paths, or presentation callbacks when a semantic state boundary can own the result.

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

Every nontrivial item being implemented must have enough acceptance detail to answer these three questions:

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
- world teardown/restart/quickload does not leave stale ownership;
- candidate-load isolation prevents old and candidate worlds from both acting authoritative;
- one semantic input frame has deterministic tick/edge lifetime;
- event ordering/lifecycle semantics and the stable gameplay boundary are defined;
- save capture produces one coherent immutable snapshot at that boundary;
- restore establishes object existence/removal/runtime recreation before semantic state application;
- mission content revision ownership/bump/refusal policy is explicit.

Before Phase 5 stealth hardening is considered complete, additionally prove the crude combat compatibility path against the same actor/input/event/perception/save architecture.

Before Phase 8 production authoring is considered complete, ordinary authored spatial values must have one source of truth and the cold-author workflow must exercise identity/reimport validation.

Before broad production generalization, inventory/deployables/runtime-created persistent objects must have exercised the persistence model if those features are part of the representative slice.

---

# 16. Anti-framework rule

When considering a new abstraction, ask in order:

1. Can the current feature be implemented correctly without it?
2. Do at least two existing or immediate real systems require the same behavior?
3. What is the smallest semantic contract they actually share?

If the first answer is yes, do not build the abstraction yet.

If the second answer is no, keep the behavior local.

If the second answer is yes, build only the answer to the third question.

Healthy foundation ownership should remain boring and small: application/world ownership, input routing, entity identity/registry, semantic events, save coordination, and concrete gameplay systems.

Avoid speculative universal entity/action/effect/actor/gameplay frameworks until real integrated use proves they are necessary.
