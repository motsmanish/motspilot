#!/usr/bin/env bats
#
# Lifecycle tests for motspilot.sh — exercises the real script end-to-end
# against a throwaway project directory per test.
#
# Run: bats tests/lifecycle.bats

MOTSPILOT="${BATS_TEST_DIRNAME}/../motspilot.sh"

setup() {
    PROJ="${BATS_TEST_TMPDIR}/proj"
    FAKE_HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "$PROJ" "$FAKE_HOME"
    PROJ="$(cd "$PROJ" && pwd)"
    WS="${PROJ}/.motspilot/workspace"
}

# Run motspilot against the test project. HOME is isolated so mem-check never
# reads the real ~/.claude, and stdin is closed so an unexpected interactive
# prompt fails fast instead of hanging.
ms() {
    HOME="$FAKE_HOME" bash "$MOTSPILOT" --project="$PROJ" "$@" </dev/null
}

# Same as ms, but feeds $1 to stdin (for confirmation prompts).
ms_input() {
    local input="$1"
    shift
    HOME="$FAKE_HOME" bash "$MOTSPILOT" --project="$PROJ" "$@" <<<"$input"
}

init_with_task() {
    ms init >/dev/null
    ms go --task=demo "demo task" >/dev/null
}

meta_value() {
    grep "^$2=" "$1/meta" | cut -d= -f2-
}

# Path where Claude Code keeps this project's memory index.
memory_dir() {
    echo "${FAKE_HOME}/.claude/projects/-$(echo "$PROJ" | sed 's|/|-|g; s|^-||')/memory"
}

# ─── help ────────────────────────────────────────────────────────────────────

@test "help lists every subcommand" {
    run ms help
    [ "$status" -eq 0 ]
    for cmd in init go tasks status archive reactivate reset view mem-check; do
        [[ "$output" == *"motspilot.sh ${cmd}"* ]]
    done
}

