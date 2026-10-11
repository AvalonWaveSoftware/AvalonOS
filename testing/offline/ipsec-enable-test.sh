#!/usr/bin/env bash
# H-1 / P-L29: Fedora ipsec.service is enabled on a fresh install,
# without a tmpfiles wants link that would undo an admin disable.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ok=0; fail=0
check() {
    local d="$1"; shift
    if "$@"; then echo "ok    $d"; ok=$((ok+1))
    else echo "FAIL  $d"; fail=$((fail+1)); fi
}
preset="$ROOT/packaging/rpm/80-avalonos.preset"
ks="$ROOT/kickstart/AvalonOS.ks"
spec="$ROOT/packaging/rpm/avalonos.spec"
check "preset enables ipsec.service" grep -q '^enable ipsec.service$' "$preset"
check "kickstart enables ipsec.service" grep -q 'systemctl enable ipsec.service' "$ks"
check "spec %post uses %systemd_post ipsec.service" grep -q '%systemd_post ipsec.service' "$spec"
check "spec %post does not systemctl enable ipsec" sh -c '! grep -q "systemctl enable ipsec.service" "$0"' "$spec"
check "spec %files network does not list tmpfiles" sh -c '! grep -q tmpfilesdir/avalonos-ipsec "$0"' "$spec"
if [ -e "$ROOT/overlay/usr/lib/tmpfiles.d/avalonos-ipsec.conf" ]; then
    echo "FAIL  tmpfiles.d/avalonos-ipsec.conf must not ship"; fail=$((fail+1))
else
    echo "ok    no ipsec tmpfiles.d link"; ok=$((ok+1))
fi
if find "$ROOT/overlay" -type l | grep -q .; then
    echo "FAIL  overlay contains a symlink"; fail=$((fail+1))
    find "$ROOT/overlay" -type l
else
    echo "ok    overlay has no symlinks"; ok=$((ok+1))
fi
echo "summary: $ok ok, $fail failed"
[ "$fail" -eq 0 ]
