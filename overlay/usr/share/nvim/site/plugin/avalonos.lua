-- Guarantee AvalonOS nvim config even if /etc/xdg/nvim is skipped.
if not vim.g.avalonos_loaded then
  dofile("/usr/share/AvalonOS/nvim/init.lua")
end
