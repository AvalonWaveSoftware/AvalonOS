#!/usr/bin/env bash
# Offline checks for first-boot Flathub / Obsidian (ADR 0021).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
unit="$ROOT/overlay/usr/lib/systemd/system/avalonos-flathub-obsidian.service"
script="$ROOT/overlay/usr/libexec/avalonos/flathub-obsidian"
inc="$ROOT/kickstart/packages.inc"
preset="$ROOT/packaging/rpm/80-avalonos.preset"
spec="$ROOT/packaging/rpm/avalonos.spec"
ok=0
fail=0
check() {
    local d="$1"; shift
    if "$@"; then
        echo "ok    $d"
        ok=$((ok + 1))
    else
        echo "FAIL  $d"
        fail=$((fail + 1))
    fi
}

check "packages.inc lists flatpak" grep -qx 'flatpak' "$inc"
check "packages.inc does not list a flathub RPM" sh -c '! grep -qi flathub "$0"' "$inc"
check "script is executable" test -x "$script"
check "script adds Flathub only at run time" grep -q 'remote-add --if-not-exists --system' "$script"
check "script installs md.obsidian.Obsidian" grep -q 'md.obsidian.Obsidian' "$script"
check "script stamps /var/lib/avalonos/obsidian-flatpak.done" grep -q '/var/lib/avalonos/obsidian-flatpak.done' "$script"
check "unit After=network-online.target" grep -q '^After=network-online.target$' "$unit"
check "unit Wants=network-online.target" grep -q '^Wants=network-online.target$' "$unit"
check "unit is not Before=greetd" sh -c '! grep -qi "^Before=.*greetd" "$0"' "$unit"
check "unit is not Before=display-manager" sh -c '! grep -qi "^Before=.*display-manager" "$0"' "$unit"
check "unit WantedBy=multi-user.target" grep -q '^WantedBy=multi-user.target$' "$unit"
check "unit retries on failure" grep -q '^Restart=on-failure$' "$unit"
check "unit does not start-limit-out after a burst" grep -q '^StartLimitIntervalSec=0$' "$unit"
# L-2: StartLimitIntervalSec belongs in [Unit], not [Service].
unit_section=$(awk 'BEGIN{p=0} /^\[Unit\]/{p=1} /^\[/{if($0!="[Unit]")p=0} p' "$unit")
svc_has=$(awk 'BEGIN{p=0} /^\[Service\]/{p=1} /^\[/{if($0!="[Service]")p=0} p && /StartLimitIntervalSec/{c=1} END{exit !c}' "$unit" && echo yes || echo no)
if printf '%s\n' "$unit_section" | grep -q '^StartLimitIntervalSec=0$' && [ "$svc_has" = no ]; then
    echo "ok    StartLimitIntervalSec is under [Unit] not [Service]"
    ok=$((ok + 1))
else
    echo "FAIL  StartLimitIntervalSec is under [Unit] not [Service]"
    fail=$((fail + 1))
fi
check "unit hardening ProtectSystem=strict" grep -q '^ProtectSystem=strict$' "$unit"
check "unit hardening NoNewPrivileges" grep -q '^NoNewPrivileges=yes$' "$unit"
check "unit hardening ProtectHome" grep -q '^ProtectHome=yes$' "$unit"
check "script asserts Flathub URL and GPG" grep -q 'assert_flathub_remote' "$script"
check "preset enables the unit" grep -q '^enable avalonos-flathub-obsidian.service$' "$preset"
check "spec Requires flatpak in firstboot" grep -q 'Requires:[[:space:]]*flatpak' "$spec"
check "ISO overlay does not vendor a Flathub repo file" sh -c '! find "$0/overlay" -iname "*.flatpakrepo" | grep -q .' "$ROOT"
check "ISO overlay does not vendor a Flathub ostree" sh -c '! find "$0/overlay" -type d \( -name ostree -o -path "*/flatpak/repo/*" \) | grep -q .' "$ROOT"
check "ISO overlay does not vendor Obsidian app content" sh -c '! find "$0/overlay" -path "*md.obsidian.Obsidian*" | grep -q .' "$ROOT"

