describe("panel", function()
  local panel = require "pi_nvim.panel"
  local chat = require "pi_nvim.chat"
  local input = require "pi_nvim.input"

  local cfg = {
    width = 30,
    input_height = 4,
    auto_scroll = false,
    render_thinking = false,
    tool_result_lines = 12,
    max_context_file_lines = 200,
    working_messages = { "Testing" },
  }

  local function top_line()
    return vim.api.nvim_win_call(panel.chat_win, function() return vim.fn.line "w0" end)
  end

  before_each(function()
    chat.setup(cfg)
    input.setup(cfg, function() end, { on_close = function() end, scroll = function() end })
    panel.setup(cfg)
    chat.ensure_buf()
    chat.append_lines(vim.tbl_map(function(i) return "line " .. i end, vim.fn.range(1, 200)))
    panel.open()
  end)

  after_each(function() panel.close() end)

  it("scrolls by half pages without focus", function()
    panel.scroll_chat_edge "top"
    assert.equals(1, top_line())
    panel.scroll_chat(1)
    assert.is_true(top_line() > 1)
    panel.scroll_chat(-1)
    assert.equals(1, top_line())
  end)

  it("jumps to edges (gg / G semantics)", function()
    panel.scroll_chat_edge "top"
    assert.equals(1, top_line())
    panel.scroll_chat_edge "bottom"
    assert.is_true(top_line() > 1)
    panel.scroll_chat_edge "top"
    assert.equals(1, top_line())
  end)

  it("ignores scroll calls when the panel is closed", function()
    panel.close()
    assert.has_no_errors(function()
      panel.scroll_chat(1)
      panel.scroll_chat_lines(3)
      panel.scroll_chat_edge "bottom"
    end)
  end)

  it("shifts the editor on open, moves the divider on resize, restores on close", function()
    panel.close()
    vim.cmd "only" -- isolate from windows leaked by other spec files
    -- Sibling shift requires 2+ normal windows (a lone window fills the grid).
    vim.cmd "vsplit"
    local editor_win = vim.api.nvim_get_current_win() -- rightmost split
    vim.api.nvim_win_set_width(editor_win, 60)
    local editor_w0 = vim.api.nvim_win_get_width(editor_win)

    panel.open()
    local chat_w = vim.api.nvim_win_get_width(panel.chat_win)
    local editor_w1 = vim.api.nvim_win_get_width(editor_win)
    assert.equals(editor_w0 - (chat_w + 2), editor_w1)

    panel.resize(-4) -- shrink panel → editor grows by the same columns
    assert.equals(chat_w - 4, vim.api.nvim_win_get_width(panel.chat_win))
    assert.equals(editor_w1 + 4, vim.api.nvim_win_get_width(editor_win))

    panel.close()
    assert.equals(editor_w0, vim.api.nvim_win_get_width(editor_win))
    vim.api.nvim_win_close(editor_win, true)
  end)
end)
