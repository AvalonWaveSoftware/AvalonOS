# Package log

Every `dnf install` on the reference box goes through
`scripts/dnf-install.sh`, which appends NEVRA + UTC timestamp to a stage
file with `install_weak_deps=False`.

| File | What |
|---|---|
| `freeze-baseline.txt` | `rpm -qa` before DE work |
| `stage0-base.md` | git-core, pciutils, mesa, iwlwifi firmware, iwd, neovim, bluez |
| `stage1-session.md` | niri, greetd, tuigreet, portals, terminus console fonts |
| `stage2-desktop.md` | waybar, rofi, alacritty, dunst, Firefox, Dolphin, qt6ct, Candy |
| `stage3-laptop.md` | pavucontrol-qt |
| `nvim-plugins.md` | vendored Neovim plugin SHAs |

ISO `%packages` is `kickstart/packages.inc` (inlined in `AvalonOS.ks`),
not a generated `freeze.txt`. NVIDIA RPMs are pulled at **install time**
from RPM Fusion, not recorded as a stage transaction on this live box
until `scripts/install-nvidia.sh` is run here.

Do not put `labwc`, `lightdm`, `meson`, `ninja-build`, or `*-devel`
(except `kernel-devel` / `elfutils-libelf-devel` for akmods) on the ISO.
