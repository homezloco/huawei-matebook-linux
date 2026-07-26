# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

## What this is

Hardware enablement for the **Huawei MateBook X Pro 2024 (VGHH-XX)** on Ubuntu.
No GUI, no build step, no test suite — five standalone Bash CLIs plus DKMS
packaging for the camera driver stack. Everything runs directly against the
machine it manages, so "testing" means running it and reading the output.

Tested on kernels 6.17 and 7.0, Ubuntu 24.04.

## Layout

```
huawei-cli               Main tool (~2000 lines). Installed as `huawei`.
huawei-thermal.sh        Temps, fan, throttling, undervolt
huawei-connect           Phone integration (KDE Connect / scrcpy / adb)
huawei-display           Backlight, colour temp, profiles, DPI
huawei-backup            Backup, cloud sync, timeshift snapshots
huawei-matebook-setup.sh One-shot setup (touchpad, IPU6 modules, camera HAL)
install-tools.sh         Installs the five CLIs to /usr/local/bin
camera/
  install.sh             Registers both DKMS packages, handles MOK signing
  gc2607/                Vendored GC2607 V4L2 sensor driver + dkms.conf
  ipu-bridge-gc2607/     Rebuilds ipu_bridge with a GCTI2607 entry
```

`gc2607-v4l2-driver/` may exist locally — an upstream working clone
(github.com/abbood/gc2607-v4l2-driver). It is gitignored and **not** the source
of truth; the driver we ship is vendored at `camera/gc2607/`.

## Working on this repo

**Install with `--link`, not the default copy:**

```bash
./install-tools.sh --link
```

`/usr/local/bin/huawei` is otherwise a *copy*, and goes stale the moment you
edit a script. A stale copy's output is indistinguishable from "the fix didn't
work" — this cost several debugging rounds. With `--link` the installed
commands are symlinks to the checkout.

Every script is `#!/usr/bin/env bash` with `set -euo pipefail`. There is no
linter or test runner. Minimum bar before committing:

```bash
bash -n <script>                    # syntax
./huawei-cli status                 # exercises most detection paths
echo $?                             # must be 0
```

## Bash hazards that have actually bitten here

These are not hypothetical. Each one shipped, and each produced a check that
confidently reported the **opposite of reality**.

### `set -o pipefail` + a pipeline in a condition

`grep -q` exits on its first match, which SIGPIPEs the producer. `pipefail`
then propagates 141 and the `if` takes the false branch *even though the
pattern matched*:

```bash
lsmod | grep -qE "^intel_ipu6"   # PIPESTATUS=141 0  -> reports "not loaded"
```

This affected 23 sites in `huawei-cli` and 7 in the setup script, and was
non-deterministic by module name. **Prefer sysfs over parsing command output:**

```bash
mod_loaded() { [[ -d "/sys/module/${1//-/_}" ]]; }   # what huawei-cli uses
```

When a pipeline is unavoidable, drop `-q` and redirect (`grep pat >/dev/null`)
so the producer is never killed early.

### A command that exits non-zero while succeeding

`mokutil --test-key` prints `is already enrolled` and **exits 1** when it
cannot read the kernel trusted keyring. Piping it into `grep` under `pipefail`
inverted a correct answer. Capture the output and match the text:

```bash
out="$(mokutil --test-key "$cert" 2>/dev/null || true)"
[[ "$out" == *"is already enrolled"* ]]
```

`v4l2-ctl` likewise prints `The pixelformat 'BA10' is invalid` and still exits
0. **Judge such commands by their effect, not their status** — `camera test`
now checks the captured file is exactly `1920*1080*2` bytes.

### `var=$(cmd | ...)` aborting the script

Under `pipefail`, any element failing kills the assignment, and `set -e` then
exits — often mid-report, silently truncating output. `grep` with no match,
`dpkg -l` on an absent package, `ls` on an empty dir, and `du`/`df` on missing
paths all do this. Append `|| true` where the code already guards with
`[[ -n "$var" ]]`.

### `[[ -f /path/glob* ]]` never matches

`[[ ]]` does **not** perform pathname expansion, so this silently tests a
literal `*`. `huawei-thermal` never printed fan speed or power draw for this
reason, despite both sysfs files existing. Resolve the glob into an array:

```bash
local f=(/sys/class/hwmon/hwmon*/fan1_input)
[[ -f "${f[0]}" ]] && ...
```

### Never hardcode `/dev/video0`

The IPU6 registers ~48 video nodes, numbering shifts, and v4l2loopback or a USB
webcam can hold `video0` — capturing from it yields a frame from the *wrong
device* rather than an error. Resolve it from the media graph
(`_isys_capture_node` in `huawei-cli`). On this machine the sensor is
`/dev/video1`, and `video0` is v4l2loopback.

## Camera stack

