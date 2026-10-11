# ISO — Fedora Everything netinst remaster

End-user USB and first-login steps: **[How to Install](../How-to-Install.md)**.

AvalonOS is a **remastered Fedora 44 Everything netinst**. Anaconda fetches
Fedora + RPM Fusion packages over HTTPS metalinks from repos pinned by
`/avalonos/updates.img` (`gpgcheck=1`, pinned keys; P-M1r); AvalonOS's own files are
**RPMs in a local repo on the ISO** (`/avalonos/repo`), installed in `%post`.
The image is hybrid: **BIOS (El Torito `images/eltorito.img` = GRUB2, no
isolinux)** and **UEFI (GPT ESP)**.

## Build

```bash
scripts/build-iso.sh
```

Runs unprivileged. No credential is needed or accepted: root is locked
(`rootpw --lock`) and the daily user is created on first boot by
`avalonos-make-user` (decision 2026-11-14). Output:
`out/AvalonOS-netinst-x86_64.iso` and `.sha256`.

Host tools (Fedora): `dnf install xorriso mtools gnupg2 curl patch tar
rpm rpm-build createrepo_c cpio gzip python3 zstd gcc systemd-rpm-macros
desktop-file-utils rpmlint`.

`AVALONOS_TEST_BUILD` (default `0`) selects a release build. `1` builds a QA
test ISO instead; see "Test builds (QA only)" below. CI release jobs pin it
to `0`.

Pipeline (`scripts/build-iso.sh`):

1. `scripts/fetch-upstream.sh`: download + verify the upstream ISO
   (`gpgv` against `keys/fedora-44.gpg`, sha256 pinned in `upstream.env`).
2. `scripts/render-kickstart.sh` twice: `/ks.cfg` (default, interactive disk
   picker) and `--erase-all` → `/ks-erase-all.cfg`. The renderer refuses to
   write a credential/hash, and refuses `zerombr`/`clearpart --all` in `/ks.cfg`.
   Both start with the installer guard `%pre` (P-M1r, below), which carries
   the sha256 manifest of `updates.img`.
3. `scripts/build-updates-img.sh` → `/avalonos/updates.img` (reproducible
   gzip newc cpio: `installer/updates/` + the pinned Fedora 44 and RPM
   Fusion 2020 keys, fingerprints checked at build time).
4. `scripts/build-rpms.sh`: Source0 tarball (sorted, mtimes =
   `SOURCE_DATE_EPOCH`), `rpmbuild` of `packaging/rpm/avalonos.spec`,
   `avalonos-nvim-parsers.spec` and `avalonos-nvim-lsp.spec`, `createrepo_c`.
   The signed repo is then verified as a whole and only its verified files
   are copied to `build/payload/avalonos/repo`
   (`check-signatures.sh --copy-to`, P-L8).
5. GRUB: apply `boot/grub-efi.patch` / `boot/grub-bios.patch` (every entry
   gets `inst.updates=hd:LABEL=Fedora-E-dvd-x86_64-44:/avalonos/updates.img`), copy EFI
   `grub.cfg` to `BOOT.conf`, `mcopy` both into the FAT ESP.
6. Clamp mtimes of all build-added files to `SOURCE_DATE_EPOCH`, then
   `xorriso ... -boot_image any replay` (root:root, kickstarts 0600).
7. `scripts/verify-iso.sh` checks boot layout, all GRUB copies (every
   `linux` line has `inst.updates=`), both kickstarts (guard first, manifest
   == `updates.img` content), the installer repo files, the RPM repo (whole
   bundle, P-L8) and, for a release ISO, that no test-seed artifact is
   anywhere on it.

### RPM signing (decision 2026-11-14 10:30 CT)

Every AvalonOS RPM and the repo metadata are signed with the **AvalonOS RPM
Signing Key**, fingerprint `F0AA82E5FEB779364658A18D96508B1357FDAB48`. The
private key exists only on the build machine (`fedora`,
`/home/admin/avalonos-signing/gnupg`); the repo carries only the public key,
`keys/RPM-GPG-KEY-avalonos`, pinned in `keys/PINNED-FINGERPRINTS` and in the
kickstart `%post` PIN table.

