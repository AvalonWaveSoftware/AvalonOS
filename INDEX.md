# AvalonOS documentation

Current description of the Fedora 44 AvalonOS desktop. Copied from
`/root/AvalonOS` for user **admin**.

| Path | What |
|---|---|
| `How-to-Install.md` | USB (BIOS + UEFI), first login, troubleshooting |
| `README.md` | stack, keybinds, overlay, ISO |
| `docs/decisions/` | ADRs |
| `docs/packages/` | dnf logs on the reference box |
| `docs/hardware.md` | this laptop |
| `docs/configs.md` | overlay file map |
| `docs/iso.md` | netinst remaster, golden tarball, kickstart |
| `kickstart/AvalonOS.ks` | kickstart **template** (placeholders, no hashes) |
| `kickstart/packages.inc` | ISO package list |
| `packaging/README.md` | golden tarball |

Install ISO (admin-owned copy):

`/home/admin/AvalonOS-netinst-x86_64.iso`

Rebuild from the git tree: `sudo /root/AvalonOS/scripts/build-iso.sh`.

Not in this tree: `overlay/`, nvim plugin sources, `AvalonOS.local.ks`
(password hash, mode 600 under `/root/AvalonOS/kickstart/`).
