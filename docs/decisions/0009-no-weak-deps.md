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

## Alternatives

- Default weak deps: niri would pull fuzzel etc. we do not want.
- COPR for QtGreet or niri-git: rejected.

## Consequences

Scripts pass the setopt. Kickstart `%packages --exclude-weakdeps`.
Document NEVRA in `docs/packages/stage*.md`.

## Rollback

Turning weak deps on would bloat the ISO; do not.
