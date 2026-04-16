# motspilot Pipeline Orchestrator

When the user says **"run motspilot pipeline"**, **"run motspilot"**, or **"go motspilot"**, follow these instructions exactly.

---

## Step 1 — Verify Prerequisites

1. Read the config for project settings and workspace location:
   `motspilot/.motspilot/config`
   - Note the `WORKSPACE_DIR` setting. If set, the workspace base is `<WORKSPACE_DIR>/` (relative to project root). Otherwise, the workspace is at `motspilot/.motspilot/workspace/`.
   - Use `<workspace>` below to refer to the resolved workspace base path.

2. Find the current task name:
   `motspilot/.motspilot/current_task`

3. Read the work order file:
   `<workspace>/tasks/<task-name>/pipeline_workorder.md`
   - The work order also contains a **Workspace** field confirming the path.

4. From the work order, note:
   - **Task name** (you will need this to archive at the end)
   - **Start from phase** (default: architecture)
   - **Project root**, language, framework, test command

5. Read the full requirements:
   `<workspace>/tasks/<task-name>/01_requirements.md`

6. Check for a framework guide:
   `motspilot/prompts/frameworks/<FRAMEWORK>.md`
   If it exists, you will include it in every subagent prompt. If not, the subagents work without framework-specific guidance.

7. Check the task checkpoint:
   `<workspace>/tasks/<task-name>/checkpoint`
   - If it contains a phase with `|pending`, ask the user: "Resume from `[phase]` or start fresh from architecture?"

If prerequisites are missing, tell the user to run `./motspilot.sh go --task=<name> "description"` first.

---

## Step 1.5 — Multi-Model Consensus (Pre-Pipeline)

Before starting the subagent phases, run the **Multi-Model Consensus** step. This fans out the full requirements to 3 LLMs (Claude, GPT-4o, Gemini) in parallel, collects their responses, and synthesizes a single authoritative starting point via a Claude judge.

### How to run it

1. Build a consensus prompt from the requirements. Write it to a temporary file:
   `<workspace>/tasks/<task-name>/consensus/prompt.txt`

   The prompt should be:
   ```
   You are a senior software architect and developer.

   Below are the full requirements for a feature/project. Analyze them carefully and produce a comprehensive technical plan covering:

   1. Architecture overview — key components, data flow, file structure
   2. Implementation approach — step-by-step build order, key decisions
   3. Potential pitfalls and edge cases to watch for
   4. Specific technical recommendations for the tech stack described

   Be thorough and specific. Include concrete details: file names, function signatures, data structures, configuration values, and code snippets where helpful. Your output will be used as the starting context for an AI development pipeline that runs architecture, development, testing, verification, and delivery phases.

   If the requirements are ambiguous on any point, state your assumption explicitly before proceeding.

   === REQUIREMENTS ===
   [Full contents of tasks/<task-name>/01_requirements.md]

   === PROJECT CONTEXT ===
   Language: [LANGUAGE]
   Framework: [FRAMEWORK]
   Project root: [PROJECT_ROOT]
   ```

2. Run the standalone consensus script via Bash:
   ```bash
   php motspilot/bin/consensus.php \
     --prompt-file=<workspace>/tasks/<task-name>/consensus/prompt.txt \
     --phase=pre-pipeline \
     --output-dir=<workspace>/tasks/<task-name>/consensus/
   ```

3. Check the exit code:
   - **Exit 0**: Success. The `consensus/` folder now contains all outputs.
   - **Exit 1**: All APIs failed. Log a warning, show the user `consensus/consensus.log`, and continue without consensus (the pipeline still works, just without the multi-model head start).
   - **Exit 2**: Bad config (missing .env or prompt). Show the error from `consensus/consensus.log` and ask the user to fix it, or continue without consensus.

