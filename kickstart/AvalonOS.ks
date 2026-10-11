# AvalonOS installer kickstart — Fedora 44 Everything netinst.
# Template. Run scripts/tailwhip to write AvalonOS.local.ks (gitignored).
# Placeholders: @AVALONOS_USER@ @AVALONOS_USER_HASH@ @AVALONOS_ROOTPW_LINE@
#
# Packages come from the network (url). The golden overlay tarball lives on
# this ISO at /avalonos/overlay.tar and is extracted in %post.

cmdline
keyboard --vckeymap=us --xlayouts='us'
lang en_US.UTF-8
timezone America/Chicago --utc
firstboot --disable
selinux --enforcing
firewall --enabled --service=ssh
reboot

# Network for netinst package fetch.
network --bootproto=dhcp --activate --onboot=on
url --mirrorlist=https://mirrors.fedoraproject.org/mirrorlist?repo=fedora-44&arch=x86_64
repo --name=updates --mirrorlist=https://mirrors.fedoraproject.org/mirrorlist?repo=updates-released-f44&arch=x86_64
# RPM Fusion (ADR 0014). Installer-only; rpmfusion-*-release RPMs persist them.
repo --name=rpmfusion-free --mirrorlist=https://mirrors.rpmfusion.org/mirrorlist?repo=free-fedora-44&arch=x86_64
repo --name=rpmfusion-free-updates --mirrorlist=https://mirrors.rpmfusion.org/mirrorlist?repo=free-fedora-updates-released-44&arch=x86_64
repo --name=rpmfusion-nonfree --mirrorlist=https://mirrors.rpmfusion.org/mirrorlist?repo=nonfree-fedora-44&arch=x86_64
repo --name=rpmfusion-nonfree-updates --mirrorlist=https://mirrors.rpmfusion.org/mirrorlist?repo=nonfree-fedora-updates-released-44&arch=x86_64

# Disk: unattended LVM. Remove these three lines for interactive partitioning.
zerombr
clearpart --all --initlabel
autopart --type=lvm

# Generic. NVIDIA modeset is added in %post only if lspci sees a 10de GPU.
bootloader --location=mbr --timeout=5 --append="rhgb quiet initcall_blacklist=simpledrm_platform_driver_init"

# --- tailwhip:auth ---
user --name=@AVALONOS_USER@ --password='@AVALONOS_USER_HASH@' --iscrypted --groups=wheel --gecos="AvalonOS"
@AVALONOS_ROOTPW_LINE@
# --- tailwhip:auth ---

services --enabled=NetworkManager,iwd,bluetooth,greetd

%packages --exclude-weakdeps --ignoremissing
@^custom-environment
mesa-dri-drivers
mesa-vulkan-drivers
libva-intel-media-driver
iwlwifi-mvm-firmware
iwd
NetworkManager
NetworkManager-wifi
NetworkManager-tui
bluez
blueman
polkit
niri
xwayland-satellite
xorg-x11-server-Xwayland
greetd
greetd-selinux
tuigreet
terminus-fonts-console
xdg-desktop-portal
xdg-desktop-portal-gtk
xdg-desktop-portal-gnome
gnome-keyring
lxpolkit
waybar
rofi
alacritty
dunst
swaylock
swayidle
swaybg
grim
slurp
wl-clipboard
brightnessctl
network-manager-applet
upower
xdg-user-dirs
xdg-utils
pipewire
wireplumber
pipewire-pulseaudio
pipewire-alsa
pavucontrol-qt
firefox
dolphin
qt6ct
qt6-qtwayland
plasma-breeze
candy-icon-theme
gtk3
python3-gobject
systemd-pam
dbus-broker
google-noto-sans-fonts
google-noto-sans-mono-fonts
jetbrains-mono-fonts
fontawesome-6-free-fonts
neovim
git-core
btop
ripgrep
fzf
fd-find
tree-sitter-cli
clang-tools-extra
python3-lsp-server
tar
pciutils
rpmfusion-free-release
rpmfusion-nonfree-release
switcheroo-control
-labwc
-lightdm
-lightdm-gobject
-meson
-ninja-build
-gcc-c++
%end

