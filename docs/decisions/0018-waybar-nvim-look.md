# ADR 0018: Waybar + Neovim look and tooling

- Status: accepted
- Date: 2026-09-07
- Fedora: 44

## Decision

Waybar is **42px**, floated with **6px top / 8px side** margins, **14px
rounded corners**, JetBrains Mono + Font Awesome 6, module pills.

Right-side modules: mpris, hardware stats, btop, brightness (lightbulb
icon, percent on the chip, tooltip `brightness`), volume (left-click
**pavucontrol-qt**, right-click mute, scroll adjusts), network (Wi-Fi
SSID list, Bluetooth, connections), battery, tray. HW and btop open
floating windows top-right.

Neovim is an AvalonOS IDE layout: nvim-tree left, terminal bottom,
AvalonOS colorscheme, Mason + lspconfig + treesitter vendored as Vim
packages under `/usr/share/AvalonOS/nvim/pack/avalon/start/`.

## Packages

jetbrains-mono-fonts, fontawesome-6-free-fonts, btop, ripgrep, fzf,
fd-find, clang-tools-extra, python3-lsp-server, tree-sitter-cli, tar.

## Notes

- Mason still installs lua_ls/bashls/marksman into the user data dir on
  first networked nvim.
- clangd and pylsp come from Fedora PATH.
- Treesitter parsers compiled on the build host into
  `/usr/share/AvalonOS/nvim/parsers`.
- Skip IDE chrome for gitcommit / COMMIT_EDITMSG.
