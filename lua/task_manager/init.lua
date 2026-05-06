local config = require("task_manager.config")
local controller = require("task_manager.controller")

local M = {}
local initialized = false

local function complete_views(arg_lead)
  controller.ensure_loaded()
  local views = { "all", "today", "overdue", "log", "schedule", "by_tag:" }
  for _, key in ipairs(controller.list_names_for_completion()) do
    table.insert(views, "list:" .. key)
  end
  local out = {}
  for _, v in ipairs(views) do
    if v:find("^" .. vim.pesc(arg_lead)) then
      table.insert(out, v)
    end
  end
  return out
end

function M.setup(opts)
  config.setup(opts)

  if initialized then
    return
  end
  initialized = true

  vim.api.nvim_create_user_command("TaskOpen", function()
    controller.open()
  end, {})

  vim.api.nvim_create_user_command("TaskAdd", function()
    controller.open()
    controller.add_task()
  end, {})

  vim.api.nvim_create_user_command("TaskView", function(args)
    local view_name = args.args ~= "" and args.args or "all"
    controller.open(view_name)
  end, {
    nargs = "?",
    complete = complete_views,
  })

  vim.api.nvim_create_user_command("TaskSearch", function()
    controller.task_search()
  end, {})

  vim.api.nvim_create_user_command("TaskLists", function()
    controller.open()
    controller.pick_list()
  end, {})

  vim.api.nvim_create_user_command("TaskListAdd", function(args)
    controller.open()
    controller.add_list(args.args)
  end, { nargs = "?" })

  vim.api.nvim_create_user_command("TaskListRename", function(args)
    controller.open()
    if args.args == "" then
      controller.rename_list_picker()
      return
    end
    local list_id, new_name = args.args:match("^(%S+)%s+(.+)$")
    if not list_id or not new_name then
      vim.notify("Task manager: use :TaskListRename <list_id> <new name>", vim.log.levels.ERROR)
      return
    end
    controller.rename_list(list_id, new_name)
  end, {
    nargs = "?",
    complete = function(arg_lead)
      controller.ensure_loaded()
      local items = controller.list_names_for_completion()
      local out = {}
      for _, item in ipairs(items) do
        if item:find("^" .. vim.pesc(arg_lead)) then
          table.insert(out, item)
        end
      end
      return out
    end,
  })

  vim.api.nvim_create_user_command("TaskListDelete", function(args)
    controller.open()
    controller.delete_list(args.args)
  end, {
    nargs = "?",
    complete = function(arg_lead)
      controller.ensure_loaded()
      local items = controller.list_names_for_completion()
      local out = {}
      for _, item in ipairs(items) do
        if item:find("^" .. vim.pesc(arg_lead)) then
          table.insert(out, item)
        end
      end
      return out
    end,
  })

  vim.api.nvim_create_user_command("TaskListColor", function(args)
    controller.open()
    if args.args == "" then
      controller.set_list_color()
      return
    end
    local key, color = args.args:match("^(%S+)%s+(%S+)$")
    if not key or not color then
      vim.notify("Task manager: use :TaskListColor <list_id_or_name> <#RRGGBB>", vim.log.levels.ERROR)
      return
    end
    controller.set_list_color(key, color)
  end, {
    nargs = "?",
    complete = function(arg_lead)
      controller.ensure_loaded()
      local items = controller.list_names_for_completion()
      local out = {}
      for _, item in ipairs(items) do
        if item:find("^" .. vim.pesc(arg_lead)) then
          table.insert(out, item)
        end
      end
      return out
    end,
  })

  vim.api.nvim_create_user_command("TaskListColorClear", function(args)
    controller.open()
    controller.clear_list_color(args.args)
  end, {
    nargs = "?",
    complete = function(arg_lead)
      controller.ensure_loaded()
      local items = controller.list_names_for_completion()
      local out = {}
      for _, item in ipairs(items) do
        if item:find("^" .. vim.pesc(arg_lead)) then
          table.insert(out, item)
        end
      end
      return out
    end,
  })

  local km = config.options.keymaps
  if km.open and km.open ~= "" then
    vim.keymap.set("n", km.open, function()
      controller.open()
    end, { desc = "Open task manager" })
  end

  vim.keymap.set("n", "<leader>ot", function()
    controller.open("all")
  end, { desc = "Open task manager (all)" })
end

return M
