# motspilot — Claude Code Reference

## Architecture

motspilot is a 5-phase AI pipeline for adding features to **existing applications** — framework-agnostic.

**Claude Code IS the orchestrator.** When the user says "run motspilot pipeline", Claude Code coordinates all phases using Task subagents. The shell script (`motspilot.sh`) manages named tasks, file state, and auto-archives on completion.

## How to Run the Pipeline

When the user says "run motspilot pipeline" (or "run motspilot", "go motspilot"):

1. Read `motspilot/PIPELINE_ORCHESTRATOR.md` for full instructions
2. Read `motspilot/.motspilot/current_task` to find the active task name
3. Read the work order: `motspilot/.motspilot/workspace/tasks/<task-name>/pipeline_workorder.md`
4. Read requirements: `motspilot/.motspilot/workspace/tasks/<task-name>/01_requirements.md`
5. Check for framework guide: `motspilot/prompts/frameworks/<FRAMEWORK>.md`
6. Run each phase as a Task subagent (general-purpose agent type)
7. Check `AUTO_APPROVE` in config (default `all` = no pausing; set `none` to pause between phases)
8. Write outputs to `motspilot/.motspilot/workspace/tasks/<task-name>/`
9. **On completion: archive automatically** — run `./motspilot/motspilot.sh archive --task=<name>`

## Phases

| Phase | Prompt | Artifact | Writes code? |
|-------|--------|----------|--------------|
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

## Core Philosophy

- Start with the person using the feature, not the code
- Explore the existing codebase before touching anything
- Trace the blast radius of every change
- Build in tiny loops (write → verify → write)
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
motspilot/
  motspilot.sh                    # Shell utility (filing system, not engine)
  PIPELINE_ORCHESTRATOR.md        # Claude Code orchestration instructions
  prompts/                        # Thinking frameworks (one per phase)
  prompts/frameworks/             # Framework-specific guides (cakephp.md, etc.)
  .motspilot/
    config                        # Project settings
    current_task                  # Active task name
    workspace/
      tasks/<name>/               # Active task artifacts
      archive/<name>/             # Completed task artifacts
    logs/
```
