#!/bin/bash
# L-6: avalonos-btop only toggles a live Alacritty pidfile PID.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BTOP="$ROOT/overlay/usr/bin/avalonos-btop"
T="$(mktemp -d)"
fail=0
cleanup() { rm -rf "$T"; }
trap cleanup EXIT

# Stub avalonos-alacritty: linger so the pidfile PID is "ours", write comm/exe via a fake /proc?
# We cannot fake /proc easily. Instead: spawn a real sleep renamed? Or a copy named alacritty.
mkdir -p "$T/bin" "$T/rt"
# A helper that execs a process named alacritty (copy of sleep).
cp /bin/sleep "$T/bin/alacritty"
chmod +x "$T/bin/alacritty"

# The product script calls `avalonos-alacritty` from PATH. Stub it to exec our named binary.
cat > "$T/bin/avalonos-alacritty" <<'X'
#!/bin/sh
# Ignore args; start a long-lived process whose comm is alacritty.
exec "$FAKE_ALACRITTY" 30
X
chmod +x "$T/bin/avalonos-alacritty"

export XDG_RUNTIME_DIR="$T/rt"
export PATH="$T/bin:$PATH"
export FAKE_ALACRITTY="$T/bin/alacritty"

# First start
if ! "$BTOP"; then echo "FAIL start"; exit 1; fi
pid=$(cat "$T/rt/avalonos-btop.pid")
comm=$(cat /proc/$pid/comm)
if [ "$comm" != alacritty ]; then echo "FAIL comm=$comm"; exit 1; fi
# Second call should kill it
if ! "$BTOP"; then echo "FAIL toggle-off"; exit 1; fi
if [ -f "$T/rt/avalonos-btop.pid" ]; then echo "FAIL pidfile remains after off"; exit 1; fi
if kill -0 "$pid" 2>/dev/null; then echo "FAIL pid still alive"; exit 1; fi
echo "ok  toggle-live-alacritty"

# Stale pidfile pointing at sleep (not alacritty) must be ignored, not killed.
cp /bin/sleep "$T/bin/not-alacritty"
"$T/bin/not-alacritty" 30 &
stale=$!
echo "$stale" > "$T/rt/avalonos-btop.pid"
if ! "$BTOP"; then echo "FAIL start-over-stale"; kill "$stale" 2>/dev/null; exit 1; fi
if ! kill -0 "$stale" 2>/dev/null; then echo "FAIL killed non-alacritty pid"; exit 1; fi
new=$(cat "$T/rt/avalonos-btop.pid")
if [ "$new" = "$stale" ]; then echo "FAIL reused stale pid"; kill "$stale"; exit 1; fi
kill "$stale" 2>/dev/null || true
kill "$new" 2>/dev/null || true
echo "ok  stale-non-alacritty-ignored"

# Missing XDG_RUNTIME_DIR
if XDG_RUNTIME_DIR= "$BTOP" 2>/dev/null; then echo "FAIL missing-runtime"; exit 1; fi
echo "ok  missing-runtime"

if command -v shellcheck >/dev/null; then
    shellcheck -s sh "$BTOP" && echo "ok  shellcheck-btop" || { echo "FAIL shellcheck-btop"; exit 1; }
fi
echo "btop-pidfile-test: ok"
