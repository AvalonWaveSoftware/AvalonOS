# ADR 0010: Portals gtk + gnome, FileChooser=gtk

- Status: accepted
- Date: 2026-09-06
- Fedora: 44

## Decision

Install `xdg-desktop-portal`, `xdg-desktop-portal-gtk`,
`xdg-desktop-portal-gnome`, `gnome-keyring`. Overlay
`niri-portals.conf` so FileChooser is **gtk** (no Nautilus). Do **not**
install `xdg-desktop-portal-wlr`.

## Context

niri Recommends gtk+gnome portals; gnome is required for screencast.
gnome portal 47+ FileChooser defaults to Nautilus. Mixing wlr + gnome
without a portals.conf silently breaks screencast.

## Alternatives

- wlr portal only: against niri upstream recommendation.
- Nautilus for file chooser: bloat.

## Consequences

Must start niri through the systemd user unit (`avalonos-session` →
`niri.service`). gnome-shell is not installed.

## Rollback

Edit portals.conf; removing gnome portal kills screencast.
