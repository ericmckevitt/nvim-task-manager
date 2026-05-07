# nvim-task-manager

Keyboard-first task management inside Neovim with JSON-backed storage, list organization, schedule/log views, and markdown notes.

## Local-Only / Offline

- Runs 100% locally on your machine
- Stores data on local disk (`tasks.json` + markdown note files)
- Requires no network access to operate
- Uses no external web services or cloud sync

## Features

- JSON file as source of truth
- Multiple views: `all`, `today`, `overdue`, `log`, `schedule`, `by_tag:<tag>`, `list:<name|id>`
- Week navigation in schedule view (`[w`, `]w`, `gw`)
- Global fuzzy task search (`:TaskSearch`, Telescope)
- List management, per-list colors, and grouped global views
- Bulk selection + bulk edits/actions
- Markdown notes per task (`n`)
- Optional Telescope integration with graceful fallback to `vim.ui.select`

## Requirements

- Neovim
- Optional: Telescope (`nvim-telescope/telescope.nvim`) for enhanced pickers/search

No external CLI tools are required.

## Installation With lazy.nvim

```lua
{
  "ericmckevitt/nvim-task-manager",
  main = "task_manager",
  opts = {
    file_path = vim.fn.stdpath("data") .. "/tasks.json",
    notes_dir = vim.fn.stdpath("data") .. "/task_manager/notes",
  },
  cmd = {
    "TaskOpen",
    "TaskAdd",
    "TaskView",
    "TaskSearch",
    "TaskLists",
    "TaskListAdd",
    "TaskListRename",
    "TaskListDelete",
    "TaskListColor",
    "TaskListColorClear",
  },
}
```

## Local Development Spec (lazy.nvim)

```lua
{
  dir = "~/Desktop/Code/task_manager.nvim",
  main = "task_manager",
  opts = {},
  cmd = { "TaskOpen", "TaskView", "TaskSearch" },
}
```

## Manual Setup (without lazy.nvim)

Place this repo on `runtimepath`, then call:

```lua
require("task_manager").setup({})
```

## Commands

- `:TaskOpen` open current list view
- `:TaskAdd` add a new task
- `:TaskView <name>` switch view
- `:TaskSearch` global task search
- `:TaskLists` jump picker for views/lists
- `:TaskListAdd [name]`
- `:TaskListRename`
- `:TaskListDelete [name_or_id]`
- `:TaskListColor` / `:TaskListColorClear`

## Default In-Buffer Keybinds

- `a` add task
- `e` full JSON edit
- `r` rename task (bulk-capable)
- `c` edit tags (bulk-capable)
- `n` open task note (markdown)
- `x` toggle done <-> todo
- `<Space>` cycle status
- `p` cycle priority (`none -> P3 -> P2 -> P1 -> none`)
- `m` move task(s) to another list
- `v` / `V` select / clear selection
- `t` / `T` set / clear due date
- `y` / `Y` set / clear scheduled date
- `/` global Telescope task search
- `?` inline filter (current rendered scope)
- `gl` or `s` jump to view/list
- `[w` / `]w` previous/next week in schedule view
- `gw` reset schedule view to current week
- `q` or `<Esc>` close task manager window

## Default Data Paths

- Task JSON: `vim.fn.stdpath("data") .. "/tasks.json"`
- Notes directory: `vim.fn.stdpath("data") .. "/task_manager/notes"`
