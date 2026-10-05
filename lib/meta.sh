# shellcheck shell=bash
# motspilot — per-task meta file, current task, checkpoints.
# Sourced by motspilot.sh; not meant to be run on its own.

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
