describe("chat buffer", function()
  local chat = require "pi_nvim.chat"

  local cfg = {
    width = 42,
    input_height = 6,
    auto_scroll = false,
    render_thinking = true,
    tool_result_lines = 12,
    max_context_file_lines = 200,
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

  it("shows and hides the spinner on agent_start/agent_settled", function()
    chat.event { type = "agent_start" }
    local started = vim.wait(
      2000,
      function() return #vim.api.nvim_buf_get_extmarks(chat.buf, chat.spinner_ns, 0, -1, {}) > 0 end,
      50
    )
    assert.is_true(started)
    chat.event { type = "agent_settled" }
    assert.same({}, vim.api.nvim_buf_get_extmarks(chat.buf, chat.spinner_ns, 0, -1, {}))
  end)

  it("stops the spinner on host_error", function()
    chat.start_spinner()
    chat.event { type = "host_error", message = "boom" }
    assert.is_nil(chat._spinner.timer)
  end)
end)