4. Log status to the user:
   ```
   Multi-Model Consensus: [OK — 3/3 models responded | PARTIAL — 2/3 models responded | SKIPPED — see consensus.log]
   Consensus files saved to: <workspace>/tasks/<task-name>/consensus/
     01_claude.md      — Claude raw response
     02_gpt4o.md       — GPT-4o raw response
     03_gemini.md      — Gemini raw response
     04_synthesis.md   — Unified synthesis (all 3 merged)
     05_differences.md — Unique contributions per AI
     consensus.log     — Execution log
   ```

### Consensus output files explained

| File | Purpose |
|------|---------|
| `01_claude.md` | Full raw response from Claude |
| `02_gpt4o.md` | Full raw response from GPT-4o |
| `03_gemini.md` | Full raw response from Gemini |
| `04_synthesis.md` | Judge-synthesized unified output (best of all 3 merged into one) |
| `05_differences.md` | **Unique contributions only** — what each AI pointed out that the others missed. Ignores common points. Highlights conflicts. |
| `consensus.log` | Timestamped execution log |

### How consensus output is used

When `04_synthesis.md` exists and is non-empty, include it in the `<consensus>` tag in every subagent prompt (see prompt template in Step 2). If the consensus folder does not exist or `04_synthesis.md` is empty, omit the `<consensus>` tag entirely — the pipeline runs normally without it.

---

## Step 2 — Run Each Phase in Sequence

Run the 5 phases in order: **architecture → development → testing → verification → delivery**

Honor the **start from phase** value from the work order — skip earlier phases if resuming mid-pipeline.

### All artifact paths use the task directory:
```
motspilot/.motspilot/workspace/tasks/<task-name>/
```

### How to Execute a Phase

For each phase, use the **Task tool** (`subagent_type: general-purpose`).

**Assemble the subagent prompt from these parts, using XML tags for unambiguous parsing:**

```xml
<motspilot_phase name="[PHASE NAME]">

<thinking_framework>
[Full contents of motspilot/prompts/<phase>.md]
</thinking_framework>

<framework_guide>
[Full contents of motspilot/prompts/frameworks/<FRAMEWORK>.md — or "No framework guide available. Use your knowledge of the project's framework based on the codebase exploration." if no guide exists]
</framework_guide>

<project_config>
Project root: [PROJECT_ROOT from config]
Language: [LANGUAGE from config]
Language version: [LANGUAGE_VERSION from config]
Framework: [FRAMEWORK from config]
Test command: [TEST_CMD from config]
App URL: [APP_URL from config]
</project_config>

<requirements>
[Full contents of tasks/<task-name>/01_requirements.md]
</requirements>

<consensus>
[Full contents of tasks/<task-name>/consensus/04_synthesis.md — or omit this tag entirely if file is missing/empty]

Note: This consensus was synthesized from Claude, GPT-4o, and Gemini analyzing the requirements independently. Use it as a strong starting point but apply your own judgment — the phase-specific thinking framework takes priority over consensus recommendations.
</consensus>

<previous_phases>
[For each completed previous phase, full contents labeled by phase name]
</previous_phases>

<task>
[Phase-specific task — see below]

Write your final output to:
motspilot/.motspilot/workspace/tasks/<task-name>/[NN_phase.md]
</task>

</motspilot_phase>
```

### Context inclusion rules

Not every phase needs the full output of every previous phase. To manage context window size and reduce noise, use these rules for `<previous_phases>`:

| Current Phase | Include full text | Include summary only |
|---------------|-------------------|----------------------|
| Architecture | requirements, consensus | — |
| Development | requirements, architecture `<summary>` block | consensus (key points only) |
| Testing | development `<summary>` block | architecture (File Map section only) |
| Verification | development `<summary>` block | architecture (File Map only), testing (results only) |
| Delivery | verification `<summary>` block | development (file list + manual steps only) |

**Directive-not-narrative rule:** Subagent prompts must read like a **work order**, not a diary. When including previous phase output, extract the **state snapshot** — decisions made, files touched, constraints inherited — not the history of iterations. The `<analysis>` block from each phase is the reasoning trail; it stays on disk in the full artifact but is never injected into downstream prompts.

