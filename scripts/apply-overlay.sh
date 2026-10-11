#!/usr/bin/env bash
# Apply overlay/ to the running system (reference box), the same way the
# kickstart %post does: extract the golden tarball as root:root without
# SELinux xattrs, then restorecon. Run as root.
# Reconstructed in 2026-10 from docs/configs.md; the original script was lost.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ "$(id -u)" = 0 ] || { echo "apply-overlay: run as root" >&2; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
"$ROOT/scripts/make-golden-tarball.sh" "$tmp/overlay.tar"
tar -C / --no-same-owner --no-selinux --numeric-owner -xpf "$tmp/overlay.tar"
if command -v restorecon >/dev/null; then
    restorecon -RF /etc /usr/local/bin /usr/share/AvalonOS /usr/share/wayland-sessions \
        /usr/share/xdg-desktop-portal /usr/share/rofi /usr/share/color-schemes \
        /usr/share/qt6ct /usr/lib64/firefox 2>/dev/null || true
fi
echo "apply-overlay: overlay applied"
