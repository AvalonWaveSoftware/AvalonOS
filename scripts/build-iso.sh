#!/usr/bin/env bash
# Build AvalonOS-netinst-x86_64.iso: a remaster of the Fedora Everything
# netinst ISO named in upstream.env (ADR 0019). Runs as an ordinary user; no
# root, loop mounts or lorax needed.
#
# Admin credentials (one of these is required; nothing secret lives in git):
#   AVALONOS_ADMIN_PW_HASH   crypt(3) hash for the admin user, e.g. from
#                            `mkpasswd -m yescrypt`. CI uses the repo secret.
#   kickstart/AvalonOS.local.ks
#                            untracked file written by scripts/tailwhip. Its
#                            user/rootpw lines are reused with the current
#                            template and package list.
#   AVALONOS_INSECURE_DEFAULT_PASSWORD=1
#                            INSECURE opt-in: admin/changeme, the documented
#                            legacy default. Only for throwaway test builds.
# Optional: AVALONOS_USER (default admin), AVALONOS_ROOTPW_LINE (default
# "rootpw --lock"), AVALONOS_CACHE (default cache/), AVALONOS_OUT (default out/).
#
# Steps: fetch + verify upstream, render ks.cfg, build overlay/docs tarballs,
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
OUT="$OUTDIR/$OUTPUT_ISO"
die() { echo "build-iso: ERROR: $*" >&2; exit 1; }
for t in xorriso mcopy mtype patch tar curl gpgv sha256sum awk dd; do
    command -v "$t" >/dev/null || die "missing tool: $t (Fedora: dnf install xorriso mtools patch tar curl gnupg2 mkpasswd)"
done

# ---- credentials -----------------------------------------------------------
USER_NAME="${AVALONOS_USER:-admin}"
ROOTPW_LINE="${AVALONOS_ROOTPW_LINE:-rootpw --lock}"
LOCAL_KS="$ROOT/kickstart/AvalonOS.local.ks"
if [ -n "${AVALONOS_ADMIN_PW_HASH:-}" ]; then
    PW_HASH="$AVALONOS_ADMIN_PW_HASH"; src="AVALONOS_ADMIN_PW_HASH"
elif [ -f "$LOCAL_KS" ]; then
    auth="$(sed -n '/^# --- tailwhip:auth ---$/,/^# --- tailwhip:auth ---$/p' "$LOCAL_KS")"
    USER_NAME="$(printf '%s\n' "$auth" | sed -n "s/^user --name=\([^ ]*\) .*/\1/p")"
    PW_HASH="$(printf '%s\n' "$auth" | sed -n "s/^user .*--password='\([^']*\)'.*/\1/p")"
    ROOTPW_LINE="$(printf '%s\n' "$auth" | grep '^rootpw ' || true)"
    [ -n "$USER_NAME" ] && [ -n "$PW_HASH" ] && [ -n "$ROOTPW_LINE" ] || die "$LOCAL_KS has no usable tailwhip:auth block; re-run scripts/tailwhip"
    src="$LOCAL_KS"
elif [ "${AVALONOS_INSECURE_DEFAULT_PASSWORD:-}" = 1 ]; then
    command -v mkpasswd >/dev/null || die "mkpasswd needed for the insecure default"
    PW_HASH="$(printf 'changeme' | mkpasswd -m yescrypt --stdin)"; src="INSECURE default admin/changeme"
    echo "build-iso: WARNING: INSECURE BUILD: admin password is 'changeme'. Do not publish or install this ISO on a real machine." >&2
else
    cat >&2 <<'MSG'
build-iso: ERROR: no admin password hash.
  Set AVALONOS_ADMIN_PW_HASH (e.g. export AVALONOS_ADMIN_PW_HASH="$(mkpasswd -m yescrypt)"),
  or run scripts/tailwhip --user admin to write kickstart/AvalonOS.local.ks,
  or (test builds only, INSECURE) AVALONOS_INSECURE_DEFAULT_PASSWORD=1 for admin/changeme.
MSG
    exit 1
fi
echo "build-iso: credentials from $src (user $USER_NAME, ${ROOTPW_LINE})"

# ---- upstream --------------------------------------------------------------
AVALONOS_CACHE="$CACHE" "$ROOT/scripts/fetch-upstream.sh"

rm -rf "$WORK"; mkdir -p "$WORK/payload/avalonos" "$WORK/grub" "$OUTDIR"
trap 'rm -f "$WORK/ks.cfg"' EXIT   # never leave the hash lying around

# ---- payload ---------------------------------------------------------------
"$ROOT/scripts/render-kickstart.sh" "$WORK/ks.cfg" "$USER_NAME" "$PW_HASH" "$ROOTPW_LINE"
"$ROOT/scripts/make-golden-tarball.sh" "$WORK/payload/avalonos/overlay.tar"
"$ROOT/scripts/make-docs-tarball.sh" "$WORK/payload/avalonos/docs.tar"
install -m 0644 "$ROOT/kickstart/packages.inc" "$WORK/payload/avalonos/packages.inc"
chmod 0644 "$WORK/payload/avalonos/"*

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
if ! xorriso -indev "$UP" -outdev "$OUT" \
    -boot_image any replay \
    -append_partition 2 "$esp_type" "$WORK/efiboot.img" \
    -boot_image any efi_path=--interval:appended_partition_2:all:: \
    -map "$WORK/ks.cfg" /ks.cfg \
    -map "$WORK/payload/avalonos" /avalonos \
    -map "$WORK/grub/EFI/BOOT/grub.cfg" /EFI/BOOT/grub.cfg \
    -map "$WORK/grub/EFI/BOOT/BOOT.conf" /EFI/BOOT/BOOT.conf \
    -map "$WORK/grub/boot/grub2/grub.cfg" /boot/grub2/grub.cfg \
    -chown_r 0 /ks.cfg /avalonos /EFI/BOOT/grub.cfg /EFI/BOOT/BOOT.conf /boot/grub2/grub.cfg -- \
    -chgrp_r 0 /ks.cfg /avalonos /EFI/BOOT/grub.cfg /EFI/BOOT/BOOT.conf /boot/grub2/grub.cfg -- \
    -chmod 0600 /ks.cfg -- \
    -chmod 0755 /avalonos -- \
    -chmod 0644 /avalonos/overlay.tar /avalonos/docs.tar /avalonos/packages.inc -- \
    -chmod 0644 /EFI/BOOT/grub.cfg /EFI/BOOT/BOOT.conf /boot/grub2/grub.cfg -- \
    -commit_eject all > "$WORK/xorriso.log" 2>&1; then
    cat "$WORK/xorriso.log" >&2; die "xorriso failed"
fi
grep -E "SORRY|FAILURE|WARNING|image produced" "$WORK/xorriso.log" || true
grep -qE "SORRY|FAILURE" "$WORK/xorriso.log" && die "xorriso reported errors (see $WORK/xorriso.log)"
[ -s "$OUT" ] || die "xorriso did not produce $OUT"
(cd "$OUTDIR" && sha256sum "$OUTPUT_ISO" > "$OUTPUT_ISO.sha256")
"$ROOT/scripts/verify-iso.sh" "$OUT"
echo "build-iso: done: $OUT"
cat "$OUT.sha256"
