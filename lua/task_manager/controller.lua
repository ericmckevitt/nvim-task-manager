local config = require("task_manager.config")
local model = require("task_manager.model")
local store = require("task_manager.store")
local view = require("task_manager.view")

local M = {}
local DEFAULT_LIST_ID = "default"

local state = {
  data = { tasks = {}, lists = {} },
  current_view = "current",
  current_list_id = DEFAULT_LIST_ID,
  buf = nil,
  win = nil,
  line_to_id = {},
  search_query = nil,
  selected_task_ids = {},
  pending_focus_task_id = nil,
  deadline_week_offset = 0,
}

local function notify_error(msg)
  vim.notify(msg, vim.log.levels.ERROR)
end

local function load_data()
  state.data = store.load(config.options.file_path)
  state.data.tasks = state.data.tasks or {}
  state.data.lists = state.data.lists or {}
end

local function save_data()
  return store.save(config.options.file_path, state.data)
end

local function ensure_dir(path)
  if vim.fn.isdirectory(path) == 0 then
    vim.fn.mkdir(path, "p")
  end
end

local function task_note_path(task)
  if type(task.note_path) == "string" and task.note_path ~= "" then
    return task.note_path
  end
  return config.options.notes_dir .. "/" .. task.id .. ".md"
end

local function note_exists_and_nonempty(task)
  local path = task_note_path(task)
  if vim.fn.filereadable(path) ~= 1 then
    return false
  end
  return vim.fn.getfsize(path) > 0
end

local function current_task_id()
  local cursor = vim.api.nvim_win_get_cursor(0)
  return state.line_to_id[cursor[1]]
end

local function selected_count()
  local count = 0
  for _ in pairs(state.selected_task_ids) do
    count = count + 1
  end
  return count
end

local function selected_ids_list()
  local out = {}
  for id in pairs(state.selected_task_ids) do
    table.insert(out, id)
  end
  return out
end

local function target_task_ids()
  local ids = selected_ids_list()
  if #ids > 0 then
    return ids
  end
  local focused = current_task_id()
  if focused then
    return { focused }
  end
  return {}
end

local function has_bulk_selection()
  return selected_count() > 0
end

local function clear_selection_state()
  state.selected_task_ids = {}
end

local function prune_selection()
  local valid = {}
  for _, task in ipairs(state.data.tasks) do
    valid[task.id] = true
  end
  for id in pairs(state.selected_task_ids) do
    if not valid[id] then
      state.selected_task_ids[id] = nil
    end
  end
end

local function is_valid_date(value)
  if type(value) ~= "string" then
    return false
  end
  if not value:match("^%d%d%d%d%-%d%d%-%d%d$") then
    return false
  end
  local y, m, d = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  local ts = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
  if not ts then
    return false
  end
  return os.date("%Y-%m-%d", ts) == value
end

local function next_priority(value)
  if value == nil then
    return 3
  end
  if value == 3 then
    return 2
  end
  if value == 2 then
    return 1
  end
  return nil
end

local function apply_search_filter(tasks)
  if not state.search_query or state.search_query == "" then
    return tasks
  end

  local q = state.search_query:lower()
  local out = {}
  if q:sub(1, 1) == "#" then
    local needle = q:sub(2)
    for _, task in ipairs(tasks) do
      for _, tag in ipairs(task.tags or {}) do
        if tostring(tag):lower():find(needle, 1, true) then
          table.insert(out, task)
          break
        end
      end
    end
    return out
  end

  for _, task in ipairs(tasks) do
    local title = tostring(task.title or ""):lower()
    if title:find(q, 1, true) then
      table.insert(out, task)
    end
  end
  return out
end

local function list_lookup()
  local out = {}
  for _, list in ipairs(state.data.lists) do
    out[list.id] = list.name
  end
  return out
end

local function list_color_lookup()
  local out = {}
  for _, list in ipairs(state.data.lists) do
    out[list.id] = list.color
  end
  return out
end

local function list_name_by_id(id)
  local list = model.get_list_by_id(state.data.lists, id)
  return list and list.name or id or "unknown"
end

local function normalize_hex_color(value)
  if type(value) ~= "string" then
    return nil
  end
  local trimmed = value:gsub("^%s+", ""):gsub("%s+$", "")
  if trimmed:match("^#%x%x%x%x%x%x$") then
    return trimmed:upper()
  end
  return nil
end

local function current_list_name()
  local list = model.get_list_by_id(state.data.lists, state.current_list_id)
  return list and list.name or state.current_list_id
end

local function get_list_from_key(key)
  local by_id = model.get_list_by_id(state.data.lists, key)
  if by_id then
    return by_id
  end
  return model.get_list_by_name(state.data.lists, key)
end

