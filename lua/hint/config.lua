local M = {}

local defaults = {
  model = 'codex-mini-latest',
  models = { 'codex-mini-latest', 'gpt-4.1-mini', 'o4-mini' },
  keymaps = {
    prompt = '<C-h>',
    run_comment = '<leader>hr',
    show_last = '<leader>hs',
    model_1 = '<leader>1',
    model_2 = '<leader>2',
    model_3 = '<leader>3',
  },
  prompt = { width = 60, height = 3 },
  status = { width = 36, height = 5, max_history = 200 },
  context = {
    max_files = 6,
    max_bytes = 8000,
    max_total_bytes = 24000,
    ignore = { '.git', 'node_modules', 'dist', 'vendor' },
    snippet_radius = 40,
    include_current_full = false,
  },
  tools = {
    enabled = true,
    max_steps = 5,
    max_output_bytes = 4000,
    max_history_bytes = 8000,
  },
  confirm = false,
  diff_preview = true,
}

M.options = vim.tbl_deep_extend('force', {}, defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', {}, defaults, opts or {})
  if not M.options.model and M.options.models[1] then
    M.options.model = M.options.models[1]
  end
end

function M.get()
  return M.options
end

return M
