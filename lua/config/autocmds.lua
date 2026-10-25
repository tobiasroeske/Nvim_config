-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Format and save a file buffer when leaving it, but only if it changed since it was
-- loaded or last formatted. Auto-save writes with noautocmd, so it never formats.
local format_on_leave = vim.api.nvim_create_augroup("format_on_leave", { clear = true })

local function mark_formatted(buf)
  vim.b[buf].format_on_leave_tick = vim.api.nvim_buf_get_changedtick(buf)
end

for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_loaded(buf) then
    mark_formatted(buf)
  end
end

vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
  group = format_on_leave,
  callback = function(ev)
    mark_formatted(ev.buf)
  end,
})

vim.api.nvim_create_autocmd("BufLeave", {
  group = format_on_leave,
  callback = function(ev)
    local buf = ev.buf
    if vim.bo[buf].buftype ~= "" or not vim.bo[buf].modifiable or vim.api.nvim_buf_get_name(buf) == "" then
      return
    end
    if vim.b[buf].format_on_leave_tick == vim.api.nvim_buf_get_changedtick(buf) then
      return
    end
    LazyVim.format({ buf = buf })
    if vim.bo[buf].modified then
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("silent! noautocmd write")
      end)
    end
    mark_formatted(buf)
  end,
})
