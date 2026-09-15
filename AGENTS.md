# Vark repository workflow

This file is the operating contract for AI-assisted work in this repository. The intended user workflow is deliberately simple: the user selects a roadmap item, authorizes one repository patch, the agent performs the complete bounded implementation/verification/documentation cycle, and the user only performs the focused manual/playtest validation that cannot be replaced by automation.

## Sources of truth

- `docs/GAME_VISION.md` — what Vark is: product, gameplay, presentation, and confirmed scope decisions.
- `docs/DEVELOPMENT_PLAN.md` — what to build next: ordered roadmap, dependencies, item-specific acceptance criteria, and status.
- `docs/FOUNDATION_CONTRACT.md` — cross-cutting architecture invariants for lifecycle, input ownership, events, persistence, save compatibility, and early stress gates.
- `docs/TESTING.md` — how correctness is verified: test rules, commands, current automated coverage, manual regression checks, and CI policy.
- Current code/tests — implementation truth.

The user's latest explicit instruction overrides stale repository documentation. When that happens, synchronize every affected living document during the next authorized repository patch.

When a roadmap item is underspecified about a cross-cutting concern, apply `FOUNDATION_CONTRACT.md`. Do not bypass a foundation gate merely because the numbered roadmap introduces the larger feature later. A foundation compatibility proof does not pull the later feature's full scope forward.

## User-facing operating model

The normal request is expected to be as small as:

> `do step X.Y, upload to gh`

Treat that as a request to complete the **entire bounded roadmap item X.Y**, not merely its most obvious production-code edit. Unless the item itself says otherwise, the agent owns all work reasonably required to make that step honestly ready for automated validation and focused user acceptance, including necessary supporting code within scope, deterministic tests, fixtures, diagnostics, and living-document updates.

The user should not need to separately ask for tests, documentation maintenance, CI inspection, status synchronization, or obvious supporting work that belongs to the requested roadmap item.

The user normally owns only subjective/manual validation. The agent owns machine-verifiable validation whenever its environment or configured CI can perform it.

## Decision states

Repository documentation distinguishes three kinds of design statements:

- **LOCKED** — implemented and accepted player-facing behavior or an explicit confirmed product rule. Internal implementation may change unless the behavior itself is explicitly reopened.
- **TARGET** — intended behavior that has not yet been sufficiently proven in playable integration. Prototype and validate it before treating it as permanent.
- **OPEN** — the problem is known, but the implementation/behavior should be discovered through a focused spike rather than designed speculatively.

Do not silently convert TARGET or OPEN decisions into LOCKED contracts.

## Roadmap status transition algorithm

Use roadmap status mechanically:

- `[ ]` — no substantial implementation exists.
- `[~]` — substantial implementation exists, but at least one required acceptance condition is still pending: post-push CI, another required automated check, required manual/user validation, or a specifically documented follow-up belonging to that item.
- `[x]` — every required `Automated:` criterion passed, every required `Manual:` criterion was accepted by the user or is explicitly `none`, and no known unresolved failure remains for the item's `Done when:` contract.

A newly implemented gameplay/system item normally enters the repository as `[~]`, because post-push CI and/or user validation happen after that implementation commit. Do not mark an implementation `[x]` in its initial upload merely because local tests passed.

If `Manual: none` and every relevant automated requirement including post-push CI is green, the item may be reconciled to `[x]` on the next authorized patch without a subjective playtest.

## Roadmap-step execution protocol

For every request to implement a numbered roadmap item, follow this protocol unless the user explicitly narrows the request further.

### 1. Reconcile prior accepted work

Before evaluating prerequisites, check the current conversation for user validation of the most recently handed-off roadmap work.

If the user previously reported that the last uploaded step passed its required manual/playtest validation, treat that report as authoritative even if the repository still shows `[~]` because no write authorization existed at the time of the report.

During the next authorized coherent patch:

- update the previously accepted step to `[x]` when all automated requirements also passed;
- apply any testing/design/status documentation changes implied by that validation;
- then implement the newly requested step.

A pending successful user validation satisfies a prerequisite in the current conversation even while the checked-in roadmap temporarily remains `[~]`.

