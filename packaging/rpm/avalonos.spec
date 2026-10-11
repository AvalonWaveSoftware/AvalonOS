# AvalonOS: the distribution's own scripts, configs, themes and programs.
# Built by scripts/build-rpms.sh; Source0 is made from this repository.
# Third-party content (vendored Neovim plugins) keeps its own licences.
#
# QA test builds only: `rpmbuild --with testseed` (scripts/build-rpms.sh with
# AVALONOS_TEST_BUILD=1) adds the avalonos-testseed subpackage. Release builds
# (the default) neither build it nor carry its sources (decision 2026-11-14
# 11:31 CT: "Strip the test-seed from release ISOs, keep it for test builds only").
%bcond testseed 0
# Public AvalonOS key this build trusts (P-L11): the production key, or in QA
# test builds (--with testseed) ONLY the separate TEST key.
%if %{with testseed}
%global avalonos_key RPM-GPG-KEY-avalonos-test
%else
%global avalonos_key RPM-GPG-KEY-avalonos
%endif

Name:           avalonos
Version:        0.1.0
Release:        8%{?dist}
Summary:        Meta-package that installs the complete desktop
License:        Apache-2.0
URL:            https://github.com/AvalonWaveSoftware/AvalonOS
Source0:        %{name}-%{version}.tar.gz
BuildArch:      noarch

BuildRequires:  systemd-rpm-macros
BuildRequires:  desktop-file-utils

Requires:       %{name}-branding = %{version}-%{release}
Requires:       %{name}-session = %{version}-%{release}
Requires:       %{name}-greeter = %{version}-%{release}
Requires:       %{name}-firstboot = %{version}-%{release}
Requires:       %{name}-desktop-tools = %{version}-%{release}
Requires:       %{name}-desktop-config = %{version}-%{release}
Requires:       %{name}-network = %{version}-%{release}
Requires:       %{name}-firefox = %{version}-%{release}
Requires:       %{name}-nvim = %{version}-%{release}
Requires:       %{name}-hw = %{version}-%{release}
Requires:       %{name}-docs = %{version}-%{release}
# Ships with the desktop (decision 2026-11-14 11:30 CT: "Ship avalonos-tailwhip").
Requires:       %{name}-tailwhip = %{version}-%{release}

%description
AvalonOS is a minimal Fedora-based desktop built on niri, greetd/tuigreet,
waybar and rofi. This meta-package pulls in every AvalonOS component that
the installer ships. The Fedora package set itself comes from the kickstart.

%package branding
Summary:        AvalonOS palette, wallpaper and color themes
License:        Apache-2.0

%description branding
Palette files, the AvalonOS wallpaper, the console palette, and color
schemes for Qt (KDE color scheme, qt6ct), rofi and btop.

%package session
Summary:        AvalonOS niri session and GPU selection
License:        Apache-2.0
Requires:       %{name}-branding = %{version}-%{release}
Requires:       niri >= 26.04
Requires:       xwayland-satellite
Requires:       xorg-x11-server-Xwayland
Requires:       mesa-dri-drivers
Requires:       mesa-libgbm
Requires:       mesa-libEGL
Requires:       python3
Requires:       systemd
Requires:       coreutils
Requires:       swaybg
Requires:       swayidle
Requires:       swaylock
Requires:       waybar
Requires:       dunst

%description session
The AvalonOS Wayland session: avalonos-session (started by greetd), the
system niri configuration, niri.service drop-ins, the session .desktop
file, portal configuration and the session environment. At boot the root
service avalonos-gpu-select probes the primary GPU and, only when it has no
3D support, makes niri use Mesa kms_swrast (software rendering).

%package greeter
Summary:        AvalonOS greetd/tuigreet login screen
License:        Apache-2.0
Requires:       %{name}-branding = %{version}-%{release}
Requires:       greetd
Requires:       tuigreet
Requires:       terminus-fonts-console
Requires:       kbd
Requires(post): shadow-utils
Requires(post): greetd

