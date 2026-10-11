# ADR 0011: Launcher is rofi 2 (Wayland)

- Status: accepted
- Date: 2026-09-06
- Fedora: 44

## Decision

Install Fedora `rofi` 2.0.0 (Provides `rofi-wayland`). There is no
separate `rofi-wayland` RPM. Do not install fuzzel or wofi.

## Alternatives

- fuzzel: niri Recommends it, smaller; user chose rofi.
- wofi: extra.

## Consequences

`rofi-themes` is a hard Requires. Super+D runs `avalonos-launcher`,
which starts rofi in a custom script mode (`rofi-grouped` +
`rofi-modes/*`): left column search + category tabs, right column
programs. Theme: `usr/share/rofi/themes/AvalonOS.rasi`.
