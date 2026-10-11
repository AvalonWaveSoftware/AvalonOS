# ADR 0012: Terminal is alacritty

- Status: accepted
- Date: 2026-09-06
- Fedora: 44

## Decision

Install `alacritty` 0.17. Bind **Super+Return** to it. Config:
`/etc/xdg/alacritty/alacritty.toml` with the palette.

## Context

Heavier than foot (OpenGL, libxkbcommon-x11). User chose it. niri also
Recommends alacritty.

## Alternatives

- foot: smaller, Wayland-native.
- kitty: extra GPU terminal.

## Consequences

Need a monospace font package (Noto Sans Mono or similar) listed in
stage2. Intentional bloat vs foot.
