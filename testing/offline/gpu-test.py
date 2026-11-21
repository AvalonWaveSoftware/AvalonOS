"""Offline scenarios for gpu-select (fake sysfs; GL probe stubbed with the
renderer each QA VM reported). Run: python3 gpu-test.py"""
import sys
sys.dont_write_bytecode = True
import importlib.machinery, importlib.util, io, os, shutil, sys, tempfile, contextlib
import pathlib
SRC = str(pathlib.Path(__file__).resolve().parents[2] / "overlay/usr/libexec/avalonos/gpu-select")
fails = 0

def card(root, name, driver, boot_vga=None, render=None, connectors=("Virtual-1",), platform=False):
    dev = os.path.join(root, "devices", ("platform/" if platform else "pci/") + name)
    os.makedirs(os.path.join(dev, "drm", name), exist_ok=True)
    drvdir = os.path.join(root, "bus/drivers", driver); os.makedirs(drvdir, exist_ok=True)
    os.symlink(drvdir, os.path.join(dev, "driver"))
    if boot_vga is not None:
        open(os.path.join(dev, "boot_vga"), "w").write(f"{boot_vga}\n")
    if render:
        os.makedirs(os.path.join(dev, "drm", render))
    cls = os.path.join(root, "class/drm"); os.makedirs(cls, exist_ok=True)
    os.makedirs(os.path.join(cls, name)); os.symlink(dev, os.path.join(cls, name, "device"))
    for c in connectors:
        os.makedirs(os.path.join(cls, f"{name}-{c}"))

def run(label, setup, renderers, cmdline="", expect_env=(), expect_kdl=None, forbid=()):
    global fails
    root = tempfile.mkdtemp(); rund = os.path.join(root, "run")
    os.environ["AVALONOS_TEST_SYSFS"] = root; os.environ["AVALONOS_TEST_RUNDIR"] = rund
    setup(root)
    ld = importlib.machinery.SourceFileLoader("gs", SRC); sp = importlib.util.spec_from_loader("gs", ld)
    gs = importlib.util.module_from_spec(sp); ld.exec_module(gs)
    probed = []
    gs.probe = lambda n: (probed.append(n), renderers.get(n))[1]
    gs.cmdline_choice = lambda: cmdline or None
    out = io.StringIO()
    with contextlib.redirect_stdout(out): gs.main()
    env = out.getvalue(); kdl = open(os.path.join(rund, "niri-gpu.kdl")).read()
    ok = all(e in env for e in expect_env) and not any(f in env for f in forbid)
    ok = ok and ((expect_kdl is None and "render-drm-device" not in kdl) or (expect_kdl and f'render-drm-device "{expect_kdl}"' in kdl))
    fails += not ok
    print(("PASS " if ok else "FAIL ") + label)
    print("     gpu.env: " + " | ".join(env.strip().splitlines()))
    print("     niri-gpu.kdl: " + " ".join(kdl.split()))
    shutil.rmtree(root)

SW = "MESA_LOADER_DRIVER_OVERRIDE=kms_swrast"; DO = "AVALONOS_DISPLAY_ONLY=1"
run("G1 QEMU -vga std (bochs-drm only; QA B/D): display-only, no kms_swrast, no niri render override",
    lambda r: card(r, "card0", "bochs-drm", 1), {}, expect_env=(DO, "bochs-drm"), forbid=(SW,))
run("G2 virtio-vga 2D (QA A): kms_swrast on renderD128, unchanged",
    lambda r: card(r, "card1", "virtio-pci", 1, "renderD128"), {"/dev/dri/renderD128": "llvmpipe (LLVM 22.1.8, 256 bits)"},
    expect_env=(SW,), forbid=(DO,))
run("G3 virtio-vga-gl 3D (QA A3D): hardware GL, no override (3D path unchanged)",
    lambda r: card(r, "card1", "virtio-pci", 1, "renderD128"), {"/dev/dri/renderD128": "virgl (...)"},
    expect_env=("hardware GL: virgl",), forbid=(SW, DO))
run("G4 real GPU (boot_vga) + leftover simpledrm: hardware GL on the GPU",
    lambda r: (card(r, "card0", "simple-framebuffer", None, None, platform=True), card(r, "card1", "amdgpu", 1, "renderD128", ("DP-1", "eDP-1"))),
    {"/dev/dri/renderD128": "AMD Radeon 780M"}, expect_env=("hardware GL: AMD",), forbid=(SW, DO))
run("G5 bochs boot VGA + second KMS GPU with render node: niri renders there",
    lambda r: (card(r, "card0", "bochs-drm", 1), card(r, "card1", "virtio-pci", 0, "renderD128")),
    {"/dev/dri/renderD128": "llvmpipe"}, expect_env=("display-only; niri renders on /dev/dri/renderD128", SW),
    expect_kdl="/dev/dri/renderD128", forbid=(DO,))
run("G6 bochs + render-only device without KMS (no connectors): still display-only",
    lambda r: (card(r, "card0", "bochs-drm", 1), card(r, "card1", "vgem", None, "renderD128", (), platform=True)),
    {}, expect_env=(DO,), forbid=(SW,))
run("G7 no DRM device: display-only message", lambda r: os.makedirs(os.path.join(r, "class/drm")), {}, expect_env=(DO,))
run("G8 avalonos.gpu=sw on bochs: still display-only (override cannot help)",
    lambda r: card(r, "card0", "bochs-drm", 1), {}, cmdline="sw", expect_env=(DO,))
run("G9 avalonos.gpu=sw on virtio: kms_swrast forced, probe skipped",
    lambda r: card(r, "card1", "virtio-pci", 1, "renderD128"), {}, cmdline="sw", expect_env=(SW,), forbid=(DO,))
def check(label, setup, want):
    global fails
    root = tempfile.mkdtemp(); os.environ["AVALONOS_TEST_SYSFS"] = root; setup(root)
    import subprocess
    r = subprocess.run([sys.executable, SRC, "--check"], capture_output=True, text=True,
                       env=dict(os.environ, AVALONOS_TEST_RUNDIR=os.path.join(root, "must-not-exist")))
    ok = r.returncode == 0 and r.stdout.strip() == want and not os.path.exists(os.path.join(root, "must-not-exist"))
    fails += not ok
    print(("PASS " if ok else "FAIL ") + f"{label}: --check -> {r.stdout.strip()!r} (want {want!r}), writes nothing")
    shutil.rmtree(root)

check("K1 bochs only", lambda r: card(r, "card0", "bochs-drm", 1), "display-only")
check("K2 virtio with render node", lambda r: card(r, "card1", "virtio-pci", 1, "renderD128"), "render")
check("K3 bochs + render-only device without KMS", lambda r: (card(r, "card0", "bochs-drm", 1), card(r, "card1", "vgem", None, "renderD128", (), platform=True)), "display-only")
check("K4 bochs + KMS GPU with render node", lambda r: (card(r, "card0", "bochs-drm", 1), card(r, "card1", "virtio-pci", 0, "renderD128")), "alt /dev/dri/renderD128")
check("K5 no DRM", lambda r: os.makedirs(os.path.join(r, "class/drm")), "display-only")
print("gpu-test: " + ("ALL PASS" if not fails else f"{fails} FAILED")); sys.exit(fails)
