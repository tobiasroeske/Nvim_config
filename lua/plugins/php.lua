return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      intelephense = {
        cmd_env = { NODE_OPTIONS = "--max-old-space-size=4096" },
        init_options = { storagePath = vim.fn.stdpath("cache") .. "/intelephense" },
        settings = {
          intelephense = {
            format = { enable = false },
            files = {
              exclude = {
                "**/.git/**",
                "**/node_modules/**",
                "**/bower_components/**",
                "**/vendor/**/{Tests,tests}/**",
                "**/vendor/**/vendor/**",
                "**/.history/**",
                "**/var/**",
                "**/.gitlab-ci-local/**",
                "**/react/.yarn/**",
                "**/src/LegacyApp/easylearn/upload/**",
                "**/src/LegacyApp/easylearn/data/**",
              },
            },
          },
        },
      },
    },
  },
}