local function effective_view()
  if state.current_view == "current" then
    return "list:" .. state.current_list_id
  end
  return state.current_view
end

local function is_global_view(view_name)
  return view_name == "all" or view_name == "today" or view_name == "overdue" or view_name == "log" or view_name == "schedule" or view_name:match("^by_tag:") ~= nil
end

local function day_start_ts(ts)
  local d = os.date("*t", ts)
  d.hour = 0
  d.min = 0
  d.sec = 0
  return os.time(d)
end

local function monday_start_ts(week_offset)
  local now = os.time()
  local start = day_start_ts(now)
  local wday = os.date("*t", start).wday
  local days_since_monday = (wday + 5) % 7
  return start - (days_since_monday * 86400) + ((week_offset or 0) * 7 * 86400)
end

local function build_schedule_sections(tasks)
  local start_ts = monday_start_ts(state.deadline_week_offset)
  local day_names = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
  local today = os.date("%Y-%m-%d")
  local by_day = {}

  local function add_for_day(date, task)
    by_day[date] = by_day[date] or { tasks = {}, seen = {} }
    if not by_day[date].seen[task.id] then
      table.insert(by_day[date].tasks, task)
      by_day[date].seen[task.id] = true
    end
  end

  for _, task in ipairs(tasks) do
    if type(task.scheduled) == "string" then
      add_for_day(task.scheduled, task)
    end
    if type(task.due) == "string" then
      add_for_day(task.due, task)
    end
  end

  local sections = {}
  for i = 0, 6 do
    local ts = start_ts + (i * 86400)
    local date = os.date("%Y-%m-%d", ts)
    local items = (by_day[date] and by_day[date].tasks) or {}
    table.sort(items, function(a, b)
      local ap = tonumber(a.priority) or 99
      local bp = tonumber(b.priority) or 99
      if ap ~= bp then
        return ap < bp
      end
      return (a.created_at or "") < (b.created_at or "")
    end)
    table.insert(sections, {
      date = date,
      label = string.format("%s %s%s", day_names[i + 1], date, date == today and " • today" or ""),
      tasks = items,
    })
  end

  local range_text = os.date("%Y-%m-%d", start_ts) .. " .. " .. os.date("%Y-%m-%d", start_ts + (6 * 86400))
  return sections, range_text
end

local function rerender()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local active_view = effective_view()
  local tasks = {}
  local schedule_sections = nil
  local schedule_range_text = nil

  if active_view == "schedule" then
    local date_tasks = {}
    for _, task in ipairs(state.data.tasks) do
      if type(task.due) == "string" or type(task.scheduled) == "string" then
        table.insert(date_tasks, task)
      end
    end
    date_tasks = apply_search_filter(date_tasks)
    schedule_sections, schedule_range_text = build_schedule_sections(date_tasks)
  else
    tasks = model.prepare_view(state.data.tasks, active_view, { current_list_id = state.current_list_id })
    tasks = apply_search_filter(tasks)
  end
  local display_tasks = {}
  for _, task in ipairs(tasks) do
    local item = vim.deepcopy(task)
    item.has_note = note_exists_and_nonempty(task)
    table.insert(display_tasks, item)
  end
  local display_view = active_view
  local global_view = is_global_view(active_view)
  local grouped = global_view and config.options.group_global_views_by_list and active_view ~= "log" and active_view ~= "schedule"
  if active_view:match("^list:") then
    display_view = "list:" .. current_list_name()
  elseif active_view == "schedule" and schedule_range_text then
    display_view = "schedule | " .. schedule_range_text
  end
  if state.search_query and state.search_query ~= "" then
    display_view = display_view .. " | search: " .. state.search_query
  end
  prune_selection()
  local count = selected_count()
  if count > 0 then
    display_view = display_view .. " | selected: " .. tostring(count)
  end
  state.line_to_id = view.render(state.buf, display_tasks, active_view, cursor[1], {
    display_view = display_view,
    show_list = global_view and not grouped,
    group_by_list = grouped,
    deadline_sections = schedule_sections,
    list_lookup = list_lookup(),
    list_colors = list_color_lookup(),
    selected_ids = state.selected_task_ids,
    has_selection = count > 0,
    theme = config.options.theme,
  })

  if state.pending_focus_task_id then
    for line, task_id in pairs(state.line_to_id) do
      if task_id == state.pending_focus_task_id then
        pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
        break
      end
    end
    state.pending_focus_task_id = nil
  end
end

