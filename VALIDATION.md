# motspilot Pipeline — Gate Validation (Dry Run)

## Purpose

This document maps six synthetic "deliberately broken" task scenarios to the
specific pipeline gates introduced in the recent gate-tightening pass:

- MUST FIX (untested seam) severity tier — `prompts/verification.md`,
  section "Untested seams"
- Four consistency checks — `prompts/verification.md`, sections "Check 1"
  through "Check 4"
- Smoke-test execution gate — `prompts/delivery.md`, section
  "3.2 Smoke test execution (pre-delivery gate)"
- Integration-vs-unit hard rule — `prompts/testing.md`, section
  "Integration tests vs reflection/unit tests — when to use which"
- Completion checklists in all five phase prompts — section
  "Completion checklist" in each of the phase prompt files
- Framework-guide smoke-test templates — `prompts/frameworks/*.md`

This is a paper validation. No real task was executed against any target
codebase. Each scenario describes a bug, the gate that should fire, the
expected verdict, and the escape hatch that a pre-improvement pipeline
left open.

To exercise these scenarios for real, see "Running these as live synthetic
tasks" at the bottom of this document.

## Scenario 1 — Listener subscribes to an unused event

### Bug

Task adds a new event listener that subscribes to a plugin event. The dev
phase creates the listener. The testing phase writes 20 reflection-based unit
tests that directly invoke the listener's handler methods with mock event
objects — all 20 pass. No test dispatches the event through the real global
dispatcher. In the target codebase, the application's custom controllers
bypass the plugin emission path, so no dispatch site exists in the
non-vendor execution path.

### Gates that fire

- **Verification, Check 4 (event-name consistency for pub/sub)** —
  `prompts/verification.md`, section "Check 4: Event-name consistency for
  pub/sub". Grep the listener's event-name string across non-vendor source
  directories of the target codebase. Zero reachable dispatch sites is a
  BLOCKER.
- **Verification, MUST FIX (untested seam) tier** —
  `prompts/verification.md`, section "Untested seams". The runtime dispatch
  path is not exercised by any test. Cannot be downgraded, cannot be
  deferred.
- **Testing phase, completion checklist item 6** —
  `prompts/testing.md`, section "Completion checklist > Items > 6".
  Every (b) framework-plumbing-dependent path requires either a real
  dispatch test or a `[DELEGATED-TO-SMOKE]` marker. Reflection-only
  coverage fails the item.

### Expected verdict

NOT READY. Verification report cites Check 4 as a BLOCKER and raises
the listener as MUST FIX (untested seam).

### Why prior pipeline shipped it

Before the improvements, the verification phase had no mechanical event-name
consistency check. It also had no severity tier that prevented the
"20 passing unit tests" pattern from being read as adequate coverage. A
listener could ship as long as its unit tests were green, regardless of
whether a real dispatch site existed.

## Scenario 2 — Architecture says `foo_bar_hit`, dev wrote `foo_bar`

### Bug

The architecture document uses the string `foo_bar_hit` for an event type
or column value. The dev phase silently writes `foo_bar` instead. The
testing phase asserts `foo_bar` (matching the dev code, not the
architecture), so the test passes for the wrong reason. The delivery smoke
test query uses `foo_bar_hit` (matching the architecture) and returns zero
rows.

### Gates that fire

- **Verification, Check 1 (data-value consistency)** —
  `prompts/verification.md`, section "Check 1: Data-value consistency".
  Grep every introduced or modified string constant across requirements,
  architecture, dev summary, testing summary, delivery doc, source, and
  tests. Mismatch is a BLOCKER. The example in that section is the exact
  shape of this bug.
- **Verification, completion checklist item 5** —
  `prompts/verification.md`, section "Completion checklist > Items > 5".
  Requires recording the result of all four consistency checks; the
  mismatch lands in the recorded output.

### Expected verdict

NOT READY. Verification report quotes both occurrences and refuses the
task until one side is updated.

### Why prior pipeline shipped it

