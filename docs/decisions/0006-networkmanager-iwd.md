# ADR 0006: NetworkManager + iwd

- Status: accepted
- Date: 2026-09-06
- Fedora: 44

## Decision

NetworkManager stays the manager (`enp59s0` and `wlan0`). Wifi backend is
**iwd**. Firmware for the AX200 is `iwlwifi-mvm-firmware`. GUI is the
waybar network popup (`net-menu`: SSID list, `nm-connection-editor`,
nmtui). `nm-applet` autostart is **Hidden**.

## Context

AX200 `8086:2723` has no driver at inventory because iwlwifi firmware
files are absent from the split firmware packages. `wifi.backend=iwd` in
`/etc/NetworkManager/conf.d/00-iwd.conf`.

## Alternatives

- wpa_supplicant under NM: Fedora default; iwd is smaller and was chosen.
- iwd standalone, no NM: worse ISO/ethernet story.
- networkd: not the Fedora desktop path.

## Consequences

Enable iwd + NetworkManager. Do not run wpa_supplicant for wifi. Weak
deps off, so install `NetworkManager-wifi` and `NetworkManager-tui`
explicitly.

## Rollback

Delete `00-iwd.conf`, disable iwd, NM falls back to wpa_supplicant.
