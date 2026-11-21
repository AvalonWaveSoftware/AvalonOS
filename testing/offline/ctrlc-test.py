"""Offline Ctrl-C / Ctrl-D / Ctrl-\\ / Ctrl-Z test of avalonos-make-user in a
real pty (curses, TERM=linux). create_user/upgrade_and_reboot are stubbed and
record calls; geteuid/already_done stubbed. Run: python3 ctrlc-test.py"""
from pathlib import Path
import tempfile
import termios
import importlib.machinery, importlib.util, os, pty, select, signal, sys, time
SRC = str(Path(__file__).resolve().parents[2] / "overlay/usr/bin/avalonos-make-user")
sys.dont_write_bytecode = True
fails = 0

def child(log, kbi_first=False, read_failure=False):
    ld = importlib.machinery.SourceFileLoader("mu", SRC); sp = importlib.util.spec_from_loader("mu", ld)
    mu = importlib.util.module_from_spec(sp); ld.exec_module(mu)
    mu.FLAG = log + ".ready"
    mu.os.geteuid = lambda: 0
    mu.already_done = lambda: False
    mu.valid_name = lambda n: None if n else "enter a username"
    mu.create_user = lambda n, p, h=None: open(log, "a").write(f"create {n} {p}\n")
    mu.upgrade_and_reboot = lambda: open(log, "a").write("upgrade\n")
    if kbi_first:  # a KeyboardInterrupt escaping curses once must re-prompt
        real, n = mu.curses.wrapper, [0]
        def wrapper(f):
            n[0] += 1
            if n[0] == 1: open(log, "a").write("kbi\n"); raise KeyboardInterrupt
            if n[0] == 2: open(log, "a").write("eof\n"); raise EOFError
            return real(f)
        mu.curses.wrapper = wrapper
    if read_failure:
        real = mu.curses.wrapper
        class DeadInput:
            def __init__(self, screen): self.screen = screen
            def __getattr__(self, name): return getattr(self.screen, name)
            def getch(self): return -1
        mu.curses.wrapper = lambda fn: real(lambda screen: fn(DeadInput(screen)))
    os.environ["TERM"] = "linux"
    os._exit(mu.main())

def drain(fd, t=0.4):
    out, end = b"", time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try: out += os.read(fd, 65536)
            except OSError: break
    return out

def case(label, keys, kill_sigint=False, kbi_first=False, expect_create=True, read_failure=False):
    global fails
    tmpfd, log = tempfile.mkstemp(prefix="avalonos-ctrlc-"); os.close(tmpfd)
    pid, fd = pty.fork()
    if pid == 0: child(log, kbi_first, read_failure)
    screen = drain(fd, 1.0)
    for k in keys:
        if k == "SIGINT":  # tty-generated SIGINT goes to the foreground pgrp
            os.killpg(os.getpgid(pid), signal.SIGINT); screen += drain(fd, 0.3); continue
        os.write(fd, k.encode()); screen += drain(fd, 0.15)
    screen += drain(fd, 5.5 if read_failure else 0.5)
    done, st = os.waitpid(pid, os.WNOHANG)
    if not done:
        os.kill(pid, signal.SIGKILL); os.waitpid(pid, 0); rc = "hung"
    else:
        rc = os.waitstatus_to_exitcode(st)
    restored = bool(termios.tcgetattr(fd)[3] & termios.ICANON) if rc != "hung" else True
    os.close(fd)
    logtxt = open(log).read(); os.unlink(log)
    tb = b"Traceback" in screen
    ok = restored and (not tb) and ((rc == 1) if read_failure else ((rc == 0 and "create alice s3cret" in logtxt and "upgrade" in logtxt) if expect_create else rc == "hung"))
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {label}: rc={rc} traceback={tb} calls={logtxt.split(chr(10))[:-1]} "
          f"ignored-msg={b'ignored: create your user' in screen}")

FILL = ["a", "l", "i", "c", "e", "\t", *"s3cret", "\t", *"s3cret", "\t", "\r"]
case("C0 baseline: fill form, create", FILL)
case("C1 Ctrl-C (key) before typing, then create", ["\x03", "\x03", *FILL])
case("C2 Ctrl-D (EOF key) mid-username, then create", ["a", "l", "\x04", "i", "c", "e", *FILL[5:]])
case("C3 Ctrl-\\ and Ctrl-Z ignored, then create", ["\x1c", "\x1a", *FILL])
case("C4 SIGINT to the process group (tty Ctrl-C in cooked mode) x3, then create", ["SIGINT", "SIGINT", "SIGINT", *FILL])
case("C5 KeyboardInterrupt + EOFError escaping curses: re-prompt, then create", ["\x03", *FILL], kbi_first=True)
case("C6 Ctrl-C/Ctrl-D only: still waiting at the prompt, no user created", ["\x03", "\x04", "SIGINT"], expect_create=False)
case("C7 permanent getch ERR: bounded failure, terminal restored", [], expect_create=False, read_failure=True)
print("ctrlc-test: " + ("ALL PASS" if not fails else f"{fails} FAILED")); sys.exit(fails)
