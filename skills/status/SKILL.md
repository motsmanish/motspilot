---
name: status
description: Show motspilot task status or list all tasks. Use when asked about motspilot task status, task list, or pipeline progress.
---

# motspilot Status

Show task status for the current project.

## Behavior

Parse the user's input after `/mots:status`:

- **No arguments** → list all active tasks:
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/motspilot.sh --project=$(pwd) tasks
  ```

- **`--all`** → list active + archived tasks:
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/motspilot.sh --project=$(pwd) tasks --all
  ```

- **`--task=<name>`** → show detailed status for one task:
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/motspilot.sh --project=$(pwd) status --task=<name>
  ```

Show the output to the user. If no `.motspilot/` directory exists, tell the user to run `/mots:init` first.
