-- lua/plugins/mini-operators.lua
return {
  "nvim-mini/mini.operators",
  event = "VeryLazy",
  opts = {
    replace = { prefix = "gr" },
  },
}
