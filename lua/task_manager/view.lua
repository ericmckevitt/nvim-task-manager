local M = {}
local NS = vim.api.nvim_create_namespace("task_manager_selection")
local NS_DONE = vim.api.nvim_create_namespace("task_manager_done")
local NS_TOKENS = vim.api.nvim_create_namespace("task_manager_tokens")
local NS_HEADER = vim.api.nvim_create_namespace("task_manager_header")
local NS_SECTION = vim.api.nvim_create_namespace("task_manager_sections")
local NS_LIST_COLOR = vim.api.nvim_create_namespace("task_manager_list_colors")
local SIGN_GROUP = "task_manager_selection_signs"
local SIGN_NAME = "TaskManagerSelectedSign"
local HIGHLIGHT_GROUP = "TaskManagerSelected"
local DONE_HIGHLIGHT_GROUP = "TaskManagerDone"
local TAG_HIGHLIGHT_GROUP = "TaskManagerTag"
local DUE_HIGHLIGHT_GROUP = "TaskManagerDue"
local SCHEDULED_HIGHLIGHT_GROUP = "TaskManagerScheduled"
local TITLE_HIGHLIGHT_GROUP = "TaskManagerTitle"
local LIST_HIGHLIGHT_GROUP = "TaskManagerList"
local PRIORITY_HIGHLIGHT_GROUP = "TaskManagerPriority"
local HEADER_HIGHLIGHT_GROUP = "TaskManagerHeader"
local HEADER_META_HIGHLIGHT_GROUP = "TaskManagerHeaderMeta"
local SECTION_HIGHLIGHT_GROUP = "TaskManagerSectionHeader"
local DEADLINE_DAY_HIGHLIGHT_GROUP = "TaskManagerDeadlineDayHeader"

local list_hl_cache = {}

local function sanitize_group_suffix(s)
  return tostring(s):gsub("[^%w_]", "_")
end

local function get_list_color_hl(list_id, color, bold)
  if not color then
    return nil
  end
  local key = tostring(list_id) .. "|" .. tostring(color) .. "|" .. tostring(bold)
  if list_hl_cache[key] then
    return list_hl_cache[key]
  end
  local group = "TaskManagerListColor_" .. sanitize_group_suffix(list_id) .. "_" .. sanitize_group_suffix(color)
  vim.api.nvim_set_hl(0, group, { fg = color, bold = bold == true })
  list_hl_cache[key] = group
  return group
end

local function format_task(task, opts)
  local options = opts or {}
  local icons = (options.theme and options.theme.icons) or {}
  local status_icons = icons.status or {}
  local icon = status_icons[task.status] or "[ ]"
  local title = task.title or "Untitled task"
  local parts = {}
  local token_spans = {}
  local col = 0

  local function append_part(text, token_type)
    local prefix = #parts == 0 and "" or " "
    local piece = prefix .. text
    table.insert(parts, piece)
    if token_type then
      local start_col = col + #prefix
      local end_col = start_col + #text
      table.insert(token_spans, {
        start_col = start_col,
        end_col = end_col,
        token_type = token_type,
        list_id = task.list_id,
      })
    end
    col = col + #piece
  end

  append_part(icon)
  append_part(title, "title")

  if options.show_list and options.list_lookup then
    local list_name = options.list_lookup[task.list_id or ""]
    if list_name then
      append_part("[" .. list_name .. "]", "list")
    end
  end

  if task.scheduled then
    local scheduled_icon = icons.scheduled or "󰃮"
    append_part(scheduled_icon .. " " .. task.scheduled, "scheduled")
  end
  if task.due then
    local due_icon = icons.due or "󰃭"
    append_part(due_icon .. " " .. task.due, "due")
  end
  if task.has_note then
    append_part(icons.note or "󰎚")
  end

  for _, tag in ipairs(task.tags or {}) do
    append_part("#" .. tag, "tag")
  end

  if task.priority ~= nil then
    append_part("P" .. tostring(task.priority), "priority")
  end
  return table.concat(parts, ""), token_spans
end

function M.create_list_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "taskmanager"
  vim.bo[buf].buflisted = false
  vim.bo[buf].undofile = false
  return buf
end

function M.open_plain_buffer(buf)
  vim.api.nvim_set_current_buf(buf)
  local win = vim.api.nvim_get_current_win()
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].cursorline = true
  vim.wo[win].signcolumn = "yes:1"
  vim.wo[win].wrap = false
