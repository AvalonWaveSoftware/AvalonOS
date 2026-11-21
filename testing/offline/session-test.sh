#!/bin/bash
# avalonos-session: display-only => message, niri NOT started; otherwise niri
# started as before. systemctl/systemd-cat stubbed; paths redirected with sed.
T="$(mktemp -d)"; S="$(cd "$(dirname "$0")/../.." && pwd)/overlay/usr/bin/avalonos-session"; fail=0
mkdir -p "$T/bin" "$T/dri"
cat > "$T/bin/systemctl" <<'X'
#!/bin/sh
echo "systemctl $*" >> "$CALLS"
case "$*" in *"is-active"*) exit 1;; *"--wait start niri.service"*) exit "${NIRI_RC:-0}";; esac
exit 0
X
printf '#!/bin/sh\ncat >/dev/null\n' > "$T/bin/systemd-cat"; chmod +x "$T/bin/"*
sed -e "s#gpu_env=/run/avalonos/gpu.env#gpu_env=$T/gpu.env#" \
    -e 's#read -r _ < /dev/tty 2>/dev/null || sleep 30#true#' "$S" > "$T/s"
grep -q "gpu_env=$T/gpu.env" "$T/s" || { echo "FAIL: gpu.env path not substituted"; exit 1; }
printf '#!/bin/sh\necho "$LIVE"\n' > "$T/bin/gpu-select"; chmod +x "$T/bin/gpu-select"
run() { # name gpu.env-content live-check(gpu-select --check output) expect-niri(yes|no) expect-msg
    printf '%s\n' "$2" > "$T/gpu.env"
    : > "$T/calls"; out="$(LIVE="$3" AVALONOS_GPU_SELECT="$T/bin/gpu-select" CALLS="$T/calls" XDG_VTNR=1 XDG_RUNTIME_DIR="$T" PATH="$T/bin:$PATH" sh "$T/s" 2>&1)"
    n=$(grep -c -- '--wait start niri.service' "$T/calls")
    got=$([ "$n" = 1 ] && echo yes || echo no)
    if [ "$got" = "$4" ] && { [ -z "$5" ] || echo "$out" | grep -q "$5"; }; then echo "PASS $1: niri started=$got"; else echo "FAIL $1: niri started=$got"; fail=1; fi
    echo "$out" | grep -E 'AvalonOS|GPU:|virtio' | sed 's/^/     /'
}
run S1-bochs-display-only "$(printf '# /dev/dri/card0 (bochs-drm): display-only adapter, no render-capable GPU; niri cannot draw on it\nAVALONOS_DISPLAY_ONLY=1')" display-only no 'no render device'
run S2-display-only-at-boot-primary-renders-now "AVALONOS_DISPLAY_ONLY=1" render yes ''
run S3-virtio-2D-kms_swrast-gate-not-consulted "MESA_LOADER_DRIVER_OVERRIDE=kms_swrast" display-only yes ''
run S4-hardware-GL-gate-not-consulted "# /dev/dri/renderD128: hardware GL: virgl" display-only yes ''
run S5-render-only-device-without-outputs "AVALONOS_DISPLAY_ONLY=1" display-only no 'no render device'
run S6-KMS-GPU-bound-after-boot "AVALONOS_DISPLAY_ONLY=1" "alt /dev/dri/renderD128" no 'reboot so the desktop'
run S7-gpu-select-check-fails "AVALONOS_DISPLAY_ONLY=1" "" no 'no render device'
rm -rf "$T"; echo "session-test: $([ $fail = 0 ] && echo ALL PASS || echo FAILURES)"; exit $fail