**Separate TEST key (P-L11, decision 2026-11-14 16:15 CT: "Yes, use a
separate signing key for test builds.").** QA test builds
(`AVALONOS_TEST_BUILD=1`) are signed with the **AvalonOS TEST Build Signing
Key** instead (fingerprint in `keys/TEST-KEY-FINGERPRINT`, public key
`keys/RPM-GPG-KEY-avalonos-test`; private key and its own passphrase file in
`/home/admin/avalonos-test-signing/` on the build machine, own `GNUPGHOME`).
`scripts/avalonos-keys.sh` picks the key from `AVALONOS_TEST_BUILD`, and every
pin follows it: the RPM's `/etc/pki/rpm-gpg/` key, the kickstart PIN table and
`gpgkey=`, the `/avalonos/` key on the ISO and `check-signatures.sh`. A
release trusts only the production key, a test build only the TEST key.
`sign-rpms.sh` refuses the other kind's fingerprint. `scripts/check-key-isolation.sh`
fails on the other kind's key file, key material (binary, armored or
compressed, under any name), fingerprint, key ID or name in any file, any RPM
not signed by this kind's key alone, and any detached signature that does not
verify against this kind's key alone; `build-iso.sh` runs it on the payload and
`verify-iso.sh` on the whole ISO, ESP and `updates.img` (negative tests:
`testing/offline/key-isolation-test.sh`).

**Hidden keys (P-L12, decision 2026-11-14 17:43 CT: "Fix it before
release").** The check also finds the other kind's key when it is hidden on
purpose: base64 without armor (any alignment, wrapped, quoted, URL-safe,
UTF-16), hex dumps, the fingerprint or key ID with any spacing or case,
OpenPGP compressed messages, LZMA-alone/xz/gzip/bzip2/zstd (also
concatenated or embedded mid-file), tar, cpio (initramfs-style), zip (also
appended), ar/deb, and inside RPM scriptlets, triggers, file triggers, names
and payloads. Formats it cannot unpack (squashfs, erofs, ISO9660, FAT, 7z,
lz4, ...) fail unless the file is byte-identical to a file of the pinned
upstream ISO (`upstream-netinst.sha256`). `scripts/check-avalonos-dir.sh`
allows exactly `packages.inc`, the build kind's key, `updates.img` and the
signed `repo/` under `/avalonos`, each byte-identical to what the tree builds;
`verify-iso.sh` also scans the raw ISO and ESP bytes and requires both
kickstarts to equal `render-kickstart.sh` output. The default path (and
`--full`; `--quick` turns this compare off) compares every
other file, directory and link, the ESP, the GRUB configs (upstream + our
patches) and `eltorito.img` (except the bytes xorriso rewrites) with
upstream. `--quick` may catch a gzip of the binary key in ESP free space;
only the default path (and `--full`) ESP compare covers ESP free space in
general (P-I15: a gzip of the armored TEST key passed `--quick` and failed
default/`--full`). After the Codex coverage review (2026-11-14) the check also
assembles OpenPGP partial-length packets, decodes hex runs and zlib streams,
carves every ZIP local entry (concatenated zips), accepts any LZMA dictionary,
reads V7 tar, treats a speculative stream that decodes completely as real
(errors inside it then fail), fails closed on unreadable directories,
encrypted zip entries, embedded 7z/rar/lzop/LUKS data, encoded runs over
256 MiB and a global 32 GiB / 1M-member budget, scans every RPM header tag
except the prose ones, and checks path names and link targets.
`scripts/check-iso-unowned.sh` gives every ISO byte outside any file
(system area, directory records, slack, appended data) the full decoding
scan, and on the default path (and `--full`) requires the ESP to equal
upstream's ESP plus our `grub.cfg` except FAT timestamps (tests:
`testing/offline/iso-unowned-test.sh`). ISO9660 volume-descriptor sectors
are exempted from the unowned-bytes ISO9660-magic check only when they are
members of a structurally validated descriptor set (type, CD001, version 1,
terminated, starting with a PVD) at a location derived from xorriso's
`-report_system_area` (principal LBA 16, partition-offset copies, and the
GPT-start views xorriso actually uses, including 64/80). A same-volume set
elsewhere, including an appended embedded ISO, is not exempted (P-L16). A
`CD001` string anywhere else still fails (R7-B1). Mid-file squashfs, lz4 and erofs magics fail in whole files as well as in gaps; mid-file zlib streams are
carved in `--gaps` (the whole gap, in 64 MiB windows; P-I16) and in files up to 64 MiB (P-L13). A real squashfs (gzip compression) holding an armored key is reported as `[zlib] foreign public-key material` rather than `squashfs data`, because the payload is reached by mid-file zlib carving; it still fails (QA-L2). Nesting that still
has decodable structure, armor or carve magic when the depth limit (6) is
reached fails closed (P-L15).
Not detectable by design: encrypted, XOR-ed or custom-encoded data, raw
deflate streams without a header, and base32 or ascii85 encodings; the
installed system still trusts only the
keys the kickstart `%post` pins (exact set).

