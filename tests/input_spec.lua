describe("input", function()
  local input = require "pi_nvim.input"

  before_each(function()
    input.setup({ input_height = 6 }, function() end, { on_close = function() end, scroll = function() end })
    input.ensure_buf()
    vim.api.nvim_set_current_buf(input.buf)
  end)

  it("leaves Escape to native mode transitions", function()
    for _, mode in ipairs { "i", "n" } do
      for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(input.buf, mode)) do
        assert.is_not.equals("<Esc>", mapping.lhs)
      end
    end
  end)

  it("offers cancel and sessions without clearing a draft", function()
    local stopped, menu = 0, 0
    input.setup({}, function() end, {
      on_close = function() end,
      scroll = function() end,
      abort = function() stopped = stopped + 1 end,
      sessions = function() menu = menu + 1 end,
    })
    input.set_text "unfinished message"
    for _, mode in ipairs { "i", "n" } do
      for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(input.buf, mode)) do
        if mapping.lhs == "<C-C>" or mapping.lhs == "<C-c>" then mapping.callback() end
        if mapping.lhs == "<F2>" then mapping.callback() end
      end
    end
    assert.equals(2, stopped)
    assert.is_true(vim.wait(1000, function() return menu == 2 end))
    assert.same({ "unfinished message" }, vim.api.nvim_buf_get_lines(input.buf, 0, -1, false))
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

  it("sends without error and clears the box (insert persistence is manual-verify)", function()
    -- NOTE: headless nvim never enters insert mode (probed: startinsert +
    -- 500ms wait still reports 'n'), so 'send keeps you typing' can't be
    -- asserted here. The mechanism: the <CR> insert map no longer calls
    -- stopinsert, and send() ends with startinsert for the normal-mode path.
    local sent = nil
    input.setup(
      { input_height = 6 },
      function(text) sent = text end,
      { on_close = function() end, scroll = function() end }
    )
    input.ensure_buf()
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, input.buf)
    vim.api.nvim_buf_set_lines(input.buf, 0, -1, false, { "hello" })
    assert.has_no_errors(function() input.send() end)
    assert.equals("hello", sent)
    assert.same({ "" }, vim.api.nvim_buf_get_lines(input.buf, 0, -1, false))
  end)
end)
