local is_windows = vim.fn.has("win32") == 1

-- Blendet offene lazygit-Fenster aus
function _G.LazygitHide()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype == "terminal" and vim.api.nvim_buf_get_name(buf):find("lazygit") then
      vim.api.nvim_win_hide(win)
    end
  end
end

-- cmd.exe-kompatible Variante des nvim-remote-Presets
local function nvim_remote(target, line)
  local nv = "nvim --server %NVIM% "
  local keys = (line and ("<Cmd>" .. line .. "<CR>") or "") .. "<Cmd>lua LazygitHide()<CR>"
  return nv .. "--remote " .. target .. " && " .. nv .. '--remote-send "' .. keys .. '"'
end

return {
  "folke/snacks.nvim",
  opts = {
    lazygit = is_windows and {
      config = {
        os = {
          edit = nvim_remote("{{filename}}"),
          editAtLine = nvim_remote("{{filename}}", "{{line}}"),
          openDirInEditor = nvim_remote("{{dir}}"),
        },
      },
    } or nil,
    picker = {
      sources = {
        explorer = {
          hidden = true,
          ignored = true,
          actions = {
            reveal_in_explorer = function(_, item)
              if item then
                local path = item.file:gsub("/", "\\")
                vim.fn.jobstart({ "explorer", "/select," .. path }, { detach = true })
              end
            end,
          },
          win = {
            list = {
              keys = {
                ["R"] = "reveal_in_explorer",
              },
            },
          },
        },
        files = {
          hidden = true,
          ignored = true,
          matcher = {
            sort_empty = true,
            frecency = true,
            history_bonus = true,
          },
        },
        buffers = {
          sort_lastused = true,
        },
        grep = {
          hidden = true,
          ignored = true,
        },
      },
    },
    terminal = {
      win = {
        position = "float",
        border = "rounded",
        width = 0.85,
        height = 0.85,
        keys = {
          hide_ctrl_t = { "<C-t>", "hide", mode = { "n", "t" }, desc = "Hide Terminal" },
        },
      },
    },
  },
}
