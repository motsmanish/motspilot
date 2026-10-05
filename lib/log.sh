# shellcheck shell=bash
# motspilot — colors, console/file logging, banner.
# Sourced by motspilot.sh; not meant to be run on its own.

# ─── Colors ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
# shellcheck disable=SC2034 # read in other lib/ modules
DIM='\033[2m'
NC='\033[0m'

# ─── Logging ─────────────────────────────────────────────────────────────────

log() {
    local level="$1"
    shift
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    mkdir -p "$LOG_DIR"
    echo -e "${timestamp} [${level}] $*" >>"${LOG_DIR}/motspilot.log"
    case "$level" in
        INFO) echo -e "  ${BLUE}ℹ${NC}  $*" ;;
        OK) echo -e "  ${GREEN}✓${NC}  $*" ;;
        WARN) echo -e "  ${YELLOW}⚠${NC}  $*" ;;
        ERROR) echo -e "  ${RED}✗${NC}  $*" ;;
        PHASE)
            echo -e "\n${CYAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "  ${CYAN}${BOLD}  $*${NC}"
            echo -e "${CYAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
            ;;
    esac
}

show_banner() {
    echo -e "${CYAN}"
    cat <<'BANNER'

    ╔═════════════════════════════════════════════════════╗
    ║                                                     ║
    ║   motspilot — AI Dev Pipeline by MOTSTECH           ║
    ║                                                     ║
    ║   📄 → ⚙️  → 💻 → ✅ → 🔍 → 🚀                     ║
    ║                                                     ║
    ╚═════════════════════════════════════════════════════╝

BANNER
    echo -e "${NC}"
}
