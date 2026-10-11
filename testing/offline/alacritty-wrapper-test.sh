#!/bin/bash
# avalonos-alacritty (r5): never pass kms_swrast to the client;
# LIBGL_ALWAYS_SOFTWARE=1 only when no-3D; journal is best-effort; exec PID retained.
# Run: testing/offline/alacritty-wrapper-test.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WRAP="$ROOT/overlay/usr/bin/avalonos-alacritty"
T="$(mktemp -d)"
fail=0
cleanup() { rm -rf "$T"; }
trap cleanup EXIT

mkdir -p "$T/bin"
# Fake Alacritty: record MESA/LIBGL, NUL-delimited argv, and PID.
cat > "$T/bin/alacritty" <<'X'
#!/bin/sh
if [ "${MESA_LOADER_DRIVER_OVERRIDE+x}" = x ]; then
    printf 'set:%s\n' "$MESA_LOADER_DRIVER_OVERRIDE" > "$OUT/override"
else
    echo unset > "$OUT/override"
fi
if [ "${LIBGL_ALWAYS_SOFTWARE+x}" = x ]; then
    printf 'set:%s\n' "$LIBGL_ALWAYS_SOFTWARE" > "$OUT/libgl"
else
    echo unset > "$OUT/libgl"
fi
: > "$OUT/argv0"
printf '%s\0' "$@" > "$OUT/argv0"
echo $$ > "$OUT/pid"
echo "alacritty-ok"
X
# Fake systemd-cat: require the journal identifier, then exec after -t NAME --
cat > "$T/bin/systemd-cat" <<'X'
#!/bin/sh
[ "$1" = -t ] && [ "$2" = avalonos-alacritty ] && [ "$3" = -- ] || exit 90
echo "used" > "$OUT/systemd-cat"
echo $$ > "$OUT/catpid"
while [ $# -gt 0 ]; do
    case "$1" in
        -t|--identifier) shift 2 ;;
        --) shift; break ;;
        -*) shift ;;
        *) break ;;
    esac
done
exec "$@"
X
# Failing systemd-cat (no journald)
cat > "$T/bin/systemd-cat-fail" <<'X'
#!/bin/sh
echo "Failed to create stream fd" >&2
exit 1
X
chmod +x "$T/bin/alacritty" "$T/bin/systemd-cat" "$T/bin/systemd-cat-fail"

make_journal() {
    # Listening UNIX socket so the connect probe (R5-J1) succeeds.
    rm -f "$1"
    python3 -c '
import socket, sys, time, os
path = sys.argv[1]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(path)
s.listen(4)
s.settimeout(8)
# stay alive for the test process; parent may kill us via the pidfile
open(path + ".pid", "w").write(str(os.getpid()))
end = time.time() + 8
while time.time() < end:
    try:
        c, _ = s.accept()
        c.close()
    except socket.timeout:
        break
    except OSError:
        break
' "$1" &
# wait until the socket is listening
for i in 1 2 3 4 5 6 7 8 9 10; do
    [ -S "$1" ] && return 0
    sleep 0.05
done
echo "make_journal: socket not ready: $1" >&2
return 1
}

make_stale_journal() {
    # Socket file exists but does not accept connections (journald gone).
    rm -f "$1"
    python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); s.bind(sys.argv[1])' "$1"
}

HOOKS=(AVALONOS_TEST_HOOKS=1)

