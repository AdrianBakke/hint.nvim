local config = require 'hint.config'
local util = require 'hint.util'

local M = {}

local stopwords = {
  ['and'] = true,
  ['the'] = true,
  ['this'] = true,
  ['that'] = true,
  ['with'] = true,
  ['from'] = true,
  ['local'] = true,
  ['function'] = true,
  ['return'] = true,
  ['table'] = true,
}

local function extract_keywords(text, max)
  local out, seen = {}, {}
  for word in text:lower():gmatch('%w+') do
    if #word >= 4 and not stopwords[word] and not seen[word] then
      table.insert(out, word)
      seen[word] = true
      if #out >= max then
        break
      end
    end
  end
  return out
end

local function rg_files(keyword, root, ignore)
  if vim.fn.executable 'rg' ~= 1 then
    return {}
  end
  local cmd = { 'rg', '-l', '--max-count', '1', '--hidden' }
  for _, glob in ipairs(ignore or {}) do
    table.insert(cmd, '--glob')
    table.insert(cmd, '!' .. glob)
  end
  table.insert(cmd, keyword)
  table.insert(cmd, root)
  local ok, res = pcall(vim.fn.systemlist, cmd)
  if not ok then
    return {}
  end
  return res
end

local function file_block(path, content)
  return ('### %s\n%s'):format(path, content or '')
end

local function numbered_block(path, lines, start_line)
  local out = {}
  for i, line in ipairs(lines) do
    out[i] = string.format('%d: %s', start_line + i - 1, line)
  end
  local last = start_line + #lines - 1
  return ('### %s (lines %d-%d)\n%s'):format(path, start_line, last, table.concat(out, '\n'))
end

local function slice_lines(lines, first, last)
  local out = {}
  for i = first, last do
    out[#out + 1] = lines[i] or ''
  end
  return out
end

function M.collect(prompt, ctx)
  local opts = config.get().context
  local parts, files = {}, {}
  local total = 0

  if ctx and ctx.selection then
    local sel = ctx.selection
    local header = ('### Selection (%s:%d-%d)'):format(ctx.file or 'buffer', sel.start, sel['end'])
    table.insert(parts, header .. '\n' .. sel.text)
  end

  if ctx and ctx.file and ctx.file ~= '' then
    local lines = nil
    if ctx.buf and vim.api.nvim_buf_is_valid(ctx.buf) then
      lines = vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false)
    else
      local content = util.read_file(ctx.file, opts.max_bytes)
      if content then
        lines = vim.split(content, '\n', { plain = true })
      end
    end
    if lines then
      local total_lines = #lines
      local radius = opts.snippet_radius or 40
      local anchor = ctx.cursor or (ctx.selection and ctx.selection.start) or 1
      local first = math.max(1, anchor - radius)
      local last = math.min(total_lines, anchor + radius)
      if ctx.selection then
        first = math.max(1, ctx.selection.start - radius)
        last = math.min(total_lines, ctx.selection['end'] + radius)
      end
      local snippet = slice_lines(lines, first, last)
      if #snippet > 0 then
        table.insert(parts, numbered_block(ctx.file, snippet, first))
      end
      if ctx.cursor and not ctx.selection then
        table.insert(parts, ('### Cursor: %s:%d'):format(ctx.file, ctx.cursor))
      end
      if opts.include_current_full then
        local content = util.truncate(table.concat(lines, '\n'), opts.max_bytes)
        total = total + #content
        table.insert(parts, file_block(ctx.file, content))
      end
      files[ctx.file] = true
    end
  end

  local root = vim.fn.getcwd()
  local keywords = extract_keywords(prompt, 6)
  local extra = {}
  for _, word in ipairs(keywords) do
    for _, path in ipairs(rg_files(word, root, opts.ignore)) do
      if not files[path] then
        table.insert(extra, path)
        files[path] = true
        if #extra >= opts.max_files then
          break
        end
      end
    end
    if #extra >= opts.max_files then
      break
    end
  end

  if ctx and ctx.file and ctx.file ~= '' then
    local ext = ctx.file:match('%.([%w]+)$')
    if ext then
      local filtered = {}
      for _, path in ipairs(extra) do
        if path:match('%.' .. ext .. '$') or (ext == 'ts' and path:match('%.tsx$')) then
          table.insert(filtered, path)
        end
      end
      extra = filtered
    end
  end

  if #extra > 0 then
    table.insert(parts, '### Related files:\n' .. table.concat(extra, '\n'))
  end

  return table.concat(parts, '\n\n'), extra
end

return M
