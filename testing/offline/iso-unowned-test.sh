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
pass=0; fails=0; skips=0
ok()  { echo "ok    $*"; pass=$((pass+1)); }
nok() { echo "FAIL  $*"; fails=$((fails+1)); }
skip() { echo "SKIP  $*"; skips=$((skips+1)); }
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
# P-L17: a deterministic fixture with validated descriptor sets at LBA 64
# and 80 must be accepted, and the validator must list those sectors.
# Built with the same xorriso append-partition recipe as production media.
mkdir -p "$T/u7tree"
printf 'public P-L17 fixture\n' > "$T/u7tree/readme.txt"
python3 - "$T/u7part.img" <<'PY'
import sys
open(sys.argv[1], "wb").write(bytes(64 * 1024))
PY
# -partition_offset 16 yields the 16/32 copies and GPT start 64, so
# 64/80 are layout-derived candidates. xorriso 1.5.8 writes those 64/80
# sets on bootable media; this small fixture may not, so we copy the
# already-validated 16 and 32 sets into unused (all-zero) sectors at
# 64 and 80. xorriso may exit 32 (SORRY) after a successful write.
env -u SOURCE_DATE_EPOCH xorriso -as mkisofs -R -V U7FIXTURE \
      -partition_offset 16 \
      -append_partition 2 0xef "$T/u7part.img" -appended_part_as_gpt \
      -o "$T/u7fix.iso" "$T/u7tree" >"$T/u7build.log" 2>&1 || true
if [ -s "$T/u7fix.iso" ]; then
    if python3 - "$T/u7fix.iso" <<'PY'
import sys
p = sys.argv[1]
S = 2048
with open(p, "r+b") as f:
    def sector(lba):
        f.seek(lba * S)
        return f.read(S)
    def is_pvd(s):
        return len(s) == S and s[0] == 1 and s[1:7] == b"CD001\x01"
    def write_set(src, dst):
        # Copy a terminated descriptor set from src to dst only if the
        # destination is unused (all-zero). Volume-space size is left as
        # in the source; the validator allows nonidentical valid sets.
        sectors = []
        for i in range(32):
            s = sector(src + i)
            if (i == 0 and not is_pvd(s)) or (i and not (len(s) == S and s[1:7] == b"CD001\x01")):
                return False
            sectors.append(s)
            if s[0] == 255:
                break
        else:
            return False
        for i, s in enumerate(sectors):
            cur = sector(dst + i)
            if cur != bytes(S) and cur != s:
                return False
            f.seek((dst + i) * S)
            f.write(s)
        return True
    if not (is_pvd(sector(16)) and is_pvd(sector(32))):
        print("P-L17 fixture missing PVD at LBA 16 or 32")
        sys.exit(1)
    if not is_pvd(sector(64)):
        if not write_set(16, 64):
            print("P-L17 fixture could not place a validated set at LBA 64")
            sys.exit(1)
    if not is_pvd(sector(80)):
        if not write_set(32, 80):
            print("P-L17 fixture could not place a validated set at LBA 80")
            sys.exit(1)
    if not (is_pvd(sector(64)) and is_pvd(sector(80))):
        print("P-L17 fixture missing PVD at LBA 64 or 80")
        sys.exit(1)
    print("P-L17 fixture has validated-style PVDs at LBA 64 and 80")
PY
    then
        accept "U7d deterministic ISO with validated sets at LBA 64 and 80 is clean" rel "$CU" "$T/u7fix.iso"
        if rel "$CU" "$T/u7fix.iso" >"$T/u7off.log" 2>&1 && \
           grep -q '^validated volume-descriptor sectors:' "$T/u7off.log" && \
           env -u SOURCE_DATE_EPOCH xorriso -indev "$T/u7fix.iso" -report_system_area plain >"$T/u7sa" 2>/dev/null; then
            p2s=$(awk '$1=="GPT" && $2=="start" && $6=="2" {print $7}' "$T/u7sa")
            if python3 - "$ROOT/scripts/check-iso-unowned.sh" "$T/u7fix.iso" "$T/u7sa" "$p2s" <<'PY'