If conversation history is unavailable, the user explicitly requests the **immediate next dependent roadmap item**, and the immediately preceding required item is checked in as `[~]` with green automated validation and only its previously required user/manual acceptance remaining, the request to advance may be treated as confirmation that the preceding focused manual acceptance passed unless the user reports otherwise. Reconcile that preceding item to `[x]` in the same authorized patch.

Never use this advancement rule to approve an arbitrary older `[~]` item, an item with failing/pending automated validation, an item with unresolved technical follow-up, or an item whose required manual cases were never clearly handed off.

### 2. Preflight the current integration head

Before editing:

- read the current `test` head;
- re-read this `AGENTS.md`;
- read the requested roadmap item and its phase gate;
- read directly relevant `GAME_VISION.md`, `FOUNDATION_CONTRACT.md`, and `TESTING.md` sections;
- inspect the current implementation, tests, fixtures, resources, and directly affected call sites;
- inspect the relevant CI result/status for the current `test` head when CI exists;
- if using a local workspace, inspect existing uncommitted/local modifications before editing.

Relevant CI for the current `test` head must be terminal and successful before uploading another implementation patch. Read-only investigation may continue while CI is queued/in-progress, but do not upload the next implementation until that integration result is known. Do not intentionally rely on concurrency cancellation to replace validation of the current head.

Do not stack new implementation work on a failing integration head. Diagnose or report the failure first.

### 3. Resume existing roadmap work correctly

If the requested item is already `[~]`, inspect the implementation already present and identify which `Done when / Automated / Manual` conditions remain unmet. Continue or correct the existing implementation; do not rebuild it from scratch unless the current implementation is proven unsuitable.

If the requested item is already `[x]`, treat it as complete. Do not reimplement it merely because its number was mentioned again. Modify/reopen it only when the user's request clearly describes a regression, reopened design decision, or intentional change; update status/contracts truthfully when that happens.

### 4. Check prerequisites without silently expanding scope

Confirm the actual prerequisites of X.Y are satisfied by repository state plus any pending accepted validation allowed above.

Do not silently implement an entire earlier/later roadmap item for convenience.

Implement the minimum supporting seam that X.Y genuinely requires when that seam is part of making X.Y work. If the missing prerequisite would amount to implementing a distinct roadmap item, report X.Y as blocked rather than hiding the scope expansion.

### 5. Establish acceptance before declaring completion

Every nontrivial roadmap item needs mechanically checkable acceptance information:

```text
Done when:
Automated:
Manual:
```

Derive these from the roadmap, foundation, vision, and testing contracts. Add/clarify them in the same implementation patch when necessary.

Do not ask the user to invent acceptance criteria when the repository already contains enough information to derive them. Ask for a product/design decision only when a genuine player-facing TARGET/OPEN choice cannot be resolved by implementation evidence or existing instructions.

### 6. Implement the complete bounded item

`do step X.Y` includes, where warranted:

- production code;
- the minimum supporting code genuinely required by X.Y;
- deterministic regression tests;
- test fixtures/maps/resources;
- useful diagnostics for otherwise invisible failure modes;
- authoring/import/source-ownership adjustments required by the item;
- updates to affected living documents.

Do **not** opportunistically:

- implement adjacent roadmap items;
- refactor unrelated systems;
- rename/reorganize unrelated content;
- upgrade tools/dependencies;
- clean up unrelated warnings/files;
- change accepted player-facing behavior.

Such work belongs in the current patch only when it is genuinely required for the requested item to be correct.

### 7. Create/update tests automatically when warranted

The agent owns the decision to add objective automated coverage. Do not wait for the user to ask for tests.

Create or update deterministic tests when at least one of these is true:

- the roadmap item explicitly requires automated coverage;
- new deterministic gameplay/system behavior is introduced;
- a reproducible bug is fixed;
- a LOCKED behavior could be affected by the implementation/refactor;
- a cross-system ownership, lifecycle, persistence, timing, ordering, or failure boundary is introduced;
- a regression would otherwise be costly or ambiguous to rediscover manually.

