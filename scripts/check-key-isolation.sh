#!/usr/bin/env bash
# Key isolation between release and QA test outputs (Code Security P-L11,
# hardened for P-L12: Master Chief 2026-11-14 17:43 CT "Fix it before release").
# A release must never carry or trust the TEST key; a test build trusts only
# the TEST key.
#   check-key-isolation.sh PATH...          deep content scan (below)
#   check-key-isolation.sh --raw FILE...    K2 only over the raw bytes of a
#                                           whole image (ISO, ESP): finds key
#                                           material outside any file, too
#   check-key-isolation.sh --gaps DIR       deep scan of ISO bytes outside any
#                                           file (check-iso-unowned.sh): no
#                                           file-format verdict at the top, but
#                                           any uninspectable format's magic fails
# Mode: release unless AVALONOS_TEST_BUILD=1. PATH may be a directory tree
# (an extracted ISO, a repo, a payload) or single files. Every file is
# inventoried by content, not by name; symlinks are never followed out of the
# artifact (a relative link that escapes it fails). FAILS on, for the key of
# the OTHER build kind ("foreign" key):
#   K1 a file, link or archive member named like the foreign key file
#   K2 foreign public-key material in any encoding: raw packet bytes, ASCII
#      armor (LF/CRLF, inside PGP messages incl. compressed packets), base64
#      without armor (any alignment, line breaks, quotes or URL-safe
#      alphabet), hex dumps (any case or separators); also base64 runs that
#      decode to compressed or archived key material
#   K3 the foreign key file name, fingerprint or key ID (16 or 8 hex digits)
#      as text in any case and with any spacing/separators, or (release) the
#      TEST UID; prose is exempt only under usr/share/doc/ inside an RPM
#      payload and in createrepo changelog/file-list metadata
#   K4 any RPM (found by its magic, any name, at any depth) unless rpm -K,
#      with a keyring holding ONLY this kind's key, reports every signature
#      OK and every signer is that key. Passing RPMs: their scriptlets,
#      triggers, file triggers, file names, link targets and dependencies
#      are scanned as text (K1-K3) and their payload is unpacked and scanned
#      (K1-K6). A failed RPM is never unpacked.
#   K5 any *.asc / *.sig that is not a public key, unless gpgv with ONLY this
#      kind's key verifies it over its sibling file
#   K6 containers: gzip, xz, LZMA-alone, bzip2 and zstd (incl. concatenated
#      streams), tar, cpio (newc/crc/odc, concatenated archives), zip/jar
#      (also appended to another file), ar/deb and RPM are unpacked and
#      every member is scanned like a file (up to 6 nested levels, 1 GiB per
#      layer; a nest that still has decodable structure, armor or carve magic
#      when the depth limit is reached fails closed). gzip/xz/zstd/bzip2 streams embedded anywhere in a file are
#      carved out and scanned. Formats that cannot be inspected (squashfs,
#      erofs, cramfs, ISO9660, FAT, ext*, 7z, rar, cab, xar, lz4, lzip, lzop,
#      compress, LUKS, disk images, encrypted zip) or a layer that cannot be
#      read completely FAIL -- unless the file is byte-identical (sha256) to
#      a file of the pinned upstream Fedora ISO (upstream-netinst.sha256,
#      generated from the ISO pinned in upstream.env; verify-iso (default, also
#      --full) proves those files identical to upstream; --quick skips that).
# No path is ever passed through a shell.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/avalonos-keys.sh
. "$ROOT/scripts/avalonos-keys.sh"
RAW=0; GAPS=0
case "${1:-}" in --raw) RAW=1; shift;; --gaps) GAPS=1; shift;; esac
[ $# -ge 1 ] || { echo "usage: $0 [--raw|--gaps] PATH..." >&2; exit 2; }
for t in python3 rpm rpmkeys rpm2cpio cpio gpg gpgv zstd; do
    command -v "$t" >/dev/null || { echo "check-key-isolation: missing tool $t" >&2; exit 2; }
done
if [ "${AVALONOS_TEST_BUILD:-0}" = 0 ]; then KIND=release; else KIND="test"; fi
[ -s "$ROOT/upstream-netinst.sha256" ] || { echo "check-key-isolation: missing $ROOT/upstream-netinst.sha256" >&2; exit 2; }
AV_RAW=$RAW AV_GAPS=$GAPS AV_TRUSTED="$ROOT/upstream-netinst.sha256" \
AV_KIND=$KIND AV_OWN_KEY="$AV_KEY_FILE" AV_OWN_PIN="$AV_KEY_PIN" AV_OWN_ID="$AV_KEY_ID" \
AV_FOREIGN_KEY="$ROOT/keys/$( [ "$KIND" = release ] && echo "$AV_TEST_NAME" || echo "$AV_PROD_NAME" )" \
AV_FOREIGN_NAME="$( [ "$KIND" = release ] && echo "$AV_TEST_NAME" || echo "$AV_PROD_NAME" )" \
AV_FOREIGN_NAME_RE="$AV_OTHER_NAME_RE" AV_FOREIGN_PIN="$AV_OTHER_PIN" AV_FOREIGN_ID="$AV_OTHER_ID" \
    exec python3 - "$@" <<'PY'
import base64, bz2, hashlib, lzma, os, re, shutil, stat, subprocess, sys, tarfile, tempfile, threading, zipfile, zlib
E = os.environ
KIND, OWN_PIN, OWN_ID = E["AV_KIND"], E["AV_OWN_PIN"].lower(), E["AV_OWN_ID"].lower()
F_NAME, F_PIN, F_ID = E["AV_FOREIGN_NAME"], E["AV_FOREIGN_PIN"].lower(), E["AV_FOREIGN_ID"].lower()
RAW = E["AV_RAW"] == "1"
GAPS = E.get("AV_GAPS") == "1"     # files are ISO bytes outside any file (check-iso-unowned.sh)
CHUNK, OVERLAP = 8 << 20, 256 << 10   # streamed reads; overlap covers any contiguous encoded key
LIMIT = 1 << 30                       # max bytes one layer/member may expand to
TOTAL = 32 << 30                      # max bytes decoded/extracted in one run (all layers)
MAXMEMBERS = 1_000_000                # max archive members/streams inspected in one run
DEPTH = 6                             # nested container levels
MAXCARVE = 4096                       # embedded streams tried per file
RUNMIN = 128                          # shortest encoded run (normalized chars) decoded
RUNCAP = 256 << 20                    # longest encoded run decoded (longer: cannot be inspected)
TIMEOUT = 1800                        # seconds per external tool call
TRUSTED = set()
for l in open(E["AV_TRUSTED"]):
    if not l.strip() or l.startswith("#"): continue
    if not re.fullmatch(r"[0-9a-f]{64}  \S.*\n?", l): sys.exit(f"check-key-isolation: malformed line in {E['AV_TRUSTED']}: {l[:80]!r}")
    TRUSTED.add(l[:64])
fails = []
def bad(msg): fails.append(msg); print(f"check-key-isolation ({KIND}): FAIL {msg}", file=sys.stderr)
class Found(Exception): pass
class Over(Exception): pass
class Broken(Exception): pass
used = {"bytes": 0, "members": 0}
def budget(nbytes=0, members=0):
    used["bytes"] += nbytes; used["members"] += members
    if used["bytes"] > TOTAL or used["members"] > MAXMEMBERS: raise Over("run budget exhausted")

# ---- foreign key material ---------------------------------------------------
ARMOR = re.compile(rb"-----BEGIN PGP ([A-Z ,0-9/]+)-----\r?\n(.*?)-----END PGP \1-----", re.S)
def dearmor_all(data):
    out = []
    for m in ARMOR.finditer(data.replace(b"\r\n", b"\n")):
        body = m.group(2)
        if b"\n\n" in body: body = body.split(b"\n\n", 1)[1]           # armor headers
        lines = [l.strip() for l in body.split(b"\n") if l.strip() and not l.strip().startswith(b"=")]
        try: out.append(base64.b64decode(b"".join(lines)))
        except Exception: pass                                         # junk: other views still apply
    return out

def packets(b):
    """(tag, body) of OpenPGP packets in b; partial body lengths are assembled."""
    i = 0
    while i < len(b):
        c = b[i]
        if not c & 0x80: return
        try:
            if c & 0x40:
                tag, i, body = c & 0x3f, i + 1, b""
                while True:
                    l0 = b[i]
                    if l0 < 192: ln, h, part = l0, 1, False
                    elif l0 < 224: ln, h, part = ((l0 - 192) << 8) + b[i+1] + 192, 2, False
                    elif l0 == 255: ln, h, part = int.from_bytes(b[i+1:i+5], "big"), 5, False
                    else: ln, h, part = 1 << (l0 & 0x1f), 1, True
                    body += b[i+h:i+h+ln]; i += h + ln
                    if not part: break
            else:
                tag = (c >> 2) & 0xf
                if c & 3 == 3: body, i = b[i+1:], len(b)              # indeterminate length
                else:
                    h = 1 + (1, 2, 4)[c & 3]; ln = int.from_bytes(b[i+1:i+h], "big")
                    body, i = b[i+h:i+h+ln], i + h + ln
        except IndexError: return
        yield tag, body

def key_snippets(path):
    """32 raw bytes of the first MPI of every public (sub)key packet in PATH."""
    data = open(path, "rb").read()
    snips = [body[10:42] for blob in (dearmor_all(data) or [data]) for tag, body in packets(blob)
             if tag in (6, 14) and len(body) > 48]
    if not snips: sys.exit(f"check-key-isolation: no key material in {path}")
    return snips

FOREIGN = key_snippets(E["AV_FOREIGN_KEY"])
# base64 of each snippet at all 3 byte alignments (padding chars dropped)
B64PATS = [base64.b64encode(t[:len(t) // 3 * 3]) for s in FOREIGN for t in (s, s[1:], s[2:])]
HEXPATS = [s.hex().encode() for s in FOREIGN]
B64CH = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
B64MAP = bytes.maketrans(b"-_", b"+/")
NONB64 = bytes(c for c in range(256) if c not in B64CH)
NONHEX = bytes(c for c in range(256) if c not in b"0123456789abcdef")
HEXTEXT = [F_PIN.encode(), F_ID.encode()]
SEP = r"[\s:._\-]{0,2}"
TEXT = re.compile(("|".join([E["AV_FOREIGN_NAME_RE"], r"(?<![0-9a-f])" + SEP.join(F_ID[-8:]) + r"(?![0-9a-f])"] +
                  (["AvalonOS TEST Build Signing Key", "rpm-signing-test@"] if KIND == "release" else []))).encode(), re.I)
# Encoded runs that are decoded and inspected: base64 (any alphabet variant,
# with line breaks, quotes, separators) and hex dumps (any case/separators).
B64RUN_CH = B64CH + b"=_- \t\r\n\v\f\"'\\,"
B64RUN = re.compile(rb"[A-Za-z0-9+/=_\-\s\"'\\,]{%d,}" % RUNMIN)
HEXRUN_CH = b"0123456789abcdefABCDEFxX \t\r\n:,.-'\"\\"
HEXRUN = re.compile(rb"(?:(?:0[xX])?[0-9A-Fa-f]{2}[\s:,.\-'\"\\]{0,4}){64,}")

def material(buf):
    """Name of the encoding in which buf carries foreign key material, or None."""
    if any(s in buf for s in FOREIGN): return "raw"
    if b"-----BEGIN PGP" in buf and any(s in blob for blob in dearmor_all(buf) for s in FOREIGN): return "armored"
    if any(p in buf.translate(B64MAP).translate(None, NONB64) for p in B64PATS): return "base64"
    if any(p in buf.lower().translate(None, NONHEX) for p in HEXPATS): return "hex"
    return None

def text_hit(buf):
    if TEXT.search(buf): return True
    h = buf.lower().translate(None, NONHEX)
    return any(p in h for p in HEXTEXT)

# ---- formats -----------------------------------------------------------------
COMPRESS = {"gzip": b"\x1f\x8b\x08", "xz": b"\xfd7zXZ\x00", "zstd": b"\x28\xb5\x2f\xfd", "bzip2": b"BZh"}
def is_lzma_alone(h):           # LZMA-alone has no magic: plausible header -> try it
    if len(h) < 13 or h[0] >= 225: return False
    size = int.from_bytes(h[5:13], "little")
    return size == 0xffffffffffffffff or 0 < size < (1 << 40)
def is_zlib(h): return len(h) >= 2 and h[0] & 0x0f == 8 and h[0] >> 4 <= 7 and (h[0] << 8 | h[1]) % 31 == 0 and not h[1] & 0x20
def is_tar(h):                  # any tar dialect (v7, ustar, gnu, pax): header checksum
    if len(h) < 512 or not h[0] or h[156:157] not in b"0123456\x00xgLKSAMNV": return False
    try: want = int(h[148:156].replace(b"\x00", b" ").strip() or b"x", 8)
    except ValueError: return False
    return want == sum(h[:148]) + 256 + sum(h[156:512])
UNINSPECTABLE = [   # (name, offset, magic)
    ("squashfs", 0, b"hsqs"), ("squashfs", 0, b"sqsh"), ("cramfs", 0, b"\x45\x3d\xcd\x28"),
    ("erofs", 1024, b"\xe2\xe1\xf5\xe0"), ("ISO9660", 0x8001, b"CD001"), ("7z", 0, b"7z\xbc\xaf\x27\x1c"),
    ("rar", 0, b"Rar!\x1a\x07"), ("cab", 0, b"MSCF\x00\x00\x00\x00"), ("xar", 0, b"xar!"),
    ("lz4", 0, b"\x04\x22\x4d\x18"), ("lz4", 0, b"\x02\x21\x4c\x18"), ("lzip", 0, b"LZIP"),
    ("lzop", 0, b"\x89LZO\x00\r\n\x1a\n"), ("compress", 0, b"\x1f\x9d"), ("LUKS", 0, b"LUKS\xba\xbe"),
    ("qcow", 0, b"QFI\xfb"), ("vmdk", 0, b"KDMV"), ("vhdx", 0, b"vhdxfile"), ("dmg", 0, b"koly"),
    ("cpio (binary)", 0, b"\xc7\x71\x00\x00"), ("MS compound file", 0, b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1"),
]
# Embedded anywhere (long magics only, so random hits are negligible): fail
# unless the whole file is a pinned upstream file.
EMBED_BAD = {b"7z\xbc\xaf\x27\x1c": "7z", b"Rar!\x1a\x07": "rar", b"\x89LZO\x00\r\n\x1a\n": "lzop",
             b"LUKS\xba\xbe": "LUKS", b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1": "MS compound file", b"vhdxfile": "vhdx"}
# P-L13: these distinctive container magics fail at any offset in whole
# files, not only in --gaps. Do not promote short/common UNINSPECTABLE
# magics (e.g. dmg "koly", binary cpio) — they false-positive in text and
# binaries. ISO9660 stays gaps-only. --gaps still uses the full list.
EMBED_BAD.update({
    b"hsqs": "squashfs", b"sqsh": "squashfs",
    b"\x04\x22\x4d\x18": "lz4", b"\x02\x21\x4c\x18": "lz4",
    b"\xe2\xe1\xf5\xe0": "erofs",
})
if GAPS:   # unowned ISO bytes are no file format: any uninspectable format's magic in them fails
    EMBED_BAD.update({m: n for n, off, m in UNINSPECTABLE if len(m) >= 4})
CARVE = dict(COMPRESS); CARVE["zip-local"] = b"PK\x03\x04"
def detect(h):
    if h[:4] == b"\xed\xab\xee\xdb": return "rpm"
    for k, m in COMPRESS.items():
        if h.startswith(m) and (k != "bzip2" or len(h) >= 10 and h[3:4] in b"123456789" and h[4:10] in (b"1AY&SY", b"\x17rE8P\x90")): return k
    if h[:6] in (b"070701", b"070702", b"070707"): return "cpio"
    if is_tar(h): return "tar"
    if h[:4] in (b"PK\x03\x04", b"PK\x05\x06"): return "zip"
    if h[:8] == b"!<arch>\n": return "ar"
    for name, off, m in UNINSPECTABLE:
        if h[off:off + len(m)] == m: return "!" + name
    if len(h) >= 1104 and h[1080:1082] == b"\x53\xef" and h[1048] <= 6 and int.from_bytes(h[1100:1104], "little") in (0, 1):
        return "!ext2/3/4"
    if len(h) >= 512 and h[510:512] == b"\x55\xaa" and (h[54:59] in (b"FAT12", b"FAT16") or h[82:87] == b"FAT32"):
        return "!FAT"
    if is_lzma_alone(h): return "lzma"
    if is_zlib(h): return "zlib"
    if h[:1] in (b"\xa0", b"\xa1", b"\xa2", b"\xa3", b"\xc8"): return "pgpz"   # OpenPGP compressed-data packet?
    return None

def file_chunks(path, off=0):
    with open(path, "rb") as f:
        f.seek(off)
        while c := f.read(CHUNK): yield c

def _decomp(kind):
    if kind == "gzip": return zlib.decompressobj(31)
    if kind == "zlib": return zlib.decompressobj(15)
    if kind == "deflate": return zlib.decompressobj(-15)
    if kind == "xz": return lzma.LZMADecompressor(lzma.FORMAT_XZ, memlimit=LIMIT)
    if kind == "lzma": return lzma.LZMADecompressor(lzma.FORMAT_ALONE, memlimit=LIMIT)
    return bz2.BZ2Decompressor()

def inflate(chunks, kind, out):
    """Decompress one layer (incl. concatenated streams of the same kind) into
    file out, at most LIMIT bytes. Raises Over/Broken AFTER writing what it could."""
    total = 0
    def put(b):
        nonlocal total
        total += len(b); budget(len(b))
        if total > LIMIT: raise Over(f"{kind} layer expands beyond {LIMIT >> 20} MiB")
        out.write(b)
    if kind == "zstd":
        p = subprocess.Popen(["zstd", "-dcq"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        def feed():
            try:
                for c in chunks: p.stdin.write(c)
            except (BrokenPipeError, ValueError, OSError): pass
            finally:
                try: p.stdin.close()
                except Exception: pass
        t = threading.Thread(target=feed, daemon=True); t.start()
        try:
            while b := p.stdout.read(CHUNK): put(b)
        except Over:
            p.kill(); raise
        t.join(TIMEOUT)
        if p.wait(TIMEOUT) != 0: raise Broken("zstd: bad or truncated data")
        return
    magic, d, pending, it = COMPRESS.get(kind), _decomp(kind), b"", iter(chunks)
    try:
        while True:
            if not pending:
                pending = next(it, None)
                if pending is None: break
            if d.eof:                                   # concatenated stream of the same kind?
                rest = pending.lstrip(b"\x00")
                if not rest: pending = b""; continue
                if not (magic and rest.startswith(magic)): return   # trailing bytes: scanned raw and carved
                d, pending = _decomp(kind), rest
            if kind in ("gzip", "zlib", "deflate"):
                put(d.decompress(pending, CHUNK))
                while d.unconsumed_tail and not d.eof: put(d.decompress(d.unconsumed_tail, CHUNK))
                while not d.eof and (b := d.decompress(b"", CHUNK)): put(b)
            else:
                put(d.decompress(pending, CHUNK))
                while not d.eof and not d.needs_input: put(d.decompress(b"", CHUNK))
            pending = d.unused_data if d.eof else b""
        if not d.eof: raise Broken(f"{kind}: truncated")
    except lzma.LZMAError as e:
        if "emory" in str(e): raise Over(f"{kind}: needs more than {LIMIT >> 20} MiB of memory")
        raise Broken(f"{kind}: {e}")
    except (zlib.error, OSError, EOFError, ValueError, MemoryError) as e:
        raise Broken(f"{kind}: {e}")

# ---- scanning ------------------------------------------------------------------
tmp = tempfile.mkdtemp(prefix="keyiso.")
nrpm = 0

def spill(prefix):
    fd, p = tempfile.mkstemp(dir=tmp, prefix=prefix)
    return os.fdopen(fd, "wb"), p

def decode_stream(chunks, kind, label, text_ok, depth, fatal):
    """Decode one stream and scan its output. A stream that decodes completely
    is real: inspection obligations inside it are then always fatal. A stream
    that does not decode is fatal only if the caller says so (fatal=True:
    recognised by structure, not by a short magic)."""
    f, p = spill("layer.")
    err = None
    try:
        with f: inflate(chunks, kind, f)
    except Over as e: err = ("over", str(e))
    except Broken as e: err = ("broken", str(e))
    if os.path.getsize(p) or not err:
        scan_file(p, f"{label}[{kind}]", text_ok, depth + 1, fatal=fatal or not err)
    os.unlink(p)
    if err and (err[0] == "over" or fatal): bad(f"{label}: {kind} data that cannot be decompressed completely ({err[1]}); cannot be inspected")

def scan_blob(blob, label, text_ok, depth):
    """Decoded run content: check it, and inspect it as a file if it has structure."""
    if (why := material(blob)): raise Found(f"{label}: foreign public-key material ({why})")
    structured = (detect(blob[:65536]) or any(m in blob for m in CARVE.values())
                  or any(m in blob for m in EMBED_BAD) or b"-----BEGIN PGP" in blob)
    if structured:
        # P-L15: do not skip remaining structure at the depth limit (fail closed
        # inside scan_file when depth exceeds DEPTH).
        f, p = spill("dec.")
        with f: f.write(blob)
        budget(len(blob))
        scan_file(p, label, text_ok, depth + 1, fatal=False)
        os.unlink(p)

def scan_runs(runbuf, label, text_ok, depth, kind):
    rx = B64RUN if kind == "base64" else HEXRUN
    for m in rx.finditer(runbuf):
        r = m.group(0)
        if kind == "base64":
            n = r.translate(B64MAP).translate(None, NONB64)
            if len(n) < RUNMIN: continue
            for k in range(4):
                s = n[k:]; s = s[:len(s) // 4 * 4]
                try: blob = base64.b64decode(s)
                except Exception: continue
                scan_blob(blob, f"{label}[base64]", text_ok, depth)
        else:
            n = re.sub(rb"0[xX]", b"", r).lower().translate(None, NONHEX)
            for k in range(2):
                s = n[k:]; s = s[:len(s) // 2 * 2]
                try: blob = bytes.fromhex(s.decode())
                except ValueError: continue
                scan_blob(blob, f"{label}[hex]", text_ok, depth)

class Runs:
    """Encoded runs across chunks: a run reaching the end of a chunk is carried
    into the next one (always all run characters); decoded when it ends."""
    def __init__(self, kind, chars): self.kind, self.chars, self.carry, self.n = kind, chars, [], 0
    def feed(self, c, label, text_ok, depth):
        t = c.rstrip(self.chars)
        if t:
            scan_runs(b"".join(self.carry) + t, label, text_ok, depth, self.kind)
            self.carry, self.n = [c[len(t):]], len(c) - len(t)
        else:
            self.carry.append(c); self.n += len(c)
            if self.n > RUNCAP: raise Over(f"{self.kind} run longer than {RUNCAP >> 20} MiB")
    def end(self, label, text_ok, depth):
        if self.n: scan_runs(b"".join(self.carry), label, text_ok, depth, self.kind)

def scan_file(path, label, text_ok, depth=0, fatal=True, payload_rel=None):
    """K1-K6 over one regular file. fatal=False for speculative content (carved
    or decoded, not yet shown to be a real stream): format errors are then
    ignored; findings always FAIL."""
    if depth > DEPTH:
        # P-L15: fail closed whenever the depth limit is exceeded, including
        # speculative (fatal=False) layers. Remaining structure must not be skipped.
        bad(f"{label}: encoding nest exceeds depth {DEPTH}; cannot be inspected")
        return
    sha = hashlib.sha256(); head = b""; prev = b""; base = 0; carves = set(); embed_bad = set()
    runs = [Runs("base64", B64RUN_CH), Runs("hex", HEXRUN_CH)]
    utf16 = None
    try:
        for c in file_chunks(path):
            sha.update(c)
            if len(head) < 65536: head += c[:65536 - len(head)]
            if utf16 is None:
                h4 = head[:4096]
                utf16 = h4[:2] in (b"\xff\xfe", b"\xfe\xff") or (len(h4) > 64 and h4.count(b"\x00") * 10 > len(h4) * 3 and not detect(h4))
            buf = prev + c
            if (why := material(buf)): raise Found(f"{label}: foreign public-key material ({why})")
            if not text_ok and text_hit(buf): raise Found(f"{label}: foreign key name/fingerprint/ID/UID as text")
            if not RAW:
                if b"-----BEGIN PGP" in buf:
                    for blob in dearmor_all(buf): pgp_blob(blob, label + "[armor]", text_ok, depth)
                rc = c.replace(b"\x00", b"") if utf16 else c
                for r in runs: r.feed(rc, label, text_ok, depth)
                lo = max(0, len(prev) - 16)
                for mg in list(CARVE.values()) + list(EMBED_BAD):
                    i = buf.find(mg, lo)
                    while i >= 0 and len(carves) <= MAXCARVE:
                        off = base - len(prev) + i
                        if mg in EMBED_BAD: embed_bad.add((off, EMBED_BAD[mg]))
                        elif off > 0 or mg == CARVE["zip-local"]: carves.add(off)
                        i = buf.find(mg, i + 1)
            base += len(c)
            prev = buf[-OVERLAP:]
        if not RAW:
            for r in runs: r.end(label, text_ok, depth)
    except Found as e:
        bad(str(e)); return
    except Over as e:
        bad(f"{label}: {e}; cannot be inspected"); return
    if RAW: return
    if depth == 0 and sha.hexdigest() in TRUSTED: return   # Fedora's pinned bytes: K2/K3 above is enough
    if GAPS and depth == 0:
        # R7-B1: ISO9660 magic is allowed only at CD001 offsets of structurally
        # validated volume-descriptor sectors (AV_GAP_VD_OFFSETS). Gap filenames
        # are gap-<absolute-start>-<length>; no wider LBA bound.
        vd_ok = set()
        _vdp = os.environ.get("AV_GAP_VD_OFFSETS")
        if _vdp:
            with open(_vdp, encoding="ascii") as _vdf:
                vd_ok = {int(l) for l in _vdf if l.strip()}
        gm = re.match(r"gap-(\d+)-", os.path.basename(path))
        start = int(gm.group(1)) if gm else None
        embed_bad = {(o, n) for o, n in embed_bad
                     if not (n == "ISO9660" and start is not None and (start + o) in vd_ok)}
    for off, name in sorted(embed_bad)[:1]:
        bad(f"{label}: {name} data at offset {off} (not inspectable, not a pinned upstream file); cannot be inspected")
    kind = detect(head)
    if GAPS and depth == 0 and kind and kind.startswith("!"): kind = None     # judged by the embedded-magic search
    def fmt_err(msg):
        if fatal: bad(f"{label}: {msg}; cannot be inspected")
    try:
        if kind == "rpm":
            check_rpm(path, label, depth)
        elif kind in ("gzip", "xz", "zstd", "bzip2"):
            decode_stream(file_chunks(path), kind, label, text_ok, depth, fatal)
        elif kind in ("lzma", "zlib"):               # no real magic: speculative until it decodes
            decode_stream(file_chunks(path), kind, label, text_ok, depth, False)
        elif kind == "pgpz":
            if os.path.getsize(path) > LIMIT: fmt_err("OpenPGP data beyond the size limit")
            else:
                with open(path, "rb") as f: pgp_blob(f.read(), label, text_ok, depth)
        elif kind in ("tar", "cpio", "zip", "ar"):
            try: members(path, kind, label, text_ok, depth, fatal, payload_rel)
            except Broken as e: fmt_err(f"{kind} archive that cannot be read completely ({e})")
        elif kind and kind.startswith("!"):
            fmt_err(f"{kind[1:]} data (not an inspectable format, not a pinned upstream file)")
        if kind != "zip" and os.path.getsize(path) > 22:
            with open(path, "rb") as f:
                f.seek(max(0, os.path.getsize(path) - 66000)); t = f.read()
            if b"PK\x05\x06" in t:                                     # zip appended to another file
                try: members(path, "zip", label + "[appended zip]", text_ok, depth, False, payload_rel)
                except Broken: pass
        if len(carves) > MAXCARVE:
            bad(f"{label}: more than {MAXCARVE} embedded streams; cannot be inspected"); return
        skip = rpm_payload_offset(path) if kind == "rpm" else None   # inspected by check_rpm (with its doc rules)
        for off in sorted(carves):
            if off != skip: carve(path, off, label, text_ok, depth)
        # P-L13 / P-I16: mid-file zlib has no unique magic. Carve in --gaps
        # and in files up to 64 MiB (larger files still get start-of-file
        # zlib via detect). In --gaps, walk the whole gap in 64 MiB windows
        # with 8 KiB overlap so a stream past the first 64 MiB is still
        # carved. Only headers that trial-inflate to >= 16 bytes are carved.
        zwin = 64 << 20
        zoverlap = 8192
        # RPM payloads are unpacked and scanned as files; skip the RPM wrapper.
        size = os.path.getsize(path)
        if kind != "rpm" and (GAPS or size <= zwin):
            zoffs, zseen, zpos = [], set(), 0
            while zpos < size:
                with open(path, "rb") as zf:
                    zf.seek(zpos)
                    zdata = zf.read(zwin)
                if not zdata:
                    break
                for zm in re.finditer(b"[\x08\x18\x28\x38\x48\x58\x68\x78]", zdata):
                    i = zm.start()
                    abs_off = zpos + i
                    if abs_off in zseen:
                        continue
                    if abs_off == 0 or i + 1 >= len(zdata) or not is_zlib(zdata[i:i+2]):
                        continue
                    try:
                        zd = zlib.decompressobj(15)
                        zout = zd.decompress(zdata[i:i+4096], 64)
                    except zlib.error:
                        continue
                    if len(zout) >= 16:
                        zoffs.append(abs_off)
                        zseen.add(abs_off)
                    if len(zoffs) > MAXCARVE:
                        bad(f"{label}: more than {MAXCARVE} embedded zlib streams; cannot be inspected"); return
                if zpos + len(zdata) >= size:
                    break
                zpos += zwin - zoverlap
            for off in zoffs:
                if off != skip:
                    decode_stream(file_chunks(path, off), "zlib", f"{label}@{off}", text_ok, depth, False)
    except Over as e:
        bad(f"{label}: {e}; cannot be inspected")

def rpm_payload_offset(path):
    """Byte offset of the payload of an RPM (lead, signature header, padding, header)."""
    with open(path, "rb") as f:
        off = 96
        for pad in (True, False):
            f.seek(off); h = f.read(16)
            if len(h) < 16 or h[:3] != b"\x8e\xad\xe8": return None
            n, size = int.from_bytes(h[8:12], "big"), int.from_bytes(h[12:16], "big")
            off += 16 + 16 * n + size
            if pad: off += (-off) % 8
    return off

ZIP_METHODS = {8: "deflate", 12: "bzip2", 14: "lzma-zip", 93: "zstd", 95: "xz"}
def carve(path, off, label, text_ok, depth):
    with open(path, "rb") as f:
        f.seek(off); h = f.read(1024)
    if h.startswith(b"PK\x03\x04"):                 # any ZIP local entry, also in concatenated/orphaned zips
        if len(h) < 30: return
        flags, method = int.from_bytes(h[6:8], "little"), int.from_bytes(h[8:10], "little")
        csize = int.from_bytes(h[18:22], "little")
        nlen, xlen = int.from_bytes(h[26:28], "little"), int.from_bytes(h[28:30], "little")
        name = h[30:30 + nlen]
        if not (0 < nlen <= 512 and int.from_bytes(h[4:6], "little") <= 63 and all(32 <= ch < 127 or ch >= 128 for ch in name)):
            return                                   # not a plausible local header
        member_name(name.decode("utf-8", "replace"), label, False)
        if flags & 1: bad(f"{label}: encrypted zip entry {name!r} at {off}; cannot be inspected"); return
        data = off + 30 + nlen + xlen
        if method == 0:
            if csize and csize != 0xffffffff and csize <= LIMIT:
                with open(path, "rb") as f:
                    f.seek(data); blob = f.read(csize)
                budget(len(blob)); scan_blob(blob, f"{label}@{off}[zip entry]", text_ok, depth)
            return
        k = ZIP_METHODS.get(method)
        if not k: bad(f"{label}: zip entry {name!r} at {off} uses compression method {method}; cannot be inspected"); return
        if k == "lzma-zip":                           # zip LZMA: 4-byte header + props; give up cleanly
            bad(f"{label}: zip entry {name!r} at {off} uses LZMA; cannot be inspected"); return
        decode_stream(file_chunks(path, data), k, f"{label}@{off}!{name.decode('utf-8', 'replace')}", text_ok, depth, False)
        return
    k = next((k for k, m in COMPRESS.items() if h.startswith(m)), None)
    if k: decode_stream(file_chunks(path, off), k, f"{label}@{off}", text_ok, depth, False)

def pgp_blob(blob, label, text_ok, depth):
    """OpenPGP compressed-data packets (any nesting) in blob: decompress, inspect."""
    for tag, body in packets(blob):
        if tag != 8 or not body: continue
        algo = body[0]
        if algo == 0: scan_blob(body[1:], f"{label}[pgp]", text_ok, depth); continue
        k = {1: "deflate", 2: "zlib", 3: "bzip2"}.get(algo)
        if not k: continue
        decode_stream(iter([body[1:]]), k, f"{label}[pgp]", text_ok, depth, False)

def member_name(name, label, text_ok):
    base = os.path.basename(name.rstrip("/"))
    nb = os.fsencode(name) if isinstance(name, str) else name
    if base == F_NAME: bad(f"{label}: foreign key file name {name}")
    elif text_hit(nb) or material(nb): bad(f"{label}: member name {name} names or encodes the foreign key")

def copy_member(src, prefix):
    f, p = spill(prefix)
    n = 0
    with f:
        while b := src.read(CHUNK):
            n += len(b); budget(len(b))
            if n > LIMIT: raise Over(f"archive member beyond {LIMIT >> 20} MiB")
            f.write(b)
    return p

def members(path, kind, label, text_ok, depth, fatal, payload_rel):
    # Archive members are files again: no prose exemption is inherited.
    def one(name, p):
        budget(members=1)
        member_name(name, label, text_ok)
        scan_file(p, f"{label}!{name}", False, depth + 1, fatal)
        os.unlink(p)
    if kind == "tar":
        try:
            with tarfile.open(path, "r:") as t:
                for m in t:
                    member_name(m.name, label, text_ok)
                    if m.issym() or m.islnk():
                        if text_hit(os.fsencode(m.linkname)) or material(os.fsencode(m.linkname)):
                            bad(f"{label}!{m.name}: link target names or encodes the foreign key")
                        continue
                    if not m.isreg(): continue
                    one(m.name, copy_member(t.extractfile(m), "tar."))
        except (tarfile.TarError, EOFError, OSError) as e: raise Broken(str(e))
    elif kind == "zip":
        try:
            with zipfile.ZipFile(path) as z:
                for i in z.infolist():
                    if i.is_dir(): member_name(i.filename, label, text_ok); continue
                    if i.flag_bits & 1: raise Broken(f"encrypted member {i.filename}")
                    with z.open(i) as s: one(i.filename, copy_member(s, "zip."))
        except (zipfile.BadZipFile, NotImplementedError, RuntimeError, EOFError, OSError, ValueError) as e: raise Broken(str(e))
    elif kind == "ar":
        with open(path, "rb") as f:
            if f.read(8) != b"!<arch>\n": raise Broken("bad ar magic")
            while (h := f.read(60)):
                if len(h) < 60 or h[58:60] != b"`\n": raise Broken("bad ar header")
                name = h[:16].decode("latin-1").strip().rstrip("/")
                try: size = int(h[48:58].decode().strip() or 0)
                except ValueError: raise Broken("bad ar size")
                if size > LIMIT: raise Over("ar member beyond the size limit")
                data = f.read(size)
                if len(data) < size: raise Broken("truncated ar member")
                if size & 1: f.read(1)
                fo, p = spill("ar.")
                with fo: fo.write(data)
                budget(size); one(name, p)
    else:   # cpio, possibly several archives back to back (initramfs)
        for name, mode, p, pos in cpio_entries(path):
            if p is None:                              # trailing non-cpio segment
                scan_file(pos, f"{label}@{name}", text_ok, depth + 1, fatal); os.unlink(pos); continue
            member_name(name, label, text_ok)
            if stat.S_ISLNK(mode):
                with open(p, "rb") as f: tgt = f.read()
                os.unlink(p)
                if text_hit(tgt) or material(tgt): bad(f"{label}!{name}: link target names or encodes the foreign key")
                continue
            if not stat.S_ISREG(mode): os.unlink(p); continue
            one(name, p)

def cpio_entries(path):
    """(name, mode, member_file, offset) for every cpio entry; a non-cpio tail
    yields (offset, 0, None, tail_file)."""
    with open(path, "rb") as f:
        while True:
            pos = f.tell(); h = f.read(6)
            if not h: return
            if not h.strip(b"\x00"):                     # zero padding between archives
                f.seek(pos)
                while True:
                    blk = f.read(65536)
                    if not blk: return
                    nz = len(blk) - len(blk.lstrip(b"\x00"))
                    if nz < len(blk): f.seek(f.tell() - len(blk) + nz); break
                continue
            if h in (b"070701", b"070702"):
                hd = f.read(104)
                if len(hd) < 104: raise Broken("truncated cpio header")
                try: fsz, nsz, mode = int(hd[48:56], 16), int(hd[88:96], 16), int(hd[8:16], 16)
                except ValueError: raise Broken("bad cpio header")
                name = f.read(nsz).rstrip(b"\x00").decode("utf-8", "replace")
                f.seek((-(110 + nsz)) % 4, 1); pad = (-fsz) % 4
            elif h == b"070707":
                hd = f.read(70)
                if len(hd) < 70: raise Broken("truncated cpio header")
                try: mode, nsz, fsz = int(hd[12:18], 8), int(hd[53:59], 8), int(hd[59:70], 8)
                except ValueError: raise Broken("bad cpio header")
                name = f.read(nsz).rstrip(b"\x00").decode("utf-8", "replace"); pad = 0
            else:
                fo, p = spill("seg.")
                with fo:
                    f.seek(pos); n = 0
                    while b := f.read(CHUNK):
                        n += len(b); budget(len(b))
                        if n > LIMIT: raise Over("cpio tail beyond the size limit")
                        fo.write(b)
                yield pos, 0, None, p
                return
            if name == "TRAILER!!!":
                f.seek(pad, 1); continue
            if fsz > LIMIT: raise Over("cpio member beyond the size limit")
            fo, p = spill("cpio.")
            with fo:
                left = fsz
                while left:
                    b = f.read(min(left, CHUNK))
                    if not b: raise Broken("truncated cpio member")
                    fo.write(b); left -= len(b)
            budget(fsz)
            f.seek(pad, 1)
            yield name, mode, p, pos

def run(cmd, **kw):
    try: return subprocess.run(cmd, capture_output=True, timeout=TIMEOUT, **kw)
    except subprocess.TimeoutExpired: raise Over(f"{cmd[0]} timed out")

own_ring = os.path.join(tmp, "own.gpg")
subprocess.run(["gpg", "--batch", "--homedir", tmp, "--yes", "--dearmor", "-o", own_ring, E["AV_OWN_KEY"]], check=True, capture_output=True)
rpmdb = os.path.join(tmp, "rpmdb"); os.mkdir(rpmdb)
subprocess.run(["rpmkeys", "--dbpath", rpmdb, "--import", E["AV_OWN_KEY"]], check=True, capture_output=True)
# Every header tag is scanned as text except the prose ones (and the scripts,
# queried separately with their interpreters).
PROSE = {"CHANGELOGTEXT", "CHANGELOGNAME", "CHANGELOGTIME", "DESCRIPTION", "SUMMARY", "HEADERI18NTABLE"}
TAGS = [t for t in subprocess.run(["rpm", "--querytags"], capture_output=True, text=True, check=True).stdout.split() if t not in PROSE]
RPM_TEXT_QF = "".join(f"[%{{{t}}}\\n]" for t in TAGS)

def check_rpm(path, label, depth):
    global nrpm; nrpm += 1
    p = run(["rpmkeys", "--dbpath", rpmdb, "-Kv", "--", path], text=True)
    sigs = [l.strip() for l in p.stdout.splitlines() if "signature" in l.lower()]
    # rpm >= 6 prints the fingerprint / 16-hex key ID, rpm 4 an 8-hex key ID (Code Security P-I8)
    ids = [m.lower() for l in sigs for m in re.findall(r"key (?:ID|fingerprint):? ([0-9a-fA-F]{8,40})", l)]
    if not (p.returncode == 0 and sigs and len(ids) == len(sigs)
            and all(l.endswith(": OK") for l in sigs) and all(OWN_PIN.endswith(i) for i in ids)):
        who = ",".join(sorted(set(ids))) or "none"
        bad(f"{label}: RPM signatures [{who}] not all OK by {OWN_ID} only ({KIND} key)"
            + (" -- signed by the foreign key" if any(F_PIN.endswith(i) for i in ids) else ""))
        return                       # never unpack a package that failed
    fo, tp = spill("rpmtext.")
    with fo:
        for args in (["--scripts", "--triggers", "--filetriggers"], ["--qf", RPM_TEXT_QF]):
            q = run(["rpm", "-qp", "--nosignature", "--nodigest", *args, "--", path])
            if q.returncode != 0: bad(f"{label}: RPM header unreadable"); return
            fo.write(q.stdout)
    scan_file(tp, f"{label} (scriptlets/triggers/header)", False, depth + 1)
    os.unlink(tp)
    # Payload: rpm2cpio into a file, names checked, then unpacked with cpio.
    fo, cp = spill("payload.")
    with fo:
        try: q = subprocess.run(["rpm2cpio", path], stdout=fo, stderr=subprocess.DEVNULL, timeout=TIMEOUT)
        except subprocess.TimeoutExpired: raise Over("rpm2cpio timed out")
    budget(os.path.getsize(cp))
    if q.returncode != 0: bad(f"{label}: payload unreadable"); os.unlink(cp); return
    try:
        names = []
        for name, mode, mp, pos in cpio_entries(cp):
            if mp is None: os.unlink(pos); bad(f"{label}: payload has data after the cpio archive"); continue
            os.unlink(mp); names.append(name)
    except Broken as e:
        bad(f"{label}: payload unreadable ({e})"); os.unlink(cp); return
    badn = [n for n in names if n.startswith("/") or ".." in n.split("/")]
    if badn: bad(f"{label}: payload path escapes ({badn[0]})"); os.unlink(cp); return
    x = tempfile.mkdtemp(dir=tmp)
    with open(cp, "rb") as fi:
        try: r = subprocess.run(["cpio", "-id", "--quiet", "--no-absolute-filenames"], stdin=fi, cwd=x,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=TIMEOUT)
        except subprocess.TimeoutExpired: raise Over("cpio timed out")
    os.unlink(cp)
    if r.returncode != 0: bad(f"{label}: payload unreadable")
    else: scan(x, label + " payload", payload=True, depth=depth + 1)
    shutil.rmtree(x, ignore_errors=True)

def check_sig(path, rel, label):
    target = path.rsplit(".", 1)[0]
    if not os.path.isfile(target): bad(f"{label}: {rel}: detached signature without its signed file"); return
    p = run(["gpgv", "--keyring", own_ring, "--status-fd", "1", "--", path, target], text=True)
    st = p.stdout.split("\n")
    if any(F_ID.upper() in l.upper() or F_PIN.upper() in l.upper() for l in st):
        bad(f"{label}: {rel} signed by the foreign key"); return
    good = [l.split() for l in st if l.startswith("[GNUPG:] VALIDSIG ")]
    if p.returncode != 0 or not good or any(OWN_PIN.upper() not in (g[2].upper(), g[-1].upper()) for g in good) \
       or any(l.startswith(("[GNUPG:] BADSIG", "[GNUPG:] ERRSIG", "[GNUPG:] NO_PUBKEY", "[GNUPG:] EXPKEYSIG", "[GNUPG:] REVKEYSIG")) for l in st):
        bad(f"{label}: {rel} is not a valid signature by {OWN_PIN} alone")

META = re.compile(r"(.*/)?repodata/[0-9a-f]{64}-(other|filelists)\.xml(\.(gz|zst|xz|bz2))?")
def scan(root, label, payload=False, depth=0):
    root = os.path.realpath(root)
    def walk_err(e): bad(f"{label}: cannot read {getattr(e, 'filename', '?')} ({e.strerror}); cannot be inspected")
    for dp, dns, fns in os.walk(root, followlinks=False, onerror=walk_err):
        for n in sorted(dns + fns):
            p = os.path.join(dp, n); rel = os.path.relpath(p, root)
            st = os.lstat(p)
            if n == F_NAME: bad(f"{label}: foreign key file name {rel}")
            elif text_hit(os.fsencode(rel)) or material(os.fsencode(rel)): bad(f"{label}: path {rel} names or encodes the foreign key")
            if stat.S_ISLNK(st.st_mode):
                t = os.readlink(p)
                if text_hit(os.fsencode(t)) or material(os.fsencode(t)): bad(f"{label}: link {rel} -> {t} names or encodes the foreign key")
                if not t.startswith("/"):
                    r = os.path.realpath(os.path.join(dp, t))
                    if not (r == root or r.startswith(root + os.sep)): bad(f"{label}: link {rel} escapes the artifact")
                continue
            if stat.S_ISDIR(st.st_mode): continue
            if not stat.S_ISREG(st.st_mode):
                if not payload: bad(f"{label}: {rel} is not a regular file, directory or symlink")
                continue
            if RAW:
                scan_file(p, f"{label}: {rel}", True); continue
            try:
                with open(p, "rb") as f: head = f.read(64)
            except OSError as e: bad(f"{label}: cannot read {rel} ({e.strerror})"); continue
            is_rpm = head[:4] == b"\xed\xab\xee\xdb"
            # Prose: non-executable docs inside an RPM payload and the createrepo
            # changelog/file-list metadata configure no trust (key material,
            # signatures and containers are still checked). RPM headers carry
            # spec prose (changelog); their other tags and scripts are scanned
            # separately as text (K4).
            text_ok = is_rpm or (rel.startswith("usr/share/doc/") and not st.st_mode & 0o111 if payload else
                                 bool(META.fullmatch(rel)))
            scan_file(p, f"{label}: {rel}", text_ok, depth, payload_rel=rel if payload else None)
            if n.endswith((".asc", ".sig")):
                with open(p, "rb") as f: blob = f.read(1 << 20)
                public = b"BEGIN PGP PUBLIC KEY BLOCK" in blob or any(t == 6 for t, _ in list(packets(blob))[:1])
                if not public: check_sig(p, rel, label)

try:
    for arg in sys.argv[1:]:
        if not os.path.lexists(arg): bad(f"{arg}: missing"); continue
        if os.path.isdir(arg) and not os.path.islink(arg): scan(arg, arg)
        else:
            d = tempfile.mkdtemp(dir=tmp); dst = os.path.join(d, os.path.basename(arg))
            shutil.copy2(arg, dst, follow_symlinks=False)
            base = arg.rsplit(".", 1)[0]
            if arg.endswith((".asc", ".sig")) and os.path.isfile(base): shutil.copy2(base, dst.rsplit(".", 1)[0])
            scan(d, arg)
except Over as e:
    bad(f"{e}; cannot be inspected completely")
finally:
    shutil.rmtree(tmp, ignore_errors=True)
if fails: sys.exit(1)
if RAW: print(f"check-key-isolation ({KIND}): OK (raw), no foreign key material in the image bytes")
else: print(f"check-key-isolation ({KIND}): OK, only {os.path.basename(E['AV_OWN_KEY'])} ({OWN_PIN}) trusted; {nrpm} RPMs signed by it alone")
PY
