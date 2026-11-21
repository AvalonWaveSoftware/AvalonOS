#!/usr/bin/env bash
# Use-after-delete check for rendered kickstarts (QA r6 FAIL 1: the QA test
# block called /root/avalonos-sigcheck.py after %post had deleted it).
#   check-ks-order.sh KS...
# For every `rm PATH...` in a %pre/%post section, no later non-comment line in
# the kickstart may mention PATH unless a line in between re-creates it (PATH
# is then the target of cp/mv/install/mkdir/ln, or of a > / >> redirect).
# Calling a shell function whose body mentions PATH counts as a use of PATH.
# Paths are compared literally (quotes removed), so "$REPO" and /root/x both count.
set -euo pipefail
[ $# -ge 1 ] || { echo "usage: $0 KS..." >&2; exit 2; }
exec python3 - "$@" <<'PY'
import re, shlex, sys
rc = 0
for ks in sys.argv[1:]:
    lines = open(ks, encoding="utf-8").read().split("\n")
    gone = {}                                   # path -> line number of the rm
    funcs, cur = {}, None                       # shell function -> body text
    for l in lines:
        m = re.match(r"\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{", l)
        if m: cur = m.group(1); funcs[cur] = ""; continue
        if cur is not None:
            if re.match(r"^\}\s*$", l): cur = None
            else: funcs[cur] += l.split("#", 1)[0] + "\n"
    def plain(t): return t.replace('"', "").replace("'", "")
    for n, l in enumerate(lines, 1):
        s = l.strip()
        if not s or s.startswith("#"): continue
        try: words = shlex.split(s, comments=True, posix=True)
        except ValueError: words = s.split()
        called = [f for f in funcs if re.search(r"(^|[;&|({]\s*|\s)" + f + r"(\s|;|$)", s) and not re.match(r"\s*(function\s+)?" + f + r"\s*\(\)", s)]
        for path, at in list(gone.items()):
            via = [f for f in called if path in plain(funcs[f])]
            if via:
                print(f"check-ks-order: {ks}:{n}: {via[0]}() uses {path}, deleted at line {at}: {s[:100]}", file=sys.stderr)
                rc = 1; continue
            if path in plain(s):
                cmd = words[0] if words else ""
                recreate = (cmd in ("cp", "mv", "install", "mkdir", "ln") and words[-1] == path) or \
                           re.search(r">>?\s*['\"]?" + re.escape(path) + r"['\"]?(\s|$)", s)
                if recreate: del gone[path]; continue
                if cmd == "rm": continue
                print(f"check-ks-order: {ks}:{n}: uses {path}, deleted at line {at}: {s[:100]}", file=sys.stderr)
                rc = 1
        if words and words[0] == "rm":
            for w in words[1:]:
                if not w.startswith("-"): gone[w] = n
sys.exit(rc)
PY
