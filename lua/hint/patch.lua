local state = require 'hint.state'

local M = {}
local highlight_ns = vim.api.nvim_create_namespace 'hint_apply'

local function flash_lines(buf, line_numbers)
  local function do_flash()
    if not (buf and vim.api.nvim_buf_is_valid(buf)) then
      return
    end
    for _, line in ipairs(line_numbers) do
      if line >= 0 then
        vim.api.nvim_buf_add_highlight(buf, highlight_ns, 'DiffAdd', line, 0, -1)
      end
    end
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_clear_namespace(buf, highlight_ns, 0, -1)
      end
    end, 1500)
  end
  if vim.in_fast_event() then
    vim.schedule(do_flash)
  else
    do_flash()
  end
end

local function parse_apply_patch(text)
  local lines = vim.split(text, '\n', { plain = true })
  local i = 1
  local files = {}
  local function extract_anchor(header)
    local anchor = header:match('^@@%s*(.-)%s*@@%s*(.+)$')
    if anchor and anchor:find('%a') then
      return anchor
    end
    anchor = header:match('^@@%s*(.+)$')
    if anchor and anchor:find('%a') then
      return anchor
    end
    return nil
  end
  local function normalize_hunk_line(line)
    if line == '' then
      return ' '
    end
    if line:match('^[%+%- ]') then
      return line
    end
    return ' ' .. line
  end
  while i <= #lines do
    local file = lines[i]:match('^%*%*%* Update File:%s*(.+)$')
    if file then
      i = i + 1
      local hunks = {}
      while i <= #lines and not lines[i]:match('^%*%*%* ') do
        if lines[i]:match('^@@') then
          local header = lines[i]
          local anchor = extract_anchor(header)
          i = i + 1
          local hunk_lines = {}
          while i <= #lines and not lines[i]:match('^@@') and not lines[i]:match('^%*%*%* ') do
            table.insert(hunk_lines, normalize_hunk_line(lines[i]))
            i = i + 1
          end
          table.insert(hunks, { lines = hunk_lines, header = header, anchor = anchor })
        else
          i = i + 1
        end
      end
      table.insert(files, { filename = file, hunks = hunks })
    else
      i = i + 1
    end
  end
  return files
end

local function find_hunk_start(buf_lines, hunk_lines)
  local pattern = {}
  for _, line in ipairs(hunk_lines) do
    local prefix = line:sub(1, 1)
    if prefix == ' ' or prefix == '-' then
      table.insert(pattern, line:sub(2))
    end
  end
  if #pattern == 0 then
    return nil
  end
  for i = 1, #buf_lines - #pattern + 1 do
    local match = true
    for j = 1, #pattern do
      if buf_lines[i + j - 1] ~= pattern[j] then
        match = false
        break
      end
    end
    if match then
      return i, #pattern
    end
  end
  return nil
end

local function apply_hunk(buf, start_idx, span, hunk_lines)
  local new_lines = {}
  local added = {}
  local out_idx = 0
  for _, line in ipairs(hunk_lines) do
    local prefix = line:sub(1, 1)
    local text = line:sub(2)
    if prefix == ' ' then
      out_idx = out_idx + 1
      new_lines[out_idx] = text
    elseif prefix == '+' then
      out_idx = out_idx + 1
      new_lines[out_idx] = text
      table.insert(added, out_idx)
    elseif prefix == '-' then
      -- skip removed line
    end
  end
  vim.api.nvim_buf_set_lines(buf, start_idx - 1, start_idx - 1 + span, false, new_lines)
  return added, #new_lines
end

local function hunk_has_context(hunk_lines)
  for _, line in ipairs(hunk_lines) do
    local prefix = line:sub(1, 1)
    if prefix == ' ' or prefix == '-' then
      return true
    end
  end
  return false
end

local function hunk_added_lines(hunk_lines)
  local out = {}
  for _, line in ipairs(hunk_lines) do
    if line:sub(1, 1) == '+' then
      table.insert(out, line:sub(2))
    end
  end
  return out
end

local function hunk_added_lines_excluding_removed(hunk_lines)
  local removed = {}
  for _, line in ipairs(hunk_lines) do
    if line:sub(1, 1) == '-' then
      removed[line:sub(2)] = true
    end
  end
  local out = {}
  for _, line in ipairs(hunk_lines) do
    if line:sub(1, 1) == '+' then
      local text = line:sub(2)
      if not removed[text] then
        table.insert(out, text)
      end
    end
  end
  return out
