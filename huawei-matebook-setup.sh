#!/usr/bin/env bash
# =============================================================================
# Huawei MateBook Linux Setup Script
# Tested on: MateBook X Pro 2024 (VGHH-XX), Ubuntu 24.04, Kernel 6.17
# GitHub issue tracker: https://github.com/intel/ipu6-drivers/issues/399
# =============================================================================

set -euo pipefail

# --- Colours -----------------------------------------------------------------
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
BLU='\033[0;34m'
CYN='\033[0;36m'
BLD='\033[1m'
RST='\033[0m'

# --- Helpers -----------------------------------------------------------------
info()    { echo -e "${BLU}[INFO]${RST}  $*"; }
ok()      { echo -e "${GRN}[OK]${RST}    $*"; }
warn()    { echo -e "${YLW}[WARN]${RST}  $*"; }
error()   { echo -e "${RED}[ERROR]${RST} $*"; }
section() { echo -e "\n${BLD}${CYN}==> $* ${RST}"; }
skip()    { echo -e "${YLW}[SKIP]${RST}  $*"; }

require_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root. Try: sudo $0"
        exit 1
    fi
}

confirm() {
    local prompt="$1"
    read -rp "$(echo -e "${YLW}${prompt} [y/N]: ${RST}")" ans
    [[ "${ans,,}" == "y" ]]
}

# --- Detection ---------------------------------------------------------------
detect_model() {
    local product
    product=$(dmidecode -s system-product-name 2>/dev/null || echo "unknown")
    echo "$product"
}

detect_kernel() {
    uname -r
}

detect_touchpad() {
    grep -qi "GXTP7863" /proc/bus/input/devices 2>/dev/null && echo "present" || echo "absent"
}

detect_ipu6() {
    lsmod | grep -q "intel_ipu6" && echo "loaded" || echo "absent"
}

# --- Banner ------------------------------------------------------------------
print_banner() {
    echo -e "${BLD}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║       Huawei MateBook Linux Hardware Setup Script        ║"
    echo "║              Ubuntu 24.04 · Kernel 6.x                  ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${RST}"

    local model kernel
    model=$(detect_model)
    kernel=$(detect_kernel)

    echo -e "  Model  : ${BLD}${model}${RST}"
    echo -e "  Kernel : ${BLD}${kernel}${RST}"
    echo -e "  Date   : $(date)"
    echo ""

    if [[ "$model" != *"VGHH"* ]]; then
        warn "This script was tested on VGHH-XX (MateBook X Pro 2024)."
        warn "Your model ($model) may differ — proceed with caution."
        confirm "Continue anyway?" || exit 0
    fi
}

# =============================================================================
# FIX 1: Touchpad (GXTP7863 / kernel 6.12+ regression)
# =============================================================================
fix_touchpad() {
    section "Touchpad Fix (GXTP7863 · i2c_hid_acpi rebind)"

    # 1a — libinput quirk
    local quirk_dir="/etc/libinput"
    local quirk_file="$quirk_dir/local-overrides.quirks"

    if grep -q "GXTP7863" "$quirk_file" 2>/dev/null; then
        skip "libinput quirk already present at $quirk_file"
    else
        info "Writing libinput quirk for MateBook X Pro 2024 touchpad..."
        mkdir -p "$quirk_dir"
        cat > "$quirk_file" << 'QUIRK'
[Huawei MateBook X Pro 2024 Touchpad]
MatchName=GXTP7863:00 27C6:01E0 Touchpad
MatchUdevType=touchpad
MatchDMIModalias=dmi:*svnHUAWEI:*pnVGHH-XX*
AttrEventCode=-BTN_RIGHT
ModelPressurePad=1
QUIRK
        ok "libinput quirk written to $quirk_file"
    fi

    # 1b — systemd rebind service
    local svc_file="/etc/systemd/system/touchpad-rebind.service"

    if systemctl is-enabled touchpad-rebind.service &>/dev/null; then
        skip "touchpad-rebind.service already enabled"
    else
        info "Creating touchpad-rebind systemd service..."
        cat > "$svc_file" << 'SVC'
[Unit]
Description=Rebind Huawei MateBook touchpad on boot
After=sysinit.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=/bin/sh -c 'echo i2c-GXTP7863:00 > /sys/bus/i2c/drivers/i2c_hid_acpi/unbind; echo i2c-GXTP7863:00 > /sys/bus/i2c/drivers/i2c_hid_acpi/bind'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVC
        systemctl daemon-reload
        systemctl enable touchpad-rebind.service
        ok "touchpad-rebind.service enabled"
    fi

    # 1c — apply right now without reboot
    info "Triggering touchpad rebind now..."
    echo "i2c-GXTP7863:00" > /sys/bus/i2c/drivers/i2c_hid_acpi/unbind 2>/dev/null || true
    sleep 1
    echo "i2c-GXTP7863:00" > /sys/bus/i2c/drivers/i2c_hid_acpi/bind 2>/dev/null && \
        ok "Touchpad rebound successfully — test it now!" || \
        warn "Rebind attempt returned non-zero (may need reboot)"
}

