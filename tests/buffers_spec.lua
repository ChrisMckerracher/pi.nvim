describe("unnamed buffers", function()
  local buffers = require "pi_nvim.buffers"
  local buf
  local function request(fields)
    return buffers.request(vim.tbl_extend("force", {
      action = "edit",
      bufferId = buf,
      expiresAt = (os.time() + 10) * 1000,
      changedtick = vim.api.nvim_buf_get_changedtick(buf),
      oldText = "hello",
      newText = "world",
    }, fields or {}))
  end
  before_each(function()
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "prefix hello suffix", "untouched" })
    buffers.describe(buf)
  end)
  after_each(function()
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
  end)

  it("reads and replaces exact text without naming or saving the buffer", function()
    local before = vim.json.decode(request { action = "read" })
    local after = vim.json.decode(request { newText = "new\ncode" })
    assert.equals("prefix hello suffix\nuntouched", before.text)
    assert.equals("prefix new\ncode suffix\nuntouched", after.text)
    assert.is_true(after.changedtick > before.changedtick)
    assert.equals("", vim.api.nvim_buf_get_name(buf))
    assert.is_true(vim.bo[buf].modified)
  end)

  it("rejects edits after the user changes the buffer", function()
    local tick = vim.api.nvim_buf_get_changedtick(buf)
    vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "user edit" })
    assert.has_error(function() request { changedtick = tick } end)
    assert.same({ "prefix hello suffix", "user edit" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it("rejects ambiguous, missing, empty-match, and expired edits", function()
    for _, fields in ipairs {
      { oldText = "x" },
      { oldText = "" },
      { expiresAt = (os.time() - 1) * 1000 },
      { oldText = "f" },
      { changedtick = "bad" },
      { action = "delete" },
    } do
      assert.has_error(function() request(fields) end)
    end
    assert.same({ "prefix hello suffix", "untouched" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it("can populate a completely empty unnamed buffer", function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
    request { oldText = "", newText = "function example()\nend" }
    assert.same({ "function example()", "end" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it("rejects saved, special, read-only, deleted, and unexposed buffers", function()
    vim.bo[buf].readonly = true
    assert.has_error(function() request() end)
    vim.bo[buf].readonly = false
    vim.bo[buf].buftype = "nofile"
    assert.has_error(function() request() end)
    vim.bo[buf].buftype = ""
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname())
    assert.has_error(function() request() end)
    vim.api.nvim_buf_delete(buf, { force = true })
    buf = vim.api.nvim_create_buf(true, false)
    assert.has_error(function() request { action = "read" } end)
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.has_error(
      function() buffers.request { action = "read", bufferId = buf, expiresAt = (os.time() + 10) * 1000 } end
    )
  end)

  it("keeps the edit undoable", function()
    -- A real input boundary closes the initial setup's undo block.
    vim.cmd "let &undolevels = &undolevels"
    request()
    vim.cmd "undo"
    assert.same({ "prefix hello suffix", "untouched" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)
end)
