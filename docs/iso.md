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
export AVALONOS_ADMIN_PW_HASH="$(mkpasswd -m yescrypt)"   # or: scripts/tailwhip --user admin
scripts/build-iso.sh
```

Runs unprivileged. Output:

- `out/AvalonOS-netinst-x86_64.iso`
- `out/AvalonOS-netinst-x86_64.iso.sha256`

Credentials, in order of precedence (nothing secret is in git):

1. `AVALONOS_ADMIN_PW_HASH`: crypt(3) hash for the daily user
   (`AVALONOS_USER`, default `admin`; `AVALONOS_ROOTPW_LINE`, default
   `rootpw --lock`). CI reads it from the repository secret of the same name.
2. `kickstart/AvalonOS.local.ks` written by `scripts/tailwhip` (0600,
   gitignored). Only its `tailwhip:auth` block is reused; the rest is
   re-rendered from the current template and `packages.inc`.
3. `AVALONOS_INSECURE_DEFAULT_PASSWORD=1`: legacy **admin / changeme**.
   **Insecure**; throwaway test VMs only.

With none of these the build stops with an error.

Pipeline (`scripts/build-iso.sh`):

1. `scripts/fetch-upstream.sh`: download the ISO named in `upstream.env`
   into `cache/`, verify the CHECKSUM file with `gpgv` against
   `keys/fedora-44.gpg` (fingerprint pinned in `upstream.env`), and check
   the ISO sha256 against both. Cached copies are reused.
2. `scripts/render-kickstart.sh`: `kickstart/AvalonOS.ks` +
   `packages.inc` + credentials → `build/ks.cfg` (deleted after the build).
3. `scripts/make-golden-tarball.sh` / `make-docs-tarball.sh` → `build/payload/avalonos/`.
4. Extract the upstream `EFI/BOOT/grub.cfg` and `boot/grub2/grub.cfg`,
   apply `boot/grub-efi.patch` / `boot/grub-bios.patch`, copy EFI
   `grub.cfg` to `BOOT.conf`.
5. Cut the FAT ESP (GPT partition 2) out of the upstream image and
   `mcopy` the patched `grub.cfg` + `BOOT.conf` into it.
6. `xorriso -indev upstream -outdev out -boot_image any replay` keeps the
   El Torito catalog, BIOS `images/eltorito.img`, `grub2-mbr` and GPT;
   the patched ESP is re-appended as partition 2 and used as the UEFI
   El Torito image; payload and GRUB configs are mapped in (root:root,
   `/ks.cfg` 0600).
7. `scripts/verify-iso.sh` checks boot layout, all three GRUB copies and
   the payload. `verify-iso.sh --full ISO` also sha256-compares every other
   file with upstream (`images/eltorito.img` is expected to differ: xorriso
   rewrites its boot-info table).

To move to a new Fedora point release or version, update `upstream.env`
(and `keys/`, the volume id and `boot/*.patch` for a new major).

## What is on the ISO

| Path on ISO | What |
|---|---|
| `/ks.cfg` | filled kickstart (`AvalonOS.local.ks`) |
| `/avalonos/overlay.tar` | golden overlay (root:root, no SELinux xattrs) |
| `/avalonos/docs.tar` | documentation → `/home/<user>/AvalonOS-Docs` |
| `/avalonos/packages.inc` | package list (also inlined in the ks) |

Everything else (kernel, initrd, `install.img`, shim/GRUB EFI binaries,
`.discinfo`) is the unmodified upstream file.

GRUB default entry: **Install AvalonOS (Fedora 44)** with
`inst.ks=hd:LABEL=Fedora-E-dvd-x86_64-44:/ks.cfg`. Volume id is left as
the Fedora netinst id so `inst.stage2=hd:LABEL=...` still works.

UEFI-only machines (HP Probook and similar) boot the **GPT EFI System
Partition** inside the hybrid ISO, not ISO9660 `/EFI/BOOT/grub.cfg`.
`build-iso.sh` patches `grub.cfg` (and `BOOT.conf`) **inside that FAT ESP**
with mtools as well as the ISO9660 copies. Re-flash the USB after rebuilding.

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

`xorriso`, `mtools`, `gpgv` (gnupg2), `curl`, `patch`, `tar`, `mkpasswd`
(Fedora: `dnf install xorriso mtools gnupg2 curl patch tar mkpasswd`).
Optional for smoke tests: `qemu-system-x86_64`, `edk2-ovmf`.