An automated test does not count as coverage merely because a test file exists. Every new deterministic regression must be reachable from the appropriate authoritative test entry point used locally and by CI. When a second independent suite appears, create/update the documented all-tests entry point and make local full-regression/CI use it in the same coherent roadmap patch.

For a reproducible bug fix, prefer a regression that would fail against the pre-fix behavior and passes after the fix. Exercise the real production path containing the bug rather than only a helper introduced by the fix. Where practical, verify that deliberately violating the protected boundary makes the new assertion fail.

Do not add tests merely to increase test count, and do not freeze subjective TARGET/OPEN tuning as permanent behavior before validation.

### 8. Maintain living documentation in the same patch

Documentation maintenance is part of implementation, not a later user chore.

- update `GAME_VISION.md` only when a confirmed product/design/scope decision changes;
- update `DEVELOPMENT_PLAN.md` when roadmap scope, dependencies, acceptance criteria, ordering, supported tool/runtime baseline, or truthful status changes;
- update `FOUNDATION_CONTRACT.md` only when a genuine cross-cutting architecture invariant/gate changes;
- update `TESTING.md` when commands, actual automated coverage, fixtures, manual regression coverage, or testing/CI strategy changes.

Do not create a second persistent source of truth when information belongs in an existing living document. Do not create `PLAYTEST_NOTES.md`; subjective feedback remains in chat unless the user explicitly requests such a document.

Before upload, perform a consistency pass across every affected living document: statuses must match implementation/validation reality, DEVELOPMENT_PLAN and TESTING must agree about commands/coverage, tool/runtime versions must agree wherever referenced, GAME_VISION must not absorb implementation-only details, FOUNDATION_CONTRACT must not absorb local implementation detail, and no duplicate source of truth may have been introduced.

### 9. Respect source/generated/vendor ownership

When an authoritative source exists, edit the source rather than generated/imported output. Do not put irreplaceable manual changes into generated/imported artifacts.

Generated files may be updated when the normal tool/import workflow intentionally produces them and repository policy says they are tracked.

`addons/func_godot/` is vendored third-party/plugin code. Prefer project-side integration, configuration, adapters, or authored-source changes. Modify vendored plugin internals only when the requested roadmap item genuinely requires a plugin/upstream patch and no appropriate project-side solution exists; document why such a modification was necessary.

Never commit credentials/tokens/secrets, user-specific absolute paths, editor-local caches/state, crash/debug dumps, temporary captures, local build output, or machine-specific generated state unless repository policy explicitly defines that exact file as durable source/configuration. If a new tool produces persistent local output, classify its ownership before committing it.

### 10. Preserve local/user work

When a local workspace is available, never discard, reset, clean, overwrite, or revert unrelated user/local changes merely to obtain a clean working tree. Do not use destructive reset/checkout/clean operations against unreviewed user work.

If unrelated existing changes do not overlap the requested item, leave them untouched. If they overlap files/code required by the item, preserve and reconcile them rather than blindly replacing them. If safe reconciliation is impossible without user intent, report the conflict instead of destroying work.

### 11. Verify version-specific external behavior instead of guessing

When correctness depends on version-specific behavior of Godot, Jolt, FuncGodot, TrenchBroom, GitHub Actions, or another external tool/library and repository evidence is insufficient, inspect the pinned version/source or current official documentation rather than guessing.

Do not upgrade a dependency merely because newer behavior would make the requested step easier unless the roadmap item explicitly requires or authorizes that upgrade.

### 12. Perform automated validation before push when possible

When execution is available, the agent should run the checks it can run before uploading:

- newly added/targeted tests;
- the current authoritative full regression barrier;
- clean import/bootstrap or tool validation when relevant to the change;
- any deterministic content/authoring validation introduced by the item.

Inspect intended changes for incidental generated-file churn and unrelated modifications before upload.

Automated validation is the agent's responsibility by default. Do not ask the user to run an automated command merely because it was omitted from the implementation workflow.

A successful process exit is necessary but not always sufficient. When runtime/import/test logs are available, inspect them for newly introduced parser/script errors, resource-load/UID/import failures, invalid authored references, or other meaningful project warnings indicating a regression. Do not fail work merely for known harmless third-party/deprecation noise; distinguish relevant project regressions from external warnings.

