local M = {}
local state_module = require 'hint.state'
local ui = require 'hint.ui'
local api = require 'hint.api'
local utils = require 'hint.utils'

-- Utility Functions
local function get_lines_until_cursor()
  local main_buf = vim.api.nvim_win_get_buf(state_module.state.main_win or vim.api.nvim_get_current_win())
  local cursor_pos = vim.api.nvim_win_get_cursor(state_module.state.main_win or vim.api.nvim_get_current_win())
  local end_row = cursor_pos[1]

  local lines = vim.api.nvim_buf_get_lines(main_buf, 0, end_row, true)

  if state_module.state.tabs and vim.api.nvim_buf_is_valid(state_module.state.tabs[state_module.state.current_tab].buf) then
    local buff_lines = vim.api.nvim_buf_get_lines(state_module.state.tabs[state_module.state.current_tab].buf, 0, -1, true)
    table.insert(lines, '') -- add a separator
    vim.list_extend(lines, buff_lines)
  end

  return table.concat(lines, '\n')
end

function M.get_prompt(opts)
  local replace = opts.replace
  local visual_lines = utils.get_visual_selection()
  local prompt = ''

  if visual_lines then
    prompt = table.concat(visual_lines, '\n')
    if replace then
      vim.api.nvim_command 'normal! d'
      vim.api.nvim_command 'normal! k'
    else
      local _, erow, ecol = unpack(vim.fn.getpos '.')
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', false, true, true), 'nx', false)
      vim.api.nvim_win_set_cursor(0, { erow, ecol })
      vim.api.nvim_command 'normal! o'
    end
  else
    prompt = get_lines_until_cursor()
  end

  return prompt
end

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

  -- Add more setup configurations as needed
end

return M
