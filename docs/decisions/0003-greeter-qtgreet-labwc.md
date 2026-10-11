# ADR 0003: greetd + tuigreet

- Status: accepted (supersedes QtGreet + labwc)
- Date: 2026-09-07
- Fedora: 44

## Decision

Login is **greetd**. The greeter is Fedora **tuigreet** 0.9, run as user
`greetd` on tty1 via `/usr/local/bin/avalonos-greeter`.

## Context

QtGreet + labwc delayed session start (~8s), printed red NVIDIA xHCI
errors on the VT, and needed a vendor Qt6/DFL build. tuigreet is in
Fedora, TTY-native, and themable.

Theme (ANSI, Linux console): neon as `lightgreen`, accent as `magenta`,
container `black`, text `white`.

Do **not** pass `--remember-user-session` (tuigreet 0.9.1 exits immediately).
Do **not** redirect tuigreet stdout (it requires a TTY).

## Alternatives

- QtGreet + labwc: rejected (DRM handoff, vendor stack).
- gtkgreet + cage: extra compositor again.
- SDDM: drops greetd.

## Rollback

Restore QtGreet/labwc (not kept in tree).