# =============================================================================
# FIX 2: IPU6 Camera kernel modules
# =============================================================================
fix_camera_modules() {
    section "Camera Kernel Modules (IPU6 · linux-modules-ipu6)"

    if dpkg -l linux-modules-ipu6-"$(uname -r)" &>/dev/null; then
        skip "linux-modules-ipu6-$(uname -r) already installed"
    else
        info "Installing IPU6 and USB-IO kernel modules..."
        apt-get install -y --no-install-recommends \
            linux-modules-ipu6-generic-hwe-24.04 \
            linux-modules-usbio-generic-hwe-24.04 || \
            warn "Module install had errors (DKMS build failure on 6.17 is expected — in-kernel modules are used instead)"
        ok "IPU6 kernel modules installed"
    fi

    # Suppress the broken intel-ipu6-dkms if present — in-kernel modules
    # cover its functionality on 6.17+
    if dpkg -l intel-ipu6-dkms &>/dev/null; then
        warn "intel-ipu6-dkms is installed but fails to build on kernel 6.17+"
        warn "The in-kernel intel_ipu6 module is used instead — this is fine."
        if confirm "Remove intel-ipu6-dkms to suppress recurring build errors?"; then
            apt-get remove -y intel-ipu6-dkms
            ok "intel-ipu6-dkms removed"
        fi
    fi
}

# =============================================================================
# FIX 3: Camera HAL userspace (libcamhal-ipu6epmtl)
# =============================================================================
fix_camera_hal() {
    section "Camera HAL (libcamhal-ipu6epmtl · Dell/Canonical OEM archive)"

    # Check if plugin already in place
    if [[ -f /usr/lib/libcamhal/plugins/ipu6epmtl.so ]]; then
        skip "ipu6epmtl.so already installed at /usr/lib/libcamhal/plugins/"
    else
        info "Adding Dell/Canonical OEM archive (stable, not dev PPA)..."
        apt-get install -y ubuntu-oem-keyring

        local list_file="/etc/apt/sources.list.d/archive_uri-http_dell_archive_canonical_com_-noble.list"
        if [[ ! -f "$list_file" ]]; then
            add-apt-repository -y "deb http://dell.archive.canonical.com/ noble somerville"
            apt-get update -q
        else
            skip "Dell OEM archive already configured"
            apt-get update -q
        fi

        info "Installing libcamhal-ipu6epmtl and GStreamer plugin..."
        apt-get install -y \
            libcamhal0 \
            libcamhal-common \
            libcamhal-ipu6epmtl \
            libcamhal-ipu6epmtl-common \
            libgsticamerainterface-1.0-1 \
            gstreamer1.0-icamera || \
            warn "Some camera HAL packages had dependency issues — partial install"

        if [[ -f /usr/lib/libcamhal/plugins/ipu6epmtl.so ]]; then
            ok "ipu6epmtl.so installed successfully"
        else
            warn "Plugin not found after install — camera HAL may not work yet"
        fi
    fi

    # Known limitation notice
    echo ""
    warn "KNOWN ISSUE: Camera streaming is currently blocked on VGHH-XX by"
    warn "an INT3472 GPIO conflict (kernel bug). The HAL is installed and"
    warn "ready — it will work once the upstream fix lands."
    warn "Track progress: https://github.com/intel/ipu6-drivers/issues/399"
}

# =============================================================================
# FIX 4: Audio check
# =============================================================================
check_audio() {
    section "Audio (PipeWire)"

    if systemctl --user is-active pipewire &>/dev/null; then
        ok "PipeWire is running"
    else
        warn "PipeWire is not running for current user"
        info "Try: systemctl --user start pipewire pipewire-pulse"
    fi

    if command -v wpctl &>/dev/null; then
        local sinks
        sinks=$(wpctl status 2>/dev/null | grep -c "Speaker\|Headphone" || true)
        if [[ "$sinks" -gt 0 ]]; then
            ok "Audio sinks detected (speakers/headphones)"
        else
            warn "No audio sinks found — check wpctl status"
        fi
    fi
}

