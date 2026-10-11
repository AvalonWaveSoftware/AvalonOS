# AvalonOS documentation

Current description of the Fedora 44 AvalonOS desktop. Copied from the
AvalonOS source repository for the daily user.

| Path | What |
|---|---|
| `How-to-Install.md` | USB (BIOS + UEFI), first login, troubleshooting |
| `README.md` | stack, keybinds, overlay, ISO |
| `docs/decisions/` | ADRs (0020: repo rebuilt from the ISO) |
| `docs/packages/` | dnf logs on the reference box |
| `docs/hardware.md` | this laptop |
| `docs/configs.md` | overlay file map |
| `docs/iso.md` | netinst remaster, golden tarball, kickstart |
| `kickstart/AvalonOS.ks` | kickstart **template** (placeholders, no hashes) |
| `kickstart/packages.inc` | ISO package list |
| `packaging/README.md` | golden tarball |

Install ISO: GitHub Releases of the AvalonOS repository
(`AvalonOS-netinst-x86_64.iso` + `.sha256`).

Rebuild from the git tree: `scripts/build-iso.sh` (see README, ISO).

Not in this tree: `overlay/`, nvim plugin sources, `AvalonOS.local.ks`
(password hash, mode 600, never committed).
