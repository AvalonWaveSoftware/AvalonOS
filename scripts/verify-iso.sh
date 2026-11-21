#!/usr/bin/env bash
# Structural checks on a built AvalonOS ISO.
#   verify-iso.sh ISO           default is the full check (same as --full)
#   verify-iso.sh --full ISO    alias for the default: also sha256-compare every
#                               other file to upstream (extracts both images;
#                               needs ~2.5 GB in $TMPDIR)
#   verify-iso.sh --quick ISO   weaker path: skip the upstream file-by-file and
#                               ESP identity compare (still does the raw ISO/ESP
#                               key scan and the unowned-bytes decoding scan)
# Release ISO unless AVALONOS_TEST_BUILD=1 (QA test ISO). A release ISO FAILS
# on any test-seed artifact (decision 2026-11-14 11:31 CT): the
# avalonos-testseed RPM, seed strings in the kickstarts, GRUB configs or
# updates.img, or seed code/units inside any RPM payload (only
# /usr/share/doc and /usr/bin/tailwhip may mention the seed; tailwhip ships
# by decision 2026-11-14 11:30 CT).
# Signing keys (P-L11): a release ISO must carry and trust only the production
# key, a -TEST ISO only the TEST key; check-key-isolation.sh fails either on
# the other key's file, key material, pins or signatures anywhere on the ISO
# (kickstarts, GRUB, updates.img, /avalonos and every RPM payload).
# P-L12 (Master Chief 2026-11-14 17:43 CT: "Fix it before release"): /avalonos
# must hold exactly packages.inc, this kind's key, updates.img and the signed
# repo (nothing else); packages.inc, updates.img and both kickstarts must be
# byte-identical to what this tree builds; the raw ISO and ESP images are
# scanned too (key material outside any file), and every byte outside the
# files gets the full decoding scan (check-iso-unowned.sh). The default (and --full)
# additionally proves
# every other file, directory, link and the ESP identical to upstream (GRUB
# configs = upstream + our patches, eltorito.img = upstream except the
# boot-info-table/grub2-boot-info bytes xorriso rewrites).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/upstream.env"
FULL=1
while [ $# -gt 0 ]; do
    case "$1" in
        --full)  FULL=1; shift;;
        --quick) FULL=0; shift;;
        -*) echo "usage: verify-iso.sh [--full|--quick] ISO" >&2; exit 2;;
        *) break;;
    esac
done
ISO="${1:?usage: verify-iso.sh [--full|--quick] ISO}"
UP="${AVALONOS_CACHE:-$ROOT/cache}/$UPSTREAM_ISO"
TEST_BUILD="${AVALONOS_TEST_BUILD:-0}"
case "$TEST_BUILD" in 0|1) ;; *) echo "verify-iso: AVALONOS_TEST_BUILD must be 0 or 1" >&2; exit 2;; esac
# shellcheck source=scripts/avalonos-keys.sh
. "$ROOT/scripts/avalonos-keys.sh"
SEED_RE='avalonos[.-]testseed|AVTESTSEED|testseed-user|avalonos-seed\.conf'
UPD_ARG="inst.updates=hd:LABEL=$VOLUME_ID:/avalonos/updates.img"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }
chk() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
echo "verify-iso: $ISO"

xorriso -indev "$ISO" -pvd_info -report_el_torito plain -report_system_area plain > "$T/rep" 2>/dev/null
chk "volume id $VOLUME_ID"                grep -q "^Volume Id    : $VOLUME_ID\$" "$T/rep"
chk "El Torito BIOS image /images/eltorito.img" grep -q "^El Torito img path :   1  /images/eltorito.img" "$T/rep"
chk "El Torito BIOS boot-info-table + grub2-boot-info" grep -q "^El Torito img opts :   1  boot-info-table grub2-boot-info" "$T/rep"
chk "El Torito UEFI entry"                grep -qE "^El Torito boot img :   2  UEFI  y   none" "$T/rep"
chk "MBR grub2-mbr + protective label + GPT" grep -q "^System area summary: MBR protective-msdos-label grub2-mbr cyl-align-off GPT" "$T/rep"
chk "GPT partition 2 is the EFI System Partition" grep -qE "^GPT type GUID      :   2  28732ac11ff8d211ba4b00a0c93ec93b" "$T/rep"
efi_lba="$(awk '$1=="El" && $3=="boot" && $7=="UEFI" {print $NF}' "$T/rep")"
read -r p2_start p2_size < <(awk '$1=="GPT" && $2=="start" && $6=="2" {print $7, $8}' "$T/rep")
chk "UEFI El Torito image == GPT partition 2 (LBA $efi_lba)" test "$((efi_lba * 4))" = "$p2_start"

