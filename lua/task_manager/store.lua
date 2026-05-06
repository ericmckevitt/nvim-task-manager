local M = {}

local DEFAULT_LIST_ID = "default"

local function default_data()
  return {
    lists = {
      {
        id = DEFAULT_LIST_ID,
        name = "Default",
        created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
      },
    },
    tasks = {},
  }
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

local function normalize_lists(data)
  if type(data.lists) ~= "table" then
    data.lists = {}
  end

  local seen = {}
  local normalized = {}
  for _, list in ipairs(data.lists) do
    if type(list) == "table" and type(list.id) == "string" and list.id ~= "" and not seen[list.id] then
      seen[list.id] = true
      table.insert(normalized, {
        id = list.id,
        name = (type(list.name) == "string" and list.name ~= "") and list.name or list.id,
        created_at = type(list.created_at) == "string" and list.created_at or os.date("!%Y-%m-%dT%H:%M:%SZ"),
        color = normalize_hex_color(list.color),
      })
    end
  end

  data.lists = normalized
  if #data.lists == 0 then
    table.insert(data.lists, {
      id = DEFAULT_LIST_ID,
      name = "Default",
      created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
      color = nil,
    })
  end

  local has_default = false
  for _, list in ipairs(data.lists) do
    if list.id == DEFAULT_LIST_ID then
      has_default = true
      break
    end
  end
  if not has_default then
    table.insert(data.lists, 1, {
      id = DEFAULT_LIST_ID,
      name = "Default",
      created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
      color = nil,
    })
  end
end

local function normalize_tasks(data)
  if type(data.tasks) ~= "table" then
    data.tasks = {}
  end

  local valid_lists = {}
  for _, list in ipairs(data.lists) do
    valid_lists[list.id] = true
  end

  for _, task in ipairs(data.tasks) do
    if type(task) == "table" then
      if type(task.list_id) ~= "string" or task.list_id == "" or not valid_lists[task.list_id] then
        task.list_id = DEFAULT_LIST_ID
      end
    end
  end
end

local function normalize_data(data)
  local normalized = data
  if type(normalized) ~= "table" then
    normalized = default_data()
  end
  normalize_lists(normalized)
  normalize_tasks(normalized)
  return normalized
end

local function notify_error(message)
  vim.notify(message, vim.log.levels.ERROR)
end

local function ensure_parent_dir(file_path)
  local dir = vim.fn.fnamemodify(file_path, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
end

local function write_default_file(file_path)
  ensure_parent_dir(file_path)
  local encoded = vim.fn.json_encode(default_data())
  local ok = pcall(vim.fn.writefile, { encoded }, file_path)
  if not ok then
    notify_error("Task manager: failed to create task file at " .. file_path)
    return false
  end
  return true
end

local function ensure_file(file_path)
  if vim.fn.filereadable(file_path) == 1 then
    return true
  end
  return write_default_file(file_path)
end

function M.load(file_path)
  if not ensure_file(file_path) then
    return default_data()
  end

  local lines = vim.fn.readfile(file_path)
  local content = table.concat(lines, "\n")

  if content == "" then
    return default_data()
  end

  local ok, decoded = pcall(vim.fn.json_decode, content)
  if not ok or type(decoded) ~= "table" then
    notify_error("Task manager: invalid JSON in " .. file_path)
    return default_data()
  end

  return normalize_data(decoded)
end

function M.save(file_path, data)
  ensure_parent_dir(file_path)

  local payload = data
  if type(payload) ~= "table" then
    payload = default_data()
  end
  payload = normalize_data(payload)

  local ok_encode, encoded = pcall(vim.fn.json_encode, payload)
  if not ok_encode then
    notify_error("Task manager: failed to encode JSON")
    return false
  end

  local ok_write = pcall(vim.fn.writefile, { encoded }, file_path)
  if not ok_write then
    notify_error("Task manager: failed to save " .. file_path)
    return false
  end

  return true
end

return M
