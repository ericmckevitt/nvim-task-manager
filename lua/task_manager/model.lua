local M = {}
local DEFAULT_LIST_ID = "default"

local STATUS_ORDER = {
  todo = "doing",
  doing = "done",
  done = "todo",
}

local function now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function today_local()
  return os.date("%Y-%m-%d")
end

local function completion_day(iso)
  if type(iso) ~= "string" then
    return nil
  end
  return iso:match("^(%d%d%d%d%-%d%d%-%d%d)")
end

local function is_done_visible_today(task)
  if task.status ~= "done" then
    return true
  end
  local day = task.completed_on
  if type(day) ~= "string" or day == "" then
    day = completion_day(task.completed_at)
  end
  if not day then
    return false
  end
  return day == today_local()
end

local function gen_id()
  local seed = tostring(os.time()) .. tostring(math.random(1000, 9999))
  local hr = string.format("%.0f", vim.loop.hrtime())
  return seed .. "-" .. hr
end

local function shallow_copy(tbl)
  local copy = {}
  for k, v in pairs(tbl or {}) do
    copy[k] = v
  end
  return copy
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

local function is_date(value)
  return type(value) == "string" and value:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil
end

function M.normalize_task(task)
  local item = shallow_copy(task)
  item.id = item.id or gen_id()
  item.title = type(item.title) == "string" and item.title or "Untitled task"
  item.status = STATUS_ORDER[item.status] and item.status or "todo"
  item.tags = type(item.tags) == "table" and item.tags or {}
  item.due = is_date(item.due) and item.due or nil
  item.scheduled = is_date(item.scheduled) and item.scheduled or nil
  local numeric_priority = tonumber(item.priority)
  if numeric_priority and numeric_priority >= 1 and numeric_priority <= 3 then
    item.priority = math.floor(numeric_priority)
  else
    item.priority = nil
  end
  item.list_id = type(item.list_id) == "string" and item.list_id or DEFAULT_LIST_ID
  item.note_path = type(item.note_path) == "string" and item.note_path or nil
  item.completed_at = type(item.completed_at) == "string" and item.completed_at or nil
  item.completed_on = type(item.completed_on) == "string" and item.completed_on or nil
  if item.status ~= "done" then
    item.completed_at = nil
    item.completed_on = nil
  end
  item.created_at = item.created_at or now_iso()
  return item
end

function M.normalize_list(list)
  local item = shallow_copy(list)
  item.id = type(item.id) == "string" and item.id ~= "" and item.id or gen_id()
  item.name = type(item.name) == "string" and item.name ~= "" and item.name or item.id
  item.created_at = type(item.created_at) == "string" and item.created_at or now_iso()
  item.color = normalize_hex_color(item.color)
  return item
end

local function find_index(tasks, id)
  for i, task in ipairs(tasks) do
    if task.id == id then
      return i
    end
  end
  return nil
end

function M.add_task(tasks, input)
  local list = tasks or {}
  local task = M.normalize_task(input or {})

  while find_index(list, task.id) do
    task.id = gen_id()
  end

  table.insert(list, task)
  return task
end

local function find_list_index(lists, id)
  for i, list in ipairs(lists or {}) do
    if list.id == id then
      return i
    end
  end
  return nil
end

function M.add_list(lists, input)
  local list_items = lists or {}
  local item = M.normalize_list(input or {})
  while find_list_index(list_items, item.id) do
    item.id = gen_id()
  end
  table.insert(list_items, item)
  return item
end

function M.rename_list(lists, id, new_name)
  local idx = find_list_index(lists, id)
  if not idx then
    return nil
  end
  if type(new_name) ~= "string" or new_name == "" then
    return nil
  end
  lists[idx].name = new_name
  return lists[idx]
end

function M.delete_list(lists, tasks, id, fallback_list_id)
  if id == DEFAULT_LIST_ID then
    return false, "Task manager: cannot delete default list"
  end
  local idx = find_list_index(lists, id)
  if not idx then
    return false, "Task manager: list not found"
  end
  local fallback = fallback_list_id or DEFAULT_LIST_ID
  for _, task in ipairs(tasks or {}) do
    if task.list_id == id then
      task.list_id = fallback
    end
  end
  table.remove(lists, idx)
  return true, nil
