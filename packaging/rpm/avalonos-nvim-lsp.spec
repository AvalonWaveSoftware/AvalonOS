# Language servers for the AvalonOS Neovim setup (Code Security P-M2).
# Before: mason downloaded lua_ls and marksman unpinned on first Neovim start.
# Now: exact upstream release artefacts, pinned by version here and by sha256
# in packaging/rpm/nvim-lsp.sha256 (checked by scripts/build-rpms.sh before
# rpmbuild). bash-language-server comes from Fedora (nodejs-bash-language-server).
# Upstream ships these as prebuilt x86_64 binaries (marksman is a
# self-contained .NET single-file executable), so nothing is compiled and the
# binaries must not be stripped.
%global luals_version     3.19.2
%global marksman_version  2026-02-08
%global marksman_rpmver   20260208
%global debug_package     %{nil}
%global __brp_strip       %{nil}
%global __brp_strip_static_archive %{nil}
%global __brp_strip_comment_note %{nil}
%global lspdir            %{_libexecdir}/avalonos/lsp

Name:           avalonos-nvim-lsp
Version:        0.1.0
Release:        2%{?dist}
Summary:        Pinned language servers (lua-language-server, marksman) for AvalonOS Neovim
License:        MIT
URL:            https://github.com/AvalonWaveSoftware/AvalonOS
Source0:        https://github.com/LuaLS/lua-language-server/releases/download/%{luals_version}/lua-language-server-%{luals_version}-linux-x64.tar.gz
Source1:        https://github.com/artempyanykh/marksman/releases/download/%{marksman_version}/marksman-linux-x64
Source2:        https://raw.githubusercontent.com/artempyanykh/marksman/%{marksman_version}/LICENSE#/LICENSE-marksman
ExclusiveArch:  x86_64
# marksman is a .NET single-file app: it dlopen()s ICU at start and aborts
# without it (QA 0.1.0-5 partial: the check section failed in a clean F44
# build), so ICU is needed to build and at run time (rpm cannot see the
# dlopen, so the dependency is on the package, not a soname).
BuildRequires:  libicu
Requires:       neovim
Requires:       libicu
# Bundled upstream builds (no Fedora package for either in Fedora 44).
Provides:       bundled(lua-language-server) = %{luals_version}
Provides:       bundled(marksman) = %{marksman_rpmver}

%description
lua-language-server %{luals_version} and marksman %{marksman_version}: the
upstream release builds, pinned by version and sha256, for the AvalonOS
Neovim configuration, which adds their directory to the Neovim PATH.
They replace the unpinned downloads mason made on first start.

%prep
%setup -q -c -T
mkdir luals
tar -C luals -xzf %{SOURCE0}
cp -p %{SOURCE1} marksman
cp -p %{SOURCE2} LICENSE-marksman
cp -p luals/LICENSE LICENSE-lua-language-server

%build
# Wrapper: keep LuaLS logs/meta out of the read-only install tree.
cat > lua-language-server.sh <<'WRAP'
#!/bin/sh
cache="${XDG_CACHE_HOME:-$HOME/.cache}/lua-language-server"
exec %{lspdir}/lua-language-server/bin/lua-language-server \
    -E %{lspdir}/lua-language-server/main.lua \
    --logpath="$cache/log" --metapath="$cache/meta" "$@"
WRAP

%install
install -d %{buildroot}%{lspdir}/bin %{buildroot}%{lspdir}/lua-language-server
cp -a luals/. %{buildroot}%{lspdir}/lua-language-server/
rm -f %{buildroot}%{lspdir}/lua-language-server/LICENSE
# Upstream tarball carries git submodule pointer files; not needed.
find %{buildroot}%{lspdir}/lua-language-server -name .git -prune -exec rm -rf {} +
find %{buildroot}%{lspdir}/lua-language-server -type d -exec chmod 0755 {} +
find %{buildroot}%{lspdir}/lua-language-server -type f -exec chmod 0644 {} +
chmod 0755 %{buildroot}%{lspdir}/lua-language-server/bin/lua-language-server
install -pm 0755 lua-language-server.sh %{buildroot}%{lspdir}/bin/lua-language-server
install -pm 0755 marksman %{buildroot}%{lspdir}/bin/marksman

%check
%{buildroot}%{lspdir}/bin/marksman --version
test -x %{buildroot}%{lspdir}/lua-language-server/bin/lua-language-server

%files
%license LICENSE-lua-language-server LICENSE-marksman
%dir %{_libexecdir}/avalonos
%{lspdir}/

%changelog
* Sat Nov 14 2026 AvalonOS <avalonos@localhost> - 0.1.0-2
- BuildRequires/Requires libicu: marksman aborts without ICU, so the check
  section failed in a clean F44 build (QA 0.1.0-5 partial, Low)

* Sat Nov 14 2026 AvalonOS <avalonos@localhost> - 0.1.0-1
- Package lua-language-server 3.19.2 and marksman 2026-02-08, pinned by
  version and sha256, instead of mason's unpinned first-start downloads
