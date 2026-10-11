# ADR 0017: tailwhip fills kickstart credentials

- Status: accepted
- Date: 2026-09-06
- Fedora: 44

## Decision

ISO user and password are **not** stored in git. `scripts/tailwhip`
hashes a password with `mkpasswd -m yescrypt` (Fedora `$y$j9T$` default)
and writes `kickstart/AvalonOS.local.ks` from the tracked template
`kickstart/AvalonOS.ks`. The local file is gitignored, mode 600.

Default root policy: `rootpw --lock`. Daily user is `wheel`. Username
comes from `--user` at whip time, not from overlay.

## Context

ADR 0008 requires a non-root GUI user. The Anaconda ancestor had a root
hash we redacted. `scripts/build-iso.sh` needs a finished kickstart
(`AvalonOS.local.ks`) with `user` + `rootpw` at build time, not in git.
Default whip: `--user admin`.

## Alternatives

- Commit hashes: rejected (secrets in git).
- `%post` useradd with plaintext in the ks: worse.
- openssl passwd: openssl is not on this minimal box; `mkpasswd` is.
- Python `crypt`: removed in Python 3.13.

## Consequences

Build host needs `mkpasswd`. ISO build must consume `AvalonOS.local.ks`,
never the template with `@AVALONOS_*@` placeholders still in it. Password is
read from `--password-env` or a tty prompt; never from argv.

```
scripts/tailwhip --user alice
scripts/tailwhip --user alice --password-env AVALONOS_PASSWORD
scripts/tailwhip --user alice --password-env AVALONOS_PASSWORD --root-password-env AVALONOS_ROOT_PASSWORD
```

## Rollback

Delete `kickstart/AvalonOS.local.ks`. Template stays placeholder-only.
