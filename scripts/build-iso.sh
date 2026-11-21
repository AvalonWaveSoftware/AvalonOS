#!/usr/bin/env bash
# Build AvalonOS-netinst-x86_64.iso: a remaster of the Fedora Everything
# netinst ISO named in upstream.env (ADR 0019). Runs as an ordinary user; no
# root, loop mounts or lorax needed.
#
# Credentials: none. Since 2026-11-14 (decision 9:40 CT) the ISO carries no
# password or hash: root is locked and the daily user is created at first
# boot (avalonos-firstboot-user.service).
# Release vs QA test build (decision 2026-11-14 11:31 CT: "Strip the test-seed
# from release ISOs, keep it for test builds only"):
#   AVALONOS_TEST_BUILD=0 (default; CI release jobs pin it): release ISO. No
#     test-seed code, unit or kickstart line; a repo containing
#     avalonos-testseed is refused and verify-iso.sh fails on any seed artifact.
#   AVALONOS_TEST_BUILD=1: QA test ISO, AvalonOS-netinst-x86_64-TEST.iso, whose
#     repo must contain avalonos-testseed (see docs/iso.md "Test builds").
# Optional: AVALONOS_CACHE (default cache/), AVALONOS_OUT (default out/),
# SOURCE_DATE_EPOCH (default: last commit time).
#
# Steps: fetch + verify upstream, render ks.cfg, build the AvalonOS RPMs and
# their repo (packaging/rpm, scripts/build-rpms.sh), copy only the files the
# signed repo metadata covers (check-signatures.sh --copy-to, P-L8), build
# /avalonos/updates.img (installer repo pinning, P-M1r),
# patch the three GRUB configs (ISO9660 BIOS + EFI and the FAT ESP copy with
# mtools), then xorriso replays the upstream El Torito/MBR/GPT layout with the
# patched ESP appended as GPT partition 2.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/upstream.env"
CACHE="${AVALONOS_CACHE:-$ROOT/cache}"
OUTDIR="${AVALONOS_OUT:-$ROOT/out}"
WORK="$ROOT/build"
UP="$CACHE/$UPSTREAM_ISO"
die() { echo "build-iso: ERROR: $*" >&2; exit 1; }
export AVALONOS_TEST_BUILD="${AVALONOS_TEST_BUILD:-0}"
case "$AVALONOS_TEST_BUILD" in
    0) OUTPUT_ISO_NAME="$OUTPUT_ISO" ;;
    1) OUTPUT_ISO_NAME="${OUTPUT_ISO%.iso}-TEST.iso"
       echo "build-iso: AVALONOS_TEST_BUILD=1: building a QA TEST ISO ($OUTPUT_ISO_NAME); never release it" >&2 ;;
    *) die "AVALONOS_TEST_BUILD must be 0 or 1" ;;
esac
OUT="$OUTDIR/$OUTPUT_ISO_NAME"
# Signing key of this build kind (P-L11): release = production key only,
# test = TEST key only (scripts/avalonos-keys.sh).
# shellcheck source=scripts/avalonos-keys.sh
. "$ROOT/scripts/avalonos-keys.sh"
for t in xorriso mcopy mtype patch tar curl gpg gpgv sha256sum awk dd rpmbuild rpmkeys rpm rpm2cpio createrepo_c cpio gzip python3 zstd; do
    command -v "$t" >/dev/null || die "missing tool: $t (Fedora: dnf install xorriso mtools patch tar curl gnupg2 rpm rpm-build createrepo_c cpio gzip python3 zstd gcc systemd-rpm-macros)"
done

export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null || echo 0)}"

