# motspilot Pipeline Orchestrator

When the user says **"run motspilot pipeline"**, **"run motspilot"**, or **"go motspilot"**, follow these instructions exactly.

---

## Step 1 — Verify Prerequisites

1. Read the work order file. It is at:
   `motspilot/.motspilot/workspace/tasks/<task-name>/pipeline_workorder.md`

   To find the current task name, read:
   `motspilot/.motspilot/current_task`

2. From the work order, note:
   - **Task name** (you will need this to archive at the end)
   - **Start from phase** (default: architecture)
   - **Project root**, language, framework, test command

3. Read the full requirements:
   `motspilot/.motspilot/workspace/tasks/<task-name>/01_requirements.md`

4. Read `motspilot/.motspilot/config` for project settings.

5. Check for a framework guide:
   `motspilot/prompts/frameworks/<FRAMEWORK>.md`
   If it exists, you will include it in every subagent prompt. If not, the subagents work without framework-specific guidance.

6. Check the task checkpoint:
   `motspilot/.motspilot/workspace/tasks/<task-name>/checkpoint`
   - If it contains a phase with `|pending`, ask the user: "Resume from `[phase]` or start fresh from architecture?"

If prerequisites are missing, tell the user to run `./motspilot.sh go --task=<name> "description"` first.

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