xorriso -osirrox on -indev "$ISO" -extract /EFI/BOOT "$T/efi" -extract /boot/grub2/grub.cfg "$T/bios.cfg" \
    -extract /avalonos "$T/avalonos" -extract /ks.cfg "$T/ks.cfg" -extract /ks-erase-all.cfg "$T/ks-erase-all.cfg" >/dev/null 2>&1 || true
chmod -R u+rw "$T" 2>/dev/null || true
dd if="$ISO" of="$T/esp.img" bs=512 skip="$p2_start" count="$p2_size" status=none
for f in grub.cfg BOOT.conf; do
    MTOOLS_SKIP_CHECK=1 mtype -i "$T/esp.img" "::/EFI/BOOT/$f" > "$T/esp-$f" 2>/dev/null || true
    chk "ESP /EFI/BOOT/$f == ISO9660 /EFI/BOOT/grub.cfg" cmp -s "$T/esp-$f" "$T/efi/grub.cfg"
done
chk "ISO9660 /EFI/BOOT/BOOT.conf == grub.cfg" cmp -s "$T/efi/BOOT.conf" "$T/efi/grub.cfg"
for c in "$T/efi/grub.cfg" "$T/bios.cfg"; do
    n="${c#"$T"/}"
    chk "$n: default entry asks for the disk" grep -q "^menuentry 'Install AvalonOS (Fedora 44) - choose disk'" "$c"
    chk "$n: set default=\"0\"" grep -qx 'set default="0"' "$c"
    chk "$n: menu waits (set timeout=-1, no countdown)" grep -qx 'set timeout=-1' "$c"
    chk "$n: 3 entries with inst.ks=hd:LABEL=$VOLUME_ID:/ks.cfg (interactive)" test "$(grep -c "inst.ks=hd:LABEL=$VOLUME_ID:/ks.cfg" "$c")" = 3
    chk "$n: exactly one entry uses /ks-erase-all.cfg" test "$(grep -c '/ks-erase-all.cfg' "$c")" = 1
    chk "$n: that entry is labelled ERASES ALL DISKS" \
        bash -c "grep -B1 '/ks-erase-all.cfg' '$c' | grep -q '^menuentry .*ERASES ALL DISKS'"
    chk "$n: the default (first) entry is not the erase entry" \
        bash -c "grep -m1 -A1 '^menuentry ' '$c' | grep -q 'inst.ks=hd:LABEL=$VOLUME_ID:/ks.cfg\$'"
    nl="$(grep -cE '^[[:space:]]*linux(efi)?[[:space:]]' "$c" || true)"
    chk "$n: all $nl linux lines carry $UPD_ARG (P-M1r)" \
        test "$nl" -gt 0 -a "$(grep -E '^[[:space:]]*linux(efi)?[[:space:]]' "$c" | grep -cF " $UPD_ARG ")" = "$nl"
    chk "$n: no inst.repo/inst.addrepo/noverifyssl" bash -c "! grep -Eq '(inst\.)?(repo|addrepo)=|noverifyssl' '$c'"
done
for k in ks.cfg ks-erase-all.cfg; do
    chk "/$k present, no unrendered placeholders, no hash" \
        bash -c "test -s '$T/$k' && ! grep -q @AVALONOS_ '$T/$k' && ! grep -Eq '\\\$(y|gy|6|5|2b)\\\$' '$T/$k'"
done
chk "/ks.cfg (default) has no zerombr / clearpart --all" bash -c "! grep -Eq '(^|[^-])zerombr|clearpart --all' '$T/ks.cfg'"
chk "/ks-erase-all.cfg is the erase kickstart" bash -c "grep -qx zerombr '$T/ks-erase-all.cfg' && grep -qx 'clearpart --all --initlabel' '$T/ks-erase-all.cfg'"
chk "/ks.cfg has rootpw --lock and no user/password line" \
    bash -c "grep -qx 'rootpw --lock' '$T/ks.cfg' && ! grep -Eq '^user |--iscrypted|--plaintext|--password' '$T/ks.cfg'"
