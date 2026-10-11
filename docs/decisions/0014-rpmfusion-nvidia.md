# ADR 0014: RPM Fusion NVIDIA (akmod-nvidia)

- Status: accepted
- Date: 2026-09-06
- Fedora: 44

## Decision

Enable RPM Fusion **free** and **nonfree** release RPMs for F44. Install
`kernel-devel` matching the running kernel, `akmod-nvidia`,
`xorg-x11-drv-nvidia`. **No** `xorg-x11-drv-nvidia-cuda` in v1.

Kernel args (all kernels):

`rd.driver.blacklist=nouveau modprobe.blacklist=nouveau nvidia-drm.modeset=1 nvidia-drm.fbdev=1`

Blacklist file: `overlay/etc/modprobe.d/blacklist-nouveau.conf`.
Wait for akmods to finish **before** reboot. niri still on Intel
(ADR 0004).

RPM Fusion URLs (F44):

- `https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm`
- `https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-44.noarch.rpm`

## Alternatives

- nouveau only.
- nvidia-open (`akmod-nvidia-open`): Turing-capable; user asked proprietary.
- CUDA stack: huge; out of v1.

## Consequences

Third-party repo exception (ADR 0009). Secure Boot: if enabled, enroll
akmods MOK or leave SB off. ISO kickstart already adds RPM Fusion repos
and runs `akmods --force` in `%post` (ADR 0019). This live box still
needs `scripts/install-nvidia.sh` if the proprietary module is not
loaded yet.

## Rollback

See ADR 0004.
