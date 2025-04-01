local M = {}

local main = require 'hint.main'
local api = require 'hint.api'
local ui = require 'hint.ui'

main.setup()

M.main = main
M.api = api
M.ui = ui

return M