# Runtime: stamp present -> exit 0 without calling flatpak.
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
install -d -m 0755 "$T/var/lib/avalonos" "$T/bin" "$T/usr/libexec/avalonos"
: > "$T/var/lib/avalonos/obsidian-flatpak.done"
cat > "$T/bin/flatpak" << 'FAKE'
#!/bin/sh
echo "flatpak should not run when stamped" >&2
exit 97
FAKE
chmod +x "$T/bin/flatpak"
# Run the real script with a rewritten stamp path via a wrapper copy.
# The script uses absolute stamp /var/lib/... so test the stamp branch
# by running under a fake root only for the no-route and missing-flatpak cases
# through a patched copy that honors AVALONOS_FLATHUB_ROOT if we add it.
# Avoid changing production behavior: test stamp short-circuit by
# invoking a copy whose STAMP is rewritten for the test.
cp "$script" "$T/script"
sed 's#/var/lib/avalonos#'"$T"'/var/lib/avalonos#g' "$T/script" > "$T/script.new"
mv "$T/script.new" "$T/script"
chmod +x "$T/script"
if PATH="$T/bin:$PATH" "$T/script"; then
    echo "ok    stamped script exits 0 without calling flatpak"
    ok=$((ok + 1))
else
    echo "FAIL  stamped script should exit 0"
    fail=$((fail + 1))
fi

# Missing default route, no stamp: exit 1, no stamp written, flatpak not called.
rm -f "$T/var/lib/avalonos/obsidian-flatpak.done"
cat > "$T/bin/ip" << 'FAKE'
#!/bin/sh
# no default route
exit 0
FAKE
chmod +x "$T/bin/ip"
cat > "$T/bin/flatpak" << 'FAKE'
#!/bin/sh
echo "flatpak should not run without a route" >&2
exit 97
FAKE
chmod +x "$T/bin/flatpak"
rc=0
PATH="$T/bin:/usr/bin:/bin" "$T/script" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 1 ] && [ ! -e "$T/var/lib/avalonos/obsidian-flatpak.done" ]; then
    echo "ok    no default route exits 1 without a stamp"
    ok=$((ok + 1))
else
    echo "FAIL  no default route (rc=$rc stamp=$( [ -e "$T/var/lib/avalonos/obsidian-flatpak.done" ] && echo yes || echo no ))"
    fail=$((fail + 1))
fi

# Successful install path (fake ip + flatpak).
cat > "$T/bin/ip" << 'FAKE'
#!/bin/sh
if [ "$1" = "-4" ] && [ "$2" = "route" ]; then
    echo "default via 192.0.2.1 dev eth0"
    exit 0
fi
exit 0
FAKE
chmod +x "$T/bin/ip"
install -d "$T/log"
cat > "$T/bin/flatpak" << FAKE
#!/bin/sh
echo "\$@" >> "$T/log/flatpak.args"
# "info" should fail the first time (not installed) unless asking for metadata.
if [ "\$1" = "info" ]; then
    if echo "\$*" | grep -q -- '-m'; then
        echo "commit: deadbeefcafebabe"
        exit 0
    fi
    exit 1
fi
if [ "\$1" = "remotes" ]; then
    case "\$*" in
        *name,url*) printf 'flathub\thttps://dl.flathub.org/repo/\n' ;;
        *name,options*) printf 'flathub\tsystem\n' ;;
        *) printf 'flathub\thttps://dl.flathub.org/repo/\n' ;;
    esac
    exit 0
fi
exit 0
FAKE
chmod +x "$T/bin/flatpak"
if PATH="$T/bin:/usr/bin:/bin" "$T/script" && [ -e "$T/var/lib/avalonos/obsidian-flatpak.done" ]; then
    echo "ok    successful fake install writes the stamp"
    ok=$((ok + 1))
else
    echo "FAIL  successful fake install"
    fail=$((fail + 1))
fi
if grep -q 'remote-add --if-not-exists --system flathub' "$T/log/flatpak.args" \
   && grep -q 'install -y --system --noninteractive flathub md.obsidian.Obsidian' "$T/log/flatpak.args"; then
    echo "ok    fake flatpak received system Flathub add and Obsidian install"
    ok=$((ok + 1))
