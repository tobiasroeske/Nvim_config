-- TaskNotes (Obsidian plugin) in Neovim: task views, quick edits and new tasks in a Snacks picker.
-- Tasks are the notes in the TaskNotes tasks folder; all edits change their frontmatter in place.
local M = {}

local vault ---@type string
local S ---@type table settings read from the TaskNotes plugin
local zed = false -- started by a Zed task: tasks open in Zed, nvim quits when done

local function zed_quit()
  if zed then
    vim.cmd("silent! wall")
    -- Deferred so closing pickers and inputs finish before nvim exits
    vim.defer_fn(function()
      vim.cmd("qa")
    end, 100)
  end
end

-- Dates -----------------------------------------------------------------------

local weekday_names = { "So", "Mo", "Di", "Mi", "Do", "Fr", "Sa" }

---@param s string|? date or datetime string
---@return string|? YYYY-MM-DD part
local function date_of(s)
  return type(s) == "string" and s:match("^%d%d%d%d%-%d%d%-%d%d") or nil
end

---@return integer|? noon of the given YYYY-MM-DD as epoch seconds
local function to_time(date)
  local y, m, d = (date or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
  if y then
    return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
  end
end

local function fmt_date(t)
  return os.date("%Y-%m-%d", t) --[[@as string]]
end

local function today()
  return os.date("%Y-%m-%d") --[[@as string]]
end

local function add_days(date, n)
  local t = os.date("*t", to_time(date)) --[[@as osdate]]
  t.day = t.day + n
  return fmt_date(os.time(t))
end

local function add_months(date, n)
  local t = os.date("*t", to_time(date)) --[[@as osdate]]
  t.month = t.month + n
  return fmt_date(os.time(t))
end

local function days_between(a, b)
  return math.floor((to_time(b) - to_time(a)) / 86400 + 0.5)
end

-- Local time like TaskNotes writes it: 2026-11-14T09:21:01.756+01:00
local function timestamp()
  local sec, usec = vim.uv.gettimeofday()
  local z = os.date("%z", sec) --[[@as string]]
  return os.date("%Y-%m-%dT%H:%M:%S", sec)
    .. (".%03d"):format(math.floor(usec / 1000))
    .. z:sub(1, 3)
    .. ":"
    .. z:sub(4)
end

-- Short label for a date: heute, morgen, gestern, otherwise "Mo 16.11." (with year if not this year)
local function date_label(date)
  local diff = days_between(today(), date)
  if diff == 0 then
    return "heute"
  elseif diff == 1 then
    return "morgen"
  elseif diff == -1 then
    return "gestern"
  end
  local t = os.date("*t", to_time(date)) --[[@as osdate]]
  local label = ("%s %02d.%02d."):format(weekday_names[t.wday], t.day, t.month)
  if t.year ~= os.date("*t").year then
    label = label .. t.year
  end
  return label
end

-- Date input: heute/h, morgen/m, übermorgen, +3 / +2w / +1m, weekday (mo..so, next one after today),
-- 24.12. / 24.12.2027, YYYY-MM-DD; empty removes the date
---@return string|false|? date, false to remove, nil if invalid
local function parse_date_input(input)
  local s = vim.trim(input):lower()
  local base = today()
  if s == "" then
    return false
  elseif s == "heute" or s == "h" then
    return base
  elseif s == "morgen" or s == "m" then
    return add_days(base, 1)
  elseif s == "übermorgen" then
    return add_days(base, 2)
  end
  local n, unit = s:match("^%+(%d+)%s*([dtwm]?)$")
  if n then
    n = tonumber(n)
    if unit == "w" then
      return add_days(base, 7 * n)
    elseif unit == "m" then
      return add_months(base, n)
    end
    return add_days(base, n)
  end
  for wday, name in ipairs(weekday_names) do
    if s == name:lower() then
      local t = os.date("*t", to_time(base)) --[[@as osdate]]
      local ahead = (wday - t.wday - 1) % 7 + 1
      return add_days(base, ahead)
    end
  end
  local d, m, y = s:match("^(%d%d?)%.(%d%d?)%.(%d*)$")
  if d then
    local year = tonumber(y) or os.date("*t").year
    local date = ("%04d-%02d-%02d"):format(year, tonumber(m), tonumber(d))
    if y == "" and date < base then
      date = ("%04d-%02d-%02d"):format(year + 1, tonumber(m), tonumber(d))
    end
    return date
  end
  if s:match("^%d%d%d%d%-%d%d%-%d%d$") then
    return s
  end
end

-- Recurrence (RRULE subset used by TaskNotes) ----------------------------------

local rrule_weekdays = { SU = 1, MO = 2, TU = 3, WE = 4, TH = 5, FR = 6, SA = 7 }

local function list_of(v)
  local out = {}
  for x in (v or ""):gmatch("[^,]+") do
    out[#out + 1] = x
  end
  return out
end

local function contains(list, value)
  return vim.tbl_contains(list or {}, value)
end

---@param rule string
---@param fallback_start string|? YYYY-MM-DD used when the rule has no DTSTART
local function parse_rule(rule, fallback_start)
  local y, m, d = rule:match("DTSTART[^:]*:(%d%d%d%d)(%d%d)(%d%d)")
  local start = y and ("%s-%s-%s"):format(y, m, d) or fallback_start
  if not start then
    return nil
  end
  local r = { start = start, interval = 1 }
  for part in rule:gmatch("[^;\n]+") do
    local k, v = part:match("^(%u+)=(.*)$")
    if k == "FREQ" then
      r.freq = v
    elseif k == "INTERVAL" then
      r.interval = tonumber(v) or 1
    elseif k == "COUNT" then
      r.count = tonumber(v)
    elseif k == "UNTIL" then
      local uy, um, ud = v:match("^(%d%d%d%d)(%d%d)(%d%d)")
      r["until"] = uy and ("%s-%s-%s"):format(uy, um, ud)
    elseif k == "BYDAY" then
      r.byday = {}
      for _, item in ipairs(list_of(v)) do
        local n, wd = item:match("^([+-]?%d*)(%u%u)$")
        if wd and rrule_weekdays[wd] then
          table.insert(r.byday, { n = tonumber(n), wd = rrule_weekdays[wd] })
        end
      end
    elseif k == "BYMONTHDAY" then
      r.bymonthday = vim.tbl_map(tonumber, list_of(v))
    elseif k == "BYMONTH" then
      r.bymonth = vim.tbl_map(tonumber, list_of(v))
    end
  end
  return r.freq and r or nil
end

local function days_in_month(year, month)
  return os.date("*t", os.time({ year = year, month = month + 1, day = 0, hour = 12 })).day
end

local function day_number(t)
  return math.floor(os.time({ year = t.year, month = t.month, day = t.day, hour = 12 }) / 86400)
end

-- Day number of the Monday of the week containing `t`
local function week_start(t)
  return day_number(t) - (t.wday + 5) % 7
end

local function byday_matches(r, t)
  for _, b in ipairs(r.byday) do
    if b.wd == t.wday then
      if not b.n then
        return true
      elseif b.n > 0 and math.ceil(t.day / 7) == b.n then
        return true
      elseif b.n < 0 and math.ceil((days_in_month(t.year, t.month) - t.day + 1) / 7) == -b.n then
        return true
      end
    end
  end
  return false
end

local function monthday_matches(r, t)
  local dim = days_in_month(t.year, t.month)
  for _, v in ipairs(r.bymonthday) do
    if v == t.day or (v < 0 and dim + v + 1 == t.day) then
      return true
    end
  end
  return false
end

-- Day within a month: BYMONTHDAY, else BYDAY, else the start day
local function day_in_month_matches(r, t, s)
  if r.bymonthday then
    return monthday_matches(r, t)
  elseif r.byday then
    return byday_matches(r, t)
  end
  return t.day == s.day
end

local function rule_matches(r, t, s)
  if r.bymonth and not contains(r.bymonth, t.month) then
    return false
  end
  if r.freq == "DAILY" then
    return (day_number(t) - day_number(s)) % r.interval == 0 and (not r.byday or byday_matches(r, t))
  elseif r.freq == "WEEKLY" then
    local weeks = (week_start(t) - week_start(s)) / 7
    return weeks % r.interval == 0 and (r.byday and byday_matches(r, t) or t.wday == s.wday)
  elseif r.freq == "MONTHLY" then
    local months = (t.year - s.year) * 12 + t.month - s.month
    return months % r.interval == 0 and day_in_month_matches(r, t, s)
  elseif r.freq == "YEARLY" then
    return (t.year - s.year) % r.interval == 0 and (r.bymonth or t.month == s.month) and day_in_month_matches(r, t, s)
  end
  return false
end

-- First occurrence on or after `from` for which `accept(date)` is true
---@param accept fun(date:string):boolean
local function next_occurrence(r, from, accept)
  local s = os.date("*t", to_time(r.start)) --[[@as osdate]]
  local t = vim.deepcopy(s)
  local count = 0
  for _ = 1, 40000 do
    local date = ("%04d-%02d-%02d"):format(t.year, t.month, t.day)
    if r["until"] and date > r["until"] then
      return nil
    end
    if rule_matches(r, t, s) then
      count = count + 1
      if r.count and count > r.count then
        return nil
      end
      if date >= from and accept(date) then
        return date
      end
    end
    t.day = t.day + 1
    t = os.date("*t", os.time(t)) --[[@as osdate]]
  end
end

-- Frontmatter -----------------------------------------------------------------

local function read_lines(path)
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  return vim.fn.readfile(path)
end

-- An open buffer of the file is edited directly so it never goes stale against the file
local function write_lines(path, lines)
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent! update")
    end)
  else
    vim.fn.writefile(lines, path)
  end
end

local function unquote(v)
  v = vim.trim(v)
  return v:match('^"(.*)"$') or v:match("^'(.*)'$") or v
end

-- Frontmatter as table (scalars as strings, lists as tables) and the line of its closing `---`
---@return table|?, integer|?
local function parse_frontmatter(lines)
  if lines[1] ~= "---" then
    return nil
  end
  local fm, key = {}, nil
  for i = 2, #lines do
    local line = lines[i]
    if line == "---" then
      return fm, i
    end
    local k, v = line:match("^([%w_%-]+):%s*(.-)%s*$")
    if k then
      key = k
      if v == "" or v == "[]" then
        fm[k] = {}
      elseif v:match("^%[.*%]$") and not v:match("^%[%[") then
        fm[k] = vim.tbl_map(unquote, list_of(v:sub(2, -2)))
      else
        fm[k] = unquote(v)
      end
    elseif key and type(fm[key]) == "table" then
      local item = line:match("^%s*%-%s+(.-)%s*$")
      if item then
        table.insert(fm[key], unquote(item))
      end
    end
  end
end

local function render_field(key, value)
  if type(value) ~= "table" then
    return { key .. ": " .. value }
  elseif #value == 0 then
    return { key .. ": []" }
  end
  local out = { key .. ":" }
  for _, v in ipairs(value) do
    out[#out + 1] = "  - " .. v
  end
  return out
end

-- Apply ordered changes { { key, value } } to the frontmatter; value false removes the key.
-- Untouched keys keep their exact formatting, new keys are appended.
local function apply_changes(lines, changes)
  lines = vim.list_slice(lines, 1)
  local _, close = parse_frontmatter(lines)
  if not close then
    return nil
  end
  for _, change in ipairs(changes) do
    local key, value = change[1], change[2]
    local first, last
    for i = 2, close - 1 do
      if lines[i]:match("^" .. vim.pesc(key) .. ":") then
        first, last = i, i
        while last + 1 < close and lines[last + 1]:match("^[%s%-]") do
          last = last + 1
        end
        break
      end
    end
    local new = value == false and {} or render_field(key, value)
    if first then
      for _ = first, last do
        table.remove(lines, first)
      end
      for j, l in ipairs(new) do
        table.insert(lines, first + j - 1, l)
      end
      close = close - (last - first + 1) + #new
    elseif #new > 0 then
      for j, l in ipairs(new) do
        table.insert(lines, close + j - 1, l)
      end
      close = close + #new
    end
  end
  return lines
end

local function update_task(task, changes)
  table.insert(changes, { "dateModified", timestamp() })
  local lines = apply_changes(read_lines(task.path), changes)
  if not lines then
    return vim.notify("Kein Frontmatter in " .. task.title, vim.log.levels.ERROR)
  end
  write_lines(task.path, lines)
end

-- Settings --------------------------------------------------------------------

local function load_settings()
  local path = vault .. "/.obsidian/plugins/tasknotes/data.json"
  local ok, data = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
  end)
  data = ok and type(data) == "table" and data or {}
  local defaults = data.taskCreationDefaults or {}
  local s = {
    folder = data.tasksFolder or "TaskNotes/Tasks",
    tag = data.taskTag or "task",
    default_status = data.defaultTaskStatus or "open",
    default_priority = data.defaultTaskPriority or "normal",
    default_contexts = vim.tbl_map(vim.trim, list_of(defaults.defaultContexts)),
    statuses = vim.deepcopy(data.customStatuses or {
      { value = "open", label = "Open", color = "#808080", order = 0 },
      { value = "in-progress", label = "In progress", color = "#0066cc", order = 1 },
      { value = "done", label = "Done", color = "#00aa00", order = 2, isCompleted = true },
    }),
    priorities = vim.deepcopy(data.customPriorities or {
      { value = "high", label = "High", color = "#ff0000" },
      { value = "normal", label = "Normal", color = "#ffaa00" },
      { value = "low", label = "Low", color = "#00aa00" },
    }),
    status = {},
    priority = {},
  }
  table.sort(s.statuses, function(a, b)
    return (a.order or 0) < (b.order or 0)
  end)
  for i, st in ipairs(s.statuses) do
    st.idx = i
    st.hl = "TaskNotesStatus" .. i
    vim.api.nvim_set_hl(0, st.hl, { fg = st.color })
    s.status[st.value] = st
  end
  for i, p in ipairs(s.priorities) do
    p.hl = "TaskNotesPriority" .. i
    vim.api.nvim_set_hl(0, p.hl, { fg = p.color })
    s.priority[p.value] = p
  end
  table.sort(s.priorities, function(a, b)
    return a.value < b.value
  end)
  local comment = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
  vim.api.nvim_set_hl(0, "TaskNotesDone", { fg = comment.fg, strikethrough = true })
  S = s
end

local function is_completed(status)
  local st = status and S.status[status]
  return st and st.isCompleted or false
end

-- Tasks -----------------------------------------------------------------------

local function str(v)
  return type(v) == "string" and v ~= "" and v or nil
end

local function strings(v)
  if type(v) == "table" then
    return v
  end
  return str(v) and { v } or {}
end

local function has_tag(tags, tag)
  for _, t in ipairs(strings(tags)) do
    if t:gsub("^#", "") == tag then
      return true
    end
  end
  return false
end

-- [[Folder/Note|Alias]] -> Alias / Note
local function link_name(v)
  local inner = v:match("^%[%[(.-)%]%]$")
  if not inner then
    return v
  end
  return inner:match("|(.+)$") or inner:gsub("#.*$", ""):match("([^/]+)$") or inner
end

-- [[Folder/Note#Heading|Alias]] -> Note (the linked file name)
local function link_target(v)
  local inner = v:match("^%[%[(.-)%]%]$") or v
  inner = inner:gsub("|.*$", ""):gsub("#.*$", ""):gsub("%.md$", "")
  return inner:match("([^/]+)$") or inner
end

local function load_tasks()
  local dir = vault .. "/" .. S.folder
  local tasks = {}
  for name, type in vim.fs.dir(dir) do
    if type == "file" and name:match("%.md$") then
      local path = dir .. "/" .. name
      local fm = parse_frontmatter(read_lines(path))
      if fm and has_tag(fm.tags, S.tag) and not has_tag(fm.tags, "archived") then
        tasks[#tasks + 1] = {
          path = path,
          title = str(fm.title) or name:sub(1, -4),
          status = str(fm.status),
          priority = str(fm.priority),
          scheduled = str(fm.scheduled),
          due = str(fm.due),
          contexts = strings(fm.contexts),
          projects = vim.tbl_map(link_name, strings(fm.projects)),
          project_targets = vim.tbl_map(link_target, strings(fm.projects)),
          completed_date = str(fm.completedDate),
          recurrence = str(fm.recurrence),
          recurrence_anchor = str(fm.recurrence_anchor) or "scheduled",
          recurrence_original_date = str(fm.recurrence_original_date),
          complete_instances = strings(fm.complete_instances),
          skipped_instances = strings(fm.skipped_instances),
          date_created = str(fm.dateCreated),
        }
      end
    end
  end
  return tasks
end

-- Complete a recurring task like TaskNotes: the current instance goes to complete_instances,
-- scheduled moves to the next open occurrence (due keeps its offset once it would lie before it)
local function complete_recurring(task)
  local anchor = task.recurrence_anchor
  local instance = anchor == "scheduled" and (date_of(task.recurrence_original_date) or date_of(task.scheduled))
    or today()
  local rule = task.recurrence
  if anchor == "completion" then
    local start = "DTSTART:" .. instance:gsub("%-", "")
    rule = rule:find("DTSTART[^:]*:%d+") and rule:gsub("DTSTART[^:]*:%d%d%d%d%d%d%d%d", start, 1)
      or (start .. ";" .. rule)
  end
  local r = parse_rule(rule, date_of(task.scheduled) or date_of(task.date_created))
  if not r then
    return vim.notify("Wiederholung nicht lesbar: " .. task.recurrence, vim.log.levels.ERROR)
  end

  local complete = vim.list_slice(task.complete_instances, 1)
  if not contains(complete, instance) then
    complete[#complete + 1] = instance
  end
  local skipped = vim.tbl_filter(function(d)
    return d ~= instance
  end, task.skipped_instances)

  local from = math.max(to_time(instance), to_time(today()))
  local next_date = next_occurrence(r, fmt_date(from), function(date)
    if anchor == "completion" then
      return date > instance and not contains(skipped, date)
    end
    return not contains(complete, date) and not contains(skipped, date)
  end)

  local changes = {
    { "complete_instances", complete },
    { "skipped_instances", skipped },
    { "recurrence_original_date", false },
  }
  if rule ~= task.recurrence then
    table.insert(changes, { "recurrence", rule })
  end
  if next_date then
    local time = task.scheduled and task.scheduled:match("^%d%d%d%d%-%d%d%-%d%d(T.*)$") or ""
    table.insert(changes, { "scheduled", next_date .. time })
    local scheduled, due = date_of(task.scheduled), date_of(task.due)
    if scheduled and due and due < next_date then
      local due_time = task.due:match("^%d%d%d%d%-%d%d%-%d%d(T.*)$") or ""
      table.insert(changes, { "due", add_days(next_date, days_between(scheduled, due)) .. due_time })
    end
  end
  update_task(task, changes)
end

local function set_status(task, status)
  local changes = { { "status", status } }
  if is_completed(status) then
    table.insert(changes, { "completedDate", today() })
  else
    table.insert(changes, { "completedDate", false })
  end
  update_task(task, changes)
end

-- Complete an open task; a completed one is reopened with the default status
local function complete_task(task)
  if is_completed(task.status) then
    return set_status(task, S.default_status)
  end
  if task.recurrence then
    return complete_recurring(task)
  end
  local done = vim.iter(S.statuses):find(function(st)
    return st.isCompleted
  end)
  if done then
    set_status(task, done.value)
  end
end

-- Keep the time part of the previous value when only a date is given
local function set_date(task, field, date)
  if date then
    local time = task[field] and task[field]:match("^%d%d%d%d%-%d%d%-%d%d(T.*)$") or ""
    date = date .. time
  end
  update_task(task, { { field, date } })
end

local function sanitize_filename(title)
  return vim.trim((title:gsub('[\\/:*?"<>|#%^%[%]]', ""):gsub("%s+", " ")))
end

---@param defaults { status?: string, scheduled?: string, project?: string, body?: string[] }
local function create_task(title, defaults)
  local name = sanitize_filename(title)
  if name == "" then
    return nil
  end
  local dir = vault .. "/" .. S.folder
  vim.fn.mkdir(dir, "p")
  local path, i = dir .. "/" .. name .. ".md", 2
  while vim.uv.fs_stat(path) do
    path, i = ("%s/%s-%d.md"):format(dir, name, i), i + 1
  end
  local ts = timestamp()
  local lines = { "---", "status: " .. (defaults.status or S.default_status), "priority: " .. S.default_priority }
  if defaults.scheduled then
    lines[#lines + 1] = "scheduled: " .. defaults.scheduled
  end
  if #S.default_contexts > 0 then
    vim.list_extend(lines, render_field("contexts", S.default_contexts))
  end
  if defaults.project then
    vim.list_extend(lines, render_field("projects", { ('"[[%s]]"'):format(defaults.project) }))
  end
  vim.list_extend(lines, { "dateCreated: " .. ts, "dateModified: " .. ts, "tags:", "  - " .. S.tag, "---" })
  vim.list_extend(lines, defaults.body or { "" })
  vim.fn.writefile(lines, path)
  return path
end

-- Views -----------------------------------------------------------------------

local function on_or_before(value, date)
  local d = date_of(value)
  return d ~= nil and d <= date
end

local function on(value, date)
  return date_of(value) == date
end

-- Mirrors the views in TaskNotes/Views/heute.base and the status columns of the board
local global_views = {
  {
    name = "Heute",
    filter = function(t)
      return on_or_before(t.scheduled, today()) or on_or_before(t.due, today())
    end,
    by_priority = true,
    new = function()
      return { scheduled = today() }
    end,
  },
  {
    name = "Morgen",
    filter = function(t)
      local tomorrow = add_days(today(), 1)
      return on(t.scheduled, tomorrow) or on(t.due, tomorrow)
    end,
    by_priority = true,
    new = function()
      return { scheduled = add_days(today(), 1) }
    end,
  },
  {
    name = "Diese Woche",
    filter = function(t)
      return t.status == "2-woche"
    end,
    new = function()
      return { status = "2-woche" }
    end,
  },
  {
    name = "Eingang",
    filter = function(t)
      return t.status == nil or t.status == S.default_status
    end,
  },
  { name = "Alle offenen" },
}

-- Mirrors Templates/Bases/Projektaufgaben.base: tasks whose projects link to the note
local function project_views(project)
  local function in_project(t)
    return contains(t.project_targets, project)
  end
  local function new()
    return { project = project }
  end
  return {
    { name = "Offen", filter = in_project, new = new },
    { name = "Erledigt", filter = in_project, done = true, new = new },
  }
end

local function earliest_date(t)
  local s, d = date_of(t.scheduled), date_of(t.due)
  if s and d then
    return s < d and s or d
  end
  return s or d or "9999"
end

local function sort_tasks(tasks, view)
  table.sort(tasks, function(a, b)
    local ka, kb
    local pa, pb = a.priority or "~", b.priority or "~"
    if view.done then
      ka = { b.completed_date or "", a.title:lower() }
      kb = { a.completed_date or "", b.title:lower() }
    elseif view.by_priority then
      ka = { pa, date_of(a.scheduled) or "9999", a.title:lower() }
      kb = { pb, date_of(b.scheduled) or "9999", b.title:lower() }
    else
      local sa, sb = S.status[a.status or ""], S.status[b.status or ""]
      ka = { ("%03d"):format(sa and sa.idx or 999), pa, earliest_date(a), a.title:lower() }
      kb = { ("%03d"):format(sb and sb.idx or 999), pb, earliest_date(b), b.title:lower() }
    end
    for i = 1, #ka do
      if ka[i] ~= kb[i] then
        return ka[i] < kb[i]
      end
    end
    return false
  end)
end

-- Picker ----------------------------------------------------------------------

local function format_item(item, picker)
  local t = item.task
  local project = picker.opts.tasknotes_project
  local ret = {}
  local st = t.status and S.status[t.status]
  local toggled = picker.opts.tasknotes_toggled[t.path]
  local checked = toggled and toggled.checked
  if checked == nil then
    checked = is_completed(t.status)
  end
  ret[#ret + 1] = { checked and "󰄵 " or "󰄱 ", checked and "DiagnosticOk" or (st and st.hl or "Comment") }
  local p = t.priority and S.priority[t.priority]
  local weight = p and p.weight or 0
  ret[#ret + 1] = { weight >= 1 and weight <= 3 and "󰈻 " or "  ", p and p.hl or "Comment" }
  ret[#ret + 1] = { t.title, toggled and checked and "TaskNotesDone" or "SnacksPickerFile" }
  local now = today()
  local function add_date(icon, value, is_due)
    local d = date_of(value)
    if not d then
      return
    end
    local hl = (d < now and "DiagnosticError") or (d == now and "DiagnosticWarn") or (is_due and "Special" or "Comment")
    ret[#ret + 1] = { "  " .. icon .. " " .. date_label(d), hl }
  end
  add_date("󰃭", t.scheduled)
  add_date("󰅐", t.due, true)
  if t.recurrence then
    ret[#ret + 1] = { "  󰑖", "Comment" }
  end
  for _, c in ipairs(t.contexts) do
    ret[#ret + 1] = { "  @" .. c, "Identifier" }
  end
  for i, pr in ipairs(t.projects) do
    if t.project_targets[i] ~= project then
      ret[#ret + 1] = { "  +" .. pr, "Directory" }
    end
  end
  if t.completed_date and is_completed(t.status) then
    ret[#ret + 1] = { "  󰄬 " .. date_label(t.completed_date), "Comment" }
  end
  if st then
    ret[#ret + 1] = { "  " .. st.label, st.hl }
  end
  return ret
end

local function view_title(opts)
  local names = vim.tbl_map(function(v)
    return v.name
  end, opts.tasknotes_views)
  names[opts.tasknotes_view] = "[" .. names[opts.tasknotes_view] .. "]"
  return (opts.tasknotes_label or "Aufgaben") .. "  " .. table.concat(names, " · ")
end

local function selected_tasks(picker)
  return vim.tbl_map(function(item)
    return item.task
  end, picker:selected({ fallback = true }))
end

-- Re-read tasks and return focus to the picker after an edit or prompt
local function reload(picker)
  vim.schedule(function()
    if picker.closed then
      return
    end
    picker:refresh()
    picker:focus()
  end)
end

local function prompt_date(picker, field, label)
  local tasks = selected_tasks(picker)
  if #tasks == 0 then
    return
  end
  vim.ui.input({
    prompt = label .. " (heute, morgen, +3, +2w, fr, 24.12., leer = entfernen): ",
    default = #tasks == 1 and date_of(tasks[1][field]) or "",
  }, function(input)
    if input ~= nil then
      local date = parse_date_input(input)
      if date == nil then
        vim.notify("Unbekanntes Datum: " .. input, vim.log.levels.WARN)
      else
        for _, t in ipairs(tasks) do
          set_date(t, field, date)
        end
      end
    end
    reload(picker)
  end)
end

local function select_value(picker, prompt, choices, apply)
  local tasks = selected_tasks(picker)
  if #tasks == 0 then
    return
  end
  vim.ui.select(choices, {
    prompt = prompt,
    format_item = function(c)
      return c.label
    end,
  }, function(choice)
    if choice then
      for _, t in ipairs(tasks) do
        apply(t, choice.value)
      end
    end
    reload(picker)
  end)
end

local actions = {
  -- Toggle the checkbox; tasks toggled in this picker stay in their view,
  -- toggling them again restores the file as it was before
  task_done = function(picker)
    local toggled = picker.opts.tasknotes_toggled
    for _, t in ipairs(selected_tasks(picker)) do
      local prev = toggled[t.path]
      if prev then
        write_lines(t.path, apply_changes(prev.lines, { { "dateModified", timestamp() } }))
        toggled[t.path] = nil
      else
        toggled[t.path] = {
          lines = read_lines(t.path),
          checked = not is_completed(t.status),
          view = picker.opts.tasknotes_view,
        }
        complete_task(t)
      end
    end
    reload(picker)
  end,
  task_status = function(picker)
    select_value(picker, "Status", S.statuses, set_status)
  end,
  task_priority = function(picker)
    select_value(picker, "Priorität", S.priorities, function(t, value)
      update_task(t, { { "priority", value } })
    end)
  end,
  task_scheduled = function(picker)
    prompt_date(picker, "scheduled", "Termin")
  end,
  task_due = function(picker)
    prompt_date(picker, "due", "Fällig")
  end,
  task_new = function(picker)
    local view = picker.opts.tasknotes_views[picker.opts.tasknotes_view]
    vim.ui.input({ prompt = "Neue Aufgabe (" .. view.name .. "): " }, function(title)
      if title and vim.trim(title) ~= "" then
        create_task(title, view.new and view.new() or {})
      end
      reload(picker)
    end)
  end,
  task_view_next = function(picker)
    picker:action("task_view_" .. (picker.opts.tasknotes_view % #picker.opts.tasknotes_views + 1))
  end,
}
for i in ipairs(global_views) do
  actions["task_view_" .. i] = function(picker)
    if picker.opts.tasknotes_views[i] then
      picker.opts.tasknotes_view = i
      picker.title = view_title(picker.opts)
      picker:refresh()
    end
  end
end

-- Actions with their key in the list (plain letter) and in the search input (Alt + letter).
-- Alt n/f are left out because WezTerm uses them.
local key_actions = {
  { "x", "task_done", "Erledigt / wieder öffnen" },
  { "s", "task_status", "Status" },
  { "p", "task_priority", "Priorität" },
  { "t", "task_scheduled", "Termin (scheduled)" },
  { "d", "task_due", "Fällig (due)" },
  { "a", "task_new", "Neue Aufgabe" },
  { "v", "task_view_next", "Nächste Ansicht" },
}
for i in ipairs(global_views) do
  table.insert(key_actions, { tostring(i), "task_view_" .. i, "Ansicht " .. i })
end

local list_keys, input_keys = {}, {}
for _, k in ipairs(key_actions) do
  list_keys[k[1]] = { k[2], desc = k[3] }
  input_keys["<a-" .. k[1] .. ">"] = { k[2], mode = { "n", "i" }, desc = k[3] }
end

---@param opts { vault: string, zed?: boolean }
function M.setup(opts)
  vault = opts.vault
  zed = opts.zed or false
end

-- Open a task in Zed; falls back to nvim when the zed CLI is missing
local function open_in_zed(picker, item)
  if not item then
    return picker:close()
  end
  local ok = pcall(function()
    vim.system({ "zed", item.file }):wait(5000)
  end)
  if ok then
    return picker:close()
  end
  picker:action("jump")
end

---@param views table[]
---@param view integer
---@param label? string
---@param project? string note name whose tasks are shown
local function open_picker(views, view, label, project)
  load_settings()
  local opts = {
    tasknotes_views = views,
    tasknotes_view = view,
    tasknotes_label = label,
    tasknotes_project = project,
    tasknotes_toggled = {},
  }
  Snacks.picker(vim.tbl_extend("force", opts, {
    title = view_title(opts),
    finder = function(picker_opts)
      local v = picker_opts.tasknotes_views[picker_opts.tasknotes_view]
      local toggled = picker_opts.tasknotes_toggled
      local tasks = vim.tbl_filter(function(t)
        local prev = toggled[t.path]
        if prev and prev.view == picker_opts.tasknotes_view then
          return true
        end
        return is_completed(t.status) == (v.done or false) and (not v.filter or v.filter(t))
      end, load_tasks())
      sort_tasks(tasks, v)
      return vim.tbl_map(function(t)
        local st = t.status and S.status[t.status]
        return {
          task = t,
          file = t.path,
          text = table.concat(
            { t.title, table.concat(t.contexts, " "), table.concat(t.projects, " "), st and st.label or "" },
            " "
          ),
        }
      end, tasks)
    end,
    format = format_item,
    preview = "file",
    sort = { fields = { "score:desc", "idx" } },
    show_empty = true,
    actions = actions,
    focus = "list",
    win = { input = { keys = input_keys }, list = { keys = list_keys } },
    confirm = zed and open_in_zed or nil,
    on_close = zed and zed_quit or nil,
  }))
end

---@param view? integer index into the views (1 = Heute, 2 = Morgen, ...)
function M.open(view)
  open_picker(global_views, view or 1)
end

-- Note name of the current buffer (in Zed: the file open there) when it is a vault note tagged as project
local function current_project()
  local path = zed and (vim.env.ZED_FILE or "") or vim.api.nvim_buf_get_name(0)
  if path == "" or not path:match("%.md$") then
    return nil
  end
  local lines = zed and read_lines(path) or vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local fm = parse_frontmatter(lines)
  if fm and (has_tag(fm.tags, "projekt") or has_tag(fm.tags, "project")) then
    return vim.fn.fnamemodify(path, ":t:r")
  end
end

-- Tasks of a project: the current project note, otherwise picked from the projects tasks link to
---@param project? string note name
function M.open_project(project)
  project = project or current_project()
  if project then
    return open_picker(project_views(project), 1, "󰉋 " .. project, project)
  end
  load_settings()
  local names = {}
  for _, t in ipairs(load_tasks()) do
    if not is_completed(t.status) then
      for _, name in ipairs(t.project_targets) do
        names[name] = true
      end
    end
  end
  local list = vim.tbl_keys(names)
  table.sort(list)
  vim.ui.select(list, { prompt = "Projekt" }, function(choice)
    if choice then
      open_picker(project_views(choice), 1, "󰉋 " .. choice, choice)
    else
      zed_quit()
    end
  end)
end

-- New task from anywhere, optionally scheduled; `body` becomes the note content
---@param opts? { body?: string[] }
function M.new(opts)
  opts = opts or {}
  load_settings()
  vim.ui.input({ prompt = "Neue Aufgabe: " }, function(title)
    if not title or vim.trim(title) == "" then
      return zed_quit()
    end
    vim.ui.input({ prompt = "Termin (heute, morgen, +3, fr, 24.12., leer = keiner): " }, function(input)
      local date = parse_date_input(input or "")
      local path = create_task(title, { scheduled = date or nil, body = opts.body })
      if path then
        vim.notify("Aufgabe angelegt: " .. vim.fn.fnamemodify(path, ":t:r"))
      end
      zed_quit()
    end)
  end)
end

return M
