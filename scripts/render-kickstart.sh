#!/usr/bin/env bash
# Render kickstart/AvalonOS.ks into a finished kickstart.
#   render-kickstart.sh OUT                 default /ks.cfg (interactive disk picker)
#   render-kickstart.sh --erase-all OUT     /ks-erase-all.cfg (ERASES ALL DISKS entry only)
# - AUTH     -> "rootpw --lock" (no user line, no hash: the user is created at
#               first boot; decision 2026-11-14 9:40 CT)
# - STORAGE  -> default: %include of the picker's output; erase-all: static lines
# - PRE      -> default: %pre running kickstart/avalonos-diskpick.sh; erase-all: none
# - PACKAGES -> kickstart/packages.inc (comments and blank lines dropped)
# - INSTGUARD -> both: first %pre, kickstart/avalonos-instguard.sh plus the
#               sha256 manifest of /avalonos/updates.img (P-M1r)
# - TESTSEED -> release (default, AVALONOS_TEST_BUILD=0): a comment, no seed
#               code; QA test builds (AVALONOS_TEST_BUILD=1): install
#               avalonos-testseed and carry avalonos.testseed=1 to the system
#               (decision 2026-11-14 11:31 CT)
# The default output must never contain zerombr or an all-drives clearpart
# (AOS-SEC-19); this script refuses to write it otherwise.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mode=interactive
if [ "${1:-}" = --erase-all ]; then mode=erase-all; shift; fi
[ $# -eq 1 ] || { echo "usage: $0 [--erase-all] OUT" >&2; exit 2; }
out="$1"
TEST_BUILD="${AVALONOS_TEST_BUILD:-0}"
case "$TEST_BUILD" in 0|1) ;; *) echo "render-kickstart: AVALONOS_TEST_BUILD must be 0 or 1" >&2; exit 2;; esac
# shellcheck source=scripts/avalonos-keys.sh
. "$ROOT/scripts/avalonos-keys.sh"   # AV_KEY_NAME / AV_KEY_PIN for this build kind (P-L11)
SEED_RE='avalonos[.-]testseed|AVTESTSEED|testseed-user'
BOOTARGS='rhgb quiet'
AV_PACKAGES="$(grep -vE '^[[:space:]]*(#|$)' "$ROOT/kickstart/packages.inc")"
if [ "$mode" = interactive ]; then
    AV_STORAGE='%include /tmp/avalonos-storage.ks'
    AV_PRE="$(printf '%s\n' '%pre --interpreter=/usr/bin/bash --erroronfail --log=/tmp/avalonos-diskpick.log'
              sed '1{/^#!/d}' "$ROOT/kickstart/avalonos-diskpick.sh"
              printf '%s\n' '%end')"
else
    AV_STORAGE="$(printf '%s\n' \
        '# ERASES ALL DISKS (menu entry "AUTOMATIC INSTALL - ERASES ALL DISKS" only).' \
        'zerombr' \
        'clearpart --all --initlabel' \
        'autopart --type=lvm' \
        "bootloader --location=mbr --timeout=5 --append=\"$BOOTARGS\"")"
    AV_PRE='# (no %pre: the erase-all kickstart has no disk picker)'
fi
# %post signature verifier, written to /root by the main %post (P-M1).
grep -qx 'AVALONOS_SIGCHECK_EOF' "$ROOT/kickstart/avalonos-sigcheck.py" \
    && { echo "render-kickstart: heredoc marker inside avalonos-sigcheck.py" >&2; exit 1; }
AV_SIGCHECK="$(printf '%s\n' "cat > /root/avalonos-sigcheck.py <<'AVALONOS_SIGCHECK_EOF'"
               cat "$ROOT/kickstart/avalonos-sigcheck.py"
               printf '%s\n' 'AVALONOS_SIGCHECK_EOF')"
# Installer guard (P-M1r): pins the content of /avalonos/updates.img.
MANIFEST="$("$ROOT/scripts/build-updates-img.sh" --manifest)"
[ -n "$MANIFEST" ] || { echo "render-kickstart: empty updates.img manifest" >&2; exit 1; }
AV_INSTGUARD="$(printf '%s\n' '%pre --interpreter=/usr/bin/bash --erroronfail --log=/tmp/avalonos-instguard.log'
                printf '%s\n' "cat > /tmp/avalonos-updates.sha256 <<'AVALONOS_MANIFEST_EOF'"
                printf '%s\n' "$MANIFEST"
                printf '%s\n' 'AVALONOS_MANIFEST_EOF'
                sed '1{/^#!/d}' "$ROOT/kickstart/avalonos-instguard.sh"
                printf '%s\n' '%end')"
