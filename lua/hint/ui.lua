local M = {}
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

    -- Create window for the tab bar
    local tab_buf = vim.api.nvim_create_buf(false, true)
    local tab_win = vim.api.nvim_open_win(tab_buf, false, {
      relative = 'editor',
      width = width,
      height = 3, -- Two lines: one for tabs, one for context files
      col = math.floor((vim.o.columns - width) / 2),
      row = math.floor((vim.o.lines - height) / 2) - 2, -- Position above the main content window
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

  -- Render Tab Bar in the tab buffer
  local tab_line = ' '
  for i, tab in ipairs(state.tabs) do
    if i == state.current_tab then
      tab_line = tab_line .. '  ' .. tab.name .. '  '
    else
      tab_line = tab_line .. '  ' .. tab.name .. '  '
    end
  end
  local tab_buf = state.win_obj.tab_buf
  vim.api.nvim_buf_set_option(tab_buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(tab_buf, 0, 1, false, { tab_line })

  -- Display context files for the current tab
  local current_tab = state.tabs[state.current_tab]
  local context_files = current_tab.context_files or {}
  local filenames = {}
  for _, file in ipairs(context_files) do
    table.insert(filenames, vim.fn.fnamemodify(file, ':t'))
  end
  local context_line = 'Context Files: ' .. ((#filenames > 0 and table.concat(filenames, ', ')) or 'None')

  -- Calculate token estimate for both the current buffer and the context files
  local buf_lines = vim.api.nvim_buf_get_lines(current_tab.buf, 0, -1, false)
  local buf_text = table.concat(buf_lines, ' ')

  -- Concatenate all context file contents
  local context_text = ''
  for _, file in ipairs(context_files) do
    local file_lines = vim.fn.readfile(file)
    context_text = context_text .. table.concat(file_lines, ' ') .. ' '
  end

  local total_text = buf_text .. context_text
  local token_estimate = math.floor(#total_text / 4)
  local token_line = 'Token Estimate: ' .. token_estimate .. ' tokens'

  -- Set context lines: one line for context and one for token estimate
  vim.api.nvim_buf_set_lines(tab_buf, 1, 3, false, { context_line, token_line })

  -- Highlight the context line and token line if desired
  vim.api.nvim_buf_add_highlight(tab_buf, namespace_id, 'Comment', 1, 0, -1)
  vim.api.nvim_buf_add_highlight(tab_buf, namespace_id, 'Comment', 2, 0, -1)

  vim.api.nvim_buf_set_option(tab_buf, 'modifiable', false)
end

function M.popup_context_files()
  local current_tab = state.tabs[state.current_tab]
  if not current_tab.context_files or #current_tab.context_files == 0 then
    vim.notify('No files in context, you dumbass!', vim.log.levels.WARN)
    return
  end

  -- Create a scratch buffer for the popup
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = {}
  for i, file in ipairs(current_tab.context_files) do
    lines[i] = vim.fn.fnamemodify(file, ':t')
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Calculate popup dimensions
  local width = math.floor(vim.o.columns * 0.4)
  local height = #lines > 0 and #lines or 1
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create the floating window with a border
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'single',
  })

  -- Allow movement with j and k (they already work by default in normal mode)
  -- Map 'd' to delete the selected file from context
  vim.api.nvim_buf_set_keymap(buf, 'n', 'd', '', {
    callback = function()
      local cursor = vim.api.nvim_win_get_cursor(win)
      local line = cursor[1]
      local file_to_delete = current_tab.context_files[line]
      if file_to_delete then
        table.remove(current_tab.context_files, line)
        vim.notify('Deleted file from context: ' .. file_to_delete .. ' 🤬', vim.log.levels.INFO)
        -- Update the popup lines
        local new_lines = {}
        for i, f in ipairs(current_tab.context_files) do
          new_lines[i] = vim.fn.fnamemodify(f, ':t')
        end
        vim.api.nvim_buf_set_option(buf, 'modifiable', true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
        vim.api.nvim_buf_set_option(buf, 'modifiable', false)
        -- Close the popup if there are no more files
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

  -- Map 'q' (or <Esc>) to close the popup
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '', {
    callback = function()
      vim.api.nvim_win_close(win, true)
    end,
    noremap = true,
    silent = true,
  })

  -- Optional: Keep the popup modifiable for a brief moment if you want to refresh, then lock it down
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

  -- Initialize context_files as an empty table
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

  -- Remove the current tab and its context_files
  local removed_tab = table.remove(state.tabs, state.current_tab)
  removed_tab.context_files = nil

  if #state.tabs == 0 then
    state.win_obj.close()
    state.win_obj = nil
  else
    -- Adjust current_tab if needed
    if state.current_tab > #state.tabs then
      state.current_tab = #state.tabs
    end

    -- Rename tabs to maintain order
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

    -- Automatically add the currently open file in your main window to context
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
  vim.notify('select_files function called!', vim.log.levels.INFO)

  local telescope_ok, telescope = pcall(require, 'telescope.builtin')
  if not telescope_ok then
    vim.notify('Telescope is not installed, dipshit!', vim.log.levels.ERROR)
    return
  end

  local actions_ok, actions = pcall(require, 'telescope.actions')
  if not actions_ok then
    vim.notify('Telescope actions could not be loaded, what the fuck!', vim.log.levels.ERROR)
    return
  end

  local action_state_ok, action_state = pcall(require, 'telescope.actions.state')
  if not action_state_ok then
    vim.notify('Telescope actions.state could not be loaded, seriously?', vim.log.levels.ERROR)
    return
  end

  telescope.find_files {
    prompt_title = 'Select Files to Add to Context',
    attach_mappings = function(prompt_bufnr, map)
      vim.notify('attach_mappings called!', vim.log.levels.INFO)

      -- Override default select action to add files to context instead of opening
      actions.select_default:replace(function()
        vim.notify('Enter pressed. Adding file to context!', vim.log.levels.INFO)
        local selection = action_state.get_selected_entry()
        if selection and selection.path then
          local current_tab = state.tabs[state.current_tab]
          current_tab.context_files = current_tab.context_files or {}

          -- Avoid duplicates
          if not vim.tbl_contains(current_tab.context_files, selection.path) then
            table.insert(current_tab.context_files, selection.path)
            vim.notify('Added to context: ' .. selection.path, vim.log.levels.INFO)
          else
            vim.notify('File already in context: ' .. selection.path, vim.log.levels.WARN)
          end

          -- Update context display
          render_tabs()
        else
          vim.notify('No selection made.', vim.log.levels.WARN)
        end
        actions.close(prompt_bufnr)
      end)

      return true
    end,
  }
end

return M
