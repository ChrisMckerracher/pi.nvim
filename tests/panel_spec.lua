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

  it("docks as real splits and resizes like a native sibling", function()
    panel.close()
    vim.cmd "only"
    local editor = vim.api.nvim_get_current_win()
    local w0 = vim.api.nvim_win_get_width(editor)

    panel.open()
    assert.is_true(panel.is_open())
    assert.equals("", vim.api.nvim_win_get_config(panel.chat_win).relative) -- split, not float
    assert.equals("", vim.api.nvim_win_get_config(panel.input_win).relative)
    assert.equals(30, vim.api.nvim_win_get_width(panel.chat_win))
    assert.is_true(vim.api.nvim_win_get_width(editor) < w0) -- editor gives space automatically

    panel.resize(-4)
    assert.equals(26, vim.api.nvim_win_get_width(panel.chat_win))
    assert.equals(26, vim.api.nvim_win_get_width(panel.input_win))
    panel.close()
    assert.is_false(panel.is_open())
  end)

  it("prompt height grows from but never below its starting point", function()
    panel.close()
    panel.open()
    local h0 = cfg.input_height
    assert.equals(h0, vim.api.nvim_win_get_height(panel.input_win))
    panel.resize_height(-2)
    assert.equals(h0, vim.api.nvim_win_get_height(panel.input_win)) -- floor
    panel.resize_height(3)
    assert.equals(h0 + 3, vim.api.nvim_win_get_height(panel.input_win))
    panel.close()
  end)

  it("switches focus between editor and prompt", function()
    panel.close()
    vim.cmd "only"
    panel.open()
    assert.equals(panel.input_win, vim.api.nvim_get_current_win())
    panel.focus_switch()
    assert.is_not.equals(panel.input_win, vim.api.nvim_get_current_win())
    panel.focus_switch()
    assert.equals(panel.input_win, vim.api.nvim_get_current_win())
    panel.close()
  end)

  it("shows a spinner in the prompt winbar while working, hints after", function()
    panel.start_spinner()
    local shown = vim.wait(2000, function() return vim.wo[panel.input_win].winbar:find "Testing" ~= nil end, 50)
    assert.is_true(shown)
    panel.stop_spinner()
    assert.equals(" send <CR> · newline <C-j> · scroll <C-d/u> ", vim.wo[panel.input_win].winbar)
  end)
end)
