---
name: reactivate
description: Restore an archived motspilot task back to active status. Use when asked to reactivate, restore, or resume an archived motspilot task.
---

# motspilot Reactivate

Restore an archived task back to active status so you can re-run phases (e.g., for bug fixes).

## Behavior

Parse the user's input after `/mots:reactivate`:

- **`<name>`** → reactivate that task:
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/motspilot.sh --project=$(pwd) reactivate <name>
  ```

- **No arguments** → list archived tasks so the user can pick one:
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/motspilot.sh --project=$(pwd) tasks --all
  ```
  Then ask which one to reactivate.

After reactivation, tell the user:
"Task '<name>' is active again. Run `/mots:pilot <description>` with `--from=<phase>` to re-run from a specific phase, or just `/mots:pilot` to pick up where it left off."
