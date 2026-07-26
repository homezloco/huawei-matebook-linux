# Goodix GXFP5130 fingerprint driver packaging

This directory installs the out-of-tree driver stack for the Goodix GXFP5130
fingerprint sensor found in the Huawei MateBook X Pro 2024 (VGHH-XX). The
sensor communicates with the host via an eSPI mailbox to the Embedded
Controller, so it is not visible as a normal USB or I²C device.

## What it does

- Builds and installs the `gxfp` kernel module via DKMS, so it survives kernel
  upgrades and is signed automatically under Secure Boot.
- Builds and installs the `gxfp_capture`, `gxfp_psk_tool`, and
  `gxfp_recovery` userspace binaries to `/usr/local/bin`.
- Installs udev rules and an `fprintd` systemd drop-in so the daemon can
  access `/dev/gxfp`.

## What it does NOT do

The full end-to-end fingerprint login flow also requires a patched
`libfprint` and `fprintd`, plus PAM configuration. Those steps can lock you out
of your system if they go wrong, so they are **not** automated here. See the
upstream repo for that part:

- https://github.com/Metrohan/gxfp5130-linux

## Usage

```bash
sudo ./fingerprint/install.sh
```

After install, provision the TLS PSK:

```bash
sudo huawei fingerprint provision
```

Then follow the upstream instructions to build/install the `libfprint` fork
and configure PAM.

## Uninstall

```bash
sudo ./fingerprint/uninstall.sh
```
