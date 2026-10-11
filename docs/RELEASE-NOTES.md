# AvalonOS 0.1.0-9

This file is the source for the v0.1.0-9 GitHub Release notes. It is not the published v0.1.0-7 or v0.1.0-8 notes, and it must not be used to edit those releases or their tags.

AvalonOS 0.1.0-9 ships the post-0.1.0-8 fix batch listed below. The v0.1.0-8 tag, tree (`460b644`, `a6aec004`), and ISO are unchanged. nvim-lsp and nvim-parsers stay 0.1.0-2 (P-I17).

## What changed

- **AOS-SEC-09:** `bluetooth.service` is disabled by default. `bluez` and
  `blueman` stay installed. ADR 0006b is revised. Users who want Bluetooth
  can enable the unit after install.
- **P-L16 / R9-B1:** extra volume-descriptor sets at GPT-start-as-2048-LBA
  alias slots (including unused 64/80) are exempted when they match the
  corresponding offset view (64 vs 16, 80 vs 32). The PVD volume-space size
  field (bytes 80-87) may differ when the candidate size is still a valid
  PVD volume-space (at least 17 sectors and no larger than the reference);
  a zero or tiny volume-space, or a planted nonidentical validated set at
  those slots, is not exempted. Legitimate partition-offset copies may
  differ and remain exempted when they validate. S0-style split payloads
  in already-owned file extents remain outside the unowned-byte scan by
  design.
- **P-I21:** partition-offset views may differ and still validate.
- **P-I22:** the unowned-byte U7 live boot-replay may skip only when the
  xorriso version is successfully parsed and is older than 1.5.8. On
  1.5.8 or newer, or when the version is unparseable or unknown, a missing
  PVD at LBA 80 or a failed replay is FAIL, not skip.
- **P-I23:** `check-iso-unowned.sh` and `verify-iso.sh` wrap xorriso in
  `timeout` (60 seconds for report/find-style calls in the unowned-byte
  checker; 30 seconds for `verify-iso` report/extract of small trees; 10
  minutes for a whole-image extract). A hang or timeout is FAIL. A
  volume-space-size 0 alias at LBA 64 is covered by a regression that must
  not hang (30-second backstop).
