local M = {}

function M.get_visual_selection()
  local mode = vim.fn.mode()
  if mode ~= 'v' and mode ~= 'V' and mode ~= '\22' then
    return nil
  end
  local _, srow, scol = unpack(vim.fn.getpos 'v')
  local _, erow, ecol = unpack(vim.fn.getpos '.')
  if srow == 0 or erow == 0 then
    return nil
  end
  if srow > erow or (srow == erow and scol > ecol) then
    srow, erow, scol, ecol = erow, srow, ecol, scol
  end
  if mode == 'V' then
    local lines = vim.api.nvim_buf_get_lines(0, srow - 1, erow, false)
    return { text = table.concat(lines, '\n'), start = srow, ['end'] = erow }
  end
  local lines = vim.api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {})
  return { text = table.concat(lines, '\n'), start = srow, ['end'] = erow }
end

function M.find_hint_comment(bufnr, from_line)
  for i = from_line, 1, -1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1] or ''
    local text = line:match('HINT:%s*(.+)')
    if text then
      return text, i
    end
  end
  return nil
end

function M.read_file(path, max_bytes)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines then
    return nil
  end
  local out = {}
  local total = 0
  for _, line in ipairs(lines) do
    total = total + #line + 1
    if max_bytes and total > max_bytes then
      table.insert(out, line)
      table.insert(out, '...truncated...')
      break
    end
    table.insert(out, line)
  end
  return table.concat(out, '\n')
end

function M.truncate(text, max)
  if not max or #text <= max then
    return text
  end
  return text:sub(1, max) .. '...'
end

return M