else
    echo "FAIL  fake flatpak argv"
    sed 's/^/      /' "$T/log/flatpak.args" 2>/dev/null || true
    fail=$((fail + 1))
fi

# Already-installed (info succeeds) writes stamp without install.
rm -f "$T/var/lib/avalonos/obsidian-flatpak.done" "$T/log/flatpak.args"
: > "$T/log/flatpak.args"
cat > "$T/bin/flatpak" << FAKE
#!/bin/sh
echo "\$@" >> "$T/log/flatpak.args"
if [ "\$1" = "info" ]; then
    echo "Commit: alreadyinstalledcommit"
    exit 0
fi
if [ "\$1" = "remotes" ]; then
    case "\$*" in
        *name,url*) printf 'flathub\thttps://dl.flathub.org/repo/\n' ;;
        *name,options*) printf 'flathub\tsystem\n' ;;
        *) printf 'flathub\thttps://dl.flathub.org/repo/\n' ;;
    esac
    exit 0
fi
echo "unexpected flatpak \$*" >&2
exit 97
FAKE
chmod +x "$T/bin/flatpak"
if PATH="$T/bin:/usr/bin:/bin" "$T/script" && [ -e "$T/var/lib/avalonos/obsidian-flatpak.done" ] \
   && ! grep -q 'install' "$T/log/flatpak.args"; then
    echo "ok    already-installed app only checks info and stamps"
    ok=$((ok + 1))
else
    echo "FAIL  already-installed short-circuit"
    fail=$((fail + 1))
fi

# P-L25: a hijacked Flathub URL must fail closed (no stamp, no install).
rm -f "$T/var/lib/avalonos/obsidian-flatpak.done" "$T/log/flatpak.args"
: > "$T/log/flatpak.args"
cat > "$T/bin/flatpak" << FAKE
#!/bin/sh
echo "\$@" >> "$T/log/flatpak.args"
if [ "\$1" = "info" ]; then
    exit 1
fi
if [ "\$1" = "remotes" ]; then
    case "\$*" in
        *name,url*) printf 'flathub\thttps://evil.example/repo/\n' ;;
        *name,options*) printf 'flathub\tsystem\n' ;;
        *) printf 'flathub\thttps://evil.example/repo/\n' ;;
    esac
    exit 0
fi
exit 0
FAKE
chmod +x "$T/bin/flatpak"
rc=0
PATH="$T/bin:/usr/bin:/bin" "$T/script" >/dev/null 2>&1 || rc=$?
if [ "$rc" -ne 0 ] && [ ! -e "$T/var/lib/avalonos/obsidian-flatpak.done" ] \
   && ! grep -q 'install' "$T/log/flatpak.args"; then
    echo "ok    hijacked Flathub URL fails closed without install or stamp"
    ok=$((ok + 1))
else
    echo "FAIL  hijacked Flathub URL (rc=$rc stamp=$( [ -e "$T/var/lib/avalonos/obsidian-flatpak.done" ] && echo yes || echo no ))"
    fail=$((fail + 1))
fi

# Fedora reports disabled verification as no-gpg-verify.
rm -f "$T/var/lib/avalonos/obsidian-flatpak.done" "$T/log/flatpak.args"
sed 's#https://evil.example/repo/#https://dl.flathub.org/repo/#g; s/system/no-gpg-verify,system/' "$T/bin/flatpak" > "$T/bin/flatpak.new"
mv "$T/bin/flatpak.new" "$T/bin/flatpak"
chmod +x "$T/bin/flatpak"
rc=0
PATH="$T/bin:/usr/bin:/bin" "$T/script" >/dev/null 2>&1 || rc=$?
if [ "$rc" -ne 0 ] && [ ! -e "$T/var/lib/avalonos/obsidian-flatpak.done" ] \
   && ! grep -q '^install ' "$T/log/flatpak.args"; then
    echo "ok    no-gpg-verify fails closed without install or stamp"
    ok=$((ok + 1))
else
    echo "FAIL  no-gpg-verify remote"
    fail=$((fail + 1))
fi

echo "summary: $ok ok, $fail failed"
[ "$fail" -eq 0 ]
