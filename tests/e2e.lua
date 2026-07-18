-- Headless full-stack E2E: real host boot against the real ~/.pi/agent,
-- sidebar windows, state handshake, session commands. No LLM calls (free).
-- Run: make e2e
local pi = require "pi_nvim"
local failures = 0

local function check(name, ok)
  print(("E2E %-28s %s"):format(name, ok and "OK" or "FAIL"))
  if not ok then failures = failures + 1 end
end

pi.setup { keymaps = false }

-- Sidebar opens and both windows exist.
pi.toggle()
local sidebar = require "pi_nvim.panel"
check("sidebar opens", sidebar.is_open())
check("chat buffer exists", require("pi_nvim.chat").buf ~= nil)
check("input buffer exists", require("pi_nvim.input").buf ~= nil)

-- Host boots; hello returns real state (waits through extension loading).
local booted = vim.wait(45000, function()
  local host = pi.get_host()
  return host ~= nil and host.state ~= nil and host.state.model ~= nil
end, 250)
local host = pi.get_host()
check("host boots with model", booted)
if booted then
  print(
    ("E2E   model=%s/%s thinking=%s"):format(
      host.state.model.provider,
      host.state.model.id,
      tostring(host.state.thinkingLevel)
    )
  )
end

-- Session commands round-trip.
local done, new_ok = false, false
host:request("new_session", {}, function(resp)
  new_ok = resp.success == true
  done = true
end)
vim.wait(20000, function() return done end, 100)
check("new_session round-trip", new_ok)

local listed, list_ok = false, false
host:request("list_sessions", {}, function(resp)
  list_ok = resp.success == true and type(resp.data) == "table"
  listed = true
end)
vim.wait(20000, function() return listed end, 100)
check("list_sessions round-trip", list_ok)

host:stop()
print(failures == 0 and "E2E PASS" or ("E2E FAIL (" .. failures .. ")"))
vim.cmd(failures == 0 and "qa!" or "cq!")
