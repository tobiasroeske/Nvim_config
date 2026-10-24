-- Seamless Ctrl-h/j/k/l navigation between Neovim splits and Zellij panes
return {
  "smart-splits-nvim/smart-splits.nvim",
  version = "^3.0.0",
  lazy = false,
  dependencies = {
    {
      "smart-splits-nvim/backend-zellij-lua",
      main = "smart-splits-backend-zellij-lua",
      opts = { disable_nav_when_zoomed = true },
    },
  },
  opts = {
    mux = { backend = "smart-splits-backend-zellij-lua" },
  },
  keys = {
    { "<c-h>", function() require("smart-splits").move_cursor_left() end, desc = "Navigate left (nvim/zellij)" },
    { "<c-j>", function() require("smart-splits").move_cursor_down() end, desc = "Navigate down (nvim/zellij)" },
    { "<c-k>", function() require("smart-splits").move_cursor_up() end, desc = "Navigate up (nvim/zellij)" },
    { "<c-l>", function() require("smart-splits").move_cursor_right() end, desc = "Navigate right (nvim/zellij)" },
  },
}
