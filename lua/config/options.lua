-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.g.snacks_animate = false
vim.g.lazyvim_prettier_needs_config = true
vim.g.ai_cmp = false
vim.o.shelltemp = false
local shellcmdflag = "-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command "
shellcmdflag = shellcmdflag .. "[Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new();"
shellcmdflag = shellcmdflag .. "$PSDefaultParameterValues['Out-File:Encoding']='utf8';"
vim.o.shellpipe = "> %s 2>&1"
vim.o.shellquote = ""
vim.o.shellxquote = ""
if vim.fn.executable("pwsh.exe") == 1 then
  vim.o.shell = "pwsh.exe"
  shellcmdflag = shellcmdflag .. "$PSStyle.OutputRendering = 'PlainText';"
  vim.env.__SuppressAnsiEscapeSequences = "1"
else
  vim.o.shell = "powershell.exe"
end
vim.o.shellcmdflag = shellcmdflag
