#!/usr/bin/env bash
# Offline check for QA r6 FAIL 2 (box lines drawn as Č/à/á on UEFI).
#   console-font-test.sh [FONTDIR]     FONTDIR default /usr/lib/kbd/consolefonts
# A Linux VT cell stores a glyph INDEX. On UEFI the GPU driver takes the
# console over from simpledrm after boot; fbcon then uses a kernel built-in
# font (CP437 order, default CP437 Unicode map) until the configured font is
# loaded again, possibly after the greeter / first-boot TUI has drawn. Cells
# drawn before keep their index, so the configured font must have every CP437
# character at its CP437 index. Checks:
#  1. the console font in the kickstart (vconsole.conf) and in
#     avalonos-console-setup is one font, with no fallback to another font;
#  2. that PSF font maps every printable CP437 character (incl. all box
#     drawing characters) to its CP437 glyph index;
#  3. every non-ASCII character the greeter (tuigreet borders) and the
#     first-boot TUI (avalonos-make-user) draw is in the font.
#  4. negative: the r6 font ter-v32n fails check 2 (proves the check bites).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FONTDIR="${1:-/usr/lib/kbd/consolefonts}"
fail=0
ks_fonts="$(grep -oE 'FONT="[^"]+"' "$ROOT/kickstart/AvalonOS.ks" | sort -u || true)"
cs_fonts="$(grep -oE '^FONT=[A-Za-z0-9._-]+' "$ROOT/overlay/usr/bin/avalonos-console-setup" | sort -u || true)"
[ "$(echo "$ks_fonts" | wc -l)" = 1 ] || { echo "FAIL kickstart sets more than one console font: $ks_fonts"; fail=1; }
font="${ks_fonts#FONT=\"}"; font="${font%\"}"
[ "$cs_fonts" = "FONT=$font" ] || { echo "FAIL avalonos-console-setup font ($cs_fonts) != kickstart vconsole font ($font)"; fail=1; }
n_setfont="$(grep -cE '^[^#]*setfont ' "$ROOT/overlay/usr/bin/avalonos-console-setup" || true)"
# shellcheck disable=SC2016  # literal $FONT
if ! grep -qE '^[^#]*setfont "\$FONT" ' "$ROOT/overlay/usr/bin/avalonos-console-setup" || [ "$n_setfont" != 1 ]; then
    echo "FAIL avalonos-console-setup must call setfont once, with \$FONT only (no other-order fallback)"; fail=1
fi
grep -q 'udevadm settle' "$ROOT/overlay/usr/bin/avalonos-console-setup" \
    || { echo "FAIL avalonos-console-setup does not wait for pending device events"; fail=1; }
for u in greetd.service.d/10-avalonos.conf avalonos-firstboot-user.service; do
    grep -q 'ExecStartPre=-\?/usr/bin/avalonos-console-setup' "$ROOT/overlay/usr/lib/systemd/system/$u" \
        || { echo "FAIL $u does not run avalonos-console-setup before the TUI"; fail=1; }
done
# Run the real helper with stub commands and a fake VT (idea from the Codex
# review on codex/uefi-boxchars): it must load exactly $font on tty1, once.
S="$(mktemp -d)"; trap 'rm -rf "$S"' EXIT
for c in setfont python3 setvtrgb udevadm; do printf '#!/bin/sh\necho "%s $*" >> "%s/calls"\n' "$c" "$S" > "$S/$c"; chmod +x "$S/$c"; done
: > "$S/tty1"; sed "s#^VT=/dev/tty1#VT=$S/tty1#" "$ROOT/overlay/usr/bin/avalonos-console-setup" > "$S/setup"
PATH="$S:/usr/bin:/bin" sh "$S/setup" >/dev/null 2>&1 || true
calls="$(grep -E '^(setfont|udevadm) ' "$S/calls" 2>/dev/null || true)"
[ "$calls" = "udevadm settle --timeout=15
setfont $font -C $S/tty1" ] || { echo "FAIL avalonos-console-setup run with stubs: expected settle then 'setfont $font -C tty1', got: ${calls//$'\n'/; }"; fail=1; }
check_font() {  # FONTFILE -> 0 if CP437-ordered and covers the TUI characters
    python3 - "$1" "$ROOT/overlay/usr/bin/avalonos-make-user" <<'PY'
import gzip, struct, sys
d = open(sys.argv[1], "rb").read()
if d[:2] == b"\x1f\x8b": d = gzip.decompress(d)
if d[:4] == b"\x72\xb5\x4a\x86":
    _, _, hs, flags, n, bpg, _, _ = struct.unpack("<8I", d[:32]); tab, sep, term, enc = d[hs + n * bpg:], b"\xfe", b"\xff", "utf-8"
elif d[:2] == b"\x36\x04":
    n = 512 if d[2] & 1 else 256; flags = d[2] & 2; tab = d[4 + n * d[3]:]; sep, term, enc = b"\xfe\xff", b"\xff\xff", "utf-16-le"
else: sys.exit("not a PSF font")
if not flags: print("  no Unicode table"); sys.exit(1)
m, i = {}, 0
for g in range(n):
    j = tab.index(term, i)
    while (j - i) % (2 if enc == "utf-16-le" else 1): j = tab.index(term, j + 1)
    for ch in tab[i:j].split(sep)[0].decode(enc, "replace"): m.setdefault(ch, g)
    i = j + len(term)
bad = [(k, c) for k in range(32, 256) if k != 127 for c in [bytes([k]).decode("cp437")] if m.get(c) != k]
need = set("┌─┐│└┘") | {c for c in open(sys.argv[2], encoding="utf-8").read() if ord(c) > 127}
miss = sorted(c for c in need if c not in m)
for k, c in bad[:8]: print(f"  {c!r} (U+{ord(c):04X}) is glyph {m.get(c)}, CP437 index {k:#04x}")
if bad: print(f"  {len(bad)} CP437 characters off their CP437 index")
if miss: print("  missing characters:", " ".join(f"U+{ord(c):04X}" for c in miss))
sys.exit(1 if bad or miss else 0)
PY
}
f="$FONTDIR/$font.psf.gz"; [ -f "$f" ] || f="$FONTDIR/$font.psf"
if [ ! -f "$f" ]; then echo "FAIL font $font not found in $FONTDIR"; fail=1
elif check_font "$f"; then echo "ok   $font: CP437 glyph order, has every TUI character"
else echo "FAIL $font: not CP437-ordered or missing TUI characters"; fail=1; fi
neg="$FONTDIR/ter-v32n.psf.gz"
if [ -f "$neg" ]; then
    if check_font "$neg" >/dev/null; then echo "FAIL negative: ter-v32n (r6 font) passes the order check"; fail=1
    else echo "ok   negative: ter-v32n (r6 font) is rejected"; fi
fi
if [ "$fail" = 0 ]; then echo "console-font-test: OK"; else echo "console-font-test: FAILED"; exit 1; fi
