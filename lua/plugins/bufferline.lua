-- Active buffer as a highlighted tab: catppuccin theme, selected parts on surface0, accent bar on the left
return {
  {
    "akinsho/bufferline.nvim",
    opts = function(_, opts)
      opts.options = opts.options or {}
      opts.options.always_show_bufferline = true
      opts.options.indicator = { style = "icon", icon = "▎" }

      opts.highlights = function()
        local hl = require("catppuccin.special.bufferline").get_theme()()
        local C = require("catppuccin.palettes").get_palette()
        for name, group in pairs(hl) do
          if name:match("_selected$") then
            group.bg = C.surface0
          end
        end
        hl.buffer_selected.fg = C.mauve
        hl.buffer_selected.bold = true
        hl.indicator_selected.fg = C.mauve
        hl.buffer_visible.fg = C.overlay1
        hl.background.fg = C.overlay1
        return hl
      end
    end,
  },
}
