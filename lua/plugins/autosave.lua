return {
  "okuuva/auto-save.nvim",
  cmd = "ASToggle",
  event = "VeryLazy",
  opts = {
    trigger_events = {
      immediate_save = { "BufLeave", "FocusLost" },
      defer_save = { "InsertLeave", "TextChanged" },
    },
    debounce_delay = 2000,
    write_all_buffers = true,
    -- skip BufWritePre so auto-save never triggers formatting; <C-s> / :w still formats
    noautocmd = true,
  },
}