chk "/ks.cfg closes ssh and excludes openssh-server" \
    bash -c "grep -qx 'firewall --enabled --remove-service=ssh' '$T/ks.cfg' && grep -qx -- '-openssh-server' '$T/ks.cfg'"
# P-M1r: updates.img content == the manifest the kickstart guard enforces.
mkdir -p "$T/upd"
if [ -s "$T/avalonos/updates.img" ] && (cd "$T/upd" && gzip -dc "$T/avalonos/updates.img" | cpio -id --quiet --no-absolute-filenames 2>/dev/null); then
    ok "/avalonos/updates.img present and unpacks (gzip newc cpio)"
else
    bad "/avalonos/updates.img missing or not a gzip cpio"
fi
for k in ks.cfg ks-erase-all.cfg; do
    awk '/^cat > \/tmp\/avalonos-updates.sha256 <</ {f=1; next} /^AVALONOS_MANIFEST_EOF$/ {f=0} f' "$T/$k" > "$T/$k.manifest"
    chk "/$k: first %pre is the installer guard" bash -c "grep -m1 '^%pre' '$T/$k' | grep -q 'avalonos-instguard.log'"
    chk "/$k: guard manifest == updates.img content (sha256 of every file, no extras)" bash -c "
        test -s '$T/$k.manifest' &&
        (cd '$T/upd' && sha256sum --check --strict --quiet '$T/$k.manifest') &&
        diff <(awk '{print \$2}' '$T/$k.manifest' | LC_ALL=C sort) <(cd '$T/upd' && find . -type f | LC_ALL=C sort)"
    chk "/$k: Fedora/RPM Fusion only via pinned system repos (no url/baseurl/metalink)" \
        bash -c "! grep -Eq '^(url|nfs|harddrive|liveimg)[[:space:]]|^repo .*--(baseurl|mirrorlist|metalink)' '$T/$k' && grep -qx 'repo --name=fedora' '$T/$k'"
