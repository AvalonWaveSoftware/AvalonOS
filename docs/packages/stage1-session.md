# stage1 / session

niri, xwayland-satellite, greetd, tuigreet, portals, polkit agent.

Fedora greetd sysusers user is **`greetd`**, not `greeter`. Overlay
`config.toml` runs `/usr/local/bin/avalonos-greeter` (tuigreet).
`usermod -aG video,input,render greetd`.

greetd owns `display-manager.service`. Polkit agent is **lxpolkit**.

QtGreet + labwc + DFL were removed 2026-09-07 (ADR 0003).

Historical vendor SHAs (obsolete):

| tree | SHA |
|---|---|
| wayqt | `674c4dedcc5f4ef3b0389e6030a3bc6e375d9de2` |
| utils | `c202448e5aea8552e3766c17576a6aab826565af` |
| ipc | `b39ab5e1d13f0ba3d5180e281b309c067d66d38a` |
| applications | `13aa6fd666a85720a3db6dfdf3aa8e43cb3fc601` |
| login1 | `9810f8c50bb227a3ed91e49d5ae0fa80521f0230` |
| QtGreet | `42c1d64472cfd0ff7952810ea8131b375ac5fa9e` |

Transactions appended by `scripts/dnf-install.sh`.
### 2026-09-07T00:21:04Z  dnf install niri xwayland-satellite greetd greetd-selinux labwc xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-gnome gnome-keyring lxpolkit meson ninja-build gcc gcc-c++ qt6-qtbase-devel qt6-qtwayland-devel qt6-qtmultimedia-devel wayland-devel wayland-protocols-devel mpv-devel lightdm-gobject-devel glib2-devel

```
niri-26.04-1.fc44.x86_64
xwayland-satellite-0.8.2-1.fc44.x86_64
greetd-0.10.3-6.fc44.x86_64
greetd-selinux-0.10.3-6.fc44.noarch
labwc-0.9.6-1.fc44.x86_64
xdg-desktop-portal-1.22.1-1.fc44.x86_64
xdg-desktop-portal-gtk-1.15.3-3.fc44.x86_64
xdg-desktop-portal-gnome-50.0-1.fc44.x86_64
gnome-keyring-50.0-1.fc44.x86_64
lxpolkit-0.5.6-4.fc44.x86_64
meson-1.11.2-1.fc44.noarch
ninja-build-1.13.2-2.fc44.x86_64
gcc-16.2.1-2.fc44.x86_64
gcc-c++-16.2.1-2.fc44.x86_64
qt6-qtbase-devel-6.11.2-2.fc44.x86_64
qt6-qtwayland-devel-6.11.2-1.fc44.x86_64
qt6-qtmultimedia-devel-6.11.2-1.fc44.x86_64
wayland-devel-1.25.0-1.fc44.x86_64
wayland-protocols-devel-1.49-1.fc44.noarch
mpv-devel-0.41.0-5.fc44.x86_64
lightdm-gobject-devel-1.33.1-2.fc44.x86_64
glib2-devel-2.88.3-1.fc44.x86_64
```

### 2026-09-07T00:23:31Z  dnf install qt6-qtbase-private-devel systemd-devel

```
qt6-qtbase-private-devel-6.11.2-2.fc44.x86_64
systemd-devel-259.8-1.fc44.x86_64
```

### 2026-09-07T02:37:57Z  dnf install tuigreet

```
tuigreet-0.9.1-7.fc44.x86_64
```

### 2026-09-07T02:51:02Z  dnf install terminus-fonts-console

```
terminus-fonts-console-4.49.1-32.fc44.noarch
```