end

function M.get_list_by_id(lists, id)
  for _, list in ipairs(lists or {}) do
    if list.id == id then
      return list
    end
  end
  return nil
end

function M.get_list_by_name(lists, name)
  for _, list in ipairs(lists or {}) do
    if list.name == name then
      return list
    end
  end
  return nil
end

function M.delete_task(tasks, id)
  local list = tasks or {}
  local idx = find_index(list, id)
  if not idx then
    return false
  end
  table.remove(list, idx)
  return true
end

function M.update_task(tasks, id, updates)
  local list = tasks or {}
  local idx = find_index(list, id)
  if not idx then
    return nil
  end

  local merged = shallow_copy(list[idx])
  for k, v in pairs(updates or {}) do
    if v == vim.NIL then
      merged[k] = nil
    else
      merged[k] = v
    end
  end
  merged.id = list[idx].id
  list[idx] = M.normalize_task(merged)
  list[idx].id = id
  return list[idx]
end

function M.toggle_status(tasks, id)
  local list = tasks or {}
  local idx = find_index(list, id)
  if not idx then
    return nil
  end

  local current = list[idx].status
  local next_status = STATUS_ORDER[current] or "todo"
  list[idx].status = next_status
  if next_status == "done" then
    list[idx].completed_at = now_iso()
    list[idx].completed_on = today_local()
  else
    list[idx].completed_at = nil
    list[idx].completed_on = nil
  end
  return list[idx]
end

function M.filter_tasks(tasks, view_name, opts)
  local list = tasks or {}
  local view = view_name or "all"
  local options = opts or {}
  local current_list_id = options.current_list_id
  local today = os.date("%Y-%m-%d")
  local out = {}

  local tag = view:match("^by_tag:(.+)$")
  local list_key = view:match("^list:(.+)$")

  for _, task in ipairs(list) do
    local include = true

    if view == "today" then
      include = task.scheduled == today and is_done_visible_today(task)
    elseif view == "overdue" then
      include = task.status ~= "done" and type(task.due) == "string" and task.due < today
    elseif view == "log" then
      include = task.status == "done"
    elseif tag then
      include = false
      for _, t in ipairs(task.tags or {}) do
        if t == tag then
          include = true
          break
        end
      end
    elseif list_key then
      include = task.list_id == list_key
    elseif view == "current" then
      include = current_list_id and task.list_id == current_list_id or true
    elseif view ~= "all" then
      include = true
    end

    if include and view ~= "overdue" and view ~= "log" then
      include = is_done_visible_today(task)
    end

    if include then
      table.insert(out, task)
    end
  end

  return out
end

function M.sort_tasks(tasks)
  table.sort(tasks, function(a, b)
    local as = a.scheduled or "9999-99-99"
    local bs = b.scheduled or "9999-99-99"
    if as ~= bs then
      return as < bs
    end

    local ad = a.due or "9999-99-99"
    local bd = b.due or "9999-99-99"
    if ad ~= bd then
      return ad < bd
    end

    local ap = tonumber(a.priority) or 99
    local bp = tonumber(b.priority) or 99
    if ap ~= bp then
      return ap < bp
    end

    return (a.created_at or "") < (b.created_at or "")
  end)

  return tasks
end

local function sort_log_tasks(tasks)
  table.sort(tasks, function(a, b)
    local ac = a.completed_at or ""
    local bc = b.completed_at or ""
    if ac ~= bc then
      return ac > bc
    end
    return (a.created_at or "") > (b.created_at or "")
  end)
  return tasks
end

function M.prepare_view(tasks, view_name, opts)
  local filtered = M.filter_tasks(tasks, view_name, opts)
  local copy = {}
  for _, task in ipairs(filtered) do
    table.insert(copy, task)
  end
  if view_name == "log" then
    return sort_log_tasks(copy)
  end
  return M.sort_tasks(copy)
end

return M
