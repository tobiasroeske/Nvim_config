-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Exit insert mode without reaching for Esc
vim.keymap.set("i", "jk", "<Esc>", { desc = "Exit insert mode" })
vim.keymap.set("i", "jj", "<Esc>", { desc = "Exit insert mode" })
vim.keymap.set({ "n", "v" }, "<Tab>", "<cmd>bnext<cr>", { desc = "Next buffer" })
vim.keymap.set({ "n", "v" }, "<S-Tab>", "<cmd>bprevious<cr>", { desc = "Previous buffer" })
