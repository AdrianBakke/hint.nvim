local M = {}

local config = require 'hint.config'
local agent = require 'hint.agent'
local status = require 'hint.ui.status'

function M.setup(opts)
  config.setup(opts or {})

  local keys = config.get().keymaps or {}
  if keys.prompt then
    vim.keymap.set({ 'n', 'v' }, keys.prompt, agent.prompt, { desc = 'Hint prompt' })
  end
  if keys.run_comment then
    vim.keymap.set('n', keys.run_comment, agent.run_comment, { desc = 'Hint run comment' })
  end
  if keys.show_last then
    vim.keymap.set('n', keys.show_last, agent.show_last, { desc = 'Hint show last output' })
  end
  if keys.model_1 then
    vim.keymap.set('n', keys.model_1, function()
      agent.set_model(1)
    end, { desc = 'Hint model 1' })
  end
  if keys.model_2 then
    vim.keymap.set('n', keys.model_2, function()
      agent.set_model(2)
    end, { desc = 'Hint model 2' })
  end
  if keys.model_3 then
    vim.keymap.set('n', keys.model_3, function()
      agent.set_model(3)
    end, { desc = 'Hint model 3' })
  end

  vim.api.nvim_create_user_command('HintRun', agent.run_comment, {})
  vim.api.nvim_create_user_command('HintPrompt', agent.prompt, {})
  vim.api.nvim_create_user_command('HintShow', agent.show_last, {})
  vim.api.nvim_create_user_command('HintRollback', agent.rollback, {})
  vim.api.nvim_create_user_command('HintDiff', agent.show_diff, {})
  vim.api.nvim_create_user_command('HintTools', agent.show_tools, {})
  vim.api.nvim_create_user_command('HintDebug', agent.show_debug, {})
  vim.api.nvim_create_user_command('HintStatus', status.open_log, {})
end

return M
