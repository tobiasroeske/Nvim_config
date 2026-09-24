return {
  {
    "stevearc/conform.nvim",
    opts = function(_, opts)
      opts.formatters = opts.formatters or {}
      opts.formatters.oxfmt = {
        condition = function(_, ctx)
          return vim.fs.root(ctx.buf, {
            ".oxfmtrc.json",
            ".oxfmtrc.jsonc",
            "oxfmt.config.ts",
          }) ~= nil
        end,
      }
      opts.default_format_opts = vim.tbl_extend("force", opts.default_format_opts or {}, {
        stop_after_first = true,
      })
    end,
  },
}
