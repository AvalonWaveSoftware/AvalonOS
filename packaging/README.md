# Packaging

The greeter is Fedora **tuigreet** (ADR 0003). QtGreet/DFL are not in
the tree.

ISO payload (built into `build/` by `scripts/build-iso.sh`):

- `scripts/make-golden-tarball.sh` → `packaging/avalonos-overlay.tar`
  (`root:root`, numeric owners, GNU format, no SELinux xattrs). Order,
  modes and mtimes come from `overlay.manifest`, so an unchanged overlay
  reproduces the shipped `overlay.tar` byte for byte
  (sha256 `7c126ea2…849ff8b7`, see ADR 0020).
- `scripts/make-docs-tarball.sh` → `packaging/avalonos-docs.tar`
  (README, INDEX, How-to-Install, docs/, kickstart template, packages.inc).
- `scripts/build-iso.sh` remasters Fedora Everything netinst and maps
  these to `/avalonos/overlay.tar` and `/avalonos/docs.tar` (ADR 0019).

`overlay.manifest` columns (tab-separated): `d|f`, octal mode, mtime
(Unix epoch), path. `scripts/update-overlay-manifest.sh` adds new paths
and drops removed ones; edit a line by hand to change a mode.

No extra AvalonOS RPM is required for the DE.
