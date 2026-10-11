#!/usr/bin/env bash
# Negative + positive tests for the release/test key split (Code Security
# P-L11). Offline; needs a release repo signed with the production key and a
# QA test repo signed with the TEST key (both with repodata + repomd.xml.asc):
#   testing/offline/key-isolation-test.sh RELEASE_REPO TEST_REPO [UNSIGNED_REPO]
# Every N-case must be REJECTED by scripts/check-key-isolation.sh (the check
# verify-iso.sh runs on the whole ISO and build-iso.sh on the payload) and,
# where it applies, by scripts/check-signatures.sh. The P-L12 cases (L*, R*,
# A*, V* from the Codex coverage review) hide the TEST key deliberately (encodings, compression, containers,
# RPM scriptlets/payloads) and add files under /avalonos.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REL="$(realpath "${1:?release repo}")"; TST="$(realpath "${2:?test repo}")"; UNS="${3:-}"
KI="$ROOT/scripts/check-key-isolation.sh"; CS="$ROOT/scripts/check-signatures.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fails=0
ok()  { echo "ok    $*"; pass=$((pass+1)); }
nok() { echo "FAIL  $*"; fails=$((fails+1)); }
accept() { local d="$1"; shift; if "$@" >"$T/out" 2>&1; then ok "$d"; else nok "$d"; sed 's/^/      /' "$T/out" | head -5; fi; }
# A negative case passes only if the command exits 1 AND says why in the
# expected words (a missing tool, exit 2 or a crash is not a rejection).
reject() {
    local d="$1"; shift; local rc=0 pat
    case " $* " in
        *" $KI "*) pat='^check-key-isolation \((release|test)\): FAIL |AVALONOS_TEST_BUILD must be 0 or 1' ;;
        *" $CS "*) pat='^FAIL |check-signatures: .*(not the pinned|FAIL)' ;;
        *) pat='must be 0 or 1|is not the key for' ;;
    esac
    "$@" >"$T/out" 2>&1 || rc=$?
    if [ "$rc" = 0 ]; then nok "$d (accepted)"
    elif ! grep -qE "$pat" "$T/out"; then nok "$d (exit $rc without the expected reason)"; sed 's/^/      /' "$T/out" | head -3
    else ok "$d -- $(grep -m1 -E "$pat" "$T/out" | sed 's/^check-key-isolation //' | cut -c1-110)"; fi
}
rel()  { AVALONOS_TEST_BUILD=0 "$@"; }
tst()  { AVALONOS_TEST_BUILD=1 "$@"; }
fresh() { rm -rf "$T/r"; cp -a "$1" "$T/r"; }

rel "$ROOT/scripts/render-kickstart.sh" "$T/rel.cfg" >/dev/null
tst "$ROOT/scripts/render-kickstart.sh" "$T/test.cfg" >/dev/null 2>&1
gpg --batch --homedir "$(mktemp -d -p "$T")" --dearmor < "$ROOT/keys/RPM-GPG-KEY-avalonos-test" > "$T/test-key.bin"

echo "== positive"
accept "P1 release repo, release mode"                        rel "$KI" "$REL"
accept "P2 test repo, test mode"                              tst "$KI" "$TST"
accept "P3 release kickstart, release mode"                   rel "$KI" "$T/rel.cfg"
accept "P4 test kickstart, test mode"                         tst "$KI" "$T/test.cfg"
accept "P5 check-signatures: release repo, production key"    rel "$CS" "$REL"
accept "P6 check-signatures: test repo, TEST key"             tst "$CS" "$TST"
echo "== release must never trust the TEST key"
fresh "$REL"; cp -p "$TST"/avalonos-hw-*.rpm "$T/r/"
reject "N1 release repo + one TEST-signed RPM"                rel "$KI" "$T/r"
fresh "$REL"; rm "$T/r"/avalonos-0.*.rpm; cp -p "$TST"/avalonos-0.*.rpm "$T/r/"
reject "N2 release repo with the TEST meta-package (ships the TEST key)" rel "$KI" "$T/r"
fresh "$REL"; cp "$ROOT/keys/RPM-GPG-KEY-avalonos-test" "$T/r/"
reject "N3 release tree + RPM-GPG-KEY-avalonos-test file"      rel "$KI" "$T/r"
fresh "$REL"; cp "$ROOT/keys/RPM-GPG-KEY-avalonos-test" "$T/r/notes.txt"
reject "N4 TEST key armored under an innocent name"           rel "$KI" "$T/r"
fresh "$REL"; cp "$T/test-key.bin" "$T/r/trusted.gpg"
reject "N5 TEST key as a binary keyring (.gpg)"               rel "$KI" "$T/r"
fresh "$REL"; mkdir -p "$T/r/odd dir"; cp "$ROOT/keys/RPM-GPG-KEY-avalonos-test" "$T/r/odd dir/a key"
reject "N6 TEST key in a path with spaces"                    rel "$KI" "$T/r"
fresh "$REL"; ln -s "$ROOT/keys/RPM-GPG-KEY-avalonos-test" "$T/r/link.asc"
reject "N7 symlink to the TEST key"                           rel "$KI" "$T/r"
fresh "$REL"; cp -p "$TST/repodata/repomd.xml.asc" "$T/r/repodata/repomd.xml.asc"
reject "N8 release repo with a TEST-signed repomd.xml.asc"    rel "$KI" "$T/r"
reject "N8b ... check-signatures too"                         rel "$CS" "$T/r"
sed 's/=f0aa82e5feb779364658a18d96508b1357fdab48$/=f2bc6934fb6501b6114177a7e221dd18ae8eaae9/' "$T/rel.cfg" > "$T/n9.cfg"
reject "N9 release kickstart pinning the TEST fingerprint"     rel "$KI" "$T/n9.cfg"
sed 's#gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-avalonos #gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-avalonos-test #' "$T/rel.cfg" > "$T/n10.cfg"
reject "N10 release kickstart with gpgkey= the TEST key file"  rel "$KI" "$T/n10.cfg"
printf 'pin %s\n' E221DD18AE8EAAE9 > "$T/n11.conf"
reject "N11 TEST short key ID in a config file"               rel "$KI" "$T/n11.conf"
reject "N12 the whole TEST repo in release mode"              rel "$KI" "$TST"
reject "N13 check-signatures: TEST repo against the production pin" rel "$CS" "$TST"
reject "N14 check-signatures: release mode handed the TEST key file" rel "$CS" "$TST" "$ROOT/keys/RPM-GPG-KEY-avalonos-test"
if [ -n "$UNS" ]; then
    fresh "$REL"; cp -p "$UNS"/avalonos-hw-*.rpm "$T/r/"
    reject "N15 release repo + an unsigned RPM"               rel "$KI" "$T/r"
