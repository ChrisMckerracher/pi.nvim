--- Host job ownership: spawn, JSONL framing, request/response correlation,
--- event dispatch, shutdown. This is the ONLY module allowed to call
--- jobstart/chansend (engineering rule 1: one owner per concern).
local protocol = require "pi_nvim.protocol"

---@class PiHostState
---@field model {provider:string,id:string,name:string}|nil
---@field thinkingLevel string
---@field isStreaming boolean
---@field sessionId string
---@field sessionFile string|nil
---@field messageCount integer

---@class PiHost
---@field cfg PiNvimConfig
---@field job integer|nil
---@field state PiHostState
---@field _pending_stdout string
---@field _next_id integer
---@field _callbacks table<string, fun(resp:table)>
---@field _listeners fun(evt:table)[]
---@field _intentional_exit boolean
---@field _starting boolean
---@field _start_waiters fun(ok:boolean, err:string|nil)[]
local Host = {}
Host.__index = Host

---@param cfg PiNvimConfig
---@return PiHost
function Host.new(cfg)
  return setmetatable({
    cfg = cfg,
    job = nil,
    state = {
      model = nil,
      thinkingLevel = "?",
      isStreaming = false,
      sessionId = "",
      sessionFile = nil,
      messageCount = 0,
    },
    _pending_stdout = "",
    _next_id = 0,
    _callbacks = {},
    _listeners = {},
    _intentional_exit = false,
    _starting = false,
    _start_waiters = {},
  }, Host)
end

--- Subscribe to agent events (responses are correlated separately).
--- Listeners run scheduled — never in a fast event context (lua.md rule 7).
---@param listener fun(evt:table)
function Host:on_event(listener) table.insert(self._listeners, listener) end

--- Track streaming/thinking state from forwarded events, then dispatch.
---@param evt table
function Host:_emit(evt)
  if evt.type == "agent_start" then
    self.state.isStreaming = true
  elseif evt.type == "agent_settled" then
    self.state.isStreaming = false
  elseif evt.type == "thinking_level_changed" and type(evt.level) == "string" then
    self.state.thinkingLevel = evt.level
  end
  for _, listener in ipairs(self._listeners) do
    vim.schedule(function() pcall(listener, evt) end)
  end
end

--- Spawn the host and perform the protocol handshake. Concurrent callers
--- queue on the same boot instead of spawning duplicate jobs.
---@param cb fun(ok:boolean, err:string|nil)
function Host:start(cb)
  if self.job then
    cb(true)
    return
  end
  if self._starting then
    table.insert(self._start_waiters, cb)
    return
  end
  local cmd = self.cfg.host_cmd
  if vim.fn.executable(cmd[1]) == 0 then
    cb(false, "not executable: " .. cmd[1])
    return
  end
  if cmd[2] and vim.fn.filereadable(cmd[2]) == 0 then
    cb(false, "host not built: " .. cmd[2] .. " (build it: npm ci --prefix host && npm run build --prefix host)")
    return
  end

  self._starting = true
  self._start_waiters = { cb }

  --- Finish boot: notify all waiters exactly once; clean up a failed job.
  ---@param ok boolean
  ---@param err string|nil
  local finish = function(ok, err)
    local waiters = self._start_waiters
    self._start_waiters = {}
    self._starting = false
    if not ok then
      if self.job then pcall(vim.fn.jobstop, self.job) end
      self.job = nil
    end
    for _, waiter in ipairs(waiters) do
      waiter(ok, err)
    end
  end

  self._intentional_exit = false
  self.job = vim.fn.jobstart(cmd, {
    cwd = vim.uv.cwd(),
    on_stdout = function(_, data) self:_handle_stdout(data) end,
    on_stderr = function(_, data)
      local text = table.concat(data, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
      if text ~= "" then
        vim.schedule(function() vim.notify("pi host stderr: " .. text:sub(1, 300), vim.log.levels.WARN) end)
      end
    end,
    on_exit = function(_, code)
      self.job = nil
      if not self._intentional_exit then
        vim.schedule(
          function() vim.notify(("pi host exited unexpectedly (code %d)"):format(code), vim.log.levels.ERROR) end
        )
      end
    end,
  })

  if self.job <= 0 then
    self.job = nil
    finish(false, "jobstart failed for: " .. table.concat(cmd, " "))
    return
  end

  self:request("hello", {}, function(resp)
    if not resp.success then
      finish(false, resp.error or "hello failed")
      return
    end
    local data = resp.data or {}
    if data.protocol ~= protocol.version then
      finish(false, ("protocol mismatch: plugin v%d, host v%s"):format(protocol.version, tostring(data.protocol)))
      return
    end
    self.state = data.state or self.state
    finish(true)
  end)
end

--- jobstart delivers stdout as a list whose first item continues the previous
--- partial line and whose last item is a new partial (arbitrary chunk
--- boundaries). Reassemble LF-delimited records; strip one trailing CR.
---@param data string[]
function Host:_handle_stdout(data)
  data[1] = self._pending_stdout .. data[1]
  self._pending_stdout = data[#data]
  for i = 1, #data - 1 do
    self:_handle_line((data[i]:gsub("\r$", "")))
  end
end

---@param line string
function Host:_handle_line(line)
  if line == "" then return end
  local msg, err = protocol.decode(line)
  if not msg then
    vim.schedule(function() vim.notify("pi host: malformed line: " .. (err or "?"), vim.log.levels.WARN) end)
    return
  end
  if msg.type == "response" then
    local cb = msg.id and self._callbacks[msg.id] or nil
    if cb then
      self._callbacks[msg.id] = nil
      vim.schedule(function() cb(msg) end)
    end
  else
    self:_emit(msg)
  end
end

--- Send a command and invoke cb with its response.
---@param cmd_type string
---@param fields table|nil
---@param cb fun(resp:table)|nil
function Host:request(cmd_type, fields, cb)
  if not self.job then
    vim.notify("pi host is not running", vim.log.levels.WARN)
    return
  end
  self._next_id = self._next_id + 1
  local id = tostring(self._next_id)
  local cmd = vim.tbl_extend("force", { id = id, type = cmd_type }, fields or {})
  self._callbacks[id] = cb or function() end
  vim.fn.chansend(self.job, protocol.encode(cmd))
end

--- Send a command with no response correlation (e.g. editor_context_response).
---@param cmd_type string
---@param fields table|nil
function Host:notify(cmd_type, fields)
  if not self.job then return end
  local cmd = vim.tbl_extend("force", { type = cmd_type }, fields or {})
  vim.fn.chansend(self.job, protocol.encode(cmd))
end

---@return boolean
function Host:is_streaming() return self.state.isStreaming == true end

--- Graceful shutdown; falls back to jobstop if the host lingers.
function Host:stop()
  if not self.job then return end
  local job = self.job
  self._intentional_exit = true
  self:notify "dispose"
  vim.defer_fn(function() pcall(vim.fn.jobstop, job) end, 2000)
end

return Host
