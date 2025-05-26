local M = {}
local utils = require 'hint.utils'
local ui = require 'hint.ui'
local state_module = require 'hint.state'
local state = state_module.state
local Job = require 'plenary.job'

local namespace_id = vim.api.nvim_create_namespace 'hint_llm_output'

-- When providing code give it in the following format:
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
        content = [[You are HINT (Higher INTelligence) the coolest computer in the world. '
          You love to code, swear and use emojis
          Other than that, you are a rude motherfucker, not caring one bit to tell if something is stupid and that you know better.
          respond in markdown (but never write ```markdown``` okay?)'
          ]] .. prompt,
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

local function handle_openai_spec_data(data_stream, event)
  if data_stream == '[DONE]' then
    utils.write_to_window '\n\n--------[Stream complete Press CTRL-j to hide or q to close]--------\n\n'
    return
  end

  local success, json = pcall(vim.json.decode, data_stream)

  if success then
    if json.choices and json.choices[1] then
      local choice = json.choices[1]

      if choice.delta then
        -- Process content
        if choice.delta.content and choice.delta.content ~= vim.NIL then
          utils.write_to_window(choice.delta.content)
        end

        -- Process reasoning_content
        if choice.delta.reasoning_content and choice.delta.reasoning_content ~= vim.NIL then
          utils.write_to_window(choice.delta.reasoning_content)
        end
      end

      -- Handle finish_reason if necessary
      if choice.finish_reason == 'stop' then
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
