local patch = require 'hint.patch'

describe('patch', function()
  it('applies apply_patch diffs', function()
    local path = vim.fn.tempname()
    vim.fn.writefile({ 'one', 'two', 'three' }, path)
    local text = [[
*** Begin Patch
*** Update File: ]] .. path .. [[
@@
-two
+TWO
*** End Patch
]]
    local diff = patch.parse_diff(text)
    assert.is_not_nil(diff)
    local ok = patch.apply_diff(diff)
    assert.is_true(ok)
    local buf = vim.fn.bufadd(path)
    vim.fn.bufload(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.are.same({ 'one', 'TWO', 'three' }, lines)
  end)

  it('parses multiple apply_patch blocks', function()
    local text = [[
*** Begin Patch
*** Update File: a.txt
@@
-a
+A
*** End Patch

*** Begin Patch
*** Update File: b.txt
@@
-b
+B
*** End Patch
]]
    local diff = patch.parse_diff(text)
    assert.is_not_nil(diff)
    assert.are.equal(2, #diff.files)
  end)

  it('applies patch() calls', function()
    local path = vim.fn.tempname()
    vim.fn.writefile({ 'one', 'two', 'three' }, path)
    local text = 'patch("two", "TWO")'
    local diff = patch.parse_diff(text, { default_path = path })
    assert.is_not_nil(diff)
    local ok = patch.apply_diff(diff)
    assert.is_true(ok)
    local buf = vim.fn.bufadd(path)
    vim.fn.bufload(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.are.same({ 'one', 'TWO', 'three' }, lines)
  end)

end)
