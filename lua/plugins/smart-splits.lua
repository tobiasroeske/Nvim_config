-- Seamless Ctrl-h/j/k/l navigation between Neovim splits and WezTerm panes
-- (WezTerm half: smart-splits plugin in the chezmoi-managed wezterm.lua)
return {
  "smart-splits-nvim/smart-splits.nvim",
  version = "^3.0.0",
  lazy = false,
  dependencies = {
    {
      "smart-splits-nvim/backend-wezterm",
      main = "smart-splits-backend-wezterm",
      opts = {},
    },
  },
  opts = {
    mux = { backend = "smart-splits-backend-wezterm" },
  },
  keys = {
    { "<c-h>", function() require("smart-splits").move_cursor_left() end, desc = "Navigate left (nvim/wezterm)" },
    { "<c-j>", function() require("smart-splits").move_cursor_down() end, desc = "Navigate down (nvim/wezterm)" },
    { "<c-k>", function() require("smart-splits").move_cursor_up() end, desc = "Navigate up (nvim/wezterm)" },
    { "<c-l>", function() require("smart-splits").move_cursor_right() end, desc = "Navigate right (nvim/wezterm)" },
  },
}
