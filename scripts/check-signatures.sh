#!/usr/bin/env bash
# Verify an AvalonOS RPM repo (or signed release bundle) against the AvalonOS
# public key ONLY. Trust chain (P-L8):
#   repodata/repomd.xml.asc --gpgv--> repomd.xml --sha256--> primary/filelists/other
#   primary.xml --sha256--> every package file; every package: `rpm -K` in a
#   throwaway rpmdb that holds just the pinned key.
# The repo's file set must be EXACTLY repomd.xml(.asc) + the metadata files it
# lists + the packages primary.xml lists: anything extra, missing, a symlink,
# a special file or an extra directory fails the check.
# Every byte is first snapshotted (regular files only, opened O_NOFOLLOW) into
# a private directory; all checks run on that snapshot and --copy-to copies
# from it, so a source changed during or after the check cannot reach DEST.
# Key: the AvalonOS key of this build kind only (scripts/avalonos-keys.sh,
# P-L11): release = production key, AVALONOS_TEST_BUILD=1 = TEST key. A KEYFILE
# with any other fingerprint is refused, so a release check can never be
# satisfied by the test key (or a test check by the production key).
#   check-signatures.sh REPODIR [KEYFILE]          verify
#   check-signatures.sh --copy-to DEST REPODIR [KEYFILE]
#                                                  verify, then copy ONLY the
#                                                  verified files to DEST (new)
set -euo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST=""
if [ "${1:-}" = --copy-to ]; then DEST="${2:?}"; shift 2; fi
SRC="${1:?usage: $0 [--copy-to DEST] REPODIR [KEYFILE]}"
# shellcheck source=scripts/avalonos-keys.sh
. "$ROOT/scripts/avalonos-keys.sh"
KEY="${2:-$AV_KEY_FILE}"
PIN="$AV_KEY_PIN"
MAX_XML=$((512 * 1024 * 1024))  # decompressed primary.xml limit (bytes)
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
chmod 700 "$t"
[ -d "$SRC" ] && [ ! -L "$SRC" ] || { echo "check-signatures: $SRC is not a directory (or is a symlink)" >&2; exit 1; }
[ -z "$DEST" ] || DEST="$(realpath -m -- "$DEST")"
[ -z "$DEST" ] || [ ! -e "$DEST" ] || { echo "check-signatures: $DEST exists" >&2; exit 1; }
# 0. Snapshot the key and the bundle; everything below reads only $t.
DIR="$t/snap"
python3 - "$SRC" "$DIR" "$KEY" "$t/key.asc" > "$t/inventory" <<'PY' || { echo "check-signatures: FAILED (cannot snapshot $SRC)"; exit 1; }
import os, re, stat, sys
src, dst, key, keycopy = sys.argv[1:5]
SAFE = re.compile(r"[A-Za-z0-9_+~^-][A-Za-z0-9._+~^-]*")  # also keeps the inventory one token per field
def copy_regular(fd, out):
    with os.fdopen(fd, "rb") as i, open(out, "xb") as o:
        if not stat.S_ISREG(os.fstat(i.fileno()).st_mode):
            return False
        while chunk := i.read(1 << 20):
            o.write(chunk)
    return True
