-- Vault location: $OBSIDIAN_VAULT or ~/Obsidian/Tobis Vault
local vault = vim.fs.normalize(vim.env.OBSIDIAN_VAULT or "~/Obsidian/Tobis Vault")
local has_vault = vim.fn.isdirectory(vault) == 1
local is_windows = vim.fn.has("win32") == 1

local function in_vault(path)
  if not has_vault or path == "" then
    return false
  end
  local p, v = vim.fs.normalize(path), vault
  if is_windows then
    p, v = p:lower(), v:lower()
  end
  return vim.startswith(p, v .. "/")
end

local function timestamp_id(title)
  local prefix = os.date("%Y-%m-%d %H%M")
  if title ~= nil and title ~= "" then
    return prefix .. " " .. title
  end
  return prefix
end

-- Nearest existing daily note before or after `date` (YYYY-MM-DD), mirroring the Templater logic
local function daily_neighbor(date, direction)
  local best
  for name, type in vim.fs.dir(vault .. "/Daily") do
    local d = type == "file" and name:match("^(%d%d%d%d%-%d%d%-%d%d)%.md$")
    if d and d ~= date then
      if direction == "prev" and d < date and (not best or d > best) then
        best = d
      elseif direction == "next" and d > date and (not best or d < best) then
        best = d
      end
    end
  end
  return best
end

-- Point the neighbor's `key` property at the new daily note
local function set_daily_property(neighbor, key, date)
  local path = vault .. "/Daily/" .. neighbor .. ".md"
  local lines = vim.fn.readfile(path)
  for i, line in ipairs(lines) do
    if i > 1 and line == "---" then
      break
    end
    if line:match("^" .. key .. ":") then
      lines[i] = string.format('%s: "[[%s]]"', key, date)
      vim.fn.writefile(lines, path)
      return
    end
  end
end

-- Template substitution for vorher/nachher; also back-links the neighbor note
local function daily_link(direction, key)
  return function(ctx)
    local date = ctx.partial_note and ctx.partial_note.id
    if not date then
      return ""
    end
    local neighbor = daily_neighbor(date, direction)
    if not neighbor then
      return ""
    end
    set_daily_property(neighbor, key, date)
    return "[[" .. neighbor .. "]]"
  end
end

-- File creation time, read once per explorer node
local function birthtime(node)
  if node.birthtime == nil then
    local stat = vim.uv.fs_stat(node.path)
    node.birthtime = stat and stat.birthtime.sec or 0
  end
  return node.birthtime
end

-- Snacks explorer: inside the vault, folders first, then notes by creation date (newest first)
local function patch_explorer_sort()
  local tree = require("snacks.explorer.tree")
  local default_walk = tree.walk

  function tree:walk(node, fn, opts)
    if not in_vault(node.path .. "/_") then
      return default_walk(self, node, fn, opts)
    end
    local abort = fn(node)
    if abort ~= nil then
      return abort
    end
    local children = vim.tbl_values(node.children)
    table.sort(children, function(a, b)
      if a.dir ~= b.dir then
        return a.dir
      end
      if a.dir then
        return a.name < b.name
      end
      local ta, tb = birthtime(a), birthtime(b)
      if ta ~= tb then
        return ta > tb
      end
      return a.name < b.name
    end)
    for c, child in ipairs(children) do
      child.last = c == #children
      if child.dir and (child.open or (opts and opts.all)) then
        abort = self:walk(child, fn, opts)
      else
        abort = fn(child)
      end
      if abort then
        return true
      end
    end
    return false
  end
end

local function new_journal_entry()
  vim.ui.input({ prompt = "Tagebuch-Titel (optional): " }, function(title)
    if title == nil then
      return
    end
    require("obsidian.actions").new_from_template(title, "Tagebuch Template", function(note)
      note:open({ sync = true })
    end)
  end)
end