local function setup_buffer_keymaps()
  local km = config.options.keymaps
  local opts = { buffer = state.buf, nowait = true, silent = true }

  vim.keymap.set("n", km.close, function()
    M.close()
  end, opts)
  if km.close_alt and km.close_alt ~= "" then
    vim.keymap.set("n", km.close_alt, function()
      M.close()
    end, opts)
  end
  vim.keymap.set("n", km.refresh, function()
    M.refresh()
  end, opts)
  vim.keymap.set("n", km.add, function()
    M.add_task()
  end, opts)
  vim.keymap.set("n", km.delete, function()
    M.delete_task()
  end, opts)
  vim.keymap.set("n", km.toggle, function()
    M.toggle_task_status()
  end, opts)
  vim.keymap.set("n", km.mark_done, function()
    M.mark_done()
  end, opts)
  vim.keymap.set("n", km.priority_cycle, function()
    M.cycle_priority()
  end, opts)
  vim.keymap.set("n", km.edit, function()
    M.edit_task()
  end, opts)
  vim.keymap.set("n", km.rename, function()
    M.rename_task()
  end, opts)
  vim.keymap.set("n", km.note, function()
    M.open_note()
  end, opts)
  vim.keymap.set("n", km.tag, function()
    M.edit_tags()
  end, opts)
  vim.keymap.set("n", km.move, function()
    M.move_task_to_list()
  end, opts)
  vim.keymap.set("n", km.search, function()
    M.task_search()
  end, opts)
  if km.search_inline and km.search_inline ~= "" then
    vim.keymap.set("n", km.search_inline, function()
      M.search_tasks()
    end, opts)
  end
  if km.week_prev and km.week_prev ~= "" then
    vim.keymap.set("n", km.week_prev, function()
      M.deadlines_prev_week()
    end, opts)
  end
  if km.week_next and km.week_next ~= "" then
    vim.keymap.set("n", km.week_next, function()
      M.deadlines_next_week()
    end, opts)
  end
  if km.week_reset and km.week_reset ~= "" then
    vim.keymap.set("n", km.week_reset, function()
      M.deadlines_reset_week()
    end, opts)
  end
  vim.keymap.set("n", km.set_scheduled, function()
    M.set_scheduled_date()
  end, opts)
  vim.keymap.set("n", km.clear_scheduled, function()
    M.clear_scheduled_date()
  end, opts)
  vim.keymap.set("n", km.set_due, function()
    M.set_due_date()
  end, opts)
  vim.keymap.set("n", km.clear_due, function()
    M.clear_due_date()
  end, opts)
  vim.keymap.set("n", km.select_toggle, function()
    M.toggle_selection()
  end, opts)
  vim.keymap.set("n", km.select_clear, function()
    M.clear_selection()
  end, opts)
  vim.keymap.set("n", km.switch_list, function()
    M.pick_list()
  end, opts)
  if km.switch_list_alt and km.switch_list_alt ~= "" then
    vim.keymap.set("n", km.switch_list_alt, function()
      M.pick_list()
    end, opts)
  end
end

local function open_main_buffer()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_set_current_win(state.win)
      return
    end
  else
    state.buf = view.create_list_buffer()
    setup_buffer_keymaps()
  end

  if config.options.use_floating_window then
    state.win = view.open_floating_window(state.buf, config.options.window)
  else
    view.open_plain_buffer(state.buf)
    state.win = vim.api.nvim_get_current_win()
  end
end

local function parse_task_json(lines)
  local content = table.concat(lines, "\n")
  local ok, decoded = pcall(vim.fn.json_decode, content)
  if not ok or type(decoded) ~= "table" then
    return nil, "Task manager: invalid JSON in edit buffer"
  end
  return decoded, nil
end

local function format_edit_json(task)
  local tags = vim.fn.json_encode(task.tags or {})
  local due = task.due and string.format('"%s"', task.due) or "null"
  local scheduled = task.scheduled and string.format('"%s"', task.scheduled) or "null"

  return {
    "{",
    string.format('  "title": %s,', vim.fn.json_encode(task.title or "")),
    string.format('  "status": %s,', vim.fn.json_encode(task.status or "todo")),
    string.format('  "tags": %s,', tags),
    string.format('  "due": %s,', due),
    string.format('  "scheduled": %s,', scheduled),
    string.format('  "priority": %s,', task.priority and tostring(task.priority) or "null"),
    string.format('  "list_id": %s', vim.fn.json_encode(task.list_id or DEFAULT_LIST_ID)),
    "}",
  }
end

local function find_task_by_id(id)
  for _, task in ipairs(state.data.tasks) do
    if task.id == id then
      return task
    end
  end
  return nil
end

local function select_list_fallback(on_choice)
  local items = {}
  for _, list in ipairs(state.data.lists) do
    table.insert(items, list.id .. " | " .. list.name)
  end
  vim.ui.select(items, { prompt = "Select task list" }, function(choice)
    if not choice then
      return
    end
    local id = choice:match("^(.-)%s+|%s+")
    if id then
      on_choice(id)
    end
  end)