fi
echo "== Codex review cases (binary/compressed/renamed material, links, paths)"
python3 - "$T/test-key.bin" "$T/test-primary.bin" <<'PY'
import sys
b = open(sys.argv[1], "rb").read(); c = b[0]
# first packet only (the primary public key; no UID, no self-signature)
if c & 0x40:
    l0 = b[1]; h, ln = (2, l0) if l0 < 192 else (3, ((l0 - 192) << 8) + b[2] + 192)
else:
    lt = c & 3; h = 1 + (1, 2, 4)[lt]; ln = int.from_bytes(b[1:h], "big")
open(sys.argv[2], "wb").write(b[:h + ln])
PY
fresh "$REL"; cp "$T/test-primary.bin" "$T/r/vendor.key"
reject "C1 TEST primary key packet only (no UID), binary, as vendor.key" rel "$KI" "$T/r"
fresh "$REL"; gzip -c < "$ROOT/keys/RPM-GPG-KEY-avalonos-test" > "$T/r/blob.dat"
reject "C2 gzip-compressed TEST key under any name"           rel "$KI" "$T/r"
fresh "$REL"; mkdir -p "$T/r/x"; cp "$TST"/avalonos-hw-*.rpm "$T/r/x/firmware.BIN"
reject "C3 TEST-signed RPM renamed (found by RPM magic)"      rel "$KI" "$T/r"
fresh "$REL"; ln -s ../../outside "$T/r/repodata/esc"
reject "C4 relative symlink escaping the artifact"            rel "$KI" "$T/r"
mkdir -p "$T/d/usr/share/doc/root/etc/yum.repos.d"; printf 'gpgkey=x\n# %s\n' f2bc6934fb6501b6114177a7e221dd18ae8eaae9 > "$T/d/usr/share/doc/root/etc/yum.repos.d/a.repo"
reject "C5 scan root under a usr/share/doc/ path gets no doc exemption" rel "$KI" "$T/d/usr/share/doc/root"
fresh "$TST"; gpg --batch --homedir "$(mktemp -d -p "$T")" --dearmor < "$ROOT/keys/RPM-GPG-KEY-avalonos" > "$T/r/vendor.key"
reject "C6 test mode: binary production key as vendor.key"    tst "$KI" "$T/r"
fresh "$REL"; mkdir -p "$T/r/extra"; cp -p "$TST/repodata/repomd.xml" "$T/r/extra/repomd.xml"; cp -p "$TST/repodata/repomd.xml.asc" "$T/r/extra/repomd.xml.asc"
reject "C7 a TEST-signed detached signature anywhere in the tree" rel "$KI" "$T/r"
mkdir -p "$T/iso/avalonos" "$T/iso/EFI/BOOT" "$T/iso/extra"; cp -a "$REL" "$T/iso/avalonos/repo"; cp "$ROOT/keys/RPM-GPG-KEY-avalonos-test" "$T/iso/extra/k"
reject "C8 ISO-shaped tree: TEST key in a non-AvalonOS directory" rel "$KI" "$T/iso"
echo "== Codex re-review cases"
fresh "$REL"; gzip -c < "$ROOT/keys/RPM-GPG-KEY-avalonos-test" | gzip -c > "$T/r/twice.dat"
reject "C9 TEST key gzip(gzip(...))"                           rel "$KI" "$T/r"
fresh "$REL"; xz -c "$T/test-primary.bin" | zstd -q -c > "$T/r/layers.bin"
reject "C10 TEST key packet in xz inside zstd"                rel "$KI" "$T/r"
fresh "$REL"; mkdir "$T/r/sig"; cp -p "$TST/repodata/repomd.xml" "$T/r/sig/data"; gpg --batch --homedir "$(mktemp -d -p "$T")" --dearmor < "$TST/repodata/repomd.xml.asc" > "$T/r/sig/data.asc"
reject "C11 binary (unarmored) TEST-key detached signature .asc" rel "$KI" "$T/r"
fresh "$REL"; mkdir "$T/r/sig"; echo hello > "$T/r/sig/data"; echo 'not a signature' > "$T/r/sig/data.sig"
reject "C12 malformed detached signature .sig"                rel "$KI" "$T/r"
fresh "$REL"; head -c 4096 /dev/urandom | gzip -c | head -c 2000 > "$T/r/cut.gz"
reject "C13 truncated gzip (cannot be inspected completely)"  rel "$KI" "$T/r"
fresh "$REL"; cp "$TST"/avalonos-hw-*.rpm "$T/r/pkg' ; touch INJECTED; #.rpm"
pushd "$T" >/dev/null || exit 1
reject "C14 RPM file name with shell metacharacters (TEST-signed)" rel "$KI" "$T/r"
popd >/dev/null || exit 1
if [ -e "$T/INJECTED" ]; then nok "C14b file name was executed by a shell"; else ok "C14b file name never reached a shell"; fi
fresh "$REL"; { printf -- '-----BEGIN PGP PUBLIC KEY BLOCK-----\r\nVersion: test\r\nComment: CRLF\r\n\r\n'; sed -n '/^$/,/^-----END/p' "$ROOT/keys/RPM-GPG-KEY-avalonos" | sed '1d' | sed 's/$/\r/'; } > "$T/r/own-crlf.asc"
accept "P7 production key, CRLF armor with headers, release mode" rel "$KI" "$T/r"
echo "== test builds trust only the TEST key"
fresh "$TST"; cp -p "$REL"/avalonos-hw-*.rpm "$T/r/"
reject "N16 test repo + one production-signed RPM"            tst "$KI" "$T/r"
fresh "$TST"; cp "$ROOT/keys/RPM-GPG-KEY-avalonos" "$T/r/"
reject "N17 test tree + production key file"                  tst "$KI" "$T/r"
reject "N18 the release repo in test mode"                    tst "$KI" "$REL"
reject "N19 release kickstart in test mode"                   tst "$KI" "$T/rel.cfg"
reject "N20 check-signatures test mode on the release repo"   tst "$CS" "$REL"
echo "== mode handling"
reject "N21 AVALONOS_TEST_BUILD=yes is refused"               env AVALONOS_TEST_BUILD=yes "$KI" "$REL"
reject "N22 render-kickstart AVALONOS_TEST_BUILD=true refused" env AVALONOS_TEST_BUILD=true "$ROOT/scripts/render-kickstart.sh" "$T/x.cfg"
reject "N23 sign-rpms: production fingerprint in test mode refused (no key needed)" \
    env AVALONOS_TEST_BUILD=1 AVALONOS_GPG_FPR=F0AA82E5FEB779364658A18D96508B1357FDAB48 bash -c '
        h=$(mktemp -d); mkdir -m700 $h/gnupg; : > $h/passphrase; chmod 600 $h/passphrase; mkdir $h/d; : > $h/d/x.rpm
        AVALONOS_SIGNING_HOME=$h "$0" --rpms $h/d' "$ROOT/scripts/sign-rpms.sh"
