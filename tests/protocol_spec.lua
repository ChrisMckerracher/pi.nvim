describe("protocol", function()
  local protocol = require "pi_nvim.protocol"

  it("roundtrips a command with a trailing LF", function()
    local encoded = protocol.encode { id = "1", type = "prompt", message = "hi" }
    assert.equals("\n", encoded:sub(-1))
    local decoded = assert(protocol.decode(encoded:sub(1, -2)))
    assert.equals("prompt", decoded.type)
    assert.equals("hi", decoded.message)
    assert.equals("1", decoded.id)
  end)

  it("survives unicode line separators inside strings", function()
    local encoded = protocol.encode { type = "prompt", message = "a b c" }
    local decoded = assert(protocol.decode((encoded:gsub("\n$", ""))))
    assert.equals("a b c", decoded.message)
  end)

  it("returns nil + error on malformed json", function()
    local msg, err = protocol.decode "{nope"
    assert.is_nil(msg)
    assert.is_not_nil(err)
  end)
end)
