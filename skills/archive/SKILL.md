---
name: archive
description: Archive a completed motspilot task. Use when asked to archive a motspilot task or clean up finished work.
---

# motspilot Archive

Archive a completed task, moving it from active to the archive directory.

## Behavior

Parse the user's input after `/mots:archive`:

- **`--task=<name>`** → archive that task:
  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/motspilot.sh --project=$(pwd) archive --task=<name>
  ```

- **No arguments** → read `.motspilot/current_task` to get the active task name. Confirm with the user before archiving:
  "Archive task '<name>'? This moves it to the archive directory. You can restore it later with /mots:reactivate."

If the task doesn't exist, show available tasks by running the status command.
