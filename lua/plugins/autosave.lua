return {
  "okuuva/auto-save.nvim",
  cmd = "ASToggle",
  event = "VeryLazy",
  opts = {
    trigger_events = {
      immediate_save = { "BufLeave", "FocusLost" },
      defer_save = {},
    },
    noautocmd = true,
  },
}
