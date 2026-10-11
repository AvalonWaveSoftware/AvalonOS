# Packaging

The greeter is Fedora **tuigreet** (ADR 0003). QtGreet/DFL are not in
the tree.

ISO payload:

- `scripts/make-golden-tarball.sh` → `packaging/avalonos-overlay.tar`
  (`root:root`, numeric owners, no SELinux xattrs)
- `scripts/build-iso.sh` remasters Fedora Everything netinst and maps
  that tarball to `/avalonos/overlay.tar` (ADR 0019)

No extra AvalonOS RPM is required for the DE.
