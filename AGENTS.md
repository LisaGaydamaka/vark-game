# Vark repository workflow

This file is the operating contract for AI-assisted work in this repository. The user should be able to manage development through chat without manually maintaining repository documentation.

## Sources of truth

- `docs/GAME_VISION.md` — what Vark is: product, gameplay, presentation, and confirmed scope decisions.
- `docs/DEVELOPMENT_PLAN.md` — what to build next: ordered roadmap, dependencies, item-specific acceptance criteria, and status.
- `docs/FOUNDATION_CONTRACT.md` — cross-cutting architecture invariants for lifecycle, input ownership, events, persistence, save compatibility, and early stress gates.
- `docs/TESTING.md` — how correctness is verified: test rules, commands, current automated coverage, manual regression checks, and CI policy.
- Current code/tests — implementation truth.

The user's latest explicit instruction overrides stale repository documentation. When that happens, synchronize the affected document during the next authorized repository patch.

When a roadmap item is underspecified about a cross-cutting concern, apply `FOUNDATION_CONTRACT.md`. Do not bypass a foundation gate merely because the numbered roadmap introduces the larger feature later. The foundation contract may require an intentionally crude compatibility proof before a later system is fully designed; that proof does not pull the later feature's full scope forward.

## Decision states

Repository documentation distinguishes three kinds of design statements:

- **LOCKED** — implemented and accepted player-facing behavior or an explicit confirmed product rule. Internal implementation may change unless the behavior itself is explicitly reopened.
- **TARGET** — intended behavior that has not yet been sufficiently proven in playable integration. Prototype and validate it before treating it as permanent.
- **OPEN** — the problem is known, but the implementation/behavior should be discovered through a focused spike rather than designed speculatively.

Do not silently convert TARGET or OPEN decisions into LOCKED contracts.

## Working on a roadmap item

For a request such as `implement 2.3`, read this file, the matching roadmap item, relevant foundation/vision/testing sections, and the current implementation before editing.

Implement only the requested bounded item plus the minimum supporting architecture it genuinely requires. Do not silently bundle adjacent roadmap items or build speculative systems for distant features.

Prefer root-cause fixes, clear ownership, semantic APIs, and reusable foundations where a real current need exists. Avoid duplicated logic, arbitrary thresholds, and workarounds that hide the actual problem.

Use the development loop:

> **spike → integrate → validate → define the contract → generalize only what proved reusable**

Do not design a universal subsystem before at least one representative gameplay use has exercised the hard interactions that define it.

When a system touches an existing integration spine such as doors, save/load, input ownership, perception, mission loading, world lifetime, persistent identity, or authoring, test the interaction while both systems are still small.

Cross-cutting architecture is not considered stable until the relevant `FOUNDATION_CONTRACT.md` gate has been exercised. In particular, do not harden stealth APIs before the crude hostile/combat compatibility proof demonstrates that the same actor/input/event/perception/persistence model can support active hostile interaction.

Do not change intended gameplay merely to make a test pass. If a test encodes the wrong invariant, correct the test.

## Player-controller rule

The accepted player-controller **behavior and feel are frozen; its implementation is not**.

Refactoring input sampling, command routing, component ownership, pause/cutscene gating, mouse ownership, scene structure, or other internals is allowed and expected when later architecture requires it, provided the accepted movement/look/traversal behavior remains unchanged.

Future tests protect the behavior contract, not a particular internal call graph.

## Testing and validation

Use `docs/TESTING.md` for detailed testing rules and `docs/FOUNDATION_CONTRACT.md` for cross-system invariants that must be proven by integrated fixtures.

As part of implementation, decide automatically whether objective automated coverage is warranted. Reproducible gameplay bugs should receive a regression test when they can reasonably be recreated deterministically. Subjective feel, pacing, readability, atmosphere, and artistic quality are accepted through the user's playtesting, not automated assertions.

Systemic features need integrated proof, not only unit-level proof. A save system is not complete because it can serialize a dictionary; a door is not complete because it animates; an acoustic system is not complete because one distance test passes.

For every nontrivial roadmap item being implemented, make completion mechanically checkable with concise `Done when`, `Automated`, and `Manual` acceptance information. These may be written in the roadmap item itself or inherited unambiguously from its phase gate/testing/foundation contract. If an automated or manual check is not warranted, say so rather than leaving completion subjective.

Never claim Godot/runtime tests were run unless they actually were. If runtime execution is unavailable, provide the exact local command and manual scenario the user should run.

Roadmap status meanings:

- `[ ]` — not implemented.
- `[~]` — implemented or substantially implemented but still awaiting required validation/follow-up.
- `[x]` — required automated checks passed and the user accepted the relevant manual/playtest behavior.

Do not mark newly uploaded gameplay code `[x]` before the user validates it.

## Documentation maintenance

Documentation maintenance is the agent's responsibility. Do not ask the user to edit documentation after implementation or testing.

During each authorized development patch, update every affected living document automatically:

- update `GAME_VISION.md` only when a confirmed product/design/scope decision changes;
- update `DEVELOPMENT_PLAN.md` when roadmap scope, dependencies, acceptance criteria, ordering, or truthful status changes;
- update `FOUNDATION_CONTRACT.md` only when a cross-cutting architecture invariant/gate changes, and keep it small rather than turning it into a general framework specification;
- update `TESTING.md` when test commands, current automated coverage, manual regression coverage, or testing strategy changes.

If the user reports validation or a design change without authorizing a repository write, remember the pending documentation change in the conversation and apply it with the next authorized coherent patch.

Do not create `PLAYTEST_NOTES.md`. Subjective feedback remains in chat unless the user explicitly requests a document later.

Avoid duplicate sources of truth. Do not create new persistent documentation when the information fits cleanly in an existing living document. `FOUNDATION_CONTRACT.md` is intentionally limited to cross-cutting invariants whose omission would make multiple roadmap phases contradict or replace one another. Add other specialized documents later only when a real production need cannot be represented clearly by the core set (for example, individual production mission documents).

## GitHub policy

Repository writes require the exact phrase `upload to gh` in the user's current request. Without it, GitHub work is read-only.

Authorized writes go only to the existing `test` branch. Never write to `main` or another branch and never create helper branches.

One `upload to gh` authorization covers one coherent requested patch. After that patch is uploaded and verified, further repository writes require a new authorization.

Before writing, re-read the current `test` head and current versions of files being changed. After writing, verify the final `test` head and compare it with the pre-write head to confirm the exact changed-file set.

## Normal development cycle

1. User selects a roadmap item.
2. Agent inspects current docs/code/tests, including relevant foundation invariants.
3. If the item contains unresolved behavior/architecture, build the smallest representative spike that can answer it.
4. Integrate the result with the existing playable path instead of leaving it isolated.
5. Exercise relevant cross-cutting foundation gates while systems are still small.
6. Add objective regressions and diagnostics where warranted.
7. Record concise `Done when`, `Automated`, and `Manual` acceptance for the implemented item.
8. Update living docs to reflect what is now LOCKED, still TARGET, or still OPEN.
9. Agent uploads only if explicitly authorized.
10. User runs local automated checks and playtests in Godot.
11. User reports success, bugs, or feel differences in chat.
12. Agent fixes/tunes as requested and keeps documentation truthful on the next authorized patch.
13. Move on only when the current item has the required acceptance.
