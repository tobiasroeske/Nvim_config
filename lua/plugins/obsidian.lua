-- Vault location: $OBSIDIAN_VAULT or ~/Obsidian/Tobis Vault
local vault = vim.fs.normalize(vim.env.OBSIDIAN_VAULT or "~/Obsidian/Tobis Vault")
local has_vault = vim.fn.isdirectory(vault) == 1
local is_windows = vim.fn.has("win32") == 1

-- Vault paths that are not notes (obsidian.nvim ignore_filters and picker excludes)
local ignored = { "_Anleitungen/", "Attachments/", "claude", ".claude" }

-- Vault path and its resolved target (symlink/junction/OneDrive), both lowercased on Windows
local vault_roots = {}
for _, v in ipairs({ vault, has_vault and vim.uv.fs_realpath(vault) or nil }) do
  v = vim.fs.normalize(v)
  vault_roots[#vault_roots + 1] = is_windows and v:lower() or v
end

local function in_vault(path)
  if not has_vault or path == "" then
    return false
  end
  local p = vim.fs.normalize(path)
  p = is_windows and p:lower() or p
  for _, v in ipairs(vault_roots) do
    if vim.startswith(p, v .. "/") then
      return true
    end
  end
  return false
end

---@param title string|?
---@return string
local function timestamp_id(title)
  local prefix = os.date("%Y-%m-%d %H%M") --[[@as string]]
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
-- An open buffer of the neighbor is edited directly so it never goes stale against the file
local function set_daily_property(neighbor, key, date)
  local path = vault .. "/Daily/" .. neighbor .. ".md"
  local buf = vim.fn.bufnr(path)
  local loaded = buf ~= -1 and vim.api.nvim_buf_is_loaded(buf)
  local lines = loaded and vim.api.nvim_buf_get_lines(buf, 0, -1, false) or vim.fn.readfile(path)
  for i, line in ipairs(lines) do
    if i > 1 and line == "---" then
      break
    end
    if line:match("^" .. key .. ":") then
      local new = string.format('%s: "[[%s]]"', key, date)
      if loaded then
        vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { new })
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("silent! update")
        end)
      else
        lines[i] = new
        vim.fn.writefile(lines, path)
      end
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

-- Directories inside an Obsidian vault (any folder with a `.obsidian` folder above it)
local vault_dirs = {}
local function is_vault_dir(path)
  if path == "" then
    return false
  end
  if vault_dirs[path] == nil then
    vault_dirs[path] = vim.fs.root(path, ".obsidian") ~= nil
  end
  return vault_dirs[path]
end

