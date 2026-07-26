#!/usr/bin/env bash
# Remove the Goodix GXFP5130 fingerprint stack installed by install.sh.
set -euo pipefail

need_root() {
    [[ $EUID -eq 0 ]] || { echo "Run as root (sudo $0)" >&2; exit 1; }
}
need_root

VERSION="0.1.0"

echo "Removing gxfp kernel module…"
rmmod gxfp 2>/dev/null || true

echo "Removing DKMS package…"
dkms remove -m gxfp -v "$VERSION" --all >/dev/null 2>&1 || true
rm -rf "/usr/src/gxfp-${VERSION}"

echo "Removing userspace binaries…"
rm -f /usr/local/bin/gxfp_capture /usr/local/bin/gxfp_psk_tool /usr/local/bin/gxfp_recovery

echo "Removing configuration files…"
rm -f /etc/udev/rules.d/60-gxfp.rules
rm -f /etc/systemd/system/fprintd.service.d/gxfp.conf

systemctl daemon-reload
udevadm control --reload-rules

echo ""
echo "✓ gxfp fingerprint stack removed."
echo "Note: enrolled fingerprints and the PSK at /var/lib/fprintd/gxfp/ are not deleted."
