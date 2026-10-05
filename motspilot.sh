#!/usr/bin/env bash
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

# ─── Modules ─────────────────────────────────────────────────────────────────
# Sourced at top level (not inside a function) so `declare -A` and other
# module globals stay global. Order matters: workspace.sh runs project
# detection on load and needs MOTSPILOT_DIR.

# shellcheck source=lib/log.sh
source "${MOTSPILOT_DIR}/lib/log.sh"
# shellcheck source=lib/workspace.sh
source "${MOTSPILOT_DIR}/lib/workspace.sh"
# shellcheck source=lib/config.sh
source "${MOTSPILOT_DIR}/lib/config.sh"
# shellcheck source=lib/phases.sh
source "${MOTSPILOT_DIR}/lib/phases.sh"
# shellcheck source=lib/validate.sh
source "${MOTSPILOT_DIR}/lib/validate.sh"
# shellcheck source=lib/meta.sh
source "${MOTSPILOT_DIR}/lib/meta.sh"
# shellcheck source=lib/tasks.sh
source "${MOTSPILOT_DIR}/lib/tasks.sh"
# shellcheck source=lib/lifecycle.sh
source "${MOTSPILOT_DIR}/lib/lifecycle.sh"
# shellcheck source=lib/picker.sh
source "${MOTSPILOT_DIR}/lib/picker.sh"
# shellcheck source=lib/commands.sh
source "${MOTSPILOT_DIR}/lib/commands.sh"
# shellcheck source=lib/memcheck.sh
source "${MOTSPILOT_DIR}/lib/memcheck.sh"
# shellcheck source=lib/help.sh
source "${MOTSPILOT_DIR}/lib/help.sh"

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
        init) cmd_init "$@" ;;
        go) cmd_go "$@" ;;
        tasks) cmd_tasks "$@" ;;
        status) cmd_status "$@" ;;
        archive) cmd_archive "$@" ;;
        reactivate) cmd_reactivate "$@" ;;
        reset) cmd_reset "$@" ;;
        view) cmd_view "$@" ;;
        mem-check) cmd_mem_check "$@" ;;
        help | --help | -h | *) cmd_help ;;
    esac
}

main "$@"
