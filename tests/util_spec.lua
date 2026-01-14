local util = require 'hint.util'

describe('util', function()
  it('finds nearest HINT comment', function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      'line 1',
      '# HINT: do the thing',
      'line 3',
    })
    local text, line = util.find_hint_comment(buf, 3)
    assert.are.equal('do the thing', text)
    assert.are.equal(2, line)
  end)
end)
