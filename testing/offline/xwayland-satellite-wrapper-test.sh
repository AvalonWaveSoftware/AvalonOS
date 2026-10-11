#!/bin/bash
# avalonos-xwayland-satellite (r6 / R5-X1): never pass kms_swrast;
# LIBGL_ALWAYS_SOFTWARE=1 only when no-3D; exec the real satellite.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WRAP="$ROOT/overlay/usr/bin/avalonos-xwayland-satellite"
T="$(mktemp -d)"
fail=0
cleanup() { rm -rf "$T"; }
trap cleanup EXIT

mkdir -p "$T/bin"
cat > "$T/bin/xwayland-satellite" <<'X'
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
printf '%s\0' "$@" > "$OUT/argv0"
echo $$ > "$OUT/pid"
echo "satellite-ok"
X
chmod +x "$T/bin/xwayland-satellite"

SW='MESA_LOADER_DRIVER_OVERRIDE=kms_swrast'
HW='# /dev/dri/renderD128: hardware GL: virgl
'

run() {
    local name="$1" envcontent="$2" inherited="$3" expect_libgl="$4"
    local d="$T/case-$name"
    mkdir -p "$d"
    if [ "$envcontent" = "MISSING" ]; then
        rm -f "$d/gpu.env"
    else
        printf '%s\n' "$envcontent" > "$d/gpu.env"
    fi
    local envcmd=(env -u MESA_LOADER_DRIVER_OVERRIDE -u LIBGL_ALWAYS_SOFTWARE)
    if [ -n "$inherited" ]; then
        envcmd=(env -u LIBGL_ALWAYS_SOFTWARE "MESA_LOADER_DRIVER_OVERRIDE=$inherited")
    fi
    out="$("${envcmd[@]}" \
        AVALONOS_TEST_HOOKS=1 \
        AVALONOS_GPU_ENV="$d/gpu.env" \
        AVALONOS_XWAYLAND_SATELLITE="$T/bin/xwayland-satellite" \
        OUT="$d" \
        "$WRAP" :1 --foo)" || { echo "FAIL $name: wrapper rc=$?"; fail=1; return; }
    got_ov="$(cat "$d/override")"
    got_gl="$(cat "$d/libgl")"
    if [ -n "$expect_libgl" ]; then expect_gl="set:$expect_libgl"; else expect_gl=unset; fi
    if [ "$got_ov" = unset ] && [ "$got_gl" = "$expect_gl" ] && [ "$out" = "satellite-ok" ]; then
        echo "PASS $name: override=$got_ov libgl=$got_gl"
    else
        echo "FAIL $name: override=$got_ov expect=unset libgl=$got_gl expect=$expect_gl out=$out"
        fail=1
    fi
}

run present "$SW" "" "1"
run absent-hw "$HW" "" ""
run stale-cleared "$HW" "kms_swrast" ""
run missing MISSING "kms_swrast" ""
run inherited-on-sw "$SW" "kms_swrast" "1"

# PID retention + argv
d="$T/case-pid"
mkdir -p "$d"
printf '%s\n' "$SW" > "$d/gpu.env"
sh -c 'echo $$ > "$1/wrap.pid"; exec env -u MESA_LOADER_DRIVER_OVERRIDE \
    AVALONOS_TEST_HOOKS=1 AVALONOS_GPU_ENV="$1/gpu.env" \
    AVALONOS_XWAYLAND_SATELLITE="$2/xwayland-satellite" OUT="$1" \
    "$3" :2 "Arg Space"' \
    sh "$d" "$T/bin" "$WRAP" >/dev/null
if [ -f "$d/pid" ] && [ "$(cat "$d/wrap.pid")" = "$(cat "$d/pid")" ]; then
    python3 - "$d/argv0" <<'PY'
import sys
got = open(sys.argv[1], "rb").read()
if got != b":2\0Arg Space\0":
    raise SystemExit(f"argv mismatch {got!r}")
PY
    echo "PASS pid-retention-and-argv"
else
    echo "FAIL pid-retention"; fail=1
fi

if grep -q 'path "/usr/bin/avalonos-xwayland-satellite"' "$ROOT/overlay/etc/niri/config.kdl"; then
    echo "PASS niri-path"
else
    echo "FAIL niri-path"; fail=1
fi

if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -s sh "$WRAP"; then echo "PASS shellcheck-xwayland-wrapper"
    else echo "FAIL shellcheck-xwayland-wrapper"; fail=1; fi
fi

echo "xwayland-satellite-wrapper-test: $([ "$fail" = 0 ] && echo ALL PASS || echo FAILURES)"
exit "$fail"
