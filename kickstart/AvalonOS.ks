# AvalonOS installer kickstart — Fedora 44 Everything netinst.
# Template, rendered by scripts/render-kickstart.sh into /ks.cfg on the ISO.
# Inline: AVALONOS_KEY_NAME AVALONOS_KEY_PIN (P-L11). Placeholders (each wrapped in @): AVALONOS_AUTH AVALONOS_STORAGE AVALONOS_INSTGUARD AVALONOS_PRE
# AVALONOS_PACKAGES AVALONOS_SIGCHECK AVALONOS_TESTSEED (empty in release builds)
# Rendered twice: /ks.cfg (default, interactive disk picker; never wipes
# unattended) and /ks-erase-all.cfg (only the "ERASES ALL DISKS" menu entry).
#
# No credential is baked in (decision 2026-11-14 9:40 CT): root is locked and
# the daily user is created at first boot by avalonos-firstboot-user.service.
# AvalonOS's own files come as RPMs from the local repo on this ISO
# (/avalonos/repo), installed in %post; Fedora packages come from the network.

cmdline
keyboard --vckeymap=us --xlayouts='us'
lang en_US.UTF-8
timezone America/Chicago --utc
firstboot --disable
selinux --enforcing
# No SSH (decision 2026-11-14 9:20 CT): port 22 closed, openssh-server excluded.
firewall --enabled --remove-service=ssh
reboot
@AVALONOS_AUTH@

# Network for netinst package fetch.
network --bootproto=dhcp --activate --onboot=on --hostname=avalonos
# ARCH-13 / P-M1r (decision 2026-11-14 11:30 CT: "Enforce the signature check
# during install"). No url/--baseurl/--metalink source here: Anaconda creates
# those repos with pkg_gpgcheck=False (pyanaconda dnf_manager.py:157). Instead
# every boot entry loads /avalonos/updates.img (inst.updates=), which replaces
# the installer's repo files with pinned ones: HTTPS metalinks, gpgcheck=1,
# gpgkey = the pinned Fedora / RPM Fusion keys (installer/updates/). Anaconda
# installs from these system repos (closest-mirror source), and libdnf5 checks
# every package signature before the transaction runs, i.e. before any
# scriptlet; an unsigned, wrong-key or tampered package aborts the install.
# The first %pre (avalonos-instguard.sh) refuses to start unless that image is
# in place byte for byte. repo_gpgcheck stays 0 for these repos: Fedora and RPM
# Fusion publish no repomd.xml.asc. Second layer: %post below re-verifies every
# installed header against the pinned keys (avalonos-sigcheck.py).
# The lines below only name the pinned system repos; a missing one is an error.
repo --name=fedora
repo --name=updates
# RPM Fusion (ADR 0014). rpmfusion-*-release RPMs persist them on the system.
repo --name=rpmfusion-free
repo --name=rpmfusion-free-updates
repo --name=rpmfusion-nonfree
repo --name=rpmfusion-nonfree-updates

# Disk + bootloader (decisions 9:36 CT and 9:59 CT / AOS-SEC-19):
#   /ks.cfg            -> the %pre disk picker asks; nothing is erased until a
#                         disk is chosen and its name typed to confirm.
#   /ks-erase-all.cfg  -> static erase-all lines; only the menu entry
#                         "AUTOMATIC INSTALL - ERASES ALL DISKS" uses it.
# NVIDIA modeset / simpledrm args are added in %post by avalonos-hw.
@AVALONOS_STORAGE@

services --enabled=NetworkManager,iwd,greetd --disabled=bluetooth

@AVALONOS_INSTGUARD@

@AVALONOS_PRE@

%packages --exclude-weakdeps --ignoremissing
@AVALONOS_PACKAGES@
%end

# Copy the AvalonOS RPM repo off the *boot ISO* (stage2 / ks media); the
# Fedora packages come from the network mirrors, not from this ISO.
%post --nochroot --log=/mnt/sysimage/root/avalonos-nochroot.log --erroronfail
set -euo pipefail
dest=/mnt/sysimage/var/lib/avalonos
mkdir -p "$dest" /run/avalonos-media
copy_payload() {
    local dir="$1"
    [ -f "$dir/repo/repodata/repomd.xml" ] || return 1
    rm -rf "$dest/repo"
    cp -a "$dir/repo" "$dest/repo"
    [ -f "$dir/packages.inc" ] && cp -a "$dir/packages.inc" "$dest/packages.inc"
    # AvalonOS RPM signing public key (fingerprint pinned in the chroot %post;
    # release: production key, QA test build: TEST key only, P-L11).
    [ -s "$dir/@AVALONOS_KEY_NAME@" ] || return 1
    install -D -m 0644 "$dir/@AVALONOS_KEY_NAME@" /mnt/sysimage/etc/pki/rpm-gpg/@AVALONOS_KEY_NAME@
    return 0
}
found=
for p in \
    /run/install/repo/avalonos \
    /mnt/install/repo/avalonos \
    /run/install/sources/mount-0000-cdrom/avalonos \
    /mnt/install/source/avalonos