%description greeter
The AvalonOS greeter: a greetd configuration that runs tuigreet with the
AvalonOS console palette and font, and the console setup helper.

%package firstboot
Summary:        AvalonOS first-boot user creation
License:        Apache-2.0
Requires:       %{name}-greeter = %{version}-%{release}
Requires:       python3
Requires:       shadow-utils
Requires:       util-linux
Requires:       xdg-user-dirs
%{?systemd_requires}

%description firstboot
On the first boot after installation, avalonos-firstboot-user.service runs
avalonos-make-user on tty1 before the greeter starts. It asks for the daily
user name and password and creates the user in the wheel group. root stays
locked. No default credential ships and this package has no way to
pre-seed a user.

%package desktop-tools
Summary:        AvalonOS desktop helpers (rofi menus, network and hardware popups)
License:        Apache-2.0
Requires:       %{name}-branding = %{version}-%{release}
Requires:       python3
Requires:       python3-gobject
Requires:       gtk3
Requires:       NetworkManager
Requires:       rofi
Requires:       alacritty
Requires:       btop

%description desktop-tools
Grouped rofi application menus, the network menu and status, the hardware
stats popup, the niri window stack helper and launchers.

%package desktop-config
Summary:        AvalonOS defaults for waybar, dunst, GTK, Qt, rofi and alacritty
License:        Apache-2.0
Requires:       %{name}-branding = %{version}-%{release}
Requires:       %{name}-desktop-tools = %{version}-%{release}

%description desktop-config
System-wide default configuration for the AvalonOS desktop. Files that
other packages also ship (waybar, dunst, autostart entries, menu entries)
live in AvalonOS's own XDG directories, which the session puts first.

%package network
Summary:        AvalonOS network defaults (NetworkManager with iwd)
License:        Apache-2.0
Requires:       NetworkManager
Requires:       NetworkManager-wifi
Requires:       iwd

%description network
Network defaults for AvalonOS: a NetworkManager configuration drop-in that
makes NetworkManager use iwd as its Wi-Fi backend instead of wpa_supplicant.

%package firefox
Summary:        AvalonOS Firefox enterprise policies
License:        Apache-2.0
Requires:       %{name}-branding = %{version}-%{release}
Requires:       firefox

%description firefox
Firefox enterprise policies for AvalonOS: no default-browser nag, no
first-run or post-update pages, and the AvalonOS palette as default page
colors. No browser extensions are installed.

%package nvim
Summary:        AvalonOS Neovim configuration and bundled plugins
# AvalonOS config: Apache-2.0. Bundled plugins: mason.nvim, mason-lspconfig.nvim,
# nvim-lspconfig, nvim-treesitter (Apache-2.0); nvim-tree.lua
# (GPL-3.0-or-later); nvim-web-devicons (MIT).
License:        Apache-2.0 AND GPL-3.0-or-later AND MIT
Requires:       %{name}-branding = %{version}-%{release}
Requires:       neovim
Requires:       git-core
Requires:       avalonos-nvim-parsers
# Pinned language servers (Code Security P-M2): replaces mason auto-install.
Requires:       avalonos-nvim-lsp
Requires:       nodejs-bash-language-server
Provides:       bundled(nvim-mason)
Provides:       bundled(nvim-mason-lspconfig)
Provides:       bundled(nvim-lspconfig)
Provides:       bundled(nvim-treesitter)
Provides:       bundled(nvim-tree.lua)
Provides:       bundled(nvim-web-devicons)

%description nvim
The AvalonOS Neovim setup: theme, IDE layout, LSP and tree-sitter
configuration, with the plugins it uses bundled. lua-language-server,
marksman (avalonos-nvim-lsp, pinned) and bash-language-server (Fedora) are
installed; mason downloads nothing on its own.

%package hw
Summary:        AvalonOS install-time hardware setup (NVIDIA, simpledrm)
License:        Apache-2.0
Requires:       pciutils
Requires:       grubby

