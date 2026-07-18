describe("input", function()
  local input = require "pi_nvim.input"

  before_each(function()
    input.setup({ input_height = 6 }, function() end, { on_close = function() end, scroll = function() end })
    input.ensure_buf()
    vim.api.nvim_set_current_buf(input.buf)
  end)

  it("locates completion start after @", function()
    vim.api.nvim_set_current_line "hello @tests/foo"
    vim.api.nvim_win_set_cursor(0, { 1, 16 }) -- cursor past end of line
    assert.equals(7, input.omnifunc(1, ""))
  end)

  it("stays silent when the token does not start with @", function()
    vim.api.nvim_set_current_line "hello world"
    vim.api.nvim_win_set_cursor(0, { 1, 11 })
    assert.equals(-3, input.omnifunc(1, ""))
  end)

  it("returns matching files for the base", function()
    local tmp = "tests/.tmp-omni-target.txt"
    vim.fn.writefile({ "x" }, tmp)
    local items = input.omnifunc(0, "tests/.tmp-omni-tar")
    vim.fn.delete(tmp)
    local words = {}
    for _, item in ipairs(items) do
      words[#words + 1] = item.word
    end
    assert.truthy(vim.tbl_contains(words, tmp))
  end)
end)
