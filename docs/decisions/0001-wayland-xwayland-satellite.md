# ADR 0001: Wayland + xwayland-satellite

- Status: accepted
- Date: 2026-09-06
- Fedora: 44

## Decision

The session is Wayland-only. X11 clients run through **xwayland-satellite**
(niri's on-demand integration), not a compositor-embedded Xwayland.

## Context

niri does not implement rootless Xwayland itself. Since niri 25.08 it
spawns `xwayland-satellite` >= 0.7 when an X client connects, exports
`$DISPLAY`, and restarts satellite if it dies. The niri RPM Requires
`xwayland-satellite >= 0.7`. F44 has 0.8.2.

## Alternatives

- Embedded Xwayland (Sway/Hyprland style): rejected; niri will not do this.
- No X11: too sharp for v1 (tools, games, Electron leftovers).
- Manual `spawn-at-startup "xwayland-satellite"` + `DISPLAY ":0"`: fights
  auto-integration; do not set `$DISPLAY` in niri config.

## Consequences

Install `xwayland-satellite`. Do not start Xwayland by hand. X11 apps that
need absolute screen coordinates may misbehave. labwc is **not** shipped.

## Rollback

Remove satellite; X11 apps stop. No X11 session is provided as a fallback.