end

local function hunk_anchor_lines(hunk_lines)
  local out = {}
  local has_add = false
  for _, line in ipairs(hunk_lines) do
    if line:sub(1, 1) == '+' then
      has_add = true
      break
    end
  end
  for i, line in ipairs(hunk_lines) do
    local prefix = line:sub(1, 1)
    local text = line:sub(2)
    if prefix == '+' then
      table.insert(out, text)
    elseif prefix == ' ' and has_add then
      if text:match('^%s*/%*%*') or text:match('^%s*//') then
        table.insert(out, text)
      end
    end
  end
  return out
end

local function hunk_contains_text(hunk_lines, text)
  if not text or text == '' then
    return false
  end
  for _, line in ipairs(hunk_lines) do
    local prefix = line:sub(1, 1)
    if prefix == ' ' or prefix == '-' then
      if line:sub(2):find(text, 1, true) then
        return true
      end
    end
  end
  return false
end

local function find_anchor_line(buf_lines, anchor)
  if not anchor or anchor == '' then
    return nil
  end
  for i, line in ipairs(buf_lines) do
    if line:find(anchor, 1, true) then
      return i
    end
  end
  return nil
end

local function extract_changes(hunk_lines)
  local added, removed, prefix_ctx, suffix_ctx = {}, {}, {}, {}
  local in_changes = false
  for _, line in ipairs(hunk_lines) do
    local prefix = line:sub(1, 1)
    local text = line:sub(2)
    if prefix == ' ' then
      if in_changes then
        table.insert(suffix_ctx, text)
      else
        table.insert(prefix_ctx, text)
      end
    elseif prefix == '+' then
      in_changes = true
      table.insert(added, text)
    elseif prefix == '-' then
      in_changes = true
      table.insert(removed, text)
    end
  end
  return added, removed, prefix_ctx, suffix_ctx
end

local function strip_common_prefix(removed, added)
  local i = 1
  while removed[i] and added[i] and removed[i] == added[i] do
    i = i + 1
  end
  if i == 1 then
    return removed, added
  end
  local new_removed, new_added = {}, {}
  for j = i, #removed do
    table.insert(new_removed, removed[j])
  end
  for j = i, #added do
    table.insert(new_added, added[j])
  end
  return new_removed, new_added
end

local function find_block(buf_lines, block)
  if #block == 0 then
    return nil
  end
  for i = 1, #buf_lines - #block + 1 do
    local match = true
    for j = 1, #block do
      if buf_lines[i + j - 1] ~= block[j] then
        match = false
        break
      end
    end
    if match then
      return i
    end
  end
  return nil
end

local function hunk_only_additions(hunk_lines)
  local has_add = false
  for _, line in ipairs(hunk_lines) do
    local prefix = line:sub(1, 1)
    if prefix == '-' then
      return false
    end
    if prefix == '+' then
      has_add = true
    end
  end
  return has_add
end

local function extract_patch_blocks(text)
  local blocks = {}
  local start = 1
  while true do
    local s = text:find('%*%*%* Begin Patch', start)
    if not s then
      break
    end
    local e = text:find('%*%*%* End Patch', s)
    if e then
      e = e + #'*** End Patch' - 1
    else
      e = #text
    end
    table.insert(blocks, text:sub(s, e))
    start = e + 1
  end
  return blocks
end

local function skip_ws(text, i)
  while i <= #text and text:sub(i, i):match('%s') do
    i = i + 1
  end
  return i
end

local function parse_quoted(text, i, quote)
  local out = {}
  i = i + 1
  while i <= #text do
    local c = text:sub(i, i)
    if c == '\\' then
      local nextc = text:sub(i + 1, i + 1)
      if nextc == 'n' then
        table.insert(out, '\n')
      elseif nextc == 't' then
        table.insert(out, '\t')
      elseif nextc == 'r' then
        table.insert(out, '\r')
      elseif nextc ~= '' then
        table.insert(out, nextc)
      end
      i = i + 2
    elseif c == quote then
      return table.concat(out), i + 1
    else
      table.insert(out, c)
      i = i + 1
    end
  end
  return nil, i
