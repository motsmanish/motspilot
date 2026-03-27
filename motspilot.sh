#!/bin/bash
###############################################################################
# motspilot — AI-Powered Dev Pipeline by MOTSTECH
#
# Named-task workflow with auto-archive on completion.
# Claude Code (VSCode) is the AI orchestrator — this script manages state.
#
# Usage:
#   ./motspilot.sh init                                      # First-time setup
#   ./motspilot.sh go --task=<name> "description"            # Create task + prepare
#   ./motspilot.sh go --task=<name>                          # Re-prepare existing task
#   ./motspilot.sh go --task=<name> --from=<phase>           # Re-run from a phase
#   ./motspilot.sh tasks [--all]                             # List tasks
#   ./motspilot.sh status [--task=<name>]                    # Task detail
#   ./motspilot.sh archive --task=<name>                     # Archive a task
#   ./motspilot.sh reactivate <name>                         # Restore from archive
#   ./motspilot.sh reset --task=<name>                       # Reset phase artifacts
#   ./motspilot.sh view <phase> [--task=<name>]              # View an artifact
#
# Setup (any of these work):
#   Option A: Symlink the directory into your project:
#     ln -s /path/to/motspilot myproject/motspilot
#     cd myproject && ./motspilot/motspilot.sh init
#
#   Option B: Symlink just the script:
#     ln -s /path/to/motspilot/motspilot.sh myproject/motspilot.sh
#     cd myproject && ./motspilot.sh init
#
#   Option C: Run directly from any project directory:
#     cd myproject && bash /path/to/motspilot/motspilot.sh init
#
#   Option D: Explicit project path:
#     /path/to/motspilot/motspilot.sh --project=/path/to/myproject init
#
# Project detection: looks for .motspilot/config walking up from CWD,
# then falls back to CWD itself. Use --project= to override.
###############################################################################

set -euo pipefail

# ─── Bash version check ────────────────────────────────────────────────────
# Associative arrays require bash 4.0+. macOS ships bash 3.2 (GPLv2).
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo ""
    echo "  motspilot requires bash 4.0 or later."
    echo "  Your version: ${BASH_VERSION}"
    echo ""
    echo "  macOS ships with bash 3.2. Install a newer version:"
    echo "    brew install bash"
    echo ""
    echo "  Then run motspilot with the Homebrew bash:"
    echo "    /opt/homebrew/bin/bash ./motspilot.sh <command>"
    echo ""
    echo "  Or add it to your PATH and set it as default:"
    echo "    sudo sh -c 'echo /opt/homebrew/bin/bash >> /etc/shells'"
    echo "    chsh -s /opt/homebrew/bin/bash"
    echo ""
    exit 1
fi

# ─── Paths ───────────────────────────────────────────────────────────────────

