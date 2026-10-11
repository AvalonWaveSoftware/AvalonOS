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
# S0-style split payloads inside owned file extents remain a documented residual.
# AVALONOS_TEST_BUILD selects the build kind as for check-key-isolation.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
exec 3>&2
X() {
    local rc=0
    # 60s covers -report_system_area / -find on a netinst ISO; a hang is FAIL.
    timeout -k 2s 60s env -u SOURCE_DATE_EPOCH xorriso "$@" || rc=$?
    if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
        echo "check-iso-unowned: FAIL: xorriso timed out" >&3
        # P-I28: exit 1 inside a subshell does not fail the main shell;
        # the later `[ ! -e "$T/xorriso-timeout" ]` check needs this mark.
        : > "$T/xorriso-timeout"
        exit 1
    fi
    return "$rc"
}
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
# P-I23: a PVD-like sector with volume-space < 17 (including 0) at LBA 16
# or at a GPT-start alias (64/80) makes xorriso 1.5.8 -report_system_area
# hang. Reject those in Python before any xorriso call.
python3 - "$ISO" <<'PYPRE'
import os, struct, sys
iso = sys.argv[1]
SECTOR = 2048
size = os.path.getsize(iso)
def pvd_volspace(s):
    if len(s) == SECTOR and s[0] == 1 and s[1:7] == b"CD001\x01":
        return int.from_bytes(s[80:84], "little"), int.from_bytes(s[84:88], "big")
    return None
