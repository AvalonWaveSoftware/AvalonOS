# ADR 0009: No weak deps, two repo exceptions

- Status: accepted
- Date: 2026-09-06
- Fedora: 44

## Decision

Every dnf transaction uses `--setopt=install_weak_deps=False`. Packages
niri Recommends are installed only when we chose them, listed in the
stage file.

Repos: Fedora + updates, plus (a) RPM Fusion free/nonfree **only** for
NVIDIA. No COPR. No vendor greeter.

Exception (ADR 0021, 2026-11-22): the Fedora `flatpak` package ships
in the image; on first boot when the network is up, Flathub is added
and `md.obsidian.Obsidian` is installed. The ISO itself stays
RPM-signed only and does not vendor Flathub content.

## Alternatives

- Default weak deps: niri would pull fuzzel etc. we do not want.
- COPR for QtGreet or niri-git: rejected.

## Consequences

Scripts pass the setopt. Kickstart `%packages --exclude-weakdeps`.
Document NEVRA in `docs/packages/stage*.md`.

## Rollback

Turning weak deps on would bloat the ISO; do not.
