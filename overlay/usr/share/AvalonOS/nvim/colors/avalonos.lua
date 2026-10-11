-- AvalonOS colorscheme
local bg, bg_alt = "#0A1628", "#102445"
local fg, neon = "#D4FFD4", "#39FF14"
local accent, dim, idle = "#C2185B", "#8B1450", "#1A3A5C"

vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
  vim.cmd("syntax reset")
end
vim.g.colors_name = "avalonos"
vim.o.termguicolors = true
vim.o.background = "dark"

local function hi(group, opts)
  vim.api.nvim_set_hl(0, group, opts)
end

hi("Normal", { fg = fg, bg = bg })
hi("NormalFloat", { fg = fg, bg = bg_alt })
hi("FloatBorder", { fg = neon, bg = bg_alt })
hi("Comment", { fg = "#6fa86f", italic = true })
hi("Constant", { fg = accent })
hi("String", { fg = neon })
hi("Identifier", { fg = fg })
hi("Function", { fg = neon })
hi("Statement", { fg = neon, bold = true })
hi("Keyword", { fg = neon, bold = true })
hi("PreProc", { fg = idle })
hi("Type", { fg = "#8ecb8e" })
hi("Special", { fg = accent })
hi("Error", { fg = accent, bold = true })
hi("Todo", { fg = accent, bold = true })
hi("LineNr", { fg = idle })
hi("CursorLineNr", { fg = neon, bold = true })
hi("CursorLine", { bg = bg_alt })
hi("Visual", { bg = dim })
hi("Search", { fg = bg, bg = neon })
hi("IncSearch", { fg = bg, bg = accent })
hi("Pmenu", { fg = fg, bg = bg_alt })
hi("PmenuSel", { fg = bg, bg = neon })
hi("StatusLine", { fg = fg, bg = bg_alt })
hi("StatusLineNC", { fg = idle, bg = bg })
hi("VertSplit", { fg = idle, bg = bg })
hi("WinSeparator", { fg = idle })
hi("SignColumn", { bg = bg })
hi("ColorColumn", { bg = bg_alt })
hi("MatchParen", { fg = neon, bold = true })
hi("DiagnosticError", { fg = accent })
hi("DiagnosticWarn", { fg = "#e0c060" })
hi("DiagnosticInfo", { fg = neon })
hi("DiagnosticHint", { fg = idle })
hi("DiffAdd", { fg = neon })
hi("DiffDelete", { fg = accent })
hi("DiffChange", { fg = idle })
hi("NvimTreeNormal", { fg = fg, bg = bg })
hi("NvimTreeFolderName", { fg = neon })
hi("NvimTreeOpenedFolderName", { fg = neon, bold = true })
hi("NvimTreeGitDirty", { fg = accent })
hi("NvimTreeGitNew", { fg = neon })