- `scripts/sign-rpms.sh DIR` (build machine only): `rpmsign --addsign` every
  RPM, `createrepo_c`, then `gpg --detach-sign --armor` →
  `repodata/repomd.xml.asc`. `--rpms` / `--repomd` run one half.
- `scripts/check-signatures.sh DIR`: `gpgv` of `repomd.xml.asc`, then the
  sha256 of every metadata file against `repomd.xml` and of every package
  against `primary.xml`, `rpm -K` of every RPM in a throwaway rpmdb that
  holds only the pinned public key, and the bundle's file set must be exactly
  what the signed metadata lists (anything extra or missing, a symlink,
  special file or extra directory fails; P-L8). It first snapshots the key
  and every file (regular files only, no symlinks followed) into a private
  directory and checks only that snapshot; metadata checksums are checked
  before anything is decompressed or parsed (size-limited, no DTD/entities,
  unique and plain relative hrefs). `--copy-to DEST` creates DEST (it must
  not exist) and copies only the verified snapshot bytes, so a file changed
  during or after the check never reaches the ISO. gpgv must report a
  VALIDSIG by the pinned key and no bad/expired/revoked signature.
  `build-iso.sh` and `verify-iso.sh` both run it.
- Signing is manual, on the build machine only; the key has **no expiry**
  and only Master Chief has access to the build machine (decisions
  2026-11-14 11:30 CT). Key backup and passphrase: Master Chief's easystore
  drive, `Secure/AvalonOS-RPM-Signing-Key` (his orders, 11:16 and 11:20 CT).
- `build-iso.sh` refuses an unsigned repo. On the build machine:
  `AVALONOS_SIGN=1 scripts/build-iso.sh`. Elsewhere (including CI, which has
  no key): `AVALONOS_SIGNED_REPO=DIR scripts/build-iso.sh` with a repo signed
  on the build machine. The release workflow downloads it from the tag's
  release asset `avalonos-signed-repo.tar`.
- The installer installs `avalonos` from the ISO repo with `gpgcheck=1`,
  `repo_gpgcheck=1` and `gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-avalonos`
  (copied from `/avalonos/RPM-GPG-KEY-avalonos` and checked against the pin).

## Boot menu (UEFI and BIOS, all three GRUB copies)

| # | Entry | Kickstart |
|---|---|---|
| 0 (default) | Install AvalonOS (Fedora 44) - choose disk | `/ks.cfg` |
| 1 | Test this media & install AvalonOS - choose disk | `/ks.cfg` |
| 2 | AUTOMATIC INSTALL - ERASES ALL DISKS (VMs/testing only) | `/ks-erase-all.cfg` |
| sub | basic graphics mode - choose disk | `/ks.cfg` |

`set timeout=-1`: the menu waits; nothing boots on its own. `/ks.cfg` runs
the `%pre` disk picker on tty6: nothing is erased until a disk is chosen and
its name typed, plus `ERASE` for removable/USB disks and for any disk with a
partition, a partition table or any signature (NTFS/BitLocker, FAT/exFAT,
HFS+/APFS, swap, LUKS, LVM, RAID/ZFS, Linux filesystems, or anything
`wipefs` sees; P-L2). Only `/ks-erase-all.cfg` contains `zerombr` /
`clearpart --all`.
`avalonos.disk=vda` on an interactive entry only **preselects** a disk: the
name (and `ERASE` when required) must still be typed (P-L1). Removable/USB
disks are refused there unless `avalonos.disk.allow-removable=1` is also
given. Fully unattended VM installs (QA) use the ERASES ALL DISKS entry.

## What is on the ISO

| Path on ISO | What |
|---|---|
| `/ks.cfg` | default kickstart (disk picker) |
| `/ks-erase-all.cfg` | erase-all kickstart (menu entry 2 only) |
| `/avalonos/repo/` | AvalonOS RPMs + repodata |
| `/avalonos/packages.inc` | package list (also inlined in the ks) |
| `/avalonos/RPM-GPG-KEY-avalonos` | public key for the ISO repo (pinned) |
| `/avalonos/updates.img` | installer repo files (`gpgcheck=1`, pinned keys) + those keys; applied by `inst.updates=` (P-M1r) |

