# motspilot — Claude Code Reference

## Architecture

motspilot is a 5-phase AI pipeline for adding features to **existing applications** — framework-agnostic.

**Claude Code IS the orchestrator.** When the user says "run motspilot pipeline", Claude Code coordinates all phases using Task subagents. The shell script (`motspilot.sh`) manages named tasks, file state, and auto-archives on completion.

## How to Run the Pipeline

When the user says "run motspilot pipeline" (or "run motspilot", "go motspilot"):

1. Read `motspilot/PIPELINE_ORCHESTRATOR.md` for full instructions
2. Read `motspilot/.motspilot/config` — check `WORKSPACE_DIR` to find where task data lives
   - If `WORKSPACE_DIR` is set (e.g., `"motspilot-data"`): workspace is at `<PROJECT_ROOT>/<WORKSPACE_DIR>/`
   - If empty/unset: workspace is at `motspilot/.motspilot/workspace/`
3. Read `motspilot/.motspilot/current_task` to find the active task name
4. Read the work order: `<workspace>/tasks/<task-name>/pipeline_workorder.md`
5. Read requirements: `<workspace>/tasks/<task-name>/01_requirements.md`
6. Check for framework guide: `motspilot/prompts/frameworks/<FRAMEWORK>.md`
7. **Run Multi-Model Consensus** (Step 1.5 in orchestrator) — fans out requirements to Claude + GPT-4o + Gemini, synthesizes into `00_consensus.md`
8. Run each phase as a Task subagent (general-purpose agent type), including consensus output as context
9. Check `AUTO_APPROVE` in config (default `all` = no pausing; set `none` to pause between phases)
10. Write outputs to `<workspace>/tasks/<task-name>/`
11. **On completion: archive automatically** — run `./motspilot/motspilot.sh archive --task=<name>`

## Phases

| Phase | Prompt | Artifact | Writes code? |
|-------|--------|----------|--------------|
| Consensus | `bin/consensus.php` (auto) | `tasks/<name>/consensus/04_synthesis.md` | No |
| Architecture | `prompts/architecture.md` | `tasks/<name>/02_architecture.md` | No |
| Development | `prompts/development.md` | `tasks/<name>/03_development.md` | Yes |
| Testing | `prompts/testing.md` | `tasks/<name>/04_testing.md` | Yes |
| Verification | `prompts/verification.md` | `tasks/<name>/05_verification.md` | No |
| Delivery | `prompts/delivery.md` | `tasks/<name>/06_delivery.md` | No |

## Framework Guides

Framework-specific knowledge lives in `prompts/frameworks/<name>.md`. Currently available:
- `cakephp.md` — CakePHP 4.x patterns, API reference, verification checks

When a framework guide exists for the configured framework, it is included in every subagent prompt alongside the thinking framework.

## Task Lifecycle

```
pending → in_progress → [auto-archived on completion]
                               ↓ (reactivate)
                        in_progress (re-run phases for bug fixes)
```

## Prompt Engineering Techniques

All phase prompts use these patterns (derived from Claude and Gemini best practices):

- **XML-tagged prompt assembly** — Orchestrator uses `<thinking_framework>`, `<requirements>`, `<consensus>`, `<previous_phases>`, `<task>` tags
- **`<investigate_before_*>` guards** — Each phase has a phase-specific block preventing speculation about unread code
- **`<anti_overengineering>` clauses** — Architecture and Development phases explicitly prevent scope creep
- **`<output_scaling>` blocks** — Architecture, Development, and Delivery scale output depth to feature complexity (small/medium/large)
- **`<self_check>` blocks** — Every phase ends with verification criteria before finalizing output
- **`<blocker_handling>`** — Development phase uses structured BLOCKER markers instead of unrealistic "stop and ask" instructions
- **`<severity_levels>`** — Verification uses a shared taxonomy (CRITICAL / SHOULD FIX / IMPROVE) with clear definitions
- **`<example>` blocks** — Few-shot examples of good vs bad patterns where applicable
- **Quote-grounded findings** — Verification must cite specific file:line and code before judging
- **Context inclusion rules** — Orchestrator sends full text or summaries per phase to manage context window
- **Architecture cross-reference** — Verification compares architecture file map against what was actually built

## Core Philosophy

- Start with the person using the feature, not the code
- Explore the existing codebase before touching anything
- Trace the blast radius of every change
- Build in layers (Foundation → Logic → Interface), verifying each against the architecture
- Think like an attacker about security
- Never greenfield — always integrating into existing apps
- One logical action per migration — never combine unrelated changes

## Commands Reference

```bash
./motspilot.sh go --task=<name> "description"    # Create task + prepare
./motspilot.sh go --task=<name>                  # Re-prepare existing task
./motspilot.sh go --task=<name> --from=<phase>   # Re-run from a phase
./motspilot.sh tasks [--all]                     # List tasks
./motspilot.sh status [--task=<name>]            # Task detail
./motspilot.sh archive --task=<name>             # Archive task (also called automatically)
./motspilot.sh reactivate <name>                 # Restore from archive
./motspilot.sh reset --task=<name>               # Clear phase artifacts
./motspilot.sh view <phase> [--task=<name>]      # View artifact
```

## Structure

```
motspilot/                            # The tool
  motspilot.sh                        # Shell utility (filing system, not engine)
  PIPELINE_ORCHESTRATOR.md            # Claude Code orchestration instructions
  bin/consensus.php                   # Standalone multi-model consensus script (PHP 8+, no framework)
  .env                                # API keys for consensus (ANTHROPIC, OPENAI, GEMINI)
  prompts/                            # Thinking frameworks (one per phase)
  prompts/frameworks/                 # Framework-specific guides (cakephp.md, etc.)
  .motspilot/
    config                            # Project settings (includes WORKSPACE_DIR)
    current_task                      # Active task name
    logs/

<workspace>/                          # WORKSPACE_DIR or .motspilot/workspace/
  tasks/<name>/                       # Active task artifacts
  archive/<name>/                     # Completed task artifacts
```
