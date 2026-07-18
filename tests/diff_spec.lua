describe("diff", function()
  local diff = require "pi_nvim.diff"

  before_each(function() diff.reset() end)

  it("records patches from tool_execution_end events", function()
    diff.on_tool_end {
      type = "tool_execution_end",
      args = { path = "a.lua" },
      result = { details = { patch = "PATCH1" } },
    }
    diff.on_tool_end {
      type = "tool_execution_end",
      args = { path = "a.lua" },
      result = { details = { patch = "PATCH2" } },
    }
    diff.on_tool_end { type = "tool_execution_end", args = { path = "b.lua" }, result = { details = {} } }
    assert.same({ "PATCH1", "PATCH2" }, diff.changes["a.lua"].patches)
    assert.is_nil(diff.changes["b.lua"])
    assert.is_true(diff.has_changes())
  end)

  it("detects patch -p level and safety from --- headers", function()
    local p1, unsafe1 = diff._patch_mode "--- a/src/x.lua\n+++ b/src/x.lua\n"
    assert.equals("-p1", p1)
    assert.is_false(unsafe1)
    local p0, unsafe0 = diff._patch_mode "--- /abs/x.lua\n+++ /abs/x.lua\n"
    assert.equals("-p0", p0)
    assert.is_true(unsafe0)
  end)
end)