- **P-L20 / P-I19 / QA-L2 / QA-L3 / P-I24:** the network menu matches
  saved Wi-Fi profiles by SSID, using `nmcli -t -f UUID,TYPE connection
  show` and `nmcli -g 802-11-wireless.ssid connection show uuid` per
  UUID — the list-mode setting field `802-11-wireless.ssid` is rejected
  by Fedora 44 nmcli 1.56.1 (QA-L2 / P-I20). It checks the `connection
  add` return code, always adds a fresh profile on the password path, and
  forgets iwd's stored PSK for that SSID (`iwctl known-networks <ssid>
  forget`) before activation so a wrong passwd-file cannot authenticate
  against `/var/lib/iwd` (QA-L3; this was already a limitation in
  0.1.0-8, not a regression introduced there). Menu-created profiles are
  recorded in a 0600 UUID registry under `$XDG_STATE_HOME/avalonos` (P-I24);
  a user profile whose name merely starts with `avalonos-` is not deleted.
  A profile created on a failed activation is deleted. PSK validation
  (reject CR/LF/NUL; 8–63 printable ASCII or 64 hex) and stale
  `avalonos-nm-*` cleanup under `$XDG_RUNTIME_DIR` at start-up are
  unchanged. Secrets never appear on argv; the 0600 tempfile form and
  `nmcli connection up … passwd-file` (Fedora 44) are unchanged.
  `wifi-sec.key-mgmt` stays `wpa-psk` (WPA3-only/SAE, enterprise, and WEP
  still fail from the menu). Tempfile cleanup still cannot survive SIGKILL;
  start-up cleanup is the mitigation.
- **IPsec VPN:** the top-bar network menu can configure, connect, and
  disconnect a Libreswan IPsec VPN using the signed Fedora packages
  `NetworkManager-libreswan` and `libreswan`. Authentication types are
  pre-shared key, certificate (NSS certificate nickname already present
  in the NSS database; the menu never takes a private key), and IKEv2
  EAP (username and password). PSK and EAP secrets use the same 0600
  passwd-file under `$XDG_RUNTIME_DIR` and `nmcli connection up …
  passwd-file`; secrets are never placed on argv or logged. Menu-created
  VPN profiles use the same UUID registry as Wi-Fi (P-I24).
- **First-boot Obsidian (ADR 0021):** the ISO ships the Fedora `flatpak`
  RPM and stays RPM-signed only. When a default route is up, first boot
  adds the Flathub remote and installs `md.obsidian.Obsidian` system-wide.
  The unit is not ordered before greetd, so an offline first boot still
  reaches login; the service retries until the install succeeds. An
  offline install gets Obsidian later.
- **P-L18:** the shipped installer guard no longer honours
  `AVALONOS_INSTGUARD_ROOT`. A missing or unreadable `/proc/cmdline`
  fails closed.
- **Alacritty on VMs (r5):** Super+Return, `avalonos-btop`, net-menu
  nmtui, and the launcher's Terminal=true wrapper start Alacritty
  through `avalonos-alacritty`. When `gpu-select` wrote the exact
  `MESA_LOADER_DRIVER_OVERRIDE=kms_swrast` line in `/run/avalonos/gpu.env`,
  the wrapper sets `LIBGL_ALWAYS_SOFTWARE=1` for that Alacritty process and what it launches, and
  never passes the Mesa loader override to the client (r4 QA B-1:
  `kms_swrast` SIGSEGVs Wayland clients on virtio-gpu 2D). The override
  remains on niri only (niri.service EnvironmentFile; niri config
  unsets it for spawned processes). Hardware GL and virtio-gpu 3D
  (virgl) get neither the override nor `LIBGL_ALWAYS_SOFTWARE`. Journal
  logging (identifier `avalonos-alacritty`) is best-effort: if
  systemd-cat or journald is down, Alacritty still starts. The rofi
  fallback prefers `/usr/bin/avalonos-alacritty`, then raw alacritty or
  xterm. Live confirmation of virtio-gpu 2D / `avalonos.gpu=sw` is
  pending QA re-test. Display-only adapters (QEMU `-vga std` / QXL, no
  render node) still cannot start niri; use a virtio GPU (2D or 3D).
- **IPsec on a fresh install (r5 / r6 / H-1 / P-L29):** `ipsec.service`
  (Fedora libreswan / pluto) is enabled on a fresh install via
  `80-avalonos.preset` and kickstart `%post`. The network RPM `%post`
  uses `%systemd_post ipsec.service` (preset on first install only),
  not `systemctl enable`. The r5 tmpfiles.d wants link is gone so an
  admin `systemctl disable` survives reboot. NetworkManager-libreswan
  does not start pluto itself. Menu-created road-warrior profiles set
  `leftsubnet=0.0.0.0/0` with `leftmodecfgclient=yes` and
  `narrowing=yes` so TSi can cover a pool VIP (r5 QA R5-M3); certificate
  profiles also set `rightca=%same` so a CERTREQ is sent (R5-V3a).
  Live confirmation that the Child SA comes up with TSi equal to the
  assigned VIP, and that CERTREQ works against a default strongSwan
  responder, is pending QA re-test.
- **P-I18 / P-L22:** `.gitleaks.toml` allowlist sets `regexTarget =
  "line"` so the treesitter `revision = '<40 hex>'` regex matches the
  line, not the secret value. The public Fedora fingerprint is allowed
  only as the exact fully anchored line forms present in the tree
  (`FEDORA_KEY_FPR=…` in `upstream.env`, the quoted KEYS entry in
  `build-updates-img.sh`, and the PINNED-FINGERPRINTS line). A planted
  token on the same line is not hidden.
- **P-L9:** accepted; no change (pinned LSP binaries, unpinned Mason
  installs).
- **P-I17:** no change. 0.1.0-8 already shipped the signed nvim 0.1.0-2
  RPMs, byte-identical to v0.1.0-7; no residual requiring a rebuild.

## Known limitations

- **Alacritty on VMs:** Live re-test of virtio-gpu 2D and `avalonos.gpu=sw` is pending QA (r6 uses `LIBGL_ALWAYS_SOFTWARE=1` for that Alacritty process and what it launches; the `kms_swrast` override is for niri, not Wayland or X11 clients). niri starts xwayland-satellite through `avalonos-xwayland-satellite` with the same client GPU policy. A leftover `/run/systemd/journal/stdout` socket after journald stops is probed (connect, not existence) before systemd-cat is used. A virtio GPU (2D or 3D) is required for the desktop; display-only adapters (QEMU `-vga std` / QXL, no render node) still cannot start niri.
- **IPsec narrowing (P-I38):** `narrowing=yes` lets the gateway shrink traffic selectors. It is not a full-tunnel or kill-switch guarantee.
- **IPsec pluto (P-I36):** `ipsec.service` starts pluto as root when enabled. Inbound UDP 500/4500 stays firewalled closed. An on-demand start was not implemented (it would risk leaving pluto down on a fresh install).
- **Display adapters:** Basic adapters (for example QEMU `-vga std`) can show a no-render-device login message instead of a desktop.
- **NVIDIA / Secure Boot:** The NVIDIA akmod driver is unsigned and will not load with Secure Boot enabled. Turn Secure Boot off before installation if that driver is needed; otherwise the system stays on nouveau.
- **P-L16 residual (S0):** split payloads in already-owned file extents stay out of the unowned-byte scan by design. Unused 64/80 alias slots no longer accept a planted nonidentical validated set; the volume-space size field may differ from the principal copy (R9-B1).
- **P-L9 residual:** Language-server binaries are pinned upstream builds, not rebuilt from source; user Mason installs are unpinned (accepted).
- **P-I19 residual:** `wifi-sec.key-mgmt` stays `wpa-psk` (WPA3-only/SAE, enterprise, and WEP fail from the menu). Tempfile cleanup cannot survive SIGKILL; start-up cleanup of stale `avalonos-nm-*` files is the mitigation. Wi-Fi WPA3-only/SAE is still not offered from the menu.
- **IKEv2 EAP stack:** the menu offers IKEv2 EAP (username and password) through NetworkManager-libreswan's documented `leftusername` / `leftxauthusername` and `xauthpassword` keys with `ikev2=insist`. Libreswan itself currently implements EAP-TLS, not EAP-MSCHAPv2; a gateway that requires EAP-MSCHAPv2 (or another password EAP method) may not complete. This is a limitation of the signed Fedora stack, not a missing menu field. Certificate profiles need the nickname of a certificate already installed in the NSS database.
- **Obsidian when offline:** if first boot has no network, Obsidian is not installed until a default route appears and the first-boot unit retries successfully.
- **Open Info (unchanged):** P-I1 (sigcheck on an empty rpmdb), P-I2 (`key_trusted` substring match), P-I4 (zizmor cache / persist-credentials), P-I5 (Anaconda 44 repo dirs), P-I6 (stale `overlay.manifest`), P-I7 (SIGKILL mid-create can leave an account), P-I8 (needs rpm ≥ 6), P-I9 (Architect scratch fixture, not in the tree), P-I11 (test vs release nvim-parsers builds differ), P-I14 (scratch make-user harness, not in the tree).
- **P-M5 / P-M6:** unchanged (already decided by Master Chief).
- **Not detectable by the ISO key scan (by design):** encrypted, XOR-ed or custom-encoded data, raw deflate streams without a header, and base32 or ascii85 encodings. The installed system still trusts only the keys the kickstart `%post` pins.

## Build notes

Release ISOs and repos pin only the production key `F0AA82E5FEB779364658A18D96508B1357FDAB48`. QA `-TEST` ISOs and repos pin only the TEST key `F2BC6934FB6501B6114177A7E221DD18AE8EAAE9` and must not be published.

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
