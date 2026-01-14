local M = {
  model = nil,
  active_job = nil,
  last_response = nil,
  last_diff = nil,
  last_tool_output = nil,
  main_win = nil,
  debug = {
    prompt = nil,
    response = nil,
    tool_history = nil,
    tool_calls = nil,
    model = nil,
    file = nil,
    cursor = nil,
    duration_ms = nil,
    note = nil,
  },
  snapshots = {},
  status = { win = nil, buf = nil, lines = {}, history = {}, timer = nil, spinner_index = 1, activity = nil },
  prompt = { win = nil, buf = nil },
}

return M
