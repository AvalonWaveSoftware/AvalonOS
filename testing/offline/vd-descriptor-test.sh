#!/usr/bin/env bash
# Standalone R7-B1 unit tests: bash + Python 3 only; no ISO tooling or repo.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec python3 - "$ROOT" <<'PY'
import ast
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
# Execute the production heredoc verbatim, rather than a copied validator.
source = (root / "scripts/check-iso-unowned.sh").read_text()
marker = 'python3 - "$ISO" "$T/vd-offsets" "$T/sa" "$p2s" <<\'PY\'\n'
assert source.count(marker) == 1, "validator heredoc changed; update extraction"
validator = source.split(marker, 1)[1].split('\nPY\n', 1)[0]
# Reuse the actual --gaps exemption block without initializing the unrelated
# key/RPM scanner. Fail loudly if its structure changes instead of skipping it.
source = (root / "scripts/check-key-isolation.sh").read_text()
scanner = source.split("exec python3 - \"$@\" <<'PY'\n", 1)[1].rsplit('\nPY', 1)[0]
tree = ast.parse(scanner)
filters = [n for n in ast.walk(tree) if isinstance(n, ast.If)
           and ast.unparse(n.test) == 'GAPS and depth == 0']
assert len(filters) == 1, "gap exemption block changed; update extraction"
gap_filter = compile(ast.Module(body=filters, type_ignores=[]), '<production gap filter>', 'exec')
S = 2048
checks = 0

def check(condition, name):
    global checks
    if not condition:
        raise AssertionError(name)
    checks += 1
    print('ok   ' + name)

def both(s, off, value, width):
    s[off:off + 2 * width] = value.to_bytes(width, 'little') + value.to_bytes(width, 'big')

def descriptor(kind):
    s = bytearray(S)
    s[:7] = bytes([kind]) + b'CD001\x01'
    return s

def pvd(space=128):
    s = descriptor(1)
    s[40:72] = b'AVALONOS_SYNTHETIC'.ljust(32, b' ')
    both(s, 80, space, 4)
    both(s, 120, 1, 2)
    both(s, 128, S, 2)
    both(s, 132, 10, 4)
    s[156] = 34
    both(s, 158, 20, 4)
    s[181] = 2
    return s

def image(primary=None, extra=None):
    data = bytearray(128 * S)
    data[16*S:17*S] = pvd() if primary is None else primary
    data[17*S:18*S] = descriptor(255)
    for lba, sector in (extra or {}).items():
        data[lba*S:(lba+1)*S] = sector
    return data

