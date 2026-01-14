local tools = require 'hint.tools'

describe('tools', function()
  it('parses tool calls', function()
    local text = [[
HINT_TOOL: rg foo bar
HINT_TOOL: read lua/hint/init.lua
]]
    local calls = tools.parse(text)
    assert.are.equal(2, #calls)
    assert.are.equal('rg', calls[1].name)
    assert.are.equal('foo bar', calls[1].arg)
    assert.are.equal('read', calls[2].name)
  end)

  it('reads from loaded buffers', function()
    local path = vim.fn.tempname()
    vim.fn.writefile({ 'one', 'two' }, path)
    local buf = vim.fn.bufadd(path)
    vim.fn.bufload(buf)
    vim.api.nvim_buf_set_lines(buf, 1, 2, false, { 'TWO' })
    local output = tools.run({ { name = 'read', arg = path .. ':1-2' } })
    assert.is_true(output:find('1: one', 1, true) ~= nil)
    assert.is_true(output:find('2: TWO', 1, true) ~= nil)
  end)
end)
