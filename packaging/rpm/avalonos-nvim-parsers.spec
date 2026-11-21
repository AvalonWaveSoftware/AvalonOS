# Tree-sitter parsers for the AvalonOS Neovim setup, built from the grammar
# sources pinned by the bundled nvim-treesitter (lua/nvim-treesitter/parsers.lua).
# Every grammar commits its generated src/parser.c, so only a C compiler is
# needed at build time: no tree-sitter-cli and nothing extra in the image.

%global commit_bash       a06c2e4415e9bc0346c6b86d401879ffb44058f7
%global commit_c          b780e47fc780ddc8da13afa35a3f4ed5c157823d
%global commit_cpp        8b5b49eb196bec7040441bee33b2c9a4838d6967
%global commit_json       254c42a6476413b776221e03982ac8ae159eeb72
%global commit_lua        10fe0054734eec83049514ea2e718b2a56acd0c9
%global commit_markdown   a0a00f817d02412bd92c54d316f164d827b57b5c
%global tag_python        0.25.0
%global commit_query      8e9e223812ff30854fbc912adbec696ba5f0e023
%global commit_vim        039c8d0aa1deae00ddeb0374dd70bcc0ec56938d
%global commit_vimdoc     23daa416c1ff5d15f59a1aa648f031d6e3ee15c5

Name:           avalonos-nvim-parsers
Version:        0.1.0
Release:        2%{?dist}
Summary:        Tree-sitter parsers for the AvalonOS Neovim setup
# bash, c, cpp, json, lua, markdown, markdown_inline, python, vim: MIT;
# query, vimdoc: Apache-2.0
License:        MIT AND Apache-2.0
URL:            https://github.com/AvalonWaveSoftware/AvalonOS
Source0:        https://github.com/tree-sitter/tree-sitter-bash/archive/%{commit_bash}/tree-sitter-bash-%{commit_bash}.tar.gz
Source1:        https://github.com/tree-sitter/tree-sitter-c/archive/%{commit_c}/tree-sitter-c-%{commit_c}.tar.gz
Source2:        https://github.com/tree-sitter/tree-sitter-cpp/archive/%{commit_cpp}/tree-sitter-cpp-%{commit_cpp}.tar.gz
Source3:        https://github.com/tree-sitter/tree-sitter-json/archive/%{commit_json}/tree-sitter-json-%{commit_json}.tar.gz
Source4:        https://github.com/tree-sitter-grammars/tree-sitter-lua/archive/%{commit_lua}/tree-sitter-lua-%{commit_lua}.tar.gz
Source5:        https://github.com/tree-sitter-grammars/tree-sitter-markdown/archive/%{commit_markdown}/tree-sitter-markdown-%{commit_markdown}.tar.gz
Source6:        https://github.com/tree-sitter/tree-sitter-python/archive/v%{tag_python}/tree-sitter-python-%{tag_python}.tar.gz
Source7:        https://github.com/tree-sitter-grammars/tree-sitter-query/archive/%{commit_query}/tree-sitter-query-%{commit_query}.tar.gz
Source8:        https://github.com/tree-sitter-grammars/tree-sitter-vim/archive/%{commit_vim}/tree-sitter-vim-%{commit_vim}.tar.gz
Source9:        https://github.com/neovim/tree-sitter-vimdoc/archive/%{commit_vimdoc}/tree-sitter-vimdoc-%{commit_vimdoc}.tar.gz

BuildRequires:  gcc
BuildRequires:  binutils
Requires:       neovim

%description
Neovim tree-sitter parsers (bash, c, cpp, json, lua, markdown,
markdown_inline, python, query, vim, vimdoc) for the AvalonOS Neovim
configuration, compiled from the upstream grammar sources pinned by the
bundled nvim-treesitter.

%prep
%setup -q -c -T
for s in %{SOURCE0} %{SOURCE1} %{SOURCE2} %{SOURCE3} %{SOURCE4} \
         %{SOURCE5} %{SOURCE6} %{SOURCE7} %{SOURCE8} %{SOURCE9}; do
    tar -xzf "$s"
done

%build
# name : grammar directory (relative to the extracted tree)
build_one() {
    local name="$1" dir="$2" srcs top l
    srcs="$dir/src/parser.c"
    top="${dir%%%%/*}"
    [ -f "$dir/src/scanner.c" ] && srcs="$srcs $dir/src/scanner.c"
    gcc %{optflags} %{build_ldflags} -fPIC -shared -I"$dir/src" $srcs -o "parser/$name.so"
    printf '%s\n' "$3" > "parser-info/$name.revision"
    for l in "$top"/LICENSE*; do install -pm 0644 "$l" "licenses/$(basename "$l")-tree-sitter-$name"; done
}
mkdir -p parser parser-info licenses
build_one bash            tree-sitter-bash-%{commit_bash}                            %{commit_bash}
build_one c               tree-sitter-c-%{commit_c}                                  %{commit_c}
build_one cpp             tree-sitter-cpp-%{commit_cpp}                              %{commit_cpp}
build_one json            tree-sitter-json-%{commit_json}                            %{commit_json}
build_one lua             tree-sitter-lua-%{commit_lua}                              %{commit_lua}
build_one markdown        tree-sitter-markdown-%{commit_markdown}/tree-sitter-markdown        %{commit_markdown}
build_one markdown_inline tree-sitter-markdown-%{commit_markdown}/tree-sitter-markdown-inline %{commit_markdown}
build_one python          tree-sitter-python-%{tag_python}                           v%{tag_python}
build_one query           tree-sitter-query-%{commit_query}                          %{commit_query}
build_one vim             tree-sitter-vim-%{commit_vim}                              %{commit_vim}
build_one vimdoc          tree-sitter-vimdoc-%{commit_vimdoc}                        %{commit_vimdoc}

%install
install -Dpm 0755 -t %{buildroot}%{_libdir}/avalonos/nvim-parsers/parser parser/*.so
install -Dpm 0644 -t %{buildroot}%{_libdir}/avalonos/nvim-parsers/parser-info parser-info/*.revision

%check
for f in parser/*.so; do
    n="$(basename "$f" .so)"
    nm -D --defined-only "$f" | grep -q " tree_sitter_${n}$"
done

%files
%license licenses/*
%dir %{_libdir}/avalonos
%{_libdir}/avalonos/nvim-parsers/

%changelog
* Sat Nov 14 2026 AvalonOS <avalonos@localhost> - 0.1.0-2
- Install licence files mode 0644 (Code Security P-I1)

* Sat Nov 14 2026 AvalonOS <avalonos@localhost> - 0.1.0-1
- Build the 11 parsers from pinned grammar sources instead of shipping prebuilt .so files