end

local function parse_string(text, i)
  local ch = text:sub(i, i)
  if ch == '"' or ch == "'" then
    return parse_quoted(text, i, ch)
  end
  if text:sub(i, i + 1) == '[[' then
    local close = text:find(']]', i + 2, true)
    if not close then
      return nil, i
    end
    local value = text:sub(i + 2, close - 1)
    return value, close + 2
  end
  return nil, i
end

local function parse_patch_calls(text, default_path)
  local hunks = {}
  local idx = 1
  while true do
    local s, e = text:find('patch%s*%(', idx)
    if not s then
      break
    end
    local i = skip_ws(text, e + 1)
    local from, next_i = parse_string(text, i)
    if not from then
      idx = e + 1
      goto continue
    end
    i = skip_ws(text, next_i)
    if text:sub(i, i) ~= ',' then
      idx = e + 1
      goto continue
    end
    i = skip_ws(text, i + 1)
    local to, next_j = parse_string(text, i)
    if not to then
      idx = e + 1
      goto continue
    end
    i = skip_ws(text, next_j)
    if text:sub(i, i) ~= ')' then
      idx = e + 1
      goto continue
    end
    local lines = {}
    for _, line in ipairs(vim.split(from, '\n', { plain = true })) do
      table.insert(lines, '-' .. line)
    end
    for _, line in ipairs(vim.split(to, '\n', { plain = true })) do
      table.insert(lines, '+' .. line)
    end
    table.insert(hunks, { lines = lines })
    idx = i + 1
    ::continue::
  end
  if #hunks == 0 then
    return nil
  end
  return {
    kind = 'apply_patch',
    files = {
      {
        filename = default_path or '',
        hunks = hunks,
      },
    },
  }
end

function M.parse_diff(text, opts)
  if not text then
    return nil
  end
  local blocks = extract_patch_blocks(text)
  local merged = {}
  local order = {}
  for _, block in ipairs(blocks) do
    local files = parse_apply_patch(block)
    for _, file in ipairs(files) do
      if not merged[file.filename] then
        merged[file.filename] = { filename = file.filename, hunks = {} }
        table.insert(order, merged[file.filename])
      end
      for _, hunk in ipairs(file.hunks or {}) do
        table.insert(merged[file.filename].hunks, hunk)
      end
    end
  end
  if #order > 0 then
    return { kind = 'apply_patch', files = order }
  end
  local default_path = opts and opts.default_path or nil
  return parse_patch_calls(text, default_path)
end

local function buffer_for(path)
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  return buf
end

local function resolve_path(filename)
  if not filename or filename == '' then
    return nil
  end
  local abs = vim.fn.fnamemodify(filename, ':p')
  if vim.fn.filereadable(abs) == 1 then
    return abs
  end
  local root = vim.fn.getcwd()
  local found = vim.fn.findfile(filename, root .. '/**')
  if found ~= '' then
    return vim.fn.fnamemodify(found, ':p')
  end
  local base = vim.fn.fnamemodify(filename, ':t')
  found = vim.fn.findfile(base, root .. '/**')
  if found ~= '' then
    return vim.fn.fnamemodify(found, ':p')
  end
  return nil
end

function M.rollback()
  for path, lines in pairs(state.snapshots or {}) do
    local buf = buffer_for(path)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
  state.snapshots = {}
end

local function invert_hunk_lines(lines)
  local out = {}
  for i, line in ipairs(lines) do
    local prefix = line:sub(1, 1)
    if prefix == '+' then
      out[i] = '-' .. line:sub(2)
    elseif prefix == '-' then
      out[i] = '+' .. line:sub(2)
    else
      out[i] = line
    end
  end
  return out
end

local function slice_diff(diff, file_idx, hunk_idx, reverse)
  local file = diff.files[file_idx]
  if not file then
    return nil
  end
  local hunk = file.hunks[hunk_idx]
  if not hunk then
    return nil
  end
  local lines = reverse and invert_hunk_lines(hunk.lines or {}) or (hunk.lines or {})
  return {
    kind = diff.kind,
    files = {
      {
        filename = file.filename,
        hunks = {
          { lines = lines },
        },
      },
    },
  }
end