If the agent environment cannot execute a required runtime/tool check:

- never claim it ran;
- use configured CI after upload when CI covers it;
- identify a genuinely local-only automated check for the user only when neither the agent nor CI can execute it.

Subjective feel, pacing, readability, atmosphere, artistic quality, and other genuinely human judgments remain user playtest territory.

### 13. Apply supported-platform validation correctly

Windows x64 desktop is the supported development/export target. Ubuntu CI is headless deterministic validation only and does not prove Windows-specific runtime/export behavior.

When a roadmap item materially changes renderer/rendering-device configuration, Windows-specific APIs, filesystem/path behavior, native/plugin integration, export/startup behavior, executable packaging, or other target-specific behavior, include an appropriate Windows x64 acceptance check.

If the agent cannot execute that Windows check, do not claim Ubuntu CI proves it. Provide the user a focused Windows validation step.

### 14. Upload one coherent integration patch

GitHub writes follow the authorization rules below.

Prefer one atomic commit for the requested roadmap-step patch, especially when code/tests/docs depend on one another. If Git tooling supports a single tree/commit operation, use it rather than intentionally exposing `test` to a sequence of half-applied file states.

If available tooling cannot make the whole patch atomic, order writes so intermediate states are as safe/buildable as possible and verify the final pre-write-to-post-write diff carefully. Do not create helper branches to work around the direct-write policy.

### 15. Verify the uploaded result

After the write:

- confirm the final `test` head;
- compare the pre-write head with the final head;
- verify the changed-file set matches the requested coherent patch;
- confirm CI was triggered when applicable;
- inspect relevant CI through completion when the tooling permits it.

A commit reaching `test` is not acceptance. Do not report the step as accepted while relevant CI is failing or pending.

### 16. Handle CI failure without consuming extra scope

If relevant CI fails:

- diagnose the actual failure, including relevant job logs when available;
- keep the roadmap item `[~]` (or `[ ]` if implementation never became substantial);
- do not hand a known-broken integration to the user for normal playtest acceptance;
- do not make another GitHub write using the already-consumed authorization;
- explain the correction needed.

A corrective GitHub patch requires a new user message containing the exact authorization phrase `upload to gh`.

### 17. Hand off only the focused manual validation that remains

After automated validation is green, tell the user exactly what still requires human validation.

The handoff should state:

- what scene/mission/setup to use;
- exact actions to perform;
- expected behavior/results;
- important regressions/failure symptoms to watch for;
- what outcome to report back.

The focused handoff must collectively cover every unresolved `Manual:` acceptance criterion for the roadmap item. “Focused” means omit irrelevant global checks, not omit required acceptance cases. Do not dump the entire global regression checklist after every unrelated change.

### 18. Interpret the user's validation report narrowly

If the user reports that the handed-off test **works/passes/is good**, treat that as manual acceptance of the most recently handed-off item **only for the cases explicitly included in that handoff**. Do not infer acceptance of manual criteria that were not asked.

Do not write to GitHub unless that user message also contains a fresh `upload to gh` authorization. Record the validation in conversation as a pending roadmap/documentation synchronization for the next authorized coherent patch.

If all required automated checks and manual acceptance are satisfied, the item is logically accepted even if checked-in status temporarily remains `[~]` until the next authorized patch.

If the user reports a failure:

- keep the item unaccepted;
- diagnose it against the intended contract;
- add/update a deterministic regression when the failure is objectively reproducible and testable;
- make corrections only after a new `upload to gh` authorization;
- repeat automated validation and focused manual handoff.

### 19. TARGET/OPEN work may require more than one user loop

For a TARGET or OPEN item:

- build the smallest representative implementation/spike that can answer the unresolved question;
- integrate it into the real playable path where the roadmap requires integration;
- automate only objective invariants that do not prematurely freeze unvalidated feel/tuning;
- keep the item `[~]` while required behavior/design validation remains unresolved;
- give the user a focused playtest/decision scenario;
- revise on a newly authorized patch if the result is rejected.

Do not convert TARGET/OPEN behavior to LOCKED merely because code exists.

### 20. Report completion consistently

