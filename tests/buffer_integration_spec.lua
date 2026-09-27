describe("unnamed buffer integration", function()
  local pi = require "pi_nvim"
  local context = require "pi_nvim.context"
  local buf, host, original_input, original_ensure, original_open, original_echo
  before_each(function()
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local value = 1" })
    pi.setup { keymaps = false }
    host = pi.get_host()
    original_input, original_ensure = vim.ui.input, pi._ensure_host
    original_open = require("pi_nvim.panel").open
    original_echo = require("pi_nvim.chat").echo_user
  end)
  after_each(function()
    vim.ui.input, pi._ensure_host = original_input, original_ensure
    require("pi_nvim.panel").open = original_open
    require("pi_nvim.chat").echo_user = original_echo
    context.pending, context._last_code_buf = nil, nil
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("preserves the initial unnamed target when focus moves into a prompt", function()
    local prompt = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(prompt)
    assert.truthy(context.editor_state():find("unnamed buffer " .. buf, 1, true))
    vim.api.nvim_buf_delete(prompt, { force = true })
  end)

  it("routes unnamed inline editing to the buffer tool", function()
    local message
    vim.ui.input = function(_, cb) cb "make value two" end
    pi._ensure_host = function(cb) cb() end
    require("pi_nvim.panel").open = function() end
    require("pi_nvim.chat").echo_user = function() end
    host.request = function(_, command, params)
      assert.equals("prompt", command)
      message = params.message
    end
    vim.cmd "normal! ggV"
    pi.inline_edit()
    assert.truthy(message:find("editor_buffer", 1, true))
    assert.truthy(message:find("unnamed buffer " .. buf, 1, true))
    assert.truthy(message:find("local value = 1", 1, true))
    assert.is_nil(message:find("modify the file directly", 1, true))
  end)

  it("answers wire edits and stale failures through the registered listener", function()
    context.capture_file()
    local responses = {}
    host.notify = function(_, command, data)
      assert.equals("editor_buffer_response", command)
      responses[#responses + 1] = data
    end
    local evt = {
      type = "editor_buffer_request",
      requestId = "edit-1",
      action = "edit",
      bufferId = buf,
      changedtick = vim.api.nvim_buf_get_changedtick(buf),
      oldText = "value = 1",
      newText = "value = 2",
      expiresAt = (os.time() + 10) * 1000,
    }
    host:_handle_line(vim.json.encode(evt))
    assert.is_true(vim.wait(1000, function() return #responses == 1 end))
    assert.equals("edit-1", responses[1].requestId)
    assert.equals("local value = 2", vim.json.decode(responses[1].result).text)
    evt.requestId = "stale-2"
    host:_handle_line(vim.json.encode(evt))
    assert.is_true(vim.wait(1000, function() return #responses == 2 end))
    assert.truthy(responses[2].result:find("buffer changed", 1, true))
    assert.same({ "local value = 2" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)
end)
