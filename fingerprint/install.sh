#!/usr/bin/env bash
# Install the Goodix GXFP5130 fingerprint stack on Ubuntu/Debian.
#
# This fetches the upstream gxfp5130-linux sources, builds the kernel module
# via DKMS, and installs the userspace tools. It does NOT replace libfprint or
# configure PAM — those steps are left manual because they can lock you out of
# your system if misconfigured. See README.md for the full procedure.
set -euo pipefail

need_root() {
    [[ $EUID -eq 0 ]] || { echo "Run as root (sudo $0)" >&2; exit 1; }
}
need_root

UPSTREAM_URL="https://github.com/Metrohan/gxfp5130-linux.git"
CACHE_DIR="/var/cache/gxfp5130-linux"
VERSION="0.1.0"
DKMS_SRC="/usr/src/gxfp-${VERSION}"
BINARIES=(gxfp_capture gxfp_psk_tool gxfp_recovery)

echo "Installing dependencies…"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
    build-essential \
    dkms \
    "linux-headers-$(uname -r)" \
    cmake \
    libmbedtls-dev \
    pkg-config \
    git

# Fetch or refresh upstream sources.
if [[ -d "${CACHE_DIR}/.git" ]]; then
    echo "Updating upstream sources…"
    git -C "$CACHE_DIR" fetch --depth 1 origin main
    git -C "$CACHE_DIR" reset --hard origin/main
else
    echo "Cloning upstream sources…"
    rm -rf "$CACHE_DIR"
    git clone --depth 1 "$UPSTREAM_URL" "$CACHE_DIR"
fi

# Patch upstream userspace source for the older MbedTLS shipped by Ubuntu 24.04.
echo "Patching userspace source for Ubuntu MbedTLS compatibility…"
# mbedtls_sha256 / mbedtls_sha512 are void-returning in MbedTLS 2.28.
sed -i 's/if (mbedtls_sha256(buf, off, digest, 0) != 0) {/mbedtls_sha256(buf, off, digest, 0);\n    if (0) {/' \
    "${CACHE_DIR}/userspace/src/algo/payload/provision.c"
sed -i 's/if (mbedtls_sha512(bb010003_wb_data, bb010003_wb_data_len, digest, 1) != 0)/mbedtls_sha512(bb010003_wb_data, bb010003_wb_data_len, digest, 1);\n    if (0)/' \
    "${CACHE_DIR}/userspace/src/algo/payload/provision.c"
# TLS version helpers changed from min_version(major,minor) to min_tls_version(enum).
sed -i 's/mbedtls_ssl_conf_min_tls_version(&e->conf, MBEDTLS_SSL_VERSION_TLS1_2);/mbedtls_ssl_conf_min_version(\&e->conf, MBEDTLS_SSL_MAJOR_VERSION_3, MBEDTLS_SSL_MINOR_VERSION_3);/' \
    "${CACHE_DIR}/userspace/src/tls/tls_engine_mbedtls.c"
sed -i 's/mbedtls_ssl_conf_max_tls_version(&e->conf, MBEDTLS_SSL_VERSION_TLS1_2);/mbedtls_ssl_conf_max_version(\&e->conf, MBEDTLS_SSL_MAJOR_VERSION_3, MBEDTLS_SSL_MINOR_VERSION_3);/' \
    "${CACHE_DIR}/userspace/src/tls/tls_engine_mbedtls.c"

# Build userspace tools.
echo "Building userspace tools…"
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
cmake -S "${CACHE_DIR}/userspace" \
      -B "${CACHE_DIR}/build/userspace" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_MODULE_PATH="${SCRIPT_DIR}/cmake"
cmake --build "${CACHE_DIR}/build/userspace" -j"$(nproc)"

# Install kernel module via DKMS so it survives kernel upgrades.
echo "Installing gxfp kernel module via DKMS…"
rm -rf "$DKMS_SRC"
install -d "$DKMS_SRC"
cp -a "${CACHE_DIR}/kernel/." "$DKMS_SRC/"

# The upstream kernel/Makefile is an in-tree Kbuild file with no default target.
# Add an out-of-tree wrapper so DKMS can build it directly.
mv "$DKMS_SRC/Makefile" "$DKMS_SRC/Makefile.upstream"
cat > "$DKMS_SRC/Makefile" <<'EOF'
KDIR ?= /lib/modules/$(shell uname -r)/build
PWD  := $(shell pwd)

all: modules
modules:
	$(MAKE) -C $(KDIR) M=$(PWD) CONFIG_GXFP5130=m modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

EOF
cat "$DKMS_SRC/Makefile.upstream" >> "$DKMS_SRC/Makefile"
rm -f "$DKMS_SRC/Makefile.upstream"

# The upstream Makefile uses obj-$(CONFIG_GXFP5130). For an out-of-tree DKMS
# build CONFIG_GXFP5130 is unset, so force it to 'm' in the dkms.conf make line.
cat > "$DKMS_SRC/dkms.conf" <<EOF
PACKAGE_NAME="gxfp"
PACKAGE_VERSION="$VERSION"
BUILT_MODULE_NAME[0]="gxfp"
DEST_MODULE_LOCATION[0]="/kernel/drivers/misc"
AUTOINSTALL="yes"
MAKE[0]="make KERNELDIR=/lib/modules/\${kernelver}/build CONFIG_GXFP5130=m"
CLEAN="make KERNELDIR=/lib/modules/\${kernelver}/build CONFIG_GXFP5130=m clean"
EOF

make -C "$DKMS_SRC" clean >/dev/null 2>&1 || true

dkms remove -m gxfp -v "$VERSION" --all >/dev/null 2>&1 || true
dkms add -m gxfp -v "$VERSION"
dkms build -m gxfp -v "$VERSION"
dkms install -m gxfp -v "$VERSION"

# Install userspace binaries.
echo "Installing userspace binaries…"
for bin in "${BINARIES[@]}"; do
    install -D -m 0755 "${CACHE_DIR}/build/userspace/${bin}" "/usr/local/bin/${bin}"
done

# Install udev rule and fprintd device allowlist.
install -D -m 0644 "${CACHE_DIR}/config/60-gxfp.rules" /etc/udev/rules.d/60-gxfp.rules
install -D -m 0644 "${CACHE_DIR}/config/fprintd-gxfp.conf" \
    /etc/systemd/system/fprintd.service.d/gxfp.conf

udevadm control --reload-rules
systemctl daemon-reload
depmod -a
modprobe gxfp

echo ""
echo "✓ gxfp kernel module and userspace tools installed."
echo ""
echo "Next steps:"
echo "  1. Provision the TLS PSK:"
echo "       sudo huawei fingerprint provision"
echo "  2. Install the libfprint fork and configure PAM manually."
echo "     See: https://github.com/Metrohan/gxfp5130-linux"
echo ""
echo "The kernel module will be rebuilt automatically on kernel upgrades via DKMS."