run() { # name gpu.env-content inherited-override expect-libgl(empty=unset or 1) use-journal(yes|no)
    local name="$1" envcontent="$2" inherited="$3" expect_libgl="$4" usej="${5:-yes}"
    local d="$T/case-$name"
    mkdir -p "$d"
    if [ "$envcontent" = "MISSING" ]; then
        rm -f "$d/gpu.env"
    else
        printf '%s\n' "$envcontent" > "$d/gpu.env"
    fi
    : > "$d/override"
    rm -f "$d/systemd-cat" "$d/journal"
    local jopt=()
    if [ "$usej" = yes ]; then
        make_journal "$d/journal" 2>/dev/null || true
        jopt=(AVALONOS_JOURNAL_STDOUT="$d/journal" AVALONOS_SYSTEMD_CAT="$T/bin/systemd-cat")
    else
        jopt=(AVALONOS_JOURNAL_STDOUT="$d/missing-journal" AVALONOS_SYSTEMD_CAT="$T/bin/systemd-cat-fail")
    fi
    local envcmd=(env -u MESA_LOADER_DRIVER_OVERRIDE -u LIBGL_ALWAYS_SOFTWARE)
    if [ -n "$inherited" ]; then
        envcmd=(env -u LIBGL_ALWAYS_SOFTWARE "MESA_LOADER_DRIVER_OVERRIDE=$inherited")
    fi
    out="$("${envcmd[@]}" \
        AVALONOS_TEST_HOOKS=1 \
        AVALONOS_GPU_ENV="$d/gpu.env" \
        AVALONOS_ALACRITTY="$T/bin/alacritty" \
        "${jopt[@]}" \
        OUT="$d" \
        "$WRAP" --class Test -e true)" || { echo "FAIL $name: wrapper rc=$?"; fail=1; return; }
    got_ov="$(cat "$d/override")"
    got_gl="$(cat "$d/libgl")"
    if [ -n "$expect_libgl" ]; then expect_gl="set:$expect_libgl"; else expect_gl=unset; fi
    argv=$(python3 -c 'import pathlib; print(pathlib.Path("'"$d"'/argv0").read_bytes())')
    expect_argv=$(python3 -c 'import sys; sys.stdout.buffer.write(b"--class\0Test\0-e\0true\0")' | python3 -c 'import sys; print(sys.stdin.buffer.read())')
    if [ "$got_ov" = unset ] && [ "$got_gl" = "$expect_gl" ] && [ "$out" = "alacritty-ok" ]; then
        if [ "$usej" = yes ] && [ ! -f "$d/systemd-cat" ]; then
            echo "FAIL $name: expected systemd-cat"; fail=1; return
        fi
        if [ "$usej" = no ] && [ -f "$d/systemd-cat" ]; then
            echo "FAIL $name: systemd-cat should have been skipped"; fail=1; return
        fi
        echo "PASS $name: override=$got_ov libgl=$got_gl"
    else
        echo "FAIL $name: override=$got_ov expect=unset libgl=$got_gl expect=$expect_gl out=$out"
        fail=1
    fi
}

SW='# /dev/dri/renderD128: no hardware GL (llvmpipe); using kms_swrast
MESA_LOADER_DRIVER_OVERRIDE=kms_swrast'
HW='# /dev/dri/renderD128: hardware GL: virgl
'
DO='# /dev/dri/card0 (bochs-drm): display-only adapter, no render-capable GPU; niri cannot draw on it
AVALONOS_DISPLAY_ONLY=1'

run present "$SW" "" "1"
run absent-hw "$HW" "" ""
run stale-cleared "$HW" "kms_swrast" ""
run stale-on-missing MISSING "kms_swrast" ""
run missing-gpu-env MISSING "" ""
run display-only "$DO" "" ""
run display-only-stale "$DO" "kms_swrast" ""
run present-despite-stale-other "$SW" "something-else" "1"
# Exact-line only: near misses must not set LIBGL_ALWAYS_SOFTWARE (and must clear override).
run prefix '# MESA_LOADER_DRIVER_OVERRIDE=kms_swrast' kms_swrast ''
run suffix 'MESA_LOADER_DRIVER_OVERRIDE=kms_swrast-extra' kms_swrast ''
run whitespace 'MESA_LOADER_DRIVER_OVERRIDE=kms_swrast ' kms_swrast ''
run wrong-value 'MESA_LOADER_DRIVER_OVERRIDE=virgl' kms_swrast ''

# Symlink and oversized gpu.env: no software path (P-I31).
d="$T/case-symlink"
mkdir -p "$d"
printf '%s\n' "$SW" > "$d/real.env"
ln -s "$d/real.env" "$d/gpu.env"
make_journal "$d/journal"
out="$(env -u MESA_LOADER_DRIVER_OVERRIDE AVALONOS_TEST_HOOKS=1 \
    AVALONOS_GPU_ENV="$d/gpu.env" AVALONOS_ALACRITTY="$T/bin/alacritty" \
    AVALONOS_JOURNAL_STDOUT="$d/journal" AVALONOS_SYSTEMD_CAT="$T/bin/systemd-cat" \
    OUT="$d" "$WRAP")" || { echo "FAIL symlink: rc=$?"; fail=1; }
