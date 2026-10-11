#!/usr/bin/env bash
# Install packages on the reference box without weak deps and log what was
# installed to docs/packages/STAGE.md (NEVRA + UTC timestamp).
#   sudo scripts/dnf-install.sh stage2-desktop waybar rofi
# Reconstructed in 2026-10 from docs/packages/README.md; the log line format is a guess.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ $# -ge 2 ] || { echo "usage: $0 STAGE PKG..." >&2; exit 2; }
stage="$1"; shift
log="$ROOT/docs/packages/$stage.md"
dnf --setopt=install_weak_deps=False -y install "$@"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
for p in "$@"; do
    rpm -q --qf '%{NAME}-%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n' "$p" 2>/dev/null | sed "s/^/- $ts /" >> "$log" || true
done
echo "dnf-install: logged to $log"
