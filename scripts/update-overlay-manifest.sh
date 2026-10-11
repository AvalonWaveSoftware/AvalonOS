#!/usr/bin/env bash
# Sync packaging/overlay.manifest with overlay/ after adding or removing files.
# Existing entries keep their order, mode and mtime (so unchanged files stay
# byte-identical in the tarball). New paths are appended in sorted order with
# mode 0755 for directories and executables, 0644 otherwise, and mtime
# $SOURCE_DATE_EPOCH (default: now). Removed paths are dropped.
# To change a file's mode, edit its manifest line.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/overlay"; MANIFEST="$ROOT/packaging/overlay.manifest"
now="${SOURCE_DATE_EPOCH:-$(date +%s)}"
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
grep '^#' "$MANIFEST" > "$tmp"
declare -A seen
while IFS=$'\t' read -r type mode mtime path; do
    case "$type" in '#'*|'') continue;; esac
    if [ -e "$SRC/$path" ]; then printf '%s\t%s\t%s\t%s\n' "$type" "$mode" "$mtime" "$path" >> "$tmp"; seen["$path"]=1
    else echo "removed: $path"; fi
done < "$MANIFEST"
while IFS= read -r path; do
    [ -n "${seen[$path]:-}" ] && continue
    if [ -d "$SRC/$path" ]; then t=d; m=0755; elif [ -x "$SRC/$path" ]; then t=f; m=0755; else t=f; m=0644; fi
    printf '%s\t%s\t%s\t%s\n' "$t" "$m" "$now" "$path" >> "$tmp"; echo "added: $path ($m)"
done < <(cd "$SRC" && find . \( -type f -o -type d \) | LC_ALL=C sort)
cp "$tmp" "$MANIFEST"