Everything else is the unmodified upstream file.

## Installer behaviour

- `cmdline` Anaconda; Fedora + updates + RPM Fusion over **HTTPS metalink**
- **Install-time signature check (P-M1r; decision 2026-11-14 11:30 CT).**
  `inst.updates=` on every GRUB entry (UEFI and BIOS) makes dracut lay
  `/avalonos/updates.img` over the installer root before Anaconda starts. It
  replaces the installer's repo files: `fedora`, `updates` and the four RPM
  Fusion repos with `gpgcheck=1`, `sslverify=1` and `gpgkey=` pinned to
  key files inside the image (`/etc/pki/avalonos-installer/`); the stock
  `updates-testing` and `cisco-openh264` repos are blanked. The kickstart
  names these repos (`repo --name=…`) and has no `url`, so Anaconda uses
  them as system repos and keeps their `gpgcheck=1` (it only forces
  gpgcheck off for kickstart `url`/`--baseurl` repos). libdnf5 checks every
  package signature before the RPM transaction starts: an unsigned,
  wrong-key or tampered package aborts the install ("Signature verification
  failed.") before any scriptlet runs. `repo_gpgcheck` stays 0 for these
  repos because Fedora and RPM Fusion publish no `repomd.xml.asc`; metadata
  integrity comes from the HTTPS metalink. The first `%pre`
  (`kickstart/avalonos-instguard.sh`) stops the install unless the
  `updates.img` content matches the sha256 manifest in the kickstart, no
  other repo files or dnf overrides exist, and neither the kernel command
  line (`inst.repo=`, `inst.addrepo=`, `noverifyssl`) nor the kickstart
  adds a repo source. The `%post` verifier below stays as a second layer.
- `%post` pins the Fedora 44, RPM Fusion and AvalonOS signing keys
  (`keys/PINNED-FINGERPRINTS`; the imported set must equal the pins) and
  fails unless every installed package's header signature **verifies
  cryptographically** against a keyring built only from those key files
  (`kickstart/avalonos-sigcheck.py`, embedded by the renderer; needs
  `python3-rpm`), and every enabled repo has `gpgcheck=1` over HTTPS (P-M1).
  Second layer since P-M1r: the Anaconda package set is already checked
  before its scriptlets; every later dnf run (ISO repo, NVIDIA) checks
  before installing too
- `dnf install avalonos` from the ISO repo with `gpgcheck=1` and
  `repo_gpgcheck=1` (no exception for the local repo)
- `firewall --remove-service=ssh`; `openssh-server` excluded (clients kept)
- `hw-setup` (avalonos-hw): NVIDIA akmod only with a `10de` GPU, **fails
  closed** (nouveau stays unless `nvidia.ko` built for every kernel); log
  `/var/log/avalonos-hw.log`
- **Secure Boot on NVIDIA machines: turn it off** (decision 2026-11-14 10:30
  CT; steps in How-to-Install.md §3). The akmod module is unsigned (or signed
  by a local akmods key the firmware does not trust) and a Secure Boot
  kernel will not load it. `hw-setup` reads the EFI `SecureBoot` variable
  (or `mokutil --sb-state`). On UEFI, a state it cannot read (variable
  missing, unreadable or odd, and no clear `mokutil` answer) counts as
  unknown and fails closed like Secure Boot on (P-L7); legacy BIOS has no
  Secure Boot. With Secure Boot on, nouveau is blacklisted only
  if every kernel's `nvidia.ko` is signed by a key in the kernel keyrings
  (`/proc/keys`); otherwise the NVIDIA step fails closed (packages removed,
  nouveau kept, reason in `/var/log/avalonos-hw.log` and the journal, tag
  `avalonos-hw`). AvalonOS does no MOK enrollment (P-M4).
- first boot: `avalonos-firstboot-user.service` creates the user on tty1,
  then greetd starts (`ConditionPathExists=/var/lib/avalonos/user-ready`).
  Ctrl-C, Ctrl-D, Ctrl-\ and Ctrl-Z are ignored on that screen (and during
  the first `dnf upgrade`); if the program still fails, the unit restarts
  (`Restart=on-failure`, 2 s, at most 10 starts in 10 min). The marker is
  written only after the user is fully made; a half-made user is removed.
- hostname: the kickstart sets `avalonos` (the greeter showed "fedora")
- `avalonos-gpu-select.service` (root, each boot) writes
  `/run/avalonos/gpu.env`; niri gets `MESA_LOADER_DRIVER_OVERRIDE=kms_swrast`
  only when the GPU has no hardware GL. The 3D path (a GPU with a render
  node) is unchanged.
- Display-only adapters (QA 2026-11-14 HIGH, QEMU `-vga std`): bochs-drm,
  cirrus, simpledrm, hyperv_drm and BMC VGA (ast, mgag200) have a KMS card but
  no render node. Mesa's EGL lists only render-capable DRM devices (a
  display-only PCI device gets no driver, only `EGL_MESA_device_software`), and
  niri 26.04 skips software EGL devices, so it gets no renderer or allocator
  for the card and runs with no output: a blank screen. kms_swrast does not
  change this. `gpu-select` therefore:
  - if another GPU has a render node and KMS outputs, writes
    `/run/avalonos/niri-gpu.kdl` with `debug { render-drm-device ... }` (read
    by `include optional=true` at the end of `/etc/niri/config.kdl`, niri
    >= 26.04), so niri renders there;
  - otherwise writes `AVALONOS_DISPLAY_ONLY=1`, and `avalonos-session` (if
    there is still no `/dev/dri/renderD*` at login) does not start niri but
    shows what to do on the console and returns to the greeter.
  A full desktop on a lone display-only adapter would need a niri that
  renders with pixman (not in Fedora's niri 26.04).

## Known limitations

- **Alacritty in a virtual machine** (Master Chief, 2026-11-21 2:39pm CT): Alacritty does not launch in a virtual machine. This is a documented known limitation; it has not been investigated or changed in code.
- Display-only adapters and NVIDIA Secure Boot are described under Installer behaviour above, and in How-to-Install.md.

## Test builds (QA only)

Decision 2026-11-14 11:31 CT: "Strip the test-seed from release ISOs, keep it
for test builds only". A **release** ISO (the default, and every CI release
job: `AVALONOS_TEST_BUILD: "0"`) has no seed code, unit or kickstart line:
`avalonos-make-user` cannot be seeded, the repo must not contain
`avalonos-testseed` (`build-iso.sh` refuses it), and `verify-iso.sh` fails a
release ISO with any seed artifact (the RPM, seed strings in the kickstarts,
GRUB configs or `updates.img`, or seed code in any RPM payload; only docs and
`tailwhip` may mention it).

