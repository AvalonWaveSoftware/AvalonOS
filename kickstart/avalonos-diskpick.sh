#!/bin/bash
# AvalonOS disk picker: kickstart %pre (inlined by scripts/render-kickstart.sh).
# Decision 2026-11-14 9:36 CT: the default boot entry stops and asks which disk;
# no countdown; nothing is erased without typing the disk name.
#
# Writes /tmp/avalonos-storage.ks (included by /ks.cfg) for ONE disk. It
# never erases all disks: that is only /ks-erase-all.cfg (its own menu entry).
# Optional kernel argument (typed by the user at the boot menu):
#   avalonos.disk=<dev>      preselect <dev> (vda, nvme0n1, /dev/disk/by-id/...).
#                            Checked like an interactive pick and STILL needs the
#                            typed confirmation (disk name, plus ERASE when it
#                            holds data or is removable). Removable/USB disks are
#                            refused unless avalonos.disk.allow-removable=1 is
#                            also given (and ERASE typed). Code Security P-L1.
# Never offered: the installer medium, read-only, removable/USB (unless U is
# pressed), loop/zram/optical devices, disks under MIN_GIB.
# ERASE is required for removable disks and for ANY disk that has a partition,
# a partition table, or any filesystem/RAID/swap signature (P-L2).
set -uo pipefail

OUT=/tmp/avalonos-storage.ks
MIN_GIB=20
BOOTARGS='rhgb quiet'
TTY=/dev/tty6

cmdarg() {  # value of key=value on the kernel command line
    local tok toks
    read -r -a toks < /proc/cmdline
    for tok in "${toks[@]}"; do
        case "$tok" in "$1="*) printf '%s\n' "${tok#*=}"; return 0;; esac
    done
    return 1
}

write_storage() {  # $1 = the confirmed /dev/... disk (exactly one)
    local d="${1#/dev/}"
    {
        echo "# written by avalonos-diskpick ($(date -u +%FT%TZ))"
        # Only the chosen disk is visible to the installer and cleared.
        echo "ignoredisk --only-use=$d"
        # Drive-scoped: clears ONLY $d (and ignoredisk hides every other disk).
        # The unscoped all-drives wipe exists only in /ks-erase-all.cfg.
        echo "clearpart --drives=$d --all --initlabel"
        echo "autopart --type=lvm"
        echo "bootloader --location=mbr --boot-drive=$d --timeout=5 --append=\"$BOOTARGS\""
    } > "$OUT"
    echo "avalonos-diskpick: target=$1" >&2
}

