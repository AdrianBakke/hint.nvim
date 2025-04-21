local M = {}
local state_module = require 'hint.state'
local ui = require 'hint.ui'
local api = require 'hint.api'
local utils = require 'hint.utils'

function M.rollback_insert()
  if not state_module.state.snapshots.before_insert then
    vim.notify('No insertion snapshot available', vim.log.levels.WARN)
    return
  end

  local main_buf = vim.api.nvim_win_get_buf(state_module.state.main_win)
  vim.api.nvim_buf_set_lines(main_buf, 0, -1, false, state_module.state.snapshots.before_insert.lines)
  vim.notify('♻️ Rolled back to pre-insertion state', vim.log.levels.INFO)
end

function M.insert_codeblock()
  -- Function implementation (similar to original code)
  -- You can refactor the original insert_codeblock function here
end

function M.setup()
  -- Initialize your plugin, set up keymaps, etc.
  -- You can set up autocommands, keybindings here
  vim.api.nvim_create_user_command('HintToggle', function()
    ui.toggle_window()
  end, {})

  vim.api.nvim_create_user_command('HintNewTab', function(opts)
    M.create_new_tab(opts.args)
  end, { nargs = '*' })
end

return M
