# ADR 0004: niri on Intel, NVIDIA offload

- Status: accepted
- Date: 2026-09-06
- Fedora: 44

## Decision

niri does **not** pin a DRM render node, connector name, or mode. The
compositor auto-selects GPU and outputs so the same overlay boots on
arbitrary hardware (Intel / AMD / NVIDIA / hybrid / HDMI-only).

On this development laptop, Intel i915 still drives the internal panel.
RPM Fusion NVIDIA (`akmod-nvidia`, ADR 0014) is in the ISO kickstart for
PRIME offload, not as a compositor pin in `config.kdl`.

## Context

Hybrid laptop: Intel `8086:9bc4` + NVIDIA `10de:1e93` (Turing, 1650 Ti
Max-Q). An earlier revision hardcoded:

- `debug { render-drm-device "/dev/dri/by-path/pci-0000:00:02.0-render" }`
- `output "eDP-1" { mode "1920x1080@60.000" }`

Those paths and modes exist only on this chassis. They would fail or
ignore the display on other machines, so they were removed.

Kickstart (and `scripts/install-nvidia.sh` on this box) blacklist nouveau
and set `nvidia-drm.modeset=1`. Do not encode PCI addresses in the distro
niri config.

## Alternatives

- nouveau only: no user-requested proprietary driver.
- NVIDIA as niri GPU: rejected for v1 stability.
- nvidia-open modules: Turing can use them; user asked RPM Fusion nvidia
  (akmod-nvidia proprietary). Stick to that.

## Consequences

If akmod build fails, machine must still TTY-boot on i915. No CUDA package
in v1. `switcheroo-control` for offload.

## Rollback

Remove NVIDIA RPMs, un-blacklist nouveau, remove kernel args, reboot.
