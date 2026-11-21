#!/usr/bin/env bash
# /avalonos on an AvalonOS ISO (Code Security P-L12; Master Chief 2026-11-14
# 17:43 CT: "Fix it before release"). Allowlist, not a scan:
#   check-avalonos-dir.sh DIR
# DIR must hold EXACTLY packages.inc, the key of this build kind
# (AVALONOS_TEST_BUILD, scripts/avalonos-keys.sh), updates.img and repo/; no
# other file, directory, link or special file (hidden ones included);
# packages.inc == kickstart/packages.inc; the key == keys/<name>; updates.img
# == build-updates-img.sh output rebuilt with the image's own timestamp
# (nothing appended, nothing extra inside); repo/ passes check-signatures.sh,
# which accepts exactly the files the signed metadata covers.
# Used by verify-iso.sh (ISO) and build-iso.sh (payload before mastering).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/avalonos-keys.sh
. "$ROOT/scripts/avalonos-keys.sh"
D="${1:?usage: $0 DIR}"
fail=0
no() { echo "check-avalonos-dir: FAIL $*" >&2; fail=1; }
[ -d "$D" ] && [ ! -L "$D" ] || { echo "check-avalonos-dir: FAIL $D is not a directory" >&2; exit 1; }
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
want="$(printf '%s\n' "d repo" "f $AV_KEY_NAME" "f packages.inc" "f updates.img" | LC_ALL=C sort)"
got="$(cd "$D" && find . -mindepth 1 -maxdepth 1 -printf '%y %P\n' | LC_ALL=C sort)"
[ "$got" = "$want" ] || no "top level is not exactly packages.inc, $AV_KEY_NAME, updates.img, repo/: $(diff <(echo "$want") <(echo "$got") | sed -n 's/^> //p' | tr '\n' ' ')"
odd="$(cd "$D" && find . -mindepth 1 ! -type f ! -type d -printf '%P ' )"
[ -z "$odd" ] || no "links or special files: $odd"
if ! { [ -f "$D/packages.inc" ] && cmp -s "$D/packages.inc" "$ROOT/kickstart/packages.inc"; }; then no "packages.inc differs from kickstart/packages.inc"; fi
if ! { [ -f "$D/$AV_KEY_NAME" ] && cmp -s "$D/$AV_KEY_NAME" "$AV_KEY_FILE"; }; then no "$AV_KEY_NAME differs from keys/$AV_KEY_NAME"; fi
m="$(gzip -dc "$D/updates.img" 2>/dev/null | head -c 110 | cut -c47-54 || true)"
if [[ "$m" =~ ^[0-9a-fA-F]{8}$ ]] && SOURCE_DATE_EPOCH=$((16#$m)) "$ROOT/scripts/build-updates-img.sh" "$t/updates.img" \
   && cmp -s "$t/updates.img" "$D/updates.img"; then :; else
    no "updates.img is not byte-identical to build-updates-img.sh output"
fi
if [ -d "$D/repo" ] && [ ! -L "$D/repo" ]; then
    "$ROOT/scripts/check-signatures.sh" "$D/repo" "$AV_KEY_FILE" > "$t/cs.log" 2>&1 || { no "repo/ fails check-signatures.sh:"; sed 's/^/    /' "$t/cs.log" >&2; }
fi
[ "$fail" = 0 ] || exit 1
echo "check-avalonos-dir: OK, $D holds exactly packages.inc, $AV_KEY_NAME, updates.img and the signed repo"