echo "== P-L12: hidden TEST key (encodings, compression, containers) in a release tree"
# rejectw DESC REASON-REGEX CMD...: exit 1 AND a FAIL line matching REASON.
rejectw() {
    local d="$1" why="$2"; shift 2; local rc=0
    "$@" >"$T/out" 2>&1 || rc=$?
    if [ "$rc" = 0 ]; then nok "$d (accepted)"
    elif [ "$rc" != 1 ] || ! grep -E 'FAIL ' "$T/out" | grep -qE "$why"; then nok "$d (exit $rc without '$why')"; sed 's/^/      /' "$T/out" | head -4
    else ok "$d -- $(grep -E 'FAIL ' "$T/out" | grep -m1 -E "$why" | sed 's/^check-key-isolation //; s/^check-avalonos-dir: //' | cut -c1-120)"; fi
}
K="$ROOT/keys/RPM-GPG-KEY-avalonos-test"; KB="$T/test-key.bin"
py() { python3 -c "$@"; }
fresh "$REL"; py 'import lzma,sys; open(sys.argv[2],"wb").write(lzma.compress(open(sys.argv[1],"rb").read(), format=lzma.FORMAT_ALONE))' "$KB" "$T/r/data.lzma"
rejectw "L1 TEST key in LZMA-alone (.lzma)" 'lzma\].*material' rel "$KI" "$T/r"
fresh "$REL"; py 'import lzma,sys; open(sys.argv[2],"wb").write(lzma.compress(open(sys.argv[1],"rb").read(), format=lzma.FORMAT_ALONE, filters=[{"id":lzma.FILTER_LZMA1,"lc":0,"lp":0,"pb":0,"dict_size":1<<16}]))' "$KB" "$T/r/blob"
rejectw "L2 LZMA-alone with unusual properties, no extension" 'lzma\].*material' rel "$KI" "$T/r"
fresh "$REL"; { printf '\x04\x22\x4d\x18'; head -c 512 /dev/zero; } > "$T/r/x.lz4"
rejectw "L3 lz4 frame (format the checker cannot unpack): fail closed" 'lz4 data .*cannot be inspected' rel "$KI" "$T/r"
fresh "$REL"; mkdir "$T/sq"; cp "$K" "$T/sq/k"; mksquashfs "$T/sq" "$T/r/fs.img" -quiet -noappend >/dev/null 2>&1
rejectw "L4 squashfs image not pinned upstream: fail closed" 'squashfs data .*not a pinned upstream file' rel "$KI" "$T/r"
fresh "$REL"; (cd "$T/sq" && 7z a -bd "$T/r/a.7z" k >/dev/null)
rejectw "L5 7z archive: fail closed" '7z data .*cannot be inspected' rel "$KI" "$T/r"
fresh "$REL"; base64 -w0 "$KB" > "$T/r/blob.txt"
rejectw "L6 bare base64, one line, no armor" 'material \(base64\)' rel "$KI" "$T/r"
fresh "$REL"; { echo 'K=""'; base64 -w 60 "$KB" | sed 's/.*/K="$K"'"'"'&'"'"'/'; } > "$T/r/setup.sh"
rejectw "L7 base64 split into quoted shell lines" 'material \(base64\)' rel "$KI" "$T/r"
fresh "$REL"; base64 -w0 "$KB" | tr '+/' '-_' | tr -d '=' > "$T/r/token"
rejectw "L8 URL-safe base64 without padding" 'material \(base64\)' rel "$KI" "$T/r"
fresh "$REL"; { printf 'payload = "'; xz -9c "$K" | base64 -w0; printf '"\n'; } > "$T/r/conf.py"
rejectw "L9 base64 of xz of the armored key (decoded base64 run)" 'base64\].*\[xz\]: .*material' rel "$KI" "$T/r"
fresh "$REL"; od -An -tx1 -v "$KB" | tr 'a-f' 'A-F' > "$T/r/dump.txt"
rejectw "L10 hex dump (od, upper case, spaced)" 'material \(hex\)' rel "$KI" "$T/r"
fresh "$REL"; printf 'trusted = F2BC 6934 FB65 01B6 1141  77A7 E221 DD18 AE8E AAE9\n' > "$T/r/a.conf"
rejectw "L11 spaced TEST fingerprint (gpg style)" 'fingerprint/ID' rel "$KI" "$T/r"
fresh "$REL"; printf 'fpr: f2:bc:69:34:fb:65:01:b6:11:41:77:a7:e2:21:dd:18:ae:8e:aa:e9\n' > "$T/r/b.yaml"
rejectw "L12 lower-case colon-separated TEST fingerprint" 'fingerprint/ID' rel "$KI" "$T/r"
fresh "$REL"; printf 'id="E221DD18""AE8EAAE9"\n' > "$T/r/c.sh"
rejectw "L13 TEST 16-hex key ID split by quotes" 'fingerprint/ID' rel "$KI" "$T/r"
fresh "$REL"; printf 'keyid 0xae8e-aae9\n' > "$T/r/d.cfg"
rejectw "L14 TEST 8-hex short key ID with a separator" 'fingerprint/ID' rel "$KI" "$T/r"
fresh "$REL"; py '
import base64,sys,zlib
k=open(sys.argv[1],"rb").read()
lit=bytes([0xcb])+bytes([255])+(len(k)+6).to_bytes(4,"big")+b"b\x00"+bytes(4)+k
z=b"\x02"+zlib.compress(lit,9)
pkt=bytes([0xc8,255])+len(z).to_bytes(4,"big")+z
open(sys.argv[2],"wb").write(pkt)
b=base64.encodebytes(pkt)
open(sys.argv[3],"wb").write(b"-----BEGIN PGP MESSAGE-----\n\n"+b+b"-----END PGP MESSAGE-----\n")' "$KB" "$T/r/msg.gpg" "$T/r/msg.txt"
rejectw "L15 OpenPGP compressed message (armored and binary) carrying the key" 'compressed|material' rel "$KI" "$T/r"
fresh "$REL"; mkdir -p "$T/tz/etc"; cp "$K" "$T/tz/etc/vendor"; (cd "$T/tz" && tar cf "$T/in.tar" etc && zip -q "$T/in.zip" "$T/in.tar" -j); { head -c 3000 /dev/urandom; cat "$T/in.zip"; } > "$T/r/image.png"
rejectw "L16 key in a tar inside a zip appended to another file" 'appended zip.*material' rel "$KI" "$T/r"
fresh "$REL"; mkdir -p "$T/ir1/kernel" "$T/ir2/etc"; echo microcode > "$T/ir1/kernel/ucode"; cp "$K" "$T/ir2/etc/k"
(cd "$T/ir1" && find . | cpio -o -H newc --quiet) > "$T/r/initrd.img"; (cd "$T/ir2" && find . | cpio -o -H newc --quiet | xz -c) >> "$T/r/initrd.img"
rejectw "L17 initramfs-style cpio + xz cpio carrying the key" 'initrd.*material' rel "$KI" "$T/r"
fresh "$REL"; { echo harmless | gzip -c; gzip -9nc < "$K"; } > "$T/r/two.gz"
rejectw "L18 key in a second (concatenated) gzip member" 'two.gz\[gzip\].*material' rel "$KI" "$T/r"
fresh "$REL"; { head -c 100000 /dev/urandom; xz -c "$K"; head -c 5000 /dev/urandom; } > "$T/r/firmware.bin"
rejectw "L19 xz stream embedded mid-file (carved)" 'firmware.bin@.*material' rel "$KI" "$T/r"
fresh "$REL"; xz -c "$K" > "$T/full.xz"; head -c $(( $(stat -c %s "$T/full.xz") - 12 )) "$T/full.xz" > "$T/r/cut.xz"
rejectw "L20 truncated xz: the layer fails closed" 'cut.xz: xz data that cannot be decompressed completely' rel "$KI" "$T/r"
fresh "$REL"; (cd "$T/tz" && tar cf - etc | xz -c > data.tar.xz && ar rc "$T/r/pkg.deb" data.tar.xz)
rejectw "L21 key in a .deb (ar > tar.xz) member" 'pkg.deb!data.tar.xz.*\[xz\].*material' rel "$KI" "$T/r"
fresh "$REL"; mkdir -p "$T/tn"; echo x > "$T/tn/RPM-GPG-KEY-avalonos-test"; (cd "$T/tn" && tar cf "$T/r/names.tar" .)
rejectw "L22 archive member named like the TEST key file" 'foreign key (file )?name' rel "$KI" "$T/r"
fresh "$REL"; printf '%s\n' "$(xxd -p "$KB" 2>/dev/null || od -An -tx1 -v "$KB" | tr -d ' \n')" | sed 's/../&:/g' > "$T/r/colon.hex"
rejectw "L23 hex with colons between bytes" 'material \(hex\)' rel "$KI" "$T/r"
fresh "$REL"; py 'import sys; d=open(sys.argv[1],"rb").read(); import base64; open(sys.argv[2],"w",encoding="utf-16").write(base64.b64encode(d).decode())' "$KB" "$T/r/u16.txt"
rejectw "L24 base64 in UTF-16 text" 'material \(base64\)' rel "$KI" "$T/r"

