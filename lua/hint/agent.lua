local config = require 'hint.config'
local state = require 'hint.state'
local util = require 'hint.util'
local context = require 'hint.context'
local provider = require 'hint.provider'
local patch = require 'hint.patch'
local tools = require 'hint.tools'
local status = require 'hint.ui.status'
local prompt_ui = require 'hint.ui.prompt'

local M = {}

local function current_file()
  local buf = vim.api.nvim_get_current_buf()
  return vim.api.nvim_buf_get_name(buf)
end

local function build_input(task, context_text, target_note)
  local note = target_note and target_note ~= '' and ('\n\n' .. target_note) or ''
  if context_text ~= '' then
    return context_text .. '\n\nTask:\n' .. task .. note
  end
  return 'Task:\n' .. task .. note
end

function M.set_model(index_or_name)
  local opts = config.get()
  local model = index_or_name
  if type(index_or_name) == 'number' then
    model = opts.models[index_or_name]
  end
  if model and model ~= '' then
    opts.model = model
    status.log('Model: ' .. model)
  end
end

function M.prompt()
  local selection = util.get_visual_selection()
  local comment = util.find_hint_comment(0, vim.api.nvim_win_get_cursor(0)[1])
  local lines = {}
  if comment then
    lines = { comment }
  end
  if selection then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', true)
  end
  prompt_ui.open({ lines = lines }, function(text)
    if text == '' then
      status.log 'Empty prompt'
      return
    end
    M.run(text, {
      selection = selection,
      file = current_file(),
      buf = vim.api.nvim_get_current_buf(),
      cursor = vim.api.nvim_win_get_cursor(0)[1],
      filetype = vim.bo[vim.api.nvim_get_current_buf()].filetype,
    })
  end)
end

function M.run_comment()
  local text = util.find_hint_comment(0, vim.api.nvim_win_get_cursor(0)[1])
  if not text then
    status.log 'No HINT comment found'
    return
  end
  M.run(text, {
    file = current_file(),
    buf = vim.api.nvim_get_current_buf(),
    cursor = vim.api.nvim_win_get_cursor(0)[1],
    filetype = vim.bo[vim.api.nvim_get_current_buf()].filetype,
  })
end

