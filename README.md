# AvalonOS

Minimal custom desktop environment on **Fedora 44**. Official Fedora
packages plus RPM Fusion **only** for NVIDIA. This repository is the
source for the AvalonOS netinst installer ISO. Documentation for the daily
user is also copied to `~/AvalonOS-Docs` on installed machines.

> This tree was rebuilt in October 2026 from the shipped ISO
> (`AvalonOS-netinst-x86_64.iso`, sha256 `4205f5d6…db30f3`) after the
> original `/root/AvalonOS` git tree was lost. Overlay, kickstart and GRUB
> changes are byte-exact; some helper scripts are reconstructions (ADR 0020).

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

## Layout

| Path | What |
|---|---|
| `kickstart/AvalonOS.ks` | kickstart template (`@AVALONOS_*@` placeholders, no hashes) |
| `kickstart/packages.inc` | `%packages` list; inlined into the kickstart at build time |
| `overlay/` | DE files, deployed as the golden tarball |
| `packaging/overlay.manifest` | tar order, modes and mtimes for a byte-reproducible `overlay.tar` |
| `boot/` | GRUB patches against the upstream `grub.cfg` (BIOS + EFI/ESP) |
| `scripts/` | build, fetch, tarball, credential and reference-box helpers |
| `upstream.env` | pinned upstream Fedora ISO (name, size, sha256, mirrors) |
| `keys/fedora-44.gpg` | Fedora 44 signing key used to verify the upstream CHECKSUM |
| `docs/` | ADRs, overlay map, ISO notes, hardware, package logs |
| `.github/workflows/release.yml` | CI build, attaches the ISO to a GitHub Release |

Not in git: the upstream ISO (`cache/`), build output (`build/`, `out/`),
generated tarballs, and `kickstart/AvalonOS.local.ks` (password hash).

## Rules

- `dnf --setopt=install_weak_deps=False`
- Overlay is source of truth; live configs must match it
- SELinux Enforcing
- No QtGreet, labwc, or vendor DFL/WayQt

## Apply overlay (this machine)

```bash
sudo scripts/apply-overlay.sh
```

Copies overlay files without SELinux context, then `restorecon`.

## ISO

The installer image is **not** in git. Get `AvalonOS-netinst-x86_64.iso`
from **GitHub Releases**.

**[How to Install](How-to-Install.md)**: USB (BIOS and UEFI), first
login, credentials.

Remaster of Fedora 44 Everything netinst (ADR 0019). Build as an ordinary
user (no root, no loop mounts) on Fedora or any Linux with `xorriso`,
`mtools`, `gnupg2`/`gpgv`, `curl`, `patch`, `tar` and `mkpasswd`:

```bash
export AVALONOS_ADMIN_PW_HASH="$(mkpasswd -m yescrypt)"   # prompts for the password
scripts/build-iso.sh
```

Output: `out/AvalonOS-netinst-x86_64.iso` and `.sha256`. The first run
downloads the upstream ISO (1.2 GB) into `cache/` and verifies it against
Fedora's signed CHECKSUM and `upstream.env`. Instead of the env var you can
run `scripts/tailwhip --user admin` once (writes the untracked
`kickstart/AvalonOS.local.ks`). With no credentials the build fails;
`AVALONOS_INSECURE_DEFAULT_PASSWORD=1` builds the legacy **admin/changeme**
image. That build is **insecure** and only for throwaway VMs.

Install needs network. The kickstart includes RPM Fusion and builds
`akmod-nvidia` in `%post`. Autopart **wipes the disk**.

Releases: push a `v*` tag; `.github/workflows/release.yml` builds in a
`fedora:44` container with the `AVALONOS_ADMIN_PW_HASH` repository secret
and uploads the ISO + `.sha256` to the Release for that tag. Release
assets may be up to 2 GB each; the ISO is about 1.24 GB.

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

Neovim plugins are vendored as shipped under
`overlay/usr/share/AvalonOS/nvim/pack/avalon/start/` (SHAs in
`docs/packages/nvim-plugins.md`). The tree-sitter parsers in
`overlay/usr/share/AvalonOS/nvim/parsers/parser/*.so` are **prebuilt x86_64
binaries** committed as-is so the overlay tarball stays byte-identical;
rebuild them with `:TSInstall` on a Fedora 44 box if you bump the plugins.