echo "== P-L12: TEST key inside RPMs signed by the build's own key (scriptlets, triggers, names, payload)"
# A throwaway PROBE key stands in for the production key in a COPY of the
# tree (scripts + keys); the checker code is the same file. No real key is used.
PR="$T/probe"; mkdir -p "$PR"; cp -a "$ROOT/scripts" "$ROOT/keys" "$ROOT/upstream-netinst.sha256" "$ROOT/upstream.env" "$PR/"
GH="$T/probe-gnupg"; mkdir -m 700 "$GH"
gpg --batch --homedir "$GH" --pinentry-mode loopback --passphrase '' --quick-gen-key 'AvalonOS PROBE key (negative tests only) <probe@invalid>' rsa2048 sign never >/dev/null 2>&1
PFPR="$(gpg --batch --homedir "$GH" --with-colons --list-keys | awk -F: '$1=="fpr"{print tolower($10); exit}')"
gpg --batch --homedir "$GH" --armor --export "$PFPR" > "$PR/keys/RPM-GPG-KEY-avalonos"
sed -i "s/^AV_PROD_PIN=.*/AV_PROD_PIN=$PFPR/" "$PR/scripts/avalonos-keys.sh"
PKI="$PR/scripts/check-key-isolation.sh"
mkrpm() { # NAME  SPEC-EXTRA [PREAMBLE-EXTRA]  (payload from $T/pl/NAME/)
    local n="$1" extra="$2" top="$T/rb-$1"; mkdir -p "$top/SPECS" "$T/pl/$n/etc/probe" "$T/pl/$n/usr/share/doc/probe-$n"
    cat > "$top/SPECS/p.spec" <<SPEC
Name: probe-$n
Version: 1
Release: 1
Summary: probe
License: MIT
BuildArch: noarch
${3:-}
%description
probe
%install
cp -a $T/pl/$n/. %{buildroot}/
%files
/etc/probe
/usr/share/doc/probe-$n
$extra
SPEC
    SOURCE_DATE_EPOCH=1791756588 rpmbuild -bb --quiet --define "_topdir $top" "$top/SPECS/p.spec" >/dev/null 2>&1 || { echo "rpmbuild $n failed"; return 1; }
    local f; f="$(find "$top/RPMS" -name '*.rpm' | head -1)"
    rpmsign --addsign --define "_gpg_name $PFPR" --define "_gpg_path $GH" "$f" >/dev/null 2>&1 || { echo "rpmsign $n failed"; return 1; }
    mkdir -p "$T/pr-$n"; cp "$f" "$T/pr-$n/"
}
mkrpm clean ''
accept "P8 control: clean RPM signed by the stand-in key passes (payload + scriptlets scanned)" rel "$PKI" "$T/pr-clean"
mkrpm post "%post
cat > /etc/pki/rpm-gpg/extra <<'K'
$(base64 -w 64 "$KB")
K"
rejectw "R1 %post writes the TEST key from base64" 'probe-post.*material \(base64\)' rel "$PKI" "$T/pr-post"
mkrpm pretrans '%pretrans -p <lua>
print("F2BC 6934 FB65 01B6 1141  77A7 E221 DD18 AE8E AAE9")'
rejectw "R2 %pretrans lua with the spaced TEST fingerprint" 'scriptlets.*fingerprint/ID' rel "$PKI" "$T/pr-pretrans"
mkrpm trig "%triggerin -- bash
cat <<'K' | rpmkeys --import /dev/stdin
$(cat "$K")
K"
rejectw "R3 %triggerin imports the armored TEST key" 'probe-trig.*material' rel "$PKI" "$T/pr-trig"
mkrpm ftrig "%filetriggerin -- /usr/lib
echo $(od -An -tx1 -v "$KB" | tr -d ' \n') | xxd -r -p > /tmp/k"
rejectw "R4 %filetriggerin with a hex dump of the TEST key" 'probe-ftrig.*material \(hex\)' rel "$PKI" "$T/pr-ftrig"
mkrpm prov '' 'Provides: RPM-GPG-KEY-avalonos-test'
rejectw "R5 Provides naming the TEST key file (header text, not prose)" 'scriptlets/triggers/header.*name/fingerprint' rel "$PKI" "$T/pr-prov"
mkdir -p "$T/pl/pay/etc/probe"; cp "$K" "$T/pl/pay/etc/probe/vendor.asc"; mkrpm pay ''
rejectw "R6 TEST key in the payload (/etc)" 'payload.*material' rel "$PKI" "$T/pr-pay"
mkdir -p "$T/pl/doc/usr/share/doc/probe-doc"; gzip -9c "$KB" | base64 > "$T/pl/doc/usr/share/doc/probe-doc/notes.txt"; mkrpm doc ''
rejectw "R7 base64(gzip(TEST key)) under usr/share/doc (doc exemption is text-only)" 'payload.*(base64|material)' rel "$PKI" "$T/pr-doc"
mkdir -p "$T/pl/tx/etc/probe" "$T/tx/a"; cp "$K" "$T/tx/a/k"; (cd "$T/tx" && tar cf - a | xz -c > "$T/pl/tx/etc/probe/bundle.tar.xz"); mkrpm tx ''
rejectw "R8 TEST key in a tar.xz inside the payload" 'payload.*bundle.tar.xz.*material' rel "$PKI" "$T/pr-tx"

