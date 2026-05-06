local M = {}

local defaults = {
  file_path = vim.fn.stdpath("data") .. "/tasks.json",
  use_floating_window = false,
  group_global_views_by_list = true,
  notes_dir = vim.fn.stdpath("data") .. "/task_manager/notes",
  keymaps = {
    open = "<leader>to",
    add = "a",
    delete = "d",
    toggle = "<Space>",
    mark_done = "x",
    priority_cycle = "p",
    note = "n",
    refresh = "R",
    close = "q",
    close_alt = "<Esc>",
    edit = "e",
    rename = "r",
    tag = "c",
    move = "m",
    search = "/",
    search_inline = "?",
    week_prev = "[w",
    week_next = "]w",
    week_reset = "gw",
    set_scheduled = "y",
    clear_scheduled = "Y",
    set_due = "t",
    clear_due = "T",
    select_toggle = "v",
    select_clear = "V",
    switch_list_alt = "s",
    switch_list = "gl",
  },
  window = {
    width = 0.6,
    height = 0.6,
  },
  theme = {
    icons = {
      status = {
        todo = "󰄱",
        doing = "󰔟",
        done = "󰄵",
      },
      selected = "▌",
      list = "󰲋",
      due = "󰓩",
      scheduled = "󰃰",
      note = "󰎚",
    },
    highlights = {
      selected = "TaskManagerSelected",
      selected_sign = "TaskManagerSelectedSign",
      done = "TaskManagerDone",
      tag = "TaskManagerTag",
      due = "TaskManagerDue",
      scheduled = "TaskManagerScheduled",
      title = "TaskManagerTitle",
      list = "TaskManagerList",
      priority = "TaskManagerPriority",
      header = "TaskManagerHeader",
      header_meta = "TaskManagerHeaderMeta",
      section = "TaskManagerSectionHeader",
      deadline_day = "TaskManagerDeadlineDayHeader",
    },
    colors = {
      header = "#89b4fa",
      header_meta = "#9399b2",
      title = "#cdd6f4",
      done = "#6c7086",
      tag = "#a6e3a1",
      due = "#f38ba8",
      scheduled = "#f9e2af",
      list = "#89dceb",
      priority = "#fab387",
      selected_sign = "#cdd6f4",
    },
  },
}

M.options = vim.deepcopy(defaults)

function M.setup(user_opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_opts or {})
  return M.options
end

return M