@test "unknown command falls back to help" {
    run ms frobnicate
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# ─── init ────────────────────────────────────────────────────────────────────

@test "init creates .motspilot/config on first run" {
    run ms init
    [ "$status" -eq 0 ]
    [[ "$output" == *"First-time setup complete"* ]]
    [ -f "$PROJ/.motspilot/config" ]
}

@test "init on configured project creates workspace dirs" {
    ms init >/dev/null
    run ms init
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ready."* ]]
    [ -d "$WS/tasks" ]
    [ -d "$WS/archive" ]
}

@test "init does not overwrite an edited config" {
    ms init >/dev/null
    echo 'FRAMEWORK="laravel"' >>"$PROJ/.motspilot/config"
    ms init >/dev/null
    grep -q '^FRAMEWORK="laravel"' "$PROJ/.motspilot/config"
}

# ─── go ──────────────────────────────────────────────────────────────────────

# Current behavior: every non-init command runs ensure_config, which creates a
# default config when missing — so `go` works without a prior `init` and the
# "Run ./motspilot.sh init first" guard in `go` is unreachable.
@test "go before init auto-creates a default config" {
    run ms go --task=demo "demo task"
    [ "$status" -eq 0 ]
    [ -f "$PROJ/.motspilot/config" ]
    [ -f "$WS/tasks/demo/01_requirements.md" ]
}

@test "go --task creates task with requirements, meta, and workorder" {
    ms init >/dev/null
    run ms go --task=demo "demo task"
    [ "$status" -eq 0 ]
    [ -f "$WS/tasks/demo/01_requirements.md" ]
    [ -f "$WS/tasks/demo/pipeline_workorder.md" ]
    grep -q '^demo task$' "$WS/tasks/demo/01_requirements.md"
    # create_task writes "pending"; write_workorder then marks it in_progress.
    [ "$(meta_value "$WS/tasks/demo" STATUS)" = "in_progress" ]
    [ "$(meta_value "$WS/tasks/demo" DESCRIPTION)" = "demo task" ]
    [ "$(cat "$PROJ/.motspilot/current_task")" = "demo" ]
}

@test "go without --task auto-names from the description" {
    ms init >/dev/null
    run ms go "Add CSV Export!"
    [ "$status" -eq 0 ]
    [ -d "$WS/tasks/add-csv-export" ]
}

@test "go on existing task keeps edited requirements" {
    init_with_task
    printf '# Feature Requirements\n\n## Request\nhand-edited\n' >"$WS/tasks/demo/01_requirements.md"
    run ms go --task=demo "a different description"
    [ "$status" -eq 0 ]
    grep -q '^hand-edited$' "$WS/tasks/demo/01_requirements.md"
    ! grep -q 'a different description' "$WS/tasks/demo/01_requirements.md"
}

@test "go --from=<phase> rejects an unknown phase" {
    ms init >/dev/null
    run ms go --task=demo --from=deploy "demo task"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown phase: deploy"* ]]
}

@test "go refuses a task that only exists in the archive" {
    init_with_task
    ms archive --task=demo >/dev/null
    run ms go --task=demo "demo task"
    [ "$status" -ne 0 ]
    [[ "$output" == *"is in the archive"* ]]
    [ ! -d "$WS/tasks/demo" ]
}

# ─── task-name validation ────────────────────────────────────────────────────

@test "task name accepts underscores in interior" {
    ms init >/dev/null
    run ms go --task=01e_owasp-input "underscores"
    [ "$status" -eq 0 ]
}

@test "task name accepts dots in interior" {
    ms init >/dev/null
    run ms go --task=task-v1.2.3 "dots"
    [ "$status" -eq 0 ]
}

@test "task name accepts a single character" {
    ms init >/dev/null
    run ms go --task=a "single char"
    [ "$status" -eq 0 ]
}

@test "task name rejects leading dot, trailing dash, uppercase, and path traversal" {
    ms init >/dev/null
    for bad in .hidden trailing- Demo ../escape; do
        run ms go --task="$bad" "bad name"
        [ "$status" -ne 0 ]
        [[ "$output" == *"Invalid task name"* ]]
    done
    [ -z "$(ls -A "$WS/tasks")" ]
    [ ! -e "$WS/escape" ]
}

# ─── tasks / status / view ───────────────────────────────────────────────────

@test "tasks lists active tasks; --all also lists archived ones" {
    init_with_task
    ms go --task=other "other task" >/dev/null
    ms archive --task=other >/dev/null

    run ms tasks
    [ "$status" -eq 0 ]
    [[ "$output" == *"demo"* ]]
    [[ "$output" != *"other"* ]]

    run ms tasks --all
    [ "$status" -eq 0 ]
    [[ "$output" == *"demo"* ]]
    [[ "$output" == *"other"* ]]
}

@test "status --task shows description and phase artifacts" {
    init_with_task
    echo "arch" >"$WS/tasks/demo/02_architecture.md"
    run ms status --task=demo
    [ "$status" -eq 0 ]
    [[ "$output" == *"demo task"* ]]
    [[ "$output" == *"in_progress"* ]]
    [[ "$output" == *"architecture"*"(5 bytes)"* ]]
}

@test "status on a missing task fails" {
    ms init >/dev/null
    run ms status --task=nope
    [ "$status" -ne 0 ]
    [[ "$output" == *"Task not found: nope"* ]]
}

@test "status with no --task and no current task uses the picker" {
    init_with_task
    : >"$PROJ/.motspilot/current_task"
    run ms_input 1 status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Select a task:"* ]]
    [[ "$output" == *"Task: "*"demo"* ]]
}

@test "picker rejects an out-of-range choice" {
    init_with_task
    : >"$PROJ/.motspilot/current_task"
    run ms_input 9 status
    [ "$status" -ne 0 ]
    [[ "$output" != *"Task: "*"demo"* ]]
}

@test "view prints an artifact via its shortcut" {
    init_with_task
    run ms view req --task=demo
    [ "$status" -eq 0 ]
    [[ "$output" == *"## Request"* ]]
}

@test "view rejects an unknown phase" {
    init_with_task
    run ms view bogus --task=demo
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown phase: bogus"* ]]
}

# ─── reset ───────────────────────────────────────────────────────────────────

@test "reset confirmed with y clears phase artifacts but keeps requirements" {
    init_with_task
    echo "fake" >"$WS/tasks/demo/02_architecture.md"
    echo "fake" >"$WS/tasks/demo/06_delivery.md"
    run ms_input y reset --task=demo
    [ "$status" -eq 0 ]
    [ ! -f "$WS/tasks/demo/02_architecture.md" ]
    [ ! -f "$WS/tasks/demo/06_delivery.md" ]
    [ ! -f "$WS/tasks/demo/pipeline_workorder.md" ]
    [ -f "$WS/tasks/demo/01_requirements.md" ]
    [ "$(meta_value "$WS/tasks/demo" STATUS)" = "pending" ]
}

@test "reset declined keeps phase artifacts" {
    init_with_task
    echo "fake" >"$WS/tasks/demo/02_architecture.md"
    run ms_input n reset --task=demo
    [ "$status" -eq 0 ]
    [[ "$output" == *"Reset cancelled"* ]]
    [ -f "$WS/tasks/demo/02_architecture.md" ]
}

# ─── archive / reactivate ────────────────────────────────────────────────────

@test "archive moves task to archive/ and clears current task" {
    init_with_task
    run ms archive --task=demo
    [ "$status" -eq 0 ]
    [ ! -d "$WS/tasks/demo" ]
    [ -d "$WS/archive/demo" ]
    [ "$(meta_value "$WS/archive/demo" STATUS)" = "completed" ]
    grep -q '^ARCHIVED_AT=' "$WS/archive/demo/meta"
    [ ! -s "$PROJ/.motspilot/current_task" ]
}

@test "archive on a missing task fails" {
    ms init >/dev/null
    run ms archive --task=nope
    [ "$status" -ne 0 ]
    [[ "$output" == *"Task not found: nope"* ]]
}

@test "reactivate restores an archived task as current and in_progress" {
    init_with_task
    ms archive --task=demo >/dev/null
    run ms reactivate demo
    [ "$status" -eq 0 ]
    [ -d "$WS/tasks/demo" ]
    [ ! -d "$WS/archive/demo" ]
    [ "$(meta_value "$WS/tasks/demo" STATUS)" = "in_progress" ]
    grep -q '^REACTIVATED_AT=' "$WS/tasks/demo/meta"
    [ "$(cat "$PROJ/.motspilot/current_task")" = "demo" ]
}

@test "reactivate fails when nothing is archived under that name" {
    ms init >/dev/null
    run ms reactivate nope
    [ "$status" -ne 0 ]
    [[ "$output" == *"No archived task found: nope"* ]]
}

@test "full cycle: go, archive, reactivate, go --from" {
    init_with_task
    ms archive --task=demo >/dev/null
    ms reactivate demo >/dev/null
    run ms go --task=demo --from=development
    [ "$status" -eq 0 ]
    grep -q 'development' "$WS/tasks/demo/pipeline_workorder.md"
}

# ─── WORKSPACE_DIR ───────────────────────────────────────────────────────────

@test "WORKSPACE_DIR in config relocates tasks and archive" {
    ms init >/dev/null
    sed -i.bak 's/^WORKSPACE_DIR=""/WORKSPACE_DIR="motspilot-data"/' "$PROJ/.motspilot/config"
    ms go --task=demo "demo task" >/dev/null
    [ -f "$PROJ/motspilot-data/tasks/demo/01_requirements.md" ]
    [ ! -d "$WS/tasks/demo" ]

    ms archive --task=demo >/dev/null
    [ -d "$PROJ/motspilot-data/archive/demo" ]
}

# ─── install shapes ──────────────────────────────────────────────────────────

@test "symlinked motspilot dir resolves the project without --project" {
    ln -s "$(cd "$BATS_TEST_DIRNAME/.." && pwd)" "$PROJ/motspilot"
    cd "$PROJ"
    HOME="$FAKE_HOME" ./motspilot/motspilot.sh init </dev/null >/dev/null
    run env HOME="$FAKE_HOME" ./motspilot/motspilot.sh go --task=demo "demo task" </dev/null
    [ "$status" -eq 0 ]
    [ -f "$PROJ/.motspilot/workspace/tasks/demo/01_requirements.md" ]
}

@test "symlinked script file resolves the project and its tool dir" {
    ln -s "$(cd "$BATS_TEST_DIRNAME/.." && pwd)/motspilot.sh" "$PROJ/motspilot.sh"
    cd "$PROJ"
    HOME="$FAKE_HOME" ./motspilot.sh init </dev/null >/dev/null
    run env HOME="$FAKE_HOME" ./motspilot.sh go --task=demo "demo task" </dev/null
    [ "$status" -eq 0 ]
    [ -f "$PROJ/.motspilot/workspace/tasks/demo/01_requirements.md" ]
}

@test "direct run from the project dir uses CWD as the project" {
    cd "$PROJ"
    HOME="$FAKE_HOME" bash "$MOTSPILOT" init </dev/null >/dev/null
    run env HOME="$FAKE_HOME" bash "$MOTSPILOT" go --task=demo "demo task" </dev/null
    [ "$status" -eq 0 ]
    [ -f "$PROJ/.motspilot/workspace/tasks/demo/01_requirements.md" ]
}

# ─── mem-check ───────────────────────────────────────────────────────────────

@test "mem-check reports OK on a healthy index for this project" {
    ms init >/dev/null
    mkdir -p "$(memory_dir)"
    echo "- [A](a.md) — note" >"$(memory_dir)/MEMORY.md"
    # A different project's index must not be picked over this one.
    mkdir -p "$FAKE_HOME/.claude/projects/-aaa-other/memory"
    echo "other" >"$FAKE_HOME/.claude/projects/-aaa-other/memory/MEMORY.md"

    run ms mem-check
    [ "$status" -eq 0 ]
    [[ "$output" == *"$(memory_dir)/MEMORY.md"* ]]
    [[ "$output" == *"Lines: 1/200"* ]]
    [[ "$output" == *"No stale topic files"* ]]
}

@test "mem-check flags an index over the line cap" {
    ms init >/dev/null
    mkdir -p "$(memory_dir)"
    for _ in $(seq 1 201); do echo "- line"; done >"$(memory_dir)/MEMORY.md"
    run ms mem-check
    [ "$status" -eq 0 ]
    [[ "$output" == *"OVER"*"Lines: 201/200"* ]]
}

@test "mem-check lists every stale topic file" {
    ms init >/dev/null
    mkdir -p "$(memory_dir)"
    echo "- index" >"$(memory_dir)/MEMORY.md"
    echo "old" >"$(memory_dir)/old-one.md"
    echo "old" >"$(memory_dir)/old-two.md"
    touch -t 202001010000 "$(memory_dir)/old-one.md" "$(memory_dir)/old-two.md"
    run ms mem-check
    [ "$status" -eq 0 ]
    [[ "$output" == *"STALE"*"old-one.md"* ]]
    [[ "$output" == *"STALE"*"old-two.md"* ]]
}

@test "mem-check fails when no memory index exists" {
    ms init >/dev/null
    run ms mem-check
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not find MEMORY.md"* ]]
}
