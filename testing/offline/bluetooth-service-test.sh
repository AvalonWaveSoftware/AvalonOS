#!/usr/bin/env bash
# AOS-SEC-09: bluetooth.service must be disabled by default; bluez and blueman stay.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ks="$ROOT/kickstart/AvalonOS.ks"
inc="$ROOT/kickstart/packages.inc"
ok=0
fail=0
check() {
    if "$@"; then
        echo "ok    $*"
        ok=$((ok + 1))
    else
        echo "FAIL  $*"
        fail=$((fail + 1))
    fi
}

# packages remain
grep -qx 'bluez' "$inc"
echo "ok    packages.inc lists bluez"; ok=$((ok+1))
grep -qx 'blueman' "$inc"
echo "ok    packages.inc lists blueman"; ok=$((ok+1))

# services --enabled must not include bluetooth
if grep -E '^services ' "$ks" | grep -E -- '--enabled=[^[:space:]]*bluetooth' >/dev/null; then
    echo "FAIL  services --enabled still lists bluetooth"
    fail=$((fail+1))
else
    echo "ok    services --enabled does not list bluetooth"
    ok=$((ok+1))
fi
if grep -E '^services ' "$ks" | grep -E -- '--disabled=[^[:space:]]*bluetooth' >/dev/null; then
    echo "ok    services --disabled includes bluetooth"
    ok=$((ok+1))
else
    echo "FAIL  services --disabled does not include bluetooth"
    fail=$((fail+1))
fi

# %post must not enable the unit, and must disable it
if grep -E 'systemctl[[:space:]]+enable[[:space:]].*bluetooth\.service' "$ks" >/dev/null; then
    echo "FAIL  kickstart still systemctl enable bluetooth.service"
    fail=$((fail+1))
else
    echo "ok    kickstart does not systemctl enable bluetooth.service"
    ok=$((ok+1))
fi
if grep -E 'systemctl[[:space:]]+disable[[:space:]].*bluetooth\.service' "$ks" >/dev/null; then
    echo "ok    kickstart systemctl disable bluetooth.service"
    ok=$((ok+1))
else
    echo "FAIL  kickstart does not systemctl disable bluetooth.service"
    fail=$((fail+1))
fi

echo "bluetooth-service-test: $ok ok, $fail failed"
exit $(( fail == 0 ? 0 : 1 ))
