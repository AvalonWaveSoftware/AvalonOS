# ADR 0002: Compositor is niri

- Status: accepted
- Date: 2026-09-06
- Fedora: 44

## Decision

The DE compositor is **niri** (scrollable tiling). The greetd session
Exec is `/usr/local/bin/avalonos-session`, which starts `niri.service`
(same systemd user + portals path as stock `niri-session`, without VT
noise). Distro default config is `/etc/niri/config.kdl` from the overlay.

## Context

F44 has niri 26.04 in official repos. It ships `niri-session`,
`niri.desktop`, `niri.service`, and `niri-portals.conf`. Default config
spawns waybar; we vendor our own so we do not double-bar.

## Alternatives

- Sway: more ISO-common, i3-like; rejected after user chose niri.
- Hyprland: extra packaging/NVIDIA pain.
- labwc: was greeter-only; removed with QtGreet.
- COSMIC/GNOME/KDE: not minimal.

## Consequences

Session Exec is `avalonos-session`, never raw `niri`. niri auto-selects
the DRM device (ADR 0004). Recommends (alacritty, waybar, portals) are
installed **explicitly**; fuzzel is not (ADR 0009).

## Rollback

Replace session desktop Exec and overlay config. Portals.conf is niri-specific.
