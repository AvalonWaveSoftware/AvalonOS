# Overlay map

`overlay/` in `/root/AvalonOS` is the source of truth.
`scripts/apply-overlay.sh` copies files onto the live root (no SELinux
xattrs, then `restorecon`). `scripts/make-golden-tarball.sh` packs the
same tree as `packaging/avalonos-overlay.tar` for the ISO.

| Overlay path | Why |
|---|---|
| `usr/share/AvalonOS/palette.env` | hex tokens |
| `usr/share/AvalonOS/palette.css` | CSS tokens for waybar |
| `usr/share/AvalonOS/wallpaper.png` | niri wallpaper (swaybg) |
| `usr/share/AvalonOS/wallpaper.svg` | vector source |
| `usr/share/wayland-sessions/AvalonOS.desktop` | also installed under `/usr/share/wayland-sessions` |
| `usr/share/AvalonOS/wayland-sessions/AvalonOS.desktop` | tuigreet `--sessions` (AvalonOS only, not stock niri.desktop) |
| `usr/local/bin/avalonos-session` | starts `niri.service` (quieter than stock niri-session) |
| `usr/local/bin/avalonos-greeter` | tuigreet + AvalonOS `--theme` |
| `usr/local/bin/avalonos-console-setup` | Terminus 32px + VT palette before greetd |
| `usr/share/AvalonOS/vconsole.palette` | setvtrgb 16-color map |
| `etc/vconsole.conf` | `FONT=ter-v32n` |
| `etc/systemd/system/greetd.service.d/10-avalonos.conf` | ExecStartPre console-setup |
| `etc/systemd/user/niri.service.d/00-avalonos.conf` | niri logs to journal |
| `etc/xdg/autostart/{blueman,nm-applet,geoclue-demo-agent,lxpolkit}.desktop` | `Hidden=true`; those apps are started from the waybar network menu / niri |
| `usr/share/xdg-desktop-portal/niri-portals.conf` | FileChooser=gtk; ScreenCast=gnome |
| `etc/profile.d/nvim-vi.sh` | `vi`→nvim; EDITOR/VISUAL |
| `usr/local/bin/vi` | nvim shim |
| `etc/modprobe.d/blacklist-nouveau.conf` | NVIDIA boxes (kickstart removes it if no 10de GPU) |
| `etc/modprobe.d/blacklist-simpledrm.conf` | stop EFI simpledrm from becoming niri’s card0 |
| `etc/NetworkManager/conf.d/00-iwd.conf` | `wifi.backend=iwd` |
| `etc/greetd/config.toml` | tuigreet via avalonos-greeter, user `greetd` |
| `etc/sysctl.d/20-avalonos-console.conf` | quieter kernel printk on the login VT |
| `etc/udev/rules.d/99-avalonos-nvidia-unused.rules` | drop unused NVIDIA USB/UCSI functions |
| `etc/niri/config.kdl` | distro niri config (no PCI/output pin) |
| `etc/xdg/waybar/config.jsonc` | bar |
| `etc/xdg/waybar/style.css` | palette |
| `etc/xdg/dunst/dunstrc` | notifications |
| `etc/dunst/dunstrc` | same file; dunst also reads `/etc/dunst` |
| `etc/xdg/alacritty/alacritty.toml` | terminal |
| `etc/xdg/rofi/config.rasi` | launcher; theme AvalonOS; Candy icons |
| `etc/skel/.config/rofi/config.rasi` | same for new users |
| `etc/gtk-3.0/settings.ini` | Candy icons, dark |
| `etc/gtk-4.0/settings.ini` | Candy icons, dark |
| `etc/xdg/gtk-3.0/settings.ini` | XDG GTK3 |
| `etc/xdg/kdeglobals` | Candy + AvalonOS KDE colors |
| `usr/share/color-schemes/AvalonOS.colors` | Dolphin/KF6 palette |
| `etc/xdg/qt6ct/qt6ct.conf` | Qt6 Breeze + AvalonOS colors |
| `etc/skel/.config/qt6ct/qt6ct.conf` | same for new users |
| `usr/share/qt6ct/colors/AvalonOS.conf` | qt6ct palette |
| `etc/environment.d/60-avalonos-qt.conf` | `QT_QPA_PLATFORMTHEME=qt6ct` |
| `usr/local/share/applications/qt6ct.desktop` | hide qt6ct from the launcher |
| `etc/firefox/pref/avalonos.js` | Firefox dark + palette links |
| `usr/lib64/firefox/distribution/policies.json` | force-install AvalonOS theme XPI |
| `usr/share/AvalonOS/firefox/` | `avalonos.xpi` + `manifest.json` |
| `etc/xdg/mimeapps.list` | Firefox browser, Dolphin files |
| `usr/share/rofi/themes/AvalonOS.rasi` | two-column launcher theme |
| `usr/share/AvalonOS/rofi.rasi` | shim `@import` of that theme |
| `usr/share/AvalonOS/rofi-grouped` | script mode: programs for one category |
| `usr/share/AvalonOS/rofi-modes/` | per-category wrappers (`all`, `internet`, …) |
| `usr/local/bin/avalonos-launcher` | Super+D; search + category tabs, programs on the right |
| `usr/share/AvalonOS/hw-stats` | GTK hardware popup |
| `usr/share/AvalonOS/net-menu` | network popup (Wi-Fi list, Bluetooth, connections) |
| `usr/share/AvalonOS/net-status` | leftover status helper (not on the bar) |
| `usr/local/share/applications/blueman-*.desktop` | hide Bluetooth Manager/Adapters from rofi |
| `usr/local/bin/avalonos-btop` | themed btop in floating alacritty |
| `usr/share/AvalonOS/btop.conf` | btop config |
| `usr/share/AvalonOS/btop.theme` | btop theme |
| `usr/share/AvalonOS/btop-themes/avalonos.theme` | named theme file |
| `usr/share/AvalonOS/niri-stack` | i3-style stack/consume/expel helper |
| `etc/xdg/nvim/init.lua` | system neovim |
| `usr/share/AvalonOS/nvim/` | colorscheme, packpath, treesitter parsers |
| `usr/share/nvim/site/plugin/avalonos.lua` | site plugin hook |

Waybar modules (right): `mpris`, `custom/hw`, `custom/btop`,
`custom/brightness` (lightbulb + percent; tooltip `brightness`),
`pulseaudio` (left-click `pavucontrol-qt`, right-click mute),
`custom/net`, `battery`, `tray`.

Kickstart credentials are not overlay files. `scripts/tailwhip` writes
`kickstart/AvalonOS.local.ks` from `kickstart/AvalonOS.ks`.