with tempfile.TemporaryDirectory(prefix='avalonos-vd-') as tmp:
    tmp = Path(tmp)
    iso, offsets = tmp / 'synthetic.iso', tmp / 'vd-offsets'

    # Fedora-like xorriso 1.5.8 layout: partition offset 16, GPT p1 start 64,
    # ESP at 4000 (512-byte sectors). Candidates: 16, 32, 64, 80.
    FAKE_SA = (
        "Partition offset   : 16\n"
        "GPT start and size :   1  64  1000\n"
        "GPT start and size :   2  4000  100\n"
    )
    sa_path = tmp / "sa"

    def validate(data, sa=None, esp_start=4000):
        iso.write_bytes(data)
        sa_path.write_text(FAKE_SA if sa is None else sa)
        offsets.unlink(missing_ok=True)
        result = subprocess.run(
            [sys.executable, '-c', validator, str(iso), str(offsets), str(sa_path), str(esp_start)],
            capture_output=True, text=True)
        assert result.returncode == 0, result.stderr or result.stdout
        return {int(x) for x in offsets.read_text().split()} if offsets.exists() else set()

    def allowed(*lbas):
        return {lba*S + 1 for lba in lbas}

    check(validate(image()) == allowed(16, 17), 'proper PVD + terminator accepted with exact offsets')
    # Other supported descriptor types within a terminated set.
    check(validate(image(extra={17: descriptor(0), 18: descriptor(2),
                                19: descriptor(3), 20: descriptor(255)})) == allowed(16,17,18,19,20),
          'supported intermediate descriptor types accepted')
    for name, off, value in [
        ('bad PVD type', 0, b'\x04'), ('version != 1', 6, b'\x02'),
        ('missing CD001', 1, bytes(5)), ('wrong CD001', 1, b'XD001'),
        ('volume-space endian mismatch', 84, b'\x00\x00\x00\x7f'),
        ('block-size endian mismatch', 130, b'\x04\x00'),
        ('root extent endian mismatch', 162, b'\x00\x00\x00\x15'),
        ('path-size endian mismatch', 136, b'\x00\x00\x00\x0b'),
        ('volume-set-size endian mismatch', 122, b'\x00\x02'),
        ('missing root directory flag', 181, b'\x00'),
    ]:
        bad = pvd()
        bad[off:off+len(value)] = value
        check(not validate(image(bad)), name + ' rejected')
    bad = pvd()
    both(bad, 128, 1024, 2)
    check(not validate(image(bad)), 'consistent block size != 2048 rejected')
    bad = pvd()
    both(bad, 132, 0, 4)
    check(not validate(image(bad)), 'empty path table rejected')
    check(not validate(image(extra={17: bytes(S)})), 'unterminated set rejected')
    check(not validate(image(extra={i: descriptor(2) for i in range(17, 49)})),
          'set without terminator within 32 sectors rejected')
    check(not validate(image()[:17*S]), 'EOF before terminator rejected')
    for off, value in [(0, b'\x04'), (6, b'\x02'), (1, b'XD001')]:
        bad = descriptor(255)
        bad[off:off+len(value)] = value
        check(not validate(image(extra={17: bad})), f'invalid terminator field {off} rejected')

    extra = {32: pvd(), 33: descriptor(255), 64: pvd(96), 65: descriptor(255),
             80: pvd(112), 81: descriptor(255)}
    check(validate(image(extra=extra)) == allowed(16,17,32,33,64,65,80,81),
          'nonidentical valid PVD sets at LBA 64/80 accepted')
    bad = pvd(96)
    bad[40:72] = b'OTHER_VOLUME'.ljust(32, b' ')
    check(validate(image(extra={64: bad, 65: descriptor(255)})) == allowed(16,17),
          'additional set with mismatched volume id rejected')
    # P-L16: a valid same-volume set outside the layout-derived candidates
    # is not exempted (this is the S1/appended-ISO case).
    check(validate(image(extra={50: pvd(96), 51: descriptor(255)})) == allowed(16,17),
          'valid same-volume set at non-candidate LBA 50 not exempted')
    # With no system-area data, only the principal set at 16 is a candidate.
    check(validate(image(extra=extra), sa="") == allowed(16,17),
          'empty system-area report accepts only the principal set')
    # P-L17 fixture: validator offset list includes 64 and 80 when the
    # layout-derived candidates include those starts and the sets validate.
    offs = validate(image(extra=extra))
    check(offs == allowed(16,17,32,33,64,65,80,81)
          and allowed(64,65,80,81).issubset(offs),
          'P-L17 fixture: validated offsets include LBA 64 and 80')

    data = image()
    bare = 70*S + 123
    data[bare:bare+5] = b'CD001'
    valid = validate(data)
    check(valid == allowed(16,17) and bare not in valid, 'bare CD001 creates no validated offset')
    # Execute the real gap exemption with synthetic scanner detections and
    # absolute gap filenames, testing the contract with AV_GAP_VD_OFFSETS.
    os.environ['AV_GAP_VD_OFFSETS'] = str(offsets)
    def filtered(start, hits, name=None, depth=0):
        env = dict(GAPS=True, depth=depth, os=os, re=re,
                   path=str(tmp / (name or f'gap-{start}-2048')),
                   embed_bad=set(hits))
        exec(gap_filter, env)
        return env['embed_bad']
    check(filtered(16*S, {(1, 'ISO9660')}) == set(), 'validated magic exempted in --gaps filter')
    check(filtered(70*S, {(123, 'ISO9660')}) == {(123, 'ISO9660')}, 'bare magic rejected by --gaps filter')
    check(filtered(16*S, {(2, 'ISO9660')}) == {(2, 'ISO9660')}, 'adjacent offset is not exempted')
    check(filtered(16*S, {(1, 'squashfs')}) == {(1, 'squashfs')}, 'other format at validated offset is not exempted')
    check(filtered(16*S, {(1, 'ISO9660')}, name='ordinary-file') == {(1, 'ISO9660')},
          'filename without absolute gap start is not exempted')
    check(filtered(16*S, {(1, 'ISO9660')}, depth=1) == {(1, 'ISO9660')},
          'nested content is not exempted')
print(f'vd-descriptor-test: {checks} passed')
PY
