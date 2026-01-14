local config = require 'hint.config'
local state = require 'hint.state'

local M = {}

local function close()
  if state.prompt.win and vim.api.nvim_win_is_valid(state.prompt.win) then
    vim.api.nvim_win_close(state.prompt.win, true)
  end
  state.prompt.win = nil
  state.prompt.buf = nil
end

function M.open(opts, on_submit)
  if state.prompt.win and vim.api.nvim_win_is_valid(state.prompt.win) then
    close()
  end
  local cfg = config.get().prompt
  local width = math.min(cfg.width, vim.o.columns - 4)
  local height = math.min(cfg.height, vim.o.lines - 4)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'hintprompt'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.lines or { '' })
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = 1
  if cursor[1] + height + 1 > vim.o.lines then
    row = -height - 1
  end
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'cursor',
    row = row,
    col = 0,
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
  })
  state.prompt.win = win
  state.prompt.buf = buf

  local function submit()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = table.concat(lines, '\n'):gsub('%s+$', '')
    close()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', true)
    if on_submit then
      on_submit(text)
    end
  end

  vim.keymap.set({ 'n', 'i' }, '<Esc>', close, { buffer = buf, silent = true })
  vim.keymap.set({ 'n', 'i' }, '<CR>', submit, { buffer = buf, silent = true })
  vim.keymap.set('n', 'q', close, { buffer = buf, silent = true })
  vim.schedule(function()
    if state.prompt.win and vim.api.nvim_win_is_valid(state.prompt.win) then
      vim.cmd 'startinsert'
    end
  end)
end

return M
