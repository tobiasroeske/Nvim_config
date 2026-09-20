return {
  {
    "petertriho/nvim-scrollbar",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = {
      "lewis6991/gitsigns.nvim",
    },
    opts = {
      handlers = {
        diagnostic = true,
        gitsigns = true,
      },
    },
  },
}
