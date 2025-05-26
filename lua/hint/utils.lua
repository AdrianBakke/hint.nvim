local M = {}

local state_module = require 'hint.state'
local state = state_module.state

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

function get_lines_until_cursor()
  --print(state.main_win)
  local main_buf = vim.api.nvim_win_get_buf(state.main_win)
  local cursor_pos = vim.api.nvim_win_get_cursor(state.main_win)
  local end_row = cursor_pos[1]

  local lines = vim.api.nvim_buf_get_lines(main_buf, 0, end_row, true)

  if state.tabs and vim.api.nvim_buf_is_valid(state.tabs[state.current_tab].buf) then
    local buff_lines = vim.api.nvim_buf_get_lines(state.tabs[state.current_tab].buf, 0, -1, true)
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
    prompt = get_lines_until_cursor()
  end

  local current_tab = state.tabs[state.current_tab]
  if current_tab or current_tab.context_files then
    local context = {}
    for _, filepath in ipairs(current_tab.context_files) do
      local file_content = vim.fn.readfile(filepath)
      if file_content then
        table.insert(context, '### ' .. filepath .. '\\n' .. table.concat(file_content, '\\n'))
      else
        vim.notify('Failed to read file: ' .. filepath, vim.log.levels.ERROR)
      end
    end
    -- Combine context and prompt
    prompt = table.concat(context, '\n\n') .. '\n\n' .. prompt
  end

  return prompt
end

function M.write_to_window(str)
  vim.schedule(function()
    if not state.win_obj or not vim.api.nvim_win_is_valid(state.win_obj.win) then
      M.create_or_update_window()
    end

    local active_tab = state.tabs[state.current_tab]
    if not active_tab or not vim.api.nvim_buf_is_valid(active_tab.buf) then
      return
    end

    local buf = active_tab.buf

    if string.find(str, '^```') then
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

    -- print(vim.inspect(state_module))
    --local ns = namespace_id
    for i = before_line, current_line_count - 1 do
      vim.api.nvim_buf_add_highlight(buf, -1, 'NormalFloat', i, 0, -1) -- -1 now should be namespace id?
    end

    vim.api.nvim_win_set_cursor(state.win_obj.win, { current_line_count, 0 })
  end)
end

function M.parse_code_block(text)
  local pattern = 'CODEBLOCK%-START%s*({.-})%s*CODEBLOCK%-END'
  local codeblock_str = string.match(text, pattern)

  if not codeblock_str then
    print 'no valid codeblock'
  end

  local t = vim.json.decode(codeblock_str)
  print(vim.inspect(t))
end

return M
