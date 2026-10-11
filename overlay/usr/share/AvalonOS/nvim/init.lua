-- AvalonOS Neovim — packpath, theme, IDE layout, LSP, treesitter
if vim.g.avalonos_loaded then
  return
end
vim.g.avalonos_loaded = true

local avalon = "/usr/share/AvalonOS/nvim"
vim.opt.packpath:prepend(avalon)
vim.opt.runtimepath:prepend(avalon)
vim.opt.runtimepath:append(avalon .. "/parsers")

vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.mouse = "a"
vim.opt.clipboard = "unnamedplus"
vim.opt.undofile = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.termguicolors = true
vim.opt.signcolumn = "yes"
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.cursorline = true
vim.opt.scrolloff = 4

vim.cmd.colorscheme("avalonos")

local function git_branch()
  local h = io.popen("git rev-parse --abbrev-ref HEAD 2>/dev/null")
  if not h then
    return ""
  end
  local b = h:read("*l")
  h:close()
  return (b and b ~= "") and ("  " .. b) or ""
end

function _G.AvalonOSStatus()
  local m = vim.fn.mode()
  local map = { n = "NORMAL", i = "INSERT", v = "VISUAL", V = "V-LINE", ["\22"] = "V-BLOCK", c = "CMD", t = "TERM" }
  return string.format(" %s  %s%s  %d:%d  %s ", map[m] or m, vim.fn.expand("%:t"), git_branch(), vim.fn.line("."), vim.fn.col("."), vim.bo.filetype)
end
vim.opt.statusline = "%!v:lua.AvalonOSStatus()"

pcall(function()
  require("nvim-web-devicons").setup()
end)

pcall(function()
  require("nvim-tree").setup({
    hijack_netrw = true,
    view = { width = 28, side = "left" },
    renderer = { icons = { show = { file = true, folder = true, git = true } } },
    git = { enable = true },
    filters = { dotfiles = false },
  })
end)

pcall(function()
  require("nvim-treesitter").setup({
    install_dir = avalon .. "/parsers",
  })
  vim.opt.runtimepath:prepend(avalon .. "/parsers")
  vim.api.nvim_create_autocmd("FileType", {
    callback = function()
      pcall(vim.treesitter.start)
    end,
  })
end)

pcall(function()
  require("mason").setup({
    install_root_dir = vim.fn.stdpath("data") .. "/mason",
  })
  require("mason-lspconfig").setup({
    ensure_installed = { "lua_ls", "bashls", "marksman" },
    automatic_installation = false,
  })
end)

local function on_attach(_, bufnr)
  local o = { buffer = bufnr, silent = true }
  vim.keymap.set("n", "gd", vim.lsp.buf.definition, o)
  vim.keymap.set("n", "gr", vim.lsp.buf.references, o)
  vim.keymap.set("n", "K", vim.lsp.buf.hover, o)
  vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, o)
  vim.keymap.set("n", "]d", vim.diagnostic.goto_next, o)
end

do
  local servers = { "clangd", "pylsp", "lua_ls", "bashls", "marksman" }
  local caps = vim.lsp.protocol.make_client_capabilities()
  if vim.lsp.config then
    for _, name in ipairs(servers) do
      vim.lsp.config(name, { on_attach = on_attach, capabilities = caps })
      vim.lsp.enable(name)
    end
  else
    pcall(function()
      local lsp = require("lspconfig")
      for _, name in ipairs(servers) do
        if lsp[name] then
          lsp[name].setup({ on_attach = on_attach, capabilities = caps })
        end
      end
    end)
  end
end

pcall(function()
  vim.lsp.completion.enable(true)
end)

local function skip_ide()
  local ft = vim.bo.filetype
  local skip = { gitcommit = true, gitrebase = true, man = true, help = true }
  if skip[ft] then
    return true
  end
  local name = vim.fn.expand("%:t")
  if name == "COMMIT_EDITMSG" or name == "MERGE_MSG" or name == "git-rebase-todo" then
    return true
  end
  if vim.fn.argc() == 1 and vim.fn.argv(0) == "-" then
    return true
  end
  return false
end

vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    if skip_ide() or vim.g.avalonos_layout then
      return
    end
    if vim.tbl_contains(vim.v.argv, "--headless") then
      return
    end
    vim.g.avalonos_layout = true
    vim.defer_fn(function()
      pcall(function()
        require("nvim-tree.api").tree.open()
      end)
      vim.cmd("wincmd l")
      vim.cmd("botright 12split")
      vim.cmd("terminal")
      vim.cmd("startinsert")
      vim.cmd("wincmd k")
    end, 30)
  end,
})

vim.keymap.set("n", "<leader>e", function()
  pcall(function()
    require("nvim-tree.api").tree.toggle()
  end)
end)
vim.keymap.set("n", "<leader>t", function()
  local found = false
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.bo[b].buftype == "terminal" then
      vim.api.nvim_win_close(w, true)
      found = true
      break
    end
  end
  if not found then
    vim.cmd("botright 12split | terminal")
  end
end)
vim.keymap.set("n", "<leader>f", ":FZF<CR>")
vim.keymap.set("n", "<leader>g", function()
  vim.cmd("terminal rg --vimgrep " .. vim.fn.input("rg> "))
end)
local function is_chrome(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  local bt = vim.bo[buf].buftype
  local ft = vim.bo[buf].filetype
  return bt == "terminal" or ft == "NvimTree"
end

local function close_chrome()
  pcall(function()
    require("nvim-tree.api").tree.close()
  end)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if is_chrome(buf) and vim.api.nvim_buf_is_loaded(buf) then
      vim.bo[buf].modified = false
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

local function quit_all(bang)
  close_chrome()
  vim.cmd("qa" .. (bang and "!" or ""))
end

vim.api.nvim_create_user_command("Q", function(opts)
  quit_all(opts.bang)
end, { bang = true })
vim.api.nvim_create_user_command("WQ", function(opts)
  vim.cmd("wa" .. (opts.bang and "!" or ""))
  quit_all(opts.bang)
end, { bang = true })

local function cabbrev(lhs, rhs)
  vim.cmd(
    ("cnoreabbrev <expr> %s (getcmdtype() ==# ':' && getcmdline() ==# '%s') ? '%s' : '%s'"):format(
      lhs,
      lhs,
      rhs,
      lhs
    )
  )
end
-- :q / :wq leave the editor; tree + terminal are chrome, not extra files.
cabbrev("q", "Q")
cabbrev("wq", "WQ")
cabbrev("x", "WQ")
cabbrev("qa", "Q")
cabbrev("wqa", "WQ")
cabbrev("quit", "Q")
cabbrev("qall", "Q")
cabbrev("quitall", "Q")
cabbrev("xa", "WQ")

vim.keymap.set("n", "<leader>w", ":write<CR>")
vim.keymap.set("n", "<leader>q", function()
  quit_all(false)
end)
vim.keymap.set("n", "ZZ", function()
  vim.cmd("wa")
  quit_all(false)
end)
vim.keymap.set("n", "ZQ", function()
  quit_all(true)
end)

vim.api.nvim_create_autocmd("TermOpen", {
  callback = function(ev)
    vim.bo[ev.buf].buflisted = false
    vim.bo[ev.buf].bufhidden = "hide"
    vim.bo[ev.buf].modified = false
  end,
})

-- A live :terminal is always "modified"; don't let that block :q / :qa.
vim.api.nvim_create_autocmd("BufModifiedSet", {
  callback = function(ev)
    if is_chrome(ev.buf) then
      vim.bo[ev.buf].modified = false
    end
  end,
})
vim.keymap.set("n", "<C-h>", "<C-w>h")
vim.keymap.set("n", "<C-j>", "<C-w>j")
vim.keymap.set("n", "<C-k>", "<C-w>k")
vim.keymap.set("n", "<C-l>", "<C-w>l")
vim.keymap.set("t", "<C-h>", "<C-\\><C-n><C-w>h")
vim.keymap.set("t", "<C-j>", "<C-\\><C-n><C-w>j")
vim.keymap.set("t", "<C-k>", "<C-\\><C-n><C-w>k")
vim.keymap.set("t", "<C-l>", "<C-\\><C-n><C-w>l")
