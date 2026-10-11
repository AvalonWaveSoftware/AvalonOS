#!/usr/bin/env bash
# Offline tests for kickstart/avalonos-instguard.sh boot-option parsing (P-L10).
# Does not run the updates.img or repo checks; extracts the cmdline scanner.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
src="$ROOT/kickstart/avalonos-instguard.sh"
python3 - "$src" <<'PY'
import pathlib, subprocess, sys, tempfile, os, textwrap

src = pathlib.Path(sys.argv[1]).read_text()
start = src.find("python3 - <<'AVIG'")
assert start >= 0
block = src[src.find("\n", start)+1:]
block = block.split("\nAVIG\n", 1)[0]
# Skip the updates.img / repo sections; run only the extracted scanner.
ns_ok = 0
ns_fail = 0

def run(cmdline=None, extra_files=None, expect=0, name=""):
    global ns_ok, ns_fail
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        (tmp / "proc").mkdir()
        if cmdline is not None:
            (tmp / "proc/cmdline").write_text(cmdline)
        env = os.environ.copy()
        env["AVALONOS_INSTGUARD_ROOT"] = str(tmp)
        if extra_files:
            for rel, text in extra_files.items():
                p = tmp / rel
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(text)
        r = subprocess.run([sys.executable, "-c", block], env=env, capture_output=True, text=True)
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
print(f"instguard-test: {ns_ok} ok, {ns_fail} failed")
sys.exit(0 if ns_fail == 0 else 1)
PY