if [ "$TEST_BUILD" = 1 ]; then
    AV_TESTSEED="$(cat <<'AV_TS_EOF'
# ==== QA TEST BUILD ONLY (AVALONOS_TEST_BUILD=1). Never in a release ISO. ====
dnf -y --setopt=install_weak_deps=False \
    --repofrompath=avalonos-local,"file://$REPO" \
    --setopt=avalonos-local.gpgcheck=1 \
    --setopt=avalonos-local.repo_gpgcheck=1 \
    --setopt=avalonos-local.gpgkey=file:///etc/pki/rpm-gpg/@AVALONOS_KEY_NAME@ \
    --setopt=avalonos-local.skip_if_unavailable=0 \
    install avalonos-testseed
audit_signatures
# Carry avalonos.testseed=1 from the installer to the installed system
# (harmless without the AVTESTSEED disk; see avalonos-testseed).
if grep -qw 'avalonos.testseed=1' /proc/cmdline && command -v grubby >/dev/null; then
    grubby --update-kernel=ALL --args='avalonos.testseed=1'
fi
AV_TS_EOF
)"
else
    AV_TESTSEED='# (release build: no test seed)'
fi
AV_TESTSEED="${AV_TESTSEED//@AVALONOS_KEY_NAME@/$AV_KEY_NAME}"
export AV_PACKAGES AV_STORAGE AV_PRE AV_SIGCHECK AV_INSTGUARD AV_TESTSEED AV_KEY_NAME AV_KEY_PIN
awk '
$0 == "@AVALONOS_PACKAGES@" { print ENVIRON["AV_PACKAGES"]; next }
$0 == "@AVALONOS_STORAGE@"  { print ENVIRON["AV_STORAGE"]; next }
$0 == "@AVALONOS_PRE@"      { print ENVIRON["AV_PRE"]; next }
$0 == "@AVALONOS_INSTGUARD@" { print ENVIRON["AV_INSTGUARD"]; next }
$0 == "@AVALONOS_SIGCHECK@" { print ENVIRON["AV_SIGCHECK"]; next }
$0 == "@AVALONOS_TESTSEED@" { print ENVIRON["AV_TESTSEED"]; next }
$0 == "@AVALONOS_AUTH@"     { print "rootpw --lock"; next }
{ gsub(/@AVALONOS_KEY_NAME@/, ENVIRON["AV_KEY_NAME"]); gsub(/@AVALONOS_KEY_PIN@/, ENVIRON["AV_KEY_PIN"]); print }' "$ROOT/kickstart/AvalonOS.ks" > "$out"
chmod 644 "$out"
if grep -q '@AVALONOS_' "$out"; then echo "render-kickstart: unreplaced placeholder in $out" >&2; exit 1; fi
# P-L11: a kickstart trusts exactly one AvalonOS key, the one of its build kind.
if grep -Eqi "$AV_OTHER_NAME_RE|$AV_OTHER_PIN" "$out" || ! grep -q "=$AV_KEY_PIN\$" "$out"; then
    echo "render-kickstart: $out must pin only $AV_KEY_NAME ($AV_KEY_PIN)" >&2; exit 1
fi
# QA r6 FAIL 1: nothing may be used after %post deleted it.
"$ROOT/scripts/check-ks-order.sh" "$out" || { echo "render-kickstart: use after delete in $out" >&2; exit 1; }
if [ "$TEST_BUILD" = 0 ] && grep -Eq "$SEED_RE" "$out"; then
    echo "render-kickstart: test-seed content in a release kickstart" >&2; exit 1
fi
# shellcheck disable=SC2016  # literal $ in the crypt-hash pattern
if grep -Eq '^(user |rootpw --(iscrypted|plaintext))|--password|\$(y|gy|6|5|2b)\$' "$out"; then
    echo "render-kickstart: credential or hash in $out (not allowed)" >&2; exit 1
fi
if [ "$mode" = interactive ] && grep -Eq '(^|[^-])zerombr|clearpart --all' "$out"; then
    echo "render-kickstart: default kickstart must not contain zerombr / clearpart --all" >&2; exit 1
fi