%description hw
hw-setup runs once from the installer: on machines with an NVIDIA GPU it
installs the RPM Fusion akmod driver, sets the nvidia-drm kernel arguments
and disables simpledrm; elsewhere it blocks the nvidia modules and leaves
simpledrm enabled as the fallback display. Also a udev rule for the
reference laptop's unused NVIDIA USB-C functions.

%package docs
Summary:        AvalonOS user documentation
License:        Apache-2.0

%description docs
README, installation guide, decision records and configuration notes.
First-boot user creation copies them to ~/AvalonOS-Docs.

%package tailwhip
Summary:        Make an AvalonOS test-harness user seed (hashed password)
License:        Apache-2.0
Requires:       bash
Requires:       /usr/bin/mkpasswd

%description tailwhip
tailwhip writes the avalonos-seed.conf file that automated tests put on a
disk labeled AVTESTSEED. It contains a yescrypt hash, never a plaintext
password, and never a root password. Installed with the desktop so QA can
prepare seed disks; only QA test builds (avalonos-testseed) read them, a
release system ignores them.

%if %{with testseed}
%package testseed
Summary:        QA TEST BUILDS ONLY: create the first-boot user from a seed disk
License:        Apache-2.0
Requires:       %{name}-firstboot = %{version}-%{release}
Requires:       python3
Requires:       util-linux

%description testseed
QA TEST BUILDS ONLY; never in a release repo or on a release ISO. Before the
first-boot prompt, if the kernel argument avalonos.testseed=1 is set and a
disk labeled AVTESTSEED carries avalonos-seed.conf (a crypt(3) hash, written
by tailwhip), creates that user and skips the prompt. Nothing is seeded
without both.
%endif

