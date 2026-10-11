# ISO — Fedora Everything netinst remaster

End-user USB and first-login steps: **[How to Install](../How-to-Install.md)**.

AvalonOS is a **remastered Fedora 44 Everything netinst**. Anaconda
fetches RPMs from Fedora + RPM Fusion mirrors. The DE overlay is a
**golden tarball** on the ISO, extracted in kickstart `%post`. The image
is hybrid: **BIOS (El Torito + grub2-mbr)** and **UEFI (GPT ESP)**. Both
GRUB copies (ISO9660 and the FAT ESP) default to **Install AvalonOS
(Fedora 44)** with `inst.ks`.

## Build

```bash
# defaults: user admin, password changeme, root locked
sudo /root/AvalonOS/scripts/build-iso.sh
```

Output:

- `/var/tmp/avalonos-iso/AvalonOS-netinst-x86_64.iso`
- copy: `/home/admin/AvalonOS-netinst-x86_64.iso`

Override user/password:

```bash
export AVALONOS_USER=alice
export AVALONOS_PASSWORD='...'
sudo -E /root/AvalonOS/scripts/build-iso.sh
```

`scripts/tailwhip` writes `kickstart/AvalonOS.local.ks` (0600, gitignored).
The tracked template `kickstart/AvalonOS.ks` never contains hashes.

## What is on the ISO

| Path on ISO | What |
|---|---|
| `/ks.cfg` | filled kickstart (`AvalonOS.local.ks`) |
| `/avalonos/overlay.tar` | golden overlay (root:root, no SELinux xattrs) |
| `/avalonos/docs.tar` | documentation → `/home/<user>/AvalonOS-Docs` |
| `/avalonos/packages.inc` | package list (also inlined in the ks) |

GRUB default entry: **Install AvalonOS (Fedora 44)** with
`inst.ks=hd:LABEL=Fedora-E-dvd-x86_64-44:/ks.cfg`. Volume id is left as
the Fedora netinst id so `inst.stage2=hd:LABEL=...` still works.

UEFI-only machines (HP Probook and similar) boot the **GPT EFI System
Partition** inside the hybrid ISO, not ISO9660 `/EFI/BOOT/grub.cfg`.
`build-iso.sh` patches `grub.cfg` **inside that FAT ESP** as well as the
ISO9660 copies. Re-flash the USB after rebuilding.

## Golden tarball

`scripts/make-golden-tarball.sh`:

1. Copy overlay files with `cp --preserve=mode,timestamps` (no SELinux xattrs).
2. Directories `0755`, files `0644`.
3. Known DE binaries `0755` (`avalonos-*`, `rofi-grouped`, `rofi-modes/*`, `hw-stats`, `net-menu`, `niri-stack`, `vi`).
4. `chown -R root:root`.
5. `tar --numeric-owner --owner=0 --group=0 --no-selinux`.

Kickstart `%post` extracts with `--no-same-owner --no-selinux`, then
`restorecon -RF`.

## Installer behaviour

- Unattended Anaconda (`cmdline`)
- Fedora `url` + `updates` mirrorlists
- RPM Fusion free + nonfree (release and updates) so `%packages` can
  install `akmod-nvidia`; `rpmfusion-*-release` RPMs remain on disk
- `%packages --exclude-weakdeps`: niri, tuigreet, waybar, rofi, Firefox,
  Dolphin, pavucontrol-qt, … RPM Fusion *release* RPMs (not akmod by default)
- bootloader (all hardware): `initcall_blacklist=simpledrm_platform_driver_init`
  so niri does not import EFI `simpledrm` as `card0` (`EINVAL` / Device missing)
- `%post` `lspci -n` for vendor `10de`: only then install `akmod-nvidia` and
  add `nvidia-drm.modeset=1`. Intel/AMD-only boxes blacklist `nvidia_drm` instead
- `autopart --type=lvm` **wipes the disk**
- `selinux --enforcing`
- enable NetworkManager, iwd, bluetooth, greetd, switcheroo-control, akmods
- overlay deploy from the **boot USB/ISO label** (not the network package
  repo), greetd as `display-manager.service`, linger for the daily user,
  docs into `~/AvalonOS-Docs`

## Host tools

`xorriso`, `mkpasswd`, `curl`, `tar`, `python3`.