**"Summary only"** means: extract only the `<summary>` block (or its File Map, test results, and manual steps subsections) — not the full narrative or `<analysis>` block. This keeps later phases focused on what they actually need.

If a subagent needs more context about a previous phase, it can read the full artifact file (including `<analysis>`) directly from the task directory.

---

## Task-Notification Parsing

Every phase subagent emits a `<task-notification>` XML envelope at the end of its response. After each phase completes, check the notification to decide the next action:

```xml
<task-notification>
  <status>completed|failed</status>
  <summary>One-line description</summary>
  <result>READY|READY WITH NOTES|NOT READY|BLOCKED</result>
</task-notification>
```

| `<status>` | `<result>` | Action |
|-------------|-----------|--------|
| `completed` | `READY` | Proceed to next phase |
| `completed` | `READY WITH NOTES` | Proceed (verify notes are IMPROVE-tier only) |
| `completed` | `NOT READY` | Re-run the phase or escalate to user |
| `failed` | `BLOCKED` | Show `<summary>` to user, ask for guidance |

If the subagent does not emit a `<task-notification>`, treat it as a warning — check the artifact file and completion checklist manually.

---

## Completion Checklist Results in Phase Outputs

Every phase prompt now ends with a structured `<completion_checklist>` block containing 12 numbered verifiable items (replacing the older prose `<self_check>`). The phase subagent must emit results — not a verbatim copy of the instructions — in its phase output doc, using one of these forms per item:

- `[x] done — <evidence>`
- `[N/A] — <justification>`
- `[ ] not done — <reason>`

When you (the orchestrator) review a completed phase artifact:

- **Unchecked items count as the phase being incomplete** — re-run the phase with feedback if any item is missing.
- **Items marked `[x]` without evidence count as incomplete** — the model must point at a file, command, or quoted code, not just claim done.
- **`[N/A]` without justification counts as incomplete** — every N/A needs one sentence saying why the item does not apply.

If the completion checklist is incomplete, do not advance to the next phase — re-run with feedback indicating which items need evidence or justification.

---

## Phase Definitions

### Phase 2: Architecture

**Artifact**: `tasks/<task-name>/02_architecture.md`
**Previous context**: requirements only

**Subagent task**:
```
Apply the architecture thinking framework above to design a complete implementation
plan for this feature in the existing codebase.

You MUST explore the codebase before designing anything:
- Use Glob and Grep to find relevant existing files
- Read key files to understand existing patterns
- Do NOT assume anything about the codebase structure

If a framework guide is provided above, use it to understand the framework's
conventions, naming patterns, and API specifics. If not, discover them from the code.

Produce a comprehensive architecture document covering:
user experience, codebase analysis, blast radius, data design,
component design, security, failure modes, alternatives considered,
file map (new files + modified files), and rollback plan.

Do NOT write any code. Design only.

Write your output to:
motspilot/.motspilot/workspace/tasks/<task-name>/02_architecture.md
```

---

### Phase 3: Development

**Artifact**: `tasks/<task-name>/03_development.md`
**Previous context**: requirements + architecture

**Subagent task**:
```
Apply the development thinking framework above to implement this feature.

IMPORTANT: Read every existing file you plan to modify before changing it.
Follow the architecture document exactly. Make surgical changes — do not
restructure or reformat existing code.

If a framework guide is provided above, follow its specific patterns for
migrations, models, controllers, templates, and routes.

Build in tiny loops:
1. Database/schema layer (migration → model → relationships)
2. Business logic (service/module methods)
3. Interface (controller/handler → templates/views)

Actually create and modify files in the codebase. Use the Write and Edit tools.

Produce a development summary document listing:
- Every file created (with full path)
- Every file modified (with what changed and why)
- Manual steps required (migrations to run, caches to clear)
- Any deviations from the architecture and why

Write your summary to:
motspilot/.motspilot/workspace/tasks/<task-name>/03_development.md
```

