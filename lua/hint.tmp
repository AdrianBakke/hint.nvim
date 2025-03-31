local M = {}
local Job = require 'plenary.job'

-- Utility Functions
local function get_api_key(name)
  return os.getenv(name)
end

local main_win = vim.api.nvim_get_current_win() -- Track main window

-- Namespace for highlights (if needed in future)
local namespace_id = vim.api.nvim_create_namespace 'hint_llm_output'

-- State Management
local state = {
  win_obj = nil,
  tabs = {},
  current_tab = 1,
  active_job = nil,
  cursor_positions = {},
}

local ntabs = 0
local tab_buf = vim.api.nvim_create_buf(false, true)

local function create_or_update_window()
  -- Check if there is at least one tab
  if #state.tabs == 0 then
    table.insert(state.tabs, { name = 'Tab 1', buf = vim.api.nvim_create_buf(false, true) })
    state.current_tab = 1
  end

  local current_tab = state.tabs[state.current_tab]
  local buf = current_tab.buf

  if state.win_obj == nil then
    -- Define dimensions for the windows
    local width = math.floor(vim.o.columns * 0.8)
    local height = math.floor(vim.o.lines * 0.8)

    -- Create window for the main content
    local win = vim.api.nvim_open_win(buf, true, {
      relative = 'editor',
      width = width - 2,
      height = height - 2,
      col = math.floor((vim.o.columns - width) / 2),
      row = math.floor((vim.o.lines - height) / 2) + 1, -- Adjust row to accommodate tab bar
      style = 'minimal',
      border = {
        { '╭', 'FloatBorder' },
        { '─', 'FloatBorder' },
        { '╮', 'FloatBorder' },
        { '│', 'FloatBorder' },
        { '╯', 'FloatBorder' },
        { '─', 'FloatBorder' },
        { '╰', 'FloatBorder' },
        { '│', 'FloatBorder' },
      },
    })

    -- Create window for the tab bar
    local tab_win = vim.api.nvim_open_win(tab_buf, false, {
      relative = 'editor',
      width = width,
      height = 1, -- Only one line for the tab bar
      col = math.floor((vim.o.columns - width) / 2),
      row = math.floor((vim.o.lines - height) / 2), -- Position above the main content window
      style = 'minimal',
      border = 'none',
    })

    -- Store window objects
    state.win_obj = {
      win = win,
      tab_win = tab_win,
      close = function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
        if vim.api.nvim_win_is_valid(tab_win) then
          vim.api.nvim_win_close(tab_win, true)
        end
        state.win_obj = nil -- Set to nil after closing
      end,
    }

    -- Set window options for the main content
    vim.wo[state.win_obj.win].wrap = true
    vim.wo[state.win_obj.win].number = false
    vim.wo[state.win_obj.win].relativenumber = false
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].modifiable = true
    vim.bo[buf].filetype = 'markdown'
  end

  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '', { callback = M.close_current_tab, noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Tab>', '', { callback = M.next_tab, noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<S-Tab>', '', { callback = M.prev_tab, noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<C-j>', '', { callback = M.toggle_window, noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<leader>tt', '', { callback = M.create_new_tab, noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<leader>i', '', { callback = M.insert_codeblock, noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<leader>ir', '', { callback = M.rollback_insert, noremap = true, silent = true })

  vim.api.nvim_win_set_buf(state.win_obj.win, buf)
  local line_count = vim.api.nvim_buf_line_count(buf)
  local cursor_pos = state.cursor_positions[state.current_tab] or { 1, 0 }
  vim.api.nvim_win_set_cursor(state.win_obj.win, cursor_pos)
end

-- Function to Render Tabs
local function render_tabs()
  if not state.win_obj or not vim.api.nvim_win_is_valid(state.win_obj.tab_win) then
    return
  end

  -- Render Tab Bar in the tab buffer
  local tab_line = ' '
  for i, tab in ipairs(state.tabs) do
    if i == state.current_tab then
      tab_line = tab_line .. '  ' .. tab.name .. '  '
    else
      tab_line = tab_line .. '  ' .. tab.name .. '  '
    end
  end
  vim.api.nvim_buf_set_option(tab_buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(tab_buf, 0, -1, false, { tab_line })
  vim.api.nvim_buf_add_highlight(tab_buf, namespace_id, 'TabLine', 0, 0, -1)
  vim.api.nvim_buf_set_option(tab_buf, 'modifiable', false)
end

function write_to_window(str)
  vim.schedule(function()
    if not state.win_obj or not vim.api.nvim_win_is_valid(state.win_obj.win) then
      state.win_obj = create_output_window()
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

    local ns = namespace_id
    for i = before_line, current_line_count - 1 do
      vim.api.nvim_buf_add_highlight(buf, ns, 'NormalFloat', i, 0, -1)
    end

    vim.api.nvim_win_set_cursor(state.win_obj.win, { current_line_count, 0 })
  end)
end

-- Public Functions for Tab Navigation
function M.next_tab()
  if #state.tabs == 0 then
    return
  end
  state.cursor_positions[state.current_tab] = vim.api.nvim_win_get_cursor(state.win_obj.win)
  state.current_tab = state.current_tab % #state.tabs + 1
  create_or_update_window()
  render_tabs()
end

function M.prev_tab()
  if #state.tabs == 0 then
    return
  end
  state.cursor_positions[state.current_tab] = vim.api.nvim_win_get_cursor(state.win_obj.win)
  state.current_tab = (state.current_tab - 2) % #state.tabs + 1
  create_or_update_window()
  render_tabs()
end

local function rename_tabs()
  -- Go through all tabs and rename them.
  for i, _ in ipairs(state.tabs) do
    state.tabs[i].name = 'Tab ' .. i
  end
end

-- Function to Close Current Tab
function M.close_current_tab()
  if #state.tabs == 0 then
    return
  end
  table.remove(state.tabs, state.current_tab)
  table.remove(state.cursor_positions, state.current_tab)
  if state.current_tab > #state.tabs then
    state.current_tab = #state.tabs
  end
  if #state.tabs == 0 then
    state.win_obj.close()
    state.win_obj = nil
  else
    rename_tabs()
    create_or_update_window()
    render_tabs()
  end
end

-- Function to Toggle Floating Window
function M.toggle_window()
  if state.win_obj and vim.api.nvim_win_is_valid(state.win_obj.win) then
    state.cursor_positions[state.current_tab] = vim.api.nvim_win_get_cursor(state.win_obj.win)
    state.win_obj.close()
    state.win_obj = nil
  else
    main_win = vim.api.nvim_get_current_win()
    create_or_update_window()
    render_tabs()
    local cursor_pos = state.cursor_positions[state.current_tab] or { 1, 0 }
    vim.api.nvim_win_set_cursor(state.win_obj.win, cursor_pos)
  end
end

function M.create_new_tab(name)
  if #state.tabs > 9 then
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  table.insert(state.tabs, { name = 'Tab ' .. (#state.tabs + 1), buf = buf })
  state.current_tab = #state.tabs
  create_or_update_window()
  render_tabs()
  return buf
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
      table.insert(lines, vim.api.nvim_buf_get_text(0, i - 1, math.min(scol - 1, ecol), i - 1, math.max(scol - 1, ecol), {})[1])
    end
    return lines
  end
end

local function get_lines_until_cursor()
  -- Validate main window reference
  -- Get main window's buffer and cursor position
  local main_buf = vim.api.nvim_win_get_buf(main_win)
  local cursor_pos = vim.api.nvim_win_get_cursor(main_win)
  local end_row = cursor_pos[1] -- 1-based index

  -- Extract lines from start to cursor position (0-based, exclusive end)
  local lines = vim.api.nvim_buf_get_lines(main_buf, 0, end_row, true)

  if state.tabs and vim.api.nvim_buf_is_valid(state.tabs[state.current_tab].buf) then
    local buff_lines = vim.api.nvim_buf_get_lines(state.tabs[state.current_tab].buf, 0, -1, true)
    table.insert(lines, '') -- add a separator
    vim.list_extend(lines, buff_lines)
  end

  return table.concat(lines, '\n')
end
local function handle_openai_spec_data(data_stream, event)
  if data_stream == '[DONE]' then
    write_to_window '\n\n--------[Stream complete Press CTRL-j to hide or q to close]--------\n\n'
    return
  end

  local success, json = pcall(vim.json.decode, data_stream)

  print(vim.inspect(json))

  if success then
    if json.choices and json.choices[1] then
      local choice = json.choices[1]

      if choice.delta then
        -- Process content
        if choice.delta.content and choice.delta.content ~= vim.NIL then
          write_to_window(choice.delta.content)
        end

        -- Process reasoning_content
        if choice.delta.reasoning_content and choice.delta.reasoning_content ~= vim.NIL then
          write_to_window(choice.delta.reasoning_content)
        end
      end

      -- Handle finish_reason if necessary
      if choice.finish_reason == 'stop' then
        --write_to_window '\n\n--------[Stream complete Press CTRL-j to hide or q to close]--------\n\n'
        -- Additional finalization if needed
        return
      end
    else
      print 'No content found in the response'
    end
  else
    print('Failed to parse JSON response:', data_stream)
  end
end

-- Functions to Create Curl Arguments
local function make_spec_curl_args(opts, prompt, api_key)
  local url = opts.url
  local data = {
    messages = {
      {
        role = 'system',
        content = 'You are HINT (Higher INTelligence) the coolest computer in the world. '
          .. 'You love to code, swear and use emojis. '
          .. 'You format code in markdown codeblocks. '
          .. 'When providing codeblocks, ensure you specify the exact lines where the code should be added startline: <the number> directly above the codeblock. '
          .. 'It must appear directly above the codeblock, immediately before the opening of the codeblock, on its own line. '
          .. 'example: \nstartline: number\n```code```)'
          .. 'Make sure to calculate and provide the correct line numbers based on the current script.'
          .. 'Other than that, you are a joy to have a conversation with. '
          .. prompt,
      },
      { role = 'user', content = prompt },
    },
    model = opts.model,
    temperature = 0.7,
    stream = true,
  }
  local args = { '-N', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', vim.json.encode(data) }

  if api_key then
    table.insert(args, '-H')
    table.insert(args, 'Authorization: Bearer ' .. api_key)
  end
  table.insert(args, url)
  return args
end

local function make_spec_curl_args_reasoner(opts, prompt, api_key)
  local url = opts.url
  local data = {
    messages = {
      {
        role = 'user',
        content = 'You are HINT (Higher INTelligence) the coolest computer in the world. '
          .. 'You love to code, swear and use emojis. '
          .. 'You format code in markdown codeblocks. '
          .. 'When providing codeblocks, ensure you specify the exact lines where the code should be added startline: <the number> directly above the codeblock. '
          .. 'It must appear directly above the codeblock, immediately before the opening of the codeblock, on its own line. '
          .. 'example: \nstartline: number\n```code```)'
          .. 'Make sure to calculate and provide the correct line numbers based on the current script.'
          .. 'Other than that, you are a joy to have a conversation with. '
          .. prompt,
      },
    },
    model = opts.model,
    stream = true,
  }
  local args = { '-N', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', vim.json.encode(data) }

  if api_key then
    table.insert(args, '-H')
    table.insert(args, 'Authorization: Bearer ' .. api_key)
  end
  table.insert(args, url)
  print(vim.inspect(args))
  return args
end

local function openai_make_curl_args(opts, prompt)
  local api_key = get_api_key 'OPENAI_API_KEY'
  return make_spec_curl_args(opts, prompt, api_key)
end

local function apply_diff(buffer, diff)
  local lines = vim.split(diff, '\n')

  for _, line in ipairs(lines) do
    if line:match '^@@' then
      -- Parse the context and determine where to apply the changes
      -- Example: @@ -2,6 +2,12 @@
      local _, _, start_line, old_count, new_count = line:find '@@ -(%d+),(%d+) +(%d+),(%d+) @@'
      start_line = tonumber(start_line) or 1
    elseif line:match '^+' then
      -- This is a line to add
      local content = line:sub(2) -- Remove the '+' character
      vim.api.nvim_buf_set_lines(buffer, start_line - 1, start_line - 1, false, { content })
      start_line = start_line + 1
    elseif line:match '^%-' then
      -- This is a line to remove
      vim.api.nvim_buf_set_lines(buffer, start_line - 1, start_line, false, {})
    else
      -- Context lines, just move the pointer
      start_line = start_line + 1
    end
  end
end

function M.insert_codeblock()
  -- Get main buffer reference
  local main_buf = vim.api.nvim_win_get_buf(main_win)
  if not vim.api.nvim_buf_is_valid(main_buf) then
    vim.notify('🚨 Main buffer is invalid', vim.log.levels.ERROR)
    return
  end

  -- 1. Snapshot current buffer state
  local pre_insert_lines = vim.api.nvim_buf_get_lines(main_buf, 0, -1, true)
  local snapshot = table.concat(pre_insert_lines, '\n')

  -- 2. Find codeblock and insertion point
  local float_win = vim.api.nvim_get_current_win()
  local cursor_line = vim.api.nvim_win_get_cursor(float_win)[1]
  local total_lines = vim.api.nvim_buf_line_count(0)

  -- Search upward for startline marker
  local start_line = nil
  for i = cursor_line, 1, -1 do
    local line = vim.fn.getline(i)
    local number = line:match '^startline:%s*(%d+)$'
    if number then
      start_line = tonumber(number)
      break
    end
  end

  if not start_line then
    vim.notify('🔥 No valid startline marker found', vim.log.levels.ERROR)
    return
  end

  -- 3. Find codeblock boundaries
  local code_start, code_end = nil, nil
  for i = cursor_line, 1, -1 do
    if vim.fn.getline(i):match '^```' then
      code_start = i + 1
      break
    end
  end

  for i = cursor_line, total_lines do
    if vim.fn.getline(i):match '^```' then
      code_end = i - 1
      break
    end
  end

  if not (code_start and code_end and code_end >= code_start) then
    vim.notify('💥 Malformed codeblock', vim.log.levels.ERROR)
    return
  end

  -- 4. Extract code content
  local code_lines = vim.api.nvim_buf_get_lines(0, code_start - 1, code_end, false)
  if #code_lines == 0 then
    vim.notify('🌑 Empty codeblock', vim.log.levels.WARN)
    return
  end

  -- 5. Conflict detection
  local current_buffer_content = table.concat(vim.api.nvim_buf_get_lines(main_buf, 0, -1, true), '\n')
  if current_buffer_content ~= snapshot then
    local choice = vim.fn.confirm('⚠️ Buffer changed since codegen. Proceed?', '&Yes\n&No', 2)
    if choice ~= 1 then
      return
    end
  end

  -- 6. Large insert confirmation
  if #code_lines > 10 then
    local choice = vim.fn.confirm(string.format('Insert %d lines at line %d?', #code_lines, start_line), '&Yes\n&No', 2)
    if choice ~= 1 then
      return
    end
  end

  -- 7. Safety checks
  local max_line = vim.api.nvim_buf_line_count(main_buf)
  if start_line > max_line + 1 then
    vim.notify(string.format('🚫 Invalid insertion line: %d (buffer has %d lines)', start_line, max_line), vim.log.levels.ERROR)
    return
  end

  -- 8. Perform atomic insert
  vim.api.nvim_buf_call(main_buf, function()
    vim.cmd 'undojoin' -- Preserve undo history
    vim.api.nvim_buf_set_lines(main_buf, start_line - 1, start_line - 1, false, code_lines)

    -- Auto-format if LSP available
    if vim.lsp.buf.format then
      vim.lsp.buf.format {
        async = true,
        range = {
          start = { start_line, 0 },
          ['end'] = { start_line + #code_lines, 0 },
        },
      }
    end
  end)

  -- 9. Visual feedback
  local ns = vim.api.nvim_create_namespace 'code_insert_flash'
  for i = 0, #code_lines - 1 do
    vim.api.nvim_buf_add_highlight(main_buf, ns, 'DiffAdd', start_line - 1 + i, 0, -1)
  end

  vim.defer_fn(function()
    vim.api.nvim_buf_clear_namespace(main_buf, ns, 0, -1)
  end, 3000)

  -- 10. Success notification
  vim.notify(string.format('🎉 Inserted %d lines at line %d (L%s-%s)', #code_lines, start_line, start_line, start_line + #code_lines - 1))
end

local function create_snapshot()
  local main_buf = vim.api.nvim_win_get_buf(main_win)
  return {
    lines = vim.api.nvim_buf_get_lines(main_buf, 0, -1, true),
    version = vim.api.nvim_buf_get_changedtick(main_buf),
  }
end

-- 400 (Add this to state management section)
local snapshots = {
  before_insert = nil,
  after_insert = nil,
}

function M.rollback_insert()
  if not snapshots.before_insert then
    vim.notify('No insertion snapshot available', vim.log.levels.WARN)
    return
  end

  local main_buf = vim.api.nvim_win_get_buf(main_win)
  vim.api.nvim_buf_set_lines(main_buf, 0, -1, false, snapshots.before_insert.lines)
  vim.notify('♻️ Rolled back to pre-insertion state', vim.log.levels.INFO)
end

function M.insert_codeblock2()
  local float_win = vim.api.nvim_get_current_win()
  local cursor_line = vim.api.nvim_win_get_cursor(float_win)[1]
  local total_lines = vim.api.nvim_buf_line_count(0)

  -- 1. Search upward for the insertion line indicator
  local insert_line_marker = nil
  for i = cursor_line, 1, -1 do
    local line = vim.fn.getline(i)
    local number = line:match '^startline:%s*(%d+)$'
    if number then
      insert_line_marker = number
      break
    end
  end

  if not insert_line_marker then
    print '🛑 Could not find "startline:" insertion marker above cursor.'
    return
  end

  -- Convert the captured number string to a number
  local start_line = tonumber(insert_line_marker)
  if not start_line then
    print '❌ Invalid format for line number marker!'
    return
  end

  -- 2. Find the surrounding fenced codeblock from cursor
  local code_start, code_end = nil, nil
  for i = cursor_line, 1, -1 do
    local line = vim.fn.getline(i)
    if line:match '^```' then
      code_start = i + 1
      break
    end
  end

  for i = cursor_line, total_lines do
    local line = vim.fn.getline(i)
    if line:match '^```' then
      code_end = i - 1
      break
    end
  end

  if not (code_start and code_end and code_end >= code_start) then
    print '🤯 Could not find full codeblock around cursor.'
    return
  end

  -- 3. Extract and insert into codebase
  local code_lines = vim.api.nvim_buf_get_lines(0, code_start - 1, code_end, false)
  local main_buf = vim.api.nvim_win_get_buf(main_win)

  vim.api.nvim_buf_set_lines(main_buf, start_line - 1, start_line - 1, false, code_lines)
  print('🎉 Code inserted at line ' .. start_line)

  -- 4. Highlight the inserted block temporarily
  local ns = vim.api.nvim_create_namespace 'codeblock_inserted'
  vim.api.nvim_buf_clear_namespace(main_buf, ns, 0, -1)

  for i = 0, #code_lines - 1 do
    vim.api.nvim_buf_add_highlight(main_buf, ns, 'DiffAdd', start_line - 1 + i, 0, -1)
  end

  -- Optional: remove highlight after a delay
  vim.defer_fn(function()
    vim.api.nvim_buf_clear_namespace(main_buf, ns, 0, -1)
  end, 3000)
end

local function openai_make_curl_args_reasoner(opts, prompt)
  local api_key = get_api_key 'OPENAI_API_KEY'
  return make_spec_curl_args_reasoner(opts, prompt, api_key)
end

local function deepseek_make_curl_args(opts, prompt)
  local api_key = get_api_key 'DEEPSEEK_API_KEY'
  return make_spec_curl_args_reasoner(opts, prompt, api_key)
end

-- Function to Get Prompt from Visual Selection or Cursor
local function get_prompt(opts)
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

  return prompt
end

-- Function to Get Lines Until Cursor
local function get_lines_until_cursor()
  local main_buf = vim.api.nvim_win_get_buf(main_win or vim.api.nvim_get_current_win())
  local cursor_pos = vim.api.nvim_win_get_cursor(main_win or vim.api.nvim_get_current_win())
  local end_row = cursor_pos[1]

  local lines = vim.api.nvim_buf_get_lines(main_buf, 0, end_row, true)

  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    local buff_lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, true)
    table.insert(lines, '') -- add a separator
    vim.list_extend(lines, buff_lines)
  end

  return table.concat(lines, '\n')
end

-- Function to Invoke LLM and Stream into Editor
function M.invoke_llm_and_stream_into_editor(opts, make_curl_args_fn, handle_data_fn)
  vim.api.nvim_clear_autocmds { group = group }
  local prompt = get_prompt(opts)
  local args = make_curl_args_fn(opts, prompt)
  local curr_event_state = nil

  local function parse_and_call(line)
    local event = line:match '^event: (.+)$'
    if event then
      curr_event_state = event
      return
    end
    local data_match = line:match '^data: (.+)$'
    if data_match then
      handle_data_fn(data_match, curr_event_state)
    end
  end

  if state.active_job then
    state.active_job:shutdown()
    state.active_job = nil
  end

  state.active_job = Job:new {
    command = 'curl',
    args = args,
    on_stdout = function(_, out)
      parse_and_call(out)
    end,
    on_exit = function()
      if state.win_obj then
        vim.schedule(function()
          vim.api.nvim_buf_clear_namespace(state.tabs[state.current_tab].buf, namespace_id, 0, -1)
        end)
      end
      state.active_job = nil
    end,
  }
  --state.main_win = vim.api.nvim_get_current_win()
  state.active_job:start()

  vim.api.nvim_set_keymap('n', '<Esc>', ':doautocmd User hint_LLM_Escape<CR>', { noremap = true, silent = true })
end

-- Function to Write String at Cursor
local function write_string_at_cursor(str)
  vim.schedule(function()
    local current_window = vim.api.nvim_get_current_win()
    local cursor_position = vim.api.nvim_win_get_cursor(current_window)
    local row, col = cursor_position[1], cursor_position[2]

    local lines = vim.split(str, '\n')
    vim.cmd 'undojoin'
    vim.api.nvim_put(lines, 'c', true, true)

    local num_lines = #lines
    local last_line_length = #lines[num_lines]
    vim.api.nvim_win_set_cursor(current_window, { row + num_lines - 1, col + last_line_length })
  end)
end

-- Function to OpenAI Chat Completion
function M.openai_chat_completion()
  vim.api.nvim_command 'normal! o'
  write_to_window '\n--------------------------------------------------------------------gtp-4o\n\n'
  M.invoke_llm_and_stream_into_editor({
    url = 'https://api.openai.com/v1/chat/completions',
    model = 'gpt-4o',
    max_tokens = 200,
  }, openai_make_curl_args, handle_openai_spec_data)
end

-- Function to OpenAI Chat Completion Reasoner
function M.openai_chat_completion_reasoner()
  vim.api.nvim_command 'normal! o'
  write_to_window '\n--------------------------------------------------------------------o1-mini\n\n'
  M.invoke_llm_and_stream_into_editor({
    url = 'https://api.openai.com/v1/chat/completions',
    model = 'o1-mini',
    --max_tokens = 200,
  }, openai_make_curl_args_reasoner, handle_openai_spec_data)
end

-- Function to DeepSeek Chat Completion
function M.deepseek_chat_completion()
  vim.api.nvim_command 'normal! o'
  write_to_window '\n--------------------------------------------------------------------deepseek-reasoner\n\n'
  M.invoke_llm_and_stream_into_editor({
    url = 'https://api.deepseek.com/chat/completions',
    model = 'deepseek-reasoner',
    max_tokens = 200,
  }, deepseek_make_curl_args, handle_openai_spec_data)
end

return M
