# shellcheck shell=bash
# motspilot — phase definitions and phase-name lookup.
# Sourced by motspilot.sh; not meant to be run on its own.

# ─── Phase definitions ───────────────────────────────────────────────────────

AUTO_PHASES=("architecture" "development" "testing" "verification" "delivery")
# shellcheck disable=SC2034 # read in other lib/ modules
ALL_PHASES=("requirements" "architecture" "development" "testing" "verification" "delivery")

# shellcheck disable=SC2034 # read in other lib/ modules
declare -A PHASE_NUM=(
    [requirements]="01"
    [architecture]="02"
    [development]="03"
    [testing]="04"
    [verification]="05"
    [delivery]="06"
)

# shellcheck disable=SC2034 # read in other lib/ modules
declare -A PHASE_SHORT=(
    [requirements]="req  "
    [architecture]="arch "
    [development]="dev  "
    [testing]="test "
    [verification]="vrfy "
    [delivery]="dlvr "
)

# ─── Phase validation ────────────────────────────────────────────────────────

phase_index() {
    local target="$1"
    for i in "${!AUTO_PHASES[@]}"; do
        [[ "${AUTO_PHASES[$i]}" == "$target" ]] && echo "$i" && return
    done
    echo "-1"
}