# Copy payload off the *boot ISO* (stage2 / ks media). With `url --mirrorlist`
# /run/install/repo is the Fedora mirror, not the USB, so also mount by label.
%post --nochroot --log=/mnt/sysimage/root/avalonos-nochroot.log --erroronfail
set -euo pipefail
dest=/mnt/sysimage/var/lib/avalonos
mkdir -p "$dest" /run/avalonos-media
copy_payload() {
    local dir="$1"
    [ -f "$dir/overlay.tar" ] || return 1
    cp -a "$dir/overlay.tar" "$dest/overlay.tar"
    [ -f "$dir/docs.tar" ] && cp -a "$dir/docs.tar" "$dest/docs.tar"
    [ -f "$dir/packages.inc" ] && cp -a "$dir/packages.inc" "$dest/packages.inc"
    return 0
}
found=
for p in \
    /run/install/repo/avalonos \
    /mnt/install/repo/avalonos \
    /run/install/sources/mount-0000-cdrom/avalonos \
    /mnt/install/source/avalonos
do
    if copy_payload "$p"; then found=1; break; fi
done
if [ -z "$found" ]; then
    shopt -s nullglob
    for p in /run/install/sources/*/avalonos; do
        if copy_payload "$p"; then found=1; break; fi
    done
    shopt -u nullglob
fi
if [ -z "$found" ]; then
    for lab in Fedora-E-dvd-x86_64-44 Fedora-E-dvd-x86_64; do
        if [ -e "/dev/disk/by-label/$lab" ]; then
            mount -o ro "/dev/disk/by-label/$lab" /run/avalonos-media || continue
            if copy_payload /run/avalonos-media/avalonos; then
                found=1
            fi
            umount /run/avalonos-media || true
            [ -n "$found" ] && break
        fi
    done
fi
if [ -z "$found" ]; then
    t="$(find /run /mnt /tmp -name overlay.tar 2>/dev/null | head -1 || true)"
    if [ -n "$t" ]; then
        copy_payload "$(dirname "$t")" && found=1
    fi
fi
if [ -z "$found" ]; then
    echo "AvalonOS: overlay.tar not found on installation media" >&2
    ls -la /dev/disk/by-label 2>/dev/null || true
    ls -laR /run/install /mnt/install 2>/dev/null || true
    exit 1
fi
%end

%post --log=/root/avalonos-post.log --erroronfail
set -euo pipefail
USER_NAME="@AVALONOS_USER@"
PAYLOAD=/var/lib/avalonos/overlay.tar
if [ ! -f "$PAYLOAD" ]; then
    echo "AvalonOS: missing $PAYLOAD" >&2
    exit 1
fi

# Extract as root:root. Ignore any SELinux xattrs that might have been
# recorded; restorecon applies policy labels afterwards.
tar -C / --no-same-owner --no-selinux --numeric-owner -xpf "$PAYLOAD"

# Executable bits the tarball already carries; reinforce the known bins.
chmod 0755 /usr/local/bin/vi \
    /usr/local/bin/avalonos-launcher \
    /usr/local/bin/avalonos-session \
    /usr/local/bin/avalonos-greeter \
    /usr/local/bin/avalonos-console-setup \
    /usr/local/bin/avalonos-btop \
    /usr/share/AvalonOS/rofi-grouped \
    /usr/share/AvalonOS/hw-stats \
    /usr/share/AvalonOS/net-menu \
    /usr/share/AvalonOS/net-status \
    /usr/share/AvalonOS/niri-stack \
    /usr/share/AvalonOS/rofi-modes/* 2>/dev/null || true

mkdir -p /etc/systemd/user
ln -sfn /dev/null /etc/systemd/user/xdg-desktop-autostart.target

systemctl set-default graphical.target
systemctl enable greetd.service
ln -sfn /usr/lib/systemd/system/greetd.service /etc/systemd/system/display-manager.service
systemctl enable NetworkManager.service iwd.service bluetooth.service
systemctl enable switcheroo-control.service 2>/dev/null || true
systemctl mask lightdm.service 2>/dev/null || true

# systemd --user at boot so XDG_RUNTIME_DIR/bus exist before graphical login.
if getent passwd "$USER_NAME" >/dev/null; then
    mkdir -p /var/lib/systemd/linger
    touch "/var/lib/systemd/linger/$USER_NAME"
fi

if getent passwd greetd >/dev/null; then
    usermod -aG video,input,render greetd
fi
if getent passwd "$USER_NAME" >/dev/null; then
    usermod -aG video,input,render,wheel "$USER_NAME"
    HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
    mkdir -p "$HOME_DIR/AvalonOS-Docs"
    if [ -f /var/lib/avalonos/docs.tar ]; then
        tar -C "$HOME_DIR/AvalonOS-Docs" --no-same-owner --no-selinux -xpf /var/lib/avalonos/docs.tar
    fi
    chown -R "$USER_NAME:$USER_NAME" "$HOME_DIR/AvalonOS-Docs"
    chmod -R u+rwX,go+rX "$HOME_DIR/AvalonOS-Docs"
    # XDG dirs so first login is not empty
    if [ -x /usr/bin/xdg-user-dirs-update ]; then
        su -s /bin/bash -c 'xdg-user-dirs-update' "$USER_NAME" || true
    fi
fi

if command -v restorecon >/dev/null; then
    restorecon -RF /etc /usr/local/bin /usr/share/AvalonOS \
        /usr/share/wayland-sessions /usr/share/xdg-desktop-portal \
        /usr/share/rofi /usr/share/color-schemes /usr/share/qt6ct \
        /usr/lib64/firefox /var/lib/avalonos \
        "$(getent passwd "$USER_NAME" | cut -d: -f6)" 2>/dev/null || true
fi

rm -f /var/lib/avalonos/overlay.tar
echo "AvalonOS overlay deployed"
%end

# NVIDIA only when a GPU is actually present (Intel-only boxes must not
# get nvidia-drm / simpledrm ghosts — niri EINVAL / "Device missing").
%post --log=/root/avalonos-nvidia-post.log
set +e
NV_ARGS='rd.driver.blacklist=nouveau modprobe.blacklist=nouveau nvidia-drm.modeset=1 nvidia-drm.fbdev=1'
if lspci -n 2>/dev/null | grep -q ' 10de:'; then
    echo "AvalonOS: NVIDIA GPU present — installing akmod-nvidia"
    dnf --setopt=install_weak_deps=False -y install \
        akmod-nvidia xorg-x11-drv-nvidia kernel-devel akmods gcc make elfutils-libelf-devel
    systemctl enable akmods.service
    KERNELS="$(rpm -q kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n')"
    for k in $KERNELS; do
        if ! rpm -q "kernel-devel-$k" >/dev/null 2>&1; then
            dnf --setopt=install_weak_deps=False -y install "kernel-devel-$k"
        fi
        akmods --force --kernels "$k"
    done
    if command -v grubby >/dev/null; then
        grubby --update-kernel=ALL --args="$NV_ARGS"
    fi
    mkdir -p /etc/modprobe.d
    printf '%s\n' \
        'blacklist nouveau' \
        'options nouveau modeset=0' \
        'install nouveau /bin/true' \
        > /etc/modprobe.d/blacklist-nouveau.conf
else
    echo "AvalonOS: no NVIDIA GPU — skipping akmod; blocking nvidia-drm nodes"
    if command -v grubby >/dev/null; then
        grubby --update-kernel=ALL --remove-args="$NV_ARGS"
        grubby --update-kernel=ALL --args='initcall_blacklist=simpledrm_platform_driver_init'
    fi
    mkdir -p /etc/modprobe.d
    printf '%s\n' \
        'blacklist nvidia' \
        'blacklist nvidia_drm' \
        'blacklist nvidia_modeset' \
        'blacklist nvidia_uvm' \
        > /etc/modprobe.d/avalonos-no-nvidia.conf
    rm -f /etc/modprobe.d/blacklist-nouveau.conf
fi
exit 0
%end
