-- Catppuccin (macchiato) mit transparentem Hintergrund und leicht transparenten Floats
-- Ablage: lua/plugins/catppuccin.lua
return {
  "catppuccin/nvim",
  name = "catppuccin",
  opts = {
    flavour = "macchiato",
    transparent_background = true, -- Normal, NormalNC, SignColumn, Statusline usw. ohne Hintergrund
    float = {
      transparent = true, -- Floating Windows ohne eigenen Hintergrund
      solid = false,
    },
  },
  config = function(_, opts)
    require("catppuccin").setup(opts)

    -- Blend-Effekt fuer alle neuen Floating Windows (Snacks-Terminal, Picker, Noice, which-key, blink.cmp)
    vim.o.winblend = 15
    -- Blend-Effekt fuer Popup-Menues (Completion-Menue)
    vim.o.pumblend = 15
  end,
}
