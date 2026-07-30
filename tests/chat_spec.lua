describe("chat buffer", function()
  local chat = require "pi_nvim.chat"

  local cfg = {
    width = 42,
    input_height = 6,
    auto_scroll = false,
    render_thinking = true,
    tool_result_lines = 12,
    max_context_file_lines = 200,
    working_messages = { "Testing" },
  }

  before_each(function()
    chat.setup(cfg)
    chat.ensure_buf()
  end)

  it(
    "is read-only for the user (transcript, not document)",
    function() assert.is_false(vim.bo[chat.buf].modifiable) end
  )

  it("still renders events through the transient-unlock wrapper", function()
    chat.event { type = "message_start", message = { role = "assistant" } }
    chat.event { type = "message_update", assistantMessageEvent = { type = "text_delta", delta = "hello" } }
    chat.event { type = "message_update", assistantMessageEvent = { type = "text_delta", delta = " world" } }
    local lines = vim.api.nvim_buf_get_lines(chat.buf, 0, -1, false)
    assert.equals("hello world", lines[#lines])
    assert.is_false(vim.bo[chat.buf].modifiable)
  end)

  it("collapses thinking into a single dim summary line", function()
    chat._cfg.render_thinking = false -- collapsed mode (the default)
    chat.event { type = "message_start", message = { role = "assistant" } }
    chat.event { type = "message_update", assistantMessageEvent = { type = "thinking_start" } }
    chat.event {
      type = "message_update",
      assistantMessageEvent = { type = "thinking_delta", delta = "let me\nconsider this" },
    }
    chat.event { type = "message_update", assistantMessageEvent = { type = "thinking_end" } }
    local text = table.concat(vim.api.nvim_buf_get_lines(chat.buf, 0, -1, false), "\n")
    assert.truthy(text:find("∙ thought (2 lines)", 1, true))
    assert.is_nil(text:find("consider this", 1, true))
  end)

  it("conceals code fences and tints block interiors", function()
    chat.echo_user "try this:\n```lua\nprint('x')\n```"
    chat._restyle()
    local found_conceal, found_code = false, false
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(chat.buf, chat.style_ns, 0, -1, { details = true })) do
      local details = mark[4]
      if details.conceal_lines then found_conceal = true end
      if details.line_hl_group == "PiNvimCode" then found_code = true end
    end
    assert.is_true(found_conceal)
    assert.is_true(found_code)
  end)

  it("starts the answer on a new line after the thought summary", function()
    chat._cfg.render_thinking = false
    chat.event { type = "message_start", message = { role = "assistant" } }
    chat.event { type = "message_update", assistantMessageEvent = { type = "thinking_start" } }
    chat.event { type = "message_update", assistantMessageEvent = { type = "thinking_delta", delta = "hmm" } }
    chat.event { type = "message_update", assistantMessageEvent = { type = "thinking_end" } }
    chat.event { type = "message_update", assistantMessageEvent = { type = "text_start" } }
    chat.event { type = "message_update", assistantMessageEvent = { type = "text_delta", delta = "the answer" } }
    local lines = vim.api.nvim_buf_get_lines(chat.buf, 0, -1, false)
    local thought_lnum, answer_lnum
    for i, line in ipairs(lines) do
      if line:find("∙ thought", 1, true) then thought_lnum = i end
      if line == "the answer" then answer_lnum = i end
    end
    assert.is_not_nil(thought_lnum)
    assert.equals(thought_lnum + 1, answer_lnum)
  end)

  it("pins to bottom while streaming unless the focused chat is scrolled up", function()
    chat._cfg.auto_scroll = true
    chat.replay {}
    vim.api.nvim_win_set_buf(0, chat.buf)
    local chat_win = vim.api.nvim_get_current_win()
    vim.cmd "vsplit | enew" -- focus moves to a new, unrelated window
    vim.api.nvim_win_set_cursor(chat_win, { 1, 0 })
    for _ = 1, 20 do
      chat.event { type = "message_update", assistantMessageEvent = { type = "text_delta", delta = "line\n" } }
    end
    assert.equals(vim.api.nvim_buf_line_count(chat.buf), vim.api.nvim_win_get_cursor(chat_win)[1])

    -- focused chat, user scrolled up to read: don't yank
    vim.api.nvim_set_current_win(chat_win)
    vim.api.nvim_win_set_cursor(chat_win, { 1, 0 })
    chat.event { type = "message_update", assistantMessageEvent = { type = "text_delta", delta = "more\n" } }
    assert.equals(1, vim.api.nvim_win_get_cursor(chat_win)[1])
  end)

  it("echoes the user even before the panel ever opened (buffer auto-created)", function()
    chat.buf = nil -- simulate: inline edit fired before any panel open
    assert.has_no_errors(function() chat.echo_user("hello", "+ selection") end)
    assert.is_not_nil(chat.buf)
    local text = table.concat(vim.api.nvim_buf_get_lines(chat.buf, 0, -1, false), "\n")
    assert.truthy(text:find("hello", 1, true))
  end)
end)
