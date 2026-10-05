# shellcheck shell=bash
# motspilot — create and load .motspilot/config.
# Sourced by motspilot.sh; not meant to be run on its own.

# ─── Config ──────────────────────────────────────────────────────────────────

ensure_config() {
    mkdir -p "$LOG_DIR"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        mkdir -p "$(dirname "$CONFIG_FILE")"
        cat >"$CONFIG_FILE" <<'EOF'
# ─── motspilot configuration ─────────────────────────────
#
# Edit these values for your project.
# This file is sourced by motspilot.sh.
#
# Project root is auto-detected:
#   - Via symlink: parent directory of the symlink
#   - Direct invocation: parent directory of motspilot/

# Language: php, python, javascript, typescript, go, ruby, java, etc.
LANGUAGE=""

# Language version (e.g. 8.2, 3.12, 20, 1.22)
LANGUAGE_VERSION=""

# Framework: cakephp, laravel, symfony, django, flask, nextjs, express, rails, gin, etc.
# A matching guide in prompts/frameworks/<name>.md will be included automatically.
FRAMEWORK=""

# Auto-approve phases or pause for human review between phases
# Options: all | none | comma-separated phase names to PAUSE on (e.g. "architecture,delivery")
# Default "all" runs the full pipeline without stopping. Set to "none" to pause after every phase.
AUTO_APPROVE="all"

# Max retries per phase if Claude Code fails
MAX_RETRIES=2

# App URL for verification phase (optional — used for smoke testing)
APP_URL="http://localhost:8080"

# Test command (e.g. ./vendor/bin/phpunit, pytest, npm test, go test ./...)
TEST_CMD=""

# Deploy command (used in delivery phase)
DEPLOY_CMD="echo 'Deploy not configured — edit .motspilot/config'"

# Workspace directory (optional — store task artifacts in the project repo instead of .motspilot/)
# Path is relative to project root. When set, tasks/ and archive/ live here.
# This allows task data to be committed to the project's git repository.
# Example: WORKSPACE_DIR="motspilot-data"
WORKSPACE_DIR=""

# Multi-model consensus phase
# Set to "disabled" to skip consensus even when PHP and API keys are available.
# /mots:init sets this automatically based on dependency detection.
CONSENSUS="enabled"

# How Claude's three consensus roles (perspective, synthesis, differences) run:
#   session = via Claude Code Task subagents (uses your session quota, no ANTHROPIC_API_KEY needed)
#   api     = via direct Anthropic API in bin/consensus.php (requires ANTHROPIC_API_KEY)
# OPENAI_API_KEY and GEMINI_API_KEY are required in both modes.
CONSENSUS_CLAUDE_MODE="session"

# Config format version — used by /mots:init to detect stale configs and offer migration.
CONFIG_VERSION="1"
EOF
        return 1 # signal that config was just created
    fi

    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    return 0
}