do
    if copy_payload "$p"; then found=1; break; fi
done
if [ -z "$found" ]; then
    shopt -s nullglob
    for p in /run/install/sources/*/avalonos; do
        if copy_payload "$p"; then found=1; break; fi
    done
    shopt -u nullglob
fi
if [ -z "$found" ]; then
    for lab in Fedora-E-dvd-x86_64-44 Fedora-E-dvd-x86_64; do
        if [ -e "/dev/disk/by-label/$lab" ]; then
            mount -o ro "/dev/disk/by-label/$lab" /run/avalonos-media || continue
            if copy_payload /run/avalonos-media/avalonos; then
                found=1
            fi
            umount /run/avalonos-media || true
            [ -n "$found" ] && break
        fi
    done
fi
if [ -z "$found" ]; then
    t="$(find /run /mnt /tmp -path '*/avalonos/repo/repodata/repomd.xml' 2>/dev/null | head -1 || true)"
    if [ -n "$t" ]; then
        copy_payload "${t%/repo/repodata/repomd.xml}" && found=1
    fi
fi
if [ -z "$found" ]; then
    echo "AvalonOS: RPM repo (avalonos/repo) not found on installation media" >&2
    ls -la /dev/disk/by-label 2>/dev/null || true
    ls -laR /run/install /mnt/install 2>/dev/null || true
    exit 1
fi
cp -a /tmp/avalonos-diskpick.log /mnt/sysimage/root/ 2>/dev/null || true
%end

%post --log=/root/avalonos-post.log --erroronfail
set -euo pipefail
REPO=/var/lib/avalonos/repo
[ -f "$REPO/repodata/repomd.xml" ] || { echo "AvalonOS: missing $REPO" >&2; exit 1; }

# ---- ARCH-13: pin package-signing keys, audit signatures (fail closed) ------
# Fingerprints = keys/PINNED-FINGERPRINTS in the AvalonOS repo.
declare -A PIN=(
    [/etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-44-x86_64]=36f612dcf27f7d1a48a835e4dbfcf71c6d9f90a6
    [/etc/pki/rpm-gpg/RPM-GPG-KEY-rpmfusion-free-fedora-44]=e9a491a3de247814e7e067eae06f8ecdd651ff2e
    [/etc/pki/rpm-gpg/RPM-GPG-KEY-rpmfusion-nonfree-fedora-44]=79bdb88f9bbf73910fd4095b6a2af96194843c65
    [/etc/pki/rpm-gpg/@AVALONOS_KEY_NAME@]=@AVALONOS_KEY_PIN@
)
for f in "${!PIN[@]}"; do
    [ -s "$f" ] || { echo "AvalonOS: missing signing key $f" >&2; exit 1; }
    rpmkeys --import "$f"
