# ADR 0007: SELinux stays Enforcing

- Status: accepted
- Date: 2026-09-06
- Fedora: 44

## Decision

Do not set SELinux permissive or disabled. Install `greetd-selinux` with
greetd. File custom policy only if our units/overlay actually AVC.

## Alternatives

- Permissive for greeter bring-up: hides bugs that the ISO would ship.

## Consequences

tuigreet, greetd, and NVIDIA modules must work under Enforcing. Log AVCs
in docs if we hit them.

`scripts/apply-overlay.sh` must **not** copy SELinux context from the git
tree (`admin_home_t`). It copies mode+timestamps only, then `restorecon`.
First apply used `cp -a` and NetworkManager refused
`/etc/NetworkManager/conf.d/00-iwd.conf` (Permission denied). Fixed.

## Rollback

Not permitted in v1.
