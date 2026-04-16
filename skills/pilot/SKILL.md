---
name: pilot
description: Run the motspilot 6-phase AI pipeline for adding features to existing applications. Use when asked to run motspilot, run pipeline, or go motspilot.
---

# motspilot Pipeline

You are the ORCHESTRATOR of the motspilot pipeline.

## Step 1 — Prepare the task

The user's input after `/mots:pilot` (or `/mots:pipeline`) is the feature description.

1. Slugify the description into a task name: lowercase, hyphens for spaces, strip special chars.
   Example: "add login throttling" → `add-login-throttling`

2. Check if `.motspilot/config` exists in the current project directory.
   - If NOT: tell the user to run `/mots:init` first and stop.

3. Create and prepare the task by running:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/motspilot.sh --project=$(pwd) go --task=<slug> "<original description>"
   ```
   This creates the task directory, writes a requirements template, and sets the task as current.

4. If requirements template was just created (`01_requirements.md`), read it and ask the user
   to confirm or edit the requirements before proceeding. The pipeline needs clear requirements.

## Step 2 — Run the pipeline

1. Read `${CLAUDE_PLUGIN_ROOT}/PIPELINE_ORCHESTRATOR.md` for full orchestration instructions.
2. Follow it exactly from Step 1 (Verify Prerequisites) onward.

The orchestrator defines:
- How to run multi-model consensus (Phase 0 — skipped if CONSENSUS=disabled in config)
- How to spawn each phase as a Task subagent
- What context to include in each subagent prompt
- When to pause for approval vs auto-proceed (AUTO_APPROVE setting)
- How to write outputs to the task directory
- How to archive on completion

## Key path rules

- Phase prompts: `${CLAUDE_PLUGIN_ROOT}/prompts/<phase>.md`
- Framework guides: `${CLAUDE_PLUGIN_ROOT}/prompts/frameworks/<FRAMEWORK>.md`
- Shell script: `${CLAUDE_PLUGIN_ROOT}/motspilot.sh`
- Consensus script: `${CLAUDE_PLUGIN_ROOT}/bin/consensus.php`
- Task artifacts: written to the TARGET project's workspace (`.motspilot/workspace/` or WORKSPACE_DIR), NOT the plugin directory