The webcam is a **GalaxyCore GC2607** (ACPI HID `GCTI2607`). The ACPI tables
also advertise `OVTI13B1`/`OVTI01AS`, but both are disabled (`status=0`) —
older docs claiming an OV13B10 are wrong. Two pieces are missing from stock
Ubuntu, both supplied as DKMS packages by `camera/install.sh`:

| Package | Why |
|---|---|
| `gc2607` | mainline has no V4L2 driver for this sensor |
| `ipu-bridge-gc2607` | `ipu_bridge`'s sensor table has no `GCTI2607` entry (still true upstream at v7.0), so it never wires up the sensor |

Both use `AUTOINSTALL="yes"`. This is the whole point: a hand-built module is
version-locked to its kernel and stops loading after the next upgrade, which is
exactly how the camera silently died before. `ipu-bridge-gc2607` fetches the
`ipu-bridge.c` matching the target kernel (~25 KB over HTTPS, cached in
`/var/cache/ipu-bridge-gc2607/`) and inserts one line into the sensor table,
anchored on the array declaration so upstream churn around it doesn't break the
patch. Do **not** switch this to a `git fetch` from kernel.org — that timed out
past two minutes and would hang `apt` during kernel upgrades.

`camera/gc2607/gc2607.c` carries one local change over upstream: `gc2607_probe()`
sets `sd.fwnode`. Without it the sensor probes but never joins the IPU6 media
pipeline. Preserve it.

### Diagnosing

```bash
huawei camera status     # ACPI, I2C binding, modules, PMIC, media graph
huawei camera test       # capture one frame, validated by size
dkms status | grep -E 'gc2607|ipu-bridge'
```

A working sensor device has a bound `driver` symlink and regulator suppliers,
and has *lost* `waiting_for_supplier`:

```bash
ls /sys/bus/i2c/devices/i2c-GCTI2607:00/
```

The device node existing proves nothing — it is ACPI-enumerated and present
even when `ipu_bridge` has no entry for it. The `5-0037` seen in `media-ctl` is
a V4L2 subdev name (`<driver> <bus>-<addr>`), **not** a sysfs path.

### Secure Boot

Modules must be signed with an enrolled MOK key or the kernel refuses them —
and an unsigned module installs without complaint, so the failure is silent.
DKMS defaults to `MOK.priv` + `MOK.der`; on a machine with more than one key
generation those may not pair, and `kmodsign` fails mid-build while DKMS
reports success. `camera/install.sh` tests each certificate against the private
key, converts the match to DER, checks enrollment, and pins the pair in
`/etc/dkms/framework.conf.d/huawei-matebook-mok.conf` so automatic rebuilds
sign correctly too.

## Relationship to linux-command-centre

`~/Development/linux-command-centre` is an Electron + Svelte 5 system dashboard
covering much of the same ground (battery threshold, thermal, display, audio,
Wi-Fi/Bluetooth soft-block, GXTP7863 touchpad rebind, a camera panel, and
GitHub issue tracking that mirrors `huawei updates`).

Current state of the coupling:

- `src/main/shell.ts` defines `huaweiCli()`, which runs `/usr/local/bin/huawei`.
  **Nothing calls it.** It is still dead code.
- MateBook checks live in `src/main/hardware-profiles.ts` under the
  `huawei-matebook` profile, matched on DMI `sys_vendor`. They read sysfs and
  `dkms status` directly rather than parsing this tool's output.

That split is deliberate and worth preserving:

- **Status → read sysfs natively in the GUI.** Do not route it through
  `huawei-cli`. Its output is colourised and human-formatted, and its wording
  has already changed more than once — `"GC2607 I2C client created"` became
  `"GC2607 wired up and bound to gc2607"` in a single session. Anything parsing
  that would have broken silently.
- **Actions → shell out.** `camera load`, `camera/install.sh` and similar are
  non-trivial, already tested here, and should not be reimplemented in
  TypeScript. This is where a bridge earns its place.

The command centre covers the camera stack's *lifecycle* (DKMS built for the
running kernel, sensor binding, module signature under Secure Boot) with
`camera-rebuild` and `camera-load` as privileged fixes. Note its security
boundary: profiles may reference a privileged operation **by name** but cannot
define one, because `lcc-helper.js` runs as root via pkexec and its safety
rests on being a fixed allowlist. Never add a privileged op there that takes a
script or path argument — that is arbitrary root execution. This is why the GUI
does not run `camera/install.sh` directly and uses `dkms autoinstall` instead.

Still not covered there, in rough order of value: `dual-boot mount`/`umount`,
keyboard backlight, fan control (`pwm1`), camera exposure/gain/white-balance
controls, and the virtual-camera stream toggle.

## Conventions

- Output helpers are consistent across all five tools: `ok`, `warn`, `err`,
  `info`, `dim`, `hdr`, `die`. Match them rather than using bare `echo`.
- Commands that write to hardware call `need_root`.
- Prefer reading sysfs directly over shelling out and parsing.
- When a check can be wrong, make the failure mode explicit — several bugs here
  were checks that reported success against broken hardware.
