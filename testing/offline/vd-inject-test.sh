#!/usr/bin/env bash
# Offline descriptor-exemption regressions; no AvalonOS payload ISO required.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for tool in xorriso python3 rpm rpmkeys rpm2cpio cpio gpg gpgv zstd; do
    command -v "$tool" >/dev/null || { echo "vd-inject-test: missing tool $tool" >&2; exit 2; }
done
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir "$T/tree"
printf 'public synthetic descriptor fixture\n' > "$T/tree/readme.txt"
# Partition 2 is only an owned-byte placeholder: this test does not exercise
# --esp or compare it with an upstream ESP, and needs no FAT tooling.
python3 - "$T/partition.img" <<'PY'
import sys
with open(sys.argv[1], 'wb') as f:
    f.write(bytes(64 * 1024))
PY
env -u SOURCE_DATE_EPOCH xorriso -as mkisofs -R -V VD_INJECT \
    -append_partition 2 0xef "$T/partition.img" -appended_part_as_gpt \
    -o "$T/base.iso" "$T/tree" >"$T/build.log" 2>&1 || {
        cat "$T/build.log" >&2; exit 1;
    }
python3 - "$T" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
base = (p / 'base.iso').read_bytes()
sector = 2048
# Place every injection beyond the original image, outside file/ESP extents,
# but inside the validator's 1024-LBA search window.
lba = (len(base) + sector - 1) // sector
assert 18 <= lba < 990, 'synthetic image unexpectedly large'
prefix = base.ljust(lba * sector, b'\0')
descriptors = []
for i in range(16, 48):
    s = base[i * sector:(i + 1) * sector]
    assert len(s) == sector and s[1:7] == b'CD001\x01'
    descriptors.append(s)
    if s[0] == 255:
        break
else:
    raise AssertionError('missing descriptor terminator')
assert descriptors[0][0] == 1

def write(name, payload):
    (p / name).write_bytes(prefix + payload)

# Control proves appended, same-volume descriptor sets can be exempted.
write('same-volume.iso', b''.join(descriptors))
# Literal sector-aligned magic, with no descriptor header or valid set.
write('aligned-magic.iso', b'CD001'.ljust(sector, b'\0'))
# Correct header positioning/version, but missing PVD fields and terminator.
write('invalid-pvd.iso', b'\x01CD001\x01'.ljust(sector, b'\0'))
# Preserve all structural fields and the terminator; change only volume ID.
foreign = bytearray(b''.join(descriptors))
foreign[40:72] = b'OTHER_VOLUME'.ljust(32, b' ')
assert foreign[40:72] != descriptors[0][40:72]
write('different-volume.iso', foreign)
print(f'injections start at LBA {lba} (byte {lba * sector})')
PY
pass=0; fails=0
check() {
    local name="$1" expected="$2" rc=0
    AVALONOS_TEST_BUILD=0 "$ROOT/scripts/check-iso-unowned.sh" "$T/$name.iso" >"$T/out" 2>&1 || rc=$?
    if { [ "$expected" = accept ] && [ "$rc" = 0 ]; } ||
       { [ "$expected" = reject ] && [ "$rc" = 1 ] && grep -q 'ISO9660 data at offset' "$T/out"; }; then
        echo "ok    $name ($expected)"; pass=$((pass + 1))
    else
        echo "FAIL  $name (expected $expected, exit $rc)"
        head -12 "$T/out"; fails=$((fails + 1))
    fi
}
check base accept
check same-volume accept
check aligned-magic reject
check invalid-pvd reject
check different-volume reject
echo "vd-inject-test: $pass ok, $fails failed"
[ "$fails" = 0 ]
