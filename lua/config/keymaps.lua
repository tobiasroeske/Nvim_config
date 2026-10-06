-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Exit insert mode without reaching for Esc
vim.keymap.set("i", "jk", "<Esc>", { desc = "Exit insert mode" })
vim.keymap.set("i", "jj", "<Esc>", { desc = "Exit insert mode" })
vim.keymap.set({ "n", "v" }, "<Tab>", "<cmd>bnext<cr>", { desc = "Next buffer" })
vim.keymap.set({ "n", "v" }, "<S-Tab>", "<cmd>bprevious<cr>", { desc = "Previous buffer" })

-- Resize windows with plain arrow keys in normal mode (no modifier, no OS shortcut conflicts)
vim.keymap.set("n", "<Up>", "<cmd>resize +2<cr>", { desc = "Increase Window Height" })
vim.keymap.set("n", "<Down>", "<cmd>resize -2<cr>", { desc = "Decrease Window Height" })
vim.keymap.set("n", "<Left>", "<cmd>vertical resize -2<cr>", { desc = "Decrease Window Width" })
vim.keymap.set("n", "<Right>", "<cmd>vertical resize +2<cr>", { desc = "Increase Window Width" })

-- Open In File Explorer
vim.keymap.set("n", "<leader>fX", function()
  local dir = vim.fn.expand("%:p:h")

  if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
    dir = dir:gsub("/", "\\")
    vim.cmd("!explorer.exe " .. vim.fn.shellescape(dir))
  elseif vim.fn.has("macunix") == 1 then
    vim.cmd("!open " .. vim.fn.shellescape(dir))
  end
end, { desc = "Ordner der aktuellen Datei im Windows Explorer öffnen" })

-- Floating Temrinal
vim.keymap.set("n", "<C-t>", function()
  Snacks.terminal(nil, { cwd = LazyVim.root() })
end, { desc = "Toggle Terminal (Root Dir)" })