---

### Phase 4: Testing

**Artifact**: `tasks/<task-name>/04_testing.md`
**Previous context**: requirements + architecture + development

**Subagent task**:
```
Apply the testing thinking framework above to write comprehensive tests.

If a framework guide is provided above, follow its specific test patterns,
fixture conventions, and security test templates.

Test priority order:
1. Integration safety — existing tests still pass
2. Security (auth, CSRF, mass assignment, IDOR)
3. Business logic edge cases
4. Happy path
5. Error paths

For each new route/action, test:
- GET loads (200)
- Auth required (redirect when not logged in)
- Valid POST changes data
- Invalid POST shows errors
- CSRF missing returns 403
- Another user's data is rejected (IDOR)

Integration-vs-unit hard rule:
For any runtime path that runs inside framework plumbing (events, middleware,
observers, lifecycle hooks, schedulers, queues), at least one test MUST exercise
the real dispatch mechanism. Reflection-based unit tests that directly invoke
handler methods are NOT sufficient. Driver-gated branches and SQL-string-generation
assertions are acceptable patterns for surviving test-DB-vs-prod-DB limitations.

Actually write the test files to the codebase. Use the Write and Edit tools.

Produce a testing summary listing all test files created/modified and strategy
rationale. The summary MUST include a runtime-path classification table
labeling each runtime path as (a) pure-logic, (b) plumbing-dependent, or
(c) external-I/O — so verification can cross-check coverage.

The testing prompt's <completion_checklist> requires the subagent to emit
12 numbered results in the output doc as `[x] done — evidence`,
`[N/A] — justification`, or `[ ] not done — reason`.

Write your summary to:
motspilot/.motspilot/workspace/tasks/<task-name>/04_testing.md
```

---

### Phase 5: Verification

**Artifact**: `tasks/<task-name>/05_verification.md`
**Previous context**: requirements + architecture + development + testing

**Subagent task**:
```
Apply the verification thinking framework above. Be skeptical — read actual code,
not just the development summary.

If a framework guide is provided above, run EVERY check in its verification
section. Do not skip any.

General checks (apply to all frameworks):
- Correct framework API usage for the project's version
- Unescaped template output (XSS vectors)
- Direct request superglobal access instead of framework API
- Mass assignment vulnerabilities in models
- Raw HTML forms instead of framework form helpers
- IDOR (user can access another user's data)
- Broken existing tests

Severity taxonomy: CRITICAL / MUST FIX (untested seam) / SHOULD FIX / IMPROVE.
- MUST FIX (untested seam) is non-downgradeable. Apply to any runtime code path
  that exists in the shipped change but is not exercised by any test (unit,
  integration, or smoke). It cannot be deferred as a follow-up note.
- Cross-check the testing phase's runtime-path classification table against
  what was actually built. Plumbing-dependent paths require an integration test
  that exercises the real dispatch mechanism — reflection-based handler tests
  do not satisfy this.

Run the four mechanical consistency checks across artifacts and source:
1. Data-value consistency — string constants, enum values, column values, and
   config keys agree across all task docs and the source code.
2. Symbol-name consistency — constant, method, class, and file-path names match
   across docs and code.
3. Timezone consistency — for any time-bucketed column, the write-side and
   read-side must agree explicitly on the timezone.
4. Event-name consistency — for pub/sub systems, every listener must have at
   least one matching dispatch site in the target codebase (NOT only in
   vendor/). Flag dangling listeners as MUST FIX (untested seam).

Verdicts:
- READY               — no CRITICAL, MUST FIX, or SHOULD FIX issues
- READY WITH NOTES    — restricted to IMPROVE-tier notes ONLY (not CRITICAL,
                        not MUST FIX, not SHOULD FIX)
- NOT READY           — any CRITICAL, MUST FIX, or SHOULD FIX

Produce a verification report listing issues grouped by severity. The
verification prompt's <completion_checklist> requires the subagent to emit
12 numbered results in the output doc as `[x] done — evidence`,
`[N/A] — justification`, or `[ ] not done — reason`.

Write your report to:
motspilot/.motspilot/workspace/tasks/<task-name>/05_verification.md
```

