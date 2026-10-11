# ADR 0006b: bluez + blueman

- Status: accepted (revised)
- Date: 2026-09-06
- Revised: 2026-11-21 (post-0.1.0-8 batch)
- Fedora: 44

## Decision

Bluetooth is **bluez** + **blueman**. The blueman tray/autostart
`.desktop` files are **Hidden**; the manager is opened from the waybar
network menu. Audio via PipeWire/WirePlumber.

As of the post-0.1.0-8 batch, `bluetooth.service` is **disabled by
default** (Master Chief, 2026-11-21: "Disable Bluetooth after this
release"). bluez and blueman remain installed so a user can enable the
service when they want Bluetooth. v0.1.0-8 and earlier shipped the
service enabled; that is unchanged on already-released images.

## Context

AX200 is a combo card. CLI-only bluetooth is not “support” for a DE. GTK
is already pulled by portals/nm-applet. AOS-SEC-09 recorded the enabled
service as a residual of the original decision. Master Chief later
directed that the service be disabled after the 0.1.0-8 release, without
removing the packages.

## Alternatives

- bluetoothctl only: rejected.
- bluetuith: TUI, smaller, less obvious.
- gnome-bluetooth: GNOME pull.
- Disable the service and remove blueman/bluez: rejected; packages stay.

## Consequences

blueman-manager is the GUI. Waybar tray is enabled for other applets;
blueman itself is not autostarted. Unblock rfkill as needed. ibt firmware
ships with iwlwifi-mvm-firmware. The kickstart `services` list disables
`bluetooth`, and `%post` runs `systemctl disable bluetooth.service`, so a
bluez package preset cannot leave the service enabled.

## Rollback

Enable `bluetooth.service` (the v0.1.0-8 behaviour), or remove
blueman/bluez as well if Bluetooth support is withdrawn.
