-- Minimap (code structure, diagnostics, git, search) in its own split on the right
return {
  "Isrothy/neominimap.nvim",
  version = "v3.x.x",
  lazy = false,
  keys = {
    { "<leader>uM", "<cmd>Neominimap Toggle<cr>", desc = "Toggle Minimap" },
  },
  init = function()
    ---@type Neominimap.UserConfig
    vim.g.neominimap = {
      auto_enable = true,
      layout = "split",
      split = {
        minimap_width = 20,
        fix_width = true,
        close_if_last_window = true,
      },
      -- 8 source lines per minimap row
      y_multiplier = 2,
      click = { enabled = true },
      search = { enabled = true },
    }
  end,
}
