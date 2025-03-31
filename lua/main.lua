local M = {}
local state_module = require 'state'
local ui = require 'ui'
local api = require 'api'
local utils = require 'utils'

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

function M.write_to_window(str)
  vim.schedule(function()
    if not state_module.state.win_obj or not vim.api.nvim_win_is_valid(state_module.state.win_obj.win) then
      ui.create_or_update_window()
    end

    local active_tab = state_module.state.tabs[state_module.state.current_tab]
    if not active_tab or not vim.api.nvim_buf_is_valid(active_tab.buf) then
      return
    end

    local buf = active_tab.buf

    if string.find(str, '^
```') then
      str = '\n' .. str
    end

    local current_line_count = vim.api.nvim_buf_line_count(buf)
    local before_line = current_line_count

    local lines = vim.split(str, '\n', true)
    for i, line in ipairs(lines) do
      if i == 1 and current_line_count > 0 then
        local last_line = vim.api.nvim_buf_get_lines(buf, current_line_count - 1, current_line_count, false)[1] or ''
        vim.api.nvim_buf_set_lines(buf, current_line_count - 1, current_line_count, false, { last_line .. line })
      else
        vim.api.nvim_buf_set_lines(buf, current_line_count, current_line_count, false, { line })
        current_line_count = current_line_count + 1
      end
    end

    local ns = namespace_id
    for i = before_line, current_line_count - 1 do
      vim.api.nvim_buf_add_highlight(buf, ns, 'NormalFloat', i, 0, -1)
    end

    vim.api.nvim_win_set_cursor(state_module.state.win_obj.win, { current_line_count, 0 })
  end)
end

function M.create_new_tab(name)
  if #state_module.state.tabs > 9 then
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  table.insert(state_module.state.tabs, { name = 'Tab ' .. (#state_module.state.tabs + 1), buf = buf })
  state_module.state.current_tab = #state_module.state.tabs
  ui.create_or_update_window()
  ui.render_tabs()
  return buf
end

function M.close_current_tab()
  if #state_module.state.tabs == 0 then
    return
  end
  table.remove(state_module.state.tabs, state_module.state.current_tab)
  table.remove(state_module.state.cursor_positions, state_module.state.current_tab)
  if state_module.state.current_tab > #state_module.state.tabs then
    state_module.state.current_tab = #state_module.state.tabs
  end
  if #state_module.state.tabs == 0 then
    state_module.state.win_obj.close()
    state_module.state.win_obj = nil
  else
    -- Rename tabs to maintain order
    for i, _ in ipairs(state_module.state.tabs) do
      state_module.state.tabs[i].name = 'Tab ' .. i
    end
    ui.create_or_update_window()
    ui.render_tabs()
  end
end

function M.next_tab()
  if #state_module.state.tabs == 0 then
    return
  end
  state_module.state.cursor_positions[state_module.state.current_tab] = vim.api.nvim_win_get_cursor(state_module.state.win_obj.win)
  state_module.state.current_tab = state_module.state.current_tab % #state_module.state.tabs + 1
  ui.create_or_update_window()
  ui.render_tabs()
end

function M.prev_tab()
  if #state_module.state.tabs == 0 then
    return
  end
  state_module.state.cursor_positions[state_module.state.current_tab] = vim.api.nvim_win_get_cursor(state_module.state.win_obj.win)
  state_module.state.current_tab = (state_module.state.current_tab - 2) % #state_module.state.tabs + 1
  ui.create_or_update_window()
  ui.render_tabs()
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