-- Snacks explorer inside a vault, like Obsidian's "Created time (new to old)":
-- folders on top (A-Z, case-insensitive), then notes by creation date (newest first),
-- dot entries (.obsidian, .trash, ...) hidden
local function patch_explorer_sort()
  local tree = require("snacks.explorer.tree")
  if rawget(tree, "walk") then
    return
  end
  local default_walk = getmetatable(tree).walk

  function tree:walk(node, fn, opts)
    if not is_vault_dir(node.path) then
      return default_walk(self, node, fn, opts)
    end
    local abort = fn(node)
    if abort ~= nil then
      return abort
    end
    local children = vim.tbl_filter(function(child)
      return child.name:sub(1, 1) ~= "."
    end, vim.tbl_values(node.children))
    table.sort(children, function(a, b)
      if a.dir ~= b.dir then
        return a.dir
      end
      if a.dir then
        return a.name:lower() < b.name:lower()
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

-- Templates -----------------------------------------------------------------

-- Split lines into frontmatter (without the `---` fences) and body
local function split_frontmatter(lines)
  if lines[1] == "---" then
    for i = 2, #lines do
      if lines[i] == "---" then
        return vim.list_slice(lines, 2, i - 1), vim.list_slice(lines, i + 1)
      end
    end
  end
  return nil, lines
end

-- Frontmatter as ordered key blocks: { key = "tags", lines = { "tags:", "  - a" } }
local function parse_frontmatter(fm)
  local blocks, by_key = {}, {}
  for _, line in ipairs(fm or {}) do
    local key = line:match("^([^%s#%-][^:]*):")
    if key then
      local block = { key = key, lines = { line } }
      table.insert(blocks, block)
      by_key[key] = block
    elseif #blocks > 0 then
      table.insert(blocks[#blocks].lines, line)
    else
      table.insert(blocks, { lines = { line } })
    end
  end
  return blocks, by_key
end

local function list_items(block)
  return vim.tbl_filter(function(line)
    return line:match("^%s*%- ") ~= nil
  end, vim.list_slice(block.lines, 2))
end

-- Text-level merge that keeps the existing formatting:
-- new keys are appended, list items (tags, aliases, ...) are unioned, existing scalar values win
local function merge_frontmatter(target, extra)
  local blocks, by_key = parse_frontmatter(target)
  for _, add in ipairs((parse_frontmatter(extra))) do
    local cur = add.key and by_key[add.key]
    if add.key and not cur then
      table.insert(blocks, add)
      by_key[add.key] = add
    elseif cur then
      local items = list_items(add)
      if #items > 0 and cur.lines[1]:match(":%s*%[%s*%]%s*$") then
        cur.lines[1] = cur.key .. ":"
      end
      if #items > 0 and cur.lines[1]:match(":%s*$") then
        local have = {}
        for _, l in ipairs(list_items(cur)) do
          have[vim.trim(l)] = true
        end
        for _, l in ipairs(items) do
          if not have[vim.trim(l)] then
            table.insert(cur.lines, l)
          end
        end
      end
    end
  end
  local out = {}
  for _, b in ipairs(blocks) do
    vim.list_extend(out, b.lines)
  end
  return out
end

-- Template contents with obsidian.nvim substitutions applied ({{date}}, {{title}}, custom ones, prompts)
local function render_template(name, buf)
  local templates = require("obsidian.templates")
  local dir = require("obsidian.api").templates_dir()
  local path = templates.resolve_template(name, dir)
  local win = vim.fn.bufwinid(buf)
  local cursor = win ~= -1 and vim.api.nvim_win_get_cursor(win) or { 1, 0 }
  local text = table.concat(
    vim.tbl_map(function(l)
      return (l:gsub("\r$", ""))
    end, vim.fn.readfile(tostring(path))),
    "\n"
  )
  text = templates.substitute_template_variables(text, {
    type = "insert_template",
    template_name = name,
    templates_dir = dir,
    location = { buf, win, cursor[1], cursor[2] },
    partial_note = require("obsidian.note").from_buffer(buf),
  })
  return vim.split(text, "\n", { plain = true })
end

-- Apply templates to `buf`: frontmatter is merged, bodies go below `row` (nil = end of note)
local function apply_templates(buf, names, row)
  local fm, body = split_frontmatter(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  local fm_len = fm and #fm + 2 or 0
  local at = row and math.min(math.max(row - fm_len, 0), #body) or #body
  local inserted = {}
  for _, name in ipairs(names) do
    local t_fm, t_body = split_frontmatter(render_template(name, buf))
    if t_fm then
      fm = merge_frontmatter(fm or {}, t_fm)
    end
    local has_body = vim.iter(t_body):any(function(l)
      return vim.trim(l) ~= ""
    end)
    if has_body then
      if t_body[1] ~= "" then
        table.insert(inserted, "")
      end
      vim.list_extend(inserted, t_body)
    end
  end
  local out = fm and vim.list_extend({ "---" }, fm) or {}
  if fm then
    table.insert(out, "---")
  end
  vim.list_extend(out, vim.list_slice(body, 1, at))
  vim.list_extend(out, inserted)
  vim.list_extend(out, vim.list_slice(body, at + 1))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
end

-- Template picker, <Tab> selects several (applied in selection order)
local function pick_templates(title, callback)
  local dir = require("obsidian.api").templates_dir()
  if not dir then
    return vim.notify("Kein Templates-Ordner gefunden", vim.log.levels.ERROR)
  end
  Snacks.picker.files({
    title = title,
    cwd = tostring(dir),
    ft = "md",
    confirm = function(picker)
      local paths = vim.tbl_map(Snacks.picker.util.path, picker:selected({ fallback = true }))
      picker:close()
      if #paths > 0 then
        vim.schedule(function()
          callback(paths)
        end)
      end
    end,
  })
end

-- New note from one or more templates; the first one decides filename and location
local function new_from_templates()
  pick_templates("Neue Notiz aus Template(s)", function(paths)
    vim.ui.input({ prompt = "Titel (optional): " }, function(title)
      if title == nil then
        return
      end
      require("obsidian.actions").new_from_template(title, paths[1], function(note)
        note:open({ sync = true })
        if #paths > 1 then
          apply_templates(vim.api.nvim_get_current_buf(), vim.list_slice(paths, 2))
          vim.cmd("silent! update")
        end
      end)
    end)
  end)
end

-- Insert one or more templates below the cursor of the current note
local function insert_templates()
  local buf = vim.api.nvim_get_current_buf()
  if not in_vault(vim.api.nvim_buf_get_name(buf)) then
    return vim.notify("Aktueller Buffer ist keine Vault-Notiz", vim.log.levels.WARN)
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  pick_templates("Template(s) einfügen", function(paths)
    apply_templates(buf, paths, row)
  end)
end

-- Quick capture ---------------------------------------------------------------

-- Visual selection as fenced code block with its source location (markdown stays plain text)
local function selection_snippet()
  local mode = vim.fn.mode()
  if not mode:match("[vV\22]") then
    return nil
  end
  local s, e = vim.fn.getpos("v"), vim.fn.getpos(".")
  local lines = vim.fn.getregion(s, e, { type = mode })
  local first, last = math.min(s[2], e[2]), math.max(s[2], e[2])
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  if vim.bo.filetype == "markdown" then
    return vim.list_extend({ "" }, lines)
  end
  local file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":~:.")
  local loc = first == last and ("%s:%d"):format(file, first) or ("%s:%d-%d"):format(file, first, last)
  local out = { "", "`" .. loc .. "`", "```" .. vim.bo.filetype }
  vim.list_extend(out, lines)
  table.insert(out, "```")
  return out
end

local function open_float(path, title, on_close)
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  vim.bo[buf].buflisted = true
  return Snacks.win({
    buf = buf,
    ft = "markdown",
    position = "float",
    width = 0.6,
    height = 0.6,
    border = "rounded",
    title = " 󰠮 " .. (title or vim.fn.fnamemodify(path, ":t:r")) .. " ",
    footer_keys = { "q", "<A-o>" },
    enter = true,
    wo = { wrap = true, linebreak = true },
    keys = {
      expand = {
        "<A-o>",
        function(self)
          self:close()
          vim.cmd.edit(vim.fn.fnameescape(path))
        end,
        desc = "Als Buffer öffnen",
      },
    },
    on_close = function(self)
      if on_close then
        on_close(self)
      end
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("silent! update")
        end)
      end
    end,
  })
end

-- Active quick note: stays active (also across restarts) until it is finished
local quick = {
  state = vim.fn.stdpath("state") .. "/obsidian-quicknote",
  path = nil, ---@type string?
  win = nil, ---@type snacks.win?
  cursor = nil, ---@type integer[]?
}
quick.path = vim.uv.fs_stat(quick.state) and vim.fn.readfile(quick.state)[1] or nil

local function quick_active()
  if quick.path and not vim.uv.fs_stat(quick.path) then
    quick.path, quick.cursor = nil, nil
    os.remove(quick.state)
  end
  return quick.path
end

local function quick_show(snippet)
  if not (quick.win and quick.win:valid()) then
    local name = vim.fn.fnamemodify(quick.path, ":t:r")
    local origin = vim.api.nvim_get_current_win()
    quick.win = open_float(quick.path, "Quick Note: " .. name, function(self)
      quick.cursor = vim.api.nvim_win_get_cursor(self.win)
      if vim.api.nvim_get_current_win() == self.win and vim.api.nvim_win_is_valid(origin) then
        vim.api.nvim_set_current_win(origin)
      end
    end)
  end
  quick.win:focus()
  local buf = quick.win.buf --[[@as integer]]
  local win = quick.win.win --[[@as integer]]
  if snippet then
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, snippet)
    vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
  elseif quick.cursor then
    pcall(vim.api.nvim_win_set_cursor, win, quick.cursor)
  else
    vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
  end
end

-- Toggle the active quick note in a floating window (works from any buffer), new one if none is active
-- In visual mode the selection is appended as code block with file:line reference
local function quick_note()
  local snippet = selection_snippet()
  if not snippet and quick.win and quick.win:valid() then
    if vim.api.nvim_get_current_win() == quick.win.win then
      quick.win:hide()
    else
      quick.win:focus()
    end
    return
  end
  if quick_active() then
    return quick_show(snippet)
  end
  vim.ui.input({ prompt = "Neue Quick Note – Titel (optional): " }, function(title)
    if title == nil then
      return
    end
    local note = require("obsidian.note").create({ id = title, template = Obsidian.opts.note.template })
    note:write()
    quick.path, quick.cursor = tostring(note.path), nil
    vim.fn.writefile({ quick.path }, quick.state)
    quick_show(snippet)
  end)
end

-- Finish the active quick note; the next <leader>Oq starts a new one
local function quick_finish()
  if not quick_active() then
    return vim.notify("Keine aktive Quick Note", vim.log.levels.WARN)
  end
  if quick.win and quick.win:valid() then
    quick.win:close()
  end
  local name = vim.fn.fnamemodify(quick.path, ":t:r")
  quick.path, quick.cursor, quick.win = nil, nil, nil
  os.remove(quick.state)
  vim.notify("Quick Note abgeschlossen: " .. name)
end

-- Append lines to a note; an open buffer of it is edited directly
local function append_to_note_file(path, lines)
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent! update")
    end)
  else
    vim.fn.writefile(vim.list_extend(vim.fn.readfile(path), lines), path)
  end
end

-- Append the visual selection to the end of an existing note, picked from the vault
local function append_selection()
  local snippet = selection_snippet()
  if not snippet then
    return
  end
  local exclude = { "Templates", ".obsidian" }
  for _, f in ipairs(ignored) do
    exclude[#exclude + 1] = (f:gsub("/$", ""))
  end
  Snacks.picker.files({
    title = "An Notiz anhängen",
    cwd = vault,
    ft = "md",
    exclude = exclude,
    confirm = function(picker, item)
      picker:close()
      if not item then
        return
      end
      local path = Snacks.picker.util.path(item)
      if not path then
        return
      end
      append_to_note_file(path, snippet)
      vim.notify("Angehängt an " .. vim.fn.fnamemodify(path, ":t:r"))
    end,
  })
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
    end,
    keys = {
      { "<leader>Oj", new_journal_entry, desc = "New Journal Entry" },
      { "<leader>Oq", quick_note, mode = { "n", "x" }, desc = "Quick Note (Toggle)" },
      { "<leader>OQ", quick_finish, desc = "Quick Note abschliessen" },
      { "<leader>On", new_from_templates, desc = "New Note from Template(s)" },
      { "<leader>OT", insert_templates, desc = "Insert Template(s)" },
      { "<leader>Or", "<cmd>Obsidian rename<cr>", desc = "Rename Note" },
      { "<leader>Oe", append_selection, mode = "x", desc = "Append Selection to Note" },
      { "<leader>Oc", "<cmd>Obsidian toc<cr>", desc = "Table of Contents" },
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
        date_format = "YYYY-MM-DD",
        time_format = "HH:mm",
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
        ignore_filters = ignored,
      },
      picker = { name = "snacks.picker" },
    },
  },
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = {
      -- Render checkboxes, including the Obsidian task states
      checkbox = {
        enabled = true,
        custom = {
          todo = { raw = "[-]", rendered = "󰥔 ", highlight = "RenderMarkdownTodo" },
          forward = { raw = "[>]", rendered = " ", highlight = "RenderMarkdownInfo" },
          cancelled = { raw = "[~]", rendered = "󰰱 ", highlight = "RenderMarkdownError" },
          important = { raw = "[!]", rendered = " ", highlight = "RenderMarkdownWarn" },
        },
      },
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
    "folke/snacks.nvim",
    opts = function()
      patch_explorer_sort()
    end,
  },
  {
    "nvim-lualine/lualine.nvim",
    optional = true,
    opts = function(_, opts)
      table.insert(opts.sections.lualine_x, 1, {
        function()
          return "󰠮 " .. vim.fn.fnamemodify(quick.path, ":t:r")
        end,
        cond = function()
          return quick.path ~= nil
        end,
        color = function()
          return { fg = Snacks.util.color("Special") }
        end,
      })
    end,
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
