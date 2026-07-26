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

# --- Secure Boot signing -----------------------------------------------------
# Under Secure Boot an unsigned module builds and installs happily, then the
# kernel refuses to load it at boot — so the camera stays broken with no error
# from this script. Worse, DKMS defaults to signing with MOK.priv + MOK.der,
# and a machine can easily end up with several MOK generations where those two
# are not a pair (kmodsign then fails with "key values mismatch" mid-build).
# So: find which certificate actually matches the private key, confirm it is
# enrolled, and point DKMS at it explicitly.
MOK_DIR=/var/lib/shim-signed/mok
MOK_KEY="${MOK_DIR}/MOK.priv"
DKMS_MOK_CONF=/etc/dkms/framework.conf.d/huawei-matebook-mok.conf

_priv_pub() { openssl rsa  -in "$1" -pubout            2>/dev/null; }
_cert_pub() { openssl x509 -in "$1" -inform "$2" -pubkey -noout 2>/dev/null; }

_cert_enrolled() {
    # mokutil --test-key needs DER. Match on its message, not its exit status:
    # it also probes the kernel trusted keyring, and when that is unavailable
    # ("Failed to accesss kernel trusted keyring") it exits 1 even while
    # correctly reporting the certificate as enrolled.
    local out
    out="$(mokutil --test-key "$1" 2>/dev/null || true)"
    [[ "$out" == *"is already enrolled"* ]]
}

configure_signing() {
    if ! command -v mokutil >/dev/null \
       || ! mokutil --sb-state 2>/dev/null | grep "enabled" >/dev/null; then
        ok "Secure Boot off (or mokutil absent) — no signing required"
        return 0
    fi

    if [[ ! -f "$MOK_KEY" ]]; then
        warn "Secure Boot is on but there is no signing key at ${MOK_KEY}"
        dim "Modules will build but the kernel will refuse to load them."
        dim "Create and enroll one, then re-run this script:"
        dim "  sudo update-secureboot-policy --new-key"
        dim "  sudo mokutil --import ${MOK_DIR}/MOK.der   # then reboot and Enroll MOK"
        return 0
    fi

    local priv_pub match="" match_der=""
    priv_pub="$(_priv_pub "$MOK_KEY")"
    [[ -n "$priv_pub" ]] || die "Cannot read the private key ${MOK_KEY}"

    # Test every certificate lying around against the private key.
    local c fmt
    for c in "${MOK_DIR}"/*.der "${MOK_DIR}"/*.pem "${MOK_DIR}"/*.crt; do
        [[ -f "$c" ]] || continue
        case "$c" in
            *.der) fmt=DER ;;
            *)     fmt=PEM ;;
        esac
        if [[ "$(_cert_pub "$c" "$fmt")" == "$priv_pub" ]]; then
            match="$c"; break
        fi
    done

    if [[ -z "$match" ]]; then
        warn "No certificate in ${MOK_DIR} matches ${MOK_KEY}"
        dim "DKMS signing will fail and the modules will not load under Secure Boot."
        dim "Generate a fresh matching pair and enroll it:"
        dim "  sudo update-secureboot-policy --new-key"
        dim "  sudo mokutil --import ${MOK_DIR}/MOK.der   # then reboot and Enroll MOK"
        return 0
    fi
    ok "Signing key matches $(basename "$match")"

    # mokutil needs DER; make one if the matching cert is PEM.
    if [[ "$match" == *.der ]]; then
        match_der="$match"
    else
        match_der="${MOK_DIR}/MOK-dkms.der"
        openssl x509 -in "$match" -outform DER -out "$match_der" 2>/dev/null \
            || die "Could not convert $(basename "$match") to DER"
        chmod 644 "$match_der"
        dim "Wrote DER form for DKMS: ${match_der}"
    fi

    if _cert_enrolled "$match_der"; then
        ok "Certificate is enrolled in the MOK list"
    else
        warn "$(basename "$match") matches the key but is NOT enrolled"
        dim "Modules will be signed but still refused at boot. Enroll it:"
        dim "  sudo mokutil --import ${match_der}"
        dim "then reboot and choose 'Enroll MOK' (you will be asked for a password)."
    fi

    # Pin the pair for DKMS. framework.conf.d overrides framework.conf without
    # editing a distro-managed file, and applies to the automatic rebuilds that
    # run on future kernel upgrades too — not just this invocation.
    mkdir -p "$(dirname "$DKMS_MOK_CONF")"
    cat > "$DKMS_MOK_CONF" <<EOF
# Written by camera/install.sh — huawei-matebook-linux
# DKMS defaults to MOK.priv + MOK.der; on this machine those are from
# different key generations and do not pair. Pin the matching, enrolled pair.
mok_signing_key="${MOK_KEY}"
mok_certificate="${match_der}"
EOF
    ok "Pinned DKMS signing pair in $(basename "$DKMS_MOK_CONF")"
}

configure_signing

# --- Install source trees ----------------------------------------------------
hdr "Installing DKMS sources"

for pkg in "${PACKAGES[@]}"; do
    src="/usr/src/${pkg}-${VERSION}"

    # Drop any previous registration so a re-run picks up edited sources
    # instead of rebuilding the stale copy already in /usr/src.
    if [[ -n "$(dkms status -m "$pkg" -v "$VERSION" 2>/dev/null)" ]]; then
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
    # Count matches rather than `grep -q`: -q exits on the first hit, which
    # SIGPIPEs `strings`, and under `set -o pipefail` the pipeline then reports
    # failure — this very check claimed the entry was missing when it was there.
    hits="$({ [[ "$bridge" == *.zst ]] && zstd -dc "$bridge" || cat "$bridge"; } \
        | strings | grep -c GCTI2607 || true)"
    if [[ "${hits:-0}" -gt 0 ]]; then
        ok "ipu-bridge carries the GCTI2607 entry"
    else
        warn "ipu-bridge built but GCTI2607 not found in it"
    fi
else
    warn "ipu-bridge module not found under updates/dkms"
fi

# A module that built fine but is unsigned will still be refused at boot under
# Secure Boot, so surface that here rather than leaving it to a silent failure.
for m in gc2607 ipu-bridge; do
    mk="/lib/modules/${KVER}/updates/dkms/${m}.ko"
    [[ -f "$mk" ]] || mk="${mk}.zst"
    [[ -f "$mk" ]] || continue
    sig="$({ [[ "$mk" == *.zst ]] && zstd -dc "$mk" || cat "$mk"; } \
        | strings | grep -c "Module signature appended" || true)"
    if [[ "${sig:-0}" -gt 0 ]]; then
        ok "${m} is signed"
    elif command -v mokutil >/dev/null && mokutil --sb-state 2>/dev/null | grep "enabled" >/dev/null; then
        err "${m} is UNSIGNED — Secure Boot will refuse to load it"
    else
        dim "  ${m} unsigned (fine: Secure Boot is off)"
    fi
done

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
