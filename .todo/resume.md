# Pending tasks

**Updated:** 2026-10-05 17:45 IST

_Nothing pending._

## How to maintain this file

- This is a **pending-only task list** — nothing "done" belongs here. When a task finishes, delete
  its line and add an entry to `completed.md` instead (with the commit hash).
- One task = one line: a short bolded label, one line of context, then a pointer to the doc with
  full detail (`.todo/item-N-some-name.md`). If no doc exists yet for a new task, create one and
  point to it — don't write the detail inline here.
- Order by priority, most urgent/blocking first. Re-sort when priorities change instead of leaving
  stale ordering.
- If a task is stalled on someone else (the owner, a third party), say so in the line (e.g.
  "blocked — owner") rather than mixing it in unmarked.
- Keep the **Updated** timestamp current, in IST, every time this file changes.
- Before trusting an old entry, re-verify it against git log / the linked doc rather than assuming
  it's still accurate — this file has gone stale before.
- This file is tracked in git and the repo is **public** — keep entries to a label and a pointer,
  no names or private context. Everything else in `.todo/` (detail docs, `completed.md`) stays
  gitignored.
