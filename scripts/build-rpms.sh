#!/usr/bin/env bash
# Build the AvalonOS RPMs and a dnf repo from them.
#   build-rpms.sh TOPDIR REPODIR
# TOPDIR: rpmbuild work tree (created); REPODIR: output repo (createrepo_c).
# Reproducible: Source0 is a sorted tar with mtimes = SOURCE_DATE_EPOCH, and
# rpmbuild clamps file mtimes / build time to it. Grammar tarballs for the
# parser RPM and the language-server release files for the LSP RPM are
# fetched once into $AVALONOS_CACHE and checked against
# packaging/rpm/nvim-parsers.sha256 / nvim-lsp.sha256.
# Signing: not done here (the private key never leaves the build machine).
# scripts/sign-rpms.sh signs the RPMs and repomd.xml there; build-iso.sh
# refuses unsigned repos (scripts/check-signatures.sh).
# AVALONOS_TEST_BUILD=1 (QA test builds only; default 0 = release): also put
# testing/testseed in Source0 and build avalonos-testseed (rpmbuild --with
# testseed). Release builds contain no test-seed code at all.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ $# -eq 2 ] || { echo "usage: $0 TOPDIR REPODIR" >&2; exit 2; }
TOP="$1"; REPO="$2"
CACHE="${AVALONOS_CACHE:-$ROOT/cache}/grammars"
EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null || echo 0)}"
export SOURCE_DATE_EPOCH="$EPOCH"
SPEC="$ROOT/packaging/rpm/avalonos.spec"
VER="$(awk '/^Version:/ {print $2; exit}' "$SPEC")"
TEST_BUILD="${AVALONOS_TEST_BUILD:-0}"
case "$TEST_BUILD" in
    0) WITH=(--without testseed); TESTSRC=() ;;
    1) WITH=(--with testseed); TESTSRC=(testing/testseed)
       echo "build-rpms: AVALONOS_TEST_BUILD=1: QA TEST BUILD (avalonos-testseed included); never release this repo" >&2 ;;
    *) echo "build-rpms: AVALONOS_TEST_BUILD must be 0 or 1" >&2; exit 2 ;;
esac
# Source0 carries only the public key of this build kind (P-L11): release =
# production key, test = TEST key; the spec ships that one file.
# shellcheck source=scripts/avalonos-keys.sh
. "$ROOT/scripts/avalonos-keys.sh"

rm -rf "$TOP" "$REPO"; mkdir -p "$TOP"/{SOURCES,SPECS,BUILD,RPMS,SRPMS} "$REPO" "$CACHE"

# ---- Source0: the AvalonOS tree --------------------------------------------
stage="$(mktemp -d)"; trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/avalonos-$VER"
(cd "$ROOT" && cp -a --parents LICENSE README.md INDEX.md How-to-Install.md docs overlay \
    kickstart/AvalonOS.ks kickstart/packages.inc packaging/rpm/80-avalonos.preset scripts/tailwhip \
    "keys/$AV_KEY_NAME" ${TESTSRC[@]+"${TESTSRC[@]}"} \
    "$stage/avalonos-$VER/")
find "$stage" -name __pycache__ -prune -exec rm -rf {} +
tar -C "$stage" --sort=name --mtime="@$EPOCH" --clamp-mtime --owner=0 --group=0 --numeric-owner \
    --no-selinux --no-xattrs --no-acls --format=gnu -cf - "avalonos-$VER" \
    | gzip -n -9 > "$TOP/SOURCES/avalonos-$VER.tar.gz"

# ---- pinned upstream sources (parsers, language servers) ---------------------
# Each spec's sources are fetched once into the cache and must match the
# sha256 list next to it, else the build stops.
SPECS=(avalonos.spec avalonos-nvim-parsers.spec avalonos-nvim-lsp.spec)
fetch_pinned() {  # SPEC SHA256FILE
    local spec="$ROOT/packaging/rpm/$1" sums="$ROOT/packaging/rpm/$2" sum file url
    while read -r sum file; do
        if ! echo "$sum  $CACHE/$file" | sha256sum -c --quiet 2>/dev/null; then
            url="$(rpmspec -P "$spec" 2>/dev/null | awk '/^Source[0-9]+:/ {print $2}' | grep -F -m1 "/${file%.tar.gz}" || true)"
            url="${url%%#*}"
            [ -n "$url" ] || { echo "build-rpms: no Source URL for $file in $1" >&2; exit 1; }
            curl -fsSL --retry 3 -o "$CACHE/$file.part" "$url" && mv "$CACHE/$file.part" "$CACHE/$file"
            echo "$sum  $CACHE/$file" | sha256sum -c --quiet || { echo "build-rpms: checksum mismatch: $file" >&2; exit 1; }
        fi
        cp -p "$CACHE/$file" "$TOP/SOURCES/"
    done < "$sums"
}
fetch_pinned avalonos-nvim-parsers.spec nvim-parsers.sha256
fetch_pinned avalonos-nvim-lsp.spec nvim-lsp.sha256

# ---- rpmbuild ------------------------------------------------------------------
for s in "${SPECS[@]}"; do
    cp "$ROOT/packaging/rpm/$s" "$TOP/SPECS/"
done
# SRPMs record the mtimes of the spec and sources: pin them too.
touch -h -d "@$EPOCH" "$TOP"/SOURCES/* "$TOP"/SPECS/*
for s in "${SPECS[@]}"; do
    rpmbuild -ba "$TOP/SPECS/$s" "${WITH[@]}" \
        --define "_topdir $TOP" \
        --define "use_source_date_epoch_as_buildtime 1" \
        --define "clamp_mtime_to_source_date_epoch 1" \
        --define "_buildhost avalonos-build"
done
find "$TOP/RPMS" -name '*.rpm' ! -name '*-debuginfo-*' ! -name '*-debugsource-*' -exec cp -p {} "$REPO/" \;
# primary.xml records each RPM's file mtime: pin it.
find "$REPO" -name '*.rpm' -exec touch -h -d "@$EPOCH" {} +
if [ "$TEST_BUILD" = 0 ] && compgen -G "$REPO/avalonos-testseed-*" >/dev/null; then
    echo "build-rpms: release build produced avalonos-testseed" >&2; exit 1
fi
createrepo_c --quiet --revision "$EPOCH" --set-timestamp-to-revision "$REPO"
echo "build-rpms: $(find "$REPO" -name '*.rpm' | wc -l) RPMs in $REPO"
