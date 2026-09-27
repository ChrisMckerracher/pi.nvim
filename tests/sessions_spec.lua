describe("session controls", function()
  local sessions = require "pi_nvim.sessions"
  local original_select
  before_each(function() original_select = vim.ui.select end)
  after_each(function() vim.ui.select = original_select end)

  it("lets the user choose new, resume, or cancel", function()
    local created, resumed = 0, 0
    local actions = {
      new_session = function() created = created + 1 end,
      resume_session = function() resumed = resumed + 1 end,
    }
    for _, choice in ipairs { 1, 2, 0 } do
      vim.ui.select = function(items, opts, cb)
        assert.equals("Pi sessions", opts.prompt)
        assert.equals("New session", opts.format_item(items[1]))
        assert.equals("Resume session…", opts.format_item(items[2]))
        cb(items[choice])
      end
      sessions.menu(actions)
    end
    assert.equals(1, created)
    assert.equals(1, resumed)
  end)

  it("sends abort and reports host failures", function()
    local pi = require "pi_nvim"
    pi.setup { keymaps = false }
    local host = pi.get_host()
    host.job = 123
    local sent
    host.request = function(_, command, _, cb)
      sent = command
      cb { success = false, error = "abort failed" }
    end
    pi.abort()
    assert.equals("abort", sent)
    local chat = require "pi_nvim.chat"
    assert.truthy(table.concat(vim.api.nvim_buf_get_lines(chat.buf, 0, -1, false), "\n"):find("abort failed", 1, true))
    host.job = nil
  end)

  it("clears old chat only when a new session succeeds", function()
    local pi = require "pi_nvim"
    local chat = require "pi_nvim.chat"
    pi.setup { keymaps = false }
    local host = pi.get_host()
    host.job = 123
    chat.append_lines { "old conversation" }
    local reply
    host.request = function(_, command, _, cb)
      assert.equals("new_session", command)
      reply = cb
    end
    pi.new_session()
    assert.truthy(
      table.concat(vim.api.nvim_buf_get_lines(chat.buf, 0, -1, false), "\n"):find("old conversation", 1, true)
    )
    reply { success = true, data = host.state }
    local text = table.concat(vim.api.nvim_buf_get_lines(chat.buf, 0, -1, false), "\n")
    assert.is_nil(text:find("old conversation", 1, true))
    assert.truthy(text:find("new session started", 1, true))
    assert.is_nil(text:find("history replayed", 1, true))
    host.job = nil
  end)
end)
