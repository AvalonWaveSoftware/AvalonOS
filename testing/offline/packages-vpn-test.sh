#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
inc="$ROOT/kickstart/packages.inc"
ok=0; fail=0
for p in NetworkManager-libreswan libreswan flatpak; do
    if grep -qx "$p" "$inc"; then
        echo "ok    packages.inc lists $p"; ok=$((ok+1))
    else
        echo "FAIL  packages.inc missing $p"; fail=$((fail+1))
    fi
done
echo "summary: $ok ok, $fail failed"
[ "$fail" -eq 0 ]
