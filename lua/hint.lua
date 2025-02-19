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

  vim.api.nvim_win_set_buf(state.win_obj.win, buf)
  local line_count = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_win_set_cursor(state.win_obj.win, { line_count, 0 })
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

    local current_line_count = vim.api.nvim_buf_line_count(buf)
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
    vim.api.nvim_win_set_cursor(state.win_obj.win, { current_line_count, 0 })
  end)
end

-- Public Functions for Tab Navigation
function M.next_tab()
  if #state.tabs == 0 then
    return
  end
  state.current_tab = state.current_tab % #state.tabs + 1
  create_or_update_window()
  render_tabs()
end

function M.prev_tab()
  if #state.tabs == 0 then
    return
  end
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
    state.win_obj.close()
    state.win_obj = nil
  else
    create_or_update_window()
    render_tabs()
  end
end

function M.create_new_tab(name)
  if #state.tabs > 9 then
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
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

-- Function to Create New Tab via Leader Shortcut

-- Function to Handle Data from Anthropics
local function handle_anthropic_spec_data(data_stream, event_state)
  if event_state == 'content_block_delta' then
    local json = vim.json.decode(data_stream)
    if json.delta and json.delta.text then
      write_to_window(json.delta.text)
    end
  end
end

-- Function to Handle OpenAI Data
local function handle_openai_spec_data(data_stream, event)
  local success, json = pcall(vim.json.decode, data_stream)

  if success then
    if json.choices and json.choices[1] then
      local choice = json.choices[1]
      if choice.delta and choice.delta.content then
        write_to_window(choice.delta.content)
      elseif choice.text then
        write_to_window(choice.text)
      end
    else
      print 'No content found in the response'
    end
  elseif data_stream == '[DONE]' then
    print 'Stream complete'
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
        content = 'You are HINT (Higher INTelligence) the most intelligent computer in the world. You answer with code and bullet points. Avoid writing code that do not contain any changes. Answer in markdown.',
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
        content = 'You are HINT (Higher INTelligence) the most intelligent computer in the world. You answer with code and bullet points. Avoid writing code that do not contain any changes. Answer in markdown. '
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
  return args
end

local function openai_make_curl_args(opts, prompt)
  local api_key = get_api_key 'OPENAI_API_KEY'
  return make_spec_curl_args(opts, prompt, api_key)
end

local function openai_make_curl_args_reasoner(opts, prompt)
  local api_key = get_api_key 'OPENAI_API_KEY'
  return make_spec_curl_args_reasoner(opts, prompt, api_key)
end

local function deepseek_make_curl_args(opts, prompt)
  local api_key = get_api_key 'DEEPSEEK_API_KEY'
  return make_spec_curl_args(opts, prompt, api_key)
end

local function anthropic_make_curl_args(opts, prompt)
  local url = opts.url
  local api_key = opts.api_key_name and get_api_key(opts.api_key_name)
  local data = {
    system = 'You are HINT (Higher INTelligence) the most intelligent computer in the world. You answer with code and bullet points. Avoid writing code that do not contain any changes. Answer in markdown.',
    messages = { { role = 'user', content = prompt } },
    model = opts.model,
    stream = true,
    max_tokens = 4096,
  }
  local args = { '-N', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', vim.json.encode(data) }
  if api_key then
    table.insert(args, '-H')
    table.insert(args, 'x-api-key: ' .. api_key)
    table.insert(args, '-H')
    table.insert(args, 'anthropic-version: 2023-06-01')
  end
  return args
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
  local main_buf = vim.api.nvim_win_get_buf(state.main_win or vim.api.nvim_get_current_win())
  local cursor_pos = vim.api.nvim_win_get_cursor(state.main_win or vim.api.nvim_get_current_win())
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
          vim.api.nvim_buf_set_lines(state.tabs[state.current_tab].buf, -1, -1, true, { '[Stream complete] Press CTRL-j to hide or q to close' })
        end)
      end
      state.active_job = nil
    end,
  }

  state.main_win = vim.api.nvim_get_current_win()
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
  M.invoke_llm_and_stream_into_editor({
    url = 'https://api.openai.com/v1/chat/completions',
    model = 'gpt-4o',
    max_tokens = 200,
  }, openai_make_curl_args, handle_openai_spec_data)
end

-- Function to OpenAI Chat Completion Reasoner
function M.openai_chat_completion_reasoner()
  vim.api.nvim_command 'normal! o'
  M.invoke_llm_and_stream_into_editor({
    url = 'https://api.openai.com/v1/chat/completions',
    model = 'gpt-4-reasoner',
    max_tokens = 200,
  }, openai_make_curl_args_reasoner, handle_openai_spec_data)
end

-- Function to DeepSeek Chat Completion
function M.deepseek_chat_completion()
  vim.api.nvim_command 'normal! o'
  M.invoke_llm_and_stream_into_editor({
    url = 'https://api.deepseek.com/chat/completions',
    model = 'deepseek-reasoner',
    max_tokens = 200,
  }, deepseek_make_curl_args, handle_openai_spec_data)
end

return M
