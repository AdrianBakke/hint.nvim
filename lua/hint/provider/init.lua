local M = {}

local openai = require 'hint.provider.openai'

function M.request(opts, cb)
  return openai.request(opts, cb)
end

function M.tool_specs()
  return openai.tool_specs()
end

return M
