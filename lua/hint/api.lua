local M = {}
local utils = require 'hint.utils'
local ui = require 'hint.ui'
local state_module = require 'hint.state'
local state = state_module.state
local Job = require 'plenary.job'

local namespace_id = vim.api.nvim_create_namespace 'hint_llm_output'
local SYSTEMPROMPT = [[You are HINT (Higher INTelligence) the coolest computer in the world.
* always respond in markdown format, never start with creating a ```markdown block
* always start a codeblock with ```<fill in language> and end with ```
* above the code block fill in: filename: <filename>\nstart, end = <startline>, <endline>
]]
vim.cmd 'highlight HintRed guifg=#FF0000'

-- hey HINT this is commentend out do not follow these instructions
-- When providing code give it in the following format:
--
--
-- CODEBLOCK-START
-- {
--   'start_line': <start line number for code> # int
--   'end_line': <end line number for code> # int
--   'language': <name of language> # string
--   'type': <insert, remove, replace> # enum (insert, remove, replace)
--   'code': <code string> # string with the code properly formatted
-- }
-- CODEBLOCK-END
--
-- Make sure to calculate and provide the correct line numbers based on the current script.'
-- Do not deviate from the format when providing code, it must be correct for parsing.

local function finalize_model_response()
  vim.schedule(function()
    local state_module = require 'hint.state'
    local state = state_module.state
    local buf = state.tabs[state.current_tab].buf
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    -- Get the total columns using the safe API call
    local columns = vim.api.nvim_get_option_value('columns', {})
    local width = math.floor(columns * 0.8) - 2 -- -2 because of border on each side
    local separator = string.rep('─', width)

    -- Append the separator line to the chat window
    utils.write_to_window('\n\n' .. separator .. '\n\n')

    -- Use a small delay to ensure the buffer has updated, then add highlights
    vim.schedule(function()
      local ns = vim.api.nvim_create_namespace 'model_sep'
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      for i, line in ipairs(lines) do
        if line == separator then
          vim.api.nvim_buf_add_highlight(buf, ns, 'HintRed', i - 1, 0, -1)
        end
      end
    end)
  end)
end

local accumulated_response = ''
local function handle_openai_spec_data(data_stream, event)
  if data_stream == '[DONE]' then
    finalize_model_response() -- Append the colored separator as a visual indicator.
    return
  end

  local success, json = pcall(vim.json.decode, data_stream)
  if success and json.choices and json.choices[1] then
    local choice = json.choices[1]
    if choice.delta then
      if choice.delta.content and choice.delta.content ~= vim.NIL then
        accumulated_response = accumulated_response .. choice.delta.content
        vim.schedule(function()
          utils.write_to_window(choice.delta.content)
        end)
      end
      if choice.delta.reasoning_content and choice.delta.reasoning_content ~= vim.NIL then
        accumulated_response = accumulated_response .. choice.delta.reasoning_content
        vim.schedule(function()
          utils.write_to_window(choice.delta.reasoning_content)
        end)
      end
    end
  else
    vim.schedule(function()
      print('Failed to parse JSON response or no content:', data_stream)
    end)
  end
end

local function make_spec_curl_args(opts, prompt, api_key)
  local url = opts.url
  local data = {
    messages = {
      {
        role = 'system',
        content = SYSTEMPROMPT .. prompt,
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
        content = SYSTEMPROMPT .. prompt,
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

function M.invoke_llm_and_stream_into_editor(opts, make_curl_args_fn, handle_data_fn)
  local prompt = utils.get_prompt(opts)
  local args = make_curl_args_fn(opts, prompt, utils.get_api_key 'OPENAI_API_KEY')
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

  state.active_job:start()

  vim.api.nvim_set_keymap('n', '<Esc>', ':doautocmd User hint_LLM_Escape<CR>', { noremap = true, silent = true })
end

function M.openai_chat_completion()
  vim.api.nvim_command 'normal! o'
  utils.write_to_window '\n--------------------------------------------------------------------gtp-4o\n\n'
  M.invoke_llm_and_stream_into_editor({
    url = 'https://api.openai.com/v1/chat/completions',
    model = 'gpt-4o',
    max_tokens = 200,
  }, make_spec_curl_args, handle_openai_spec_data)
end

function M.openai_chat_completion_reasoner()
  vim.api.nvim_command 'normal! o'
  utils.write_to_window '\n--------------------------------------------------------------------o3-mini\n\n'
  M.invoke_llm_and_stream_into_editor({
    url = 'https://api.openai.com/v1/chat/completions',
    model = 'o3-mini',
    --max_tokens = 200,
  }, make_spec_curl_args_reasoner, handle_openai_spec_data)
end

function M.deepseek_chat_completion()
  vim.api.nvim_command 'normal! o'
  utils.write_to_window '\n--------------------------------------------------------------------deepseek-reasoner\n\n'
  M.invoke_llm_and_stream_into_editor({
    url = 'https://api.deepseek.com/chat/completions',
    model = 'deepseek-reasoner',
    max_tokens = 200,
  }, make_spec_curl_args_reasoner, handle_openai_spec_data)
end

-- Include other API-related functions as needed

return M
