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
end)