Before the improvements, no mechanical consistency check existed. The
verification phase relied on prose review of the dev summary, which
described the change in its own words and never grepped the actual strings
in the source. The wrong-value test passed, the verification phase saw
green, the delivery smoke test was treated as documentation rather than a
gate (see Scenario 3), and the bug shipped.

## Scenario 3 — Side-effect smoke test written but not executed

### Bug

The delivery doc contains a properly-shaped smoke test — entry-point check
plus side-effect check, framework-idiomatic. The delivery phase doesn't run
it. It treats the smoke test block as a post-deploy checklist for the
operator to execute by hand.

### Gates that fire

- **Delivery phase, section "3.2 Smoke test execution (pre-delivery gate)"** —
  `prompts/delivery.md`. Smoke tests are executed by the delivery phase
  itself, not handed to the operator. Status is NOT READY if execution is
  skipped without an `[UNEXECUTABLE]` justification.
- **Delivery phase, completion checklist items 4, 5, 6** —
  `prompts/delivery.md`, section "Completion checklist > Items".
  - Item 4 — every smoke test must be EXECUTED or marked `[UNEXECUTABLE]`
    with a one-sentence justification.
  - Item 5 — exact stdout/stderr/HTTP/DB output must be recorded.
  - Item 6 — any failed smoke test returns the task to dev.

### Expected verdict

NOT READY at the delivery phase. The phase output is INCOMPLETE because
items 4, 5, 6 cannot be checked off truthfully without execution.

### Why prior pipeline shipped it

Before the improvements, the delivery phase prompt described smoke tests as
post-deploy procedure. There was no pre-delivery execution gate, no
"exact output" recording requirement, and no obligation to bounce a failed
smoke test back to dev. A delivery doc could be marked complete with smoke
tests in a "to do later" state.

## Scenario 4 — Integration test skipped in favor of reflection-only

### Bug

Task adds a new middleware to the stack. The testing phase writes only
reflection-based unit tests that directly invoke the middleware's `handle()`
method with mock request/response objects, declaring stack integration
"covered by direct invocation."

### Gates that fire

- **Testing phase, "Integration tests vs reflection/unit tests" hard rule** —
  `prompts/testing.md`, section "Integration tests vs reflection/unit
  tests — when to use which". Middleware is plumbing-dependent code; at
  least one test must exercise the real pipeline.
- **Testing phase, completion checklist item 6** —
  `prompts/testing.md`, section "Completion checklist > Items > 6".
  No real-dispatch test, no `[DELEGATED-TO-SMOKE]` marker — the box cannot
  be checked.
- **Verification, MUST FIX (untested seam) tier** —
  `prompts/verification.md`, section "Untested seams". Runtime path exists
  but no test exercises it.

### Expected verdict

NOT READY. The testing phase fails its own checklist; if it slips through,
verification raises the seam as MUST FIX.

### Why prior pipeline shipped it

Before the improvements, the testing phase prompt did not enumerate
plumbing-dependent code as a forced category. Reflection-based tests with
high counts of green checks were treated as adequate. Verification had no
"untested seam" tier to escalate the gap.

## Scenario 5 — Phase output missing completion checklist results

### Bug

A task's dev phase subagent writes its output doc without emitting the
completion checklist results section, or emits it with all boxes
unchecked.

### Gates that fire

- **Completion checklist contract** — every phase prompt has a "Contract"
  block stating: "Unchecked boxes (`[ ]`), `[N/A]` without justification,
  and `[x]` without evidence all count as the phase being INCOMPLETE."
  See `prompts/development.md`, `prompts/testing.md`,
  `prompts/verification.md`, `prompts/delivery.md`,
  `prompts/architecture.md` — section "Completion checklist > Contract"
  in each.
- **Verification phase reading the dev summary** — the contract grants
  verification (or the operator, for verification itself) the right to
  refuse any phase output that has missing results, unjustified N/A
  entries, or evidence-free checks.

### Expected verdict

Verification refuses the dev phase as INCOMPLETE and returns NOT READY to
dev for rework. The pipeline does not advance to testing.

### Why prior pipeline shipped it

Before the improvements, phase outputs had no enforced completion contract.
A dev summary that described what was built in prose was acceptable. There
was no explicit list of items the next phase could grep for to confirm the
phase had actually finished its work.

