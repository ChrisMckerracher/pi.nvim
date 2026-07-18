describe("context", function()
  local context = require "pi_nvim.context"

  it("expands @file mentions into fenced blocks", function()
    local tmp = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "local x = 1", "return x" }, tmp)
    local expanded, paths = context.expand_mentions("look at @" .. tmp, 200)
    assert.truthy(expanded:find("[file:", 1, true))
    assert.truthy(expanded:find("local x = 1", 1, true))
    assert.equals(1, #paths)
    vim.fn.delete(tmp)
  end)

  it("leaves text untouched when no files match", function()
    local expanded, paths = context.expand_mentions("hello @definitely-not-a-real-file.xyz", 200)
    assert.equals("hello @definitely-not-a-real-file.xyz", expanded)
    assert.same({}, paths)
  end)

  it("truncates files beyond the line cap", function()
    local tmp = vim.fn.tempname() .. ".txt"
    local lines = {}
    for i = 1, 50 do
      lines[i] = "line " .. i
    end
    vim.fn.writefile(lines, tmp)
    local expanded = context.expand_mentions("@" .. tmp, 10)
    assert.truthy(expanded:find("first 10 lines", 1, true))
    assert.truthy(expanded:find("line 10", 1, true))
    assert.is_nil(expanded:find("line 11", 1, true))
    vim.fn.delete(tmp)
  end)

  it("composes pending selection into the message", function()
    context.pending = {
      kind = "selection",
      path = "src/main.lua",
      start_line = 3,
      end_line = 5,
      text = "print('hi')",
      filetype = "lua",
    }
    local message, attached = context.compose("fix this", { editor_context = false, max_context_file_lines = 200 })
    assert.equals("selection", attached.kind)
    assert.truthy(message:find("[selection from src/main.lua, lines 3-5]", 1, true))
    assert.truthy(message:find("fix this", 1, true))
    assert.is_nil(context.pending)
  end)

  it("describes the last code buffer, not the panel input (regression)", function()
    local code_buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(code_buf, (vim.uv.cwd() or "") .. "/fake-code.lua")
    context._last_code_buf = code_buf
    local state = context.editor_state()
    assert.truthy(state:find "fake%-code%.lua")
    context._last_code_buf = nil
    vim.api.nvim_buf_delete(code_buf, { force = true })
  end)
end)
