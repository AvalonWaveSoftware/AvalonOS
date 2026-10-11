# ADR 0013: neovim, vi → nvim system-wide

- Status: accepted
- Date: 2026-09-06
- Fedora: 44

## Decision

Install `neovim`. Do not install `vim-enhanced`. Leave `vim-minimal` if
already present (it is: `vim-minimal-9.2.967-1.fc44`).

Two layers, because aliases do not apply to sudo/scripts:

1. `/etc/profile.d/nvim-vi.sh` — `alias vi=nvim`; `EDITOR=nvim`; `VISUAL=nvim`
2. `/usr/local/bin/vi` — `exec /usr/bin/nvim -- "$@"`

`/usr/local/bin` is ahead of `/usr/bin` on this system's PATH. Do **not**
alias `vim`.

## Alternatives

- `update-alternatives` for vi: Fedora vim-minimal owns `/usr/bin/vi`; a
  PATH shim is simpler and overlay-friendly.
- Removing vim-minimal: may be required by other RPMs; leave it.

## Consequences

Verify `vi --version`, `sudo vi --version`, and `bash -lc 'vi --version'`
all report NVIM.
