local M = {}
local Job = require 'plenary.job'

local function get_api_key(name)
  return os.getenv(name)
end

local namespace_id = vim.api.nvim_create_namespace 'hint_llm_output'
local last_line = 0 -- Track last line written for typewriter effect
local main_win = vim.api.nvim_get_current_win() -- Track main window

local state = {
  win_obj = nil,
  buf = vim.api.nvim_create_buf(false, true), -- Store buffer here to persist it
  should_close = false,
}
-- Add this function to create a floating window
function M.delete_buffer()
  state.buf = nil
end

local function create_output_window()
  main_win = vim.api.nvim_get_current_win()
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local border_style = {
    { '╭', 'FloatBorder' }, -- Top-left
    { '─', 'FloatBorder' }, -- Top
    { '╮', 'FloatBorder' }, -- Top-right
    { '│', 'FloatBorder' }, -- Right
    { '╯', 'FloatBorder' }, -- Bottom-right
    { '─', 'FloatBorder' }, -- Bottom
    { '╰', 'FloatBorder' }, -- Bottom-left
    { '│', 'FloatBorder' }, -- Left
  }

  local buf = state.buf or vim.api.nvim_create_buf(false, true)
  state.buf = buf -- Store buffer in state

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width - 2,
    height = height - 2,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = 'minimal',
    border = border_style,
  })

  -- Set window options
  vim.wo[win].wrap = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].modifiable = true

  -- vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", "<CMD>hide<CR>", { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<leader>q', '<CMD>q!<CR>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<leader>h', '<CMD>hide<CR>', { noremap = true, silent = true, desc = 'Close HINT Window' })

  return {
    buf = buf,
    win = win,
    close = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  }
end

function write_to_window(str)
  vim.schedule(function()
    if not state.win_obj or not vim.api.nvim_win_is_valid(state.win_obj.win) then
      state.win_obj = create_output_window()
    end

    local buf = state.win_obj.buf
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

local function print_buffer_content(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  print 'Buffer Content:'
  for _, line in ipairs(lines) do
    print(line)
  end
end

local function print_lines(lines)
  for _, line in ipairs(lines) do
    print(line)
  end
end

-- Function to reopen the window with the existing buffer
function M.open_window()
  -- Check if buffer is valid before reopening
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    print 'No buffer to reopen.'
    return
  end

  -- Create a new window using the existing buffer
  state.win_obj = create_output_window()
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

local function get_lines_until_cursor()
  -- Validate main window reference
  -- Get main window's buffer and cursor position
  local main_buf = vim.api.nvim_win_get_buf(main_win)
  local cursor_pos = vim.api.nvim_win_get_cursor(main_win)
  local end_row = cursor_pos[1] -- 1-based index

  -- Extract lines from start to cursor position (0-based, exclusive end)
  local lines = vim.api.nvim_buf_get_lines(main_buf, 0, end_row, true)

  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    local buff_lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, true)
    table.insert(lines, '') -- add a separator
    vim.list_extend(lines, buff_lines)
  end

  return table.concat(lines, '\n')
end

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
      local _, erow, ecol = unpack(vim.fn.getpos 'v')
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', false, true, true), 'nx', false)
      vim.api.nvim_win_set_cursor(0, { erow, ecol })
      vim.api.nvim_command 'normal! o'
    end
  else
    prompt = get_lines_until_cursor()
  end

  return prompt
end

function M.handle_anthropic_spec_data(data_stream, event_state)
  if event_state == 'content_block_delta' then
    local json = vim.json.decode(data_stream)
    if json.delta and json.delta.text then
      write_string_at_cursor(json.delta.text)
    end
  end
end

local group = vim.api.nvim_create_augroup('hint_LLM_AutoGroup', { clear = true })
local active_job = nil

function M.invoke_llm_and_stream_into_editor(opts, make_curl_args_fn, handle_data_fn)
  -- state.buf = nil -- clear global buffer

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
      handle_data_fn(data_match, curr_event_state, state)
    end
  end

  if active_job then
    active_job:shutdown()
    active_job = nil
  end

  active_job = Job:new {
    command = 'curl',
    args = args,
    on_stdout = function(_, out)
      parse_and_call(out)
    end,
    on_exit = function()
      if state.win_obj then
        -- Remove temporary typing effects
        vim.schedule(function()
          vim.api.nvim_buf_clear_namespace(state.buf, namespace_id, 0, -1)
          -- Add completion message
          vim.api.nvim_buf_set_lines(state.buf, -1, -1, true, { '[Stream complete] Press <leader>w to hide or <leader>q to close' })
        end)
      end
      active_job = nil
    end,
  }

  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'hint_LLM_Escape',
    callback = function()
      if state.win_obj then
        state.win_obj.close()
      end
    end,
  })

  active_job:start()

  vim.api.nvim_set_keymap('n', '<Esc>', ':doautocmd User hint_LLM_Escape<CR>', { noremap = true, silent = true })
  return active_job
