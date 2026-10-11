#!/usr/bin/env bash
# Render kickstart/AvalonOS.ks into a finished kickstart.
#   render-kickstart.sh OUT USER PASSWORD_HASH ROOTPW_LINE
# The %packages body comes from kickstart/packages.inc (comments and blank
# lines dropped). Output is written mode 0600; it contains a password hash.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ $# -eq 4 ] || { echo "usage: $0 OUT USER PASSWORD_HASH ROOTPW_LINE" >&2; exit 2; }
out="$1"
export AV_USER="$2" AV_HASH="$3" AV_ROOTPW="$4"
case "$AV_USER" in ''|*[!a-z0-9_-]*) echo "render-kickstart: bad user name '$AV_USER'" >&2; exit 1;; esac
case "$AV_HASH" in \$*\$*) ;; *) echo "render-kickstart: password hash must be a crypt(3) string (\$y\$..., \$6\$...)" >&2; exit 1;; esac
case "$AV_HASH$AV_ROOTPW" in *\'*|*$'\n'*) echo "render-kickstart: hash/rootpw must not contain quotes or newlines" >&2; exit 1;; esac
case "$AV_ROOTPW" in rootpw\ *) ;; *) echo "render-kickstart: ROOTPW_LINE must start with 'rootpw '" >&2; exit 1;; esac

AV_PACKAGES="$(grep -vE '^[[:space:]]*(#|$)' "$ROOT/kickstart/packages.inc")"
export AV_PACKAGES
umask 077
awk '
function rep(s, k, v,   i, r) { r = ""; while ((i = index(s, k)) > 0) { r = r substr(s, 1, i - 1) v; s = substr(s, i + length(k)) } return r s }
$0 == "@AVALONOS_PACKAGES@" { print ENVIRON["AV_PACKAGES"]; next }
{ l = $0
  l = rep(l, "@AVALONOS_USER_HASH@", ENVIRON["AV_HASH"])
  l = rep(l, "@AVALONOS_ROOTPW_LINE@", ENVIRON["AV_ROOTPW"])
  l = rep(l, "@AVALONOS_USER@", ENVIRON["AV_USER"])
  print l }' "$ROOT/kickstart/AvalonOS.ks" > "$out"
chmod 600 "$out"
if grep -q '@AVALONOS_' "$out"; then echo "render-kickstart: unreplaced placeholder in $out" >&2; exit 1; fi