installer_disks() {  # parent disks of the installer medium / mounted sources
    local label dev src
    label="$(cmdarg inst.stage2 | sed -n 's/^hd:LABEL=\([^:]*\).*/\1/p')"
    label="${label//\\x20/ }"
    for dev in $( [ -n "$label" ] && blkid -L "$label" 2>/dev/null ) \
               $(findmnt -rno SOURCE /run/install/repo 2>/dev/null) \
               $(findmnt -rno SOURCE /run/install/sources 2>/dev/null) \
               $(findmnt -rno SOURCE /run/install/ks 2>/dev/null); do
        case "$dev" in /dev/*) ;; *) continue;; esac
        src="$(lsblk -dno PKNAME "$dev" 2>/dev/null)"
        echo "/dev/${src:-${dev#/dev/}}"
    done | sort -u
}

# Candidate disks: "NAME SIZE_BYTES RM TRAN" (one per line)
list_disks() {  # $1 = 1 to include removable/USB
    local excl name size ro rm tran type
    excl="$(installer_disks)"
    lsblk -dbpnro NAME,SIZE,RO,RM,TRAN,TYPE 2>/dev/null |
    while read -r name size ro rm tran type; do
        [ "$type" = disk ] || continue
        case "$name" in /dev/loop*|/dev/zram*|/dev/ram*|/dev/sr*|/dev/fd*|/dev/nbd*) continue;; esac
        [ "$ro" = 0 ] || continue
        grep -qx "$name" <<<"$excl" && continue
        [ "$size" -ge $((MIN_GIB * 1024 * 1024 * 1024)) ] || continue
        if [ "${1:-0}" != 1 ] && { [ "$rm" = 1 ] || [ "$tran" = usb ]; }; then continue; fi
        echo "$name $size $rm ${tran:--}"
    done
}

# Does the disk hold anything at all? Partitions, a partition table, or any
# signature wipefs/blkid knows (filesystems, swap, RAID, ZFS, ...).
has_data() {  # $1 = disk
    local d="$1"
    [ "$(lsblk -nro TYPE "$d" 2>/dev/null | grep -c part)" -gt 0 ] && return 0
    [ -n "$(lsblk -dnro PTTYPE "$d" 2>/dev/null | tr -d ' ')" ] && return 0
    [ -n "$(lsblk -nro FSTYPE "$d" 2>/dev/null | tr -d ' \n')" ] && return 0
    [ -n "$(wipefs -n -o TYPE --noheadings "$d" 2>/dev/null)" ] && return 0
    return 1
}

describe() {  # one-line contents warning for a disk
    local d="$1" fs warn=""
    fs="$(lsblk -nro FSTYPE "$d" 2>/dev/null | sort -u | tr '\n' ' ')"
    case "$fs" in *ntfs*|*BitLocker*) warn="$warn WINDOWS/NTFS";; esac
    case "$fs" in *vfat*|*exfat*|*" fat"*|fat*|*msdos*) warn="$warn FAT/EXFAT";; esac
    case "$fs" in *hfs*|*apfs*) warn="$warn APPLE(HFS+/APFS)";; esac
    case "$fs" in *swap*) warn="$warn SWAP";; esac
    case "$fs" in *crypto_LUKS*) warn="$warn LUKS";; esac
    case "$fs" in *LVM2_member*) warn="$warn LVM";; esac
    case "$fs" in *linux_raid_member*|*zfs_member*) warn="$warn RAID/ZFS";; esac
    case "$fs" in *ext2*|*ext3*|*ext4*|*xfs*|*btrfs*|*f2fs*) warn="$warn LINUX";; esac
    if [ -z "$warn" ] && has_data "$d"; then warn=" DATA (partitions or signatures)"; fi
    printf '%s partitions; filesystems: %s%s' \
        "$(lsblk -nro TYPE "$d" | grep -c part)" "${fs:-none}" "${warn:+  !! contains:$warn}"
}

# Ask for the typed confirmation. 0 = confirmed. Runs on the TTY.
confirm_disk() {  # name size rm tran
    local name="$1" size="$2" rm="$3" tran="$4" c1 c2
    echo
    echo "  ALL DATA on $name ($((size / 1073741824)) GiB, $(lsblk -dno MODEL "$name" | xargs)) WILL BE ERASED."
    if [ "$rm" = 1 ] || [ "$tran" = usb ]; then echo "  !! REMOVABLE / USB device"; fi
    echo "  $(describe "$name")"
    printf '  Type the disk name to confirm (%s), anything else goes back: ' "${name#/dev/}"
    read -r c1 || return 1
    [ "$c1" = "${name#/dev/}" ] || return 1
    if describe "$name" | grep -q '!!' || has_data "$name" || [ "$rm" = 1 ] || [ "$tran" = usb ]; then
        printf '  This disk has existing data or is removable. Type ERASE to continue: '
        read -r c2 || return 1
        [ "$c2" = ERASE ] || return 1
    fi
    return 0
}

valid_target() {  # resolve and check a requested disk; prints /dev/name
    local want="$1" real
    case "$want" in /dev/*) ;; *) want="/dev/$want";; esac
    real="$(readlink -f "$want" 2>/dev/null)" || return 1
    [ -b "$real" ] || return 1
    list_disks 1 | awk '{print $1}' | grep -qx "$real" || return 1
    echo "$real"
}

# ---- the picker runs on tty6 ---------------------------------------------------
# shellcheck disable=SC2094  # a TTY is read and written on purpose
exec <"$TTY" >"$TTY" 2>&1
chvt 6 2>/dev/null || true

# ---- avalonos.disk= preselection: still confirmed by typing (P-L1) -------------
if req="$(cmdarg avalonos.disk)"; then
    allow_rm=0; [ "$(cmdarg avalonos.disk.allow-removable || true)" = 1 ] && allow_rm=1
    if ! tgt="$(valid_target "$req")"; then
        echo "  avalonos.disk=$req is not an eligible disk; choose one below."
    elif line="$(list_disks "$allow_rm" | awk -v t="$tgt" '$1 == t')" && [ -n "$line" ]; then
        read -r name size rm tran <<<"$line"
        echo "=================== AvalonOS installer: confirm the target disk =================="
        echo "  Preselected by avalonos.disk=$req"
        if confirm_disk "$name" "$size" "$rm" "$tran"; then
            write_storage "$name"
            echo "  Partition plan written. Installation starts on $name."
            sleep 2; chvt 1 2>/dev/null || true; exit 0
        fi
        echo "  Not confirmed; choose a disk below."
    else
        echo "  avalonos.disk=$req is removable/USB: refused (add avalonos.disk.allow-removable=1"
        echo "  to allow it, or press U below). Choose a disk below."
    fi
    sleep 3
fi

# ---- interactive picker ----------------------------------------------------------
show_usb=0
while :; do
    clear 2>/dev/null || printf '\033c'
    echo "=================== AvalonOS installer: choose the target disk ==================="
    echo
    mapfile -t disks < <(list_disks "$show_usb")
    if [ "${#disks[@]}" -eq 0 ]; then
        echo "  No suitable disk found (>= ${MIN_GIB} GiB, writable, not the installer medium"
        [ "$show_usb" = 1 ] || echo "  and not removable/USB; press U to include those)."
        echo
    else
        i=0
        for line in "${disks[@]}"; do
            i=$((i + 1))
            read -r name size rm tran <<<"$line"
            printf '  %d) %-14s %6s GiB  %-5s %s %s\n' "$i" "$name" "$((size / 1073741824))" "$tran" \
                "$(lsblk -dno MODEL "$name" 2>/dev/null | xargs)" "$(lsblk -dno SERIAL "$name" 2>/dev/null | xargs)"
            if [ "$rm" = 1 ] || [ "$tran" = usb ]; then echo "     !! REMOVABLE / USB device"; fi
            echo "     $(describe "$name")"
        done
        echo
    fi
    echo "  The chosen disk is ERASED completely. Other disks are not touched."
    printf '  Disk number, R = rescan, U = %s removable/USB, Q = quit and power off: ' \
        "$([ "$show_usb" = 1 ] && echo hide || echo show)"
    read -r ans || ans=Q
    case "$ans" in
        [Qq]) echo; echo "  Powering off. Nothing was written."; sleep 2; poweroff -f; exit 1;;
        [Rr]) continue;;
        [Uu]) show_usb=$((1 - show_usb)); continue;;
        ''|*[!0-9]*) continue;;
    esac
    [ "$ans" -ge 1 ] && [ "$ans" -le "${#disks[@]}" ] || continue
    read -r name size rm tran <<<"${disks[$((ans - 1))]}"
    confirm_disk "$name" "$size" "$rm" "$tran" || continue
    write_storage "$name"
    echo "  Partition plan written. Installation starts on $name."
    sleep 2
    break
done
chvt 1 2>/dev/null || true
exit 0
