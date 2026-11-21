#!/usr/bin/bash
# AvalonOS installer guard (P-M1r, decision 2026-11-14 11:30 CT): the first
# %pre of both kickstarts. Refuses to install unless Anaconda will install
# ONLY from the pinned repos of /avalonos/updates.img, i.e. with gpgcheck=1 and
# the pinned keys, so libdnf5 checks every package signature before any
# scriptlet runs. render-kickstart.sh writes the image's sha256 manifest to
# /tmp/avalonos-updates.sha256 just above this script.
set -uo pipefail
M=/tmp/avalonos-updates.sha256
die() {
    echo "AvalonOS: $*" >&2
    echo "AvalonOS: refusing to install (package signature checks could not be guaranteed)." >&2
    for t in /dev/tty1 /dev/console; do
        [ -w "$t" ] && printf '\nAvalonOS installer: %s\nRefusing to install. Nothing was written.\n' "$*" > "$t" 2>/dev/null
    done
    exit 1
}
# 1. updates.img was applied: every file in place, byte for byte.
[ -s "$M" ] || die "missing $M (kickstart not rendered by render-kickstart.sh)"
(cd / && sha256sum --check --strict --quiet "$M") \
    || die "the installer update /avalonos/updates.img is missing or altered (inst.updates= removed?)"
# 2. The only repo definitions Anaconda reads (DNF_REPO_DIRS) are ours.
for d in /etc/anaconda.repos.d /etc/yum.repos.d; do
    for f in "$d"/*.repo; do
        [ -e "$f" ] || continue
        grep -qF "  .$f" "$M" || die "unexpected repo file $f"
    done
done
# 3. No dnf override or drop-in that could switch the checks off.
for d in /etc/dnf/repos.override.d /usr/share/dnf5/repos.override.d /etc/dnf/libdnf5.conf.d /usr/share/dnf5/repos.d; do
    [ -z "$(ls -A "$d" 2>/dev/null)" ] || die "unexpected dnf configuration in $d"
done
# 4. No boot option that adds an unchecked source or turns TLS checks off.
for a in $(cat /proc/cmdline); do
    case "$a" in
        inst.repo=*|repo=*|inst.addrepo=*|inst.noverifyssl|noverifyssl)
            die "boot option $a is not allowed (it bypasses the pinned, signature-checked repos)";;
    esac
done
# 5. No kickstart install source: url/--baseurl/--mirrorlist/--metalink repos
#    are created by Anaconda with gpgcheck off.
for ks in /run/install/ks.cfg /tmp/ks.cfg; do
    [ -f "$ks" ] || continue
    if grep -Eq '^[[:space:]]*(url|nfs|harddrive|cdrom|hmc|liveimg|ostreesetup|ostreecontainer|bootc)([[:space:]]|$)|^[[:space:]]*repo[[:space:]].*--(baseurl|mirrorlist|metalink)' "$ks"; then
        die "$ks defines an install source outside the pinned repos"
    fi
done
echo "AvalonOS: installer repos pinned; package signatures will be checked before installation"