kfd = os.open(key, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
if not copy_regular(kfd, keycopy):
    sys.exit(f"{key}: not a regular file")
os.mkdir(dst, 0o700)
def walk(rel):
    sfd = os.open(os.path.join(src, rel) if rel else src, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        names = sorted(os.listdir(sfd))
        if rel:
            print("dir", rel)
        for n in names:
            r = f"{rel}/{n}" if rel else n
            if not SAFE.fullmatch(n):
                print("bad", ascii(r).replace(" ", "\\x20")); continue
            st = os.stat(n, dir_fd=sfd, follow_symlinks=False)
            if stat.S_ISDIR(st.st_mode):
                os.mkdir(os.path.join(dst, r), 0o700); walk(r)
            elif stat.S_ISREG(st.st_mode):
                fd = os.open(n, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=sfd)
                print("file" if copy_regular(fd, os.path.join(dst, r)) else "bad", r)
            else:
                print("bad", r)  # symlink, fifo, socket, device
    finally:
        os.close(sfd)
walk("")
PY
rpmkeys --dbpath "$t/db" --import "$t/key.asc"
fp="$(rpm --dbpath "$t/db" -q gpg-pubkey --qf '%{VERSION}\n' | tr 'A-F' 'a-f')"
[ "$fp" = "$PIN" ] || { echo "check-signatures: key fingerprint $fp is not the pinned $PIN" >&2; exit 1; }
fail=0
# 1. repomd.xml signature (the trust anchor for everything below): gpgv must
#    report a VALIDSIG by the pinned primary key and no bad/unknown signature.
mkdir -m 700 "$t/g"
gpg --batch --quiet --homedir "$t/g" --dearmor --output "$t/k.gpg" "$t/key.asc"
if [ -f "$DIR/repodata/repomd.xml.asc" ] && [ -f "$DIR/repodata/repomd.xml" ] \
    && gpgv --status-fd 3 --keyring "$t/k.gpg" "$DIR/repodata/repomd.xml.asc" "$DIR/repodata/repomd.xml" \
        2>"$t/gpgv.log" 3>"$t/gpgv.status" \
    && awk -v pin="$PIN" '$2=="VALIDSIG" && (tolower($3)==pin || tolower($NF)==pin) {ok=1}
                          $2 ~ /^(BADSIG|ERRSIG|EXPSIG|EXPKEYSIG|REVKEYSIG)$/ {bad=1} END {exit !(ok && !bad)}' "$t/gpgv.status"; then
    echo "OK    repodata/repomd.xml.asc: good signature from $PIN"
else
    echo "FAIL  repodata/repomd.xml.asc"; sed 's/^/      /' "$t/gpgv.log" 2>/dev/null || true
    echo "check-signatures: FAILED (repomd.xml not signed by the pinned key)"; exit 1
fi
# 2. Metadata (sha256-checked BEFORE it is decompressed or parsed) and the
#    package list, with strict structure and path rules.
python3 - "$DIR" "$MAX_XML" > "$t/expect" <<'PY' || { echo "FAIL  repodata rejected"; echo "check-signatures: FAILED"; exit 1; }
import hashlib, re, subprocess, sys, xml.etree.ElementTree as ET
d, limit = sys.argv[1], int(sys.argv[2])
R = "{http://linux.duke.edu/metadata/repo}"; C = "{http://linux.duke.edu/metadata/common}"
SAFE = re.compile(r"[A-Za-z0-9_+~^-][A-Za-z0-9._+~^-]*")
seen = set()
def href_of(el, ns):
    loc = el.find(ns + "location")
    if loc is None or set(loc.attrib) - {"href"}:  # no xml:base or other attributes
        sys.exit("location element missing or with extra attributes")
    h = loc.get("href", "")
    parts = h.split("/")
    if not h or not all(SAFE.fullmatch(p) for p in parts):
        sys.exit(f"unsafe href {h!r}")
    if h.lower() in seen:
        sys.exit(f"duplicate href {h!r}")
    seen.add(h.lower()); return h
def sha_of(el, ns):
    ck = el.find(ns + "checksum")
    if ck is None or ck.get("type") != "sha256" or not re.fullmatch(r"[0-9a-f]{64}", (ck.text or "").strip()):
        sys.exit("checksum missing or not sha256")
    return ck.text.strip()
def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(1 << 20): h.update(chunk)
    return h.hexdigest()
root = ET.parse(d + "/repodata/repomd.xml").getroot()
if root.tag != R + "repomd": sys.exit("repomd.xml: wrong root element")
types, primary = set(), None
for data in root:
    if data.tag in (R + "revision", R + "tags"): continue
    if data.tag != R + "data": sys.exit(f"repomd.xml: unexpected element {data.tag}")
    ty = data.get("type")
    if not ty or ty in types: sys.exit(f"repomd.xml: missing or duplicate data type {ty!r}")
    types.add(ty)
    href, want = href_of(data, R), sha_of(data, R)
    try:
        got = sha256(d + "/" + href)
    except OSError:
        sys.exit(f"{href}: missing (listed in signed repomd.xml)")
    if got != want: sys.exit(f"{href}: sha256 differs from the signed repomd.xml")
    print("meta", want, href)
    if ty == "primary": primary = href
if not primary: sys.exit("no primary metadata")
tool = {"zst": ["zstd", "-dc"], "gz": ["gzip", "-dc"], "xz": ["xz", "-dc"]}.get(primary.rsplit(".", 1)[-1])
if tool:
    p = subprocess.Popen(tool + ["--", d + "/" + primary], stdout=subprocess.PIPE)
    raw = p.stdout.read(limit + 1); p.stdout.close(); p.kill(); rc = p.wait()
    if len(raw) > limit: sys.exit("primary metadata too large when decompressed")
    if rc not in (0, -9): sys.exit("primary metadata does not decompress")
else:
    with open(d + "/" + primary, "rb") as f: raw = f.read(limit + 1)
    if len(raw) > limit: sys.exit("primary metadata too large")
if b"<!DOCTYPE" in raw or b"<!ENTITY" in raw: sys.exit("primary metadata: DTD/entities not allowed")
proot = ET.fromstring(raw)
if proot.tag != C + "metadata": sys.exit("primary: wrong root element")
n = 0
for pkg in proot:
    if pkg.tag != C + "package": sys.exit(f"primary: unexpected element {pkg.tag}")
    print("pkg", sha_of(pkg, C), href_of(pkg, C)); n += 1
if str(n) != proot.get("packages", str(n)): sys.exit("primary: package count mismatch")
PY
n=0
{ echo repodata/repomd.xml; echo repodata/repomd.xml.asc; } > "$t/allowed"
while read -r kind sum rel; do
    echo "$rel" >> "$t/allowed"
    if [ "$kind" = meta ]; then echo "OK    $rel: sha256 matches repomd.xml"; continue; fi
    [ -f "$DIR/$rel" ] || { echo "FAIL  $rel: missing (listed in signed metadata)"; fail=1; continue; }
    [ "$(sha256sum < "$DIR/$rel" | cut -d' ' -f1)" = "$sum" ] || { echo "FAIL  $rel: sha256 differs from the signed metadata"; fail=1; continue; }
    n=$((n + 1))
    rc=0; out="$(rpm --dbpath "$t/db" -K "$DIR/$rel" 2>&1)" || rc=$?
    case "$rc:$out" in
        "0:$DIR/$rel: digests signatures OK") echo "OK    ${out#"$DIR"/}" ;;
        *) echo "FAIL  ${out#"$DIR"/} (rpm -K exit $rc)"; fail=1 ;;
    esac
