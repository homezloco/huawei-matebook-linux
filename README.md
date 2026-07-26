# Huawei MateBook Linux Toolkit

Setup scripts and management tools for getting Huawei MateBook hardware working on Ubuntu. Tested on the **MateBook X Pro 2024 (VGHH-XX)** running kernels 6.17 and 7.0.

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
| Webcam | ✅ Working | GalaxyCore GC2607 — needs the out-of-tree driver in [`camera/`](#camera) |
| Fingerprint | 🧪 Partial | Goodix GXFP5130 — experimental driver in [`fingerprint/`](#fingerprint); libfprint/PAM setup still manual |

---

## Requirements

- **OS:** Ubuntu 24.04 LTS
- **Kernel:** 6.8 or newer (6.17 and 7.0 tested)
- **Hardware:** Huawei MateBook X Pro 2024 (VGHH-XX) — other MateBook models may work with adjustments

---

## CLI Utilities

We provide several CLI tools for day-to-day management of your MateBook on Linux.

### `huawei` — Hardware Management

The main hardware management tool for status, battery, power, and connectivity.

```bash
# Install
sudo cp huawei-cli /usr/local/bin/huawei
sudo chmod +x /usr/local/bin/huawei

# Core commands
huawei status                        # full hardware report
huawei battery threshold 80          # stop charging at 80%
huawei battery threshold-persist 80  # persist across reboots
huawei power set balanced            # change power profile
huawei touchpad rebind               # fix frozen touchpad
huawei display brightness 60         # set screen brightness
huawei audio volume 50               # set volume
huawei wifi toggle                   # toggle WiFi
huawei camera status                 # camera module/HAL status
huawei fingerprint status            # Goodix GXFP5130 diagnostics
huawei updates check                 # check status of known upstream bugs
huawei updates add <github-url>      # track a custom GitHub issue
```

### `huawei-thermal` — Thermal & Fan Control

Manage temperatures, fan speeds, and CPU throttling.

```bash
# Install
sudo cp huawei-thermal.sh /usr/local/bin/huawei-thermal
sudo chmod +x /usr/local/bin/huawei-thermal

# Commands
huawei-thermal status               # show all temperatures
huawei-thermal monitor              # live temperature monitor
huawei-thermal profile performance  # set high-performance mode
huawei-thermal profile quiet        # set quiet/efficient mode
huawei-thermal throttle             # check thermal throttling status
sudo huawei-thermal fan set 128     # manual fan control (if supported)
sudo huawei-thermal undervolt apply -50  # CPU undervolting (requires intel-undervolt)
```

### `huawei-connect` — Phone Integration (Huawei Share Alternative)

Replace Huawei Share / Multi-Screen Collaboration with Linux-native solutions.

```bash
# Install
sudo cp huawei-connect /usr/local/bin/huawei-connect
sudo chmod +x /usr/local/bin/huawei-connect

# Dependencies: sudo apt install kdeconnect scrcpy adb qrencode

# Pairing & file transfer
huawei-connect pair                 # pair with phone (shows QR code)
huawei-connect share <file>         # send file to phone
huawei-connect receive              # monitor for incoming files
huawei-connect web                  # web interface for file sharing

# Screen mirroring (requires USB debugging enabled on phone)
huawei-connect screen mirror        # mirror phone screen
huawei-connect screen record        # record phone screen
huawei-connect screen audio         # forward phone audio

# Clipboard & notifications
huawei-connect clipboard send       # send clipboard to phone
huawei-connect clipboard monitor    # auto-sync clipboard
huawei-connect notifications enable # sync notifications

# Other features
huawei-connect find                 # ring phone to locate it
huawei-connect sms                  # send SMS from computer
```

### `huawei-display` — Display & Color Management

Optimize the MateBook's high-DPI display for different use cases.

```bash
# Install
sudo cp huawei-display /usr/local/bin/huawei-display
sudo chmod +x /usr/local/bin/huawei-display

# Brightness
huawei-display brightness set 75
huawei-display brightness up 10
huawei-display brightness down

# Color temperature
huawei-display night enable         # blue light filter
huawei-display night temp 4000      # warmer color temp
huawei-display gamma warm           # manual warm adjustment
huawei-display gamma cool           # manual cool adjustment

# Color profiles for different work
huawei-display profile list
huawei-display profile apply photo  # photo editing optimized
huawei-display profile apply web    # web design (sRGB)
huawei-display profile apply video  # video editing (DCI-P3 approx)
huawei-display calibrate            # interactive calibration

# High DPI scaling (MateBook X Pro has 3120x2080 display)
huawei-display dpi auto             # auto-detect optimal scaling
huawei-display dpi set 1.25         # set text scaling
```

### `huawei-backup` — Automated Backup & Sync

Comprehensive backup solution for your MateBook.

```bash
# Install
sudo cp huawei-backup /usr/local/bin/huawei-backup
sudo chmod +x /usr/local/bin/huawei-backup

# Initialize configuration
huawei-backup config init

# Manual backups
huawei-backup backup full           # full backup (all configured dirs)
huawei-backup backup quick         # quick backup (Documents, etc.)
huawei-backup backup config        # config files only
huawei-backup restore              # restore from backup

# Cloud sync
huawei-backup sync                 # sync to Nextcloud/Dropbox/etc.

# System snapshots (requires timeshift)
huawei-backup snapshot daily       # create daily snapshot
huawei-backup snapshot list         # list available snapshots
huawei-backup snapshot restore      # restore system snapshot

# Automation
huawei-backup schedule weekly      # schedule weekly backups
huawei-backup daemon start          # start auto-backup daemon
huawei-backup daemon status         # check daemon status

# View/edit config
huawei-backup config show
huawei-backup config edit
```

Edit `~/.config/huawei-backup/config` to customize:
- Backup directories
- Cloud service (Nextcloud, Dropbox, etc.)
- Retention policy
- Auto-sync intervals

---

**Note:** Commands that write to hardware require `sudo`. Run any tool with `help` for full reference.

Install all five tools at once:

```bash
./install-tools.sh          # copy into /usr/local/bin
./install-tools.sh --link   # symlink to this checkout (use when editing them)
```

Use `--link` if you plan to modify the tools. The default copies them, so an
edit doesn't take effect until you re-run the installer — and a stale copy's
output looks exactly like a fix that didn't work.

---

## Camera

The MateBook X Pro 2024's webcam is a **GalaxyCore GC2607** (ACPI HID `GCTI2607`), not the OmniVision part its ACPI tables also advertise — `OVTI13B1` and `OVTI01AS` are both present but disabled (`status=0`). Two pieces are missing from a stock Ubuntu install:

1. **No sensor driver.** The mainline kernel has no GC2607 V4L2 driver. The community solution started with [abbood/gc2607-v4l2-driver](https://github.com/abbood/gc2607-v4l2-driver); this repo vendors it in `camera/gc2607/` with small local fixes.
2. **`ipu_bridge` doesn't know the sensor.** Its sensor table has no `GCTI2607` entry (still true as of upstream v7.0), so it never instantiates the sensor's I2C client and nothing probes.

The camera was already demonstrated working on Arch by the [adubovskoy/gc2607-v4l2-driver](https://github.com/adubovskoy/gc2607-v4l2-driver) fork, which adds DKMS packaging, a C ISP daemon, and a systemd service. This project does **not** reimplement that work; it provides an Ubuntu/Debian-specific DKMS + CLI integration and the GStreamer pipeline behind `huawei camera stream`.

`camera/` supplies both as DKMS packages:

```bash
sudo ./camera/install.sh
```

| Package | What it does |
|---------|--------------|
| `gc2607` | V4L2 subdev driver — 1920x1080 @ 30fps, 10-bit RAW Bayer (GRBG), exposure + analogue gain |
| `ipu-bridge-gc2607` | Rebuilds `ipu_bridge` with a `GCTI2607` entry, installed to `updates/` so it overrides the in-tree module without overwriting it |

Both are registered with `AUTOINSTALL="yes"`, so **they rebuild automatically on every kernel upgrade**. This matters: the driver is version-locked to the kernel it was built against, and a manually-built `gc2607.ko` silently stops loading the moment you boot a new kernel — the camera then appears broken with no obvious cause.

Under Secure Boot, modules must be signed with an enrolled MOK key or the kernel refuses to load them — and an unsigned module still builds and installs without complaint, so the camera just stays dark with nothing in the log pointing at signing.

DKMS defaults to signing with `MOK.priv` + `MOK.der`. If a machine has been through more than one key generation those two can be from *different* pairs, and `kmodsign` fails mid-build with `key values mismatch` while DKMS carries on and installs the module unsigned. `install.sh` handles this: it tests every certificate in `/var/lib/shim-signed/mok/` against the private key, converts the matching one to DER if needed, checks it's actually enrolled, and pins the pair in `/etc/dkms/framework.conf.d/huawei-matebook-mok.conf` — which also applies to the automatic rebuilds on future kernel upgrades. It then verifies both installed modules actually carry a signature.

If it reports a certificate that matches but is **not enrolled**:

```bash
sudo mokutil --import /var/lib/shim-signed/mok/MOK-dkms.der
# reboot, choose "Enroll MOK", enter the password you just set
```

`ipu-bridge-gc2607` fetches the `ipu-bridge.c` matching the kernel it's building for (~25 KB from the torvalds/linux mirror) and caches it under `/var/cache/ipu-bridge-gc2607/`, so it needs network access once per kernel series.

Check and load the stack:

```bash
huawei camera status         # ACPI nodes, I2C client, modules, PMIC, media graph
sudo huawei camera load      # load modules in dependency order + enable the media link
huawei camera test           # capture one frame to /tmp/gc2607_test.raw
```

`camera test` captures one frame and validates it by size — 1920x1080 10-bit
Bayer is exactly 4147200 bytes. Convert it to view:

```bash
ffmpeg -f rawvideo -pixel_format bayer_grbg10le -s 1920x1080 \
       -i /tmp/gc2607_test.raw out.png
```

### Virtual camera for Meet / Zoom / OBS

The sensor emits raw Bayer, which conferencing apps cannot consume directly.
`huawei camera stream` demosaics it, applies white balance and a vertical flip,
and publishes an RGB stream to a v4l2loopback device that appears as **GC2607 RGB**:

```bash
sudo apt install gstreamer1.0-plugins-bad gstreamer1.0-plugins-good \
                 frei0r-plugins v4l2loopback-dkms
huawei camera stream                    # default white balance
huawei camera stream 1.10 1.00 1.30     # custom R G B gains
```

`bayer2rgb` comes from `gstreamer1.0-plugins-bad`, `videoflip` from
`gstreamer1.0-plugins-good`, and the colour filter from `frei0r-plugins`; none
are installed by default. The command checks every element it needs up front
and names the missing package rather than failing with a bare GStreamer error.

The command discovers an available `v4l2loopback` device dynamically, stops any
`v4l2-relayd` instance that holds the loopback, and reloads the module with
`exclusive_caps=0` so the device can be both written to and read from at the same
time. The image is flipped vertically because the sensor is mounted upside-down.

Preview the virtual camera while the stream is running in another terminal:

```bash
gst-launch-1.0 v4l2src device=/dev/video0 ! videoconvert ! autovideosink
```

Replace `/dev/video0` with the device printed by `huawei camera stream`.

### Notes

The driver source is vendored at `camera/gc2607/`, derived from
[abbood/gc2607-v4l2-driver](https://github.com/abbood/gc2607-v4l2-driver) with one
local change: `gc2607_probe()` sets `sd.fwnode`, without which the sensor probes
but never joins the IPU6 media pipeline.

The capture node is **not** `/dev/video0`. The IPU6 registers dozens of video
nodes and v4l2loopback commonly takes `video0`; the tools resolve the real node
from the media graph (`/dev/video1` on this machine). Note that `gc2607 5-0037`
as shown by `media-ctl` is a V4L2 subdev name, not a device path.

---

## Fingerprint

The MateBook X Pro 2024 fingerprint sensor is a **Goodix GXFP5130** connected
over the Embedded Controller's internal SPI bus via an **eSPI mailbox**. It does
not show up as a normal USB or I²C device, so stock `libfprint` cannot see it.

`fingerprint/install.sh` fetches the upstream `gxfp5130-linux` sources, builds
the `gxfp` kernel module via DKMS (so it survives kernel upgrades and is signed
under Secure Boot), and installs the userspace tools:

```bash
sudo ./fingerprint/install.sh
sudo huawei fingerprint provision   # generate the TLS PSK
```

This gets you `/dev/gxfp` and the capture tools. The remaining pieces — a
patched `libfprint` fork and `fprintd` PAM configuration — are **not automated**
because a mistake can lock you out of your system. Follow the upstream guide to
complete the setup:

- https://github.com/Metrohan/gxfp5130-linux

To remove the kernel module and tools:

```bash
sudo ./fingerprint/uninstall.sh
```

A kernel patch series for the GXFP5130 is also under review for mainline
inclusion as of July 2026.

---

## Quick Start

```bash
git clone https://github.com/homezloco/huawei-matebook-linux.git
cd huawei-matebook-linux

# One-shot hardware setup (touchpad, IPU6 modules, camera HAL)
sudo ./huawei-matebook-setup.sh

# Camera driver stack (DKMS — survives kernel upgrades)
sudo ./camera/install.sh

# Management CLIs
./install-tools.sh

# Reboot, then confirm the camera came up
huawei camera status
huawei camera test
```

The setup script is interactive — it will ask before making changes and offer a reboot at the end. It is safe to run multiple times; steps that are already complete are skipped.

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

> **Note:** The HAL alone is not sufficient on VGHH-XX — the GC2607 sensor also needs the driver stack in [`camera/`](#camera). Install that too.

### 4. Audio Check

Verifies PipeWire is running and that audio sinks are present. No fixes are applied — audio works out of the box on this model.

### 5. Hardware Status Report

Prints a full status table for all hardware components at the end of the run, including known unfixable issues with links to relevant upstream bug reports.

---

## Known Issues

### Fingerprint Reader

The Goodix fingerprint sensor on this model is a **GXFP5130** (ACPI HID `GXFP5130`) connected over an eSPI mailbox rather than USB/I2C. It was long unsupported, but there is now active work:

- **[Metrohan/gxfp5130-linux](https://github.com/Metrohan/gxfp5130-linux)** provides an out-of-tree kernel module, a `libfprint` fork, userspace tools, and PAM integration. It is reported working on the MateBook D16 2024 and the patch series explicitly lists the MateBook X Pro 2024.
- A kernel patch series was submitted in July 2026: **[[PATCH 0/4] drivers/misc: add Goodix GXFP5130 eSPI fingerprint sensor driver](https://lore.kernel.org/linux-kernel/20260718080917.21893-1-metehangnen@gmail.com/)**.

It is **not yet mainlined** and not packaged for Ubuntu, but this repo can install the experimental kernel module and userspace tools via `fingerprint/install.sh`. The `libfprint` fork and PAM configuration are **not automated** because a misconfiguration can lock you out of your system.

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

### Camera

```bash
# Full stack report — ACPI nodes, I2C client, modules, PMIC, media graph
huawei camera status

# Both DKMS packages should be "installed" for the running kernel
dkms status | grep -E 'gc2607|ipu-bridge'

# The patched bridge must win over the in-tree module
modinfo ipu_bridge | grep filename        # expect .../updates/dkms/ipu-bridge.ko

# Capture a frame
sudo huawei camera load && huawei camera test
```

If `huawei camera status` reports *"GC2607 is waiting for a supplier"*,
`ipu_bridge` is the stock one — rerun `sudo ./camera/install.sh` and reboot.
A healthy stack reports *"GC2607 wired up and bound to gc2607"*.

### Audio

```bash
wpctl status
```

---

## Development

Everything is Bash with `set -euo pipefail`; there is no build step or test
suite. Install with `./install-tools.sh --link` so edits take effect
immediately, and sanity-check changes with:

```bash
bash -n huawei-cli && ./huawei-cli status && echo $?   # expect 0
```

[`CLAUDE.md`](CLAUDE.md) documents the shell hazards that have caused real bugs
in this repo — `pipefail` inverting `grep -q` checks, commands that exit
non-zero while succeeding, `[[ -f glob* ]]` never matching, and why
`/dev/video0` must never be hardcoded. Worth reading before adding a hardware
detection check, since each of those shipped as a check that confidently
reported the opposite of reality.

---

## Contributing

If you have a different MateBook model and this script works (or doesn't) for you, please open an issue with:

- `sudo dmidecode -s system-product-name`
- `uname -r`
- Which fixes worked and which didn't

PRs welcome for supporting additional models.

---

## References

- [abbood/gc2607-v4l2-driver](https://github.com/abbood/gc2607-v4l2-driver) — upstream of the GC2607 sensor driver vendored in `camera/gc2607/`
- [Intel IPU6 drivers issue #399 — VGHH-XX camera](https://github.com/intel/ipu6-drivers/issues/399) — the original INT3472 report; superseded on this model by the GC2607 stack
- [Ubuntu Wiki — IntelMIPICamera](https://wiki.ubuntu.com/IntelMIPICamera)
- [Arch Linux Forums — GXTP7863 touchpad fix](https://bbs.archlinux.org/viewtopic.php?id=301467)
- [Linux on Huawei MateBook X Pro 2024](https://daichendt.one/blog/huawei-matebook-x-pro-2024/)

---

## License

MIT