import sys
from pathlib import Path
src = Path(sys.argv[1]).read_text()
marker = 'python3 - "$ISO" "$T/vd-offsets" "$T/sa" "$p2s" <<\'PY\'\n'
val = src.split(marker, 1)[1].split("\nPY\n", 1)[0]
iso, sa, p2s = sys.argv[2], sys.argv[3], sys.argv[4]
import subprocess, tempfile, os
out = tempfile.NamedTemporaryFile(delete=False)
out.close()
r = subprocess.run([sys.executable, "-c", val, iso, out.name, sa, p2s], capture_output=True, text=True)
if r.returncode != 0:
    sys.stderr.write(r.stderr or r.stdout)
    sys.exit(1)
offs = {int(x) for x in Path(out.name).read_text().split()} if Path(out.name).exists() else set()
need = {lba * 2048 + 1 for lba in (64, 65, 80, 81)}
if not need.issubset(offs):
    print("validator offsets missing 64/80:", sorted(offs), file=sys.stderr)
    sys.exit(1)
print("validator offsets include LBA 64,65,80,81")
PY
            then
                ok "U7d validator offset list includes LBA 64 and 80"
            else
                nok "U7d validator offset list does not include LBA 64 and 80"
            fi
        else
            nok "U7d re-run of fixture failed or summary missing"
            sed 's/^/      /' "$T/u7off.log" 2>/dev/null | head -8
        fi
        cp "$T/u7fix.iso" "$T/u7inj.iso"
        printf 'xxCD001yy' >> "$T/u7inj.iso"
        rejectw "U8d CD001 injected outside validated descriptor sectors still fails" 'ISO9660 data at offset' rel "$CU" "$T/u7inj.iso"
    else
        nok "U7d fixture ISO has no PVD at LBA 64 or 80"; sed 's/^/      /' "$T/u7build.log" | tail -8
    fi
else
    nok "U7d could not build the deterministic 64/80 fixture"; sed 's/^/      /' "$T/u7build.log" | tail -8
fi
# Optional live boot-replay of the upstream ISO: require a PVD at LBA 80
# or report SKIP (counted). Do not vacuous-ok when LBA 80 is absent.
esp_type="$(X -indev "$UP" -report_system_area plain 2>/dev/null | awk '$1=="GPT" && $2=="type" && $5=="2" {print $6}')"
if [ -n "$esp_type" ] && [ -s "$T/up-esp.img" ] && \
   env -u SOURCE_DATE_EPOCH xorriso -indev "$UP" -outdev "$T/replay.iso" \
      -boot_image any replay \
      -append_partition 2 "$esp_type" "$T/up-esp.img" \
      -boot_image any efi_path=--interval:appended_partition_2:all:: \
      -commit_eject all >"$T/replay.log" 2>&1; then
    if python3 - "$T/replay.iso" <<'PY'
import sys
p = sys.argv[1]
with open(p, "rb") as f:
    f.seek(80 * 2048)
    s = f.read(2048)
if not (len(s) == 2048 and s[0] == 1 and s[1:7] == b"CD001\x01"):
    sys.exit(2)
print("replay ISO has validated-style PVD at LBA 80")
PY
    then
        accept "U7 xorriso replay ISO (descriptor sets incl. LBA 64/80) unowned bytes clean" rel "$CU" "$T/replay.iso"
        printf 'xxCD001yy' >> "$T/replay.iso"
        rejectw "U8 CD001 injected outside validated descriptor sectors still fails" 'ISO9660 data at offset' rel "$CU" "$T/replay.iso"
    else
        rc=$?
        if [ "$rc" = 2 ]; then
            skip "U7 replay ISO has no PVD at LBA 80"
        else
            nok "U7 replay ISO PVD probe failed"
        fi
    fi
else
    skip "U7 could not build a xorriso replay ISO"
    sed 's/^/      /' "$T/replay.log" 2>/dev/null | tail -8
fi
rm -f "$T/replay.iso" "$T/u7fix.iso" "$T/u7inj.iso"
echo "iso-unowned-test: $pass ok, $skips skipped, $fails failed"
[ "$fails" = 0 ]
