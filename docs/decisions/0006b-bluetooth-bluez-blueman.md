# ADR 0006b: bluez + blueman

- Status: accepted
- Date: 2026-09-06
- Fedora: 44

## Decision

Bluetooth is **bluez** + **blueman**. The blueman tray/autostart
`.desktop` files are **Hidden**; the manager is opened from the waybar
network menu. Audio via PipeWire/WirePlumber. `bluetooth.service` enabled.

## Context

AX200 is a combo card. CLI-only bluetooth is not “support” for a DE. GTK
is already pulled by portals/nm-applet.

## Alternatives

- bluetoothctl only: rejected.
- bluetuith: TUI, smaller, less obvious.
- gnome-bluetooth: GNOME pull.

## Consequences

blueman-manager is the GUI. Waybar tray is enabled for other applets;
blueman itself is not autostarted. Unblock rfkill as needed. ibt firmware
ships with iwlwifi-mvm-firmware.

## Rollback

Disable bluetooth.service; remove blueman/bluez.

## Residual (AOS-SEC-09)

`bluetooth.service` remains enabled by design of this decision, including
the kickstart `services --enabled=` list and a `systemctl enable` of
`bluetooth.service`. That is an accepted residual of the chosen Bluetooth
support, not an oversight. Do not silently disable it in a later hardening
pass without revisiting this decision. Rollback, if Master Chief chooses
it, is still: disable `bluetooth.service` and remove blueman/bluez.