done
# rpm 6: gpg-pubkey VERSION is the full fingerprint. The imported set must be
# exactly the pinned set (a swapped key file shows up here as a stranger).
have_fps="$(rpm -q gpg-pubkey --qf '%{VERSION}\n' | tr 'A-F' 'a-f' | sort -u)"
want_fps="$(printf '%s\n' "${PIN[@]}" | sort -u)"
[ "$have_fps" = "$want_fps" ] || {
    echo "AvalonOS: trusted keys differ from the pinned set" >&2
    diff <(echo "$want_fps") <(echo "$have_fps") >&2 || true
    exit 1
}
# Every installed package: cryptographic header-signature verification
# against a keyring built ONLY from the pinned key files (P-M1; source:
# kickstart/avalonos-sigcheck.py). Unsigned, wrong-key, tampered or unreadable
# headers fail the install.
@AVALONOS_SIGCHECK@
audit_signatures() {
    command -v python3 >/dev/null && python3 -c 'import rpm' 2>/dev/null \
        || { echo "AvalonOS: python3-rpm missing; cannot verify signatures" >&2; exit 1; }
    python3 /root/avalonos-sigcheck.py "${!PIN[@]}" \
        || { echo "AvalonOS: package signature verification FAILED" >&2; exit 1; }
}
audit_signatures
# Installed system: every enabled repo must check signatures, over HTTPS.
for r in /etc/yum.repos.d/*.repo; do
    awk -v f="$r" '
        /^\[/ { if (sec != "" && en && (!gc || insecure)) bad=1; sec=$0; en=1; gc=0; insecure=0; next }
        /^enabled[ \t]*=[ \t]*0/ { en=0 }
        /^gpgcheck[ \t]*=[ \t]*1/ { gc=1 }
        /^(baseurl|metalink|mirrorlist)[ \t]*=[ \t]*http:/ { insecure=1 }
        END { if (sec != "" && en && (!gc || insecure)) bad=1; if (bad) { print "AvalonOS: insecure enabled repo in " f > "/dev/stderr"; exit 1 } }' "$r"
done
echo "AvalonOS: signing keys pinned; every installed package verified against them"

# AvalonOS RPMs (avalonos meta-package and its subpackages) from the ISO repo.
# Signed with the AvalonOS RPM signing key (pinned above); the repo metadata
# carries a detached signature (repodata/repomd.xml.asc). Both are checked.
dnf -y --setopt=install_weak_deps=False \
    --repofrompath=avalonos-local,"file://$REPO" \
    --setopt=avalonos-local.gpgcheck=1 \
    --setopt=avalonos-local.repo_gpgcheck=1 \
    --setopt=avalonos-local.gpgkey=file:///etc/pki/rpm-gpg/@AVALONOS_KEY_NAME@ \
    --setopt=avalonos-local.skip_if_unavailable=0 \
    install avalonos
audit_signatures
echo "AvalonOS: avalonos RPMs installed; all packages still verified against pinned keys"
rpm -q avalonos avalonos-session avalonos-greeter avalonos-firstboot

# Guard against --ignoremissing silently dropping a renamed package.
missing=0
while read -r p; do
    case "$p" in ''|'#'*|-*|@*) continue;; esac
    rpm -q --whatprovides "$p" >/dev/null 2>&1 || { echo "AvalonOS: NOT INSTALLED: $p" >&2; missing=1; }
done < /var/lib/avalonos/packages.inc
[ "$missing" = 0 ] || { echo "AvalonOS: ERROR: some packages.inc entries are missing (see above)" >&2; exit 1; }
if rpm -q openssh-server >/dev/null 2>&1; then
    echo "AvalonOS: openssh-server is installed although excluded" >&2; exit 1
fi

# Console font (KEYMAP comes from the keyboard command). ter-i32n: Terminus
# 16x32 in CP437 glyph order, the order of the kernel's built-in fonts and
# default Unicode map. A VT cell stores a glyph index, so a font change after a
# TUI has drawn (the UEFI simpledrm -> GPU driver handover) must not move any
# glyph; with ter-v32n (512 glyphs, other order) box lines became Č/à/á
# (QA r6 FAIL 2). testing/offline/console-font-test.sh checks this.
if grep -q '^FONT=' /etc/vconsole.conf 2>/dev/null; then
    sed -i 's/^FONT=.*/FONT="ter-i32n"/' /etc/vconsole.conf
else
    echo 'FONT="ter-i32n"' >> /etc/vconsole.conf
fi

systemctl set-default graphical.target
systemctl enable avalonos-firstboot-user.service avalonos-gpu-select.service
systemctl enable greetd.service
ln -sfn /usr/lib/systemd/system/greetd.service /etc/systemd/system/display-manager.service
systemctl enable NetworkManager.service NetworkManager-wait-online.service iwd.service
# H-1: NM-libreswan does not start pluto.
systemctl enable ipsec.service
systemctl disable bluetooth.service
systemctl enable switcheroo-control.service 2>/dev/null || true
systemctl mask lightdm.service 2>/dev/null || true

# Release builds: nothing here. QA test builds (AVALONOS_TEST_BUILD=1) only:
# the test-seed package and its kernel flag (scripts/render-kickstart.sh).
@AVALONOS_TESTSEED@

# The verifier goes only after its last use (the QA test block above calls
# audit_signatures again; QA r6 FAIL 1). scripts/check-ks-order.sh enforces it.
rm -f /root/avalonos-sigcheck.py
rm -rf "$REPO"
echo "AvalonOS packages installed"
%end

# Hardware: NVIDIA akmod (only with a 10de GPU) and the NVIDIA-only simpledrm
# blacklist. Non-fatal, so a failed akmod build does not stop the install.
%post --log=/root/avalonos-hw-post.log
/usr/libexec/avalonos/hw-setup
# GPU firmware must be in the initramfs (Alder Lake etc. wedge without it).
if command -v dracut >/dev/null; then
    dracut -f --regenerate-all || dracut -f || true
fi
exit 0
%end
