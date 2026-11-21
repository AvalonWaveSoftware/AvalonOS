#!/usr/bin/env bash
# Sign AvalonOS RPMs and the repo metadata with the AvalonOS RPM signing key.
# Runs ONLY on the build machine, where the private key lives:
#   key home   ~/avalonos-signing/gnupg      (GNUPGHOME, mode 0700)
#   passphrase ~/avalonos-signing/passphrase (mode 0600; never printed, never copied)
# Usage:
#   sign-rpms.sh --rpms   DIR   rpmsign --addsign every *.rpm in DIR (in place)
#   sign-rpms.sh --repomd DIR   detached armored DIR/repodata/repomd.xml.asc
#   sign-rpms.sh DIR            both, with createrepo_c in between
# AVALONOS_TEST_BUILD=1 (QA test builds, P-L11) signs with the separate TEST
# key instead, from its own folder, GNUPGHOME and passphrase file:
#   ~/avalonos-test-signing/{gnupg,passphrase}   F2BC6934FB6501B6114177A7E221DD18AE8EAAE9
# The production key is never used for test builds and vice versa.
# Afterwards (anywhere): [AVALONOS_TEST_BUILD=1] scripts/check-signatures.sh DIR
set -euo pipefail
case "${AVALONOS_TEST_BUILD:-0}" in
    0) DEF_FPR=F0AA82E5FEB779364658A18D96508B1357FDAB48; DEF_HOME="$HOME/avalonos-signing" ;;
    1) DEF_FPR=F2BC6934FB6501B6114177A7E221DD18AE8EAAE9; DEF_HOME="$HOME/avalonos-test-signing" ;;
    *) echo "sign-rpms: AVALONOS_TEST_BUILD must be 0 or 1" >&2; exit 2 ;;
esac
FPR="${AVALONOS_GPG_FPR:-$DEF_FPR}"
S="${AVALONOS_SIGNING_HOME:-$DEF_HOME}"
export GNUPGHOME="${AVALONOS_GNUPGHOME:-$S/gnupg}"
PASSFILE="${AVALONOS_PASSFILE:-$S/passphrase}"
RPMSIGN="${AVALONOS_RPMSIGN:-$(command -v rpmsign || echo "$HOME/avalonos-signing/tools/usr/bin/rpmsign")}"
[ "${FPR^^}" = "$DEF_FPR" ] \
    || { echo "sign-rpms: $FPR is not the key for AVALONOS_TEST_BUILD=${AVALONOS_TEST_BUILD:-0}" >&2; exit 1; }
mode=all
case "${1:-}" in --rpms|--repomd) mode="${1#--}"; shift;; esac
[ $# -eq 1 ] && [ -d "$1" ] || { echo "usage: $0 [--rpms|--repomd] DIR" >&2; exit 2; }
DIR="$1"
[ -d "$GNUPGHOME" ] || { echo "sign-rpms: no key home $GNUPGHOME (not the build machine?)" >&2; exit 1; }
[ -f "$PASSFILE" ] && [ "$(stat -c %a "$PASSFILE")" = 600 ] \
    || { echo "sign-rpms: $PASSFILE missing or not mode 0600" >&2; exit 1; }
gpg --batch --list-secret-keys "$FPR" >/dev/null 2>&1 \
    || { echo "sign-rpms: secret key $FPR not in $GNUPGHOME" >&2; exit 1; }

sign_rpms() {
    shopt -s nullglob; local rpms=("$DIR"/*.rpm); shopt -u nullglob
    [ ${#rpms[@]} -gt 0 ] || { echo "sign-rpms: no RPMs in $DIR" >&2; exit 1; }
    "$RPMSIGN" --addsign \
        --define "_gpg_path $GNUPGHOME" \
        --define "_gpg_name $FPR" \
        --define "_gpg_sign_cmd_extra_args --batch --pinentry-mode loopback --passphrase-file $PASSFILE" \
        "${rpms[@]}" >/dev/null
    echo "sign-rpms: signed ${#rpms[@]} RPMs with $FPR"
}
sign_repomd() {
    local md="$DIR/repodata/repomd.xml"
    [ -f "$md" ] || { echo "sign-rpms: $md missing (run createrepo_c first)" >&2; exit 1; }
    rm -f "$md.asc"
    gpg --batch --yes --pinentry-mode loopback --passphrase-file "$PASSFILE" \
        --local-user "$FPR" --armor --detach-sign --output "$md.asc" "$md"
    echo "sign-rpms: signed $md"
}
case "$mode" in
    rpms) sign_rpms ;;
    repomd) sign_repomd ;;
    all)
        sign_rpms
        createrepo_c --quiet --update ${SOURCE_DATE_EPOCH:+--revision "$SOURCE_DATE_EPOCH" --set-timestamp-to-revision} "$DIR"
        sign_repomd ;;
esac