---

### Phase 6: Delivery

**Artifact**: `tasks/<task-name>/06_delivery.md`
**Previous context**: all previous phases

**Subagent task**:
```
Apply the delivery thinking framework. Every deployment step must have an undo.

If a framework guide is provided above, use its specific deployment commands,
cache clearing steps, and rollback procedures.

Smoke-test execution gate (delivery prompt section 3.2):
- Smoke tests are NOT a post-deploy operator checklist. The delivery phase
  EXECUTES every smoke test before marking the task complete.
- Each smoke test requires BOTH:
  (a) an entry-point check — HTTP status, CLI exit code, queue arrival
  (b) a side-effect check — DB row, mail catcher (Mailpit/MailHog/smtp4dev)
      message, file written, cache key updated, external API called
- Status-code-only tests count as zero tests.
- For any smoke test that cannot be executed in the current environment, tag
  it [UNEXECUTABLE] with a one-sentence justification and surface it in the
  delivery doc for the operator to run post-deploy.

Produce a delivery document containing:
1. What changed (1-2 sentence summary)
2. Files changed (new, modified, deleted)
3. Deployment steps (backup → pull → dependencies → migrate → cache clear → verify)
4. Rollback steps (exact commands)
5. Configuration changes (or "none")
6. Git commit message (conventional format)
7. Smoke-test execution results (each with entry-point + side-effect evidence,
   or [UNEXECUTABLE] with justification)
8. What to watch after deployment
9. Known limitations / deferred work

The delivery prompt's <completion_checklist> requires the subagent to emit
12 numbered results in the output doc as `[x] done — evidence`,
`[N/A] — justification`, or `[ ] not done — reason`.

Write your delivery document to:
motspilot/.motspilot/workspace/tasks/<task-name>/06_delivery.md
```

---

## Step 3 — Human Approval Between Phases

Check `AUTO_APPROVE` in `.motspilot/config` to determine behavior:

- **`AUTO_APPROVE=all`** (default): After each phase, show a brief one-line status (e.g. "Phase [NAME] complete — continuing to [NEXT PHASE]") and proceed immediately to the next phase without waiting for approval.
- **`AUTO_APPROVE=none`**: Pause after every phase and ask for approval.
- **Comma-separated phase names** (e.g. `"architecture,delivery"`): Pause only after the listed phases; auto-approve all others.

When pausing for approval, show:

```
Phase [NAME] complete

Key outputs:
- [bullet 1]
- [bullet 2]
- [bullet 3]

Approve and continue to [NEXT PHASE]?
  [A] Approve
  [R] Reject — re-run with feedback
  [V] View full artifact
```

On rejection: ask what to change, then re-run the phase with feedback appended to the task prompt.

---

## Step 4 — Checkpointing

After each approved phase, update the checkpoint:

```bash
echo "<phase>|approved" > motspilot/.motspilot/workspace/tasks/<task-name>/checkpoint
```

---

## Step 5 — Completion and Auto-Archive

When all phases are approved:

1. Archive the task automatically using the Bash tool:
   ```bash
   ./motspilot/motspilot.sh archive --task=<task-name>
   ```
   (Use the task name from the work order — it is always in the **Task name** field.)

2. Show a completion summary:
   ```
   Pipeline complete!

   Task: <task-name>

   Artifacts:
     02_architecture.md
     03_development.md
     04_testing.md
     05_verification.md
     06_delivery.md

   Task has been archived automatically.

   To reactivate later (e.g., for a bug fix):
     ./motspilot.sh reactivate <task-name>
     ./motspilot.sh go --task=<task-name> --from=development

   Next: Review deployment steps in tasks/<task-name>/06_delivery.md
   ```

---

## Optional: Parallel Multi-Dimensional Review (Medium/Large Features)

