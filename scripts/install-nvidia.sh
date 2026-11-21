#!/usr/bin/env bash
# Install the NVIDIA akmod on an already-installed AvalonOS box. Run as root.
# Delegates to hw-setup (avalonos-hw), the same code the installer runs, so it
# fails closed the same way (ARCH-04): nouveau is blacklisted only after
# nvidia.ko built for every kernel; on failure the driver packages are
# removed and nouveau stays. Log: /var/log/avalonos-hw.log.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "install-nvidia: run as root" >&2; exit 1; }
lspci -n | grep -q ' 10de:' || { echo "install-nvidia: no NVIDIA GPU (10de) found"; exit 0; }
rpm -q rpmfusion-nonfree-release >/dev/null || dnf -y install rpmfusion-free-release rpmfusion-nonfree-release
hw=/usr/libexec/avalonos/hw-setup
[ -x "$hw" ] || hw="$(cd "$(dirname "$0")/.." && pwd)/overlay/usr/libexec/avalonos/hw-setup"
"$hw"
if [ -f /etc/modprobe.d/blacklist-nouveau.conf ]; then
    rm -f /etc/modprobe.d/avalonos-no-nvidia.conf
    dracut -f --regenerate-all || true
    echo "install-nvidia: done; reboot to load nvidia"
else
    echo "install-nvidia: NVIDIA driver NOT enabled (see /var/log/avalonos-hw.log); nouveau stays" >&2
    exit 1
fi
