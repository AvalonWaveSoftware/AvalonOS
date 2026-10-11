# AvalonOS runtime packages. Weak deps off in the %packages header.
# Do not list *-devel, meson, ninja-build, gcc-c++, labwc, lightdm.

@^custom-environment

# Seat / GPU / wifi / bluetooth
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
tree-sitter-cli
clang-tools-extra
python3-lsp-server
tar
pciutils
rpmfusion-free-release
rpmfusion-nonfree-release
switcheroo-control

# Explicitly not the vendor greeter stack or C++ toolchain
-labwc
-lightdm
-lightdm-gobject
-meson
-ninja-build
-gcc-c++
