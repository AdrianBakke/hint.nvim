local M = {}
local state_module = require 'hint.state'
local state = state_module.state
local utils = require 'hint.utils'
local namespace_id = vim.api.nvim_create_namespace 'hint_llm_output'
local Job = require 'plenary.job'

function M.create_or_update_window()
  -- Check if there is at least one tab
  if #state.tabs == 0 then
    table.insert(state.tabs, { name = 'Tab 1', buf = vim.api.nvim_create_buf(false, true) })
    state.current_tab = 1
  end

  local current_tab = state.tabs[state.current_tab]
  local buf = current_tab.buf

  if state.win_obj == nil then
    -- Define dimensions for the windows
    local width = math.floor(vim.o.columns * 0.8)
    local height = math.floor(vim.o.lines * 0.8)

    -- Create window for the main content
    local win = vim.api.nvim_open_win(buf, true, {
      relative = 'editor',
      width = width - 2,
      height = height - 2,
      col = math.floor((vim.o.columns - width) / 2),
      row = math.floor((vim.o.lines - height) / 2) + 1, -- Adjust row to accommodate tab bar
      style = 'minimal',
      border = {
        { '╭', 'FloatBorder' },
        { '─', 'FloatBorder' },
        { '╮', 'FloatBorder' },
        { '│', 'FloatBorder' },
        { '╯', 'FloatBorder' },
        { '─', 'FloatBorder' },
        { '╰', 'FloatBorder' },
        { '│', 'FloatBorder' },
      },
    })

    -- Create window for the tab bar
    local tab_buf = vim.api.nvim_create_buf(false, true)
    local tab_win = vim.api.nvim_open_win(tab_buf, false, {
      relative = 'editor',
      width = width,
      height = 1, -- Only one line for the tab bar
      col = math.floor((vim.o.columns - width) / 2),
      row = math.floor((vim.o.lines - height) / 2), -- Position above the main content window
      style = 'minimal',
      border = 'none',
    })

    -- Store window objects
    state.win_obj = {
      win = win,
      tab_win = tab_win,
      tab_buf = tab_buf,
      close = function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
        if vim.api.nvim_win_is_valid(tab_win) then
          vim.api.nvim_win_close(tab_win, true)
        end
        state.win_obj = nil -- Set to nil after closing
      end,
    }

    -- Set window options for the main content
    vim.wo[state.win_obj.win].wrap = true
    vim.wo[state.win_obj.win].number = false
    vim.wo[state.win_obj.win].relativenumber = false
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].modifiable = true
    vim.bo[buf].filetype = 'markdown'
  end

  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '', { callback = M.close_current_tab, noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Tab>', '', { callback = M.next_tab, noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<S-Tab>', '', { callback = M.prev_tab, noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<C-j>', '', { callback = M.toggle_window, noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<leader>tt', '', { callback = M.create_new_tab, noremap = true, silent = true })
  --vim.api.nvim_buf_set_keymap(buf, 'n', '<leader>i', '', { callback = M.insert_codeblock, noremap = true, silent = true })
  --vim.api.nvim_buf_set_keymap(buf, 'n', '<leader>ir', '', { callback = M.rollback_insert, noremap = true, silent = true })

  vim.api.nvim_win_set_buf(state.win_obj.win, buf)
  local line_count = vim.api.nvim_buf_line_count(buf)
  local cursor_pos = state.cursor_positions[state.current_tab] or { 1, 0 }
  vim.api.nvim_win_set_cursor(state.win_obj.win, cursor_pos)
end

local function render_tabs()
  if not state.win_obj or not vim.api.nvim_win_is_valid(state.win_obj.tab_win) then
    return
  end

  -- Render Tab Bar in the tab buffer
  local tab_line = ' '
  for i, tab in ipairs(state.tabs) do
    if i == state.current_tab then
      tab_line = tab_line .. '  ' .. tab.name .. '  '
    else
      tab_line = tab_line .. '  ' .. tab.name .. '  '
    end
  end
  --print(vim.inspect(state))
  local tab_buf = state.win_obj.tab_buf
  vim.api.nvim_buf_set_option(tab_buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(tab_buf, 0, -1, false, { tab_line })
  vim.api.nvim_buf_add_highlight(tab_buf, namespace_id, 'TabLine', 0, 0, -1)
  vim.api.nvim_buf_set_option(tab_buf, 'modifiable', false)
end

function M.next_tab()
  if #state.tabs == 0 then
    return
  end
  state.cursor_positions[state.current_tab] = vim.api.nvim_win_get_cursor(state.win_obj.win)
  state.current_tab = state.current_tab % #state.tabs + 1
  M.create_or_update_window()
  render_tabs()
end

function M.create_new_tab(name)
  if #state.tabs > 9 then
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  table.insert(state.tabs, { name = 'Tab ' .. (#state.tabs + 1), buf = buf })
  state.current_tab = #state.tabs
  M.create_or_update_window()
  render_tabs()
  return buf
end

function M.prev_tab()
  if #state.tabs == 0 then
    return
  end
  state.cursor_positions[state.current_tab] = vim.api.nvim_win_get_cursor(state.win_obj.win)
  state.current_tab = (state.current_tab - 2) % #state.tabs + 1
  M.create_or_update_window()
  render_tabs()
end

function M.close_current_tab()
  if #state.tabs == 0 then
    return
  end
  table.remove(state.tabs, state.current_tab)
  table.remove(state.cursor_positions, state.current_tab)
  if state.current_tab > #state.tabs then
    state.current_tab = #state.tabs
  end
  if #state.tabs == 0 then
    state.win_obj.close()
    state.win_obj = nil
  else
    -- Rename tabs to maintain order
    for i, _ in ipairs(state.tabs) do
      state.tabs[i].name = 'Tab ' .. i
    end
    M.create_or_update_window()
    render_tabs()
  end
end

function M.toggle_window()
  if state.win_obj and vim.api.nvim_win_is_valid(state.win_obj.win) then
    state.cursor_positions[state.current_tab] = vim.api.nvim_win_get_cursor(state.win_obj.win)
    state.win_obj.close()
    state.win_obj = nil
  else
    state.main_win = vim.api.nvim_get_current_win()

    M.create_or_update_window()
    render_tabs()
    local cursor_pos = state.cursor_positions[state.current_tab] or { 1, 0 }
    vim.api.nvim_win_set_cursor(state.win_obj.win, cursor_pos)
  end
end

return M
