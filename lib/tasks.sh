# shellcheck shell=bash
# motspilot — task creation, requirements, work order.
# Sourced by motspilot.sh; not meant to be run on its own.

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