done < "$t/expect"
[ "$n" -gt 0 ] || { echo "FAIL  no packages in primary.xml"; fail=1; }
# 3. Nothing else may be in the bundle: no extra file, no symlink or special
#    file, no directory that holds no listed file.
sort -u "$t/allowed" > "$t/allowed.s"
awk '$1=="file" {print $2}' "$t/inventory" | sort > "$t/present"
extra="$(comm -23 "$t/present" "$t/allowed.s")"
if [ -n "$extra" ]; then echo "$extra" | sed 's/^/FAIL  not covered by the signed metadata: /'; fail=1; fi
bad="$(awk '$1=="bad" {print $2}' "$t/inventory")"
if [ -n "$bad" ]; then echo "$bad" | sed 's/^/FAIL  symlink or special file: /'; fail=1; fi
awk -F/ '{p=""; for (i=1;i<NF;i++) {p = p (i>1?"/":"") $i; print p}}' "$t/allowed.s" | sort -u > "$t/dirs.ok"
xdirs="$(awk '$1=="dir" {print $2}' "$t/inventory" | sort | comm -23 - "$t/dirs.ok")"
if [ -n "$xdirs" ]; then echo "$xdirs" | sed 's/^/FAIL  directory not covered by the signed metadata: /'; fail=1; fi
if [ "$fail" = 0 ] && [ -n "$DEST" ]; then
    mkdir -- "$DEST" || { echo "check-signatures: cannot create $DEST (exists?)" >&2; exit 1; }
    if (cd "$DIR" && xargs -d '\n' cp --parents -t "$DEST" --) < "$t/allowed.s"; then
        echo "check-signatures: copied the $(wc -l < "$t/allowed.s") verified files to $DEST"
    else
        rm -rf -- "$DEST"; echo "check-signatures: copy failed; $DEST removed" >&2; exit 1
    fi
fi
echo "check-signatures: $n RPMs, $([ $fail = 0 ] && echo PASS || echo FAILED)"
exit "$fail"
