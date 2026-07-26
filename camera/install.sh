#!/usr/bin/env bash
# =============================================================================
# Install the MateBook camera stack as DKMS packages
#
#   gc2607             — V4L2 driver for the GalaxyCore GC2607 sensor
#   ipu-bridge-gc2607  — ipu_bridge rebuilt with a GCTI2607 sensor entry
#
# Both are registered with AUTOINSTALL, so they rebuild on every kernel
# upgrade instead of the camera silently dying until someone runs make by
# hand. Under Secure Boot, DKMS signs the modules with the enrolled MOK key.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; CYN='\033[0;36m'
BLD='\033[1m'; DIM='\033[2m'; RST='\033[0m'

ok()   { echo -e "${GRN}✓${RST} $*"; }
warn() { echo -e "${YLW}!${RST} $*"; }
err()  { echo -e "${RED}✗${RST} $*" >&2; }
info() { echo -e "${CYN}→${RST} $*"; }
dim()  { echo -e "${DIM}  $*${RST}"; }
hdr()  { echo -e "\n${BLD}$*${RST}"; }
die()  { err "$*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KVER="$(uname -r)"

PACKAGES=(gc2607 ipu-bridge-gc2607)
VERSION=1.0

[[ $EUID -eq 0 ]] || die "Run as root: sudo $0"

hdr "MateBook camera stack — DKMS install"
dim "kernel: ${KVER}"

# --- Prerequisites -----------------------------------------------------------
hdr "Checking prerequisites"

command -v dkms  >/dev/null || die "dkms not installed — sudo apt install dkms"
ok "dkms $(dkms --version 2>/dev/null | head -1)"

command -v curl  >/dev/null || die "curl not installed — sudo apt install curl"
ok "curl present"

[[ -d "/lib/modules/${KVER}/build" ]] \
    || die "Kernel headers missing — sudo apt install linux-headers-${KVER}"
ok "kernel headers for ${KVER}"

# Secure Boot: unsigned modules are refused at load time, so catch a missing
# MOK key here rather than after a successful-looking build.
if command -v mokutil >/dev/null && mokutil --sb-state 2>/dev/null | grep -q "enabled"; then
    if [[ -f /var/lib/shim-signed/mok/MOK.priv && -f /var/lib/shim-signed/mok/MOK.der ]]; then
        ok "Secure Boot enabled — DKMS will sign with the enrolled MOK key"
        if ! mokutil --test-key /var/lib/shim-signed/mok/MOK.der 2>/dev/null | grep -q "is already enrolled"; then
            warn "MOK key exists but does not look enrolled"
            dim "Enroll it: sudo mokutil --import /var/lib/shim-signed/mok/MOK.der"
            dim "then reboot and choose 'Enroll MOK' in the blue MOK manager screen."
        fi
    else
        warn "Secure Boot is on but no MOK key at /var/lib/shim-signed/mok/"
        dim "Modules will build but refuse to load. Create and enroll a key first:"
        dim "  sudo update-secureboot-policy --new-key"
        dim "  sudo mokutil --import /var/lib/shim-signed/mok/MOK.der"
    fi
else
    ok "Secure Boot off (or mokutil absent) — no signing required"
fi

# --- Install source trees ----------------------------------------------------
hdr "Installing DKMS sources"

for pkg in "${PACKAGES[@]}"; do
    src="/usr/src/${pkg}-${VERSION}"

    # Drop any previous registration so a re-run picks up edited sources
    # instead of rebuilding the stale copy already in /usr/src.
    if dkms status -m "$pkg" -v "$VERSION" 2>/dev/null | grep -q .; then
        info "Removing previous ${pkg}/${VERSION} registration"
        dkms remove -m "$pkg" -v "$VERSION" --all >/dev/null 2>&1 || true
    fi

    rm -rf "$src"
    mkdir -p "$src"
    cp -a "${SCRIPT_DIR}/${pkg}/." "$src/"
    chmod +x "$src"/*.sh 2>/dev/null || true
    ok "${src}"
done

# --- Build & install ---------------------------------------------------------
hdr "Building"

failed=()
for pkg in "${PACKAGES[@]}"; do
    info "${pkg} ${VERSION} for ${KVER}"
    if dkms install -m "$pkg" -v "$VERSION" -k "$KVER" 2>&1 | sed 's/^/    /'; then
        ok "${pkg} built and installed"
    else
        err "${pkg} failed to build"
        failed+=("$pkg")
    fi
done

if (( ${#failed[@]} )); then
    echo ""
    die "Build failed: ${failed[*]} — see /var/lib/dkms/<pkg>/${VERSION}/build/make.log"
fi

depmod -a "$KVER"
ok "depmod refreshed"

# --- Verify ------------------------------------------------------------------
hdr "Verifying"

bridge="/lib/modules/${KVER}/updates/dkms/ipu-bridge.ko"
for f in "$bridge" "${bridge%.ko}.ko.zst"; do
    [[ -f "$f" ]] && bridge="$f" && break
done

if [[ -f "$bridge" ]]; then
    if { [[ "$bridge" == *.zst ]] && zstd -dc "$bridge" || cat "$bridge"; } \
        | strings | grep -q GCTI2607; then
        ok "ipu-bridge carries the GCTI2607 entry"
    else
        warn "ipu-bridge built but GCTI2607 not found in it"
    fi
else
    warn "ipu-bridge module not found under updates/dkms"
fi

# modprobe resolves through updates/ ahead of kernel/ — confirm that landed.
resolved="$(modinfo -k "$KVER" ipu_bridge 2>/dev/null | awk '/^filename:/{print $2}')"
if [[ "$resolved" == *updates/dkms* ]]; then
    ok "modprobe resolves ipu_bridge to our build"
    dim "$resolved"
else
    warn "modprobe still resolves ipu_bridge to: ${resolved:-<none>}"
    dim "The in-tree module may take precedence; check depmod output."
fi

echo ""
dkms status | grep -E "gc2607|ipu-bridge" | sed 's/^/  /' || true

hdr "Done"
if [[ "$KVER" == "$(uname -r)" ]]; then
    echo "Reboot to load the new module stack, then check:"
else
    echo "Boot into ${KVER}, then check:"
fi
dim "huawei camera status"
dim "sudo huawei camera load && huawei camera test"
echo ""