if [ -n "${AVALONOS_SIGNED_REPO:-}" ]; then
    AVALONOS_SIGNED_REPO="$(realpath -e "$AVALONOS_SIGNED_REPO")" || die "AVALONOS_SIGNED_REPO not found"
    case "$AVALONOS_SIGNED_REPO/" in "$WORK"/*) die "AVALONOS_SIGNED_REPO must be outside $WORK (it is wiped)";; esac
fi

# ---- upstream --------------------------------------------------------------
AVALONOS_CACHE="$CACHE" "$ROOT/scripts/fetch-upstream.sh"

rm -rf "$WORK"; mkdir -p "$WORK/payload/avalonos" "$WORK/grub" "$OUTDIR"

# ---- payload ---------------------------------------------------------------
"$ROOT/scripts/render-kickstart.sh" "$WORK/ks.cfg"
"$ROOT/scripts/render-kickstart.sh" --erase-all "$WORK/ks-erase-all.cfg"
# Installer repo pinning (P-M1r): repo files with gpgcheck=1 and pinned keys,
# applied by inst.updates= on every GRUB entry; the kickstart's first %pre
# checks its content against the manifest render-kickstart.sh embedded.
"$ROOT/scripts/build-updates-img.sh" "$WORK/payload/avalonos/updates.img"
# AvalonOS RPM repo: must be signed with the AvalonOS key (the installer
# enforces gpgcheck=1 + repo_gpgcheck=1). Either
#   AVALONOS_SIGNED_REPO=DIR  a repo already signed on the build machine, or
#   AVALONOS_SIGN=1           build here and sign here (build machine only).
# Either way only files covered by the signed metadata reach the ISO (P-L8):
# check-signatures.sh verifies the whole bundle, rejects anything extra, and
# copies just the verified files.
if [ -n "${AVALONOS_SIGNED_REPO:-}" ]; then
    SRCREPO="$AVALONOS_SIGNED_REPO"
else
    SRCREPO="$WORK/signed-repo"
    "$ROOT/scripts/build-rpms.sh" "$WORK/rpmbuild" "$SRCREPO"
    [ "${AVALONOS_SIGN:-0}" = 1 ] \
        || die "the AvalonOS repo must be signed: set AVALONOS_SIGN=1 on the build machine, or AVALONOS_SIGNED_REPO=DIR"
    "$ROOT/scripts/sign-rpms.sh" "$SRCREPO"
fi
"$ROOT/scripts/check-signatures.sh" --copy-to "$WORK/payload/avalonos/repo" "$SRCREPO" "$AV_KEY_FILE" \
    || die "AvalonOS repo signature check failed (nothing copied)"
names="$(find "$WORK/payload/avalonos/repo" -name '*.rpm' -exec rpm -qp --nosignature --qf '%{NAME}\n' {} + 2>/dev/null)"
if [ "$AVALONOS_TEST_BUILD" = 0 ]; then
    ! grep -qx 'avalonos-testseed' <<<"$names" \
        || die "release build: the signed repo contains avalonos-testseed (a QA test-build repo); rebuild with AVALONOS_TEST_BUILD=0"
else
    grep -qx 'avalonos-testseed' <<<"$names" \
        || die "test build: the repo has no avalonos-testseed (build it with AVALONOS_TEST_BUILD=1)"
fi
install -m 0644 "$ROOT/kickstart/packages.inc" "$WORK/payload/avalonos/packages.inc"
install -m 0644 "$AV_KEY_FILE" "$WORK/payload/avalonos/$AV_KEY_NAME"
chmod -R u=rwX,go=rX "$WORK/payload/avalonos"
"$ROOT/scripts/check-avalonos-dir.sh" "$WORK/payload/avalonos" || die "/avalonos payload is not exactly what this tree builds (P-L12)"
# P-L11: nothing on the ISO may carry or trust the other build kind's key.
"$ROOT/scripts/check-key-isolation.sh" "$WORK/payload/avalonos" "$WORK/ks.cfg" "$WORK/ks-erase-all.cfg" \
    || die "key isolation failed: a $( [ "$AVALONOS_TEST_BUILD" = 0 ] && echo release || echo test ) ISO may trust only $AV_KEY_NAME"

# ---- GRUB configs ----------------------------------------------------------
xorriso -osirrox on -indev "$UP" \
    -extract /EFI/BOOT/grub.cfg "$WORK/grub/EFI/BOOT/grub.cfg" \
    -extract /boot/grub2/grub.cfg "$WORK/grub/boot/grub2/grub.cfg" 2>/dev/null
chmod -R u+w "$WORK/grub"
(cd "$WORK/grub" && patch -p1 --no-backup-if-mismatch -s < "$ROOT/boot/grub-efi.patch" \
                 && patch -p1 --no-backup-if-mismatch -s < "$ROOT/boot/grub-bios.patch")
cp "$WORK/grub/EFI/BOOT/grub.cfg" "$WORK/grub/EFI/BOOT/BOOT.conf"

# ---- UEFI ESP (GPT partition 2 / El Torito UEFI image) ---------------------
read -r esp_start esp_size < <(xorriso -indev "$UP" -report_system_area plain 2>/dev/null | \
    awk '$1=="GPT" && $2=="start" && $6=="2" {print $7, $8}')
esp_type="$(xorriso -indev "$UP" -report_system_area plain 2>/dev/null | awk '$1=="GPT" && $2=="type" && $5=="2" {print $6}')"
[ -n "${esp_start:-}" ] && [ -n "$esp_type" ] || die "could not find the ESP partition in $UP"
dd if="$UP" of="$WORK/efiboot.img" bs=512 skip="$esp_start" count="$esp_size" status=none
for f in grub.cfg BOOT.conf; do
    MTOOLS_SKIP_CHECK=1 mcopy -o -i "$WORK/efiboot.img" "$WORK/grub/EFI/BOOT/grub.cfg" "::/EFI/BOOT/$f"
    cmp -s <(MTOOLS_SKIP_CHECK=1 mtype -i "$WORK/efiboot.img" "::/EFI/BOOT/$f") "$WORK/grub/EFI/BOOT/grub.cfg" \
        || die "ESP $f does not match after mcopy"
done

# ---- ISO -------------------------------------------------------------------
rm -f "$OUT" "$OUT.sha256"
# Reproducibility (QA 2026-11-14, verified bit-identical): clamp the mtimes of
# every build-added file before xorriso records them.
find "$WORK" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
if ! xorriso -indev "$UP" -outdev "$OUT" \
    -boot_image any replay \
    -append_partition 2 "$esp_type" "$WORK/efiboot.img" \
    -boot_image any efi_path=--interval:appended_partition_2:all:: \
    -map "$WORK/ks.cfg" /ks.cfg \
    -map "$WORK/ks-erase-all.cfg" /ks-erase-all.cfg \
    -map "$WORK/payload/avalonos" /avalonos \
    -map "$WORK/grub/EFI/BOOT/grub.cfg" /EFI/BOOT/grub.cfg \
    -map "$WORK/grub/EFI/BOOT/BOOT.conf" /EFI/BOOT/BOOT.conf \
    -map "$WORK/grub/boot/grub2/grub.cfg" /boot/grub2/grub.cfg \
    -chown_r 0 /ks.cfg /ks-erase-all.cfg /avalonos /EFI/BOOT/grub.cfg /EFI/BOOT/BOOT.conf /boot/grub2/grub.cfg -- \
    -chgrp_r 0 /ks.cfg /ks-erase-all.cfg /avalonos /EFI/BOOT/grub.cfg /EFI/BOOT/BOOT.conf /boot/grub2/grub.cfg -- \
    -chmod 0600 /ks.cfg /ks-erase-all.cfg -- \
    -chmod 0755 /avalonos -- \
    -chmod 0644 /EFI/BOOT/grub.cfg /EFI/BOOT/BOOT.conf /boot/grub2/grub.cfg -- \
    -commit_eject all > "$WORK/xorriso.log" 2>&1; then
    cat "$WORK/xorriso.log" >&2; die "xorriso failed"
fi
# Fedora's volume id (lowercase, dashes) triggers a harmless ISO 9660 naming warning.
grep -E "SORRY|FAILURE|WARNING|image produced" "$WORK/xorriso.log" | grep -v "volid text does not comply" || true
grep -qE "SORRY|FAILURE" "$WORK/xorriso.log" && die "xorriso reported errors (see $WORK/xorriso.log)"
[ -s "$OUT" ] || die "xorriso did not produce $OUT"
(cd "$OUTDIR" && sha256sum "$OUTPUT_ISO_NAME" > "$OUTPUT_ISO_NAME.sha256")
# --full: also every upstream file byte-identical to upstream (P-L11 review:
# the key-isolation guarantee must not depend on an optional flag).
"$ROOT/scripts/verify-iso.sh" --full "$OUT"
echo "build-iso: done: $OUT"
cat "$OUT.sha256"
