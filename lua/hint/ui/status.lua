local config = require 'hint.config'
local state = require 'hint.state'
local util = require 'hint.util'

local M = {}

local frames = { '|', '/', '-', '\\' }

local function ensure()
  local opts = config.get().status
  if state.status.win and vim.api.nvim_win_is_valid(state.status.win) then
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  local width = math.min(opts.width, vim.o.columns - 2)
  local height = math.min(opts.height, vim.o.lines - 2)
  local row = math.max(0, vim.o.lines - height - 2)
  local col = math.max(0, vim.o.columns - width - 2)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    focusable = false,
  })
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].modifiable = false
  state.status.buf = buf
  state.status.win = win
  state.status.lines = state.status.lines or {}
  state.status.history = state.status.history or {}
end

local function activity_line()
  if not state.status.activity then
    return nil
  end
  local idx = state.status.spinner_index or 1
  local frame = frames[(idx - 1) % #frames + 1]
  return ('HINT %s %s'):format(frame, state.status.activity)
end

local function render()
  if not (state.status.activity or (state.status.win and vim.api.nvim_win_is_valid(state.status.win))) then
    return
  end
  ensure()
  local buf = state.status.buf
  local opts = config.get().status
  local lines = {}
  local header = activity_line()
  if header then
    table.insert(lines, header)
  end
  local limit = math.max(0, opts.height - #lines)
  if limit > 0 and #state.status.lines > 0 then
    local start_idx = math.max(1, #state.status.lines - limit + 1)
    for i = start_idx, #state.status.lines do
      table.insert(lines, state.status.lines[i])
    end
  end
  local out = {}
  for _, line in ipairs(lines) do
    table.insert(out, util.truncate(line, opts.width - 2))
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
  vim.bo[buf].modifiable = false
end

local function append_line(msg)
  local opts = config.get().status
  local limit = opts.height - (state.status.activity and 1 or 0)
  limit = math.max(0, limit)
  table.insert(state.status.lines, msg)
  while #state.status.lines > limit do
    table.remove(state.status.lines, 1)
  end
  table.insert(state.status.history, msg)
  while #state.status.history > opts.max_history do
    table.remove(state.status.history, 1)
  end
end

local function start_timer()
  if state.status.timer then
    return
  end
  state.status.spinner_index = 1
  state.status.timer = vim.loop.new_timer()
  state.status.timer:start(
    0,
    120,
    vim.schedule_wrap(function()
      if not state.status.activity then
        return
      end
      state.status.spinner_index = state.status.spinner_index + 1
      render()
    end)
  )
end

local function stop_timer()
  if not state.status.timer then
    return
  end
  state.status.timer:stop()
  state.status.timer:close()
  state.status.timer = nil
end

function M.close()
  if state.status.win and vim.api.nvim_win_is_valid(state.status.win) then
    vim.api.nvim_win_close(state.status.win, true)
  end
  state.status.win = nil
  state.status.buf = nil
end

function M.log(msg)
  local function write()
    append_line(msg)
    render()
  end
  if vim.in_fast_event() then
    vim.schedule(write)
  else
    write()
  end
end

function M.clear()
  local function wipe()
    state.status.lines = {}
    state.status.history = {}
    if state.status.win and vim.api.nvim_win_is_valid(state.status.win) then
      render()
    end
  end
  if vim.in_fast_event() then
    vim.schedule(wipe)
  else
    wipe()
  end
end

function M.start(msg)
  local function go()
    state.status.activity = msg or 'Working'
    ensure()
    start_timer()
    render()
  end
  if vim.in_fast_event() then
    vim.schedule(go)
  else
    go()
  end
end

function M.set_activity(msg)
  local function go()
    state.status.activity = msg
    render()
  end
  if vim.in_fast_event() then
    vim.schedule(go)
  else
    go()
  end
end

function M.finish(msg)
  local function done()
    if msg and msg ~= '' then
      append_line(msg)
    end
    state.status.activity = nil
    stop_timer()
    M.close()
  end
  if vim.in_fast_event() then
    vim.schedule(done)
  else
    done()
  end
end

function M.open_log()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'hintlog'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, state.status.history or {})
  vim.cmd 'botright 10split'
  vim.api.nvim_win_set_buf(0, buf)
end

return M