# MOTSPILOT_DIR: where the tool itself lives (prompts, scripts)
# Resolve the real path even through symlinks (portable — works on macOS and Linux)
_resolve_symlink() {
    local target="$1"
    while [[ -L "$target" ]]; do
        local dir
        dir="$(cd "$(dirname "$target")" && pwd)"
        target="$(readlink "$target")"
        # Handle relative symlink targets
        [[ "$target" != /* ]] && target="${dir}/${target}"
    done
    echo "$target"
}
MOTSPILOT_DIR="$(cd "$(dirname "$(_resolve_symlink "$0")")" && pwd)"

# PROJECT_DIR: the project that is using motspilot
#
# Resolution order:
#   1. --project=<path> flag (explicit override)
#   2. Symlink detection (project/motspilot/ or project/bin/motspilot.sh)
#   3. Walk up from CWD looking for .motspilot/config
#   4. CWD itself (if .motspilot/config exists or will be created by init)
#   5. Fallback: MOTSPILOT_DIR parent (legacy behavior)

# Check for --project= flag in args
_EXPLICIT_PROJECT=""
for _arg in "$@"; do
    case "$_arg" in
        --project=*) _EXPLICIT_PROJECT="${_arg#--project=}" ;;
    esac
done

# Helper: walk up from a directory looking for .motspilot/config
find_project_root() {
    local dir="$1"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "${dir}/.motspilot/config" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

if [[ -n "$_EXPLICIT_PROJECT" ]]; then
    # 1. Explicit --project= flag
    PROJECT_DIR="$(cd "$_EXPLICIT_PROJECT" && pwd)"
elif [[ -L "$0" ]] || [[ "$(cd "$(dirname "$0")" && pwd)" != "$MOTSPILOT_DIR" ]]; then
    # 2. Invoked via symlink — project is where the symlink lives
    #    Supports: project/motspilot/motspilot.sh (symlinked dir)
    #              project/bin/motspilot.sh (symlinked file in subdir)
    #              project/motspilot.sh (symlinked file at root)
    SYMLINK_DIR="$(cd "$(dirname "$0")" && pwd)"
    if [[ -f "${SYMLINK_DIR}/.motspilot/config" ]]; then
        # Symlink is at project root (e.g. project/motspilot.sh)
        PROJECT_DIR="$SYMLINK_DIR"
    elif [[ -f "${SYMLINK_DIR}/../.motspilot/config" ]]; then
        # Symlink is in a subdirectory (e.g. project/motspilot/motspilot.sh)
        PROJECT_DIR="$(cd "${SYMLINK_DIR}/.." && pwd)"
    else
        # No config found — walk up from symlink location
        PROJECT_DIR="$(find_project_root "$SYMLINK_DIR" || echo "$SYMLINK_DIR")"
    fi
else
    # 3. Invoked directly (not via symlink)
    #    Prefer CWD if it has .motspilot/config, otherwise walk up from CWD
    if PROJECT_DIR="$(find_project_root "$(pwd)")"; then
        : # found it
    elif [[ "$(pwd)" != "$MOTSPILOT_DIR" ]] && [[ "$(pwd)" != "$(dirname "$MOTSPILOT_DIR")" ]]; then
        # CWD looks like a project directory — use it (init will create config)
        PROJECT_DIR="$(pwd)"
    else
        # Fallback: motspilot's parent (legacy behavior for co-located setups)
        PROJECT_DIR="$(cd "${MOTSPILOT_DIR}/.." && pwd)"
    fi
fi

# State lives in the PROJECT, not in the tool directory
STATE_DIR="${PROJECT_DIR}/.motspilot"
LOG_DIR="${STATE_DIR}/logs"
CONFIG_FILE="${STATE_DIR}/config"
CURRENT_TASK_FILE="${STATE_DIR}/current_task"

# Workspace paths (defaults — may be overridden by WORKSPACE_DIR in config)
WORK_DIR="${STATE_DIR}/workspace"
TASKS_DIR="${WORK_DIR}/tasks"
ARCHIVE_DIR="${WORK_DIR}/archive"

# ─── Phase definitions ───────────────────────────────────────────────────────

AUTO_PHASES=("architecture" "development" "testing" "verification" "delivery")
ALL_PHASES=("requirements" "architecture" "development" "testing" "verification" "delivery")

declare -A PHASE_NUM=(
    [requirements]="01"
    [architecture]="02"
    [development]="03"
    [testing]="04"
    [verification]="05"
    [delivery]="06"
)

declare -A PHASE_SHORT=(
    [requirements]="req  "
    [architecture]="arch "
    [development]="dev  "
    [testing]="test "
    [verification]="vrfy "
    [delivery]="dlvr "
)

# ─── Colors ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ─── Logging ─────────────────────────────────────────────────────────────────

log() {
    local level="$1"
    shift
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    mkdir -p "$LOG_DIR"
    echo -e "${timestamp} [${level}] $*" >>"${LOG_DIR}/motspilot.log"
    case "$level" in
        INFO) echo -e "  ${BLUE}ℹ${NC}  $*" ;;
        OK) echo -e "  ${GREEN}✓${NC}  $*" ;;
        WARN) echo -e "  ${YELLOW}⚠${NC}  $*" ;;
        ERROR) echo -e "  ${RED}✗${NC}  $*" ;;
        PHASE)
            echo -e "\n${CYAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "  ${CYAN}${BOLD}  $*${NC}"
            echo -e "${CYAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
            ;;
    esac
}

show_banner() {
    echo -e "${CYAN}"
    cat <<'BANNER'

    ╔═════════════════════════════════════════════════════╗
    ║                                                     ║
    ║   motspilot — AI Dev Pipeline by MOTSTECH           ║
    ║                                                     ║
    ║   📄 → ⚙️  → 💻 → ✅ → 🔍 → 🚀                     ║
    ║                                                     ║
    ╚═════════════════════════════════════════════════════╝

BANNER
    echo -e "${NC}"
}

# ─── Workspace resolution ─────────────────────────────────────────────────────

resolve_workspace() {
    # If WORKSPACE_DIR is set in config, use it (relative to PROJECT_DIR)
    if [[ -n "${WORKSPACE_DIR:-}" ]]; then
        WORK_DIR="${PROJECT_DIR}/${WORKSPACE_DIR}"
        TASKS_DIR="${WORK_DIR}/tasks"
        ARCHIVE_DIR="${WORK_DIR}/archive"
    fi
    mkdir -p "$TASKS_DIR" "$ARCHIVE_DIR" "$LOG_DIR"
}

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
EOF
        return 1 # signal that config was just created
    fi

    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    return 0
}

# ─── Slug / name helpers ─────────────────────────────────────────────────────

slugify() {
    # Convert a description to a valid task name (lowercase, hyphens, max 40 chars)
    echo "$1" |
        tr '[:upper:]' '[:lower:]' |
        sed 's/[^a-z0-9]/-/g' |
        tr -s '-' |
        sed 's/^-//;s/-$//' |
        cut -c1-40
}

validate_task_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$ ]]; then
        log ERROR "Invalid task name: '${name}'"
        log INFO "Use lowercase letters, numbers, and hyphens only (e.g. add-csv-export)"
        return 1
    fi
}

# ─── Task directory helpers ───────────────────────────────────────────────────

task_dir() {
    echo "${TASKS_DIR}/${1}"
}

archived_task_dir() {
    echo "${ARCHIVE_DIR}/${1}"
}

task_exists() {
    [[ -d "${TASKS_DIR}/${1}" ]]
}

archived_task_exists() {
    [[ -d "${ARCHIVE_DIR}/${1}" ]]
}

# ─── Meta file (key=value per task) ──────────────────────────────────────────

task_meta_get() {
    local name="$1"
    local key="$2"
    local meta_file
    meta_file="$(task_dir "$name")/meta"
    [[ -f "$meta_file" ]] && grep "^${key}=" "$meta_file" | cut -d= -f2- | head -1 || echo ""
}

archived_meta_get() {
    local name="$1"
    local key="$2"
    local meta_file
    meta_file="$(archived_task_dir "$name")/meta"
    [[ -f "$meta_file" ]] && grep "^${key}=" "$meta_file" | cut -d= -f2- | head -1 || echo ""
}

task_meta_set() {
    local name="$1"
    local key="$2"
    local value="$3"
    local meta_file
    meta_file="$(task_dir "$name")/meta"
    local tmp
    tmp=$(mktemp)
    # Remove existing key, append new value
    grep -v "^${key}=" "$meta_file" 2>/dev/null >"$tmp" || true
    echo "${key}=${value}" >>"$tmp"
    mv "$tmp" "$meta_file"
}

# ─── Current task ────────────────────────────────────────────────────────────

get_current_task() {
    [[ -f "$CURRENT_TASK_FILE" ]] && cat "$CURRENT_TASK_FILE" || echo ""
}

set_current_task() {
    echo "$1" >"$CURRENT_TASK_FILE"
}

clear_current_task() {
    rm -f "$CURRENT_TASK_FILE"
}

# Resolve task name: from --task=<name> arg, then current_task file, then error
resolve_task() {
    local explicit_task="$1" # empty string if not provided
    if [[ -n "$explicit_task" ]]; then
        echo "$explicit_task"
        return 0
    fi

    local current
    current=$(get_current_task)
    if [[ -n "$current" ]]; then
        echo "$current"
        return 0
    fi

    log ERROR "No task specified and no current task is set."
    log INFO "Use: --task=<name>"
    log INFO "Or:  ./motspilot.sh tasks  (to see available tasks)"
    return 1
}

# ─── Checkpoints (per-task) ──────────────────────────────────────────────────

save_checkpoint() {
    local name="$1"
    local phase="$2"
    local state="${3:-pending}"
    echo "${phase}|${state}" >"$(task_dir "$name")/checkpoint"
}

load_checkpoint() {
    local name="$1"
    local cp_file
    cp_file="$(task_dir "$name")/checkpoint"
    [[ -f "$cp_file" ]] && cat "$cp_file" || echo ""
}

clear_checkpoint() {
    local name="$1"
    rm -f "$(task_dir "$name")/checkpoint"
}

# ─── Phase validation ────────────────────────────────────────────────────────

phase_index() {
    local target="$1"
    for i in "${!AUTO_PHASES[@]}"; do
        [[ "${AUTO_PHASES[$i]}" == "$target" ]] && echo "$i" && return
    done
    echo "-1"
}

# ─── Requirements ────────────────────────────────────────────────────────────

req_file() {
    echo "$(task_dir "$1")/01_requirements.md"
}

write_requirements() {
    local name="$1"
    local description="$2"
    cat >"$(req_file "$name")" <<EOF
# Feature Requirements

## Request
${description}

## Acceptance Criteria
<!-- What does "done" look like? -->

## Out of Scope
<!-- What are we NOT building? -->

## Notes / Constraints
<!-- Any technical constraints, related issues, or context -->
EOF
    log OK "Requirements written for task: ${name}"
}

create_requirements_template() {
    local name="$1"
    local dest
    dest=$(req_file "$name")

    if [[ -f "$dest" ]] && [[ -s "$dest" ]]; then
        log WARN "Requirements already exist for task: ${name}"
        log INFO "Edit: ${dest}"
        return
    fi

    cat >"$dest" <<'TEMPLATE'
# motspilot — Requirements Specification

## Request
<!-- Describe what you want built. Be specific. -->



## User Stories
<!-- As a [role], I want [feature], so that [benefit] -->
-


## Acceptance Criteria
<!-- GIVEN [context] WHEN [action] THEN [result] -->
-


## Data Requirements
<!-- Entities, fields, relationships, validation -->



## UI / Screen Requirements
<!-- Pages, forms, interactions, error states -->



## API / Endpoints (if applicable)
<!-- Method, path, request/response -->



## Security & Constraints
<!-- Auth, permissions, rate limits, etc. -->



## Out of Scope
<!-- What this does NOT include -->



## Notes
<!-- Anything else the AI copilots should know -->


TEMPLATE
    log OK "Created requirements template: ${dest}"
}

validate_requirements() {
    local name="$1"
    local dest
    dest=$(req_file "$name")

    if [[ ! -f "$dest" ]] || [[ ! -s "$dest" ]]; then
        log ERROR "Requirements file is missing or empty for task: ${name}"
        log INFO "Edit: ${dest}"
        return 1
    fi

    local content
    content=$(sed -n '/^## Request/,/^## /p' "$dest" | grep -v '^#\|^$\|^>' | head -5)
    if [[ -z "$content" || "$content" =~ ^[[:space:]]*$ ]]; then
        log WARN "The 'Request' section appears empty — are requirements filled in?"
        read -rp "  Continue anyway? [y/N]: " answer
        [[ "$(echo "$answer" | tr '[:upper:]' '[:lower:]')" == "y" ]] || return 1
    fi

    log OK "Requirements validated"
    return 0
}

# ─── Task creation ────────────────────────────────────────────────────────────

create_task() {
    local name="$1"
    local description="${2:-}"
    local tdir
    tdir=$(task_dir "$name")

    mkdir -p "$tdir"
    mkdir -p "${tdir}/screenshots"

    # Write meta
    cat >"${tdir}/meta" <<EOF
STATUS=pending
DESCRIPTION=${description}
CREATED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

    log OK "Task created: ${name}"
}

# ─── Work order ──────────────────────────────────────────────────────────────

write_workorder() {
    local name="$1"
    local from_phase="${2:-architecture}"
    local tdir
    tdir=$(task_dir "$name")

    # shellcheck source=/dev/null
    source "$CONFIG_FILE"

    local req_preview
    req_preview=$(head -20 "$(req_file "$name")")
    local description
    description=$(task_meta_get "$name" "DESCRIPTION")

    # Compute workspace path relative to project root (for work order references)
    local workspace_rel
    if [[ -n "${WORKSPACE_DIR:-}" ]]; then
        workspace_rel="${WORKSPACE_DIR}"
    else
        workspace_rel=".motspilot/workspace"
    fi

    cat >"${tdir}/pipeline_workorder.md" <<EOF
# motspilot Pipeline Work Order

**Task name**: ${name}
**Description**: ${description}
**Status**: READY
**Created**: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
**Start from phase**: ${from_phase}
**Project root**: ${PROJECT_DIR}
**Language**: ${LANGUAGE:-"(not set)"}
**Language version**: ${LANGUAGE_VERSION:-"(not set)"}
**Framework**: ${FRAMEWORK:-"(not set)"}
**Test command**: ${TEST_CMD:-"(not set)"}
**Workspace**: ${workspace_rel}

## Requirements (preview)

${req_preview}

[Full requirements: ${workspace_rel}/tasks/${name}/01_requirements.md]

## Artifact Paths

All phase artifacts for this task are stored in:
  ${workspace_rel}/tasks/${name}/

| # | Phase        | Thinking Framework               | Artifact                                            |
|---|--------------|----------------------------------|-----------------------------------------------------|
| 2 | Architecture | motspilot/prompts/architecture.md | ${workspace_rel}/tasks/${name}/02_architecture.md |
| 3 | Development  | motspilot/prompts/development.md  | ${workspace_rel}/tasks/${name}/03_development.md  |
| 4 | Testing      | motspilot/prompts/testing.md      | ${workspace_rel}/tasks/${name}/04_testing.md      |
| 5 | Verification | motspilot/prompts/verification.md | ${workspace_rel}/tasks/${name}/05_verification.md |
| 6 | Delivery     | motspilot/prompts/delivery.md     | ${workspace_rel}/tasks/${name}/06_delivery.md     |

## Orchestration Instructions

See: **motspilot/PIPELINE_ORCHESTRATOR.md**

## On Completion

When all phases are approved, run:
  ./motspilot.sh archive --task=${name}
EOF

    task_meta_set "$name" "STATUS" "in_progress"
    save_checkpoint "$name" "$from_phase" "pending"

    log OK "Work order written for task: ${name}"
}

# ─── Task listing ─────────────────────────────────────────────────────────────

# Print phase progress bar for a task dir
phase_progress() {
    local tdir="$1"
    local bar=""
    for phase in "${AUTO_PHASES[@]}"; do
        local artifact="${tdir}/${PHASE_NUM[$phase]}_${phase}.md"
        if [[ -f "$artifact" ]] && [[ -s "$artifact" ]]; then
            bar+="${GREEN}✓${NC} ${PHASE_SHORT[$phase]}  "
        else
            bar+="${DIM}○${NC} ${PHASE_SHORT[$phase]}  "
        fi
    done
    echo -e "$bar"
}

list_tasks() {
    local include_archived="${1:-false}"

    echo ""

    # Active tasks
    local active_count=0
    if [[ -d "$TASKS_DIR" ]]; then
        while IFS= read -r -d '' tdir; do
            [[ -f "${tdir}/meta" ]] || continue
            local name
            name=$(basename "$tdir")
            local status description
            status=$(grep -i "^STATUS=" "${tdir}/meta" | head -1 | cut -d= -f2- || echo "")
            description=$(grep -i "^DESCRIPTION=" "${tdir}/meta" | head -1 | cut -d= -f2- || echo "")

            local current
            current=$(get_current_task)
            local marker="  "
            [[ "$name" == "$current" ]] && marker="${CYAN}▶ ${NC}"

            local status_color="$DIM"
            [[ "$status" == "in_progress" ]] && status_color="$YELLOW"

            printf "  %b%-25s ${status_color}%-12s${NC} %s\n" "$marker" "$name" "$status" "$description"
            echo -e "    $(phase_progress "$tdir")"
            echo ""
            active_count=$((active_count + 1))
        done < <(find "$TASKS_DIR" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null | sort -z)
    fi

    if [[ $active_count -eq 0 ]]; then
        echo -e "  ${DIM}No active tasks.${NC}"
        echo -e "  Create one: ${CYAN}./motspilot.sh go --task=my-feature \"description\"${NC}"
        echo ""
    fi

    # Archived tasks
    if [[ "$include_archived" == "true" ]] && [[ -d "$ARCHIVE_DIR" ]]; then
        local archived_count=0
        echo -e "  ${DIM}── Archived ─────────────────────────────────────────────${NC}"
        echo ""
        while IFS= read -r -d '' adir; do
            [[ -f "${adir}/meta" ]] || continue
            local name description archived_at
            name=$(basename "$adir")
            description=$(grep -i "^DESCRIPTION=" "${adir}/meta" | head -1 | cut -d= -f2- || echo "")
            archived_at=$(grep -i "^ARCHIVED_AT=" "${adir}/meta" | head -1 | cut -d= -f2- | cut -c1-10 || echo "")
            printf "  ${DIM}✓ %-25s %-12s %s${NC}\n" "$name" "${archived_at:-unknown}" "$description"
            archived_count=$((archived_count + 1))
        done < <(find "$ARCHIVE_DIR" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null | sort -z)

        if [[ $archived_count -eq 0 ]]; then
            echo -e "  ${DIM}No archived tasks.${NC}"
        fi
        echo ""
    fi
}

# ─── Detailed status for one task ────────────────────────────────────────────

show_task_status() {
    local name="$1"
    local tdir
    tdir=$(task_dir "$name")

    echo ""
    echo -e "  ${BOLD}Task: ${CYAN}${name}${NC}"

    local description status created
    description=$(task_meta_get "$name" "DESCRIPTION")
    status=$(task_meta_get "$name" "STATUS")
    created=$(task_meta_get "$name" "CREATED" | cut -c1-10)

    echo -e "  ${DIM}Description:${NC} ${description}"
    echo -e "  ${DIM}Status:${NC}      ${status}"
    echo -e "  ${DIM}Created:${NC}     ${created}"
    echo ""
    echo -e "  ${DIM}─── Phase artifacts ─────────────────────────────${NC}"
    echo ""

    for phase in "${ALL_PHASES[@]}"; do
        local artifact="${tdir}/${PHASE_NUM[$phase]}_${phase}.md"
        if [[ -f "$artifact" ]] && [[ -s "$artifact" ]]; then
            local size
            size=$(wc -c <"$artifact")
            echo -e "  ${GREEN}✓${NC} ${phase} ${DIM}(${size} bytes)${NC}"
        else
            echo -e "  ${DIM}○${NC} ${phase}"
        fi
    done

    echo ""

    local cp
    cp=$(load_checkpoint "$name")
    if [[ -n "$cp" ]]; then
        local cp_phase="${cp%%|*}"
        local cp_state="${cp##*|}"
        echo -e "  ${YELLOW}⚑${NC}  Checkpoint: ${BOLD}${cp_phase}${NC} [${cp_state}]"
    fi

    echo ""
}

# ─── Archive / reactivate ────────────────────────────────────────────────────

archive_task() {
    local name="$1"

    if ! task_exists "$name"; then
        log ERROR "Task not found: ${name}"
        return 1
    fi

    local tdir adir
    tdir=$(task_dir "$name")
    adir=$(archived_task_dir "$name")

    mkdir -p "$ARCHIVE_DIR"

    # If already exists in archive (from a previous cycle), remove it
    [[ -d "$adir" ]] && rm -rf "$adir"

    mv "$tdir" "$adir"

    # Update meta in archive
    local tmp
    tmp=$(mktemp)
    grep -v "^STATUS=\|^ARCHIVED_AT=" "${adir}/meta" >"$tmp" || true
    echo "STATUS=completed" >>"$tmp"
    echo "ARCHIVED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >>"$tmp"
    mv "$tmp" "${adir}/meta"

    # Clear current task if it was this one
    if [[ "$(get_current_task)" == "$name" ]]; then
        clear_current_task
    fi

    log OK "Task archived: ${name}"
    log INFO "Reactivate with: ./motspilot.sh reactivate ${name}"
}

reactivate_task() {
    local name="$1"

    if ! archived_task_exists "$name"; then
        log ERROR "No archived task found: ${name}"
        log INFO "Run: ./motspilot.sh tasks --all  to see archived tasks"
        return 1
    fi

    if task_exists "$name"; then
        log ERROR "An active task named '${name}' already exists."
        return 1
    fi

    local adir tdir
    adir=$(archived_task_dir "$name")
    tdir=$(task_dir "$name")

    mv "$adir" "$tdir"

    # Update status back to in_progress
    task_meta_set "$name" "STATUS" "in_progress"
    task_meta_set "$name" "REACTIVATED_AT" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    set_current_task "$name"

    log OK "Task reactivated: ${name}"
    echo ""
    echo -e "  ${BOLD}Next step:${NC}"
    echo -e "  Decide which phase to re-run from, then:"
    echo -e "  ${CYAN}./motspilot.sh go --task=${name} --from=development${NC}"
    echo -e "  Then in Claude Code: ${CYAN}run motspilot pipeline${NC}"
    echo ""
}

# ─── Reset ───────────────────────────────────────────────────────────────────

reset_task() {
    local name="$1"
    local tdir
    tdir=$(task_dir "$name")

    echo ""
    log WARN "This deletes all phase artifacts for '${name}' (requirements preserved)."
    read -rp "  Are you sure? [y/N]: " answer
    if [[ "$(echo "$answer" | tr '[:upper:]' '[:lower:]')" == "y" ]]; then
        for phase in "${AUTO_PHASES[@]}"; do
            rm -f "${tdir}/${PHASE_NUM[$phase]}_${phase}.md" 2>/dev/null || true
        done
        rm -f "${tdir}/checkpoint" "${tdir}/pipeline_workorder.md" 2>/dev/null || true
        task_meta_set "$name" "STATUS" "pending"
        log OK "Task reset: ${name}"
        log INFO "Requirements preserved. Run ./motspilot.sh go --task=${name} to restart."
    else
        log INFO "Reset cancelled."
    fi
    echo ""
}

# ─── View artifact ───────────────────────────────────────────────────────────

view_artifact() {
    local phase="$1"
    local name="$2"
    local tdir
    tdir=$(task_dir "$name")
    local file=""

    case "$phase" in
        requirements | req | 1) file="${tdir}/01_requirements.md" ;;
        architecture | arch | 2) file="${tdir}/02_architecture.md" ;;
        development | dev | 3) file="${tdir}/03_development.md" ;;
        testing | test | 4) file="${tdir}/04_testing.md" ;;
        verification | verify | 5) file="${tdir}/05_verification.md" ;;
        delivery | 6) file="${tdir}/06_delivery.md" ;;
        workorder | wo) file="${tdir}/pipeline_workorder.md" ;;
        meta) file="${tdir}/meta" ;;
        *)
            log ERROR "Unknown phase: ${phase}"
            echo "  Valid: requirements, architecture, development, testing, verification, delivery, workorder"
            exit 1
            ;;
    esac

    if [[ ! -f "$file" ]]; then
        log WARN "No artifact found: ${file}"
    else
        cat "$file"
    fi
}

# ─── Interactive task picker ──────────────────────────────────────────────

# Determine the current phase stage for a task directory
get_phase_stage() {
    local tdir="$1"
    local last_done=""
    local next_pending=""

    for phase in "${ALL_PHASES[@]}"; do
        local artifact="${tdir}/${PHASE_NUM[$phase]}_${phase}.md"
        if [[ -f "$artifact" ]] && [[ -s "$artifact" ]]; then
            last_done="$phase"
        elif [[ -z "$next_pending" ]]; then
            next_pending="$phase"
        fi
    done

    if [[ -z "$last_done" ]] && [[ -n "$next_pending" ]]; then
        echo "${next_pending}"
    elif [[ -n "$next_pending" ]]; then
        echo "${next_pending}"
    elif [[ -n "$last_done" ]]; then
        echo "done"
    else
        echo "—"
    fi
}

# Build a compact phase progress string: [✓✓✓○○○]
get_phase_bar() {
    local tdir="$1"
    local bar="["
    for phase in "${ALL_PHASES[@]}"; do
        local artifact="${tdir}/${PHASE_NUM[$phase]}_${phase}.md"
        if [[ -f "$artifact" ]] && [[ -s "$artifact" ]]; then
            bar+="${GREEN}✓${NC}"
        else
            bar+="${DIM}○${NC}"
        fi
    done
    bar+="]"
    echo -e "$bar"
}

# Get last-modified timestamp of the most recently changed file in a task dir
# Portable — works on both GNU (Linux) and BSD (macOS) systems
get_last_modified() {
    local tdir="$1"
    local epoch=""
    # GNU find supports -printf, BSD find does not
    if find --version 2>/dev/null | grep -q 'GNU' 2>/dev/null; then
        epoch=$(find "$tdir" -maxdepth 1 -type f -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)
    else
        # BSD/macOS: use stat -f "%m" for epoch seconds
        epoch=$(find "$tdir" -maxdepth 1 -type f -exec stat -f "%m" {} \; 2>/dev/null | sort -rn | head -1)
    fi
    if [[ -n "$epoch" ]]; then
        # GNU date uses -d, BSD date uses -r
        date -d "@${epoch}" '+%Y-%m-%d %H:%M' 2>/dev/null ||
            date -r "${epoch}" '+%Y-%m-%d %H:%M' 2>/dev/null ||
            echo "—"
    else
        echo "—"
    fi
}

pick_task() {
    local source="${1:-active}" # "active", "archived", or "all"
    local tasks=()
    local task_dirs=()

    # Collect active tasks
    if [[ "$source" != "archived" ]] && [[ -d "$TASKS_DIR" ]]; then
        while IFS= read -r -d '' tdir; do
            [[ -f "${tdir}/meta" ]] || continue
            tasks+=("$(basename "$tdir")")
            task_dirs+=("$tdir")
        done < <(find "$TASKS_DIR" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null | sort -z)
    fi

    # Collect archived tasks
    if [[ "$source" == "archived" || "$source" == "all" ]] && [[ -d "$ARCHIVE_DIR" ]]; then
        while IFS= read -r -d '' adir; do
            [[ -f "${adir}/meta" ]] || continue
            tasks+=("$(basename "$adir")")
            task_dirs+=("$adir")
        done < <(find "$ARCHIVE_DIR" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null | sort -z)
    fi

    if [[ ${#tasks[@]} -eq 0 ]]; then
        log WARN "No tasks found."
        log INFO "Create one: ${CYAN}./motspilot.sh go --task=my-feature \"description\"${NC}"
        return 1
    fi

    local current
    current=$(get_current_task)

    echo ""
    echo -e "  ${BOLD}Select a task:${NC}"
    echo ""

    # Table header
    printf "  ${DIM}───┬──────────────────────────┬────────────┬──────────────┬────────────┬──────────────────${NC}\n"
    printf "  ${BOLD} #  │ Task                     │ Status     │ Stage        │ Progress   │ Last Modified    ${NC}\n"
    printf "  ${DIM}───┼──────────────────────────┼────────────┼──────────────┼────────────┼──────────────────${NC}\n"

    local i=1
    for idx in "${!tasks[@]}"; do
        local name="${tasks[$idx]}"
        local tdir="${task_dirs[$idx]}"
        local meta_file="${tdir}/meta"

        local status description created
        status=$(grep -i "^STATUS=" "$meta_file" | head -1 | cut -d= -f2- || echo "")
        description=$(grep -i "^DESCRIPTION=" "$meta_file" | head -1 | cut -d= -f2- || echo "")
        created=$(grep -i "^CREATED=" "$meta_file" | head -1 | cut -d= -f2- | cut -c1-10 || echo "—")

        # Phase stage
        local stage
        stage=$(get_phase_stage "$tdir")

        # Phase progress bar
        local bar
        bar=$(get_phase_bar "$tdir")

        # Last modified
        local modified
        modified=$(get_last_modified "$tdir")

        # Status color
        local status_color="$DIM"
        [[ "$status" == "in_progress" ]] && status_color="$YELLOW"
        [[ "$status" == "pending" ]] && status_color="$BLUE"
        [[ "$status" == "completed" ]] && status_color="$GREEN"

        # Stage color
        local stage_color="$DIM"
        [[ "$stage" != "done" ]] && [[ "$stage" != "—" ]] && stage_color="$CYAN"
        [[ "$stage" == "done" ]] && stage_color="$GREEN"

        # Current task marker
        local marker=" "
        [[ "$name" == "$current" ]] && marker="${CYAN}▶${NC}"

        printf "  %b${BOLD}%2d${NC} │ %-24s │ ${status_color}%-10s${NC} │ ${stage_color}%-12s${NC} │ %b │ ${DIM}%-16s${NC}\n" \
            "$marker" "$i" "$name" "$status" "$stage" "$bar" "$modified"
        i=$((i + 1))
    done

    printf "  ${DIM}───┴──────────────────────────┴────────────┴──────────────┴────────────┴──────────────────${NC}\n"
    echo ""

    read -rp "  Enter number (1-${#tasks[@]}): " choice

    # Validate input
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#tasks[@]} ]]; then
        log ERROR "Invalid selection."
        return 1
    fi

    PICKED_TASK="${tasks[$((choice - 1))]}"
    return 0
}

# ─── CLI ─────────────────────────────────────────────────────────────────────

main() {
    show_banner

    # Strip --project= from args (already consumed during path resolution)
    local filtered_args=()
    for _a in "$@"; do
        [[ "$_a" != --project=* ]] && filtered_args+=("$_a")
    done
    set -- "${filtered_args[@]}"

    local command="${1:-help}"
    shift || true

    # Load config and resolve workspace path (WORKSPACE_DIR override)
    if [[ "$command" != "init" ]]; then
        ensure_config 2>/dev/null || true
        resolve_workspace
    fi

    case "$command" in

        # ── init ────────────────────────────────────────────────────────────
        init)
            if ! ensure_config; then
                echo ""
                echo -e "  ${BOLD}First-time setup complete!${NC}"
                echo ""
                echo -e "  ${YELLOW}1.${NC} Edit config: ${BOLD}.motspilot/config${NC}"
                echo -e "  ${YELLOW}2.${NC} Run again:   ${BOLD}./motspilot.sh init${NC}"
                echo ""
                exit 0
            fi

            resolve_workspace

            echo ""
            echo -e "  ${BOLD}Ready. Create your first task:${NC}"
            echo ""
            echo -e "  ${CYAN}./motspilot.sh go --task=my-feature \"Describe what to build\"${NC}"
            echo ""
            ;;

        # ── go ──────────────────────────────────────────────────────────────
        go)
            if [[ ! -f "$CONFIG_FILE" ]]; then
                log ERROR "Run ./motspilot.sh init first"
                exit 1
            fi

            local task_name=""
            local from_phase="architecture"
            local inline_desc=""

            for arg in "$@"; do
                case "$arg" in
                    --task=*) task_name="${arg#--task=}" ;;
                    --from=*) from_phase="${arg#--from=}" ;;
                    --*) log WARN "Unknown flag: $arg" ;;
                    *) inline_desc="$arg" ;;
                esac
            done

            # Resolve task name
            if [[ -z "$task_name" ]]; then
                if [[ -n "$inline_desc" ]]; then
                    task_name=$(slugify "$inline_desc")
                    log INFO "Auto-named task: ${task_name}"
                else
                    # Try current task first, then offer picker
                    local current
                    current=$(get_current_task)
                    if [[ -n "$current" ]] && task_exists "$current"; then
                        task_name="$current"
                    else
                        log INFO "No task specified. Pick from existing tasks:"
                        if pick_task "active"; then
                            task_name="$PICKED_TASK"
                        else
                            exit 1
                        fi
                    fi
                fi
            fi

            validate_task_name "$task_name" || exit 1

            # Validate from_phase
            if [[ $(phase_index "$from_phase") == "-1" ]]; then
                log ERROR "Unknown phase: ${from_phase}"
                log INFO "Valid: ${AUTO_PHASES[*]}"
                exit 1
            fi

            # Handle archive conflict
            if archived_task_exists "$task_name" && ! task_exists "$task_name"; then
                log WARN "Task '${task_name}' is in the archive."
                log INFO "Reactivate with: ./motspilot.sh reactivate ${task_name}"
                exit 1
            fi

            # Create task if new
            if ! task_exists "$task_name"; then
                create_task "$task_name" "$inline_desc"
                create_requirements_template "$task_name"
            fi

            # Write inline description to requirements — only for NEW tasks
            # (don't overwrite requirements the user has already edited)
            if [[ -n "$inline_desc" ]]; then
                local req_file
                req_file=$(req_file "$task_name")
                if [[ ! -f "$req_file" ]] || [[ ! -s "$req_file" ]] || grep -q '<!-- Describe what you want built' "$req_file" 2>/dev/null; then
                    write_requirements "$task_name" "$inline_desc"
                else
                    log WARN "Requirements already edited — skipping overwrite. Description: ${inline_desc}"
                fi
            fi

            # Validate requirements
            if ! validate_requirements "$task_name"; then
                exit 1
            fi

            # Set as current task
            set_current_task "$task_name"

            # Write work order
            write_workorder "$task_name" "$from_phase"

            # Show instructions
            local desc
            desc=$(task_meta_get "$task_name" "DESCRIPTION")
            echo ""
            log PHASE "Task ready: ${task_name} — phases: ${from_phase} → delivery"
            echo ""
            echo -e "  ${BOLD}Task:${NC}  ${task_name}"
            echo -e "  ${BOLD}Start:${NC} ${from_phase}"
            echo ""
            if [[ -n "$desc" ]]; then
                echo -e "  ${BOLD}Request:${NC}"
                echo -e "  ${DIM}${desc}${NC}"
                echo ""
            fi
            echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "  ${BOLD}Tell Claude Code:${NC}"
            echo ""
            echo -e "  ${CYAN}${BOLD}    run motspilot pipeline${NC}"
            echo ""
            echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo -e "  Claude Code orchestrates all phases via Task subagents."
            if [[ "${AUTO_APPROVE:-all}" == "all" ]]; then
                echo -e "  Pipeline will run all phases without pausing."
                echo -e "  Set ${BOLD}AUTO_APPROVE=\"none\"${NC} in .motspilot/config to pause between phases."
            elif [[ "${AUTO_APPROVE}" == "none" ]]; then
                echo -e "  It will ask for your approval between each phase."
            else
                echo -e "  It will pause for approval after: ${AUTO_APPROVE}"
            fi
            echo -e "  The task auto-archives when delivery is complete."
            echo ""
            ;;

        # ── tasks ───────────────────────────────────────────────────────────
        tasks)
            local include_archived="false"
            for arg in "$@"; do
                [[ "$arg" == "--all" ]] && include_archived="true"
            done
            list_tasks "$include_archived"
            ;;

        # ── status ──────────────────────────────────────────────────────────
        status)
            local task_name=""
            for arg in "$@"; do
                [[ "$arg" == --task=* ]] && task_name="${arg#--task=}"
            done

            if [[ -z "$task_name" ]]; then
                local current
                current=$(get_current_task)
                if [[ -n "$current" ]] && task_exists "$current"; then
                    task_name="$current"
                else
                    if pick_task "active"; then
                        task_name="$PICKED_TASK"
                    else
                        exit 1
                    fi
                fi
            fi

            if ! task_exists "$task_name"; then
                log ERROR "Task not found: ${task_name}"
                exit 1
            fi
            show_task_status "$task_name"
            ;;

        # ── archive ─────────────────────────────────────────────────────────
        archive)
            local task_name=""
            for arg in "$@"; do
                [[ "$arg" == --task=* ]] && task_name="${arg#--task=}"
            done

            if [[ -z "$task_name" ]]; then
                local current
                current=$(get_current_task)
                if [[ -n "$current" ]] && task_exists "$current"; then
                    task_name="$current"
                else
                    if pick_task "active"; then
                        task_name="$PICKED_TASK"
                    else
                        exit 1
                    fi
                fi
            fi

            archive_task "$task_name"
            ;;

        # ── reactivate ──────────────────────────────────────────────────────
        reactivate)
            local task_name="${1:-}"
            if [[ -z "$task_name" ]]; then
                if pick_task "archived"; then
                    task_name="$PICKED_TASK"
                else
                    exit 1
                fi
            fi
            reactivate_task "$task_name"
            ;;

        # ── reset ───────────────────────────────────────────────────────────
        reset)
            local task_name=""
            for arg in "$@"; do
                [[ "$arg" == --task=* ]] && task_name="${arg#--task=}"
            done

            if [[ -z "$task_name" ]]; then
                local current
                current=$(get_current_task)
                if [[ -n "$current" ]] && task_exists "$current"; then
                    task_name="$current"
                else
                    if pick_task "active"; then
                        task_name="$PICKED_TASK"
                    else
                        exit 1
                    fi
                fi
            fi

            if ! task_exists "$task_name"; then
                log ERROR "Task not found: ${task_name}"
                exit 1
            fi
            reset_task "$task_name"
            ;;

        # ── view ────────────────────────────────────────────────────────────
        view)
            local phase=""
            local task_name=""

            for arg in "$@"; do
                case "$arg" in
                    --task=*) task_name="${arg#--task=}" ;;
                    *) [[ -z "$phase" ]] && phase="$arg" ;;
                esac
            done

            phase="${phase:-requirements}"

            if [[ -z "$task_name" ]]; then
                local current
                current=$(get_current_task)
                if [[ -n "$current" ]] && task_exists "$current"; then
                    task_name="$current"
                else
                    if pick_task "active"; then
                        task_name="$PICKED_TASK"
                    else
                        exit 1
                    fi
                fi
            fi

            if ! task_exists "$task_name"; then
                log ERROR "Task not found: ${task_name}"
                exit 1
            fi
            view_artifact "$phase" "$task_name"
            ;;

        # ── help ────────────────────────────────────────────────────────────
        help | --help | -h | *)
            echo -e "  ${BOLD}Usage:${NC}"
            echo ""
            echo -e "    ${CYAN}./motspilot.sh init${NC}                                First-time setup"
            echo -e "    ${CYAN}./motspilot.sh go --task=<name> \"description\"${NC}      Create task + prepare pipeline"
            echo -e "    ${CYAN}./motspilot.sh go --task=<name>${NC}                    Re-prepare existing task"
            echo -e "    ${CYAN}./motspilot.sh go --task=<name> --from=<phase>${NC}     Prepare to re-run from a phase"
            echo -e "    ${CYAN}./motspilot.sh tasks${NC}                               List active tasks"
            echo -e "    ${CYAN}./motspilot.sh tasks --all${NC}                         List active + archived tasks"
            echo -e "    ${CYAN}./motspilot.sh status [--task=<name>]${NC}              Detailed task status"
            echo -e "    ${CYAN}./motspilot.sh archive --task=<name>${NC}               Archive a completed task"
            echo -e "    ${CYAN}./motspilot.sh reactivate <name>${NC}                   Restore task from archive"
            echo -e "    ${CYAN}./motspilot.sh reset --task=<name>${NC}                 Reset phase artifacts (keeps requirements)"
            echo -e "    ${CYAN}./motspilot.sh view <phase> [--task=<name>]${NC}        View a phase artifact"
            echo ""
            echo -e "  ${BOLD}Global flag:${NC}  ${CYAN}--project=<path>${NC}  Override project directory detection"
            echo ""
            echo -e "  ${BOLD}Tip:${NC}  Omit ${CYAN}--task=${NC} on any command to get an interactive task picker."
            echo ""
            echo -e "  ${BOLD}Phases:${NC}  architecture · development · testing · verification · delivery"
            echo -e "  ${BOLD}View shortcuts:${NC}  req · arch · dev · test · verify · wo (workorder)"
            echo ""
            echo -e "  ${BOLD}Setup:${NC}"
            echo ""
            echo -e "    ${DIM}# Option A: Symlink the directory${NC}"
            echo -e "    ln -s /path/to/motspilot myproject/motspilot"
            echo -e "    cd myproject && ./motspilot/motspilot.sh init"
            echo ""
            echo -e "    ${DIM}# Option B: Symlink just the script${NC}"
            echo -e "    ln -s /path/to/motspilot/motspilot.sh myproject/motspilot.sh"
            echo -e "    cd myproject && ./motspilot.sh init"
            echo ""
            echo -e "    ${DIM}# Option C: Run directly from project dir${NC}"
            echo -e "    cd myproject && bash /path/to/motspilot/motspilot.sh init"
            echo ""
            echo -e "  ${BOLD}Workflow:${NC}"
            echo ""
            echo -e "    1. ${YELLOW}./motspilot.sh go --task=add-csv \"Add CSV export\"${NC}"
            echo -e "    2. ${YELLOW}Claude Code: run motspilot pipeline${NC}      ← AI orchestrates all phases"
            echo -e "    3. Task auto-archives on completion"
            echo ""
            echo -e "  ${BOLD}Bug fix on completed task:${NC}"
            echo ""
            echo -e "    1. ${YELLOW}./motspilot.sh reactivate add-csv${NC}"
            echo -e "    2. ${YELLOW}./motspilot.sh go --task=add-csv --from=development${NC}"
            echo -e "    3. ${YELLOW}Claude Code: run motspilot pipeline${NC}"
            echo ""
            ;;
    esac
}

main "$@"