Build a QA test ISO:

1. Build and sign a test repo on the build machine:
   `AVALONOS_TEST_BUILD=1 AVALONOS_SIGN=1 scripts/build-iso.sh`
   (or `AVALONOS_TEST_BUILD=1 scripts/build-rpms.sh TOP REPO`, sign `REPO`
   with `scripts/sign-rpms.sh`, then
   `AVALONOS_TEST_BUILD=1 AVALONOS_SIGNED_REPO=REPO scripts/build-iso.sh`).
   It is signed with the TEST key (P-L11): `sign-rpms.sh` with
   `AVALONOS_TEST_BUILD=1` uses `~/avalonos-test-signing/`, and the test
   RPMs, kickstarts and ISO pin and ship only `RPM-GPG-KEY-avalonos-test`.
   This adds the `avalonos-testseed` RPM (`testing/testseed/`, `rpmbuild
   --with testseed`) and a kickstart step that installs it and carries
   `avalonos.testseed=1` to the installed system.
2. Output: `out/AvalonOS-netinst-x86_64-TEST.iso`. Never publish it, and
   never upload a test repo as `avalonos-signed-repo.tar`.
3. Check it with `AVALONOS_TEST_BUILD=1 scripts/verify-iso.sh out/AvalonOS-netinst-x86_64-TEST.iso`
   (the default is the full check; pass `--quick` only for the weaker path —
   `--quick` may catch a gzip'd key in ESP free space, but only default/`--full`
   covers ESP free space).
4. Seed a user: `tailwhip --user NAME` (installed with AvalonOS, or
   `scripts/tailwhip`) writes `avalonos-seed.conf` (yescrypt hash, never
   plaintext). Put it on a disk labelled `AVTESTSEED` and add
   `avalonos.testseed=1` to the installer's kernel command line: first boot
   creates that user without the TUI. Without both the flag and the disk
   nothing is seeded.
