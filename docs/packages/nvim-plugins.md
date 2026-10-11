# Vendored Neovim plugins

Snapshotted into `overlay/usr/share/AvalonOS/nvim/pack/avalon/start/`
(`.git` stripped). Built 2026-09-07.

Upstream URLs are the project's usual GitHub repositories. Full 40-character
commits were not recorded at snapshot time (AOS-SEC-16); the short SHAs below
are the ones written then, and the full commits are the unique GitHub
resolutions of those short SHAs (queried 2026-11-21). The sha256 is a
content hash of the vendored tree in this repository (paths sorted, file
contents concatenated) so the shipped snapshot can be re-checked without
`.git`. The vendored tree may still differ from the upstream commit because
`.git` was stripped.

| Plugin | Upstream | Short SHA (as recorded 2026-09-07) | Full commit | Vendored tree sha256 |
|---|---|---|---|
| nvim-lspconfig | https://github.com/neovim/nvim-lspconfig | 615d7b2 | 615d7b2712efb2f530a83a9d0466acafba6b1d6f | 56c37f25ba430e4f53da59043a0b33c3623d7bb86a7dd19273ad35a10e212b58 |
| mason.nvim | https://github.com/williamboman/mason.nvim | 2a6940a | 2a6940af80375532e5e9e7c1f2fc6319a1b7a69d | 43617683a3ff3c6aa886296da977efe8abf4cce20fb7f9831cd3a38871023c40 |
| mason-lspconfig.nvim | https://github.com/williamboman/mason-lspconfig.nvim | 40276c4 | 40276c4df7e6bdce6801d6c035c6227f9115a855 | b0cd5883c7e106e8771419cf9f2874f5ace5eb0539132fde9a2ec4e5821bb61a |
| nvim-treesitter | https://github.com/nvim-treesitter/nvim-treesitter | 0d09690 | 0d0969030ad955b510d7c8012b40252a25c12a6d | c61776ca3a5fa9facb5bff3322591e16d8c7659a98d2cfb3f8c63de648192e98 |
| nvim-tree.lua | https://github.com/nvim-tree/nvim-tree.lua | b2aadda | b2aadda94b107480c48e548d6db51c6840b7b33c | d8527f7fba1f1ebd0cd8cf65980a78d46b8efb9920bb3357fdfad44c6cf776c4 |
| nvim-web-devicons | https://github.com/nvim-tree/nvim-web-devicons | 5f032a8 | 5f032a85be210cd1c6ac98861eb3b187ff3bd5eb | 1a4a81d3417deafc70f09b28695d4847f88ea495bad3b1ea4c38a9d039996978 |

Treesitter parsers (`.so`, prebuilt x86_64 binaries committed as shipped) in
`nvim/parsers/parser/`: lua vim vimdoc query
python bash json markdown markdown_inline c cpp.

## LSP binaries (P-L9)

The `avalonos-nvim-lsp` RPM pins sha256 hashes of the upstream-published
language-server binaries it vendors. Those pins are the review artifact;
this tree does not rebuild those servers from source. Mason-managed
installs performed later by a user are outside the pinned set and are not
a reviewed AvalonOS component.

When these plugins are next refreshed, record the full commit, a
`git write-tree` (or equivalent) of the snapshot, and the upstream URL in
this file.
