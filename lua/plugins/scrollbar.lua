return {
  "petertriho/nvim-scrollbar",
  branch = "v1",
  event = "BufReadPost",
  opts = {
    handlers = {
      diagnostic = true,
      gitsigns = true,
      search = false,
    },
    marks = {
      Error = { text = { "▐" }, color = "#ED8796" },
      Warn = { text = { "▐" }, color = "#EED49F" },
      Info = { text = { "▐" }, color = "#8AADF4" },
      Hint = { text = { "▐" }, color = "#A6DA95" },
    },
  },
}
