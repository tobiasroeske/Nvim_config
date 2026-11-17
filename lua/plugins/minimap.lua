-- Minimap as a floating overlay on the right edge of each window
-- (outside the window layout, so split navigation skips it): code shape with syntax colors,
-- git/diagnostics/search as thin markers in a fixed gutter
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
      layout = "float",
      float = {
        minimap_width = 20,
        window_border = "none",
      },
      -- 8 source lines per minimap row
      y_multiplier = 2,
      -- Current line position maps proportionally to the file
      current_line_position = "percent",
      click = { enabled = true },
      -- Git hunks, diagnostics and search matches as gutter markers
      git = { enabled = true, mode = "sign" },
      diagnostic = { mode = "sign", severity = { min = vim.diagnostic.severity.WARN } },
      search = { enabled = true, mode = "sign" },
      -- Always reserve the gutter so the minimap doesn't shift when markers appear
      winopt = function(opt)
        opt.signcolumn = "yes:1"
      end,
    }
  end,
}
