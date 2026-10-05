# shellcheck shell=bash
# motspilot — init/go/tasks/status/archive/reactivate/reset/view commands.
# Sourced by motspilot.sh; not meant to be run on its own.

# ── init ────────────────────────────────────────────────────────────
cmd_init() {
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
}

# ── go ──────────────────────────────────────────────────────────────
cmd_go() {
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
}

# ── tasks ───────────────────────────────────────────────────────────
cmd_tasks() {
    local include_archived="false"
    for arg in "$@"; do
        [[ "$arg" == "--all" ]] && include_archived="true"
    done
    list_tasks "$include_archived"
}

# ── status ──────────────────────────────────────────────────────────
cmd_status() {
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
}

# ── archive ─────────────────────────────────────────────────────────
cmd_archive() {
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
}

# ── reactivate ──────────────────────────────────────────────────────
cmd_reactivate() {
    local task_name="${1:-}"
    if [[ -z "$task_name" ]]; then
        if pick_task "archived"; then
            task_name="$PICKED_TASK"
        else
            exit 1
        fi
    fi
    reactivate_task "$task_name"
}

# ── reset ───────────────────────────────────────────────────────────
cmd_reset() {
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
}

# ── view ────────────────────────────────────────────────────────────
cmd_view() {
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
}
