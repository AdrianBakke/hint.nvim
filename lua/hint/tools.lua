local config = require 'hint.config'
local util = require 'hint.util'

local M = {}

local function trim(s)
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function normalize_path(path)
  if path == '' then
    return ''
  end
  local root = vim.fn.getcwd()
  local full = vim.fn.fnamemodify(path, ':p')
  if vim.fn.filereadable(full) == 1 and full:sub(1, #root) == root then
    return full
  end
  local found = vim.fn.findfile(path, root .. '/**')
  if found ~= '' then
    return vim.fn.fnamemodify(found, ':p')
  end
  local base = vim.fn.fnamemodify(path, ':t')
  found = vim.fn.findfile(base, root .. '/**')
  if found ~= '' then
    return vim.fn.fnamemodify(found, ':p')
  end
  return ''
end

local function parse_range(arg)
  local path, start_line, end_line = arg:match('^(.-):(%d+)%-(%d+)$')
  if path then
    return trim(path), tonumber(start_line), tonumber(end_line)
  end
  path, start_line = arg:match('^(.-):(%d+)$')
  if path then
    return trim(path), tonumber(start_line), tonumber(start_line)
  end
  path, start_line, end_line = arg:match('^(.-)%s+(%d+)%-(%d+)$')
  if path then
    return trim(path), tonumber(start_line), tonumber(end_line)
  end
  path, start_line = arg:match('^(.-)%s+(%d+)$')
  if path then
    return trim(path), tonumber(start_line), tonumber(start_line)
  end
  return trim(arg), nil, nil
end

local function format_lines(lines, start_line)
  local out = {}
  for i, line in ipairs(lines) do
    out[i] = string.format('%d: %s', start_line + i - 1, line)
  end
  return table.concat(out, '\n')
end

function M.parse(text)
  local calls = {}
  if not text or text == '' then
    return calls
  end
  for line in text:gmatch('[^\r\n]+') do
    local name, rest = line:match('^HINT_TOOL:%s*(%S+)%s*(.*)$')
    if name then
      local arg = trim(rest or '')
      arg = arg:gsub('[^%g%s]', '')
      if arg ~= '' then
        table.insert(calls, { name = name, arg = arg })
      end
    end
  end
  return calls
end

local function run_rg(query)
  if query == '' then
    return 'rg: missing query'
  end
  if vim.fn.executable 'rg' ~= 1 then
    return 'rg: not available'
  end
  local opts = config.get().context
  local cmd = { 'rg', '--no-heading', '-n', '--max-count', '50', '--hidden' }
  for _, glob in ipairs(opts.ignore or {}) do
    table.insert(cmd, '--glob')
    table.insert(cmd, '!' .. glob)
  end
  table.insert(cmd, '--')
  table.insert(cmd, query)
  table.insert(cmd, vim.fn.getcwd())
  local ok, res = pcall(vim.fn.systemlist, cmd)
  if not ok then
    return 'rg: failed'
  end
  if #res == 0 then
    return 'rg: no matches'
  end
  return table.concat(res, '\n')
end

local function run_read(path)
  local raw_path, start_line, end_line = parse_range(path)
  local full = normalize_path(raw_path)
  if full == '' then
    return 'read: invalid path'
  end
  local buf = vim.fn.bufnr(full, false)
  if buf > 0 and vim.api.nvim_buf_is_loaded(buf) then
    local total = vim.api.nvim_buf_line_count(buf)
    local from = start_line or 1
    local to = end_line or total
    if to < from then
      return 'read: empty range'
    end
    local lines = vim.api.nvim_buf_get_lines(buf, from - 1, to, false)
    if start_line and end_line then
      local body = format_lines(lines, from)
      return util.truncate(body, config.get().tools.max_output_bytes)
    end
    return util.truncate(table.concat(lines, '\n'), config.get().tools.max_output_bytes)
  end
  if start_line and end_line then
    local ok, lines = pcall(vim.fn.readfile, full)
    if not ok or not lines then
      return 'read: failed'
    end
    local from = math.max(1, start_line)
    local to = math.min(#lines, end_line)
    if to < from then
      return 'read: empty range'
    end
    local slice = {}
    for i = from, to do
      slice[#slice + 1] = lines[i]
    end
    local body = format_lines(slice, from)
    return util.truncate(body, config.get().tools.max_output_bytes)
  end
  local content = util.read_file(full, config.get().tools.max_output_bytes)
  if not content then
    return 'read: failed'
  end
  return content
end

local function run_ls(path)
  local full = normalize_path(path == '' and '.' or path)
  if full == '' then
    return 'ls: invalid path'
  end
  local ok, entries = pcall(vim.fn.readdir, full)
  if not ok then
    return 'ls: failed'
  end
  return table.concat(entries, '\n')
end

local function normalize_arg(call)
  if type(call.arg) == 'table' then
    return call.arg
  end
  -- Legacy string arg format
  if call.name == 'rg' then
    return { query = call.arg or '' }
  end
  if call.name == 'read' then
    return { path = call.arg or '' }
  end
  if call.name == 'ls' then
    return { path = call.arg or '.' }
  end
  if call.name == 'patch' then
    return {}
  end
  return {}
end

local function run_patch(arg)
  -- Validate patch args
  local path = arg.path
  local match = arg.match or arg.find or arg.from
  local replace = arg.replace or arg.to
  if not path or path == '' then
    return { error = 'patch: missing path' }
  end
  if type(match) ~= 'string' then
    return { error = 'patch: missing match' }
  end
  if type(replace) ~= 'string' then
    return { error = 'patch: missing replace' }
  end
  -- Return patch data for agent to apply
  return {
    patch = {
      path = path,
      match = match,
      replace = replace,
    },
  }
end

-- Run a single tool call, returns { output = string } or { patch = {...} } or { error = string }
local function run_tool(name, arg)
  if name == 'rg' then
    local query = arg.query or arg.pattern or ''
    return { output = run_rg(query) }
  elseif name == 'read' then
    local path = arg.path or ''
    local range = arg.range or arg.lines or arg.line_range
    if range and range ~= '' then
      path = path .. ':' .. range
    end
    return { output = run_read(path) }
  elseif name == 'ls' then
    local path = arg.path or '.'
    return { output = run_ls(path) }
  elseif name == 'patch' then
    return run_patch(arg)
  end
  return { error = 'tool: unsupported' }
end

-- Run tool calls and return structured results
-- Returns: { results = [{call_id, name, output?, patch?}], patches = [...] }
function M.run_calls(calls)
  local results = {}
  local patches = {}
  local max_bytes = config.get().tools.max_output_bytes

  for _, call in ipairs(calls) do
    local arg = normalize_arg(call)
    local result = run_tool(call.name, arg)

    local entry = {
      call_id = call.call_id, -- Use call_id for function_call_output
      name = call.name,
    }

    if result.error then
      entry.output = result.error
    elseif result.patch then
      table.insert(patches, result.patch)
      entry.output = 'patch: queued'
      entry.patch = result.patch
    elseif result.output then
      entry.output = util.truncate(result.output, max_bytes)
    end

    table.insert(results, entry)
  end

  return { results = results, patches = patches }
end

-- Format results as function_call_output items for OpenAI Responses API
function M.format_tool_outputs(results)
  local outputs = {}
  for _, r in ipairs(results) do
    if r.call_id then
      table.insert(outputs, {
        type = 'function_call_output',
        call_id = r.call_id,
        output = r.output or '',
      })
    end
  end
  return outputs
end

-- Legacy: run calls and return text summary
function M.run(calls)
  local data = M.run_calls(calls)
  local blocks = {}
  for _, r in ipairs(data.results) do
    local header = ('[%s]'):format(r.name)
    table.insert(blocks, header .. '\n' .. (r.output or ''))
  end
  return table.concat(blocks, '\n\n')
end

return M