end

local function select_list_telescope(on_choice)
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    return false
  end
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local entries = {}
  for _, list in ipairs(state.data.lists) do
    table.insert(entries, { id = list.id, name = list.name, display = list.name .. " (" .. list.id .. ")" })
  end

  pickers.new({}, {
    prompt_title = "Task Lists",
    finder = finders.new_table {
      results = entries,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.name .. " " .. entry.id,
        }
      end,
    },
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if selection and selection.value then
          on_choice(selection.value.id)
        end
      end)
      return true
    end,
  }):find()

  return true
end

local function build_jump_entries()
  local entries = {
    { kind = "view", value = "all", label = "󰑭 All", ordinal = "view all" },
    { kind = "view", value = "today", label = " Today", ordinal = "view today" },
    { kind = "view", value = "overdue", label = "󰃤 Overdue", ordinal = "view overdue" },
    { kind = "view", value = "schedule", label = "󰃬 Schedule", ordinal = "view schedule" },
    { kind = "view", value = "log", label = "󱉺 Log", ordinal = "view log" },
    { kind = "view", value = "current", label = "󱃔 Current List", ordinal = "view current" },
  }

  for _, list in ipairs(state.data.lists) do
    table.insert(entries, {
      kind = "list",
      value = list.id,
      label = "󰲋 " .. list.name,
      ordinal = "list " .. list.name .. " " .. list.id,
    })
  end

  return entries
end

local function select_jump_fallback(on_choice)
  local entries = build_jump_entries()
  local labels = {}
  local by_label = {}
  for _, entry in ipairs(entries) do
    table.insert(labels, entry.label)
    by_label[entry.label] = entry
  end

  vim.ui.select(labels, { prompt = "Jump to view/list" }, function(choice)
    if not choice then
      return
    end
    local entry = by_label[choice]
    if entry then
      on_choice(entry)
    end
  end)
end

local function select_jump_telescope(on_choice)
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    return false
  end
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local entries = build_jump_entries()

  pickers.new({}, {
    prompt_title = "Task Jump",
    finder = finders.new_table {
      results = entries,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.label,
          ordinal = entry.ordinal,
        }
      end,
    },
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if selection and selection.value then
          on_choice(selection.value)
        end
      end)
      return true
    end,
  }):find()

  return true
end

local function select_existing_list_fallback(on_choice)
  local items = {}
  local by_label = {}
  for _, list in ipairs(state.data.lists) do
    local label = (config.options.theme.icons.list or "󰲋") .. " " .. list.name .. " (" .. list.id .. ")"
    table.insert(items, label)
    by_label[label] = list
  end

  vim.ui.select(items, { prompt = "Rename which list?" }, function(choice)
    if not choice then
      return
    end
    local list = by_label[choice]
    if list then
      on_choice(list)
    end
  end)
end

local function select_existing_list_telescope(on_choice)
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    return false
  end
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local entries = {}
  for _, list in ipairs(state.data.lists) do
    table.insert(entries, {
      id = list.id,
      name = list.name,
      display = (config.options.theme.icons.list or "󰲋") .. " " .. list.name .. " (" .. list.id .. ")",
    })
  end

  pickers.new({}, {
    prompt_title = "Rename List",
    finder = finders.new_table {
      results = entries,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.name .. " " .. entry.id,
        }
      end,
    },
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if selection and selection.value then
          on_choice(selection.value)
        end
      end)
      return true
    end,
  }):find()

  return true
end

local function pick_existing_list(on_choice, prompt)
  local callback = function(list)
    if not list then
      return
    end
    local resolved = list
    if list.id then
      resolved = get_list_from_key(list.id) or list
    end
    on_choice(resolved)
  end

  local ok, pickers = pcall(require, "telescope.pickers")
  if ok then
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    local entries = {}
    for _, list in ipairs(state.data.lists) do
      table.insert(entries, {
        id = list.id,
        name = list.name,
        color = list.color,
        display = (config.options.theme.icons.list or "󰲋") .. " " .. list.name .. " (" .. list.id .. ")",
      })
    end

    pickers.new({}, {
      prompt_title = prompt or "Select List",
      finder = finders.new_table {
        results = entries,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.display,
            ordinal = entry.name .. " " .. entry.id,
          }
        end,
      },
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection and selection.value then
            callback(selection.value)
          end
        end)
        return true
      end,
    }):find()

    return
  end

  local items = {}
  local by_label = {}
  for _, list in ipairs(state.data.lists) do
    local label = (config.options.theme.icons.list or "󰲋") .. " " .. list.name .. " (" .. list.id .. ")"
    table.insert(items, label)
    by_label[label] = list
  end

  vim.ui.select(items, { prompt = prompt or "Select List" }, function(choice)
    if not choice then
      return
    end
    callback(by_label[choice])
  end)
