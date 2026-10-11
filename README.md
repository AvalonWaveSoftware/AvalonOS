# AvalonOS

Minimal custom desktop environment on **Fedora 44**. Official Fedora
packages plus RPM Fusion **only** for NVIDIA, with one first-boot
exception: Flathub is added after install to install Obsidian
(ADR 0021). The installer ISO stays RPM-signed only. This repository is the
source for the AvalonOS netinst installer ISO. Documentation for the daily
user is also copied to `~/AvalonOS-Docs` on installed machines.

> This tree was rebuilt in October 2026 from the shipped ISO
> (`AvalonOS-netinst-x86_64.iso`, sha256 `4205f5d6…db30f3`) after the
> original `/root/AvalonOS` git tree was lost. Overlay, kickstart and GRUB
> changes are byte-exact; some helper scripts are reconstructions (ADR 0020).

ISO installs: root is locked (`rootpw --lock`) and the daily user (uid 1000,
`wheel`) is created on first boot by `avalonos-make-user`. No password or
hash is on the ISO.

## Locked stack

Wayland, **niri** 26, **xwayland-satellite**, **greetd** + **tuigreet**
(wrapper `/usr/local/bin/avalonos-greeter`), **waybar**, **rofi** 2,
**alacritty**, **neovim** (`vi` → nvim), **dunst**, PipeWire,
NetworkManager + **iwd**, **NetworkManager-libreswan**, **bluez** +
**blueman**, **Firefox**, **Dolphin**, **pavucontrol-qt**, **flatpak**
(Obsidian from Flathub on first boot when the network is up; an offline
install gets it later, ADR 0021). Session Exec is
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
| `overlay/` | DE files, packaged into the `avalonos-*` RPMs |
| `packaging/rpm/` | RPM specs (`avalonos`, `avalonos-nvim-parsers`, `avalonos-nvim-lsp`), preset, rpmlintrc |
| `installer/updates/` | installer repo files (`gpgcheck=1`, pinned keys) packed into `/avalonos/updates.img` (P-M1r) |
| `testing/testseed/` | QA test builds only (`AVALONOS_TEST_BUILD=1`): first-boot test seed; never in a release |
| `packaging/overlay.manifest` | legacy (golden tarball, no longer used by the ISO build) |
| `boot/` | GRUB patches against the upstream `grub.cfg` (BIOS + EFI/ESP) |
| `scripts/` | build, fetch, tarball, credential and reference-box helpers |
| `upstream.env` | pinned upstream Fedora ISO (name, size, sha256, mirrors) |
| `keys/` | Fedora 44 key (verifies the upstream CHECKSUM), RPM Fusion keys, `PINNED-FINGERPRINTS` |
| `docs/` | ADRs, overlay map, ISO notes, hardware, package logs |
| `.github/workflows/release.yml` | CI build, attaches the ISO to a GitHub Release |

Not in git: the upstream ISO (`cache/`), build output (`build/`, `out/`),
generated RPMs, and any `avalonos-seed.conf` test seed (QA test builds
only; see docs/iso.md "Test builds").

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
`mtools`, `gnupg2`/`gpgv`, `curl`, `patch`, `tar`, `rpm-build`,
`createrepo_c` and `gcc` (see `docs/iso.md`; a signed AvalonOS repo is required, see below):

```bash
scripts/build-iso.sh
```

Output: `out/AvalonOS-netinst-x86_64.iso` and `.sha256`. The first run
downloads the upstream ISO (1.2 GB) into `cache/` and verifies it against
Fedora's signed CHECKSUM and `upstream.env`.

Install needs network. The kickstart includes RPM Fusion and builds
`akmod-nvidia` in `%post` (fails closed: nouveau stays if the build fails).
**NVIDIA machines: turn Secure Boot off in the firmware before installing**:
the akmod driver is unsigned and will not load with Secure Boot on; AvalonOS
then stays on nouveau (see [How to Install](How-to-Install.md) §3).
The default boot entry asks which disk to use and erases only that disk
after you type its name; only the separate "ERASES ALL DISKS" entry wipes
unattended.

AvalonOS RPMs and repo metadata are signed (key fingerprint
`F0AA82E5FEB779364658A18D96508B1357FDAB48`, public key
`keys/RPM-GPG-KEY-avalonos`); the private key stays on the build machine, so
`build-iso.sh` needs `AVALONOS_SIGN=1` there or `AVALONOS_SIGNED_REPO=DIR`
elsewhere (see `docs/iso.md`). QA test builds (`AVALONOS_TEST_BUILD=1`) use a
separate TEST signing key (`keys/RPM-GPG-KEY-avalonos-test`) that no release
ever ships or trusts.

Releases: sign on the build machine and attach the signed repo as
`avalonos-signed-repo.tar` to the release, then push the `v*` tag;
`.github/workflows/release.yml` builds in a `fedora:44` container (no signing
key), verifies the repo against the pinned key, runs rpmlint, and uploads the
ISO + `.sha256` to the Release for that tag. Release
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
Language servers lua-language-server, marksman (`avalonos-nvim-lsp`, pinned
by version and sha256) and bash-language-server (Fedora) are installed;
nothing is downloaded on first start.

Neovim plugins are vendored as shipped under
`overlay/usr/share/AvalonOS/nvim/pack/avalon/start/` (SHAs in
`docs/packages/nvim-plugins.md`). The tree-sitter parsers are
compiled from pinned grammar sources at build time
(`packaging/rpm/avalonos-nvim-parsers.spec`, revisions in
`packaging/rpm/nvim-parser-info/`); no prebuilt binaries are committed.