done
chk "updates.img: every enabled installer repo has gpgcheck=1 and a pinned file:///etc/pki/avalonos-installer/ key" bash -c '
    n=0; for r in "$1"/upd/etc/anaconda.repos.d/*.repo; do
        awk "/^\[/ {if (s && !(g && k)) bad=1; s=1; g=0; k=0; n++} /^gpgcheck=1\$/ {g=1}
             /^gpgkey=file:\/\/\/etc\/pki\/avalonos-installer\// {k=1}
             END {if (s && !(g && k)) bad=1; exit bad}" "$r" || exit 1
    done; ls "$1"/upd/etc/anaconda.repos.d/fedora.repo >/dev/null' _ "$T"
chk "updates.img: pinned keys present" bash -c "ls '$T'/upd/etc/pki/avalonos-installer/RPM-GPG-KEY-* >/dev/null"
chk "/ks.cfg mode 0600 on the ISO" bash -c "xorriso -indev '$ISO' -lsdl /ks.cfg 2>/dev/null | grep -q '^-rw-------'"
chk "/avalonos/packages.inc" test -s "$T/avalonos/packages.inc"
chk "/avalonos/repo has repodata" test -s "$T/avalonos/repo/repodata/repomd.xml"
chk "/avalonos/$AV_KEY_NAME == keys/$AV_KEY_NAME" cmp -s "$T/avalonos/$AV_KEY_NAME" "$AV_KEY_FILE"
# P-L12: nothing else under /avalonos; every non-repo file rebuilt and compared.
chk "/avalonos holds exactly packages.inc, $AV_KEY_NAME, updates.img and the signed repo; all byte-identical to this tree's build (check-avalonos-dir.sh)" \
    "$ROOT/scripts/check-avalonos-dir.sh" "$T/avalonos"
for k in ks.cfg ks-erase-all.cfg; do
    a=(); [ "$k" = ks-erase-all.cfg ] && a=(--erase-all)
    chk "/$k == render-kickstart.sh ${a[*]} output of this tree" bash -c '
        "$1/scripts/render-kickstart.sh" "${@:4}" "$2.rendered" >/dev/null 2>&1 && cmp -s "$2.rendered" "$2"' _ "$ROOT" "$T/$k" x "${a[@]}"
done
chk "/avalonos/repo: every RPM and repomd.xml signed by the pinned AvalonOS key ($AV_KEY_NAME)" "$ROOT/scripts/check-signatures.sh" "$T/avalonos/repo" "$AV_KEY_FILE"
chk "/ks.cfg + /ks-erase-all.cfg pin only $AV_KEY_NAME ($AV_KEY_PIN)" bash -c '
    for k in "$1/ks.cfg" "$1/ks-erase-all.cfg"; do
        grep -qxF "    [/etc/pki/rpm-gpg/$2]=$3" "$k" && grep -qF "gpgkey=file:///etc/pki/rpm-gpg/$2 " "$k" || exit 1
    done' _ "$T" "$AV_KEY_NAME" "$AV_KEY_PIN"
# Whole ISO, whole ESP and the unpacked updates.img, every file by content
# (not just /avalonos): no file, key, pin or signature of the other kind's key.
# Upstream's embedded images (install.img, initrd) are checked byte-for-byte
# against upstream by the default path (and --full), which build-iso.sh always runs.
mkdir -p "$T/isoall" "$T/espall"
# Extraction must be complete: both extractors must succeed and the extracted
# file counts must equal the ISO's and the ESP's own listings.
iso_n="$(env -u SOURCE_DATE_EPOCH xorriso -indev "$ISO" -find / -type f 2>/dev/null | grep -c "^'/" || true)"
esp_n="$(MTOOLS_SKIP_CHECK=1 mdir -/ -b -i "$T/esp.img" ::/ 2>/dev/null | grep -cv '/$' || true)"
if env -u SOURCE_DATE_EPOCH xorriso -osirrox on -indev "$ISO" -extract / "$T/isoall" >/dev/null 2>&1 \
   && chmod -R u+rwX "$T/isoall" \
   && MTOOLS_SKIP_CHECK=1 mcopy -s -n -i "$T/esp.img" '::/*' "$T/espall/" 2>/dev/null \
   && [ "$iso_n" -gt 0 ] && [ "$(find "$T/isoall" -type f | wc -l)" = "$iso_n" ] \
   && [ "$esp_n" -gt 0 ] && [ "$(find "$T/espall" -type f | wc -l)" = "$esp_n" ] \
   && "$ROOT/scripts/check-key-isolation.sh" "$T/isoall" "$T/espall" "$T/upd" > "$T/iso-keys.log" 2>&1 \
   && "$ROOT/scripts/check-key-isolation.sh" --raw "$ISO" "$T/esp.img" >> "$T/iso-keys.log" 2>&1; then
    ok "key isolation (P-L11/P-L12): no $( [ "$TEST_BUILD" = 0 ] && echo TEST || echo production ) key file, key (any encoding or container), pin or signature anywhere on the ISO, ESP, updates.img or in the raw ISO/ESP bytes"
else
    bad "key isolation (P-L11) (ISO files $iso_n, ESP files $esp_n; extraction must be complete):"
    sed 's/^/         /' "$T/iso-keys.log" 2>/dev/null || true
fi
# P-L12 (Codex review finding 1): ISO bytes that belong to no file (system
# area, directory records, slack, anything appended) get the full decoding
# scan; the default path (and --full) also proves the ESP byte-identical to
# upstream's + grub.cfg. --quick skips that ESP identity compare; the raw
# ISO/ESP key scan still runs and will catch foreign key material in ESP
# free space (P-L14: the default path also caught a gzip'd TEST key there).
unowned_up=(); if [ "$FULL" = 1 ] && [ -f "$UP" ]; then unowned_up=("$UP"); fi
if "$ROOT/scripts/check-iso-unowned.sh" "$ISO" "${unowned_up[@]}" > "$T/unowned.log" 2>&1; then
    ok "unowned ISO bytes carry no other-kind key in any encoding$( [ "$FULL" = 1 ] && echo '; ESP == upstream ESP + grub.cfg (only FAT timestamps differ)')"
else
    bad "unowned ISO bytes / ESP:"; sed 's/^/         /' "$T/unowned.log"
fi
chk "/avalonos/repo has the avalonos meta-package" bash -c "ls '$T'/avalonos/repo/avalonos-[0-9]*.rpm >/dev/null 2>&1 || ls '$T'/avalonos/repo/*/avalonos-[0-9]*.rpm >/dev/null 2>&1"

