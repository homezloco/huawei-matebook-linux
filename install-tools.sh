#!/usr/bin/env bash
# =============================================================================
# Install all Huawei MateBook management tools
# =============================================================================

set -euo pipefail

# Colors
GRN='\033[0;32m'
BLD='\033[1m'
RST='\033[0m'

ok() { echo -e "${GRN}✓${RST} $*"; }
hdr() { echo -e "\n${BLD}$*${RST}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$SCRIPT_DIR"

hdr "Installing Huawei MateBook Tools"
echo ""

# Install main huawei CLI
if [[ -f huawei-cli ]]; then
    sudo cp huawei-cli /usr/local/bin/huawei
    sudo chmod +x /usr/local/bin/huawei
    ok "Installed: huawei"
fi

# Install thermal management
if [[ -f huawei-thermal.sh ]]; then
    sudo cp huawei-thermal.sh /usr/local/bin/huawei-thermal
    sudo chmod +x /usr/local/bin/huawei-thermal
    ok "Installed: huawei-thermal"
fi

# Install phone integration
if [[ -f huawei-connect ]]; then
    sudo cp huawei-connect /usr/local/bin/huawei-connect
    sudo chmod +x /usr/local/bin/huawei-connect
    ok "Installed: huawei-connect"
fi

# Install display management
if [[ -f huawei-display ]]; then
    sudo cp huawei-display /usr/local/bin/huawei-display
    sudo chmod +x /usr/local/bin/huawei-display
    ok "Installed: huawei-display"
fi

# Install backup tool
if [[ -f huawei-backup ]]; then
    sudo cp huawei-backup /usr/local/bin/huawei-backup
    sudo chmod +x /usr/local/bin/huawei-backup
    ok "Installed: huawei-backup"
fi

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
echo "Camera driver stack is installed separately (DKMS):"
echo "  sudo ${SCRIPT_DIR}/camera/install.sh"
echo ""
