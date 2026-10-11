# ADR 0016: Palette

- Status: accepted
- Date: 2026-09-06
- Fedora: 44

## Decision

Single token file `overlay/usr/share/AvalonOS/palette.env` (and
`palette.css`). Hex is the contract.

| Token | Hex | Role |
|---|---|---|
| bg | `#0A1628` | dark naval blue |
| bg-alt | `#102445` | lifted navy |
| border-idle | `#1A3A5C` | unfocused |
| fg | `#D4FFD4` | body text |
| neon | `#39FF14` | focus, titles, cursor |
| accent | `#C2185B` | purple-red |
| accent-dim | `#8B1450` | pressed/hover |

Applied to niri, tuigreet, waybar, dunst, rofi, alacritty, qt6ct, KDE
colors, Firefox prefs. Session wallpaper is `wallpaper.png` (swaybg).
tuigreet uses ANSI `lightgreen`/`magenta`/`black`. GTK uses Candy icons
and prefers dark; no custom GTK theme pack. System icons are Fedora
**candy-icon-theme** (`Candy`).

## Alternatives

- Per-app ad-hoc colors: rejected; ISO would drift.
- Full Sweet GTK/Kvantum pack: skipped; icons only (`Candy`).

## Consequences

Change colors only in the token files, then copy hex into app configs
(waybar CSS can `@import` palette.css; kdl/toml/rasi cannot — keep hex
in sync when tokens change).
