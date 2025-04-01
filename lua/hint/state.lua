local M = {}

M.state = {
  win_obj = nil,
  tabs = {},
  current_tab = 1,
  active_job = nil,
  cursor_positions = {},
  snapshots = {
    before_insert = nil,
    after_insert = nil,
  },
}

return M
