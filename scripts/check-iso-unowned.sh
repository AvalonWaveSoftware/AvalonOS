#!/usr/bin/env bash
# ISO bytes outside any file (Code Security P-L12; Codex review finding 1).
#   check-iso-unowned.sh ISO [UPSTREAM_ISO]
#   check-iso-unowned.sh --esp ESP.img UPSTREAM_ESP.img GRUB_CFG   (part 2 only, on images)
# 1. Every ISO byte that belongs to no file -- system area, volume
#    descriptors, directory records, padding, the slack after each file's
#    last byte, anything appended -- except the ESP (GPT partition 2) is
#    written out and inspected by check-key-isolation.sh in full (decoding,
#    carving), not only the raw scan.
# 2. With UPSTREAM_ISO: the ESP must be byte-identical to upstream's ESP with
#    this ISO's /EFI/BOOT/grub.cfg copied in as EFI/BOOT/grub.cfg and BOOT.conf
#    (as build-iso.sh does), except the timestamp bytes of FAT directory
#    entries (mtools stamps them with SOURCE_DATE_EPOCH). Free clusters and
#    every other ESP byte are thereby proven upstream's.
# AVALONOS_TEST_BUILD selects the build kind as for check-key-isolation.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
X() { env -u SOURCE_DATE_EPOCH xorriso "$@"; }
esp_cmp() {  # ESP.img UPSTREAM_ESP.img GRUB_CFG
    local ok=1 f
    cp "$2" "$T/re.img"
    [ -s "$3" ] || ok=0
    for f in grub.cfg BOOT.conf; do
        SOURCE_DATE_EPOCH=0 MTOOLS_SKIP_CHECK=1 mcopy -o -i "$T/re.img" "$3" "::/EFI/BOOT/$f" 2>/dev/null || ok=0
    done
    [ "$ok" = 1 ] && python3 - "$T/re.img" "$1" <<'PY'
import sys
a, b = open(sys.argv[1], "rb").read(), open(sys.argv[2], "rb").read()
if len(a) != len(b): print(f"  ESP size {len(b)} != rebuilt {len(a)}"); sys.exit(1)
TIME = {13, 14, 15, 16, 17, 18, 19, 22, 23, 24, 25}       # FAT dir entry: ctime, cdate, adate, wtime, wdate
ents = set(); n = 0
step = 1 << 20
for o in range(0, len(a), step):
    x, y = a[o:o + step], b[o:o + step]
    if x == y: continue
    for i in range(len(x)):
        if x[i] != y[i]:
            p = o + i; e = p - p % 32
            if p % 32 not in TIME or a[e:e + 12] != b[e:e + 12] or a[e] in (0, 0xE5):
                print(f"  ESP byte {p} differs from the rebuilt ESP (not a directory-entry timestamp)"); sys.exit(1)
            ents.add(e); n += 1
if len(ents) > 8: print(f"  {len(ents)} directory entries differ (at most 8 expected)"); sys.exit(1)
print(f"  ESP == rebuilt ESP except {n} timestamp bytes in {len(ents)} directory entries")
PY
}
if [ "${1:-}" = --esp ]; then
    [ $# = 4 ] || { echo "usage: $0 --esp ESP.img UPSTREAM_ESP.img GRUB_CFG" >&2; exit 2; }
    if esp_cmp "$2" "$3" "$4"; then echo "check-iso-unowned: ok   ESP == upstream ESP + grub.cfg (only FAT timestamps differ)"; exit 0
    else echo "check-iso-unowned: FAIL ESP is not upstream's ESP + grub.cfg" >&2; exit 1; fi
fi
ISO="${1:?usage: check-iso-unowned.sh ISO [UPSTREAM_ISO]}"; UP="${2:-}"
X -indev "$ISO" -report_system_area plain > "$T/sa" 2>/dev/null
read -r p2s p2z < <(awk '$1=="GPT" && $2=="start" && $6=="2" {print $7, $8}' "$T/sa")
[ -n "${p2s:-}" ] || { echo "check-iso-unowned: FAIL no GPT partition 2 (ESP) in $ISO" >&2; exit 1; }
X -indev "$ISO" -find / -type f -exec report_lba -- > "$T/lba" 2>/dev/null
grep -q '^File data lba:' "$T/lba" || { echo "check-iso-unowned: FAIL cannot list file extents of $ISO" >&2; exit 1; }
mkdir "$T/gaps"
python3 - "$ISO" "$T/lba" "$p2s" "$p2z" "$T/gaps" <<'PY'
import os, re, sys
iso, lba, p2s, p2z, out = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
size = os.path.getsize(iso)
owned = []
for l in open(lba, encoding="utf-8", errors="replace"):
    m = re.match(r"File data lba:\s*\d+\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,", l)
    if m:
        start, blocks, fsize = (int(x) for x in m.groups())
        owned.append((start * 2048, start * 2048 + min(fsize, blocks * 2048)))   # slack after the file is NOT owned
owned.append((p2s * 512, (p2s + p2z) * 512))                                      # ESP: checked by part 2
owned.sort()
gaps, pos = [], 0
for a, b in owned:
    if a > pos: gaps.append((pos, a))
    pos = max(pos, b)
if pos < size: gaps.append((pos, size))
# The system area (first 32 KiB) is its own piece, so the volume descriptors
# behind it are inspected as data, not taken for an ISO9660 image.
gaps = [g for a, b in gaps for g in ([(a, 32768), (32768, b)] if a < 32768 < b else [(a, b)])]
total = 0
with open(iso, "rb") as f:
    # Merge gaps separated by small owned spans? No: each gap is one file, so a
    # stream can never be stitched across file data.
    for a, b in gaps:
        f.seek(a); d = f.read(b - a); total += len(d)
        if d.strip(b"\x00"):
            open(os.path.join(out, f"gap-{a:012d}-{b - a}"), "wb").write(d)
print(f"{len(gaps)} unowned ranges, {total} bytes, {len(os.listdir(out))} not all-zero")
PY
if "$ROOT/scripts/check-key-isolation.sh" --gaps "$T/gaps" > "$T/ki" 2>&1; then
    echo "check-iso-unowned: ok   unowned ISO bytes (outside every file and the ESP) carry no foreign key in any encoding"
else
    echo "check-iso-unowned: FAIL unowned ISO bytes:" >&2; sed 's/^/    /' "$T/ki" >&2; fail=1
fi
if [ -n "$UP" ]; then
    read -r us uz < <(X -indev "$UP" -report_system_area plain 2>/dev/null | awk '$1=="GPT" && $2=="start" && $6=="2" {print $7, $8}')
    dd if="$ISO" of="$T/esp.img" bs=512 skip="$p2s" count="$p2z" status=none
    X -osirrox on -indev "$ISO" -extract /EFI/BOOT/grub.cfg "$T/grub.cfg" >/dev/null 2>&1 || true
    dd if="$UP" of="$T/up-esp.img" bs=512 skip="$us" count="$uz" status=none
    if esp_cmp "$T/esp.img" "$T/up-esp.img" "$T/grub.cfg"
    then echo "check-iso-unowned: ok   ESP == upstream ESP + this ISO's grub.cfg (only FAT timestamps differ)"
    else echo "check-iso-unowned: FAIL ESP is not upstream's ESP + this ISO's grub.cfg" >&2; fail=1; fi
fi
[ "$fail" = 0 ]
