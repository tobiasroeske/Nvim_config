return {
  "petertriho/nvim-scrollbar",
  branch = "v1",
  event = "BufReadPost",
  opts = function()
    local C = require("catppuccin.palettes").get_palette()
    return {
      handle = {
        color = C.surface2,
        blend = 0,
      },
      handlers = {
        diagnostic = true,
        gitsigns = true,
        search = false,
      },
      marks = {
        Error = { text = { "▐" }, color = C.red },
        Warn = { text = { "▐" }, color = C.yellow },
        Info = { text = { "▐" }, color = C.blue },
        Hint = { text = { "▐" }, color = C.green },
      },
    }
  end,
}
