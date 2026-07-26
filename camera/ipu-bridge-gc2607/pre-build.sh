#!/usr/bin/env bash
# =============================================================================
# DKMS PRE_BUILD for ipu-bridge-gc2607
#
# Ubuntu's in-tree ipu_bridge has no entry for the GalaxyCore GC2607 sensor
# (ACPI HID GCTI2607) used by the Huawei MateBook X Pro 2024, so it never
# instantiates the sensor's I2C client and the camera never appears. Upstream
# has not taken the entry as of v7.0, so we rebuild the module with it added.
#
# We fetch the ipu-bridge.c matching the kernel being built for, add the one
# sensor entry, and let DKMS build it into updates/dkms/ — which depmod
# prefers over the in-tree kernel/ copy. Nothing in /lib/modules is
# overwritten, so a kernel package update cannot clobber us and there is no
# backup/restore dance to get wrong.
#
# Run by DKMS from the build directory with $kernelver set.
# =============================================================================

set -euo pipefail

kver="${kernelver:-$(uname -r)}"

# 7.0.0-28-generic -> v7.0 ; 6.17.0-40-generic -> v6.17
tag="v$(echo "$kver" | cut -d. -f1-2)"

# Cache outside the build tree: DKMS wipes the build dir on every rebuild, so
# caching there would re-fetch on each kernel upgrade.
cache_dir="${IPU_BRIDGE_CACHE_DIR:-/var/cache/ipu-bridge-gc2607}"
cache="${cache_dir}/ipu-bridge-${tag}.c"
url="https://raw.githubusercontent.com/torvalds/linux/${tag}/drivers/media/pci/intel/ipu-bridge.c"

echo "ipu-bridge-gc2607: building for kernel ${kver} (upstream ${tag})"

mkdir -p "$cache_dir"

if [[ -s "$cache" ]]; then
    echo "ipu-bridge-gc2607: using cached source $cache"
else
    echo "ipu-bridge-gc2607: fetching $url"
    if ! curl -fsS --max-time 60 -o "${cache}.tmp" "$url"; then
        rm -f "${cache}.tmp"
        echo "ipu-bridge-gc2607: ERROR: could not fetch ipu-bridge.c for ${tag}." >&2
        echo "  This build needs network access once per kernel series." >&2
        echo "  Retry later with: sudo dkms autoinstall -k ${kver}" >&2
        exit 1
    fi
    mv "${cache}.tmp" "$cache"
fi

cp "$cache" ipu-bridge.c

# Insert the sensor entry at the head of the table. Anchoring on the array
# declaration rather than on a neighbouring sensor keeps this working as
# upstream adds and removes entries around it.
if grep -q "GCTI2607" ipu-bridge.c; then
    echo "ipu-bridge-gc2607: upstream already carries GCTI2607 — no patch needed"
else
    awk '
      /^static const struct ipu_sensor_config ipu_supported_sensors\[\] = \{/ && !done {
        print
        print "\t/* GalaxyCore GC2607 (Huawei MateBook X Pro 2024) */"
        print "\tIPU_SENSOR_CONFIG(\"GCTI2607\", 1, 336000000),"
        done = 1
        next
      }
      { print }
    ' ipu-bridge.c > ipu-bridge.c.patched

    if ! grep -q "GCTI2607" ipu-bridge.c.patched; then
        echo "ipu-bridge-gc2607: ERROR: could not find the sensor table in ipu-bridge.c." >&2
        echo "  Upstream layout changed; camera/ipu-bridge-gc2607/pre-build.sh needs updating." >&2
        exit 1
    fi
    mv ipu-bridge.c.patched ipu-bridge.c
    echo "ipu-bridge-gc2607: patched in GCTI2607 @ 336 MHz, 1 link freq"
fi
