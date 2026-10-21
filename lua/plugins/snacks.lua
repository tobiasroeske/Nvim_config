local is_windows = vim.fn.has("win32") == 1

-- Verzeichnisse, die Files-Picker und Grep nie durchsuchen (auch nicht mit Alt+i)
-- Gitignorete Dateien, die trotzdem durchsucht werden sollen, stehen als !-Regel in der .ignore im Projekt-Root
local exclude = {
  ".git",
  "node_modules",
  "build",
  "web/bundles",
  "web/css",
  "web/js",
  "web/build",
  "web/react",
  "web/assets/bulby",
  "web/assets/legacy/css/elearnwin/assistants",
  "web/assetic",
  "web/data",
  "web/course",
  "src/LegacyApp/easylearn/upload",
  "src/LegacyApp/easylearn/data",
  "packages/AuthoringTool/src/Application/Export/dist-files",
  "knowledge-frame",
  ".gitlab-ci-local",
  "react/.yarn",
}

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

-- Alle Terminals im unteren Panel ein-/ausblenden, beim ersten Aufruf eins erstellen
local function toggle_panel()
  local terms = Snacks.terminal.list()
  local visible = vim.tbl_filter(function(t)
    return t:win_valid()
  end, terms)
  if #visible > 0 then
    for _, t in ipairs(visible) do
      t:hide()
    end
  elseif #terms > 0 then
    for _, t in ipairs(terms) do
      t:show()
    end
  else
    Snacks.terminal.open(nil, { cwd = LazyVim.root(), count = 1 })
  end
end

-- Weiteres Terminal neben den bestehenden im Panel öffnen
local function new_terminal()
  local terms = Snacks.terminal.list()
  local next_id = 1
  for _, t in ipairs(terms) do
    if not t:win_valid() then
      t:show()
    end
    local info = vim.b[t.buf].snacks_terminal
    if info and info.id >= next_id then
      next_id = info.id + 1
    end
  end
  Snacks.terminal.open(nil, { cwd = LazyVim.root(), count = next_id })
end

return {
  "folke/snacks.nvim",
  keys = {
    { "<C-t>", toggle_panel, desc = "Toggle Terminal Panel" },
    { "<leader>tn", new_terminal, desc = "New Terminal" },
  },
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
          ignored = false,
          exclude = exclude,
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
          ignored = false,
          exclude = exclude,
        },
      },
    },
    terminal = {
      win = {
        position = "bottom",
        height = 0.3,
        keys = {
          toggle_panel = { "<C-t>", toggle_panel, mode = { "n", "t" }, desc = "Toggle Terminal Panel" },
          new_terminal = { "<A-n>", new_terminal, mode = { "n", "t" }, desc = "New Terminal" },
        },
      },
    },
  },
}
