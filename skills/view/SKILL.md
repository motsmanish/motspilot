---
name: view
description: View a motspilot phase artifact. Use when asked to view, show, or read a pipeline phase output (architecture, development, testing, verification, delivery, requirements, or workorder).
---

# motspilot View

View a phase artifact for a task.

## Behavior

Parse the user's input after `/mots:view`:

- **`<phase>`** → view that phase for the current task:
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/motspilot.sh --project=$(pwd) view <phase>
  ```

- **`<phase> --task=<name>`** → view that phase for a specific task:
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/motspilot.sh --project=$(pwd) view <phase> --task=<name>
  ```

- **No arguments** → show available phases:
  ```
  Which phase do you want to view?
    req       — Requirements
    arch      — Architecture
    dev       — Development
    test      — Testing
    verify    — Verification
    delivery  — Delivery
    wo        — Work order
  ```

Read the artifact file and show its contents to the user. If the artifact doesn't exist yet, tell the user which phases have been completed.
