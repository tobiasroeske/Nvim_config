-- Seamless Ctrl-h/j/k/l navigation between Neovim splits and tmux panes
return {
  "christoomey/vim-tmux-navigator",
  cmd = {
    "TmuxNavigateLeft",
    "TmuxNavigateDown",
    "TmuxNavigateUp",
    "TmuxNavigateRight",
    "TmuxNavigatePrevious",
  },
  keys = {
    { "<c-h>", "<cmd><C-U>TmuxNavigateLeft<cr>", desc = "Navigate left (nvim/tmux)" },
    { "<c-j>", "<cmd><C-U>TmuxNavigateDown<cr>", desc = "Navigate down (nvim/tmux)" },
    { "<c-k>", "<cmd><C-U>TmuxNavigateUp<cr>", desc = "Navigate up (nvim/tmux)" },
    { "<c-l>", "<cmd><C-U>TmuxNavigateRight<cr>", desc = "Navigate right (nvim/tmux)" },
    { "<c-\\>", "<cmd><C-U>TmuxNavigatePrevious<cr>", desc = "Navigate previous (nvim/tmux)" },
  },
}
