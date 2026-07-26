#!/usr/bin/env bash
# =============================================================================
# Install all Huawei MateBook management tools
#
#   ./install-tools.sh          copy into /usr/local/bin (normal install)
#   ./install-tools.sh --link   symlink to this checkout (development)
#
# Use --link when you are editing the tools in place: a copy goes stale the
# moment you change a script, and it is easy to spend a while debugging output
# from a binary that predates your fix. A symlink always runs current code.
# =============================================================================

set -euo pipefail

GRN='\033[0;32m'
YLW='\033[1;33m'
BLD='\033[1m'
DIM='\033[2m'
RST='\033[0m'

ok()   { echo -e "${GRN}✓${RST} $*"; }
warn() { echo -e "${YLW}!${RST} $*"; }
dim()  { echo -e "${DIM}  $*${RST}"; }
hdr()  { echo -e "\n${BLD}$*${RST}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

MODE=copy
case "${1:-}" in
    --link) MODE=link ;;
    --copy|"") MODE=copy ;;
    -h|--help)
        sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
        exit 0 ;;
    *) echo "Unknown option: $1 (use --link, --copy, or --help)" >&2; exit 1 ;;
esac

BIN=/usr/local/bin

# source file : installed command name
TOOLS=(
    "huawei-cli:huawei"
    "huawei-thermal.sh:huawei-thermal"
    "huawei-connect:huawei-connect"
    "huawei-display:huawei-display"
    "huawei-backup:huawei-backup"
)

hdr "Installing Huawei MateBook Tools ($MODE)"
echo ""

for entry in "${TOOLS[@]}"; do
    src="${entry%%:*}"
    name="${entry#*:}"
    [[ -f "$src" ]] || { warn "Skipped: $src not found"; continue; }

    if [[ "$MODE" == link ]]; then
        sudo ln -sfn "${SCRIPT_DIR}/${src}" "${BIN}/${name}"
        chmod +x "${SCRIPT_DIR}/${src}" 2>/dev/null || true
        ok "Linked: ${name} -> ${SCRIPT_DIR}/${src}"
    else
        sudo cp "$src" "${BIN}/${name}"
        sudo chmod +x "${BIN}/${name}"
        ok "Installed: ${name}"
    fi
done

echo ""
hdr "Installation Complete!"
echo ""
echo "Available commands:"
echo "  huawei              - Hardware management"
echo "  huawei-thermal      - Thermal & fan control"
echo "  huawei-connect      - Phone integration"
echo "  huawei-display      - Display & color management"
echo "  huawei-backup       - Backup & sync"
echo ""
echo "Run any command with 'help' for usage:"
echo "  huawei help"
echo ""
if [[ "$MODE" == link ]]; then
    dim "Symlinked — edits to this checkout take effect immediately."
else
    dim "Copied — re-run this script after editing any tool, or use --link."
fi
echo ""
echo "Camera driver stack is installed separately (DKMS):"
echo "  sudo ${SCRIPT_DIR}/camera/install.sh"
echo ""
