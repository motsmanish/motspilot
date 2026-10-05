# shellcheck shell=bash
# motspilot — project root detection, state and workspace paths, task dirs.
# Sourced by motspilot.sh; not meant to be run on its own.

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
# shellcheck disable=SC2034 # read in other lib/ modules
CONFIG_FILE="${STATE_DIR}/config"
# shellcheck disable=SC2034 # read in other lib/ modules
CURRENT_TASK_FILE="${STATE_DIR}/current_task"

# Workspace paths (defaults — may be overridden by WORKSPACE_DIR in config)
WORK_DIR="${STATE_DIR}/workspace"
TASKS_DIR="${WORK_DIR}/tasks"
ARCHIVE_DIR="${WORK_DIR}/archive"

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