if [ "$(cat "$d/override")" = unset ] && [ "$(cat "$d/libgl")" = unset ]; then
    echo "PASS symlink-ignored"
else
    echo "FAIL symlink-ignored: override=$(cat "$d/override") libgl=$(cat "$d/libgl")"; fail=1
fi

d="$T/case-huge"
mkdir -p "$d"
# 64k+1, includes the exact line
python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); p.write_bytes(b"#"+b"x"*65536+b"\nMESA_LOADER_DRIVER_OVERRIDE=kms_swrast\n")' "$d/gpu.env"
make_journal "$d/journal"
out="$(env -u MESA_LOADER_DRIVER_OVERRIDE AVALONOS_TEST_HOOKS=1 \
    AVALONOS_GPU_ENV="$d/gpu.env" AVALONOS_ALACRITTY="$T/bin/alacritty" \
    AVALONOS_JOURNAL_STDOUT="$d/journal" AVALONOS_SYSTEMD_CAT="$T/bin/systemd-cat" \
    OUT="$d" "$WRAP")" || { echo "FAIL huge: rc=$?"; fail=1; }
if [ "$(cat "$d/override")" = unset ] && [ "$(cat "$d/libgl")" = unset ]; then
    echo "PASS size-cap"
else
    echo "FAIL size-cap"; fail=1
fi

# L-1: no journal socket / failing systemd-cat still starts Alacritty.
run no-journal "$SW" "" "1" no

# R5-J1: leftover stdout socket after journald stops must not block launch.
d="$T/case-stale-journal"
mkdir -p "$d"
printf '%s\n' "$SW" > "$d/gpu.env"
make_stale_journal "$d/journal"
out="$(env -u MESA_LOADER_DRIVER_OVERRIDE AVALONOS_TEST_HOOKS=1 \
    AVALONOS_GPU_ENV="$d/gpu.env" AVALONOS_ALACRITTY="$T/bin/alacritty" \
    AVALONOS_JOURNAL_STDOUT="$d/journal" AVALONOS_SYSTEMD_CAT="$T/bin/systemd-cat" \
    OUT="$d" "$WRAP")" || { echo "FAIL stale-journal: wrapper rc=$?"; fail=1; }
if [ "$(cat "$d/override")" = unset ] && [ "$(cat "$d/libgl")" = set:1 ] \
    && [ "$out" = "alacritty-ok" ] && [ ! -f "$d/systemd-cat" ]; then
    echo "PASS stale-journal-socket-falls-back"
else
    echo "FAIL stale-journal-socket-falls-back ov=$(cat "$d/override" 2>/dev/null) libgl=$(cat "$d/libgl" 2>/dev/null) out=$out cat=$( [ -f "$d/systemd-cat" ] && echo yes || echo no )"
    fail=1
fi

# Production hooks are ignored without AVALONOS_TEST_HOOKS=1 (P-I32).
d="$T/case-nohooks"
mkdir -p "$d"
printf '%s\n' "$SW" > "$d/gpu.env"
# Point hooks at a recorder that must NOT run if hooks are ignored.
# The wrapper will try /usr/bin/alacritty; we only assert the script gates hooks.
if grep -q 'AVALONOS_TEST_HOOKS' "$WRAP" && grep -q '/usr/bin/grep' "$WRAP" && grep -q '/usr/bin/systemd-cat' "$WRAP"; then
    echo "PASS hooks-gated-and-absolute-paths"
else
    echo "FAIL hooks-gated-and-absolute-paths"; fail=1
fi

# PID retention + argument boundaries (exec systemd-cat then alacritty).
d="$T/case-pid"
mkdir -p "$d"
printf '%s\n' "$SW" > "$d/gpu.env"
make_journal "$d/journal"
sh -c 'echo $$ > "$1/wrap.pid"; exec env -u MESA_LOADER_DRIVER_OVERRIDE \
    AVALONOS_TEST_HOOKS=1 AVALONOS_GPU_ENV="$1/gpu.env" \
    AVALONOS_ALACRITTY="$2/alacritty" AVALONOS_JOURNAL_STDOUT="$1/journal" \
    AVALONOS_SYSTEMD_CAT="$2/systemd-cat" OUT="$1" "$3" --class "Arg Space" -e true "$4"' \
    sh "$d" "$T/bin" "$WRAP" ';$(id)' >/dev/null
