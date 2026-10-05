# shellcheck shell=bash
# motspilot — list, status, archive, reactivate, reset, view.
# Sourced by motspilot.sh; not meant to be run on its own.

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
