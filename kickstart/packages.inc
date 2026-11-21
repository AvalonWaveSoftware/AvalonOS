# AvalonOS runtime packages. Weak deps off in the %packages header.
# Do not list *-devel, meson, ninja-build, gcc-c++, labwc, lightdm.
# AvalonOS's own files are RPMs from the ISO repo (avalonos meta-package),
# installed in %post because the netinst %packages repos are network-only.

@^custom-environment

# Seat / GPU / wifi / bluetooth
# mesa-dri-drivers also carries kms_swrast (no-3D GPUs, decision 9:41 CT).
mesa-dri-drivers
mesa-vulkan-drivers
libva-intel-media-driver

# Firmware + CPU microcode (Sep 13 list, decision 9:33 CT). Weak deps are
# off, so list them explicitly. Intel microcode ships in microcode_ctl.
linux-firmware
intel-gpu-firmware
amd-gpu-firmware
nvidia-gpu-firmware
amd-ucode-firmware
microcode_ctl
intel-audio-firmware
alsa-sof-firmware
cirrus-audio-firmware
intel-vsc-firmware
iwlwifi-mvm-firmware
iwlwifi-mld-firmware
iwlwifi-dvm-firmware
iwlegacy-firmware
atheros-firmware
brcmfmac-firmware
realtek-firmware
mt7xxx-firmware
nxpwireless-firmware
tiwilink-firmware
libertas-firmware
qcom-wwan-firmware

# VM guest agents (decision 9:33 CT); each starts only on its hypervisor.
qemu-guest-agent
spice-vdagent
open-vm-tools
hyperv-daemons
virtualbox-guest-additions

iwd
NetworkManager
NetworkManager-wifi
NetworkManager-tui
bluez
blueman
polkit

# Session
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

# Desktop chrome
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

# Audio (PipeWire)
pipewire
wireplumber
pipewire-pulseaudio
pipewire-alsa
pavucontrol-qt

# Apps / Qt / icons
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

# Fonts
google-noto-sans-fonts
google-noto-sans-mono-fonts
jetbrains-mono-fonts
fontawesome-6-free-fonts

# Editor / CLI
neovim
git-core
btop
ripgrep
fzf
fd-find
tar
openssh-clients
pciutils
rpmfusion-free-release
rpmfusion-nonfree-release
# rpm Python bindings: %post verifies every installed package's header
# signature against the pinned keys (Code Security P-M1).
python3-rpm
switcheroo-control

# Dev tools dropped (decision 9:33 CT): clang-tools-extra, python3-lsp-server,
# tree-sitter-cli are simply not listed (nothing else pulls them in).

# No SSH server (decision 9:20 CT); @core would pull it in.
-openssh-server

# Explicitly not the vendor greeter stack or C++ toolchain
-labwc
-lightdm
-lightdm-gobject
-meson
-ninja-build
-gcc-c++