return {
  {
    "obsidian-nvim/obsidian.nvim",
    version = "*",
    cond = has_vault,
    ft = "markdown",
    cmd = "Obsidian",
    init = function()
      -- Vault notes are not auto-formatted (prettier/markdownlint)
      vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
        group = vim.api.nvim_create_augroup("obsidian_vault", { clear = true }),
        pattern = "*.md",
        callback = function(ev)
          if in_vault(vim.api.nvim_buf_get_name(ev.buf)) then
            vim.b[ev.buf].autoformat = false
          end
        end,
      })
      -- Vault notes have no spell checking (LazyVim enables it for markdown)
      vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
        group = "obsidian_vault",
        pattern = { "markdown", "*.md" },
        callback = function(ev)
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(ev.buf) and in_vault(vim.api.nvim_buf_get_name(ev.buf)) then
              for _, win in ipairs(vim.fn.win_findbuf(ev.buf)) do
                vim.wo[win].spell = false
              end
            end
          end)
        end,
      })
      vim.api.nvim_create_autocmd("User", {
        pattern = "VeryLazy",
        once = true,
        callback = patch_explorer_sort,
      })
    end,
    keys = {
      { "<leader>Oj", new_journal_entry, desc = "New Journal Entry" },
      { "<leader>On", "<cmd>Obsidian new_from_template<cr>", desc = "New Note (pick Template)" },
      { "<leader>Ot", "<cmd>Obsidian today<cr>", desc = "Today" },
      { "<leader>Oy", "<cmd>Obsidian yesterday<cr>", desc = "Yesterday" },
      { "<leader>Od", "<cmd>Obsidian dailies<cr>", desc = "Dailies" },
      { "<leader>Of", "<cmd>Obsidian quick_switch<cr>", desc = "Find Note" },
      { "<leader>Os", "<cmd>Obsidian search<cr>", desc = "Search Vault" },
      { "<leader>Ob", "<cmd>Obsidian backlinks<cr>", desc = "Backlinks" },
      { "<leader>Ol", "<cmd>Obsidian links<cr>", desc = "Links" },
      { "<leader>Og", "<cmd>Obsidian tags<cr>", desc = "Tags" },
      { "<leader>Oo", "<cmd>Obsidian open<cr>", desc = "Open in Obsidian App" },
      { "<leader>Op", "<cmd>Obsidian paste_img<cr>", desc = "Paste Image" },
    },
    ---@module 'obsidian'
    ---@type obsidian.config
    opts = {
      legacy_commands = false,
      workspaces = {
        { name = "Tobis Vault", path = vault },
      },

      -- Notes land in the vault root; the title is the filename, no title gives a timestamp
      new_notes_location = "notes_subdir",
      note_id_func = function(title)
        if title ~= nil and title ~= "" then
          return title
        end
        return timestamp_id()
      end,
      note = { template = "Notiz Template.md" },

      -- Leave frontmatter untouched; templates provide it
      frontmatter = { enabled = false },

      templates = {
        folder = "Templates",
        substitutions = {
          vorher = daily_link("prev", "nachher"),
          nachher = daily_link("next", "vorher"),
        },
        customizations = {
          -- Journal entries get the "YYYY-MM-DD HHmm" prefix
          ["Tagebuch Template"] = { note_id_func = timestamp_id },
        },
      },
      daily_notes = {
        folder = "Daily",
        date_format = "YYYY-MM-DD",
        workdays_only = false,
        template = vim.fn.stdpath("config") .. "/templates/obsidian/daily.md",
      },
      attachments = { folder = "Attachments" },
      file = {
        ignore_filters = { "_Anleitungen/", "Attachments/", "claude", ".claude" },
      },
      picker = { name = "snacks.picker" },
    },
  },
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters = {
        ["markdownlint-cli2"] = {
          condition = function(ctx)
            return not in_vault(ctx.filename)
          end,
        },
      },
    },
  },
  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        { "<leader>O", group = "obsidian", icon = { icon = "󰠮 ", color = "purple" } },
      },
    },
  },
}
