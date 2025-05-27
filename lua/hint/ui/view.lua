local M = {}
local state = require('hint.state').state
local vim = vim

-- Creates the main content window
function M.create_main_window(buf)
  local width = math.floor(vim.o.columns * 0.8) - 2
  local height = math.floor(vim.o.lines * 0.8) - 2
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width - 2) / 2),
    row = math.floor((vim.o.lines - height - 2) / 2) + 1,
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
  return win
end

-- Creates the tab header window
function M.create_tab_window(width, row)
  local tab_buf = vim.api.nvim_create_buf(false, true)
  local tab_win = vim.api.nvim_open_win(tab_buf, false, {
    relative = 'editor',
    width = width,
    height = 4,
    col = math.floor((vim.o.columns - width) / 2),
    row = row,
    style = 'minimal',
    border = 'none',
  })
  return tab_win, tab_buf
end

-- Renders a header with emojis and colored text
function M.render_header(tab_buf, win_width)
  local prefix = '🔥🔥🔥 '
  local suffix = ' 🔥🔥🔥'
  local header = 'HINT'
  local full_header = prefix .. header .. suffix
  local total_width = vim.fn.strdisplaywidth(full_header)
  local padding = math.floor((win_width - total_width) / 2)
  local header_line = string.rep(' ', padding) .. full_header

  vim.api.nvim_buf_set_option(tab_buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(tab_buf, 0, 1, false, { header_line })
  vim.api.nvim_buf_set_option(tab_buf, 'modifiable', false)
end

-- Renders the tab bar showing tabs and the active one
function M.render_tab_bar(tab_buf, tabs, current_index)
  local tab_line = ' '
  for i, tab in ipairs(tabs) do
    if i == current_index then
      tab_line = tab_line .. '  ' .. tab.name .. '  '
    else
      tab_line = tab_line .. '  ' .. tab.name .. '  '
    end
  end
  vim.api.nvim_buf_set_option(tab_buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(tab_buf, 1, 2, false, { tab_line })
  vim.api.nvim_buf_set_option(tab_buf, 'modifiable', false)
end

-- Renders context file info in the header
function M.render_context_info(tab_buf, current_tab)
  local context_files = current_tab.context_files or {}
  local filenames = {}
  for _, file in ipairs(context_files) do
    table.insert(filenames, vim.fn.fnamemodify(file, ':t'))
  end
  local context_line = '  Context Files: ' .. (#filenames > 0 and table.concat(filenames, ', ') or 'None')
  vim.api.nvim_buf_set_option(tab_buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(tab_buf, 2, 3, false, { context_line })
  vim.api.nvim_buf_set_option(tab_buf, 'modifiable', false)
end

-- Renders a token estimate (a simplistic example)
function M.render_token_estimate(tab_buf, current_tab)
  local buf_lines = vim.api.nvim_buf_get_lines(current_tab.buf, 0, -1, false)
  local buf_text = table.concat(buf_lines, ' ')
  local token_estimate = math.floor(#buf_text / 4)
  local token_line = '  Token Estimate: ' .. token_estimate .. ' tokens'
  vim.api.nvim_buf_set_option(tab_buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(tab_buf, 3, 4, false, { token_line })
  vim.api.nvim_buf_set_option(tab_buf, 'modifiable', false)
end

return M