function M.apply_diff(diff, anchor)
  local snapshots = {}
  local first_change = nil
  for _, file in ipairs(diff.files or {}) do
    local path = resolve_path(file.filename)
    if not path and anchor and anchor.path then
      path = resolve_path(anchor.path)
    end
    if not path then
      return false, 'File not found: ' .. file.filename
    end
    local buf = buffer_for(path)
    snapshots[path] = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  for _, file in ipairs(diff.files or {}) do
    local path = resolve_path(file.filename)
    if not path and anchor and anchor.path then
      path = resolve_path(anchor.path)
    end
    if not path then
      return false, 'File not found: ' .. file.filename
    end
    local buf = buffer_for(path)
    local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local anchor_line = nil
    local anchor_text = nil
    if anchor and anchor.path and anchor.line then
      local anchor_path = resolve_path(anchor.path)
      if anchor_path == path then
        anchor_line = anchor.line
        anchor_text = anchor.text
      end
    end
    for _, hunk in ipairs(file.hunks or {}) do
      local added, removed, prefix_ctx, suffix_ctx = extract_changes(hunk.lines)
      if #removed > 0 and #added > 0 then
        removed, added = strip_common_prefix(removed, added)
      end
      if #removed == 0 and #added > 0 then
        local insert_at = nil
        if #suffix_ctx > 0 then
          local idx = find_anchor_line(buf_lines, suffix_ctx[1])
          if idx then
            insert_at = idx
          end
        end
        if not insert_at and #prefix_ctx > 0 then
          local idx = find_anchor_line(buf_lines, prefix_ctx[#prefix_ctx])
          if idx then
            insert_at = idx + 1
          end
        end
        if not insert_at and anchor_line then
          insert_at = math.min(anchor_line, #buf_lines + 1)
        end
        if insert_at then
          vim.api.nvim_buf_set_lines(buf, insert_at - 1, insert_at - 1, false, added)
          local highlights = {}
          for i = 0, #added - 1 do
            table.insert(highlights, insert_at - 1 + i)
          end
          flash_lines(buf, highlights)
          if not first_change and #highlights > 0 then
            first_change = { path = path, line = highlights[1] + 1 }
          end
          anchor_line = insert_at + #added
          buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          goto continue
        end
      end
      if #removed > 0 then
        local idx = find_block(buf_lines, removed)
        if idx then
          vim.api.nvim_buf_set_lines(buf, idx - 1, idx - 1 + #removed, false, added)
          local highlights = {}
          for i = 0, #added - 1 do
            table.insert(highlights, idx - 1 + i)
          end
          flash_lines(buf, highlights)
          if not first_change and #highlights > 0 then
            first_change = { path = path, line = highlights[1] + 1 }
          end
          buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          goto continue
        end
      end
      local hunk_anchor_line = anchor_line
      local hunk_anchor_text = anchor_text
      if hunk.anchor then
        local found = find_anchor_line(buf_lines, hunk.anchor)
        if found then
          hunk_anchor_line = found
          hunk_anchor_text = hunk.anchor
        end
      end
      if hunk_anchor_line and not hunk_contains_text(hunk.lines, hunk_anchor_text) then
        local added_lines = hunk_anchor_lines(hunk.lines)
        if #added_lines > 0 then
          local insert_at = math.min(hunk_anchor_line, #buf_lines + 1)
          vim.api.nvim_buf_set_lines(buf, insert_at - 1, insert_at - 1, false, added_lines)
          local highlights = {}
          for i = 0, #added_lines - 1 do
            table.insert(highlights, insert_at - 1 + i)
          end
          flash_lines(buf, highlights)
          if not first_change and #highlights > 0 then
            first_change = { path = path, line = highlights[1] + 1 }
          end
          anchor_line = insert_at + #added_lines
          buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          goto continue
        end
      end
      local start_idx, span = find_hunk_start(buf_lines, hunk.lines)
      if not start_idx then
        if hunk_anchor_line and not hunk_has_context(hunk.lines) then
          local added_lines = hunk_added_lines(hunk.lines)
          if #added_lines == 0 then
            return false, 'No insertable lines found'
          end
          local insert_at = math.min(hunk_anchor_line, #buf_lines + 1)
          vim.api.nvim_buf_set_lines(buf, insert_at - 1, insert_at - 1, false, added_lines)
          local highlights = {}
          for i = 0, #added_lines - 1 do
            table.insert(highlights, insert_at - 1 + i)
          end
          flash_lines(buf, highlights)
          if not first_change and #highlights > 0 then
            first_change = { path = path, line = highlights[1] + 1 }
          end
          anchor_line = insert_at + #added_lines
          buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          goto continue
        end
        for restore_path, restore_lines in pairs(snapshots) do
          local restore_buf = buffer_for(restore_path)
          vim.api.nvim_buf_set_lines(restore_buf, 0, -1, false, restore_lines)
        end
        return false, 'Failed to match hunk context'
      end
      if hunk_anchor_line and hunk_only_additions(hunk.lines) then
        local added_lines = hunk_added_lines(hunk.lines)
        if #added_lines == 0 then
          return false, 'No insertable lines found'
        end
        local insert_at = math.min(hunk_anchor_line, #buf_lines + 1)
        vim.api.nvim_buf_set_lines(buf, insert_at - 1, insert_at - 1, false, added_lines)
        local highlights = {}
        for i = 0, #added_lines - 1 do
          table.insert(highlights, insert_at - 1 + i)
        end
        flash_lines(buf, highlights)
        if not first_change and #highlights > 0 then
          first_change = { path = path, line = highlights[1] + 1 }
        end
        anchor_line = insert_at + #added_lines
        buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        goto continue
      end
      local added, new_len = apply_hunk(buf, start_idx, span, hunk.lines)
      local highlights = {}
      for _, pos in ipairs(added) do
        table.insert(highlights, start_idx - 1 + pos - 1)
      end
      if #highlights == 0 and new_len > 0 then
        table.insert(highlights, math.max(0, start_idx - 1))
      end
      flash_lines(buf, highlights)
      if not first_change and #highlights > 0 then
        first_change = { path = path, line = highlights[1] + 1 }
      end
      buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      ::continue::
    end
  end
  state.snapshots = snapshots
  return true, nil, first_change
end

local function format_preview(diff)
  local out = {}
  local meta = {}
  local line_idx = 0
  for file_idx, file in ipairs(diff.files or {}) do
    line_idx = line_idx + 1
    out[line_idx] = ('Proposed change: %s'):format(file.filename)
    meta[line_idx] = { kind = 'header' }
    for hunk_idx, hunk in ipairs(file.hunks or {}) do
      for _, line in ipairs(hunk.lines or {}) do
        line_idx = line_idx + 1
        out[line_idx] = line
        meta[line_idx] = { file = file_idx, hunk = hunk_idx, line = line }
      end
    end
    line_idx = line_idx + 1
    out[line_idx] = ''
  end
  return out, meta
end

function M.preview(diff, on_accept)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'diff'
  local lines, meta = format_preview(diff)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_var(buf, 'hint_diff_meta', meta)
  vim.cmd 'botright 12split'
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win].wrap = false
  local function apply_and_close()
    local cursor = vim.api.nvim_win_get_cursor(win)[1]
    local info = meta[cursor]
    if not info or not info.line then
      return
    end
    local prefix = info.line:sub(1, 1)
    if prefix ~= '+' and prefix ~= '-' then
      return
    end
    local reverse = prefix == '-'
    local selected = slice_diff(diff, info.file, info.hunk, reverse)
    if selected and on_accept then
      on_accept(selected, reverse)
    end
  end
  vim.keymap.set('n', '<CR>', apply_and_close, { buffer = buf, silent = true })
  vim.keymap.set('n', 'y', apply_and_close, { buffer = buf, silent = true })
  vim.keymap.set('n', 'n', function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true })
  vim.keymap.set('n', 'q', function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true })
end

function M.jump(info, preferred_win)
  if not info or not info.path or not info.line then
    return
  end
  local buf = buffer_for(info.path)
  local win = preferred_win
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_cursor(win, { info.line, 0 })
    return
  end
  local open_win = vim.fn.bufwinid(buf)
  if open_win ~= -1 then
    vim.api.nvim_set_current_win(open_win)
    vim.api.nvim_win_set_cursor(open_win, { info.line, 0 })
    return
  end
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_cursor(0, { info.line, 0 })
end

return M
