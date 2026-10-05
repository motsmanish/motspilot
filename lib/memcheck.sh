# shellcheck shell=bash
# motspilot — mem-check command.
# Sourced by motspilot.sh; not meant to be run on its own.

# ── mem-check ────────────────────────────────────────────────────────
cmd_mem_check() {
    local mem_dir="$HOME/.claude/projects"
    local mem_file=""
    # Find the MEMORY.md for the current project
    local sanitized
    sanitized=$(echo "$PROJECT_DIR" | sed 's|/|-|g; s|^-||')
    local candidate="$mem_dir/-${sanitized}/memory/MEMORY.md"
    if [[ -f "$candidate" ]]; then
        mem_file="$candidate"
    else
        # Fallback: search for it
        mem_file=$(find "$mem_dir" -name "MEMORY.md" -path "*memory/MEMORY.md" 2>/dev/null | head -1 || true)
    fi

    if [[ -z "$mem_file" || ! -f "$mem_file" ]]; then
        log WARN "Could not find MEMORY.md for this project"
        exit 1
    fi

    local max_lines=200
    local max_bytes=25000
    local line_count byte_count

    line_count=$(wc -l <"$mem_file")
    byte_count=$(wc -c <"$mem_file")

    echo -e "  ${BOLD}Memory Index Check${NC}  ${DIM}${mem_file}${NC}"
    echo ""

    # Line cap
    if ((line_count > max_lines)); then
        echo -e "  ${RED}OVER${NC}  Lines: ${line_count}/${max_lines} — truncation will occur"
    elif ((line_count > max_lines * 80 / 100)); then
        echo -e "  ${YELLOW}WARN${NC}  Lines: ${line_count}/${max_lines} — approaching cap (${max_lines})"
    else
        echo -e "  ${GREEN}  OK${NC}  Lines: ${line_count}/${max_lines}"
    fi

    # Byte cap
    if ((byte_count > max_bytes)); then
        echo -e "  ${RED}OVER${NC}  Bytes: ${byte_count}/${max_bytes} — truncation will occur"
    elif ((byte_count > max_bytes * 80 / 100)); then
        echo -e "  ${YELLOW}WARN${NC}  Bytes: ${byte_count}/${max_bytes} — approaching cap (${max_bytes})"
    else
        echo -e "  ${GREEN}  OK${NC}  Bytes: ${byte_count}/${max_bytes}"
    fi

    # Memory staleness check (Idea 12)
    echo ""
    local stale_count=0
    local mem_topic_dir
    mem_topic_dir=$(dirname "$mem_file")
    for topic_file in "$mem_topic_dir"/*.md; do
        [[ "$(basename "$topic_file")" == "MEMORY.md" ]] && continue
        [[ ! -f "$topic_file" ]] && continue
        local mtime_epoch now_epoch age_days
        mtime_epoch=$(stat -c %Y "$topic_file" 2>/dev/null || stat -f %m "$topic_file" 2>/dev/null)
        now_epoch=$(date +%s)
        age_days=$(((now_epoch - mtime_epoch) / 86400))
        if ((age_days > 7)); then
            echo -e "  ${YELLOW}STALE${NC}  $(basename "$topic_file") — ${age_days} days old"
            stale_count=$((stale_count + 1))
        fi
    done
    if ((stale_count == 0)); then
        echo -e "  ${GREEN}  OK${NC}  No stale topic files (>7 days)"
    fi
    echo ""
}