function M.run(text, ctx)
  state.main_win = vim.api.nvim_get_current_win()
  status.start 'Collecting context'
  local opts = config.get()
  local run_started = vim.loop.hrtime()
  if ctx and ctx.buf and ctx.cursor and vim.api.nvim_buf_is_valid(ctx.buf) then
    ctx.cursor_text = vim.api.nvim_buf_get_lines(ctx.buf, ctx.cursor - 1, ctx.cursor, false)[1] or ''
  end
  local context_text, extra = context.collect(text, ctx)
  context_text = context_text or ''
  if extra and #extra > 0 then
    status.log(('Context files: %d'):format(#extra))
  end
  local target_note = ''
  if ctx and ctx.file and ctx.file ~= '' then
    local cursor_text = ctx and ctx.cursor_text or nil
    if ctx.selection then
      target_note = ('Target file: %s (lines %d-%d). Modify only this region unless necessary.'):format(
        ctx.file,
        ctx.selection.start,
        ctx.selection['end']
      )
    else
      target_note = ('Target file: %s (cursor line %d). Insert near this line if needed.'):format(
        ctx.file,
        ctx.cursor or 1
      )
    end
    if ctx.filetype and ctx.filetype ~= '' then
      target_note = target_note .. (' Use %s.'):format(ctx.filetype)
    end
    if cursor_text then
      target_note = target_note .. (' Cursor line text: %s'):format(cursor_text)
    end
  end
  local base_input = build_input(text, context_text, target_note)
  state.debug = {
    prompt = base_input,
    response = nil,
    tool_history = '',
    tool_calls = nil,
    model = opts.model,
    file = ctx and ctx.file or nil,
    cursor = ctx and ctx.cursor or nil,
    duration_ms = nil,
    note = nil,
  }

  local function record_finish(note)
    state.debug.duration_ms = math.floor((vim.loop.hrtime() - run_started) / 1000000)
    state.debug.note = note
  end

  local request_count = 0
  local collected_patches = {}
  local tool_specs = nil
  if opts.tools.enabled and provider.tool_specs then
    tool_specs = provider.tool_specs()
  end
  local function extract_leading_status(text)
    if not text or text == '' then
      return {}, text
    end
    local out = {}
    local kept = {}
    local in_status = true
    for line in text:gmatch('[^\r\n]+') do
      if in_status then
        local trimmed = line:gsub('^%s+', ''):gsub('%s+$', '')
        if trimmed == '' then
          -- skip
        elseif trimmed:match('^patch%s*%(')
          or trimmed:match('^HINT_TOOL:')
          or trimmed == 'NO_CHANGES'
        then
          in_status = false
          table.insert(kept, line)
        else
          table.insert(out, trimmed)
        end
      else
        table.insert(kept, line)
      end
    end
    return out, table.concat(kept, '\n')
  end

  local function log_status_lines(lines)
    for _, msg in ipairs(lines) do
      status.log(msg)
    end
  end

  local function normalize_tool_calls(calls)
    local out = {}
    for _, call in ipairs(calls or {}) do
      local args = call.arguments or call.args or call.input or call.parameters
      if type(args) == 'string' then
        local ok, decoded = pcall(vim.json.decode, args)
        if ok then
          args = decoded
        end
      end
      table.insert(out, {
        name = call.name,
        arg = args,
        call_id = call.call_id, -- Use call_id for function_call_output
      })
    end
    return out
  end

  local function patches_to_diff(patches)
    local merged = {}
    local order = {}
    for _, p in ipairs(patches) do
      local path = p.path
      if not merged[path] then
        merged[path] = { filename = path, hunks = {} }
        table.insert(order, merged[path])
      end
      local lines = {}
      for _, line in ipairs(vim.split(p.match, '\n', { plain = true })) do
        table.insert(lines, '-' .. line)
      end
      for _, line in ipairs(vim.split(p.replace, '\n', { plain = true })) do
        table.insert(lines, '+' .. line)
      end
      table.insert(merged[path].hunks, { lines = lines })
    end
    return { kind = 'apply_patch', files = order }
  end

  local function handle_diff(diff)
    state.last_diff = diff
    local anchor = nil
    if ctx and ctx.file and ctx.cursor and not ctx.selection then
      anchor = { path = ctx.file, line = ctx.cursor, text = ctx.cursor_text }
    end
    local function apply_diff(selected)
      local ok, perr, info = patch.apply_diff(selected or diff, anchor)
      if not ok then
        record_finish('patch_failed')
        status.finish('Patch failed: ' .. perr)
        return
      end
      record_finish('applied_diff')
      status.finish 'Applied diff'
      if info then
        patch.jump(info, state.main_win)
      end
    end
    local function run()
      if opts.diff_preview then
        status.finish 'Diff ready (press Enter to apply)'
        patch.preview(diff, apply_diff)
      else
        apply_diff()
      end
    end
    if vim.in_fast_event() then
      vim.schedule(run)
    else
      run()
    end
  end

  -- Accumulating input list (following OpenAI docs pattern)
  local input_list = {
    { role = 'user', content = base_input },
  }

  local function request_loop(tool_steps)
    request_count = request_count + 1
    local max_steps = opts.tools.max_steps or 0

    -- Check tool limit
    if max_steps > 0 and tool_steps >= max_steps then
      if #collected_patches > 0 then
        handle_diff(patches_to_diff(collected_patches))
        return
      end
      record_finish('tool_limit')
      status.finish 'Tool loop limit reached'
      return
    end

    status.set_activity(('Calling model (%d): %s'):format(request_count, opts.model))

    provider.request({
      model = opts.model,
      input = input_list,
      temperature = opts.temperature,
      tools = tool_specs,
      tool_choice = opts.tools.enabled and 'auto' or nil,
    }, function(err, response)
      if err then
        state.debug.response = err
        record_finish('error')
        status.finish('Error: ' .. err)
        return
      end

      local resp_text = ''
      local resp_tools = {}
      local resp_output = {}

      if type(response) == 'table' then
        resp_text = response.text or ''
        resp_tools = response.tool_calls or {}
        resp_output = response.output or {}
      else
        resp_text = response or ''
      end

      -- Extract status lines from response
      local cleaned = resp_text
      if resp_text ~= '' then
        local status_lines
        status_lines, cleaned = extract_leading_status(resp_text)
        log_status_lines(status_lines)
      end

      state.last_response = cleaned
      state.debug.response = resp_text

      -- Check for inline diff in response
      local diff = patch.parse_diff(cleaned, { default_path = ctx and ctx.file or nil })
      if diff then
        handle_diff(diff)
        return
      end

      -- Normalize tool calls from response
      local tool_calls = normalize_tool_calls(resp_tools)
      -- Also check for legacy text-based tool calls
      if #tool_calls == 0 then
        tool_calls = tools.parse(cleaned)
      end
      state.debug.tool_calls = tool_calls

      -- No tool calls - we're done
      if #tool_calls == 0 then
        if #collected_patches > 0 then
          handle_diff(patches_to_diff(collected_patches))
          return
        end
        if cleaned:match('NO_CHANGES') then
          record_finish('no_changes')
          status.finish 'No changes requested'
          return
        end
        if cleaned ~= '' then
          record_finish('answer')
          status.finish 'Answer ready (use :HintShow)'
          return
        end
        record_finish('invalid_response')
        status.finish 'No patch found. Use :HintShow'
        return
      end

      -- Tools disabled
      if not opts.tools.enabled then
        status.log 'Tools disabled; ignoring tool request'
        record_finish('tools_disabled')
        status.finish 'Tools disabled'
        return
      end

      -- Run tools
      status.set_activity(('Running tools (%d)'):format(#tool_calls))
      for _, call in ipairs(tool_calls) do
        status.log(('Tool: %s'):format(call.name))
      end

      local function run_tools()
        local data = tools.run_calls(tool_calls)
        state.debug.tool_history = vim.inspect(data.results)

        -- Collect patches
        for _, p in ipairs(data.patches) do
          table.insert(collected_patches, p)
        end

        -- Accumulate input per OpenAI docs:
        -- 1. Add response.output to input_list
        for _, item in ipairs(resp_output) do
          table.insert(input_list, item)
        end
        -- 2. Add function_call_output items
        local tool_outputs = tools.format_tool_outputs(data.results)
        for _, item in ipairs(tool_outputs) do
          table.insert(input_list, item)
        end

        -- Continue the loop
        request_loop(tool_steps + 1)
      end

      if vim.in_fast_event() then
        vim.schedule(run_tools)
      else
        run_tools()
      end
    end)
  end

  -- Start the loop
  request_loop(0)
end

function M.show_tools()
  local text = state.last_tool_output
  if not text or text == '' then
    status.log 'No tool output'
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'hinttools'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, '\n', { plain = true }))
  vim.cmd 'botright 12split'
  vim.api.nvim_win_set_buf(0, buf)
end

function M.show_debug()
  local dbg = state.debug or {}
  local lines = {}
  local function add_line(text)
    table.insert(lines, text)
  end
  local function add_block(title, value)
    add_line(title)
    if value and value ~= '' then
      local text = type(value) == 'string' and value or vim.inspect(value)
      for _, line in ipairs(vim.split(text, '\n', { plain = true })) do
        table.insert(lines, line)
      end
    end
    add_line('')
  end

  add_line(('Model: %s'):format(dbg.model or ''))
  add_line(('File: %s'):format(dbg.file or ''))
  add_line(('Cursor: %s'):format(dbg.cursor or ''))
  add_line(('Duration: %s ms'):format(dbg.duration_ms or ''))
  add_line(('Note: %s'):format(dbg.note or ''))
  add_line('')

  add_block('--- Prompt ---', dbg.prompt)
  add_block('--- Tool Calls ---', dbg.tool_calls)
  add_block('--- Tool History ---', dbg.tool_history)
  add_block('--- Response ---', dbg.response)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'hintdebug'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.cmd 'botright 12split'
  vim.api.nvim_win_set_buf(0, buf)
end

function M.show_diff()
  local diff = state.last_diff
  if not diff then
    status.log 'No diff available'
    return
  end
  local function apply_diff(selected)
    local ok, perr = patch.apply_diff(selected or diff)
    if not ok then
      status.finish('Patch failed: ' .. perr)
      return
    end
    status.finish 'Applied diff'
  end
  if vim.in_fast_event() then
    vim.schedule(function()
      patch.preview(diff, apply_diff)
    end)
  else
    patch.preview(diff, apply_diff)
  end
end

function M.show_last()
  local text = state.last_response
  if not text or text == '' then
    status.log 'No response yet'
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'markdown'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, '\n'))
  vim.cmd 'botright 12split'
  vim.api.nvim_win_set_buf(0, buf)
end

function M.rollback()
  patch.rollback()
  status.log 'Rolled back last apply'
end

return M
