# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Removed
- **Codex plugin manifests** (`.codex-plugin/` and `.agents/`). They were added speculatively in v1.1.0, never linked from the README, never tested in CI, and cost a dual-version-bump at every release. If Codex compatibility comes back as a real demand, the manifests are recoverable from git history.

## [1.2.1] - 2026-05-15

### Changed
- **Consensus default Claude model bumped from Sonnet 4 to Sonnet 4.6** (`claude-sonnet-4-20250514` → `claude-sonnet-4-6`). Sonnet 4 is being retired on the Anthropic API on 2026-06-15; this avoids service interruption for `CONSENSUS_CLAUDE_MODE=api` and the standalone `bin/consensus.php` script. `session` mode is unaffected — it routes Claude work through Claude Code Task subagents, which the harness resolves to current models.
- `motspilot.sh` task-name validation now allows `_` and `.` in the interior of task names (e.g. `01e_owasp-8.2.3-input-validation`). Start/end must still be `[a-z0-9]`.

### Added
- `CONSENSUS_CLAUDE_MODEL` environment variable in `bin/consensus.php` — overrides the default Claude model used for both the fan-out call and the synthesis/differences judge calls. Lets you upgrade past future deprecations without a code edit.

## [1.2.0] - 2026-04-17

### Added
- **Per-phase model routing** — phase prompts now declare a `model:` YAML frontmatter field. The orchestrator reads it with `yq` and passes it to the Task tool so each phase runs on the right model. Defaults: Architecture → `opus` (design trade-offs, blast-radius reasoning); Development / Testing / Verification / Delivery → `sonnet` (routine code generation + mechanical checks). Stretches Opus session quota without hurting output quality where it matters.
- **Session-mode consensus** — new `CONSENSUS_CLAUDE_MODE` config key with two modes:
  - `session` (default inside Claude Code) — `bin/consensus.php --external-only` fans out to GPT-4o + Gemini only; the orchestrator spawns three Sonnet Task subagents for Claude's consensus roles (perspective → `01_claude.md`, synthesis → `04_synthesis.md`, differences → `05_differences.md`). Claude work draws from session quota; `ANTHROPIC_API_KEY` is no longer required for consensus.
  - `api` (legacy) — `bin/consensus.php` handles everything via direct Anthropic API calls. Requires `ANTHROPIC_API_KEY`.
- `bin/consensus.php` gains a `--external-only` flag that skips the Claude fan-out and both judge calls, drops `ANTHROPIC_API_KEY` from the required-key set, and reports `=== EXTERNAL-ONLY CONSENSUS COMPLETE ===`.

### Changed
- `/mots:init` adapts required-key checks to `CONSENSUS_CLAUDE_MODE`: only `OPENAI_API_KEY` + `GEMINI_API_KEY` are required in session mode. Claude Code's `ANTHROPIC_API_KEY` stripping is now reported as "ready (mode: session)" instead of a problem.
- Default `.motspilot/config` written by `motspilot.sh` now includes `CONSENSUS_CLAUDE_MODE="session"`.
- `plugin.json` userConfig description for `ANTHROPIC_API_KEY` clarifies it's only needed in `api` mode.

## [1.1.0] - 2026-04-16

### Added
- **Claude Code plugin support** — install via `/plugin marketplace add motsmanish/motspilot` + `/plugin install mots`
- 7 skills: `/mots:pilot`, `/mots:pipeline` (alias), `/mots:init`, `/mots:status`, `/mots:archive`, `/mots:reactivate`, `/mots:view`
- Codex cross-compatibility (`.codex-plugin/` + `.agents/plugins/marketplace.json`)
- `CONSENSUS` config variable — graceful degradation when PHP/API keys unavailable
- `CONFIG_VERSION` field for config migration tracking
- Secret precedence in `consensus.php`: userConfig (keychain) > env vars > `.env` file

### Changed
- `PIPELINE_ORCHESTRATOR.md` paths are now plugin-aware (no `motspilot/` prefix)
- Consensus phase auto-skips when `CONSENSUS=disabled`
- README installation options re-lettered (plugin is now Option A)

### Added (previous)
- `WORKSPACE_DIR` config option — store task artifacts in the project repo instead of inside motspilot's own directory. Enables version-controlling task data alongside project code.
- Installation guide in README — symlink, submodule, and direct clone options with step-by-step instructions.

### Fixed
- Case-insensitive meta key matching in `list_tasks()` for compatibility with tasks created by older versions.

## [1.0.2] - 2026-02-24

### Changed
- Default `AUTO_APPROVE` to `all` — pipeline phases run without pausing by default

## [1.0.1] - 2026-02-23

### Fixed
- Use `set -e` safe arithmetic for counter increments in shell script

## [1.0.0] - 2026-02-23

### Added
- Initial release of motspilot
- 5-phase AI pipeline: Architecture, Development, Testing, Verification, Delivery
- Shell script (`motspilot.sh`) for task management, archiving, and state tracking
- Thinking framework prompts for each pipeline phase
- CakePHP 4.x framework guide (`prompts/frameworks/cakephp.md`)
- Auto-archive on pipeline completion
- Task lifecycle: create, prepare, run, archive, reactivate
- Checkpoint system for phase state tracking
- Configurable approval gates between phases (`AUTO_APPROVE` setting)
- Claude Code as native orchestrator via `PIPELINE_ORCHESTRATOR.md`
- Multi-task support with concurrent task management
- Color-coded logging to console and file
