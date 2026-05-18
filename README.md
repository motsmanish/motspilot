# motspilot

[![CI](https://github.com/motsmanish/motspilot/actions/workflows/ci.yml/badge.svg)](https://github.com/motsmanish/motspilot/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-brightgreen)](https://www.shellcheck.net/)

A 6-phase AI pipeline for shipping features into *existing* codebases — without the "the agent confidently broke prod" failure mode.

Each phase has a hard-constraint block the AI reads before any creative work, every verification finding quotes file:line evidence from your code, and a multi-model consensus (Claude + GPT-4o + Gemini) runs before the first design decision. Ships as a Claude Code plugin.

**What you write:** a 2–3 line feature description.
**What it produces:** consensus synthesis → architecture plan with blast-radius analysis → code → tests (security-first) → verification report with confidence-scored findings → executed smoke tests → deployment plan. Each artifact is a file in your repo, so the full decision trail is committable.

<!-- TODO: 30-second asciinema or GIF of one real task — see docs/example-task/ -->

> motspilot is built for engineers integrating into production codebases — not for greenfield prototyping. If your codebase is younger than its first incident, a single-model agent is probably fine.

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
- **`yq` v4.52+** — parses YAML frontmatter from phase prompts
  - Install: `wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O ~/.local/bin/yq && chmod +x ~/.local/bin/yq`
  - macOS: `brew install yq`

---

## Installation

### As a Claude Code Plugin (recommended)

From any Claude Code session:

```bash
/plugin marketplace add motsmanish/motspilot
/plugin install mots
```

Then in your target project:

```bash
/mots:init                                # One-time setup
/mots:pilot add login throttling          # Run the pipeline
/mots:status                              # Check progress
/mots:view verify                         # Read verification report
/mots:archive --task=add-login-throttling # Archive when done
```

> **Requires:** WSL, macOS, or Linux (bash). Consensus phase optionally requires PHP 8+ and API keys for Claude, GPT-4o, and Gemini.

### Clone (for development/contribution)

```bash
git clone https://github.com/motsmanish/motspilot.git
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup. Alternative integration methods (symlink, submodule) are documented there.

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

Claude Code orchestrates all 5 phases and archives the task automatically when delivery is approved. By default, phases run without pausing (`AUTO_APPROVE="all"`). Set `AUTO_APPROVE="none"` in `.motspilot/config` to approve each phase before it proceeds.

---

## Framework Support

motspilot works with any framework. Framework-specific knowledge lives in `prompts/frameworks/`:

| Guide | Framework | Status |
|-------|-----------|--------|
| `cakephp.md` | CakePHP 4.x | Shipped |
| `plain-php.md` | Plain PHP (no framework) | Shipped |

Both shipped guides include side-effect-asserting smoke-test templates (status-code-only curl is no longer accepted by the delivery phase), `<framework_tool_affinity>` blocks that route the AI toward correct tool usage, and point at `prompts/delivery.md` section 3.2 for the smoke-test execution gate. The plain-PHP guide is structured around two callouts — Shape A (page-file) and Shape B (PDS-skeleton) — and includes webserver isolation rules.

Without a guide for your framework, the pipeline runs on framework-agnostic reasoning and discovers patterns from your codebase as it goes. Adding a guide is a one-file contribution — see [Adding a Framework Guide](#adding-a-framework-guide) below.

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
| `./motspilot.sh mem-check` | Check memory index health (line/byte caps, staleness) |

**Phase names:** `architecture` · `development` · `testing` · `verification` · `delivery`

**View shortcuts:** `req` · `arch` · `dev` · `test` · `verify` · `wo` (workorder)

---

## Pipeline Phases

You write the requirements. motspilot runs 6 AI phases:

```
Requirements (input) → Consensus → Architecture → Development → Testing → Verification → Delivery
```

| # | Phase | What it does | Writes code? |
|---|-------|-------------|--------------|
| 1 | Consensus | Fans out the requirements to Claude + GPT-4o + Gemini, synthesizes a starting point | No |
| 2 | Architecture | Explores codebase, designs feature, traces blast radius | No |
| 3 | Development | Implements the feature — schema, models, controllers, views | Yes |
| 4 | Testing | Writes comprehensive tests (security-first) | Yes |
| 5 | Verification | Senior code review — security, correctness, framework patterns | No |
| 6 | Delivery | Executes smoke tests, deployment steps, rollback plan, git commit message | No |

Each phase uses a **thinking framework** (in `prompts/`) — not a checklist. Every phase prompt includes YAML frontmatter (parsed by `yq`), a `<hard_constraints>` block of non-negotiable rules read before any creative work, and a structured 12-item `<completion_checklist>` the phase must self-report against. Downstream phases consume tight `<summary>` blocks, not full reasoning history. Verification quotes file:line evidence; Delivery executes smoke tests with both entry-point and side-effect checks before marking a task complete.

For the full catalogue of patterns applied across phases — structure, reasoning gates, output discipline, severity / confidence / consistency tiers, and cross-phase contracts — see [docs/prompt-engineering.md](docs/prompt-engineering.md).

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
│   ├── _xml_tags.md                    # Canonical reference for all XML tag names
│   ├── architecture.md                 # Architecture thinking framework (YAML frontmatter)
│   ├── development.md                  # Development thinking framework (YAML frontmatter)
│   ├── testing.md                      # Testing thinking framework (YAML frontmatter)
│   ├── verification.md                 # Verification thinking framework (YAML frontmatter)
│   ├── delivery.md                     # Delivery thinking framework (YAML frontmatter)
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
AUTO_APPROVE="all"              # "all" = fully automatic, "none" = approve each phase
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

Before the pipeline phases begin, motspilot runs a **Multi-Model Consensus** step. It fans out the task requirements to 3 LLMs (Claude, GPT-4o, Gemini) in parallel, collects their responses, and synthesizes a single authoritative starting point via a Claude judge using a **3-pass process** (Extract → Reconcile → Synthesize) with a completeness contract ensuring no unique insight is lost. The synthesis uses a **9-section structured format** with Agreed/Split/Risks/Scope sections. Split decisions auto-resolve by majority when `AUTO_APPROVE=all`. The synthesized output is then fed as additional context into every pipeline phase.

The consensus script is a standalone PHP CLI — no framework dependencies, just PHP 8.0+ with curl:

```bash
# Direct usage (the pipeline runs this automatically):
php motspilot/bin/consensus.php --prompt-file=prompt.txt --phase=architecture > output.md

# Or via stdin:
echo "Design a caching strategy" | php motspilot/bin/consensus.php --phase=general
```

**Setup:** Set `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, and `GEMINI_API_KEY` in `motspilot/.env`.

**Fault-tolerant by design:** if 1–2 APIs fail, synthesis proceeds with the remaining responses. If all 3 fail, the pipeline continues without consensus and logs the gap for review. Consensus strengthens the starting point but is not a hard dependency for the rest of the pipeline to run.

**Dynamic timeouts:** API timeouts scale automatically based on prompt length (90s floor, +5s per 1K chars, 300s ceiling). Judge calls get 1.5x. No hardcoded limits — large requirements documents get proportionally more time. Human-readable error messages for timeouts, DNS failures, and connection issues.

---

## Core Philosophy

- **Start with the user** — think about who uses the feature before touching code
- **Explore before building** — read existing code, do not assume
- **Trace blast radius** — know what breaks before you change it
- **Layered build order** — Foundation → Logic → Interface, verifying each against the architecture
- **Security mindset** — think like an attacker at every step
- **Never greenfield** — always integrating into existing apps, matching existing patterns
- **One action per migration** — never combine unrelated changes in a single migration

---

## Project Status

motspilot was built for production work I do day-to-day and shared because it may help others doing similar work. It's maintained alongside that primary work — issue and PR response times may be longer than a full-time-staffed project, and community contributions (especially framework guides and bug fixes) are very welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Disclaimer

- motspilot requires your own [Claude Code](https://claude.ai/code) subscription or API access. It does not include, bundle, or redistribute any Anthropic software.
- motspilot stores all data locally on your machine. It does not collect or transmit any data. When the pipeline runs, task data is sent to Anthropic's servers by Claude Code under [Anthropic's privacy policy](https://www.anthropic.com/privacy).
- All AI-generated code must be reviewed by qualified developers before deployment. The authors are not responsible for code produced by AI models.
- Security testing instructions are intended for testing your own applications only.
