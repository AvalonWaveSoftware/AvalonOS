#!/usr/bin/env bash
# Download the upstream Fedora netinst ISO into cache/ and verify it:
#   1. CHECKSUM file signature against the pinned key keys/fedora-44.gpg (gpgv)
#   2. ISO sha256 against both the signed CHECKSUM and upstream.env
# Re-running is cheap: a cached ISO with the right sha256 is reused.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../upstream.env
. "$ROOT/upstream.env"
CACHE="${AVALONOS_CACHE:-$ROOT/cache}"
mkdir -p "$CACHE"
cd "$CACHE"

die() { echo "fetch-upstream: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "missing tool: $1"; }
need curl; need gpgv; need sha256sum

fetch() { # file
    local f="$1" base
    for base in $UPSTREAM_URLS; do
        echo "fetch-upstream: $base/$f"
        if curl -fL --retry 3 --connect-timeout 20 --speed-limit 1000000 --speed-time 60 -C - -o "$f.part" "$base/$f"; then
            mv "$f.part" "$f"; return 0
        fi
        rm -f "$f.part"
    done
    die "could not download $f from any mirror"
}

[ -s "$UPSTREAM_CHECKSUM" ] || fetch "$UPSTREAM_CHECKSUM"

# Verify the signature with only the pinned key and use the *signed* text.
gpgv --keyring "$ROOT/keys/fedora-44.gpg" --output "$UPSTREAM_CHECKSUM.verified" \
    "$UPSTREAM_CHECKSUM" 2>gpgv.log || { cat gpgv.log >&2; die "bad CHECKSUM signature"; }
grep -q "$FEDORA_KEY_FPR" gpgv.log || { cat gpgv.log >&2; die "CHECKSUM not signed by $FEDORA_KEY_FPR"; }
signed_sha="$(sed -n "s/^SHA256 ($UPSTREAM_ISO) = \([0-9a-f]\{64\}\)\$/\1/p" "$UPSTREAM_CHECKSUM.verified")"
[ "$signed_sha" = "$UPSTREAM_SHA256" ] || die "signed CHECKSUM ($signed_sha) != upstream.env ($UPSTREAM_SHA256)"

check_iso() { [ -f "$UPSTREAM_ISO" ] && echo "$UPSTREAM_SHA256  $UPSTREAM_ISO" | sha256sum -c --status; }
if check_iso; then
    echo "fetch-upstream: cached $UPSTREAM_ISO OK"
else
    fetch "$UPSTREAM_ISO"
    check_iso || die "sha256 mismatch for $UPSTREAM_ISO"
fi
echo "fetch-upstream: $CACHE/$UPSTREAM_ISO verified (sha256 + Fedora $FEDORA_RELEASE signature)"