end

function M.open(view_name)
  load_data()
  if view_name then
    M.set_view(view_name)
  end
  open_main_buffer()
  rerender()
end

function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    local win = state.win
    local is_last_window = #vim.api.nvim_list_wins() == 1
    if is_last_window then
      local fallback_buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_set_current_buf(fallback_buf)
    end
    pcall(vim.api.nvim_win_close, win, true)
  end
  state.win = nil
end

function M.refresh()
  load_data()
  rerender()
end

function M.set_view(view_name)
  local next_view = view_name
  if type(next_view) ~= "string" or next_view == "" then
    next_view = "current"
  end

  local list_key = next_view:match("^list:(.+)$")
  if list_key then
    local list = get_list_from_key(list_key)
    if not list then
      notify_error("Task manager: list not found: " .. list_key)
      return
    end
    state.current_list_id = list.id
    state.current_view = "current"
  else
    state.current_view = next_view
    if next_view ~= "schedule" then
      state.deadline_week_offset = 0
    end
  end

  rerender()
end

function M.deadlines_prev_week()
  if effective_view() ~= "schedule" then
    return
  end
  state.deadline_week_offset = state.deadline_week_offset - 1
  rerender()
end

function M.deadlines_next_week()
  if effective_view() ~= "schedule" then
    return
  end
  state.deadline_week_offset = state.deadline_week_offset + 1
  rerender()
end

function M.deadlines_reset_week()
  if effective_view() ~= "schedule" then
    return
  end
  state.deadline_week_offset = 0
  rerender()
end

function M.add_task()
  local title = vim.fn.input("Task title: ")
  if not title or title == "" then
    return
  end

  model.add_task(state.data.tasks, {
    title = title,
    status = "todo",
    tags = {},
    list_id = state.current_list_id,
  })

  if save_data() then
    rerender()
  end
end

function M.delete_task()
  local bulk = has_bulk_selection()
  local ids = target_task_ids()
  if #ids == 0 then
    return
  end
  for _, id in ipairs(ids) do
    model.delete_task(state.data.tasks, id)
    state.selected_task_ids[id] = nil
  end
  if save_data() then
    if bulk then
      clear_selection_state()
    end
    rerender()
  end
end

function M.toggle_task_status()
  local bulk = has_bulk_selection()
  local ids = target_task_ids()
  if #ids == 0 then
    return
  end
  for _, id in ipairs(ids) do
    model.toggle_status(state.data.tasks, id)
  end
  if save_data() then
    if bulk then
      clear_selection_state()
    end
    rerender()
  end
end

function M.add_tag_to_task()
  local id = current_task_id()
  if not id then
    return
  end
  local tag = vim.fn.input("Tag: ")
  if tag == "" then
    return
  end

  local task = find_task_by_id(id)
  if not task then
    return
  end

  task.tags = task.tags or {}
  for _, existing in ipairs(task.tags) do
    if existing == tag then
      return
    end
  end
  table.insert(task.tags, tag)

  if save_data() then
    rerender()
  end
end

function M.rename_task()
  local bulk = has_bulk_selection()
  local ids = target_task_ids()
  if #ids == 0 then
    return
  end
  local task = find_task_by_id(ids[1])
  if not task then
    return
  end
  local title = vim.fn.input(bulk and "Rename selected tasks to: " or "Rename task: ", task.title or "")
  if not title or title == "" then
    return
  end
  for _, id in ipairs(ids) do
    model.update_task(state.data.tasks, id, { title = title })
  end
  if save_data() then
    if bulk then
      clear_selection_state()
    end
    rerender()
  end
end

function M.edit_tags()
  local bulk = has_bulk_selection()
  local ids = target_task_ids()
  if #ids == 0 then
    return
  end
  local task = find_task_by_id(ids[1])
  if not task then
    return
  end
  local existing = table.concat(task.tags or {}, ",")
  local raw = vim.fn.input(bulk and "Tags for selected (comma-separated): " or "Tags (comma-separated): ", existing)
  if raw == nil then
    return
  end
  local next_tags = {}
  local seen = {}
  for token in string.gmatch(raw, "[^,]+") do
    local cleaned = token:gsub("^%s+", ""):gsub("%s+$", "")
    if cleaned ~= "" and not seen[cleaned] then
      seen[cleaned] = true
      table.insert(next_tags, cleaned)
    end
  end
  for _, id in ipairs(ids) do
    model.update_task(state.data.tasks, id, { tags = next_tags })
  end
  if save_data() then
    if bulk then
      clear_selection_state()
    end
    rerender()
  end
