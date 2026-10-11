#!/usr/bin/env bash
# Offline tests for kickstart/avalonos-instguard.sh boot-option parsing (P-L10, P-L18).
# Does not run the updates.img or repo checks; extracts the cmdline scanner.
# The shipped guard must not honor AVALONOS_INSTGUARD_ROOT; this test only
# rewrites root= on a copy.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
src="$ROOT/kickstart/avalonos-instguard.sh"
python3 - "$src" <<'PY'
import pathlib, subprocess, sys, tempfile, os

src = pathlib.Path(sys.argv[1]).read_text()
if "AVALONOS_INSTGUARD_ROOT" in src:
    print("FAIL  shipped instguard still mentions AVALONOS_INSTGUARD_ROOT")
    sys.exit(1)
print("ok    shipped instguard has no AVALONOS_INSTGUARD_ROOT hook")

start = src.find("python3 - <<'AVIG'")
assert start >= 0
block = src[src.find("\n", start)+1:]
block = block.split("\nAVIG\n", 1)[0]
if 'root = pathlib.Path("/")' not in block:
    print("FAIL  could not find shipped root = pathlib.Path(\"/\") to rewrite in a test copy")
    sys.exit(1)

ns_ok = 1  # hook-absent check above
ns_fail = 0

def run(cmdline=None, extra_files=None, expect=0, name="", env_root=None):
    global ns_ok, ns_fail
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        (tmp / "proc").mkdir()
        if cmdline is not None:
            (tmp / "proc/cmdline").write_text(cmdline)
        if extra_files:
            for rel, text in extra_files.items():
                p = tmp / rel
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(text)
        # Test-only copy: substitute the fs root. The shipped file is unchanged.
        copy = block.replace('root = pathlib.Path("/")', f'root = pathlib.Path({str(tmp)!r})', 1)
        env = os.environ.copy()
        if env_root is not None:
            env["AVALONOS_INSTGUARD_ROOT"] = env_root
        r = subprocess.run([sys.executable, "-c", copy], env=env, capture_output=True, text=True)
        if r.returncode == expect:
            print(f"ok    {name}")
            ns_ok += 1
        else:
            print(f"FAIL  {name} (exit {r.returncode}, expected {expect})")
            if r.stderr:
                print("      ", r.stderr.splitlines()[:4])
            ns_fail += 1

run("BOOT_IMAGE=/vmlinuz quiet inst.ks=hd:LABEL=OEMDRV", expect=0, name="clean cmdline accepted")
run('BOOT_IMAGE=/vmlinuz "inst.addrepo=https://evil.example/repo"', expect=1, name="quoted inst.addrepo rejected")
run("BOOT_IMAGE=/vmlinuz addrepo=https://evil.example/repo", expect=1, name="bare addrepo= rejected")
run("BOOT_IMAGE=/vmlinuz inst.noverifyssl", expect=1, name="inst.noverifyssl rejected")
run("BOOT_IMAGE=/vmlinuz noverifyssl", expect=1, name="bare noverifyssl rejected")
run("BOOT_IMAGE=/vmlinuz method=http://evil.example/", expect=1, name="method= rejected")
run("BOOT_IMAGE=/vmlinuz repo=https://evil.example/", expect=1, name="bare repo= rejected")
run("BOOT_IMAGE=/vmlinuz inst.repo=https://evil.example/", expect=1, name="inst.repo= rejected")
run("BOOT_IMAGE=/vmlinuz quiet", extra_files={"run/install/cmdline": "inst.addrepo=https://evil.example/\n"},
    expect=1, name="Anaconda cmdline file inst.addrepo rejected")
run("BOOT_IMAGE=/vmlinuz quiet", extra_files={"run/install/cmdline.d/extra": '"inst.noverifyssl"\n'},
    expect=1, name="quoted inst.noverifyssl in cmdline.d rejected")
run("BOOT_IMAGE=/vmlinuz report=1 repository=local", expect=0, name="unrelated tokens accepted")
# P-L18
run(cmdline=None, expect=1, name="missing /proc/cmdline fails closed")
run("BOOT_IMAGE=/vmlinuz inst.repo=https://evil.example/", expect=1,
    env_root="/nonexistent", name="AVALONOS_INSTGUARD_ROOT env does not bypass (test copy still uses rewritten root)")
print(f"instguard-test: {ns_ok} ok, {ns_fail} failed")
sys.exit(0 if ns_fail == 0 else 1)
PY
