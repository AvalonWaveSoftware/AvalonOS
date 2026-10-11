# Reference hardware

This CyberPowerPC TRACER IV is the development box and the ISO
reference. Inventory date 2026-09-06; **current** session notes 2026-09-07.

| Item | Value |
|---|---|
| Product | CyberPowerPC TRACER IV GM5MQ8W |
| Chassis | laptop |
| CPU | Intel Core i7-10875H (Comet Lake-H, 16 threads) |
| RAM | 31 GiB |
| Disk | 1.9T XFS on LVM `fedora/root`, plus `/boot` XFS and `/boot/efi` |
| OS | Fedora Linux 44, `@^custom-environment` |
| Kernel | `7.1.13-200.fc44.x86_64` |
| Timezone / kbd | America/Chicago, us |
| SELinux | Enforcing |
| Daily user | **admin** (uid 1000, `wheel`) |
| systemd default | `graphical.target` (greetd is `display-manager.service`) |

## GPUs (hybrid)

| Card | PCI ID | Driver on this box | Role |
|---|---|---|---|
| Intel UHD | `8086:9bc4` | `i915` | internal panel; niri typically renders here |
| GTX 1650 Ti Max-Q | `10de:1e93` | `nouveau` until akmod; ISO installs `akmod-nvidia` | PRIME offload, not niri pin |

Distro niri config does **not** pin a render node or connector (ADR 0004).

Audio: HDA Intel PCH (PipeWire default). Mixer GUI: **pavucontrol-qt**.

Power: `BAT0`, `AC0`.

## Network

- Wired: `enp59s0` (NetworkManager)
- Wifi: Intel AX200 (`8086:2723`), firmware `iwlwifi-mvm-firmware`, backend **iwd**. Interface `wlan0` is up and can associate.
- Bluetooth: AX200 combo; `bluez` + `blueman` (manager opened from the waybar network menu, not a tray applet). `bluetooth.service` is disabled by default as of the post-0.1.0-8 batch (ADR 0006b); enable the unit if you want Bluetooth.

## Implications

- Graphical login is **admin** via tuigreet, never root.
- ISO kickstart builds NVIDIA akmod; this live box may still be on `i915`+`nouveau` until `scripts/install-nvidia.sh` or a kickstart install.
