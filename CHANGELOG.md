# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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
