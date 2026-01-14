local Job = require 'plenary.job'
local config = require 'hint.config'

local M = {}

local function tool_specs()
  return {
    {
      type = 'function',
      name = 'rg',
      description = 'Search the repository using ripgrep.',
      strict = true,
      parameters = {
        type = 'object',
        additionalProperties = false,
        properties = {
          query = { type = 'string', description = 'Search pattern.' },
        },
        required = { 'query' },
      },
    },
    {
      type = 'function',
      name = 'read',
      description = 'Read a file, optionally with a line range.',
      strict = true,
      parameters = {
        type = 'object',
        additionalProperties = false,
        properties = {
          path = { type = 'string', description = 'File path.' },
          range = { type = { 'string', 'null' }, description = 'Line range like 5-20.' },
        },
        required = { 'path', 'range' },
      },
    },
    {
      type = 'function',
      name = 'ls',
      description = 'List directory entries.',
      strict = true,
      parameters = {
        type = 'object',
        additionalProperties = false,
        properties = {
          path = { type = 'string', description = 'Directory path.' },
        },
        required = { 'path' },
      },
    },
    {
      type = 'function',
      name = 'patch',
      description = 'Queue a textual replacement in a file. The patch will be presented to the user for review and applied after the tool loop ends.',
      strict = true,
      parameters = {
        type = 'object',
        additionalProperties = false,
        properties = {
          path = { type = 'string', description = 'File path.' },
          match = { type = 'string', description = 'Exact text to replace.' },
          replace = { type = 'string', description = 'Replacement text.' },
        },
        required = { 'path', 'match', 'replace' },
      },
    },
  }
end

local SYSTEM_PROMPT = [[You are a coding agent. You MUST use tool calls to make changes.

IMPORTANT: Do NOT output diffs or code blocks in text. ALWAYS use the patch tool to make changes.

Available tools:
- rg: Search code with ripgrep
- read: Read file contents
- ls: List directory
- patch: Apply text replacement (MUST use this for any code changes)

For patch tool: match must be exact text from the file. Use \\n for newlines in JSON.
Never ask questions. If no change needed, return "NO_CHANGES".]]

local function extract_text(payload)
  if type(payload.output_text) == 'string' and payload.output_text ~= '' then
    return payload.output_text
  end
  if type(payload.output) ~= 'table' then
    return nil
  end
  local chunks = {}
  for _, item in ipairs(payload.output) do
    if type(item.output_text) == 'string' and item.output_text ~= '' then
      table.insert(chunks, item.output_text)
    end
    local content = item.content
    if type(content) == 'table' then
      for _, part in ipairs(content) do
        if type(part.text) == 'string' and part.text ~= '' then
          table.insert(chunks, part.text)
        elseif type(part.output_text) == 'string' and part.output_text ~= '' then
          table.insert(chunks, part.output_text)
        end
      end
    end
  end
  local out = table.concat(chunks, '')
  if out == '' then
    return nil
  end
  return out
end

local function extract_tool_calls(payload)
  local out = {}
  for _, item in ipairs(payload.output or {}) do
    if type(item) == 'table' and item.type == 'function_call' then
      table.insert(out, {
        name = item.name,
        arguments = item.arguments,
        call_id = item.call_id, -- Use call_id for function_call_output
      })
    end
  end
  return out
end

local function build_data(opts)
  local data = {
    model = opts.model,
  }

  -- Input is the accumulated input list
  -- Use 'developer' role for system instructions (per API spec)
  local input = opts.input
  if type(input) == 'string' then
    data.input = {
      { role = 'developer', content = SYSTEM_PROMPT },
      { role = 'user', content = input },
    }
  elseif type(input) == 'table' then
    -- Check if developer message already present
    local has_developer = false
    for _, item in ipairs(input) do
      if type(item) == 'table' and item.role == 'developer' then
        has_developer = true
        break
      end
    end
    if not has_developer then
      -- Prepend developer message
      local new_input = { { role = 'developer', content = SYSTEM_PROMPT } }
      for _, item in ipairs(input) do
        table.insert(new_input, item)
      end
      data.input = new_input
    else
      data.input = input
    end
  end

  if opts.tools then
    data.tools = opts.tools
  end
  if opts.tool_choice then
    data.tool_choice = opts.tool_choice
  end
  if opts.temperature ~= nil then
    data.temperature = opts.temperature
  end
  return data
end

local function make_request(opts, cb, allow_retry)
  local api_key = opts.api_key or os.getenv 'OPENAI_API_KEY'
  if not api_key or api_key == '' then
    cb('OPENAI_API_KEY is not set')
    return
  end

  local data = build_data(opts)

  local args = {
    '-sS',
    '-X',
    'POST',
    '-H',
    'Content-Type: application/json',
    '-H',
    'Authorization: Bearer ' .. api_key,
    '-d',
    vim.json.encode(data),
    'https://api.openai.com/v1/responses',
  }

  Job:new({
    command = 'curl',
    args = args,
    on_exit = function(job, code)
      local raw = table.concat(job:result(), '\n')
      local stderr = table.concat(job:stderr_result(), '\n')
      if code ~= 0 then
        if allow_retry and stderr:find('Unsupported parameter') and opts.temperature ~= nil then
          opts.temperature = nil
          make_request(opts, cb, false)
          return
        end
        cb(stderr ~= '' and stderr or 'Request failed')
        return
      end
      if raw == '' then
        cb(stderr ~= '' and stderr or 'Empty response')
        return
      end
      local ok, payload = pcall(vim.json.decode, raw)
      if not ok then
        cb('Failed to parse response')
        return
      end
      if type(payload.error) == 'table' and payload.error.message then
        if allow_retry and payload.error.message:find('Unsupported parameter') and opts.temperature ~= nil then
          opts.temperature = nil
          make_request(opts, cb, false)
          return
        end
        cb(payload.error.message)
        return
      end
      local text = extract_text(payload) or ''
      local tool_calls = extract_tool_calls(payload)
      local output = payload.output or {}

      if text == '' and #tool_calls == 0 and #output == 0 then
        cb('Empty response')
        return
      end
      cb(nil, {
        text = text,
        tool_calls = tool_calls,
        output = output,
      })
    end,
  }):start()
end

function M.request(opts, cb)
  make_request(opts, cb, true)
end

function M.tool_specs()
  return tool_specs()
end

return M