## Scenario 6 — Phase marks checklist item `[N/A]` without justification

### Bug

A task's testing phase marks item 6 (plumbing-dependent coverage) as
`[N/A]` with no one-sentence justification on the same line, or with a
trivially invalid justification like "not applicable" or "unit tests cover
it."

### Gates that fire

- **Completion checklist contract** — `prompts/testing.md`, section
  "Completion checklist > Contract". `[N/A]` without justification = phase
  is INCOMPLETE.
- **Same contract, explicit invalid-justification rule** — "It's a small
  change" and "unit tests cover it" are not valid `[N/A]` justifications
  for integration/smoke items. Those items have dedicated handling
  (`[DELEGATED-TO-SMOKE]` for integration, `[UNEXECUTABLE]` for smoke).

### Expected verdict

The testing phase output is INCOMPLETE. Verification returns NOT READY to
testing for rework.

### Why prior pipeline shipped it

Before the improvements, there was no checklist contract at all. Phase
outputs could omit any field, hand-wave any concern, or skip integration
coverage with an inline excuse. The pipeline had no mechanical place to
catch the excuse.

## Summary table

| # | Scenario                              | Verif Check 1 | Verif Check 4 | MUST FIX seam | Test int. rule | Test checklist | Delivery exec gate | Phase checklist contract |
|---|---------------------------------------|---------------|---------------|---------------|----------------|----------------|--------------------|--------------------------|
| 1 | Listener on unused event              |               | x             | x             |                | x              |                    | x                        |
| 2 | `foo_bar_hit` vs `foo_bar`            | x             |               |               |                |                |                    | x                        |
| 3 | Smoke test written but not executed   |               |               |               |                |                | x                  | x                        |
| 4 | Middleware reflection-only            |               |               | x             | x              | x              |                    | x                        |
| 5 | Dev phase output missing checklist    |               |               |               |                |                |                    | x                        |
| 6 | `[N/A]` without justification         |               |               |               |                | x              |                    | x                        |

## Running these as live synthetic tasks

These scenarios are paper validation. To exercise them against a real
pipeline run, the operator stages each scenario as a one-off task against
a throwaway target codebase and watches the verdict.

### Test target

Use a minimal toy app in a throwaway directory — for plain PHP, a single
`index.php` with two routes is enough; for a framework, the smallest
scaffold the framework supports. Set `WORKSPACE_DIR` in
`motspilot/.motspilot/config` to a scratch directory so artifacts stay
isolated.

### Per-scenario stub

For each scenario, stage a task with a description that forces the bug
shape:

```bash
./motspilot.sh go --task=validation-1 \
  "Add a listener for a plugin event. Write reflection-only unit tests."

./motspilot.sh go --task=validation-2 \
  "Add a counter column. Use foo_bar_hit in the architecture brief, \
   foo_bar in the implementation."

./motspilot.sh go --task=validation-3 \
  "Add a new route with a side-effect smoke test. Have the delivery \
   phase document the smoke test without executing it."

./motspilot.sh go --task=validation-4 \
  "Add a request middleware. Write reflection-only tests for handle()."

./motspilot.sh go --task=validation-5 \
  "Any small change. Have the dev subagent omit the completion \
   checklist results section."

./motspilot.sh go --task=validation-6 \
  "Add a middleware. Have the testing subagent mark item 6 [N/A] \
   with no justification."
```

After each `go`, run the pipeline phases as usual. The operator watches:

1. Which phase issues the verdict.
2. Whether the verdict matches the "Expected verdict" line in the
   corresponding scenario above.
3. Whether the named gate appears by name in the report (e.g., "Check 4",
   "MUST FIX (untested seam)", "completion checklist item 6").

A scenario passes validation when the actual verdict and the cited gate
match this document. A scenario fails validation when the bug ships
through to delivery, or when the verdict cites a different gate than the
one this document predicts.

### Cleanup

After each validation run, archive the task with
`./motspilot.sh archive --task=validation-<n>` and reset the throwaway
target codebase to its pre-task state. Do not keep validation artifacts in
the production workspace.
