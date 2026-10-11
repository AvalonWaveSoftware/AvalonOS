# stage0 / base

Inventory freeze: `freeze-baseline.txt` (433 NEVRA, 2026-09-06).

Already present and relevant (do not reinstall):

- `NetworkManager-1.56.1-2.fc44.x86_64` (enabled, manages `enp59s0`)
- `linux-firmware-20260810-1.fc44.noarch` (metapackage; **no** iwlwifi files)
- `vim-minimal-9.2.967-1.fc44.x86_64` (owns `/usr/bin/vi`; leave it)

Transactions appended below by `scripts/dnf-install.sh`.

**Correction:** first pass installed `git`, which Requires perl-Git and pulled
~69 MiB of Perl. Removed `git` + Perl, installed **`git-core` only**
(`/usr/bin/git`, no Perl). Use `git-core` in the ISO freeze.
### 2026-09-07T00:01:33Z  dnf install git pciutils

```
git-2.55.0-1.fc44.x86_64
pciutils-3.15.0-1.fc44.x86_64
```

### SELinux overlay note
First `apply-overlay.sh` used `cp -a` and labeled NM config `admin_home_t`.
NM failed to start (`00-iwd.conf: Permission denied`). Relabeled with
`restorecon`; script now copies without SELinux context.

### 2026-09-07T00:02:03Z  dnf install git-core

```
git-core-2.55.0-1.fc44.x86_64
```

### 2026-09-07T00:02:48Z  dnf install mesa-dri-drivers mesa-vulkan-drivers libva-intel-media-driver iwlwifi-mvm-firmware iwd NetworkManager-wifi NetworkManager-tui neovim bluez blueman rfkill

```
mesa-dri-drivers-26.1.8-1.fc44.x86_64
mesa-vulkan-drivers-26.1.8-1.fc44.x86_64
libva-intel-media-driver-26.2.4-1.fc44.x86_64
iwlwifi-mvm-firmware-20260810-1.fc44.noarch
iwd-3.12-1.fc44.x86_64
NetworkManager-wifi-1.56.1-2.fc44.x86_64
NetworkManager-tui-1.56.1-2.fc44.x86_64
neovim-0.12.5-1.fc44.x86_64
bluez-5.87-6.fc44.x86_64
blueman-2.4.6-7.fc44.x86_64
# rfkill is util-linux on F44 (already installed); not a separate RPM
```


### 2026-09-06  systemctl set-default graphical.target
Default target is now graphical.target (greetd not installed yet; no display-manager alias).
