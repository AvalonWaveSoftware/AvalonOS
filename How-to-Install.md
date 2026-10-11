# How to install AvalonOS

> Rewritten in October 2026 from `docs/iso.md`; the original page was not
> on the ISO.

The default menu entry asks which disk to install to and **erases that whole
disk** after you type its name. Back up first. Installation needs a wired or
DHCP network: packages come from Fedora and RPM Fusion mirrors.

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

## 3. NVIDIA machines: turn off Secure Boot first

**Why.** AvalonOS installs the NVIDIA driver from RPM Fusion as
`akmod-nvidia`: the kernel module is compiled on your machine and is not
signed with a key your firmware trusts. With Secure Boot on, the kernel
refuses to load an unsigned module, so the NVIDIA driver cannot work.
AvalonOS does not enroll its own Machine Owner Key (MOK).

**How.** Exact menus differ by vendor; in general:

1. Enter the firmware setup: power on and press the setup key (often `F2`,
   `Del`, `F10`, `F12` or `Esc`; Lenovo laptops may have a Novo button). From
   a running Linux system, `sudo systemctl reboot --firmware-setup` does it.
2. Find **Secure Boot**, usually under *Security*, *Boot* or
   *Authentication*. Some firmware asks you to set a supervisor/admin
   password before the option can be changed.
3. Set Secure Boot to **Disabled** (on some machines: set *OS type* to
   *Other OS*, or clear the Secure Boot keys / switch to *Setup Mode*). Leave
   UEFI mode on; do not switch to Legacy/CSM unless you also want a BIOS
   install.
4. Save and exit (often `F10`).

Check from Linux afterwards: `mokutil --sb-state` should print
`SecureBoot disabled` (or `od -An -tu1 -j4 -N1
/sys/firmware/efi/efivars/SecureBoot-*` prints `0`).

**If you leave it on.** The install still finishes, but unless the driver is
signed by a key your firmware trusts (never the case on a fresh install), the
NVIDIA step counts as failed and fails closed: AvalonOS removes the NVIDIA packages,
does not blacklist nouveau, and the machine runs on the open-source
**nouveau** driver (if nouveau cannot drive the card either, see
Troubleshooting: "no render device"). The reason
is logged in `/var/log/avalonos-hw.log` ("Secure Boot is on"). The same
happens if AvalonOS cannot read the Secure Boot state on a UEFI machine
("Secure Boot state unreadable"): it then assumes Secure Boot is on. To switch
later, turn Secure Boot off, boot AvalonOS and run:

```bash
sudo /usr/libexec/avalonos/hw-setup && sudo dracut -f --regenerate-all && sudo reboot
```

Machines without an NVIDIA GPU can keep Secure Boot on.

## 4. Boot

- UEFI: pick the USB entry in the firmware boot menu. UEFI-only machines
  boot the ESP inside the image; it carries the same menu.
- BIOS/legacy: pick the USB disk.

The GRUB menu waits; nothing starts on its own. Pick **Install AvalonOS
(Fedora 44) - choose disk**, then follow the disk prompt on the text screen:
type the disk name (and `ERASE` if it holds data or is a USB disk). Use
*Troubleshooting → basic graphics mode* if the screen stays blank. Do not
pick **AUTOMATIC INSTALL - ERASES ALL DISKS**: it is for VMs and testing and
wipes every disk without asking.

The installer then runs on its own and reboots when done. Remove the USB stick.

## 5. First login

On the first boot a text screen on tty1 asks for a **username and password**
(no default account exists; root stays locked, admin via `sudo`). After that
the machine updates, reboots, and tuigreet shows the login screen.

Machines with an NVIDIA GPU build `akmod-nvidia` during install (Secure Boot
off; see step 3); the first boot may take a little longer.

## Troubleshooting

- Install logs: `/root/avalonos-post.log`, `/root/avalonos-nochroot.log`,
  `/root/avalonos-hw-post.log`, `/var/log/avalonos-hw.log`.
- NVIDIA GPU but nouveau in use (`lspci -k | grep -A3 -i nvidia`): see
  `/var/log/avalonos-hw.log`; "Secure Boot is on" or "Secure Boot state
  unreadable" means step 3.
- The installer stops right away with "AvalonOS installer: … Refusing to
  install" (or the install aborts with "Signature verification failed"): the
  ISO or a package from the mirror did not pass the signature checks. Write
  the ISO again from a verified download (`sha256sum -c`); do not add
  `inst.repo=`, `inst.addrepo=` or `noverifyssl` to the boot line.
- "RPM repo (avalonos/repo) not found on installation media": the stick was relabeled
  or the ISO was copied as a file instead of written raw.
- After login: "this display adapter has no render device; the desktop
  (niri) cannot draw on it". The only display is a plain framebuffer adapter
  (QEMU `-vga std`/cirrus, Hyper-V video, server BMC VGA) with no GPU behind
  it. In QEMU/libvirt use a virtio GPU (`-vga virtio`, or `virtio-vga-gl` with
  `gl=on` for 3D). On a machine that also has a real GPU, plug the monitor
  into that GPU. The text console (Ctrl+Alt+F2) still works.
- After login, Alacritty (Super+Return) does not launch in a virtual machine. This is a known limitation.
