local M = {}

local state_module = require 'hint.state'

function M.get_api_key(name)
  return os.getenv(name)
end

function M.get_visual_selection()
  local _, srow, scol = unpack(vim.fn.getpos 'v')
  local _, erow, ecol = unpack(vim.fn.getpos '.')

  if vim.fn.mode() == 'V' then
    if srow > erow then
      return vim.api.nvim_buf_get_lines(0, erow - 1, srow, true)
    else
      return vim.api.nvim_buf_get_lines(0, srow - 1, erow, true)
    end
  end

  if vim.fn.mode() == 'v' then
    if srow < erow or (srow == erow and scol <= ecol) then
      return vim.api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {})
    else
      return vim.api.nvim_buf_get_text(0, erow - 1, ecol - 1, srow - 1, scol, {})
    end
  end

  if vim.fn.mode() == '\22' then
    local lines = {}
    if srow > erow then
      srow, erow = erow, srow
    end
    if scol > ecol then
      scol, ecol = ecol, scol
    end
    for i = srow, erow do
      local line_content = vim.api.nvim_buf_get_text(0, i - 1, math.min(scol - 1, ecol), i - 1, math.max(scol - 1, ecol), {})
      if line_content[1] then
        table.insert(lines, line_content[1])
      end
    end
    return lines
  end
end

function M.get_lines_until_cursor(state_module)
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
  local visual_lines = M.get_visual_selection()
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
    prompt = M.get_lines_until_cursor(state_module)
  end

  return prompt
end

return M
