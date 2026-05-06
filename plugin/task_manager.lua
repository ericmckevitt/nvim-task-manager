if vim.g.loaded_task_manager_plugin == 1 then
  return
end
vim.g.loaded_task_manager_plugin = 1

require("task_manager").setup()
