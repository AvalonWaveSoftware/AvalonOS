# AvalonOS

Minimal custom desktop environment on **Fedora 44**. Official Fedora
packages plus RPM Fusion **only** for NVIDIA. The git tree is
`/root/AvalonOS`. Documentation for the daily user is also copied to
`/home/admin/AvalonOS-Docs`.

Daily graphical user on this box and on the ISO default: **admin**
(uid 1000, `wheel`). Root has no GUI session. ISO root is locked
(`rootpw --lock`) unless `scripts/tailwhip --root-password-env` is used.

## Locked stack

Wayland, **niri** 26, **xwayland-satellite**, **greetd** + **tuigreet**
(wrapper `/usr/local/bin/avalonos-greeter`), **waybar**, **rofi** 2,
**alacritty**, **neovim** (`vi` → nvim), **dunst**, PipeWire,
NetworkManager + **iwd**, **bluez** + **blueman**, **Firefox**,
**Dolphin**, **pavucontrol-qt**. Session Exec is
`/usr/local/bin/avalonos-session` (starts `niri.service`). niri does not
pin a GPU or connector. NVIDIA (`akmod-nvidia`) is for PRIME offload,
not the compositor.

Palette: navy `#0A1628`, neon `#39FF14`, purple-red `#C2185B`.
Tokens: `overlay/usr/share/AvalonOS/palette.env`.
Wallpaper: `wallpaper.png` via **swaybg**. Greeter is TTY tuigreet (no image).

## Layout (git tree)

| Path | What |
|---|---|
| `docs/decisions/` | ADRs |
| `docs/packages/` | dnf transaction log |
| `docs/hardware.md` | reference laptop |
| `docs/configs.md` | overlay file map |
| `docs/iso.md` | netinst remaster + golden tarball |
| `overlay/` | DE files (`apply-overlay.sh` / golden tarball) |
| `packaging/` | golden tarball output |
| `kickstart/` | `AvalonOS.ks` template + `packages.inc` |
| `scripts/` | overlay, ISO, tailwhip, stage installers |

## Rules

- `dnf --setopt=install_weak_deps=False`
- Overlay is source of truth; live configs must match it
- SELinux Enforcing
- No QtGreet, labwc, or vendor DFL/WayQt

## Apply overlay (this machine)

```bash
sudo /root/AvalonOS/scripts/apply-overlay.sh
```

Copies overlay files without SELinux context, then `restorecon`.

## ISO

The installer image is **not** in git. Get `AvalonOS-netinst-x86_64.iso`
from **GitHub Releases**.

**[How to Install](How-to-Install.md)** — USB (BIOS and UEFI), first
login, credentials.

Remaster of Fedora 44 Everything netinst (ADR 0019):

```bash
sudo /root/AvalonOS/scripts/build-iso.sh
```

Writes `/var/tmp/avalonos-iso/AvalonOS-netinst-x86_64.iso` (also copied
to `/home/admin/AvalonOS-netinst-x86_64.iso`). Needs network at install
time. Kickstart includes RPM Fusion and builds `akmod-nvidia` in `%post`.
Default ISO user: **admin** / **changeme**. Autopart **wipes the disk**.

Credentials: `scripts/tailwhip --user NAME` → `kickstart/AvalonOS.local.ks`
(gitignored, mode 600).

## Session keybinds (niri)

| Key | Action |
|---|---|
| Super+Return | alacritty |
| Super+D | `avalonos-launcher` (rofi: search + category tabs) |
| Super+Shift+Q | close window |
| Super+j/k/l/; or arrows | focus (left / down / up / right) |
| Super+Shift+j/k/l/; or arrows | move |
| Super+1…0 | workspace 1–10 |
| Super+Shift+1…0 | move column to workspace |
| Super+H | expel window to a new column |
| Super+V or Super+, | stack window to the right (tabbed, one visible) |
| Super+Shift+V or Super+Shift+, | consume into column (all visible) |
| Super+. | expel one window from the stack |
| Super+Shift+. | expel from column |
| Super+S / Super+Shift+S | stack all / consume all into a column |
| Super+W / Super+Shift+W | expel all from stack / column |
| Super+F | fullscreen |
| Super+Shift+F | maximize column |
| Super+Shift+Space | toggle floating |
| Super+Space | focus floating ↔ tiling |
| Super+R | cycle column width |
| Super+Shift+C | reload niri config |
| Super+Shift+E | exit niri |
| Super+Shift+X | lock (swaylock) |
| Print / Super+Print | screenshot full / region (grim, slurp) |

Waybar (right): mpris · HW stats · btop · brightness (lightbulb; tooltip
“brightness”) · volume (left-click **pavucontrol-qt**, right-click mute) ·
network (Wi-Fi picker, Bluetooth, connections) · battery · tray.
Icons: **Candy**.

Neovim (`<Space>` leader): `<leader>e` tree, `<leader>t` terminal,
`<leader>f` FZF, `gd`/`K` LSP. `:q` / `:wq` quit nvim entirely.