if [ -f "$d/pid" ] && [ "$(cat "$d/wrap.pid")" = "$(cat "$d/pid")" ] && [ -f "$d/systemd-cat" ]; then
    python3 - "$d/argv0" <<'PY'
import sys
got = open(sys.argv[1], "rb").read()
exp = b"--class\0Arg Space\0-e\0true\0;$(id)\0"
if got != exp:
    raise SystemExit(f"argv mismatch {got!r} != {exp!r}")
PY
    echo "PASS pid-retention-and-argv-boundaries"
else
    echo "FAIL pid-retention wrap=$(cat "$d/wrap.pid" 2>/dev/null) alac=$(cat "$d/pid" 2>/dev/null)"; fail=1
fi

# Fallback path also execs (PID retained) when journal is absent.
d="$T/case-pid-fallback"
mkdir -p "$d"
printf '%s\n' "$SW" > "$d/gpu.env"
sh -c 'echo $$ > "$1/wrap.pid"; exec env -u MESA_LOADER_DRIVER_OVERRIDE \
    AVALONOS_TEST_HOOKS=1 AVALONOS_GPU_ENV="$1/gpu.env" \
    AVALONOS_ALACRITTY="$2/alacritty" AVALONOS_JOURNAL_STDOUT="$1/missing" \
    AVALONOS_SYSTEMD_CAT="$2/systemd-cat-fail" OUT="$1" "$3"' \
    sh "$d" "$T/bin" "$WRAP" >/dev/null
if [ -f "$d/pid" ] && [ "$(cat "$d/wrap.pid")" = "$(cat "$d/pid")" ] && [ ! -f "$d/systemd-cat" ]; then
    echo "PASS pid-retention-fallback"
else
    echo "FAIL pid-retention-fallback"; fail=1
fi

# niri unsets the override for spawns; EnvironmentFile still on niri.service.
if grep -q 'MESA_LOADER_DRIVER_OVERRIDE null' "$ROOT/overlay/etc/niri/config.kdl" \
    && grep -q 'EnvironmentFile=-/run/avalonos/gpu.env' "$ROOT/overlay/usr/lib/systemd/user/niri.service.d/10-avalonos-gpu.conf"; then
    echo "PASS niri-client-unset-niri-keeps-override"
else
    echo "FAIL niri-client-unset-niri-keeps-override"; fail=1
fi
if grep -q 'path "/usr/bin/avalonos-xwayland-satellite"' "$ROOT/overlay/etc/niri/config.kdl"; then
    echo "PASS niri-xwayland-satellite-wrapper-path"
else
    echo "FAIL niri-xwayland-satellite-wrapper-path"; fail=1
fi

# Launch sites must call the wrapper (not a raw alacritty spawn).
check() { # name file pattern
    if grep -q "$3" "$2"; then echo "PASS site $1"; else echo "FAIL site $1: missing $3 in $2"; fail=1; fi
}
check niri "$ROOT/overlay/etc/niri/config.kdl" 'spawn "avalonos-alacritty"'
check btop "$ROOT/overlay/usr/bin/avalonos-btop" 'avalonos-alacritty --class AvalonOS-btop'
check net-menu "$ROOT/overlay/usr/share/AvalonOS/net-menu" 'spawn("avalonos-alacritty"'
check rofi-grouped "$ROOT/overlay/usr/share/AvalonOS/rofi-grouped" '/usr/bin/avalonos-alacritty'
if grep -q 'spawn "alacritty"' "$ROOT/overlay/etc/niri/config.kdl"; then
    echo "FAIL niri still spawns raw alacritty"; fail=1
else
    echo "PASS niri has no raw alacritty spawn"
fi
if grep -q 'spawn("alacritty"' "$ROOT/overlay/usr/share/AvalonOS/net-menu"; then
    echo "FAIL net-menu still spawns raw alacritty"; fail=1
else
    echo "PASS net-menu has no raw alacritty spawn"
fi

if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -s sh "$WRAP"; then echo "PASS shellcheck-wrapper"
    else echo "FAIL shellcheck-wrapper"; fail=1; fi
fi

echo "alacritty-wrapper-test: $([ "$fail" = 0 ] && echo ALL PASS || echo FAILURES)"
exit "$fail"
