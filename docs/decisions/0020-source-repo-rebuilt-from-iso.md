# ADR 0020: Source repository rebuilt from the shipped ISO; CI releases

- Status: accepted
- Date: 2026-10-11
- Fedora: 44

## Decision

The original `/root/AvalonOS` git tree was lost. This repository was
rebuilt from `AvalonOS-netinst-x86_64.iso` (1,238,040,576 bytes, sha256
`4205f5d6220a2a58cf36b96f0e15651cedbaa8ee8b6a991b24a0c57a08db30f3`,
built 2026-09-12). It is the source of truth from now on. ISOs are built by
`.github/workflows/release.yml` on `v*` tags and attached to GitHub Releases.

## What was recovered exactly

- `overlay/` from `/avalonos/overlay.tar`. With `packaging/overlay.manifest`
  (member order, modes, mtimes) `scripts/make-golden-tarball.sh` reproduces
  the shipped tarball byte for byte.
- `kickstart/AvalonOS.ks` template (shipped inside `docs.tar`) and
  `packages.inc`. The rendered kickstart is byte-identical to the shipped
  `/ks.cfg` for the same credentials.
- GRUB changes, as patches against the upstream configs in `boot/`.
- Docs and ADRs 0001–0019 from `/avalonos/docs.tar`.

Base image: the ISO is a remaster of the stock
`Fedora-Everything-netinst-x86_64-44-1.7.iso`; kernel, initrd,
`install.img` and EFI binaries are unmodified, so the build fetches
upstream instead of committing 1.2 GB.

## Changes while rebuilding

- `packages.inc` gained `systemd-pam` and `dbus-broker`. They were in the
  shipped kickstart's `%packages` but missing from the shipped
  `packages.inc` (drift). The kickstart `%packages` body is now generated
  from `packages.inc` (`@AVALONOS_PACKAGES@`), so the two cannot drift.
- Docs updated for the repo layout and the unprivileged build.
- Admin password hash comes from `AVALONOS_ADMIN_PW_HASH`,
  `kickstart/AvalonOS.local.ks`, or an explicit insecure opt-in.
- Upstream verification pins Fedora's 44 key in `keys/fedora-44.gpg`.

## Reconstructed (not recovered)

These scripts were not on the ISO; they were rewritten from the docs and
may differ from the originals: `build-iso.sh`, `fetch-upstream.sh`,
`render-kickstart.sh`, `make-golden-tarball.sh`, `make-docs-tarball.sh`,
`update-overlay-manifest.sh`, `verify-iso.sh`, `tailwhip`,
`apply-overlay.sh`, `dnf-install.sh` (log format guessed),
`install-nvidia.sh`. `How-to-Install.md` was referenced but not shipped;
it was rewritten from `docs/iso.md`.

Not recoverable: git history, the overlay before golden-tarball packing
(e.g. original file mtimes beyond those in the tarball), plugin `.git`
directories (SHAs survive in `docs/packages/nvim-plugins.md`).

## Consequences

The shipped ISO's admin password hash is visible to anyone who has the
ISO; treat that password as public and rotate it. New releases need the
`AVALONOS_ADMIN_PW_HASH` repository secret.
