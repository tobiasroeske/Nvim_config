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

local toggle_panel, new_terminal
local editor_win

-- Panel-Terminals sind Snacks-Terminals ohne eigenen Befehl (lazygit & Co. bleiben aussen vor)
local function panel_terms()
  return vim.tbl_filter(function(t)
    local info = vim.b[t.buf].snacks_terminal
    return info ~= nil and info.cmd == nil
  end, Snacks.terminal.list())
end

-- Fenster merken, aus dem das Panel geöffnet wurde, damit der Fokus beim Schliessen dorthin zurückgeht
local function remember_editor_win()
  if not vim.b.snacks_terminal then
    editor_win = vim.api.nvim_get_current_win()
  end
end

local function open_panel_terminal(count)
  Snacks.terminal.open(nil, {
    cwd = LazyVim.root(),
    count = count,
    win = {
      position = "bottom",
      height = 0.3,
      keys = {
        toggle_panel = {
          "<C-t>",
          function()
            toggle_panel()
          end,
          mode = { "n", "t" },
          desc = "Toggle Terminal Panel",
        },
        new_terminal = {
          "<A-n>",
          function()
            new_terminal()
          end,
          mode = { "n", "t" },
          desc = "New Terminal",
        },
      },
    },
  })
end

-- Alle Panel-Terminals ein-/ausblenden, beim ersten Aufruf eins erstellen
function toggle_panel()
  local terms = panel_terms()
  local visible = vim.tbl_filter(function(t)
    return t:win_valid()
  end, terms)
  if #visible > 0 then
    for _, t in ipairs(visible) do
      t:hide()
    end
    if editor_win and vim.api.nvim_win_is_valid(editor_win) then
      vim.api.nvim_set_current_win(editor_win)
    end
  else
    remember_editor_win()
    if #terms > 0 then
      for _, t in ipairs(terms) do
        t:show()
      end
    else
      open_panel_terminal(1)
    end
  end
end

-- Weiteres Terminal neben den bestehenden im Panel öffnen
function new_terminal()
  remember_editor_win()
  local next_id = 1
  for _, t in ipairs(panel_terms()) do
    if not t:win_valid() then
      t:show()
    end
    local id = vim.b[t.buf].snacks_terminal.id
    if id >= next_id then
      next_id = id + 1
    end
  end
  open_panel_terminal(next_id)
end

return {
  "folke/snacks.nvim",
  keys = {
    {
      "<C-t>",
      function()
        toggle_panel()
      end,
      desc = "Toggle Terminal Panel",
    },
    {
      "<leader>tn",
      function()
        new_terminal()
      end,
      desc = "New Terminal",
    },
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
            toggle_terminal_panel = function()
              toggle_panel()
            end,
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
                ["<c-t>"] = "toggle_terminal_panel",
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
  },
}
