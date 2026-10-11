#!/usr/bin/env bash
# Structural checks on a built AvalonOS ISO.
#   verify-iso.sh ISO           boot layout, GRUB entries (ISO9660 + ESP), payload
#   verify-iso.sh --full ISO    also sha256-compare every other file to upstream
#                               (extracts both images; needs ~2.5 GB in $TMPDIR)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/upstream.env"
FULL=0; [ "${1:-}" = --full ] && { FULL=1; shift; }
ISO="${1:?usage: verify-iso.sh [--full] ISO}"
UP="${AVALONOS_CACHE:-$ROOT/cache}/$UPSTREAM_ISO"
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
    -extract /avalonos "$T/avalonos" -extract /ks.cfg "$T/ks.cfg" >/dev/null 2>&1 || true
chmod -R u+rw "$T" 2>/dev/null || true
dd if="$ISO" of="$T/esp.img" bs=512 skip="$p2_start" count="$p2_size" status=none
for f in grub.cfg BOOT.conf; do
    MTOOLS_SKIP_CHECK=1 mtype -i "$T/esp.img" "::/EFI/BOOT/$f" > "$T/esp-$f" 2>/dev/null || true
    chk "ESP /EFI/BOOT/$f == ISO9660 /EFI/BOOT/grub.cfg" cmp -s "$T/esp-$f" "$T/efi/grub.cfg"
done
chk "ISO9660 /EFI/BOOT/BOOT.conf == grub.cfg" cmp -s "$T/efi/BOOT.conf" "$T/efi/grub.cfg"
for c in "$T/efi/grub.cfg" "$T/bios.cfg"; do
    n="${c#"$T"/}"
    chk "$n: default entry 'Install AvalonOS (Fedora 44)'" grep -q "^menuentry 'Install AvalonOS (Fedora 44)'" "$c"
    chk "$n: set default=\"0\"" grep -qx 'set default="0"' "$c"
    chk "$n: 3 entries with inst.ks=hd:LABEL=$VOLUME_ID:/ks.cfg" test "$(grep -c "inst.ks=hd:LABEL=$VOLUME_ID:/ks.cfg" "$c")" = 3
done
chk "/ks.cfg present, no unrendered placeholders" bash -c "test -s '$T/ks.cfg' && ! grep -q @AVALONOS_ '$T/ks.cfg'"
chk "/ks.cfg has an iscrypted user" grep -q "^user --name=.* --iscrypted" "$T/ks.cfg"
chk "/ks.cfg mode 0600 on the ISO" bash -c "xorriso -indev '$ISO' -lsdl /ks.cfg 2>/dev/null | grep -q '^-rw-------'"
for f in overlay.tar docs.tar packages.inc; do chk "/avalonos/$f" test -s "$T/avalonos/$f"; done
chk "overlay.tar is a valid tar" tar -tf "$T/avalonos/overlay.tar"

if [ "$FULL" = 1 ]; then
    [ -f "$UP" ] || { bad "upstream ISO $UP not found for --full"; exit 1; }
    echo "verify-iso: full sha256 compare against $UPSTREAM_ISO"
    xorriso -osirrox on -indev "$UP"  -extract / "$T/up"  >/dev/null 2>&1
    xorriso -osirrox on -indev "$ISO" -extract / "$T/new" >/dev/null 2>&1
    chmod -R u+rwX "$T/up" "$T/new"
    (cd "$T/up" && find . -type f | LC_ALL=C sort | xargs -d '\n' sha256sum) > "$T/up.sha"
    (cd "$T/new" && find . -type f | LC_ALL=C sort | xargs -d '\n' sha256sum) > "$T/new.sha"
    # Expected differences: our additions/patches, and eltorito.img whose
    # boot-info-table xorriso rewrites with the new LBAs.
    expect='^\./(ks\.cfg|avalonos/.*|EFI/BOOT/grub\.cfg|EFI/BOOT/BOOT\.conf|boot/grub2/grub\.cfg|images/eltorito\.img)$'
    unexpected="$(diff <(awk '{print $2, $1}' "$T/up.sha") <(awk '{print $2, $1}' "$T/new.sha") | \
        awk '/^[<>]/{print $2}' | sort -u | grep -vE "$expect" || true)"
    if [ -z "$unexpected" ]; then ok "all other files identical to upstream ($(wc -l < "$T/up.sha") upstream files)"
    else bad "unexpected differences vs upstream:"; echo "$unexpected" | sed 's/^/         /'; fi
fi
[ "$fail" = 0 ] && echo "verify-iso: PASS" || { echo "verify-iso: FAILED"; exit 1; }