end

function M.mark_done()
  local bulk = has_bulk_selection()
  local ids = target_task_ids()
  if #ids == 0 then
    return
  end
  for _, id in ipairs(ids) do
    local task = find_task_by_id(id)
    if task then
      if task.status == "done" then
        model.update_task(state.data.tasks, id, {
          status = "todo",
          completed_at = vim.NIL,
          completed_on = vim.NIL,
        })
      else
        model.update_task(state.data.tasks, id, {
          status = "done",
          completed_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
          completed_on = os.date("%Y-%m-%d"),
        })
      end
    end
  end
  if save_data() then
    if bulk then
      clear_selection_state()
    end
    rerender()
  end
end

function M.cycle_priority()
  local bulk = has_bulk_selection()
  local ids = target_task_ids()
  if #ids == 0 then
    return
  end

  for _, id in ipairs(ids) do
    local task = find_task_by_id(id)
    if task then
      local next_value = next_priority(task.priority)
      model.update_task(state.data.tasks, id, { priority = next_value == nil and vim.NIL or next_value })
    end
  end

  if save_data() then
    if bulk then
      clear_selection_state()
    end
    rerender()
  end
end

function M.move_task_to_list()
  local bulk = has_bulk_selection()
  local ids = target_task_ids()
  if #ids == 0 then
    return
  end
  local on_choice = function(list_id)
    for _, id in ipairs(ids) do
      model.update_task(state.data.tasks, id, { list_id = list_id })
      state.selected_task_ids[id] = nil
    end
    if save_data() then
      if bulk then
        clear_selection_state()
      end
      rerender()
    end
  end
  local used_telescope = select_list_telescope(on_choice)
  if not used_telescope then
    select_list_fallback(on_choice)
  end
end

function M.search_tasks()
  local query = vim.fn.input("Search (/ clear with empty): ", state.search_query or "")
  if query == nil then
    return
  end
  if query == "" then
    state.search_query = nil
  else
    state.search_query = query
  end
  rerender()
end

function M.set_scheduled_date()
  local bulk = has_bulk_selection()
  local ids = target_task_ids()
  if #ids == 0 then
    return
  end
  local current = (find_task_by_id(ids[1]) or {}).scheduled or os.date("%Y-%m-%d")
  local value = vim.fn.input("Scheduled (YYYY-MM-DD): ", current)
  if not value or value == "" then
    return
  end
  if not is_valid_date(value) then
    notify_error("Task manager: invalid date format (YYYY-MM-DD)")
    return
  end
  for _, id in ipairs(ids) do
    model.update_task(state.data.tasks, id, { scheduled = value })
  end
  if save_data() then
    if bulk then
      clear_selection_state()
    end
    rerender()
  end
end

function M.clear_scheduled_date()
  local bulk = has_bulk_selection()
  local ids = target_task_ids()
  if #ids == 0 then
    return
  end
  for _, id in ipairs(ids) do
    model.update_task(state.data.tasks, id, { scheduled = vim.NIL })
    local task = find_task_by_id(id)
    if task then
      task.scheduled = nil
    end
  end
  if save_data() then
    if bulk then
      clear_selection_state()
    end
    rerender()
  end
end

function M.set_due_date()
  local bulk = has_bulk_selection()
  local ids = target_task_ids()
  if #ids == 0 then
    return
  end
  local current = (find_task_by_id(ids[1]) or {}).due or os.date("%Y-%m-%d")
  local value = vim.fn.input("Due (YYYY-MM-DD): ", current)
  if not value or value == "" then
    return
  end
  if not is_valid_date(value) then
    notify_error("Task manager: invalid date format (YYYY-MM-DD)")
    return
  end
  for _, id in ipairs(ids) do
    model.update_task(state.data.tasks, id, { due = value })
  end
  if save_data() then
    if bulk then
      clear_selection_state()
    end
    rerender()
  end
end

function M.clear_due_date()
  local bulk = has_bulk_selection()
  local ids = target_task_ids()
  if #ids == 0 then
    return
  end
  for _, id in ipairs(ids) do
    model.update_task(state.data.tasks, id, { due = vim.NIL })
    local task = find_task_by_id(id)
    if task then
      task.due = nil
    end
  end
  if save_data() then
    if bulk then
      clear_selection_state()
    end
    rerender()
  end
end

function M.toggle_selection()
  local id = current_task_id()
  if not id then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]
  if state.selected_task_ids[id] then
    state.selected_task_ids[id] = nil
  else
    state.selected_task_ids[id] = true
  end
  rerender()
  local max_line = vim.api.nvim_buf_line_count(state.buf)
  local target_line = nil
  for line = current_line + 1, max_line do
    if state.line_to_id[line] then
      target_line = line
      break
    end
  end
  if target_line then
    pcall(vim.api.nvim_win_set_cursor, 0, { target_line, 0 })
  end
