# ADR 0015: Notifications are dunst

- Status: accepted
- Date: 2026-09-06
- Fedora: 44

## Decision

Install `dunst` 1.13.2. Spawn it from niri. Do not install mako. Frame
color neon, urgency-critical uses purple-red.

## Alternatives

- mako: wlroots-typical; user chose dunst.
- notification-daemon / swaync: extra.

## Consequences

dunst talks Wayland layer-shell. Config in `/etc/xdg/dunst/dunstrc` and
`/etc/dunst/dunstrc` (same content).
