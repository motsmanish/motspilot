# shellcheck shell=bash
# motspilot — task-name slugify and validation.
# Sourced by motspilot.sh; not meant to be run on its own.

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
    if [[ ! "$name" =~ ^[a-z0-9][a-z0-9._-]*[a-z0-9]$|^[a-z0-9]$ ]]; then
        log ERROR "Invalid task name: '${name}'"
        log INFO "Use lowercase letters, numbers, '-', '_', or '.' only; must start and end with a letter or digit (e.g. add-csv-export, 01e_owasp-8.2.3-input-validation)"
        return 1
    fi
}
