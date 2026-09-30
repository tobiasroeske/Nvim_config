return {
  {
    "akinsho/bufferline.nvim",
    opts = function(_, opts)
      opts.options = opts.options or {}
      opts.options.always_show_bufferline = true
      opts.options.indicator = { style = "underline" }

      opts.highlights = {
        buffer_selected = {
          fg = "#cba6f7",
          bg = "#313244",
          bold = true,
          italic = false,
        },
      }
    end,
  },
}
