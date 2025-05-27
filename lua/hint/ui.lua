local M = {}
vim.cmd 'highlight HintGreen guifg=#00FF00'
vim.cmd 'highlight HintYellow guifg=#FFFF00'
vim.cmd 'highlight HintWhite guifg=#FFFFFF'
vim.cmd 'highlight HintBlue guifg=#0000FF'
vim.cmd 'highlight HintRed guifg=#FF0000'

local state_module = require 'hint.state'
local state = state_module.state
local utils = require 'hint.utils'
local namespace_id = vim.api.nvim_create_namespace 'hint_llm_output'
local Job = require 'plenary.job'

function M.create_or_update_window()
  -- Check if there is at least one tab
  if #state.tabs == 0 then
    table.insert(state.tabs, { name = 'Tab 1', buf = vim.api.nvim_create_buf(false, true), context_files = {} })
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

    -- Create window for the tab bar. Height increased to 4 lines:
    -- 1 for header, 1 for tab list, 2 for context info.
    local tab_buf = vim.api.nvim_create_buf(false, true)
    local tab_win = vim.api.nvim_open_win(tab_buf, false, {
      relative = 'editor',
      width = width,
      height = 4,
      col = math.floor((vim.o.columns - width) / 2),
      row = math.floor((vim.o.lines - height) / 2) - 3, -- Position above the main content window
      style = 'minimal',
      border = 'none',
    })

    -- Store window objects
    state.win_obj = {
      win = win,
      tab_win = tab_win,
      tab_buf = tab_buf,
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

  -- Set keymaps
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '', { callback = M.close_current_tab, noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Tab>', '', { callback = M.next_tab, noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<S-Tab>', '', { callback = M.prev_tab, noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<C-j>', '', { callback = M.toggle_window, noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<leader>tt', '', { callback = M.create_new_tab, noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<C-c>', '', { callback = M.popup_context_files, noremap = true, silent = true })

  -- Add the Ctrl-P keymap for selecting files
  vim.api.nvim_buf_set_keymap(buf, 'n', '<C-p>', '', { callback = M.select_files, noremap = true, silent = true })

  vim.api.nvim_win_set_buf(state.win_obj.win, buf)
  local line_count = vim.api.nvim_buf_line_count(buf)
  local cursor_pos = state.cursor_positions[state.current_tab] or { 1, 0 }
  vim.api.nvim_win_set_cursor(state.win_obj.win, cursor_pos)
end

local function render_tabs()
  if not state.win_obj or not vim.api.nvim_win_is_valid(state.win_obj.tab_win) then
    return
  end

  local tab_buf = state.win_obj.tab_buf
  vim.api.nvim_buf_set_option(tab_buf, 'modifiable', true)

  local win_width = vim.api.nvim_win_get_width(state.win_obj.tab_win)

  -- Build header with emojis and the text "HINT" where the "H" is red and "INT" is blue.
  local prefix = '🔥🔥🔥 ' -- emoji prefix
  local suffix = ' 🔥🔥🔥' -- emoji suffix
  local header = 'HINT'
  local full_header = prefix .. header .. suffix

  -- Calculate padding to center the header line.
  local total_width = vim.fn.strdisplaywidth(full_header)
  local padding = math.floor((win_width - total_width) / 2)
  local header_line = string.rep(' ', padding) .. full_header

  -- Set the header line as the first line of the tab buffer.
  vim.api.nvim_buf_set_lines(tab_buf, 0, 1, false, { header_line })

  -- Render the Tab Bar: iterate through tabs.
  local tab_line = ' '
  for i, tab in ipairs(state.tabs) do
    if i == state.current_tab then
      tab_line = tab_line .. '  ' .. tab.name .. '  '
    else
      tab_line = tab_line .. '  ' .. tab.name .. '  '
    end
  end

  local current_tab = state.tabs[state.current_tab]
  local context_files = current_tab.context_files or {}
  local filenames = {}
  for _, file in ipairs(context_files) do
    table.insert(filenames, vim.fn.fnamemodify(file, ':t'))
  end
  local context_line = '  Context Files: ' .. (#filenames > 0 and table.concat(filenames, ', ') or 'None')

  -- Calculate token estimate for both the current buffer and the context files.
  local buf_lines = vim.api.nvim_buf_get_lines(current_tab.buf, 0, -1, false)
  local buf_text = table.concat(buf_lines, ' ')

  local context_text = ''
  for _, file in ipairs(context_files) do
    local file_lines = vim.fn.readfile(file)
    context_text = context_text .. table.concat(file_lines, ' ') .. ' '
  end

  local total_text = buf_text .. context_text
  local token_estimate = math.floor(#total_text / 4)
  local token_line = '  Token Estimate: ' .. token_estimate .. ' tokens'

  -- Set the remaining lines in the tab buffer.
  -- Row 1: tab list, Row 2: context files, Row 3: token estimate.
  vim.api.nvim_buf_set_lines(tab_buf, 1, 2, false, { tab_line })
  vim.api.nvim_buf_set_lines(tab_buf, 2, 4, false, { context_line, token_line })

  -- Add some additional highlighting for the other lines.
  vim.api.nvim_buf_add_highlight(tab_buf, namespace_id, 'HintYellow', 1, 0, -1)
  vim.api.nvim_buf_add_highlight(tab_buf, namespace_id, 'HintGreen', 2, 0, 15)
  vim.api.nvim_buf_add_highlight(tab_buf, namespace_id, 'HintWhite', 2, 15, -1)
  vim.api.nvim_buf_add_highlight(tab_buf, namespace_id, 'HintGreen', 3, 0, 16)
  vim.api.nvim_buf_add_highlight(tab_buf, namespace_id, 'HintWhite', 3, 16, -1)

  vim.api.nvim_buf_set_option(tab_buf, 'modifiable', false)
end

function M.popup_context_files()
  local current_tab = state.tabs[state.current_tab]
  if not current_tab.context_files or #current_tab.context_files == 0 then
    vim.notify('No files in context, you dumbass!', vim.log.levels.WARN)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local lines = {}
  for i, file in ipairs(current_tab.context_files) do
    lines[i] = vim.fn.fnamemodify(file, ':t')
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local width = math.floor(vim.o.columns * 0.4)
  local height = #lines > 0 and #lines or 1
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'single',
  })

  vim.api.nvim_buf_set_keymap(buf, 'n', 'd', '', {
    callback = function()
      local cursor = vim.api.nvim_win_get_cursor(win)
      local line = cursor[1]
      local file_to_delete = current_tab.context_files[line]
      if file_to_delete then
        table.remove(current_tab.context_files, line)
        vim.notify('Deleted file from context: ' .. file_to_delete .. ' 🤬', vim.log.levels.INFO)
        local new_lines = {}
        for i, f in ipairs(current_tab.context_files) do
          new_lines[i] = vim.fn.fnamemodify(f, ':t')
        end
        vim.api.nvim_buf_set_option(buf, 'modifiable', true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
        vim.api.nvim_buf_set_option(buf, 'modifiable', false)
        if #current_tab.context_files == 0 then
          vim.api.nvim_win_close(win, true)
        end
      else
        vim.notify('Invalid selection, you stupid prick!', vim.log.levels.WARN)
      end
      render_tabs()
    end,
    noremap = true,
    silent = true,
  })

  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '', {
    callback = function()
      vim.api.nvim_win_close(win, true)
    end,
    noremap = true,
    silent = true,
  })

  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.cmd 'normal! gg'
end

function M.next_tab()
  if #state.tabs == 0 then
    return
  end
  state.cursor_positions[state.current_tab] = vim.api.nvim_win_get_cursor(state.win_obj.win)
  state.current_tab = state.current_tab % #state.tabs + 1
  M.create_or_update_window()
  render_tabs()
end

function M.create_new_tab(name)
  if #state.tabs > 9 then
    vim.notify('Maximum of 10 tabs reached', vim.log.levels.WARN)
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  table.insert(state.tabs, { name = 'Tab ' .. (#state.tabs + 1), buf = buf, context_files = {} })
  state.current_tab = #state.tabs
  M.create_or_update_window()
  render_tabs()
  return buf
end

function M.prev_tab()
  if #state.tabs == 0 then
    return
  end
  state.cursor_positions[state.current_tab] = vim.api.nvim_win_get_cursor(state.win_obj.win)
  state.current_tab = (state.current_tab - 2) % #state.tabs + 1
  M.create_or_update_window()
  render_tabs()
end

function M.close_current_tab()
  if #state.tabs == 0 then
    return
  end
  local removed_tab = table.remove(state.tabs, state.current_tab)
  removed_tab.context_files = nil
  if #state.tabs == 0 then
    state.win_obj.close()
    state.win_obj = nil
  else
    if state.current_tab > #state.tabs then
      state.current_tab = #state.tabs
    end
    for i, _ in ipairs(state.tabs) do
      state.tabs[i].name = 'Tab ' .. i
    end
    M.create_or_update_window()
    render_tabs()
  end
end

function M.toggle_window()
  if state.win_obj and vim.api.nvim_win_is_valid(state.win_obj.win) then
    state.cursor_positions[state.current_tab] = vim.api.nvim_win_get_cursor(state.win_obj.win)
    state.win_obj.close()
    state.win_obj = nil
  else
    state.main_win = vim.api.nvim_get_current_win()
    M.create_or_update_window()
    local file_path = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(state.main_win))
    if file_path ~= '' then
      local current_tab = state.tabs[state.current_tab]
      if not vim.tbl_contains(current_tab.context_files, file_path) then
        table.insert(current_tab.context_files, file_path)
        vim.notify('Added current file to context: ' .. file_path, vim.log.levels.INFO)
      else
        vim.notify('File already in context: ' .. file_path, vim.log.levels.WARN)
      end
    else
      vim.notify('No valid file found in the current window, you idiot!', vim.log.levels.WARN)
    end
    render_tabs()
    local cursor_pos = state.cursor_positions[state.current_tab] or { 1, 0 }
    vim.api.nvim_win_set_cursor(state.win_obj.win, cursor_pos)
  end
end

function M.select_files()
  local telescope_ok, telescope = pcall(require, 'telescope.builtin')
  if not telescope_ok then
    vim.notify('Telescope is not installed, dipshit!', vim.log.levels.ERROR)
    return
  end

  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'

  telescope.find_files {
    prompt_title = 'Select Files [Multi-select with <TAB>]',
    attach_mappings = function(prompt_bufnr, map)
      -- Toggle selection with TAB in insert and normal mode
      map('i', '<TAB>', actions.toggle_selection)
      map('n', '<TAB>', actions.toggle_selection)

      -- Override the default selection to handle multiple choices
      actions.select_default:replace(function()
        local picker = action_state.get_current_picker(prompt_bufnr)
        local selections = picker:get_multi_selection()
        if not selections or vim.tbl_isempty(selections) then
          selections = { action_state.get_selected_entry() }
        end

        for _, entry in ipairs(selections) do
          local current_tab = state.tabs[state.current_tab]
          current_tab.context_files = current_tab.context_files or {}
          if not vim.tbl_contains(current_tab.context_files, entry.path) then
            table.insert(current_tab.context_files, entry.path)
            vim.notify('Added to context: ' .. entry.path, vim.log.levels.INFO)
          else
            vim.notify('File already in context: ' .. entry.path, vim.log.levels.WARN)
          end
        end

        render_tabs()
        actions.close(prompt_bufnr)
      end)

      return true
    end,
  }
end

--local ts_utils = require("nvim-treesitter.ts_utils")

-- Grab dependencies by parsing the current buffer with Treesitter.
function M.get_file_dependencies(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lang = vim.bo[bufnr].filetype
  if not lang or lang == '' then
    vim.notify('No filetype set for buffer, asshole.', vim.log.levels.WARN)
    return {}
  end

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  if not ok or not parser then
    vim.notify('Treesitter parser not found for language: ' .. lang, vim.log.levels.ERROR)
    return {}
  end

  local tree = parser:parse()[1]
  local root = tree:root()

  -- This is a sample query.
  -- Adjust it for your language. For example for Lua, "require" calls and function definitions.
  local query_text = [[
    ((call_expression
       function: (identifier) @func_name
       arguments: (arguments (string) @import_string))
     (#eq? @func_name "require"))
    ; For languages with import statements, add a query like:
    (import_statement
       (string) @import)
  ]]

  local query_ok, query = pcall(vim.treesitter.query.parse, lang, query_text)
  if not query_ok then
    vim.notify('Failed to parse Treesitter query', vim.log.levels.ERROR)
    return {}
  end

  local dependencies = {}

  for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
    local capture_name = query.captures[id] -- name of the capture in the query
    if capture_name == 'import_string' or capture_name == 'import' then
      local dep = vim.treesitter.query.get_node_text(node, bufnr)
      table.insert(dependencies, dep)
    end
  end

  return dependencies
end

-- Example function to add dependencies to current context
function M.add_file_dependencies()
  local deps = M.get_file_dependencies()
  if vim.tbl_isempty(deps) then
    vim.notify('No dependencies found, dipshit!', vim.log.levels.WARN)
    return
  end

  local current_tab = state.tabs[state.current_tab]
  current_tab.context_files = current_tab.context_files or {}

  for _, dep in ipairs(deps) do
    -- Here, you might want to transform the dependency string to an actual file path.
    -- This example assumes the dependency is a file path.
    if not vim.tbl_contains(current_tab.context_files, dep) then
      table.insert(current_tab.context_files, dep)
      vim.notify('Added dependency to context: ' .. dep, vim.log.levels.INFO)
    else
      vim.notify('Dependency already in context: ' .. dep, vim.log.levels.WARN)
    end
  end

  render_tabs()
end

-- function M.create_input_box(callback)
--   local width = math.floor(vim.o.columns * 0.8)
--   local height = 3
--   local row = vim.o.lines - height - 2 -- a couple of lines above the bottom
--   local col = math.floor((vim.o.columns - width) / 2)
--   local buf = vim.api.nvim_create_buf(false, true)
--   local win = vim.api.nvim_open_win(buf, true, {
--     relative = 'editor',
--     width = width,
--     height = height,
--     row = row,
--     col = col,
--     style = 'minimal',
--     border = 'rounded',
--   })
--
--   -- Configure the buffer as a prompt.
--   vim.api.nvim_buf_set_option(buf, 'buftype', 'prompt')
--   vim.fn.prompt_setprompt(buf, 'Input> ')
--
--   -- Save the callback and window info in state.
--   state.input_callback = callback
--   state.input_win = win
--   state.input_buf = buf
--
--   -- Map <CR> in insert mode to submit the input.
--   vim.api.nvim_buf_set_keymap(buf, 'i', '<CR>', [[<C-\><C-n>:lua require("hint.ui").submit_input()<CR>]], { noremap = true, silent = true })
--   return win, buf
-- end
--
-- -- Called when the user hits <CR> in the input box.
-- function M.submit_input()
--   local state_module = require 'hint.state'
--   local state = state_module.state
--   if not state.input_buf or not vim.api.nvim_buf_is_valid(state.input_buf) then
--     return
--   end
--   local lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
--   local user_input = table.concat(lines, '\n')
--   if state.input_callback then
--     state.input_callback(user_input)
--   end
--   if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
--     vim.api.nvim_win_close(state.input_win, true)
--   end
--   state.input_win = nil
--   state.input_buf = nil
--   state.input_callback = nil
-- end

return M
