# motspilot — prompt engineering techniques

Each phase prompt under `prompts/` (and each framework guide under `prompts/frameworks/`) layers in the techniques below. They evolved from running the pipeline on real production work and watching where single-model agents quietly broke things.

Grouped by concern:

- [Structure](#structure) — how prompts are organized
- [Reasoning gates](#reasoning-gates) — what the AI is forced to think about (or forced to skip)
- [Output discipline](#output-discipline) — how outputs are shaped so downstream phases can consume them
- [Quality tiers](#quality-tiers) — how severity, confidence, and exclusion work
- [Cross-phase contracts](#cross-phase-contracts) — rules that span more than one phase

---

## Structure

- **YAML frontmatter** — Machine-readable metadata on every prompt (`phase`, `order`, `writes_code`, `artifact`, `requires`, `framework_guide`, `output_scaling`, `allowed_tools`, `model`). Parsed by the orchestrator with `yq` v4.52+.
- **XML-tagged prompt assembly** — Orchestrator wraps each section (`<thinking_framework>`, `<requirements>`, `<consensus>`, `<previous_phases>`, `<task>`, etc.) in XML tags for unambiguous parsing. See `prompts/_xml_tags.md` for the canonical tag list.
- **`<analysis>` / `<summary>` output split** — Every phase produces two XML blocks. `<analysis>` is scratch work (stays on disk, not forwarded to downstream phases). `<summary>` is the clean deliverable downstream phases read. Context forwarding uses summaries, not full reasoning history.
- **`<task-notification>` envelope** — Every phase emits a structured XML completion signal parsed by the orchestrator.
- **Per-phase model routing** — The `model:` frontmatter field (`opus` | `sonnet` | `haiku`) is passed through to the Task tool when spawning the phase subagent. Defaults: Architecture → `opus` (design trade-offs, blast-radius reasoning); Development / Testing / Verification / Delivery → `sonnet` (routine code generation + mechanical checks).
- **Directive-not-narrative context** — Subagent prompts receive `<summary>` blocks (state snapshots), not full reasoning history. Full artifacts stay on disk for on-demand reading.

## Reasoning gates

- **`<hard_constraints>` block** — Non-negotiable rules at the top of every prompt, read before any creative work begins. Prevents the most damaging failure modes before the AI has a chance to over-confidently propose them.
- **`<investigate_before_*>` guards** — Each phase has a phase-specific block (`<investigate_before_designing>`, `<investigate_before_coding>`, `<investigate_before_documenting>`) preventing speculation about unread code.
- **`<anti_overengineering>` clauses** — Architecture and Development phases explicitly prevent scope creep and premature abstraction.
- **`<one_in_progress>` rule** — Development enforces one WIP item at a time. Each layer includes a `**Success signal:**` line defining when to advance.
- **`<blocker_handling>`** — Development uses structured BLOCKER markers (dual-form: imperative + present-continuous) instead of unrealistic "stop and ask" instructions that an autonomous agent cannot follow.
- **Assumption-gating** — Ambiguous requirements must be stated explicitly, never silently filled in.
- **Investigate-before-acting** — Verification must read every file before judging; Development must complete every planned file before declaring done.

## Output discipline

- **`<output_scaling>` blocks** — Architecture, Development, and Delivery scale output depth to feature complexity (small / medium / large).
- **`<completion_checklist>` blocks** — Every phase ends with a structured 12-item numbered checklist (replacing the older prose `<self_check>`). The phase subagent must emit results in its phase output doc as `[x] done — evidence`, `[N/A] — justification`, or `[ ] not done — reason`. Unchecked items, missing evidence, and unjustified N/A count as the phase being incomplete.
- **Few-shot `<example>` blocks** — Demonstrate good vs bad output patterns where the contrast matters.
- **`<tool_affinity>` rules** — Development and framework guides route AI toward correct tools (Grep over `Bash(grep)`, Edit over `Bash(sed)`, etc.). Framework guides include `<framework_tool_affinity>` blocks for ecosystem-specific patterns.
- **Quote-grounded findings** — Verification must quote specific code lines (file:line + the code itself) before making judgments. Findings without file:line + code evidence are invalid.
- **Terse verdict first** — Verification's `<summary>` starts with `VERDICT: READY | READY WITH NOTES | NOT READY — <reason>` as its first line. The reader sees the bottom line before reading any analysis.
- **5–30 unit decomposition** — Architecture decomposes large features into 5–30 discrete implementation units, each independently verifiable.

## Quality tiers

- **Severity levels** — Verification uses a shared taxonomy with clear definitions: **CRITICAL / MUST FIX (untested seam) / SHOULD FIX / IMPROVE**. **MUST FIX (untested seam)** is a non-downgradeable tier between CRITICAL and SHOULD FIX, applied to any runtime code path that exists in the shipped change but is not exercised by any test (unit, integration, or smoke). It cannot be deferred as a follow-up note.
- **Confidence scoring** — Every Verification finding carries a confidence score (1–10). Findings below 7 are demoted to NOTE (non-blocking). A dated `<hard_exclusions>` list suppresses known false-positive patterns.
- **`<consistency_checks>`** — Verification runs four mechanical grep-level checks across task artifacts and source code:
    - **Data-value consistency** — string constants, enum values, column values, config keys agree across all docs and code
    - **Symbol-name consistency** — constant/method/class/file-path names
    - **Timezone consistency** — for time-bucketed columns, write-side and read-side must agree explicitly
    - **Event-name consistency** — for pub/sub systems, every listener has at least one matching dispatch site in the target codebase, not only in `vendor/`
- **Adversarial anti-patterns** — Verification includes guards against "verification avoidance" and "seduced by 80%" failure modes, with `<before_pass>` and `<before_fail>` checklists.
- **Constants discipline** — Development greps for existing constants before coding domain values (statuses, tiers, roles); Verification flags duplicated or missing constants as SHOULD FIX.
- **`READY WITH NOTES` restriction** — Verification's `READY WITH NOTES` verdict is restricted to IMPROVE-tier notes only. Any CRITICAL, MUST FIX, or SHOULD FIX issue forces NOT READY.
- **Completeness contracts** — Verification must read every file claimed in architecture; Development must complete every planned file.

## Cross-phase contracts

- **Smoke-test execution gate (Delivery)** — Delivery **executes** every smoke test before marking the task complete (not a post-deploy operator checklist). Each smoke test requires BOTH an entry-point check (HTTP status, CLI exit, queue arrival) AND a side-effect check (DB row, mail catcher message, file written, cache key updated, external API called). Status-code-only tests count as zero tests. Tests that cannot run in the environment are tagged `[UNEXECUTABLE]` with a one-sentence justification and surfaced for the operator. Smoke tests use dual-form naming (imperative + present-continuous).
- **Entry-point classification (Delivery)** — Before writing a smoke test, the AI must classify the touched surface (GET-safe action / state-changing HTTP / webhook / CLI / cron / queue / event listener) and pick the matching entry-point mechanism. The curl-GET template only applies to read-only surfaces.
- **Integration-vs-unit hard rule (Testing)** — For any runtime path that runs inside framework plumbing (events, middleware, observers, lifecycle hooks, schedulers, queues), at least one test must exercise the real dispatch mechanism. Reflection-based unit tests directly invoking handler methods are NOT sufficient. The testing summary must include a runtime-path classification table (pure-logic / plumbing-dependent / external-I/O) so verification can cross-check coverage.
- **Architecture cross-reference** — Verification compares the architecture file map against what was actually built.
- **Parallel 3-lens review** — (Optional, medium/large features) Architecture and Verification can fan out into 3 specialist subagents (integration-fit / blast-radius / testability for Architecture; correctness / consistency / regression for Verification). All 3 complete — no sibling cancellation.
- **Phase heartbeats** — Orchestrator emits progress lines every ~30s during long phases so the operator can tell whether the pipeline is working or stuck.
- **Fork vs spawn heuristic** — Orchestrator documentation includes guidance on when to fork (new Task) vs spawn (subagent within a phase).

---

## Where each technique lives

| Technique | Primary file |
|-----------|--------------|
| Hard constraints, output split, completion checklist | every `prompts/<phase>.md` |
| YAML frontmatter parser | `motspilot.sh` (via `yq`) |
| XML tag canonical list | `prompts/_xml_tags.md` |
| Severity levels, confidence scoring, consistency checks | `prompts/verification.md` |
| Smoke-test execution gate, entry-point classification | `prompts/delivery.md` |
| Integration-vs-unit hard rule | `prompts/testing.md` |
| 5–30 unit decomposition, parallel 3-lens review | `prompts/architecture.md` |
| One-in-progress, anti-overengineering, blocker handling | `prompts/development.md` |
| Framework-specific tool affinity | `prompts/frameworks/<name>.md` |

If you're adding a new technique, group it under the matching concern above and link the source prompt file so the next maintainer can find where it's enforced.
