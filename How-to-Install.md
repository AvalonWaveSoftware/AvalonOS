# How to install AvalonOS

> Rewritten in October 2026 from `docs/iso.md`; the original page was not
> on the ISO.

**The installer is unattended and wipes the whole target disk** (`zerombr`,
`clearpart --all`, LVM autopart). Back up first. Installation needs a wired
or DHCP network: packages come from Fedora and RPM Fusion mirrors.

## 1. Get the ISO

Download `AvalonOS-netinst-x86_64.iso` and `AvalonOS-netinst-x86_64.iso.sha256`
from the GitHub Release, then:

```bash
sha256sum -c AvalonOS-netinst-x86_64.iso.sha256
```

## 2. Write a USB stick

The image is hybrid (BIOS + UEFI). Write it raw; do not copy files:

```bash
sudo dd if=AvalonOS-netinst-x86_64.iso of=/dev/sdX bs=4M conv=fsync status=progress
```

(Fedora Media Writer or `dd` on Windows/macOS equivalents also work.)
Do not relabel the stick: the installer finds its files by the volume label
`Fedora-E-dvd-x86_64-44`.

## 3. Boot

- UEFI: pick the USB entry in the firmware boot menu. UEFI-only machines
  boot the ESP inside the image; it carries the same menu.
- BIOS/legacy: pick the USB disk.

GRUB defaults to **Install AvalonOS (Fedora 44)** after 15 s. Use
*Troubleshooting → basic graphics mode* if the screen stays blank.

The installer runs on its own and reboots when done. Remove the USB stick.

## 4. First login

tuigreet on the console. User **admin** (wheel); the password is whatever
the ISO builder set (`AVALONOS_ADMIN_PW_HASH`). Root is locked. Change the
password after the first login with `passwd`.

Machines with an NVIDIA GPU build `akmod-nvidia` during install; the first
boot may take a little longer.

## Troubleshooting

- Install logs: `/root/avalonos-post.log`, `/root/avalonos-nochroot.log`,
  `/root/avalonos-nvidia-post.log`.
- "overlay.tar not found on installation media": the stick was relabeled
  or the ISO was copied as a file instead of written raw.
