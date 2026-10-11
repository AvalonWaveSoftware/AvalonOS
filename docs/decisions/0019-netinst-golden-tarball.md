# ADR 0019: Fedora netinst remaster + golden overlay tarball

- Status: accepted
- Date: 2026-09-07
- Fedora: 44

## Decision

The ISO is a remaster of **Fedora Everything netinst**, not a lorax live
squashfs. Anaconda installs from Fedora mirrors. The DE is a **golden
tarball** (`overlay.tar`) on the ISO, deployed in kickstart `%post` as
`root:root` with `restorecon` afterwards.

## Context

livemedia-creator would duplicate the whole root. A netinst keeps the
image small, uses official packages at install time, and still ships our
overlay (configs, wallpaper, nvim pack, greeter wrapper).

SELinux: copying from `/root/AvalonOS` labels files `admin_home_t`.
NetworkManager already refused that once. The tarball stores **no**
SELinux xattrs; `%post` runs `restorecon`.

## Alternatives

- lorax/livemedia-creator: heavier, full live root. Rejected for v1.
- Overlay RPM: still valid later; tarball is enough to install.
- `mkosi`: fallback if remastering boot catalogs breaks.

## Consequences

Build host needs network to fetch the netinst ISO (once) and the
installed machine needs network during Anaconda. Kickstart enables
RPM Fusion free+nonfree and builds `akmod-nvidia` in `%post` (ADR 0014).

## Rollback

Use stock Fedora netinst. Delete `AvalonOS-netinst-x86_64.iso`.