end

function M.clear_selection()
  state.selected_task_ids = {}
  rerender()
end

function M.edit_task()
  local id = current_task_id()
  if not id then
    return
  end

  local task = find_task_by_id(id)
  if not task then
    return
  end

  local edit_buf = vim.api.nvim_create_buf(true, false)
  vim.bo[edit_buf].buftype = "acwrite"
  vim.bo[edit_buf].filetype = "json"
  vim.bo[edit_buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_name(edit_buf, "task://" .. id)
  vim.api.nvim_buf_set_lines(edit_buf, 0, -1, false, format_edit_json(task))
  vim.api.nvim_set_current_buf(edit_buf)

  local group = vim.api.nvim_create_augroup("TaskManagerEdit" .. id, { clear = true })
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    buffer = edit_buf,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(edit_buf, 0, -1, false)
      local decoded, err = parse_task_json(lines)
      if err then
        notify_error(err)
        return
      end

      if type(decoded.title) ~= "string" or decoded.title == "" then
        notify_error("Task manager: title is required")
        return
      end
      if decoded.list_id ~= nil then
        local list = model.get_list_by_id(state.data.lists, decoded.list_id)
        if not list then
          notify_error("Task manager: list_id does not exist")
          return
        end
      end

      local updated = {
        title = decoded.title,
        status = decoded.status,
        tags = decoded.tags,
        due = decoded.due,
        scheduled = decoded.scheduled,
        priority = decoded.priority,
        list_id = decoded.list_id,
      }

      model.update_task(state.data.tasks, id, updated)
      if save_data() then
        vim.bo[edit_buf].modified = false
        vim.notify("Task saved", vim.log.levels.INFO)
        M.open(state.current_view)
      end
    end,
  })
end

function M.open_note()
  local id = current_task_id()
  if not id then
    return
  end
  local task = find_task_by_id(id)
  if not task then
    return
  end

  local path = task_note_path(task)
  ensure_dir(config.options.notes_dir)
  if vim.fn.filereadable(path) ~= 1 then
    local ok = pcall(vim.fn.writefile, {
      "# " .. (task.title or "Task Note"),
      "",
    }, path)
    if not ok then
      notify_error("Task manager: failed to create note file")
      return
    end
  end

  if task.note_path ~= path then
    model.update_task(state.data.tasks, id, { note_path = path })
    save_data()
  end

  vim.cmd("edit " .. vim.fn.fnameescape(path))
  vim.bo.filetype = "markdown"
end

function M.add_list(name)
  local list_name = name
  if not list_name or list_name == "" then
    list_name = vim.fn.input("New list name: ")
  end
  if not list_name or list_name == "" then
    return
  end
  if model.get_list_by_name(state.data.lists, list_name) then
    notify_error("Task manager: list already exists")
    return
  end
  local list = model.add_list(state.data.lists, { name = list_name })
  state.current_list_id = list.id
  state.current_view = "current"
  if save_data() then
    rerender()
  end
end

function M.rename_list(old_key, new_name)
  local old = old_key
  local next_name = new_name
  if not old or old == "" then
    old = vim.fn.input("List id or name: ")
  end
  local list = get_list_from_key(old)
  if not list then
    notify_error("Task manager: list not found")
    return
  end
  if not next_name or next_name == "" then
    next_name = vim.fn.input("New name: ", list.name)
  end
  if not next_name or next_name == "" then
    return
  end
  model.rename_list(state.data.lists, list.id, next_name)
  if save_data() then
    rerender()
  end
end

function M.rename_list_picker()
  local on_choice = function(list)
    local next_name = vim.fn.input("New name: ", list.name)
    if not next_name or next_name == "" then
      return
    end
    model.rename_list(state.data.lists, list.id, next_name)
    if save_data() then
      rerender()
    end
  end

  local used_telescope = select_existing_list_telescope(on_choice)
  if not used_telescope then
    select_existing_list_fallback(on_choice)
  end
end

function M.delete_list(key)
  local value = key
  if not value or value == "" then
    value = vim.fn.input("Delete list id or name: ")
  end
  local list = get_list_from_key(value)
  if not list then
    notify_error("Task manager: list not found")
    return
  end
  local ok, err = model.delete_list(state.data.lists, state.data.tasks, list.id, DEFAULT_LIST_ID)
  if not ok then
    notify_error(err)
    return
  end
  if state.current_list_id == list.id then
    state.current_list_id = DEFAULT_LIST_ID
    state.current_view = "current"
  end
  if save_data() then
    rerender()
  end
end

