#!/usr/bin/env python3
"""P-L22: exact fingerprint line forms are allowed; planted tokens are not."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TQ = chr(39) * 3
cfg = (ROOT / ".gitleaks.toml").read_text().splitlines()
pats = []
for line in cfg:
    s = line.strip()
    if s.startswith(TQ) and s.endswith(TQ + ","):
        pats.append(s[3:-4])
    elif s.startswith(TQ) and s.endswith(TQ):
        pats.append(s[3:-3])
if len(pats) < 4:
    print(f"FAIL  expected at least 4 allowlist regexes, got {len(pats)}: {pats!r}")
    sys.exit(1)
compiled = [re.compile(p) for p in pats]

env = [l for l in (ROOT / "upstream.env").read_text().splitlines() if l.startswith("FEDORA_KEY_FPR=")]
keys = [l for l in (ROOT / "scripts/build-updates-img.sh").read_text().splitlines() if "36F612DC" in l]
pin = [l for l in (ROOT / "keys/PINNED-FINGERPRINTS").read_text().splitlines() if l.startswith("36F612DC")]
if len(env) != 1 or len(keys) != 1 or len(pin) != 1:
    print("FAIL  unexpected fingerprint line counts")
    sys.exit(1)
samples = [env[0], keys[0], pin[0]]
ok = 0
fail = 0
for line in samples:
    if any(p.search(line) for p in compiled):
        print("ok    allowlist matches tree line form")
        ok += 1
    else:
        print("FAIL  tree line not allowed")
        fail += 1
    planted = line + " planted-token"
    if any(p.search(planted) for p in compiled):
        print("FAIL  planted token on a fingerprint line is hidden")
        fail += 1
    else:
        print("ok    planted token on a fingerprint line is not allowed")
        ok += 1
if any("revision = " in p.pattern for p in compiled):
    print("ok    revision allowlist retained")
    ok += 1
else:
    print("FAIL  revision allowlist missing")
    fail += 1
print(f"summary: {ok} ok, {fail} failed")
sys.exit(0 if fail == 0 else 1)
