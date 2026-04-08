# Huawei MateBook Linux Setup Script

A one-shot setup script for getting Huawei MateBook hardware working on Ubuntu 24.04. Tested on the **MateBook X Pro 2024 (VGHH-XX)** running kernel 6.17.

---

## Hardware Status

| Component | Status | Notes |
|-----------|--------|-------|
| Touchpad | ✅ Working | Requires libinput quirk + systemd rebind workaround |
| WiFi | ✅ Working | Intel CNVi — works out of the box |
| Bluetooth | ✅ Working | Works out of the box |
| Audio | ✅ Working | PipeWire — speakers, headphones, mic all functional |
| Touchscreen | ✅ Working | Works out of the box |
| Battery | ✅ Working | Works out of the box |
| GPU | ✅ Working | Intel Arc (Meteor Lake) via i915/Xe |
| Webcam | ❌ Broken | INT3472 GPIO conflict — upstream kernel bug |
| Fingerprint | ❌ Broken | Goodix sensor — no Linux driver for this model |

---

## Requirements

- **OS:** Ubuntu 24.04 LTS
- **Kernel:** 6.8 or newer (6.17 tested)
- **Hardware:** Huawei MateBook X Pro 2024 (VGHH-XX) — other MateBook models may work with adjustments

---

## CLI Utility

`huawei-cli` is a day-to-day hardware management tool — separate from the one-shot setup script.

```bash
# Install
sudo cp huawei-cli /usr/local/bin/huawei
sudo chmod +x /usr/local/bin/huawei

# Examples
huawei status                        # full hardware report
huawei battery threshold 80          # stop charging at 80%
huawei battery threshold-persist 80  # persist across reboots
huawei power set balanced            # change power profile
huawei touchpad rebind               # fix frozen touchpad
huawei display brightness 60         # set screen brightness
huawei audio volume 50               # set volume
huawei wifi toggle                   # toggle WiFi
huawei camera status                 # camera module/HAL status
```

Commands that write to hardware require `sudo`. Run `huawei help` for the full reference.

---

## Quick Start

```bash
# Download the script
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/huawei-matebook-setup.sh

# Make executable
chmod +x huawei-matebook-setup.sh

# Run as root
sudo ./huawei-matebook-setup.sh
```

The script is interactive — it will ask before making changes and offer a reboot at the end. It is safe to run multiple times; steps that are already complete are skipped.

---

## What the Script Does

### 1. Touchpad Fix

The GXTP7863 touchpad on kernel 6.12+ suffers from a regression where the `i2c_hid_acpi` driver initialises the device too early at boot, resulting in a malformed report descriptor (`device returned incorrect report: 0 vs 14 expected`). Two fixes are applied:

**libinput quirk** — tells libinput to treat the device correctly as a clickpad:

```
/etc/libinput/local-overrides.quirks
```

**systemd rebind service** — unbinds and rebinds the touchpad 5 seconds after boot to force correct initialisation:

```
/etc/systemd/system/touchpad-rebind.service
```

### 2. IPU6 Camera Kernel Modules

Installs `linux-modules-ipu6-generic-hwe-24.04` and `linux-modules-usbio-generic-hwe-24.04` from the Ubuntu HWE track. On kernel 6.17 the `intel-ipu6-dkms` out-of-tree package fails to build (removed kernel API `no_llseek`); the script handles this gracefully since the in-kernel `intel_ipu6` module covers the same functionality.

### 3. Camera HAL Userspace

Adds the Dell/Canonical OEM archive (`dell.archive.canonical.com`) — a stable, production archive used for OEM Ubuntu deployments, not to be confused with the development PPA. Installs:

- `libcamhal-ipu6epmtl` — Meteor Lake camera HAL plugin
- `gstreamer1.0-icamera` — GStreamer source element for the IPU6 pipeline

> **Note:** Even with the HAL installed, camera streaming is currently blocked by an `INT3472` GPIO conflict specific to the VGHH-XX ACPI tables. The HAL is ready and will work once the upstream kernel fix lands.

### 4. Audio Check

Verifies PipeWire is running and that audio sinks are present. No fixes are applied — audio works out of the box on this model.

### 5. Hardware Status Report

Prints a full status table for all hardware components at the end of the run, including known unfixable issues with links to relevant upstream bug reports.

---

## Known Issues

### Webcam (INT3472 GPIO conflict)

The camera hardware (`OV13B10` 13MP main + `OV01A1S` IR/Windows Hello) is present in ACPI but the `int3472-discrete` driver fails with `error -EBUSY: Failed to get GPIO` at boot. This prevents the sensor from being powered on and probed.

This is an unresolved upstream kernel bug specific to the VGHH-XX ACPI tables. Track progress and add your details here:

> https://github.com/intel/ipu6-drivers/issues/399

### Fingerprint Reader

The Goodix fingerprint sensor on this model is connected via a proprietary interface and has no Linux driver. `libfprint` does not support it. There is no workaround at this time.

---

## Manual Steps (if not using the script)

### Touchpad

```bash
# 1. Write libinput quirk
sudo mkdir -p /etc/libinput
sudo tee /etc/libinput/local-overrides.quirks << 'EOF'
[Huawei MateBook X Pro 2024 Touchpad]
MatchName=GXTP7863:00 27C6:01E0 Touchpad
MatchUdevType=touchpad
MatchDMIModalias=dmi:*svnHUAWEI:*pnVGHH-XX*
AttrEventCode=-BTN_RIGHT
ModelPressurePad=1
EOF

# 2. Create systemd rebind service
sudo tee /etc/systemd/system/touchpad-rebind.service << 'EOF'
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
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now touchpad-rebind.service
```

### Camera HAL

```bash
sudo apt install ubuntu-oem-keyring
sudo add-apt-repository "deb http://dell.archive.canonical.com/ noble somerville"
sudo apt update
sudo apt install \
  linux-modules-ipu6-generic-hwe-24.04 \
  linux-modules-usbio-generic-hwe-24.04 \
  libcamhal-ipu6epmtl \
  libcamhal-ipu6epmtl-common \
  gstreamer1.0-icamera
```

---

## Testing

### Touchpad

```bash
# Verify it's detected
cat /proc/bus/input/devices | grep -A5 GXTP

# Verify libinput quirk is applied
libinput quirks list /dev/input/event4
```

### Camera (HAL only — streaming blocked pending kernel fix)

```bash
# Verify plugin is in place
ls /usr/lib/libcamhal/plugins/

# Test pipeline (will fail with INT3472 error on VGHH-XX for now)
sudo -E gst-launch-1.0 icamerasrc ! fakesink
```

### Audio

```bash
wpctl status
```

---

## Contributing

If you have a different MateBook model and this script works (or doesn't) for you, please open an issue with:

- `sudo dmidecode -s system-product-name`
- `uname -r`
- Which fixes worked and which didn't

PRs welcome for supporting additional models.

---

## References

- [Intel IPU6 drivers issue #399 — VGHH-XX camera](https://github.com/intel/ipu6-drivers/issues/399)
- [Ubuntu Wiki — IntelMIPICamera](https://wiki.ubuntu.com/IntelMIPICamera)
- [Arch Linux Forums — GXTP7863 touchpad fix](https://bbs.archlinux.org/viewtopic.php?id=301467)
- [Linux on Huawei MateBook X Pro 2024](https://daichendt.one/blog/huawei-matebook-x-pro-2024/)

---

## License

MIT
