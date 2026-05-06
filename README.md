# task_manager.nvim

A keyboard-first task manager for Neovim with JSON-backed storage and no external service requirements.

## Highlights

- Local-first task management inside Neovim
- JSON file as the source of truth
- Multiple views (`all`, `today`, `overdue`, `log`, `schedule`, `by_tag:<tag>`, and list-scoped views)
- Bulk actions, list switching, and task search
- Markdown notes per task
- Optional Telescope integration with graceful fallback
- Runs completely locally with no network access required

## Requirements

- Neovim
- Optional: Telescope (`nvim-telescope/telescope.nvim`) for enhanced pickers/search

No external CLI tools, cloud services, or network connectivity are required.

## Installation (manual)

Copy this repo into your Neovim runtime path (or plugin directory) so that:

- `plugin/task_manager.lua`
- `lua/task_manager/*.lua`

are available to Neovim.

## Basic Setup

`plugin/task_manager.lua` auto-calls setup with defaults. You can also configure manually:

```lua
require("task_manager").setup({
  file_path = vim.fn.stdpath("data") .. "/tasks.json",
  notes_dir = vim.fn.stdpath("data") .. "/task_manager/notes",
  use_floating_window = false,
  group_global_views_by_list = true,
})
```

## Main Commands

- `:TaskOpen` — open current list view
- `:TaskAdd` — open task manager and add task
- `:TaskView <name>` — switch view
- `:TaskSearch` — Telescope global task search
- `:TaskLists` — jump picker for views/lists
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

## Data Model

Tasks are stored in JSON with list support and metadata (status, tags, due/scheduled dates, priority, notes, completion timestamps).

Task notes are stored as local markdown files in `notes_dir`.

## Notes

- The plugin is fully local and offline.
- Done-task retention and log/schedule behavior are view-specific.
- Works without Telescope, but Telescope provides the best search/picker UX.
