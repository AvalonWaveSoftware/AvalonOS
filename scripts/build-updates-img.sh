#!/usr/bin/env bash
# Installer update image /avalonos/updates.img (P-M1r, decision 2026-11-14
# 11:30 CT). Every GRUB entry loads it with inst.updates=; it replaces the
# installer's repo files with pinned ones (gpgcheck=1 + pinned gpgkey) so the
# packages Anaconda installs are signature-checked before any scriptlet runs.
#   build-updates-img.sh OUT        write OUT (gzip'd newc cpio, reproducible)
#   build-updates-img.sh --manifest print "sha256  ./path" for every file
#                                   (embedded in the kickstart's %pre guard)
# Contents: installer/updates/ + the installer copies of the pinned keys.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ $# -eq 1 ] || { echo "usage: $0 OUT | --manifest" >&2; exit 2; }
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null || echo 0)}"
# key in keys/ : name in the image : pinned fingerprint (keys/PINNED-FINGERPRINTS)
KEYS=(
    "RPM-GPG-KEY-fedora-44-x86_64:RPM-GPG-KEY-fedora-44-x86_64:36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6"
    "rpmfusion-free-fedora-2020.gpg:RPM-GPG-KEY-rpmfusion-free-fedora-2020:E9A491A3DE247814E7E067EAE06F8ECDD651FF2E"
    "rpmfusion-nonfree-fedora-2020.gpg:RPM-GPG-KEY-rpmfusion-nonfree-fedora-2020:79BDB88F9BBF73910FD4095B6A2AF96194843C65"
)
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
d="$t/root"; mkdir -m 0755 "$d"; mkdir -m 0700 "$t/gnupg"
cp -R "$ROOT/installer/updates/." "$d/"
install -d -m 0755 "$d/etc/pki/avalonos-installer"
for k in "${KEYS[@]}"; do
    IFS=: read -r src dst fpr <<<"$k"
    got="$(gpg --batch --homedir "$t/gnupg" --show-keys --with-colons "$ROOT/keys/$src" 2>/dev/null | awk -F: '$1=="fpr"{print $10}')"
    [ "$got" = "$fpr" ] || { echo "build-updates-img: keys/$src is $got, not the pinned $fpr" >&2; exit 1; }
    install -m 0644 "$ROOT/keys/$src" "$d/etc/pki/avalonos-installer/$dst"
done
# gpgkey= of every repo must be one of the pinned installer keys.
grep -h '^gpgkey=' "$d"/etc/anaconda.repos.d/*.repo | sed 's#^gpgkey=file://##' | sort -u | while read -r p; do
    [ -f "$d$p" ] || { echo "build-updates-img: gpgkey $p is not a pinned installer key" >&2; exit 1; }
done
find "$d" -type d -exec chmod 0755 {} +
find "$d" -type f -exec chmod 0644 {} +
if [ "$1" = --manifest ]; then
    (cd "$d" && find . -type f | LC_ALL=C sort | xargs -d '\n' sha256sum)
    exit 0
fi
find "$d" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
(cd "$d" && find . -mindepth 1 | LC_ALL=C sort | cpio -o -H newc --reproducible --owner=0:0 --quiet) | gzip -9 -n > "$1"
chmod 0644 "$1"