lbas = {16, 32, 64, 80}
with open(iso, "rb") as f:
    f.seek(512)
    hdr = f.read(92)
    if hdr[:8] == b"EFI PART":
        part_lba, npart, psz = struct.unpack_from("<QII", hdr, 72)
        f.seek(part_lba * 512)
        for _ in range(npart):
            e = f.read(psz)
            if len(e) < 40 or e[:16] == b"\x00" * 16:
                continue
            start512 = int.from_bytes(e[32:40], "little")
            if start512 % 4 == 0:
                lbas.add(start512 // 4)
with open(iso, "rb") as f:
    for lba in sorted(lbas):
        if (lba + 1) * SECTOR > size:
            continue
        f.seek(lba * SECTOR)
        vs = pvd_volspace(f.read(SECTOR))
        if vs is None:
            continue
        le, be = vs
        if le != be or le < 17 or le * SECTOR > size:
            print(f"check-iso-unowned: FAIL unusable volume-space size {le} at LBA {lba}", file=sys.stderr)
            sys.exit(1)
PYPRE
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
# R7-B1 / P-L16 / R9-B1: exempt only structurally validated volume-descriptor
# sectors at layout-derived candidates, derived from
# -report_system_area (principal at 16, partition-offset copies, and the
# GPT-start views including 64/80). Partition-offset / offset-view sets
# (LBA 16+po, typically 32) may differ and are still exempted when they
# validate (P-I21). GPT-start-as-2048-LBA aliases (64/80) are exempted
# only when they match their corresponding offset view (64 vs 16, 80 vs
# 32): same set length, byte-identical except the PVD volume-space-size
# field at bytes 80-87, whose LE/BE halves must agree and be <= the
# reference. xorriso 1.5.8 copies 16->64 and 32->80 this way. A planted
# set that differs anywhere else is not exempted. This is not a scan of
# LBA 16..1024 and not a wider bound: a same-volume set elsewhere (e.g.
# an appended embedded ISO) is not exempted.
python3 - "$ISO" "$T/vd-offsets" "$T/sa" "$p2s" <<'PY'
import os, sys
SECTOR, TYPES = 2048, {0, 1, 2, 3, 255}
iso, outp, sa_path, esp_start = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
iso_size = os.path.getsize(iso)
iso_lbas = iso_size // SECTOR

def be32(s, off):
    le, be = int.from_bytes(s[off:off+4], "little"), int.from_bytes(s[off+4:off+8], "big")
    return le if le == be else None

def be16(s, off):
    le, be = int.from_bytes(s[off:off+2], "little"), int.from_bytes(s[off+2:off+4], "big")
    return le if le == be else None

def is_desc(s):
    return len(s) == SECTOR and s[1:7] == b"CD001\x01" and s[0] in TYPES

def is_pvd(s, expect_vol_id=None):
    if not is_desc(s) or s[0] != 1:
        return False
    vol_space, block_size = be32(s, 80), be16(s, 128)
    if vol_space is None or vol_space < 17 or block_size != 2048:
        return False
    if vol_space * SECTOR > iso_size:
        return False
    if expect_vol_id is not None and s[40:72] != expect_vol_id:
        return False
    rlen = s[156]
    if rlen < 34 or 156 + rlen > SECTOR or (s[156 + 25] & 2) == 0:
        return False
    extent, path_size, vss = be32(s, 156 + 2), be32(s, 132), be16(s, 120)
    if extent is None or extent >= vol_space or path_size is None or path_size == 0 or vss is None or vss < 1:
        return False
    return True

def read_set(f, start_lba, expect_vol_id=None):
    sectors = []
    for i in range(32):
        lba = start_lba + i
        if lba >= iso_lbas:
            return None
        f.seek(lba * SECTOR)
        s = f.read(SECTOR)
        if i == 0:
            if not is_pvd(s, expect_vol_id):
                return None
        elif not is_desc(s):
            return None
        sectors.append(lba)
        if s[0] == 255:
            return sectors if i > 0 else None
    return None

def read_raw_set(f, start_lba):
    # Terminated CD001 set, no PVD field checks. Alias copies may have a
    # smaller volume-space than the reference (xorriso 1.5.8), so the root
    # extent can fail is_pvd's extent < vol_space test even when the set is
    # a valid near-copy. alias_copy_ok is the real check.
    sectors = []
    for i in range(32):
        lba = start_lba + i
        if lba >= iso_lbas:
            return None
        f.seek(lba * SECTOR)
        s = f.read(SECTOR)
        if not is_desc(s) or (i == 0 and s[0] != 1):
            return None
        sectors.append(lba)
        if s[0] == 255:
            return sectors if i > 0 else None
    return None

# P-L16 / R9-B1: extra sets are accepted only at locations xorriso actually uses,
# derived from -report_system_area (not a scan of LBA 16..1024).
#   * LBA 16 (principal) and 16+partition_offset (may differ from principal)
#   * each non-ESP GPT partition start as an ISO LBA (start_512/4) and +po
#   * the same GPT start number treated as a 2048-byte LBA, and +po
#     (xorriso 1.5.8 copies 16->64 and 32->80, differing only in PVD
#     volume-space size at bytes 80-87; unused or planted aliases are
#     not exempted)
def candidates(sa_text, esp_start_512):
    # offset_views: principal and real ISOHybrid 2048-byte views
    # (16, 16+po, GPT start_512/4 and +po). These copies may legitimately
    # differ (volume-space size, a shorter set, no Boot Record).
    # alias_refs: GPT start number used as a 2048-byte LBA (64/80), mapped
    # to the corresponding offset view (start_512 -> start_512/4, and
    # start_512+po -> start_512/4+po). xorriso 1.5.8 copies 16->64 and
    # 32->80, allowing only PVD volume-space size (bytes 80-87) to differ.
    offset_views, alias_refs, po, gpt = {16}, {}, 0, []
    for line in sa_text.splitlines():
        w = line.split()
        if len(w) >= 4 and w[0] == "Partition" and w[1] == "offset" and w[2] == ":":
            try:
                po = int(w[3])
            except ValueError:
                pass
        if len(w) >= 8 and w[0] == "GPT" and w[1] == "start" and w[2] == "and" and w[3] == "size" and w[4] == ":":
            try:
                gpt.append((int(w[5]), int(w[6]), int(w[7])))
            except ValueError:
                pass
    if po > 0:
        offset_views.add(16 + po)
    for _n, start512, _sz in gpt:
        if start512 == esp_start_512:
            continue
        iso_start = (start512 // 4) if (start512 % 4 == 0) else None
        if iso_start is not None:
            offset_views.add(iso_start)
            if po > 0:
                offset_views.add(iso_start + po)
        if iso_start is None:
            continue
        if 16 <= start512 < iso_lbas:
            alias_refs[start512] = iso_start
        if po > 0 and 16 <= start512 + po < iso_lbas:
            alias_refs[start512 + po] = iso_start + po
    offset_views = {c for c in offset_views if 16 <= c < iso_lbas}
    alias_refs = {a: r for a, r in alias_refs.items()
                  if a not in offset_views and r in offset_views}
    return offset_views, alias_refs

def alias_copy_ok(cand, ref):
    # Same length as the reference set. Only PVD bytes 80-87 (both-endian
    # volume-space size) may differ; LE/BE must agree, cand must be a
    # usable volume-space (at least 17 like is_pvd), and cand <= ref.
    # A zero or tiny volume-space is not exempted (P-I23).
    if len(cand) != len(ref) or len(cand) < SECTOR:
        return False
    if cand[:80] != ref[:80] or cand[88:] != ref[88:]:
        return False
    c_le = int.from_bytes(cand[80:84], "little")
    c_be = int.from_bytes(cand[84:88], "big")
    r_le = int.from_bytes(ref[80:84], "little")
    r_be = int.from_bytes(ref[84:88], "big")
    if c_le != c_be or r_le != r_be:
        return False
    if c_le < 17 or c_le * SECTOR > iso_size:
        return False
    return c_le <= r_le

sa_text = open(sa_path, encoding="utf-8", errors="replace").read() if os.path.exists(sa_path) else ""
offset_views, alias_refs = candidates(sa_text, esp_start)
allowed, seen, sets = [], set(), []
with open(iso, "rb") as f:
    principal = read_set(f, 16)
    if not principal:
        sys.exit(0)
    f.seek(16 * SECTOR)
    principal_bytes = f.read(len(principal) * SECTOR)
    vol_id = principal_bytes[40:72]
    seen.add(16)
    sets.append(principal)
    for lba in sorted(offset_views):
        if lba in seen:
            continue
        st = read_set(f, lba, vol_id)
        if st:
            sets.append(st)
            seen.add(lba)
    set_at = {st[0]: st for st in sets}
    for lba in sorted(alias_refs):
        if lba in seen:
            continue
        ref_lba = alias_refs[lba]
        ref_st = set_at.get(ref_lba)
        if not ref_st:
            continue
        st = read_raw_set(f, lba)
        if not st or len(st) != len(ref_st):
            continue
        f.seek(lba * SECTOR)
        cand_bytes = f.read(len(st) * SECTOR)
        f.seek(ref_lba * SECTOR)
        ref_bytes = f.read(len(ref_st) * SECTOR)
        if alias_copy_ok(cand_bytes, ref_bytes):
            sets.append(st)
            seen.add(lba)
            set_at[lba] = st
for st in sets:
    for lba in st:
        allowed.append(lba * SECTOR + 1)  # absolute offset of CD001
open(outp, "w").write("\n".join(str(o) for o in allowed) + ("\n" if allowed else ""))
print(f"validated volume-descriptor sectors: {len(allowed)} CD001 offsets in {len(sets)} set(s)")
PY
[ -s "$T/vd-offsets" ] || { echo "check-iso-unowned: FAIL no validated ISO9660 volume descriptor set at LBA 16 in $ISO" >&2; exit 1; }
if AV_GAP_VD_OFFSETS="$T/vd-offsets" "$ROOT/scripts/check-key-isolation.sh" --gaps "$T/gaps" > "$T/ki" 2>&1; then
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
[ ! -e "$T/xorriso-timeout" ] || fail=1
[ "$fail" = 0 ]
