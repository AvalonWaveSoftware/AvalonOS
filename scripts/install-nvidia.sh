#!/usr/bin/env bash
# Install the NVIDIA akmod on an already-installed AvalonOS box. Same logic
# as the kickstart's NVIDIA %post (ADR 0004, ADR 0014). Run as root.
# Reconstructed in 2026-10 from the kickstart; the original script was lost.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "install-nvidia: run as root" >&2; exit 1; }
lspci -n | grep -q ' 10de:' || { echo "install-nvidia: no NVIDIA GPU (10de) found"; exit 0; }
NV_ARGS='rd.driver.blacklist=nouveau modprobe.blacklist=nouveau nvidia-drm.modeset=1 nvidia-drm.fbdev=1'
rpm -q rpmfusion-nonfree-release >/dev/null || dnf -y install rpmfusion-free-release rpmfusion-nonfree-release
dnf --setopt=install_weak_deps=False -y install \
    akmod-nvidia xorg-x11-drv-nvidia kernel-devel akmods gcc make elfutils-libelf-devel
systemctl enable akmods.service
for k in $(rpm -q kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n'); do
    rpm -q "kernel-devel-$k" >/dev/null 2>&1 || dnf --setopt=install_weak_deps=False -y install "kernel-devel-$k"
    akmods --force --kernels "$k"
done
grubby --update-kernel=ALL --args="$NV_ARGS"
printf '%s\n' 'blacklist nouveau' 'options nouveau modeset=0' 'install nouveau /bin/true' > /etc/modprobe.d/blacklist-nouveau.conf
rm -f /etc/modprobe.d/avalonos-no-nvidia.conf
echo "install-nvidia: done; reboot to load nvidia"
