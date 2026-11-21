#!/usr/bin/env bash
# Tests for scripts/check-iso-unowned.sh (P-L12, Codex review finding 1):
# key material in ISO bytes that belong to no file, and in the ESP outside its
# files. Offline, on COPIES of the pinned upstream netinst (no ISO is built):
#   testing/offline/iso-unowned-test.sh UPSTREAM_ISO
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UP="$(realpath "${1:?upstream ISO}")"
CU="$ROOT/scripts/check-iso-unowned.sh"; K="$ROOT/keys/RPM-GPG-KEY-avalonos-test"
T="$(mktemp -d -p "${TMPDIR:-/var/tmp}")"; trap 'rm -rf "$T"' EXIT
pass=0; fails=0
ok()  { echo "ok    $*"; pass=$((pass+1)); }
nok() { echo "FAIL  $*"; fails=$((fails+1)); }
accept() { local d="$1"; shift; if "$@" >"$T/out" 2>&1; then ok "$d"; else nok "$d"; sed 's/^/      /' "$T/out" | head -8; fi; }
rejectw() { local d="$1" re="$2"; shift 2; local rc=0; "$@" >"$T/out" 2>&1 || rc=$?
    if [ "$rc" = 1 ] && grep -qE "$re" "$T/out"; then ok "$d -- $(grep -m1 -E "$re" "$T/out" | cut -c1-110)"
    else nok "$d (exit $rc)"; sed 's/^/      /' "$T/out" | head -5; fi; }
rel() { AVALONOS_TEST_BUILD=0 "$@"; }
tst() { AVALONOS_TEST_BUILD=1 "$@"; }
X() { env -u SOURCE_DATE_EPOCH xorriso "$@"; }
gpg --batch --homedir "$(mktemp -d -p "$T")" --dearmor < "$K" > "$T/k.bin"
gzip -9nc < "$T/k.bin" > "$T/k.gz"
accept "U1 upstream netinst: unowned bytes clean, release mode" rel "$CU" "$UP"
accept "U2 upstream netinst: unowned bytes clean, test mode"    tst "$CU" "$UP"
# Gap1 (GPT partition 3 on Fedora media) is no file's data.
read -r g3s _ < <(X -indev "$UP" -report_system_area plain 2>/dev/null | awk '$1=="GPT" && $2=="start" && $6=="3" {print $7, $8}')
cp --reflink=auto "$UP" "$T/iso"
dd if="$T/k.gz" of="$T/iso" bs=512 seek="$((g3s + 7))" conv=notrunc status=none
rejectw "U3 gzip(TEST key) in unowned sectors (GPT Gap1), same ISO size" 'gap-.*material' rel "$CU" "$T/iso"
cp --reflink=auto "$UP" "$T/iso"
read -r s z < <(X -indev "$UP" -find /.discinfo -exec report_lba -- 2>/dev/null | awk -F, '/File data lba/ {gsub(/ /,""); print $2, $4}')
[ "$(stat -c %s "$T/k.gz")" -lt $((2048 - z)) ] || echo "note: k.gz larger than the slack"
dd if="$T/k.gz" of="$T/iso" bs=1 seek="$((s * 2048 + z))" conv=notrunc status=none
rejectw "U4 gzip(TEST key) in the slack after a file's last byte" 'gap-.*material' rel "$CU" "$T/iso"
rm -f "$T/iso"; cp --reflink=auto "$UP" "$T/iso"; mkdir "$T/sq"; cp "$K" "$T/sq/k"; mksquashfs "$T/sq" "$T/sq.img" -quiet -noappend >/dev/null 2>&1
dd if="$T/sq.img" of="$T/iso" bs=512 seek="$((g3s + 20))" conv=notrunc status=none
rejectw "U6 squashfs image (uninspectable) in unowned sectors" 'squashfs data at offset' rel "$CU" "$T/iso"
rm -f "$T/iso"; cp --reflink=auto "$UP" "$T/iso"; base64 -w0 "$T/k.bin" >> "$T/iso"
rejectw "U5 base64 TEST key appended after the image" 'gap-.*material' rel "$CU" "$T/iso"
rm -f "$T/iso"
# ESP: build-iso.sh's construction vs. the checker's rebuild.
read -r es ez < <(X -indev "$UP" -report_system_area plain 2>/dev/null | awk '$1=="GPT" && $2=="start" && $6=="2" {print $7, $8}')
dd if="$UP" of="$T/up-esp.img" bs=512 skip="$es" count="$ez" status=none
X -osirrox on -indev "$UP" -extract /EFI/BOOT/grub.cfg "$T/grub.cfg" >/dev/null 2>&1; chmod u+w "$T/grub.cfg"
patch -s --no-backup-if-mismatch "$T/grub.cfg" < "$ROOT/boot/grub-efi.patch" || echo "note: grub-efi.patch did not apply"
mkesp() { cp "$T/up-esp.img" "$T/esp.img"; for f in grub.cfg BOOT.conf; do SOURCE_DATE_EPOCH=1791756588 MTOOLS_SKIP_CHECK=1 mcopy -o -i "$T/esp.img" "$T/grub.cfg" "::/EFI/BOOT/$f"; done; }
mkesp; accept "E1 ESP built as build-iso.sh does (other SOURCE_DATE_EPOCH) == rebuild" "$CU" --esp "$T/esp.img" "$T/up-esp.img" "$T/grub.cfg"
mkesp; dd if="$T/k.gz" of="$T/esp.img" bs=1 seek="$(( $(stat -c %s "$T/esp.img") - 65536 ))" conv=notrunc status=none
rejectw "E2 gzip(TEST key) in free ESP clusters" 'differs from the rebuilt ESP' "$CU" --esp "$T/esp.img" "$T/up-esp.img" "$T/grub.cfg"
mkesp; SOURCE_DATE_EPOCH=1791756588 MTOOLS_SKIP_CHECK=1 mcopy -i "$T/esp.img" "$T/k.gz" ::/EFI/BOOT/fonts.bin
rejectw "E3 extra file in the ESP" 'differs from the rebuilt ESP' "$CU" --esp "$T/esp.img" "$T/up-esp.img" "$T/grub.cfg"
mkesp; cp "$T/grub.cfg" "$T/grub2.cfg"; echo "# x" >> "$T/grub2.cfg"
rejectw "E4 ESP grub.cfg differs from the ISO9660 one" 'differs from the rebuilt ESP|size' "$CU" --esp "$T/esp.img" "$T/up-esp.img" "$T/grub2.cfg"
echo "iso-unowned-test: $pass ok, $fails failed"
[ "$fails" = 0 ]
