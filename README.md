# motspilot

[![CI](https://github.com/motsmanish/motspilot/actions/workflows/ci.yml/badge.svg)](https://github.com/motsmanish/motspilot/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-brightgreen)](https://www.shellcheck.net/)

AI-powered feature development pipeline for existing codebases — framework-agnostic.

Coordinates five specialized AI agents (architecture, development, testing, verification, delivery) to build features in your existing codebase — safely, with human approval between each phase.

> **Project Status:** This tool was built for my own production work and shared because it may help others. I maintain it alongside my primary work, so response times on issues and PRs may be longer than typical. Community contributions — especially framework guides and bug fixes — are very welcome.

---

## How It Works

**Two components:**

1. **`motspilot.sh`** — Shell utility. Manages named tasks, requirements, state, and artifacts. Does not invoke AI directly.

2. **Claude Code** — The AI orchestrator. Reads the work order and runs each phase as a Task subagent. You approve each phase before it proceeds. Tasks auto-archive on completion.

**Claude Code is the engine. `motspilot.sh` is the filing system.**

---

## Requirements

- **[Claude Code](https://claude.ai/code)** — the AI orchestrator that runs the pipeline phases
- **Bash 4.0+** — the shell script uses associative arrays
  - Linux: you almost certainly have bash 4+ already
  - macOS: ships with bash 3.2 — install a newer version with `brew install bash`
  - Windows: use Git Bash, WSL, or any bash 4+ environment

---

## Installation

### Option A: Symlink (recommended for teams)

Clone motspilot once and symlink it into each project. The tool stays separate from your project code, and updates apply to all projects.

```bash
# Clone motspilot to a shared location
git clone https://github.com/motsmanish/motspilot.git ~/motspilot

# In your project root, create a symlink
cd /path/to/your-project
ln -s ~/motspilot ./motspilot

# Add the symlink to your project's .gitignore
echo '/motspilot' >> .gitignore
```

### Option B: Submodule (for version-pinning)

Add motspilot as a git submodule. This pins a specific version and makes setup automatic for other developers who clone your repo.

```bash
cd /path/to/your-project
git submodule add https://github.com/motsmanish/motspilot.git motspilot
git commit -m "Add motspilot as submodule"
```

Other developers clone with `--recursive`, or run `git submodule update --init` after cloning.

### Option C: Direct clone (simplest)

Clone motspilot directly into your project. Simple but you manage updates manually.

```bash
cd /path/to/your-project
git clone https://github.com/motsmanish/motspilot.git
echo '/motspilot' >> .gitignore
```

---

## Quick Start

```bash
# 1. Initialize (first time only)
./motspilot/motspilot.sh init
# Edit .motspilot/config with your project's language, framework, and test command

# 2. Create a task and prepare the pipeline
./motspilot/motspilot.sh go --task=csv-export "Add CSV export to the reports page"

# 3. In Claude Code chat:
run motspilot pipeline
```

Claude Code orchestrates all 5 phases, asks for your approval between each one, and archives the task automatically when delivery is approved.

---

## Framework Support

motspilot works with any framework. Framework-specific knowledge lives in `prompts/frameworks/`:

| Guide | Framework | Status |
|-------|-----------|--------|
| `cakephp.md` | CakePHP 4.x | Shipped |

**CakePHP is the only framework guide that currently exists.** Without a framework guide, the pipeline still works — it uses framework-agnostic reasoning and discovers patterns from your codebase. Framework guides make the AI's output more precise by providing version-specific API patterns, verification checks, and deployment commands.

**Community contributions welcome.** See [CONTRIBUTING.md](CONTRIBUTING.md) for how to write a framework guide. Guides for Laravel, Django, Rails, Next.js, Express, and others would be valuable additions.

To add support for a new framework, create `prompts/frameworks/<name>.md` and set `FRAMEWORK="<name>"` in `.motspilot/config`.

---

## Multi-Task Workflow

### Start a new task
```bash
./motspilot.sh go --task=billing-fix "Fix incorrect subtotal on invoices"
# Then in Claude Code: run motspilot pipeline
```

### Switch tasks mid-pipeline
```bash
# Current task is paused automatically when you start a new one.
# Artifacts are preserved on disk.

./motspilot.sh go --task=high-priority "Fix critical login bug"
# Then in Claude Code: run motspilot pipeline
```

### Resume a paused task
```bash
./motspilot.sh go --task=csv-export --from=development
# Then in Claude Code: run motspilot pipeline
```

### Bug fix on a completed (archived) task
```bash
./motspilot.sh reactivate csv-export
./motspilot.sh go --task=csv-export --from=development
# Then in Claude Code: run motspilot pipeline
```

### See all tasks
```bash
./motspilot.sh tasks          # active tasks
./motspilot.sh tasks --all    # active + archived
```

---

## Task Lifecycle

```
go --task=name   →   pending
pipeline starts  →   in_progress
delivery approved →  archived  (automatic)
reactivate       →   in_progress (again)
```

Tasks auto-archive when the delivery phase is approved. You never lose the artifacts — they move from `tasks/` to `archive/` and are retrievable anytime.

---

## Commands

| Command | Description |
|---------|-------------|
| `./motspilot.sh init` | First-time setup |
| `./motspilot.sh go --task=<name> "description"` | Create task + prepare pipeline |
| `./motspilot.sh go --task=<name>` | Re-prepare existing task |
| `./motspilot.sh go --task=<name> --from=<phase>` | Re-run pipeline from a specific phase |
| `./motspilot.sh tasks` | List all active tasks with phase progress |
| `./motspilot.sh tasks --all` | List active + archived tasks |
| `./motspilot.sh status [--task=<name>]` | Detailed phase status for a task |
| `./motspilot.sh archive --task=<name>` | Manually archive a task |
| `./motspilot.sh reactivate <name>` | Restore task from archive |
| `./motspilot.sh reset --task=<name>` | Delete phase artifacts (keeps requirements) |
| `./motspilot.sh view <phase> [--task=<name>]` | View a phase artifact |

**Phase names:** `architecture` · `development` · `testing` · `verification` · `delivery`

**View shortcuts:** `req` · `arch` · `dev` · `test` · `verify` · `wo` (workorder)

---

## Pipeline Phases

```
Requirements → Architecture → Development → Testing → Verification → Delivery
```

| # | Phase | What it does | Writes code? |
|---|-------|-------------|--------------|
| 1 | Requirements | You write this | No |
| 2 | Architecture | Explores codebase, designs feature, traces blast radius | No |
| 3 | Development | Implements the feature — schema, models, controllers, views | Yes |
| 4 | Testing | Writes comprehensive tests (security-first) | Yes |
| 5 | Verification | Senior code review — security, correctness, framework patterns | No |
| 6 | Delivery | Deployment steps, rollback plan, git commit message | No |

Each phase uses a **thinking framework** (in `prompts/`) — not a checklist.
Each phase also receives a **framework guide** (in `prompts/frameworks/`) if one exists for your framework.

---

## When to Create a New Task vs Reactivate

| Situation | Action |
|-----------|--------|
| New unrelated feature | New task: `go --task=new-name "description"` |
| Bug in a recently completed feature | Reactivate: `reactivate <name>`, re-run from development |
| Bug that reveals a design flaw | New task (architecture needs rethinking) |
| Bug in old unrelated code | New task |

---

## File Structure

```
motspilot/                              # The tool (symlink, submodule, or clone)
├── motspilot.sh                        # Shell utility
├── PIPELINE_ORCHESTRATOR.md            # Claude Code orchestration instructions
├── README.md                           # This file
├── CLAUDE.md                           # Quick reference for Claude Code
├── prompts/
│   ├── architecture.md                 # Architecture thinking framework
│   ├── development.md                  # Development thinking framework
│   ├── testing.md                      # Testing thinking framework
│   ├── verification.md                 # Verification thinking framework
│   ├── delivery.md                     # Delivery thinking framework
│   └── frameworks/                     # Framework-specific guides
│       └── cakephp.md                  # CakePHP 4.x guide
└── .motspilot/
    ├── config                          # Project settings (edit this)
    ├── current_task                    # Name of currently active task
    └── logs/
        └── motspilot.log
```

**Task data** lives in the workspace — either inside `.motspilot/workspace/` (default) or in your project repo via `WORKSPACE_DIR`:

```
<workspace>/                            # .motspilot/workspace/ OR <WORKSPACE_DIR>/
├── tasks/
│   └── <task-name>/
│       ├── meta                        # STATUS, DESCRIPTION, CREATED
│       ├── 01_requirements.md
│       ├── 02_architecture.md
│       ├── 03_development.md
│       ├── 04_testing.md
│       ├── 05_verification.md
│       ├── 06_delivery.md
│       ├── checkpoint                  # Current phase state
│       └── pipeline_workorder.md
└── archive/
    └── <task-name>/                    # Same structure, auto-moved on completion
```

---

## Configuration

Edit `motspilot/.motspilot/config`:

```bash
LANGUAGE="php"                  # Language: php, python, javascript, typescript, go, ruby, java, etc.
LANGUAGE_VERSION="8.2"          # Language version
FRAMEWORK="cakephp"             # Framework: cakephp, laravel, django, nextjs, express, rails, etc.
PROJECT_ROOT=".."               # Path to your project root (relative to motspilot/)
AUTO_APPROVE="none"             # "none" = approve each phase, "all" = fully automatic
TEST_CMD="./vendor/bin/phpunit" # How to run tests
APP_URL="http://localhost:8080" # For smoke testing (verification phase)
WORKSPACE_DIR=""                # Store task data in your project repo (see below)
```

### Storing task data in your project repo (`WORKSPACE_DIR`)

By default, task artifacts (requirements, architecture docs, development summaries, etc.) are stored inside `motspilot/.motspilot/workspace/`. This directory is gitignored in the motspilot repo, so **task data is not version-controlled**.

If you want to preserve task history in your project's git repository, set `WORKSPACE_DIR` to a directory inside your project:

```bash
# In .motspilot/config
WORKSPACE_DIR="motspilot-data"
```

This tells motspilot to store `tasks/` and `archive/` at `<PROJECT_ROOT>/motspilot-data/` instead of inside the motspilot tool directory. Then commit `motspilot-data/` to your project's git repo:

```
your-project/
├── motspilot/                 # symlink/submodule (gitignored or submodule)
├── motspilot-data/            # committed to YOUR repo
│   ├── tasks/
│   │   └── csv-export/
│   │       ├── 01_requirements.md
│   │       ├── 02_architecture.md
│   │       └── ...
│   └── archive/
│       └── completed-feature/
└── src/
```

**Why this matters:**
- Task data survives even if motspilot is uninstalled or the symlink breaks
- Architecture decisions and development summaries are part of your project's history
- Other team members can read past task artifacts without running motspilot
- `git log motspilot-data/` shows the evolution of feature development decisions

---

## Adding a Framework Guide

To add support for a new framework:

1. Create `motspilot/prompts/frameworks/<framework-name>.md`
2. Include these sections:
   - **Version reference** — correct vs incorrect API for the framework version
   - **Naming conventions** — how files, classes, and routes are named
   - **Files to explore** — key landmark files for the architecture phase
   - **Migration/schema patterns** — how to create and rollback schema changes
   - **Model/entity patterns** — access control, validation, relationships
   - **Service/business logic patterns** — where business logic lives
   - **Controller/handler patterns** — request handling conventions
   - **Template/view patterns** — output escaping, form helpers
   - **Test patterns** — test setup, fixtures, security test examples
   - **Verification checks** — grep patterns to catch common mistakes
   - **Deployment commands** — deploy, rollback, cache clear
3. Set `FRAMEWORK="<framework-name>"` in `.motspilot/config`

See `prompts/frameworks/cakephp.md` as a reference.

---

## Multi-Model Consensus

motspilot includes an optional Multi-Model Consensus service that fans out a prompt to 3 LLMs (Claude, GPT-4o, Gemini 1.5 Pro) in parallel, then synthesizes a single authoritative answer via Claude as judge. Any pipeline phase can use it.

```bash
bin/cake consensus "Design a caching strategy for this API" --phase=architecture
```

**Setup:** Set `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, and `GEMINI_API_KEY` in your `.env` file. See `prompts/frameworks/cakephp.md` for full integration instructions.

**Fault tolerant:** If 1 or 2 APIs fail, the service proceeds with whatever responses are available. All 3 fail = error. Failed APIs are logged with reasons.

> **Security note — Gemini API key in URL:** Google's API requires the key as a URL query parameter. If your reverse proxy logs full URIs, the key will appear in access logs. Use targeted nginx log exclusion (not blanket query string suppression):
>
> ```nginx
> map $request_uri $loggable {
>     ~*googleapis.com  0;
>     default           1;
> }
> access_log /var/log/nginx/access.log combined if=$loggable;
> ```
>
> **Long-term:** Switch to Vertex AI with service account credentials to eliminate key-in-URL entirely. See `prompts/frameworks/cakephp.md` for details.

---

## Core Philosophy

- **Start with the user** — think about who uses the feature before touching code
- **Explore before building** — read existing code, do not assume
- **Trace blast radius** — know what breaks before you change it
- **Tiny build loops** — write → verify → write, not 500 lines then test
- **Security mindset** — think like an attacker at every step
- **Never greenfield** — always integrating into existing apps, matching existing patterns
- **One action per migration** — never combine unrelated changes in a single migration

---

## Disclaimer

- motspilot requires your own [Claude Code](https://claude.ai/code) subscription or API access. It does not include, bundle, or redistribute any Anthropic software.
- motspilot stores all data locally on your machine. It does not collect or transmit any data. When the pipeline runs, task data is sent to Anthropic's servers by Claude Code under [Anthropic's privacy policy](https://www.anthropic.com/privacy).
- All AI-generated code must be reviewed by qualified developers before deployment. The authors are not responsible for code produced by AI models.
- Security testing instructions are intended for testing your own applications only.
