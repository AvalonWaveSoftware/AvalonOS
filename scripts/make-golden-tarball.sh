#!/usr/bin/env bash
# Pack overlay/ into the golden overlay tarball shipped as /avalonos/overlay.tar.
#   make-golden-tarball.sh [OUT]   (default: packaging/avalonos-overlay.tar)
#
# Member order, modes and mtimes come from packaging/overlay.manifest, so the
# tarball is byte-reproducible (git does not keep mtimes). Owners are 0:0,
# numeric, GNU format, no SELinux xattrs/ACLs. Kickstart %post extracts it
# with --no-same-owner --no-selinux, then runs restorecon.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/packaging/avalonos-overlay.tar}"
SRC="$ROOT/overlay"
MANIFEST="$ROOT/packaging/overlay.manifest"
die() { echo "make-golden-tarball: $*" >&2; exit 1; }

# Every path in overlay/ must be in the manifest and vice versa.
listed="$(mktemp)"; actual="$(mktemp)"; STAGE="$(mktemp -d)"
trap 'rm -rf "$listed" "$actual" "$STAGE"' EXIT
grep -v '^#' "$MANIFEST" | cut -f4 | sort > "$listed"
(cd "$SRC" && find . -mindepth 0 \( -type f -o -type d \) | sort) > "$actual"
if ! diff -q "$listed" "$actual" >/dev/null; then
    diff "$listed" "$actual" | sed -n 's/^</  only in manifest:/p; s/^>/  only in overlay\/:/p' >&2
    die "overlay/ and packaging/overlay.manifest disagree; run scripts/update-overlay-manifest.sh"
fi
if (cd "$SRC" && find . ! -type f ! -type d | grep -q .); then
    die "overlay/ contains symlinks or special files; the golden tarball only carries files and directories"
fi

# Stage a copy with the manifest's modes and mtimes.
cp -r --preserve=mode "$SRC/." "$STAGE/"
dirs=()
while IFS=$'\t' read -r type mode mtime path; do
    case "$type" in '#'*|'') continue;; esac
    chmod "$mode" "$STAGE/$path"
    if [ "$type" = d ]; then dirs+=("$mtime $path"); else touch -h -d "@$mtime" "$STAGE/$path"; fi
done < "$MANIFEST"
for ((i=${#dirs[@]}-1; i>=0; i--)); do
    touch -h -d "@${dirs[i]%% *}" "$STAGE/${dirs[i]#* }"
done

mkdir -p "$(dirname "$OUT")"
grep -v '^#' "$MANIFEST" | cut -f4 | \
    tar -C "$STAGE" --no-recursion -T - --numeric-owner --owner=0 --group=0 \
        --no-selinux --no-xattrs --no-acls --format=gnu -cf "$OUT"
echo "make-golden-tarball: $OUT ($(stat -c %s "$OUT") bytes, sha256 $(sha256sum "$OUT" | cut -c1-16)...)"