Every uploaded roadmap-step handoff should state, concisely:

- roadmap item implemented;
- commit/final `test` head;
- important files/systems changed;
- automated checks actually performed and their results;
- relevant CI result;
- current roadmap status (`[ ]`, `[~]`, or pending/accepted `[x]` reconciliation);
- exact manual validation still required, or explicitly `none`;
- anything intentionally left out because it belongs to another roadmap item.

## Implementation principles

Prefer root-cause fixes, clear ownership, semantic APIs, and reusable foundations where a real current need exists. Avoid duplicated logic, arbitrary thresholds, and workarounds that hide the actual problem.

Use the development loop:

> **spike → integrate → validate → define the contract → generalize only what proved reusable**

Do not design a universal subsystem before at least one representative gameplay use has exercised the hard interactions that define it.

When a system touches an existing integration spine such as doors, save/load, input ownership, perception, mission loading, world lifetime, persistent identity, or authoring, test the interaction while both systems are still small.

Cross-cutting architecture is not considered stable until the relevant `FOUNDATION_CONTRACT.md` gate has been exercised. In particular, do not harden stealth APIs before the crude hostile/combat compatibility proof demonstrates that the same actor/input/event/perception/persistence model can support active hostile interaction.

When save/load work begins, preserve the foundation's stable gameplay boundary: semantic save capture represents one completed simulation/event instant, and restore establishes object existence before applying semantic state. Do not add per-system ad hoc save timing.

Do not change intended gameplay merely to make a test pass. If a test encodes the wrong invariant, correct the test.

## Player-controller rule

The accepted player-controller **behavior and feel are frozen; its implementation is not**.

Refactoring input sampling, command routing, component ownership, pause/cutscene gating, mouse ownership, scene structure, or other internals is allowed and expected when later architecture requires it, provided the accepted movement/look/traversal behavior remains unchanged.

Future tests protect the behavior contract, not a particular internal call graph.

## Testing and validation status

Use `docs/TESTING.md` for detailed testing rules and `docs/FOUNDATION_CONTRACT.md` for cross-system invariants that must be proven by integrated fixtures.

Systemic features need integrated proof, not only unit-level proof. A save system is not complete because it can serialize a dictionary; a door is not complete because it animates; an acoustic system is not complete because one distance test passes.

Never claim Godot/runtime tests were run unless they actually were.

Roadmap status follows the transition algorithm above. Do not mark newly uploaded gameplay code `[x]` before required post-push automated validation and user acceptance. Because repository writes require explicit authorization, a logically accepted `[~]` may remain checked in temporarily; reconcile it during the next authorized patch.

Under the current direct-write workflow, `test` is an **integration branch**. CI on `test` is post-push validation, not a pre-push gate.

## GitHub policy

Repository writes require the exact phrase `upload to gh` in the user's **current request**. Without it, GitHub work is read-only.

Authorized writes go only to the existing `test` branch. Never write to `main` or another branch and never create helper branches.

One `upload to gh` authorization covers one coherent requested patch. After that patch is uploaded and verified, further repository writes require a new authorization.

Before writing, re-read the current `test` head, current `AGENTS.md`, and current versions of every file being changed. After writing, verify the final `test` head and compare it with the pre-write head to confirm the exact changed-file set.

Never force-update/rewind `test` as part of normal development. If the head moved unexpectedly after preflight, re-read/reconcile rather than overwriting another change.

Because writes intentionally go directly to `test`, repository policy must not pretend CI validated a commit before it landed. CI should run immediately after the push when available; failed CI means the integration commit is not accepted and requires correction before the roadmap item advances.

## Normal chat-driven development cycle

The expected steady-state interaction is:

```text
User: do step X.Y, upload to gh
Agent: preflight → implement complete bounded item → tests/docs → automated validation → upload → verify CI → focused manual handoff
User: works
Agent: records pending acceptance; no repository write without new authorization
User: do step X.Z, upload to gh
Agent: reconciles X.Y to [x] when warranted → performs complete X.Z cycle
```

If the user reports a bug instead of acceptance, the step stays open. The agent diagnoses it, then waits for a new authorized correction request before writing.