echo "== P-L12: /avalonos allowlist (check-avalonos-dir.sh, run by verify-iso and build-iso)"
CA="$ROOT/scripts/check-avalonos-dir.sh"
mkav() { rm -rf "$T/av"; mkdir -p "$T/av"; cp -a "$REL" "$T/av/repo"; cp "$ROOT/kickstart/packages.inc" "$T/av/"; cp "$ROOT/keys/RPM-GPG-KEY-avalonos" "$T/av/"
         SOURCE_DATE_EPOCH=1791756588 "$ROOT/scripts/build-updates-img.sh" "$T/av/updates.img"; }
mkav; accept "P9 /avalonos exactly as build-iso makes it" rel "$CA" "$T/av"
mkav; echo hi > "$T/av/README"
rejectw "A1 extra file under /avalonos" 'top level is not exactly' rel "$CA" "$T/av"
mkav; cp "$K" "$T/av/.cache"
rejectw "A2 hidden file under /avalonos" 'top level is not exactly' rel "$CA" "$T/av"
mkav; mkdir "$T/av/extra"
rejectw "A3 extra directory under /avalonos" 'top level is not exactly' rel "$CA" "$T/av"
mkav; ln -s repo "$T/av/link"
rejectw "A4 symlink under /avalonos" 'top level is not exactly|links' rel "$CA" "$T/av"
mkav; gzip -c "$KB" >> "$T/av/updates.img"
rejectw "A5 data appended to updates.img" 'updates.img is not byte-identical' rel "$CA" "$T/av"
mkav; echo '# extra' >> "$T/av/packages.inc"
rejectw "A6 modified packages.inc" 'packages.inc differs' rel "$CA" "$T/av"
mkav; cp "$K" "$T/av/repo/extra.asc"
rejectw "A7 extra file inside /avalonos/repo" 'repo/ fails check-signatures' rel "$CA" "$T/av"
mkav; mv "$T/av/RPM-GPG-KEY-avalonos" "$T/av/RPM-GPG-KEY-avalonos-test"
rejectw "A8 release /avalonos with the TEST key file instead" 'top level is not exactly' rel "$CA" "$T/av"
mkav; mkdir "$T/av/repo/sub"
rejectw "A9 extra directory inside /avalonos/repo" 'repo/ fails check-signatures' rel "$CA" "$T/av"
echo "== P-L12: Codex coverage review fixtures (MacBook review 2026-11-14, findings 2-12)"
fresh "$REL"; py '
import gzip,os,sys
d=open(sys.argv[1],"rb").read()
for i in range(8): d=os.urandom(97)+gzip.compress(d,mtime=0)
open(sys.argv[2],"wb").write(d)' "$K" "$T/nest.bin"; cp "$T/nest.bin" "$T/r/nest.bin"
rejectw "V1 8 nested gzip layers, each after a random prefix (carved)" 'nested containers|material' rel "$KI" "$T/r"
fresh "$REL"; base64 -w0 "$T/nest.bin" > "$T/r/nest.txt"
rejectw "V2 the same, base64-encoded" 'nested containers|material' rel "$KI" "$T/r"
fresh "$REL"; py '
import sys,zlib
k=open(sys.argv[1],"rb").read()
lit=bytes([0xcb,255])+(len(k)+6).to_bytes(4,"big")+b"b\x00"+bytes(4)+k
z=b"\x02"+zlib.compress(lit,9)
out=bytes([0xc8]); i=0
while len(z)-i>512: out+=bytes([0xe9])+z[i:i+512]; i+=512      # partial body lengths (512)
r=z[i:]; out+=(bytes([len(r)]) if len(r)<192 else bytes([((len(r)-192)>>8)+192,(len(r)-192)&255]))+r
open(sys.argv[2],"wb").write(out)' "$KB" "$T/r/partial.pgp"
rejectw "V3 OpenPGP compressed packet with partial body lengths" 'material' rel "$KI" "$T/r"
fresh "$REL"; mkdir -p "$T/cz"; echo harmless > "$T/cz/a.txt"; cp "$K" "$T/cz/b.txt"; (cd "$T/cz" && zip -q "$T/z1.zip" a.txt && zip -q "$T/z2.zip" b.txt); cat "$T/z2.zip" "$T/z1.zip" > "$T/r/two.zip"
rejectw "V4 key in the first of two concatenated zips" 'material' rel "$KI" "$T/r"
fresh "$REL"; py 'import lzma,sys; open(sys.argv[2],"wb").write(lzma.compress(open(sys.argv[1],"rb").read(), format=lzma.FORMAT_ALONE, filters=[{"id":lzma.FILTER_LZMA1,"dict_size":(1<<16)+12345}]))' "$K" "$T/r/odd"
rejectw "V5 LZMA-alone with a non-standard dictionary size" 'lzma\].*material' rel "$KI" "$T/r"
fresh "$REL"; py 'import zlib,sys; open(sys.argv[2],"wb").write(zlib.compress(open(sys.argv[1],"rb").read(),9))' "$K" "$T/r/blob.z"
rejectw "V6 zlib stream at file start" 'zlib\].*material' rel "$KI" "$T/r"
fresh "$REL"; py 'import lzma,sys; open(sys.argv[2],"w").write(lzma.compress(open(sys.argv[1],"rb").read(), format=lzma.FORMAT_ALONE).hex())' "$K" "$T/r/lz.hex"
rejectw "V7 hex text of LZMA-alone of the armored key" 'hex\].*material' rel "$KI" "$T/r"
fresh "$REL"; py 'import lzma,sys,base64; open(sys.argv[2],"w",encoding="utf-16").write(base64.b64encode(lzma.compress(open(sys.argv[1],"rb").read(), format=lzma.FORMAT_ALONE)).decode())' "$K" "$T/r/u16.txt"
rejectw "V8 UTF-16 base64 of LZMA-alone" 'base64\].*material' rel "$KI" "$T/r"
fresh "$REL"; (cd "$T/tz" && tar --format=v7 -cf "$T/r/old.tar" etc)
rejectw "V9 key in a V7 (pre-ustar) tar" 'old.tar.*material' rel "$KI" "$T/r"
# V10 needs a non-root reader (root reads everything): run as nobody if root.
AS=(); [ "$(id -u)" = 0 ] && command -v setpriv >/dev/null && AS=(setpriv --reuid=65534 --regid=65534 --clear-groups --)
if [ "$(id -u)" != 0 ] || [ ${#AS[@]} -gt 0 ]; then
    V10="$(mktemp -d)"; chmod 755 "$V10"; mkdir -p "$V10/r/locked"; cp "$K" "$V10/r/locked/k"; chmod 000 "$V10/r/locked"
    rejectw "V10 unreadable directory fails closed" 'cannot read' rel "${AS[@]}" "$KI" "$V10/r"; chmod 755 "$V10/r/locked"; rm -rf "$V10"
else echo "skip  V10 unreadable directory (root without setpriv)"; fi
fresh "$REL"; touch "$T/r/ae8eaae9"
rejectw "V11 file named by the TEST short key ID" 'path .*names or encodes' rel "$KI" "$T/r"
fresh "$REL"; ln -s "$(base64 -w0 "$KB" | cut -c1-3000)" "$T/r/lnk"
rejectw "V12 symlink target carrying base64 key material" 'link .*names or encodes' rel "$KI" "$T/r"
fresh "$REL"; mkdir -p "$T/r/repodata"; printf 'fpr F2BC 6934 FB65 01B6 1141 77A7 E221 DD18 AE8E AAE9\n' > "$T/r/repodata/$(printf '%064d' 0)-other.xml.sh"
rejectw "V13 '-other.xml.sh' does not get the metadata prose exemption" 'fingerprint/ID' rel "$KI" "$T/r"
mkrpm url '' 'URL: https://example.invalid/F2BC6934FB6501B6114177A7E221DD18AE8EAAE9'
rejectw "V14 RPM URL tag naming the TEST fingerprint (all non-prose tags)" 'header.*fingerprint/ID' rel "$PKI" "$T/pr-url"
fresh "$REL"; (cd "$T/cz" && zip -q -P pw "$T/r/enc.zip" b.txt)
rejectw "V15 encrypted zip entry fails closed" 'encrypted' rel "$KI" "$T/r"
fresh "$REL"; (cd "$T/sq" && 7z a -bd "$T/in.7z" k >/dev/null); { head -c 5000 /dev/urandom; cat "$T/in.7z"; } > "$T/r/fw.bin"
rejectw "V16 7z archive embedded mid-file fails closed" '7z data at offset' rel "$KI" "$T/r"
# P-L13: uninspectable magics mid-file (not only at offset 0 / --gaps)
fresh "$REL"; { head -c 4096 /dev/urandom; printf '\x04\x22\x4d\x18'; head -c 512 /dev/zero; } > "$T/r/x.lz4"
rejectw "L3b lz4 frame embedded mid-file: fail closed" 'lz4 data at offset' rel "$KI" "$T/r"
# mid-file squashfs (L4 is squashfs at offset 0)
fresh "$REL"; mkdir -p "$T/sq2"; cp "$K" "$T/sq2/k"
mksquashfs "$T/sq2" "$T/sq-mid.img" -quiet -noappend >/dev/null 2>&1
{ head -c 4096 /dev/urandom; cat "$T/sq-mid.img"; } > "$T/r/fs.img"
rejectw "L4b squashfs image embedded mid-file: fail closed" 'squashfs data at offset' rel "$KI" "$T/r"
# P-L13: zlib mid-file (V6 is zlib at start)
fresh "$REL"
python3 - "$K" "$T/r/mid.zlib" <<'PY'
import sys, zlib
from pathlib import Path
key = Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_bytes(b"X"*4096 + zlib.compress(key))
PY
rejectw "V17 zlib stream embedded mid-file carrying the TEST key" 'zlib\].*material|@.*\[zlib\]' rel "$KI" "$T/r"
# P-L15: base64(gzip(.)) nested 4 times must fail closed (previously passed)
fresh "$REL"
python3 - "$K" "$T/r/nest.b64" <<'PY'
import sys, gzip, base64
from pathlib import Path
blob = Path(sys.argv[1]).read_bytes()
for _ in range(4):
    blob = base64.b64encode(gzip.compress(blob))
Path(sys.argv[2]).write_bytes(blob)
PY
rejectw "V18 base64(gzip(.)) nested 4 times fails closed at the depth limit" 'encoding nest exceeds depth|cannot be inspected|material' rel "$KI" "$T/r"
fresh "$REL"; gpg --batch --homedir "$(mktemp -d -p "$T")" --dearmor < "$ROOT/keys/RPM-GPG-KEY-avalonos" > "$T/r/vendor.asc"
accept "P10 production key as a BINARY key file named .asc (not a signature), release mode" rel "$KI" "$T/r"
# P-I16: mid-file zlib past the first 64 MiB of a --gaps file must still be carved.
fresh "$REL"
python3 - "$K" "$T/r/gap-000000000000-67108880" <<'PY'
import sys, zlib, os
from pathlib import Path
key = Path(sys.argv[1]).read_bytes()
path = Path(sys.argv[2])
off = 64 << 20
payload = zlib.compress(key)
# Sparse prefix: cheap 64 MiB hole, then a zlib stream of the public TEST key.
with open(path, "wb") as f:
    f.truncate(off + len(payload))
    f.seek(off)
    f.write(payload)
PY
rejectw "V19 zlib stream past 64 MiB in a --gaps file carrying the TEST key" 'zlib\].*material|@.*\[zlib\]' rel "$KI" --gaps "$T/r"
echo "key-isolation-test: $pass ok, $fails failed"
[ "$fails" = 0 ]
