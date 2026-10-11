# AvalonOS 0.1.0-8

This file is the source for the v0.1.0-8 GitHub Release notes. It is not the published v0.1.0-7 notes, and it must not be used to edit that release or its tag.

AvalonOS 0.1.0-8 is a post-release Low batch on the released 0.1.0-7 tree. It ships the checker, documentation, and runtime fixes listed below. The v0.1.0-7 tag, tree, and ISO are unchanged.

## What changed

### ISO checkers and verification

- Unowned-byte volume-descriptor exemptions are accepted only at locations derived from xorriso `-report_system_area` (principal LBA 16, partition-offset copies, and the GPT-start views xorriso actually uses, including 64/80). A same-volume set elsewhere, including an appended embedded ISO, is not exempted (P-L16). A split-payload (S1) regression must fail.
- The unowned-byte test requires a PVD at LBA 80 or reports SKIP, counted in the summary (P-L17).
- Mid-file zlib carving in `--gaps` walks the whole gap, not only the first 64 MiB (P-I16).
- `verify-iso.sh` prints `validated volume-descriptor sectors:` and `check-iso-unowned: ok` on success so build/CI logs show them (QA-L1).
- `--quick` may catch a gzip'd key in ESP free space; only the default path and `--full` ESP compare cover ESP free space in general (P-I15).
- A real squashfs (gzip compression) holding an armored key is reported as `[zlib] foreign public-key material`, not `squashfs data`; it still fails (QA-L2).

### Installer and installed-system runtime

- The installer guard parses boot options with shlex (quoted tokens, bare `addrepo=`, `method=`), also reads Anaconda cmdline files, and refuses `repo`, `addrepo`, `noverifyssl`, and `method`. It fails closed if `python3` is missing (P-L10).
- A missing `packages.inc` entry aborts the install instead of warning (P-L3).
- First-boot user creation requires a password of at least 8 characters and refuses a password equal to the username (P-L5).
- The network menu passes the Wi-Fi PSK to `nmcli connection up` via a `passwd-file` under `XDG_RUNTIME_DIR`, not on the command line (AOS-SEC-10). Fedora 44 `nmcli` does not accept `passwd-file` on `device wifi connect` (R8-B1). The 0600 tempfile is removed even if writing it fails (P-L19).
- `net-menu`, `hw-stats`, and `avalonos-btop` exit if `XDG_RUNTIME_DIR` is unset; they no longer fall back to `/tmp` for pidfiles (AOS-SEC-11).
- The session login-shell re-exec no longer interpolates arguments unsafely (AOS-SEC-12).

### Documentation and packaging hygiene

- LSP binaries remain sha256-pinned upstream builds; this tree does not rebuild them from source. Later Mason installs are outside the pinned set (P-L9).
- Vendored Neovim plugins record upstream URLs, full commits, and a vendored-tree sha256 (AOS-SEC-16). The snapshot may still differ from the upstream commit because `.git` was stripped.
- `bluetooth.service` stays enabled, as accepted in ADR 0006b (AOS-SEC-09).
- `.gitleaks.toml` allowlists only anchored `revision = '<40 hex>'` lines in treesitter parser data, not the whole file (AOS-SEC-13).

## Known limitations

- **Alacritty in a virtual machine** (Master Chief, 2026-11-21 2:39pm CT): Alacritty does not launch in a virtual machine. This is a documented known limitation; it has not been investigated or changed in code.
- **Display adapters:** Basic adapters (for example QEMU `-vga std`) can show a no-render-device login message instead of a desktop.
- **NVIDIA / Secure Boot:** The NVIDIA akmod driver is unsigned and will not load with Secure Boot enabled. Turn Secure Boot off before installation if that driver is needed; otherwise the system stays on nouveau.
- **P-L16 residual:** An unused layout-derived volume-descriptor slot could still host a planted validated set. Split payloads in already-owned file extents stay out of the unowned-byte scan (S0-style residual).
- **P-L9 residual:** Language-server binaries are pinned upstream builds, not rebuilt from source; user Mason installs are unpinned.
- **AOS-SEC-09:** `bluetooth.service` is enabled on every install, by design of ADR 0006b.
- **Open Info (unchanged in 0.1.0-8):** P-I1 (sigcheck on an empty rpmdb), P-I2 (`key_trusted` substring match), P-I4 (zizmor cache / persist-credentials), P-I5 (Anaconda 44 repo dirs), P-I6 (stale `overlay.manifest`), P-I7 (SIGKILL mid-create can leave an account), P-I8 (needs rpm ≥ 6), P-I9 (Architect scratch fixture, not in the tree), P-I11 (test vs release nvim-parsers builds differ), P-I14 (scratch make-user harness, not in the tree).
- **P-M5 / P-M6:** unchanged (already decided by Master Chief).
- **Not detectable by the ISO key scan (by design):** encrypted, XOR-ed or custom-encoded data, raw deflate streams without a header, and base32 or ascii85 encodings. The installed system still trusts only the keys the kickstart `%post` pins.

## Build notes

Release ISOs and repos pin only the production key `F0AA82E5FEB779364658A18D96508B1357FDAB48`. QA `-TEST` ISOs and repos pin only the TEST key `F2BC6934FB6501B6114177A7E221DD18AE8EAAE9` and must not be published.