# Test seed (decision 2026-11-14 11:31 CT).
find "$T/avalonos/repo" -name '*.rpm' -exec rpm -qp --nosignature --qf '%{NAME}\n' {} + 2>/dev/null | sort > "$T/names" || true
if [ "$TEST_BUILD" = 0 ]; then
    echo "verify-iso: release ISO: no test-seed artifact allowed"
    chk "release: no avalonos-testseed RPM" bash -c "! grep -qx avalonos-testseed '$T/names' && ! find '$T/avalonos' -iname '*testseed*' | grep -q ."
    chk "release: kickstarts, GRUB configs and updates.img carry no seed strings" \
        bash -c "! grep -rEq '$SEED_RE' '$T/ks.cfg' '$T/ks-erase-all.cfg' '$T/efi' '$T/bios.cfg' '$T/esp-grub.cfg' '$T/esp-BOOT.conf' '$T/upd' '$T/avalonos/packages.inc'"
    seedhits=""
    for r in "$T"/avalonos/repo/*.rpm; do
        x="$T/x/$(basename "$r")"; mkdir -p "$x"
        (cd "$x" && rpm2cpio "$r" | cpio -id --quiet --no-absolute-filenames 2>/dev/null) || { seedhits+=" $(basename "$r"):unreadable"; continue; }
        h="$(cd "$x" && { find . -iname '*testseed*'; grep -rlE "$SEED_RE" . 2>/dev/null; } | grep -vE '^\./(usr/share/doc/|usr/bin/tailwhip$)' || true)"
        [ -z "$h" ] || seedhits+=" $(basename "$r"):$(echo $h)"
        rm -rf "$x"
    done
    chk "release: no seed code, unit or file in any RPM payload (except docs, tailwhip)${seedhits:+ -- found:$seedhits}" test -z "$seedhits"
else
    echo "verify-iso: QA TEST ISO (AVALONOS_TEST_BUILD=1)"
    chk "test: ISO file name ends in -TEST.iso" bash -c "case '$ISO' in *-TEST.iso) ;; *) exit 1;; esac"
    chk "test: repo has avalonos-testseed" grep -qx avalonos-testseed "$T/names"
    chk "test: kickstarts install avalonos-testseed" bash -c "grep -q 'install avalonos-testseed' '$T/ks.cfg' && grep -q 'install avalonos-testseed' '$T/ks-erase-all.cfg'"
fi

if [ "$FULL" = 1 ]; then
    [ -f "$UP" ] || { bad "upstream ISO $UP not found for --full"; exit 1; }
    echo "$UPSTREAM_SHA256  $UP" | sha256sum -c --status || { bad "upstream ISO $UP is not the pinned one (upstream.env)"; exit 1; }
    echo "verify-iso: full compare against $UPSTREAM_ISO"
    up_n="$(env -u SOURCE_DATE_EPOCH xorriso -indev "$UP" -find / -type f 2>/dev/null | grep -c "^'/" || true)"
    if ! env -u SOURCE_DATE_EPOCH xorriso -osirrox on -indev "$UP" -extract / "$T/up" >/dev/null 2>&1 \
       || ! chmod -R u+rwX "$T/up" || [ "$(find "$T/up" -type f | wc -l)" != "$up_n" ]; then
        bad "upstream ISO extraction incomplete"; echo "verify-iso: FAILED"; exit 1
    fi
    # $T/isoall is this ISO, extracted completely above (counts checked).
    sums() { (cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum); }
    sums "$T/up" > "$T/up.sha"; sums "$T/isoall" > "$T/new.sha"
    # Expected differences: our additions and patched configs; eltorito.img
    # is compared separately below.
    expect='^\./(ks\.cfg|ks-erase-all\.cfg|avalonos/.*|EFI/BOOT/grub\.cfg|EFI/BOOT/BOOT\.conf|boot/grub2/grub\.cfg|images/eltorito\.img)$'
    unexpected="$(diff "$T/up.sha" "$T/new.sha" | sed -n 's/^[<>] [0-9a-f]\{64\}  //p' | LC_ALL=C sort -u | grep -vE "$expect" || true)"
    if [ -z "$unexpected" ]; then ok "all other files identical to upstream ($(wc -l < "$T/up.sha") upstream files)"
    else bad "unexpected differences vs upstream:"; echo "$unexpected" | sed 's/^/         /'; fi
    chk "no file of upstream is missing (incl. the expected ones)" bash -c '! diff <(sed "s/^[0-9a-f]*  //" "$1/up.sha") <(sed "s/^[0-9a-f]*  //" "$1/new.sha") | grep -q "^<"' _ "$T"
    chk "directories, links and special files == upstream (+ /avalonos, /avalonos/repo, /avalonos/repo/repodata)" \
        bash -c 'diff <(cd "$1/up" && find . ! -type f -printf "%y %p -> %l\n" | LC_ALL=C sort) \
                      <(cd "$1/isoall" && find . ! -type f -printf "%y %p -> %l\n" | grep -vxE "d \./avalonos(/repo(/repodata)?)? -> " | LC_ALL=C sort)' _ "$T"
    # eltorito.img: xorriso rewrites the boot-info-table (bytes 8-63) and the
    # grub2-boot-info LBA (bytes 2548-2555); everything else must be upstream.
    chk "images/eltorito.img == upstream except the boot-info-table / grub2-boot-info bytes" python3 -c '
import sys
a, b = (open(p, "rb").read() for p in sys.argv[1:3])
m = lambda x: x[:8] + bytes(56) + x[64:2548] + bytes(8) + x[2556:]
sys.exit(0 if len(a) == len(b) > 2556 and m(a) == m(b) else 1)' "$T/up/images/eltorito.img" "$T/isoall/images/eltorito.img"
    # GRUB configs: exactly upstream + our patches (as build-iso.sh makes them).
    mkdir -p "$T/grubre"
    (cd "$T/up" && cp --parents EFI/BOOT/grub.cfg boot/grub2/grub.cfg "$T/grubre/") && chmod -R u+w "$T/grubre"
    chk "GRUB configs (ISO9660 EFI/BIOS) == upstream + boot/grub-efi.patch + boot/grub-bios.patch" bash -c '
        cd "$1/grubre" && patch -p1 --no-backup-if-mismatch -s < "$2/boot/grub-efi.patch" && patch -p1 --no-backup-if-mismatch -s < "$2/boot/grub-bios.patch" &&
        cmp -s EFI/BOOT/grub.cfg "$1/isoall/EFI/BOOT/grub.cfg" && cmp -s EFI/BOOT/grub.cfg "$1/isoall/EFI/BOOT/BOOT.conf" &&
        cmp -s boot/grub2/grub.cfg "$1/isoall/boot/grub2/grub.cfg"' _ "$T" "$ROOT"
    # ESP: same size and files as upstream's, except the two GRUB configs.
    read -r ups uz < <(env -u SOURCE_DATE_EPOCH xorriso -indev "$UP" -report_system_area plain 2>/dev/null | awk '$1=="GPT" && $2=="start" && $6=="2" {print $7, $8}')
    dd if="$UP" of="$T/esp-up.img" bs=512 skip="$ups" count="$uz" status=none
    mkdir -p "$T/espup"
    chk "ESP == upstream ESP: same size, same files, all identical except EFI/BOOT/grub.cfg and BOOT.conf" bash -c '
        [ "$(stat -c %s "$1/esp-up.img")" = "$(stat -c %s "$1/esp.img")" ] &&
        MTOOLS_SKIP_CHECK=1 mcopy -s -n -i "$1/esp-up.img" "::/*" "$1/espup/" 2>/dev/null &&
        diff <(cd "$1/espup" && find . -type f ! -path ./EFI/BOOT/grub.cfg ! -path ./EFI/BOOT/BOOT.conf -print0 | LC_ALL=C sort -z | xargs -0 sha256sum) \
             <(cd "$1/espall" && find . -type f ! -path ./EFI/BOOT/grub.cfg ! -path ./EFI/BOOT/BOOT.conf -print0 | LC_ALL=C sort -z | xargs -0 sha256sum) >/dev/null &&
        diff <(cd "$1/espup" && find . | LC_ALL=C sort) <(cd "$1/espall" && find . | LC_ALL=C sort) >/dev/null' _ "$T"
fi
[ "$fail" = 0 ] && echo "verify-iso: PASS" || { echo "verify-iso: FAILED"; exit 1; }