For medium or large features (>5 new files or >300 lines of new code), the orchestrator MAY fan out Architecture and Verification into 3 parallel specialist subagents. This is optional — skip for small features.

### Architecture — 3 lenses

Spawn 3 Task subagents concurrently, each with the same requirements + consensus but a different focus:

1. **Integration fit** — "Does this design match existing patterns? Will it feel native to the codebase?"
2. **Blast radius** — "What existing code, tables, or features could break if this ships?"
3. **Testability** — "Can we verify every seam of this design? Where are the testing gaps?"

Wait for all 3 to complete (do NOT cancel siblings on failure — all findings are valuable). Merge their outputs into a single `02_architecture.md`.

### Verification — 3 lenses

1. **Correctness** — "Does the code do what the requirements asked for?"
2. **Consistency** — "Does the code match what the architecture document promised?"
3. **Regression** — "Did any existing functionality break in the files that were touched?"

Same merge pattern as Architecture. All 3 must complete before the verdict is synthesized.

### When to use parallel review

Use it when the feature is complex enough that a single reviewer would miss things. Skip it when:
- The feature is small (<5 files, <300 lines)
- Token budget is constrained
- The feature is a bug fix or minor enhancement

---

## Fork vs Spawn Heuristic

When deciding whether to delegate work to a Task subagent during a phase:

**Fork a Task subagent when:**
- The investigation will read >5 files (protect the main context from the reads)
- The output is a one-shot answer (e.g., "which files touch the users table?")
- You can fully state the question before starting

**Do the work inline when:**
- You need to iterate on intermediate results
- The user might interrupt or redirect mid-investigation
- The work involves a single file or simple lookup

---

## Memory Staleness Caveat

When referencing information from motspilot's auto-memory (topic files in the project memory directory), be aware that memories older than 1 day are point-in-time observations, not live state. Claims about code behavior, file:line citations, or architecture decisions may be outdated.

Before acting on a memory that names a specific function, file, or flag:
- If it names a file path: check the file exists.
- If it names a function or flag: grep for it.
- If the user is about to act on your recommendation: verify first.

Run `./motspilot.sh mem-check` to check memory index health (line/byte caps and topic staleness).

---

## Phase Heartbeats

When a phase subagent has been running for more than 30 seconds, emit a brief progress line to the user so long-running phases are observable:

```
[hh:mm:ss] Architecture phase still running... (reading codebase)
[hh:mm:ss] Development phase still running... (implementing Layer 2: Logic)
[hh:mm:ss] Testing phase still running... (writing security tests)
```

This is not a retry — just progress visibility. One line every ~30 seconds is sufficient.

---

## Error Handling

- **Phase produces empty output**: Tell the user, offer to re-run with additional context
- **Phase output has unchecked completion-checklist items**: Re-run the phase with feedback indicating which numbered items need evidence or justification.
- **Verification returns NOT READY**: Show the issues, ask: re-run development? fix manually? skip?
- **Verification returns READY WITH NOTES**: Verify the notes are IMPROVE-tier only. If any CRITICAL, MUST FIX (untested seam), or SHOULD FIX issue is present in the report, treat as NOT READY regardless of the verdict label.
- **Verification flags MUST FIX (untested seam)**: This tier is non-downgradeable. Do NOT proceed to delivery — re-run development or testing to add the missing test coverage. Do not record it as a follow-up note.
- **Delivery smoke test marked [UNEXECUTABLE]**: Acceptable if the justification is environmental (e.g., missing prod credentials, no mail catcher in CI). Surface these in the completion summary so the operator runs them post-deploy.
- **Delivery smoke test status-code-only (no side-effect check)**: Reject. Re-run delivery with feedback that smoke tests must include both an entry-point check and a side-effect check.
- **Archive command fails**: Tell the user to run `./motspilot.sh archive --task=<name>` manually
- **Requirements missing**: Ask user to run `./motspilot.sh go --task=<name> "description"` first