function M.set_list_color(key, color)
  local list_key = key
  local next_color = color
  local apply = function(list)
    if not next_color or next_color == "" then
      next_color = vim.fn.input("Color (#RRGGBB): ", list.color or "")
    end
    local normalized = normalize_hex_color(next_color)
    if not normalized then
      notify_error("Task manager: invalid color, use #RRGGBB")
      return
    end
    list.color = normalized
    if save_data() then
      rerender()
    end
  end

  if not list_key or list_key == "" then
    pick_existing_list(apply, "Set List Color")
    return
  end
  local list = get_list_from_key(list_key)
  if not list then
    notify_error("Task manager: list not found")
    return
  end
  apply(list)
end

function M.clear_list_color(key)
  local list_key = key
  local clear = function(list)
    list.color = nil
    if save_data() then
      rerender()
    end
  end

  if not list_key or list_key == "" then
    pick_existing_list(clear, "Clear List Color")
    return
  end
  local list = get_list_from_key(list_key)
  if not list then
    notify_error("Task manager: list not found")
    return
  end
  clear(list)
end

function M.pick_list()
  local on_choice = function(entry)
    if entry.kind == "view" then
      M.set_view(entry.value)
      return
    end
    if entry.kind == "list" then
      state.current_list_id = entry.value
      state.current_view = "current"
      rerender()
    end
  end

  local used_telescope = select_jump_telescope(on_choice)
  if not used_telescope then
    select_jump_fallback(on_choice)
  end
end

function M.list_names_for_completion()
  local out = {}
  for _, list in ipairs(state.data.lists or {}) do
    table.insert(out, list.name)
    table.insert(out, list.id)
  end
  return out
end

function M.task_search()
  load_data()

  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    notify_error("Task manager: Telescope is required for :TaskSearch")
    return
  end

  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")

  local icons = ((config.options.theme or {}).icons or {})
  local status_icons = icons.status or {}

  local entries = {}
  for _, task in ipairs(state.data.tasks or {}) do
    local list_name = list_name_by_id(task.list_id)
    local status_icon = status_icons[task.status] or "[ ]"
    local parts = {
      status_icon,
      task.title or "Untitled task",
      "[" .. list_name .. "]",
    }
    if task.scheduled then
      table.insert(parts, (icons.scheduled or "󰃰") .. " " .. task.scheduled)
    end
    if task.due then
      table.insert(parts, (icons.due or "󰓩") .. " " .. task.due)
    end
    if task.priority then
      table.insert(parts, "P" .. tostring(task.priority))
    end
    for _, tag in ipairs(task.tags or {}) do
      table.insert(parts, "#" .. tag)
    end

    local display = table.concat(parts, "  ")
    local ordinal_parts = {
      task.title or "",
      list_name,
      task.status or "",
      task.due or "",
      task.scheduled or "",
      task.priority and ("p" .. tostring(task.priority)) or "",
      table.concat(task.tags or {}, " "),
    }

    table.insert(entries, {
      task = task,
      list_name = list_name,
      display = display,
      ordinal = table.concat(ordinal_parts, " "),
    })
  end

  pickers.new({}, {
    prompt_title = "Task Search",
    finder = finders.new_table {
      results = entries,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.ordinal,
        }
      end,
    },
    previewer = previewers.new_buffer_previewer {
      title = "Task Details",
      define_preview = function(self, entry)
        local e = entry.value
        local task = e.task
        local lines = {
          "Title: " .. (task.title or "Untitled task"),
          "Status: " .. (task.status or "todo"),
          "List: " .. (e.list_name or "unknown"),
          "Priority: " .. (task.priority and ("P" .. tostring(task.priority)) or "none"),
          "Due: " .. (task.due or "none"),
          "Scheduled: " .. (task.scheduled or "none"),
          "Tags: " .. (#(task.tags or {}) > 0 and table.concat(task.tags, ", ") or "none"),
          "",
          "ID: " .. (task.id or ""),
        }

        if task.note_path and vim.fn.filereadable(task.note_path) == 1 then
          table.insert(lines, "")
          table.insert(lines, "Note: " .. task.note_path)
          local note_lines = vim.fn.readfile(task.note_path, "", 20)
          if #note_lines > 0 then
            table.insert(lines, "---")
            for _, line in ipairs(note_lines) do
              table.insert(lines, line)
            end
          end
        end

        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      end,
    },
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if not selection or not selection.value then
          return
        end
        local task = selection.value.task
        state.current_list_id = task.list_id or DEFAULT_LIST_ID
        state.current_view = "current"
        state.pending_focus_task_id = task.id
        M.open()
      end)
      return true
    end,
  }):find()
end

function M.ensure_loaded()
  if not state.data or not state.data.lists then
    load_data()
  end
end

return M