# =============================================================================
# Hardware Status Report
# =============================================================================
hardware_report() {
    section "Hardware Status Report"

    local pad=30

    status_line() {
        local label="$1" state="$2" note="${3:-}"
        local colour
        case "$state" in
            OK)      colour="$GRN" ;;
            WARN)    colour="$YLW" ;;
            FAIL)    colour="$RED" ;;
            UNKNOWN) colour="$CYN" ;;
            *)       colour="$RST" ;;
        esac
        printf "  %-${pad}s %b%-8s%b %s\n" "$label" "$colour" "[$state]" "$RST" "$note"
    }

    # Touchpad
    if grep -qi "GXTP7863" /proc/bus/input/devices 2>/dev/null; then
        status_line "Touchpad (GXTP7863)" "OK" "Detected in /proc/bus/input"
    else
        status_line "Touchpad (GXTP7863)" "FAIL" "Not detected — reboot may be needed"
    fi

    # Touchpad service
    if systemctl is-enabled touchpad-rebind.service &>/dev/null; then
        status_line "Touchpad rebind service" "OK" "Enabled at boot"
    else
        status_line "Touchpad rebind service" "WARN" "Not enabled"
    fi

    # WiFi
    if rfkill list wifi 2>/dev/null | grep -q "Soft blocked: no"; then
        status_line "WiFi (Intel CNVi)" "OK" "Not blocked"
    else
        status_line "WiFi (Intel CNVi)" "UNKNOWN" "Check rfkill list"
    fi

    # Bluetooth
    if hciconfig 2>/dev/null | grep -q "UP RUNNING"; then
        status_line "Bluetooth" "OK" "UP RUNNING"
    else
        status_line "Bluetooth" "WARN" "Not detected or down"
    fi

    # Audio
    if wpctl status 2>/dev/null | grep -q "Speaker"; then
        status_line "Audio (PipeWire)" "OK" "Speaker sink present"
    else
        status_line "Audio (PipeWire)" "WARN" "No speaker sink found"
    fi

    # IPU6 module
    if lsmod | grep -q "intel_ipu6"; then
        status_line "Camera kernel module (IPU6)" "OK" "intel_ipu6 loaded"
    else
        status_line "Camera kernel module (IPU6)" "FAIL" "intel_ipu6 not loaded"
    fi

    # Camera HAL plugin
    if [[ -f /usr/lib/libcamhal/plugins/ipu6epmtl.so ]]; then
        status_line "Camera HAL (ipu6epmtl)" "OK" "Plugin installed"
    else
        status_line "Camera HAL (ipu6epmtl)" "FAIL" "Plugin missing"
    fi

    # Camera streaming (INT3472)
    if dmesg | grep -q "INT3472.*EBUSY"; then
        status_line "Camera streaming" "FAIL" "INT3472 GPIO conflict — upstream bug"
    else
        status_line "Camera streaming" "UNKNOWN" "Run: sudo -E gst-launch-1.0 icamerasrc ! fakesink"
    fi

    # Battery
    if upower -e 2>/dev/null | grep -q battery; then
        local pct
        pct=$(upower -i "$(upower -e | grep battery)" 2>/dev/null | grep percentage | awk '{print $2}')
        status_line "Battery" "OK" "${pct:-unknown}"
    else
        status_line "Battery" "UNKNOWN" "upower not available"
    fi

    # Fingerprint
    status_line "Fingerprint reader" "FAIL" "No Linux driver — hardware unsupported"

    echo ""
    echo -e "  ${YLW}Known unfixable issues on VGHH-XX:${RST}"
    echo -e "  • Webcam: INT3472 GPIO conflict → https://github.com/intel/ipu6-drivers/issues/399"
    echo -e "  • Fingerprint: Goodix sensor has no Linux driver for this model"
    echo ""
}

# =============================================================================
# Main
# =============================================================================
main() {
    require_root
    print_banner

    echo -e "This script will apply the following fixes:"
    echo -e "  1. Touchpad libinput quirk + systemd rebind service"
    echo -e "  2. IPU6 camera kernel modules"
    echo -e "  3. Camera HAL userspace (libcamhal-ipu6epmtl)"
    echo -e "  4. Audio status check"
    echo ""

    confirm "Proceed with setup?" || { echo "Aborted."; exit 0; }

    apt-get update -q

    fix_touchpad
    fix_camera_modules
    fix_camera_hal
    check_audio
    hardware_report

    echo -e "${GRN}${BLD}Setup complete!${RST}"
    echo -e "A reboot is recommended to ensure the touchpad rebind service runs cleanly."
    confirm "Reboot now?" && reboot || echo "Reboot when ready."
}

main "$@"
