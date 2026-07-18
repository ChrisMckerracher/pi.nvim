describe("host framing and state", function()
  local Host = require "pi_nvim.host"

  local function new_host() return Host.new { host_cmd = { "node", "host/dist/main.js" } } end

  it("reassembles JSONL records across arbitrary chunk boundaries", function()
    local host = new_host()
    local lines = {}
    host._handle_line = function(_, line) table.insert(lines, line) end
    -- nvim jobstart semantics: first item continues the pending partial,
    -- last item is the new partial; a line is complete once followed by
    -- another item ("" after a trailing newline).
    host:_handle_stdout { '{"type":"agent_st' }
    host:_handle_stdout { 'art"}', '{"type":"agent_settled"}', '{"type":"x' }
    assert.same({ '{"type":"agent_start"}', '{"type":"agent_settled"}' }, lines)
    host:_handle_stdout { '"}', "" }
    assert.same({ '{"type":"agent_start"}', '{"type":"agent_settled"}', '{"type":"x"}' }, lines)
  end)

  it("tracks streaming state from forwarded events", function()
    local host = new_host()
    host:_handle_line '{"type":"agent_start"}'
    assert.is_true(host.state.isStreaming)
    host:_handle_line '{"type":"agent_settled"}'
    assert.is_false(host.state.isStreaming)
  end)

  it("tracks thinking level changes", function()
    local host = new_host()
    host:_handle_line '{"type":"thinking_level_changed","level":"max"}'
    assert.equals("max", host.state.thinkingLevel)
  end)

  it("correlates responses to callbacks and consumes them", function()
    local host = new_host()
    host._callbacks["7"] = function() end
    host:_handle_line '{"id":"7","type":"response","command":"get_state","success":true,"data":{}}'
    assert.is_nil(host._callbacks["7"])
  end)

  it("strips a trailing CR from records (CRLF tolerance)", function()
    local host = new_host()
    local lines = {}
    host._handle_line = function(_, line) table.insert(lines, line) end
    host:_handle_stdout { '{"type":"agent_start"}\r', "" }
    assert.same({ '{"type":"agent_start"}' }, lines)
  end)
end)