%prep
%autosetup -n %{name}-%{version}
# Bundled plugin licence texts, renamed so they can sit side by side.
mkdir -p nvim-licenses
for d in overlay/usr/share/AvalonOS/nvim/pack/avalon/start/*; do
    for l in "$d"/LICENSE*; do
        cp -p "$l" "nvim-licenses/$(basename "$l").$(basename "$d")"
    done
done

%build
# Nothing to build: scripts and data only.

%install
cp -a overlay/. %{buildroot}/
# Bundled Neovim plugins: drop upstream developer files (CI scripts, git and
# editor dotfiles); nothing in them is used at runtime.
pack=%{buildroot}%{_datadir}/AvalonOS/nvim/pack/avalon/start
find "$pack" -mindepth 1 -name '.*' -prune -exec rm -rf {} +
find "$pack" -mindepth 2 -maxdepth 2 -type d -name scripts -prune -exec rm -rf {} +
mkdir -p %{buildroot}%{_sysconfdir}/systemd/user
ln -s /dev/null %{buildroot}%{_sysconfdir}/systemd/user/xdg-desktop-autostart.target
install -Dpm 0644 packaging/rpm/80-avalonos.preset %{buildroot}%{_presetdir}/80-avalonos.preset
install -Dpm 0755 scripts/tailwhip %{buildroot}%{_bindir}/tailwhip
%if %{with testseed}
install -Dpm 0755 testing/testseed/testseed-user %{buildroot}%{_libexecdir}/avalonos/testseed-user
install -Dpm 0644 testing/testseed/50-avalonos-testseed.conf \
    %{buildroot}%{_unitdir}/avalonos-firstboot-user.service.d/50-avalonos-testseed.conf
%endif
install -Dpm 0644 keys/%{avalonos_key} %{buildroot}%{_sysconfdir}/pki/rpm-gpg/%{avalonos_key}
mkdir -p %{buildroot}%{_docdir}/%{name}-docs/AvalonOS-Docs
cp -a README.md INDEX.md How-to-Install.md docs %{buildroot}%{_docdir}/%{name}-docs/AvalonOS-Docs/
install -Dpm 0644 kickstart/AvalonOS.ks kickstart/packages.inc -t %{buildroot}%{_docdir}/%{name}-docs/AvalonOS-Docs/kickstart/

%check
# Session files (wayland-sessions) use DesktopNames, which
# desktop-file-validate does not know; only application entries are checked.
for f in %{buildroot}%{_datadir}/AvalonOS/xdg-data/applications/*.desktop \
         %{buildroot}%{_sysconfdir}/xdg/avalonos/autostart/*.desktop; do
    desktop-file-validate "$f"
done

%post greeter
if getent passwd greetd >/dev/null; then
    usermod -aG video,input,render greetd || :
fi

%post session
%systemd_post avalonos-gpu-select.service

%preun session
%systemd_preun avalonos-gpu-select.service

%postun session
%systemd_postun avalonos-gpu-select.service

%post firstboot
%systemd_post avalonos-firstboot-user.service

%preun firstboot
%systemd_preun avalonos-firstboot-user.service

%postun firstboot
%systemd_postun avalonos-firstboot-user.service

%files
%license LICENSE
# Public half of the AvalonOS RPM signing key of this build kind (fingerprint
# pinned in the kickstart; keys/PINNED-FINGERPRINTS, keys/TEST-KEY-FINGERPRINT).
%{_sysconfdir}/pki/rpm-gpg/%{avalonos_key}

%files branding
%license LICENSE
%dir %{_datadir}/AvalonOS
%{_datadir}/AvalonOS/palette.css
%{_datadir}/AvalonOS/palette.env
%{_datadir}/AvalonOS/vconsole.palette
%{_datadir}/AvalonOS/wallpaper.png
%{_datadir}/AvalonOS/wallpaper.svg
%{_datadir}/AvalonOS/btop.conf
%{_datadir}/AvalonOS/btop.theme
%{_datadir}/AvalonOS/btop-themes/
%{_datadir}/color-schemes/AvalonOS.colors
%{_datadir}/qt6ct/colors/AvalonOS.conf
%{_datadir}/rofi/themes/AvalonOS.rasi

%files session
%license LICENSE
%{_bindir}/avalonos-session
%dir %{_libexecdir}/avalonos
%{_libexecdir}/avalonos/gpu-select
%dir %{_sysconfdir}/niri
%config(noreplace) %{_sysconfdir}/niri/config.kdl
%dir %{_sysconfdir}/xdg/avalonos
%dir %{_sysconfdir}/xdg/avalonos/xdg-desktop-portal
%config(noreplace) %{_sysconfdir}/xdg/avalonos/xdg-desktop-portal/niri-portals.conf
%{_sysconfdir}/systemd/user/xdg-desktop-autostart.target
%dir %{_userunitdir}/niri.service.d
%{_userunitdir}/niri.service.d/00-avalonos.conf
%{_userunitdir}/niri.service.d/10-avalonos-gpu.conf
%{_unitdir}/avalonos-gpu-select.service
%{_prefix}/lib/environment.d/50-avalonos-xdg.conf
%{_prefix}/lib/environment.d/60-avalonos-qt.conf
%{_datadir}/wayland-sessions/AvalonOS.desktop
%{_datadir}/AvalonOS/wayland-sessions/

%files greeter
%license LICENSE
%{_bindir}/avalonos-greeter
%{_bindir}/avalonos-console-setup
%config(noreplace) %{_sysconfdir}/greetd/avalonos.toml
%dir %{_unitdir}/greetd.service.d
%{_unitdir}/greetd.service.d/10-avalonos.conf
%{_sysctldir}/20-avalonos-console.conf

%files firstboot
%license LICENSE
%{_bindir}/avalonos-make-user
%{_unitdir}/avalonos-firstboot-user.service
%{_presetdir}/80-avalonos.preset

%files desktop-tools
%license LICENSE
%{_bindir}/avalonos-launcher
%{_bindir}/avalonos-btop
%{_datadir}/AvalonOS/hw-stats
%{_datadir}/AvalonOS/net-menu
%{_datadir}/AvalonOS/net-status
%{_datadir}/AvalonOS/niri-stack
%{_datadir}/AvalonOS/rofi-grouped
%{_datadir}/AvalonOS/rofi-modes/
%{_datadir}/AvalonOS/rofi.rasi

%files desktop-config
%license LICENSE
%dir %{_sysconfdir}/xdg/avalonos/autostart
%config(noreplace) %{_sysconfdir}/xdg/avalonos/autostart/*.desktop
%dir %{_sysconfdir}/xdg/avalonos/dunst
%config(noreplace) %{_sysconfdir}/xdg/avalonos/dunst/dunstrc
%dir %{_sysconfdir}/xdg/avalonos/waybar
%config(noreplace) %{_sysconfdir}/xdg/avalonos/waybar/config.jsonc
%config(noreplace) %{_sysconfdir}/xdg/avalonos/waybar/style.css
%dir %{_sysconfdir}/xdg/alacritty
%config(noreplace) %{_sysconfdir}/xdg/alacritty/alacritty.toml
%dir %{_sysconfdir}/xdg/gtk-3.0
%config(noreplace) %{_sysconfdir}/xdg/gtk-3.0/settings.ini
%dir %{_sysconfdir}/gtk-4.0
%config(noreplace) %{_sysconfdir}/gtk-4.0/settings.ini
%config(noreplace) %{_sysconfdir}/xdg/kdeglobals
%config(noreplace) %{_sysconfdir}/xdg/mimeapps.list
%dir %{_sysconfdir}/xdg/qt6ct
%config(noreplace) %{_sysconfdir}/xdg/qt6ct/qt6ct.conf
%dir %{_sysconfdir}/xdg/rofi
%config(noreplace) %{_sysconfdir}/xdg/rofi/config.rasi
%dir %{_sysconfdir}/skel/.config
%config(noreplace) %{_sysconfdir}/skel/.config/qt6ct/
%config(noreplace) %{_sysconfdir}/skel/.config/rofi/
%{_datadir}/AvalonOS/xdg-data/

%files network
%license LICENSE
%{_prefix}/lib/NetworkManager/conf.d/00-iwd.conf

%files firefox
%license LICENSE
%dir %{_sysconfdir}/firefox
%dir %{_sysconfdir}/firefox/policies
%config(noreplace) %{_sysconfdir}/firefox/policies/policies.json

%files nvim
%license LICENSE
%license nvim-licenses/*
%dir %{_sysconfdir}/xdg/nvim
%config(noreplace) %{_sysconfdir}/xdg/nvim/init.lua
%config(noreplace) %{_sysconfdir}/profile.d/nvim-vi.sh
%{_datadir}/AvalonOS/nvim/
%dir %{_datadir}/nvim/site
%dir %{_datadir}/nvim/site/plugin
%{_datadir}/nvim/site/plugin/avalonos.lua

%files hw
%license LICENSE
%dir %{_libexecdir}/avalonos
%{_libexecdir}/avalonos/hw-setup
%{_udevrulesdir}/99-avalonos-nvidia-unused.rules

%files docs
%license LICENSE
%doc %{_docdir}/%{name}-docs/

%files tailwhip
%license LICENSE
%{_bindir}/tailwhip

%if %{with testseed}
%files testseed
%license LICENSE
%dir %{_libexecdir}/avalonos
%{_libexecdir}/avalonos/testseed-user
%dir %{_unitdir}/avalonos-firstboot-user.service.d
%{_unitdir}/avalonos-firstboot-user.service.d/50-avalonos-testseed.conf
%endif

%changelog
* Sat Nov 21 2026 AvalonOS <avalonos@localhost> - 0.1.0-8
- Post-release Low batch on the 0.1.0-7 tree: ISO unowned-byte volume-descriptor
  exemption is layout-derived (P-L16); U7 requires a PVD at LBA 80 or SKIP (P-L17);
  mid-file zlib carving covers the whole --gaps window (P-I16); verify-iso prints
  unowned summary lines on success (QA-L1); docs for --quick ESP coverage (P-I15),
  squashfs-via-zlib reporting (QA-L2), LSP binary pins (P-L9), plugin full commits
  (AOS-SEC-16), and bluetooth.service as an accepted residual (AOS-SEC-09)
- Runtime: installer guard parses quoted/Anaconda cmdline tokens and refuses
  repo/addrepo/noverifyssl/method, fail-closed without python3 (P-L10); missing
  packages.inc entries abort the install (P-L3); first-boot password policy
  (P-L5); net-menu uses nmcli passwd-file on connection up, never on
  device wifi connect (AOS-SEC-10, R8-B1); PSK tempfile cleanup starts
  immediately after mkstemp (P-L19); no /tmp pidfile fallback
  (AOS-SEC-11); session login-shell re-exec quoting (AOS-SEC-12)
- Docs: Alacritty does not launch in a virtual machine (known limitation;
  not investigated or changed in code)
- gitleaks: allow only anchored treesitter revision lines (AOS-SEC-13)

* Sun Nov 15 2026 AvalonOS <avalonos@localhost> - 0.1.0-7
- Console font ter-i32n (CP437 glyph order) instead of ter-v32n: box lines
  of the greeter and the first-boot TUI no longer turn into accented letters
  after the UEFI framebuffer handover (QA r6 FAIL 2); avalonos-console-setup
  waits for pending device events and has no other-order font fallback;
  avalonos-make-user prints ASCII instead of en dash / ellipsis
- Docs: key-isolation hardening against hidden keys (Code Security P-L12,
  decision 2026-11-14 17:43 CT)

* Sat Nov 14 2026 AvalonOS <avalonos@localhost> - 0.1.0-6
- QA test builds (--with testseed) ship and trust only the separate TEST
  signing key (RPM-GPG-KEY-avalonos-test); releases only the production key
  (Code Security P-L11, decision 2026-11-14 16:15 CT)

* Sat Nov 14 2026 AvalonOS <avalonos@localhost> - 0.1.0-5
- session: the display-only gate re-checks the live GPU state with
  gpu-select --check (render-only devices without outputs do not count; a
  GPU bound after boot asks for a reboot)
- firstboot: useradd and the marker are inside the rollback; signals are
  ignored before anything else; an interrupted upgrade retries; a name taken
  meanwhile (useradd exit 9) is never removed

* Sat Nov 14 2026 AvalonOS <avalonos@localhost> - 0.1.0-4
- session/gpu-select: a display-only adapter (QEMU -vga std/bochs-drm,
  simpledrm, hyperv_drm, BMC VGA) has no render node, so niri cannot draw:
  render on another KMS GPU via /run/avalonos/niri-gpu.kdl when there is one,
  otherwise show a console message instead of a blank screen (QA 2026-11-14
  HIGH); needs niri >= 26.04 (optional include)
- firstboot: Ctrl-C, Ctrl-D and Ctrl-Z no longer kill the user screen;
  the unit restarts on failure (QA 2026-11-14 MEDIUM)

* Sat Nov 14 2026 AvalonOS <avalonos@localhost> - 0.1.0-3
- Test seed out of release builds: avalonos-make-user no longer reads seed
  disks; QA test builds (--with testseed) add avalonos-testseed (decision
  2026-11-14 11:31 CT)
- Meta-package requires avalonos-tailwhip (decision 2026-11-14 11:30 CT)
- hw: on UEFI an unreadable Secure Boot state counts as unknown and fails
  closed (Code Security P-L7)

* Sat Nov 14 2026 AvalonOS <avalonos@localhost> - 0.1.0-2
- Drop the Firefox theme add-on and its prefs (decision 2026-11-14 10:30 CT)
- Package the AvalonOS RPM signing public key; RPMs and repo metadata are signed
- nvim: no mason auto-install; require pinned avalonos-nvim-lsp and Fedora
  bash-language-server (Code Security P-M2)
- hw: Secure Boot on: blacklist nouveau only if nvidia.ko is signed by a
  trusted key (Code Security P-M4)

* Sat Nov 14 2026 AvalonOS <avalonos@localhost> - 0.1.0-1
- First RPM packaging of the AvalonOS overlay (port of the Sep 13 ISO onto 02b02d3)