end

function M.open_floating_window(buf, window_config)
  local columns = vim.o.columns
  local lines = vim.o.lines
  local width = math.max(40, math.floor(columns * window_config.width))
  local height = math.max(10, math.floor(lines * window_config.height))
  local row = math.floor((lines - height) / 2) - 1
  local col = math.floor((columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, row),
    col = math.max(0, col),
    style = "minimal",
    border = "rounded",
  })

  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].cursorline = true
  vim.wo[win].signcolumn = "yes:1"
  vim.wo[win].wrap = false

  return win
end

function M.render(buf, tasks, view_name, cursor_line, opts)
  local options = opts or {}
  local lines = {}
  local line_to_id = {}
  local line_to_task = {}
  local line_tokens = {}
  local section_lines = {}
  local display_view = options.display_view or view_name or "all"

  local function insert_task_line(task)
    local line, tokens = format_task(task, options)
    table.insert(lines, line)
    line_to_id[#lines] = task.id
    line_to_task[#lines] = task
    line_tokens[#lines] = tokens
  end

  table.insert(lines, "Task Manager | view: " .. display_view)
  table.insert(lines, string.rep("-", 60))

  if options.deadline_sections then
    for idx, section in ipairs(options.deadline_sections) do
      if idx > 1 then
        table.insert(lines, "")
      end
      local day_icon = ((options.theme or {}).icons or {}).scheduled or "󰃰"
      table.insert(lines, day_icon .. " " .. section.label)
      section_lines[#lines] = "__deadline_day__"
      if #section.tasks == 0 then
        table.insert(lines, "-")
      else
        for _, task in ipairs(section.tasks) do
          insert_task_line(task)
        end
      end
    end
  elseif #tasks == 0 then
    table.insert(lines, "No tasks")
  else
    if options.group_by_list and options.list_lookup then
      local grouped = {}
      local list_order = {}

      for _, task in ipairs(tasks) do
        local list_id = task.list_id or "default"
        if not grouped[list_id] then
          grouped[list_id] = {}
          table.insert(list_order, list_id)
        end
        table.insert(grouped[list_id], task)
      end

      table.sort(list_order, function(a, b)
        local an = options.list_lookup[a] or a
        local bn = options.list_lookup[b] or b
        return an:lower() < bn:lower()
      end)

      for idx, list_id in ipairs(list_order) do
        local list_name = options.list_lookup[list_id] or list_id
        local list_icon = ((options.theme or {}).icons or {}).list or "󰲋"
        if idx > 1 then
          table.insert(lines, "")
        end
        table.insert(lines, list_icon .. " " .. list_name)
        section_lines[#lines] = list_id
        for _, task in ipairs(grouped[list_id]) do
          insert_task_line(task)
        end
      end
    else
      for _, task in ipairs(tasks) do
        insert_task_line(task)
      end
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local highlights = (options.theme and options.theme.highlights) or {}
  local colors = (options.theme and options.theme.colors) or {}
  local selected_hl = highlights.selected or HIGHLIGHT_GROUP
  local selected_sign_hl = highlights.selected_sign or "TaskManagerSelectedSign"
  local done_hl = highlights.done or DONE_HIGHLIGHT_GROUP
  local tag_hl = highlights.tag or TAG_HIGHLIGHT_GROUP
  local due_hl = highlights.due or DUE_HIGHLIGHT_GROUP
  local scheduled_hl = highlights.scheduled or SCHEDULED_HIGHLIGHT_GROUP
  local title_hl = highlights.title or TITLE_HIGHLIGHT_GROUP
  local list_hl = highlights.list or LIST_HIGHLIGHT_GROUP
  local priority_hl = highlights.priority or PRIORITY_HIGHLIGHT_GROUP
  local header_hl = highlights.header or HEADER_HIGHLIGHT_GROUP
  local header_meta_hl = highlights.header_meta or HEADER_META_HIGHLIGHT_GROUP
  local section_hl = highlights.section or SECTION_HIGHLIGHT_GROUP
  local deadline_day_hl = highlights.deadline_day or DEADLINE_DAY_HIGHLIGHT_GROUP

  vim.api.nvim_set_hl(0, selected_hl, { link = "Visual", default = true })
  if type(colors.done) == "string" and colors.done ~= "" then
    vim.api.nvim_set_hl(0, done_hl, { fg = colors.done })
  else
    vim.api.nvim_set_hl(0, done_hl, { link = "Comment" })
  end
  vim.api.nvim_set_hl(0, tag_hl, { fg = colors.tag or "#a6e3a1" })
  vim.api.nvim_set_hl(0, due_hl, { fg = colors.due or "#f38ba8" })
  vim.api.nvim_set_hl(0, scheduled_hl, { fg = colors.scheduled or "#f9e2af" })
  vim.api.nvim_set_hl(0, title_hl, { fg = colors.title or "#cdd6f4" })
  vim.api.nvim_set_hl(0, list_hl, { fg = colors.list or "#89dceb" })
  vim.api.nvim_set_hl(0, priority_hl, { fg = colors.priority or "#fab387" })
  vim.api.nvim_set_hl(0, header_hl, { fg = colors.header or "#89b4fa", bold = true })
  vim.api.nvim_set_hl(0, header_meta_hl, { fg = colors.header_meta or "#9399b2" })
  vim.api.nvim_set_hl(0, section_hl, { fg = colors.list or "#89dceb", bold = true })
  vim.api.nvim_set_hl(0, deadline_day_hl, { fg = colors.scheduled or "#f9e2af", bold = true })
  vim.api.nvim_set_hl(0, selected_sign_hl, { fg = colors.selected_sign or colors.title or "#cdd6f4", bold = true })
  local selected_sign = (((options.theme or {}).icons or {}).selected) or "●"
  vim.fn.sign_define(SIGN_NAME, { text = selected_sign, texthl = selected_sign_hl })

  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, NS_DONE, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, NS_TOKENS, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, NS_HEADER, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, NS_SECTION, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, NS_LIST_COLOR, 0, -1)

  vim.api.nvim_buf_add_highlight(buf, NS_HEADER, header_hl, 0, 0, 12)
  vim.api.nvim_buf_add_highlight(buf, NS_HEADER, header_meta_hl, 0, 12, -1)
  vim.api.nvim_buf_add_highlight(buf, NS_HEADER, header_meta_hl, 1, 0, -1)

  local list_colors = options.list_colors or {}
  for line, list_id in pairs(section_lines) do
    local section_group = section_hl
    if list_id == "__deadline_day__" then
      section_group = deadline_day_hl
    else
      local list_color = list_colors[list_id]
      if list_color then
        section_group = get_list_color_hl(list_id, list_color, true) or section_hl
      end
    end
    vim.api.nvim_buf_add_highlight(buf, NS_SECTION, section_group, line - 1, 0, -1)
  end

  for line, task in pairs(line_to_task) do
    if task and task.status == "done" then
      vim.api.nvim_buf_add_highlight(buf, NS_DONE, done_hl, line - 1, 0, -1)
    end
  end

  for line, tokens in pairs(line_tokens) do
    for _, token in ipairs(tokens) do
      local group = nil
      if token.token_type == "tag" then
        group = tag_hl
      elseif token.token_type == "due" then
        group = due_hl
      elseif token.token_type == "scheduled" then
        group = scheduled_hl
      elseif token.token_type == "title" then
        group = title_hl
      elseif token.token_type == "list" then
        local color = list_colors[token.list_id]
        if color then
          group = get_list_color_hl(token.list_id or "list", color, false) or list_hl
        else
          group = list_hl
        end
      elseif token.token_type == "priority" then
        group = priority_hl
      end
      if group then
        vim.api.nvim_buf_add_highlight(buf, NS_TOKENS, group, line - 1, token.start_col, token.end_col)
      end
    end
  end

  if options.has_selection and options.selected_ids then
    vim.fn.sign_unplace(SIGN_GROUP, { buffer = buf })
    for line, task_id in pairs(line_to_id) do
      if options.selected_ids[task_id] then
        vim.api.nvim_buf_add_highlight(buf, NS, selected_hl, line - 1, 0, -1)
        vim.fn.sign_place(0, SIGN_GROUP, SIGN_NAME, buf, { lnum = line, priority = 10 })
      end
    end
  else
    vim.fn.sign_unplace(SIGN_GROUP, { buffer = buf })
  end

  local max_line = #lines
  local target = math.min(math.max(cursor_line or 3, 3), max_line)
  pcall(vim.api.nvim_win_set_cursor, 0, { target, 0 })

  return line_to_id
end

return M
