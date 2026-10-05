# shellcheck shell=bash
# motspilot — interactive task picker.
# Sourced by motspilot.sh; not meant to be run on its own.

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

        local status
        status=$(grep -i "^STATUS=" "$meta_file" | head -1 | cut -d= -f2- || echo "")

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

    # shellcheck disable=SC2034 # read in other lib/ modules
    PICKED_TASK="${tasks[$((choice - 1))]}"
    return 0
}
