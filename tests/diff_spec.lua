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
    -- pi's actual format (verified against source): no prefixes, path as-is
    local pr, unsafer = diff._patch_mode "--- src/x.lua\n+++ src/x.lua\n"
    assert.equals("-p0", pr)
    assert.is_false(unsafer)
  end)
end)

describe("diff apply round-trips (real git apply)", function()
  local diff = require "pi_nvim.diff"
  local tmp_rel = "tests/.tmp-diff-roundtrip.lua"

  local function make_patch(path)
    -- unified diff changing line 2 old → new, in pi's prefix-less format
    return ("--- %s\n+++ %s\n@@ -1,2 +1,2 @@\n keep\n-old\n+new\n"):format(path, path)
  end

  before_each(function() diff.reset() end)
  after_each(function() vim.fn.delete(tmp_rel) end)

  it("reconstructs before-content for RELATIVE paths", function()
    vim.fn.writefile({ "keep", "new" }, tmp_rel)
    diff.changes[tmp_rel] = { patches = { make_patch(tmp_rel) } }
    local done, got = false, nil
    diff._reconstruct(tmp_rel, function(lines)
      got = lines
      done = true
    end)
    vim.wait(5000, function() return done end, 50)
    assert.same({ "keep", "old" }, got)
  end)

  it("reconstructs before-content for ABSOLUTE paths", function()
    local abs = (vim.uv.cwd() .. "/" .. tmp_rel)
    vim.fn.writefile({ "keep", "new" }, abs)
    diff.changes[abs] = { patches = { make_patch(abs) } }
    local done, got = false, nil
    diff._reconstruct(abs, function(lines)
      got = lines
      done = true
    end)
    vim.wait(5000, function() return done end, 50)
    assert.same({ "keep", "old" }, got)
  end)

  it("rejects by reverse-applying to the real file", function()
    vim.fn.writefile({ "keep", "new" }, tmp_rel)
    diff.changes[tmp_rel] = { patches = { make_patch(tmp_rel) } }
    local original_select = vim.ui.select
    vim.ui.select = function(_, _, cb) cb "Reject changes" end
    diff.reject(tmp_rel)
    vim.ui.select = original_select
    -- git apply mutates the file before nvim's scheduled callback clears the
    -- entry — waiting on file content would race the callback.
    local cleared = vim.wait(5000, function() return diff.changes[tmp_rel] == nil end, 100)
    assert.is_true(cleared)
    assert.same("old", vim.fn.readfile(tmp_rel)[2])
  end)

  it("reports drift instead of forcing a bad apply", function()
    vim.fn.writefile({ "user", "edited", "this", "later" }, tmp_rel)
    diff.changes[tmp_rel] = { patches = { make_patch(tmp_rel) } }
    local done, got_lines, got_err = false, nil, nil
    diff._reconstruct(tmp_rel, function(lines, err)
      got_lines = lines
      got_err = err
      done = true
    end)
    vim.wait(5000, function() return done end, 50)
    assert.is_nil(got_lines)
    assert.truthy(got_err and got_err:find "reverse%-apply failed")
  end)
end)