end

local function handle_openai_spec_data(data_stream, event)
  -- Attempt to decode the JSON data
  local success, json = pcall(vim.json.decode, data_stream)

  if success then
    -- Handle streamed completion where "delta" contains the content
    if json.choices and json.choices[1] and json.choices[1].delta then
      local content = json.choices[1].delta.content
      local resoning_content = json.choices[1].delta.reasoning_content
      -- Write the streamed content chunk to the editor
      if content == vim.NIL and reasoning_content then
        --write_string_at_cursor(json.choices[1].delta.reasoning_content)
        write_to_window(resoning_content)
      elseif content and content ~= vim.NIL and content ~= '' then
        --write_string_at_cursor(content)
        write_to_window(content)
      end
    elseif json.choices and json.choices[1] and json.choices[1].text then
      -- This handles non-streamed completions
      local content = json.choices[1].text
      if content then
        --write_string_at_cursor(content)
        write_to_window(content)
      end
    else
      print 'No content found in the response'
    end
  elseif data_stream == '[DONE]' then
    --write_string_at_cursor("\n")
    print 'Stream complete'
  else
    print('Failed to parse JSON response:', data_stream)
  end
end

-- Function to create the curl arguments for OpenAI requests
local function make_spec_curl_args(opts, prompt, api_key)
  print 'Creating curl arguments' -- Debugging: Check if this function is called
  local url = opts.url

  if not api_key then
    print 'API key not found' -- Debugging: Check if the API key is set
  end

  local data = {
    messages = {
      {
        role = 'system',
        content = 'You are HINT (Higher INTelligence) the most intelligent computer in the world. you answer with code. NO text unless asked to, you write helpfull code comments though',
      },
      { role = 'user', content = prompt }, -- Replace with actual input from Neovim
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
  print(vim.inspect(args))
  return args
end

local function make_spec_curl_args_reasoner(opts, prompt, api_key)
  print 'Creating curl arguments for reasoner' -- Debugging: Check if this function is called
  local url = opts.url

  if not api_key then
    print 'API key not found' -- Debugging: Check if the API key is set
  end

  local data = {
    messages = {
      {
        role = 'user',
        content = 'You are HINT (Higher INTelligence) the most intelligent computer in the world. you answer with code. NO text unless asked to, you write helpfull code comments though '
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
  local api_key = os.getenv 'OPENAI_API_KEY'
  return make_spec_curl_args(opts, prompt, api_key)
end

local function openai_make_curl_args_reasoner(opts, prompt)
  local api_key = os.getenv 'OPENAI_API_KEY'
  return make_spec_curl_args_reasoner(opts, prompt, api_key)
end

local function deepseek_make_curl_args(opts, prompt)
  local api_key = os.getenv 'DEEPSEEK_API_KEY'
  return make_spec_curl_args(opts, prompt, api_key)
end

local function anthropic_make_curl_args(opts, prompt)
  local url = opts.url
  local api_key = opts.api_key_name and get_api_key(opts.api_key_name)
  local data = {
    system = system_prompt,
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

-- Function to invoke OpenAI chat-based completion
function M.openai_chat_completion()
  print 'Invoking OpenAI chat completion'
  vim.api.nvim_command 'normal! o'
  -- write_string_at_cursor("\n")
  M.invoke_llm_and_stream_into_editor({
    url = 'https://api.openai.com/v1/chat/completions',
    model = 'gpt-4o',
    max_tokens = 200,
    --replace = true,
  }, openai_make_curl_args, handle_openai_spec_data)
end

function M.openai_chat_completion_reasoner()
  print 'Invoking OpenAI chat completion'
  vim.api.nvim_command 'normal! o'
  -- write_string_at_cursor("\n")
  M.invoke_llm_and_stream_into_editor({
    url = 'https://api.openai.com/v1/chat/completions',
    model = 'o1-mini',
    max_tokens = 200,
    --replace = true,
  }, openai_make_curl_args_reasoner, handle_openai_spec_data)
end

function M.deepseek_chat_completion()
  print 'Invoking deepseek chat completion'
  vim.api.nvim_command 'normal! o'
  -- write_string_at_cursor("\n")
  M.invoke_llm_and_stream_into_editor({
    url = 'https://api.deepseek.com/chat/completions',
    model = 'deepseek-reasoner',
    max_tokens = 200,
    --replace = true,
  }, deepseek_make_curl_args, handle_openai_spec_data)
end

return M
