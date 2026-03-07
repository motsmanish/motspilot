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

   Be thorough and specific. Your output will be used as the starting context for an AI development pipeline that runs architecture, development, testing, verification, and delivery phases.

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

When `04_synthesis.md` exists and is non-empty, include it as **additional context** in every subagent prompt. Add this section after `=== REQUIREMENTS ===` and before `=== PREVIOUS PHASE OUTPUTS ===`:

```
=== MULTI-MODEL CONSENSUS (Pre-Pipeline Analysis) ===
[Full contents of tasks/<task-name>/consensus/04_synthesis.md]

Note: This consensus was synthesized from Claude, GPT-4o, and Gemini analyzing the
requirements independently. Use it as a strong starting point but apply your own
judgment — the phase-specific thinking framework takes priority over consensus
recommendations.

For unique insights each AI contributed, see: consensus/05_differences.md
```

If the consensus folder does not exist or `04_synthesis.md` is empty, simply omit this section — the pipeline runs normally without it.

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

**Assemble the subagent prompt from these parts:**

```
=== MOTSPILOT PHASE: [PHASE NAME] ===

=== THINKING FRAMEWORK ===
[Full contents of motspilot/prompts/<phase>.md]

=== FRAMEWORK GUIDE ===
[Full contents of motspilot/prompts/frameworks/<FRAMEWORK>.md — or "No framework guide available. Use your knowledge of the project's framework based on the codebase exploration." if no guide exists]

=== PROJECT CONFIGURATION ===
Project root: [PROJECT_ROOT from config]
Language: [LANGUAGE from config]
Language version: [LANGUAGE_VERSION from config]
Framework: [FRAMEWORK from config]
Test command: [TEST_CMD from config]
App URL: [APP_URL from config]

=== REQUIREMENTS ===
[Full contents of tasks/<task-name>/01_requirements.md]

=== MULTI-MODEL CONSENSUS (Pre-Pipeline Analysis) ===
[Full contents of tasks/<task-name>/consensus/04_synthesis.md — or omit this section if file is missing/empty]

=== PREVIOUS PHASE OUTPUTS ===
[For each completed previous phase, full contents labeled by phase name]

=== YOUR TASK ===
[Phase-specific task — see below]

Write your final output to:
motspilot/.motspilot/workspace/tasks/<task-name>/[NN_phase.md]
```

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
1. Security (auth, CSRF, mass assignment, IDOR)
2. Business logic edge cases
3. Happy path
4. Error paths

For each new route/action, test:
- GET loads (200)
- Auth required (redirect when not logged in)
- Valid POST changes data
- Invalid POST shows errors
- CSRF missing returns 403
- Another user's data is rejected (IDOR)

Actually write the test files to the codebase. Use the Write and Edit tools.

Produce a testing summary listing all test files created/modified and strategy rationale.

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

Produce a verification report: READY or NOT READY, with issues by severity.

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

Produce a delivery document containing:
1. What changed (1-2 sentence summary)
2. Files changed (new, modified, deleted)
3. Deployment steps (backup → pull → dependencies → migrate → cache clear → verify)
4. Rollback steps (exact commands)
5. Configuration changes (or "none")
6. Git commit message (conventional format)
7. What to watch after deployment
8. Known limitations / deferred work

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

## Error Handling

- **Phase produces empty output**: Tell the user, offer to re-run with additional context
- **Verification returns NOT READY**: Show the issues, ask: re-run development? fix manually? skip?
- **Archive command fails**: Tell the user to run `./motspilot.sh archive --task=<name>` manually
- **Requirements missing**: Ask user to run `./motspilot.sh go --task=<name> "description"` first
