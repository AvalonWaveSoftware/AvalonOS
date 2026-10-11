#!/usr/bin/env bash
# Pack the user documentation shipped as /avalonos/docs.tar. Kickstart %post
# unpacks it into ~/AvalonOS-Docs for the daily user.
#   make-docs-tarball.sh [OUT]   (default: packaging/avalonos-docs.tar)
# Deterministic: sorted names, mtime $SOURCE_DATE_EPOCH (default: last commit).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/packaging/avalonos-docs.tar}"
EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null || echo 0)}"
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
cd "$ROOT"
for p in README.md INDEX.md How-to-Install.md docs kickstart/AvalonOS.ks kickstart/packages.inc packaging/README.md; do
    mkdir -p "$STAGE/$(dirname "$p")"
    cp -r "$p" "$STAGE/$p"
done
mkdir -p "$(dirname "$OUT")"
tar -C "$STAGE" --sort=name --mtime="@$EPOCH" --numeric-owner --owner=0 --group=0 \
    --mode='u=rwX,go=rX' --no-selinux --no-xattrs --no-acls --format=gnu -cf "$OUT" .
echo "make-docs-tarball: $OUT"
