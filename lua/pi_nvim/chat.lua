--- Chat rendering: the sidebar's message buffer. Owns all chat-buffer
--- mutations (engineering rule 1). Renders the forwarded SDK event stream:
--- assistant text/thinking deltas, tool calls and results, lifecycle notes.
---
--- The buffer is READ-ONLY for the user (modifiable=false) — chat history is
--- a transcript, not a document. Our own renders unlock it transiently via
--- with_modifiable().
local M = {
  ---@type integer|nil
  buf = nil,
  ns = vim.api.nvim_create_namespace "pi_nvim_chat",
  spinner_ns = vim.api.nvim_create_namespace "pi_nvim_spinner",
  ---@type PiNvimConfig|nil
  _cfg = nil,
  _spinner = { timer = nil, frame = 1, mark = nil },
}

---@param cfg PiNvimConfig
function M.setup(cfg)
  M._cfg = cfg
  vim.api.nvim_set_hl(0, "PiNvimHeader", { link = "Title", default = true })
  vim.api.nvim_set_hl(0, "PiNvimTool", { link = "Statement", default = true })
  vim.api.nvim_set_hl(0, "PiNvimToolResult", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "PiNvimThinking", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "PiNvimNote", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "PiNvimError", { link = "ErrorMsg", default = true })
  vim.api.nvim_set_hl(0, "PiNvimSpinner", { link = "Statement", default = true })
end

---@return integer
function M.ensure_buf()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then return M.buf end
  M.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M.buf].buftype = "nofile"
  vim.bo[M.buf].bufhidden = "hide"
  vim.bo[M.buf].swapfile = false
  vim.bo[M.buf].filetype = "markdown"
  -- Chat history is a transcript: read-only for the user (see header note).
  -- (No `readonly`: it would W10-warn on our own transient-unlock writes.)
  vim.bo[M.buf].modifiable = false
  return M.buf
end

--- Run fn with the buffer transiently modifiable, always re-locking after.
---@param fn fun()
local function with_modifiable(fn)
  vim.bo[M.buf].modifiable = true
  local ok, err = pcall(fn)
  vim.bo[M.buf].modifiable = false
  if not ok then error(err) end
end

--- Highlight a line range with a group.
---@param from integer 0-indexed inclusive
---@param to integer 0-indexed exclusive
---@param hl string|nil
local function hl_lines(from, to, hl)
  if not hl then return end
  for lnum = from, to - 1 do
    vim.api.nvim_buf_set_extmark(M.buf, M.ns, lnum, 0, { line_hl_group = hl })
  end
end

--- Append whole lines at the end of the buffer.
---@param lines string[]
---@param hl string|nil
function M.append_lines(lines, hl)
  if #lines == 0 then return end
  local count = vim.api.nvim_buf_line_count(M.buf)
  -- Keep a single leading blank line from looking odd on an empty buffer.
  if count == 1 and vim.api.nvim_buf_get_lines(M.buf, 0, 1, false)[1] == "" and lines[1] == "" then
    lines = vim.list_slice(lines, 2)
    if #lines == 0 then return end
  end
  with_modifiable(function() vim.api.nvim_buf_set_lines(M.buf, count, count, false, lines) end)
  hl_lines(count, count + #lines, hl)
end

--- Append streaming text, continuing the current last line.
---@param text string
---@param hl string|nil
function M.append_text(text, hl)
  local segments = vim.split(text, "\n", { plain = true })
  local count = vim.api.nvim_buf_line_count(M.buf)
  local last = vim.api.nvim_buf_get_lines(M.buf, count - 1, count, false)[1] or ""
  local replacement = { last .. segments[1] }
  for i = 2, #segments do
    replacement[#replacement + 1] = segments[i]
  end
  with_modifiable(function() vim.api.nvim_buf_set_lines(M.buf, count - 1, count, false, replacement) end)
  hl_lines(count - 1, count - 1 + #replacement, hl)
end

--- Section header, e.g. "## Pi".
---@param text string
function M.header(text) M.append_lines({ "", "## " .. text, "" }, "PiNvimHeader") end

--- Locally echo what the user sent (the SDK does not re-emit user messages
--- in a way the chat renders; echoing also shows what was attached).
---@param text string
---@param attached_note string|nil
function M.echo_user(text, attached_note)
  M.header "You"
  M.append_lines(vim.split(text, "\n", { plain = true }))
  if attached_note then M.append_lines({ attached_note }, "PiNvimNote") end
end

--- System note line (session switches, compaction, retries).
---@param text string
function M.note(text) M.append_lines({ "", "— " .. text }, "PiNvimNote") end

--- Error line.
---@param text string
function M.show_error(text) M.append_lines({ "", "! " .. text }, "PiNvimError") end

--- Short human summary of a tool call's arguments.
---@param name string
---@param args table|nil
---@return string
local function args_summary(name, args)
  if type(args) ~= "table" then return "" end
  if name == "bash" and type(args.command) == "string" then return " " .. args.command:gsub("\n", " "):sub(1, 80) end
  if type(args.path) == "string" then return " " .. args.path end
  local ok, encoded = pcall(vim.json.encode, args)
  return " " .. (ok and encoded:sub(1, 80) or "")
end

--- Extract display text from a tool result.
---@param result table|nil
---@return string
local function result_text(result)
  if type(result) ~= "table" then return "" end
  local content = result.content
  if type(content) == "table" then
    local parts = {}
    for _, block in ipairs(content) do
      if type(block) == "table" and block.type == "text" and type(block.text) == "string" then
        parts[#parts + 1] = block.text
      end
    end
    if #parts > 0 then return table.concat(parts, "\n") end
  end
  local ok, encoded = pcall(vim.json.encode, result)
  return ok and encoded:sub(1, 400) or ""
end

---@param text string
---@param max_lines integer
---@return string[]
local function truncate_lines(text, max_lines)
  local lines = vim.split(text, "\n", { plain = true })
  if #lines > max_lines then
    lines = vim.list_slice(lines, 1, max_lines)
    lines[#lines + 1] = "  … (truncated)"
  end
  return lines
end

--- Render one forwarded agent event into the chat buffer.
---@param evt table
function M.event(evt)
  M.ensure_buf()
  local t = evt.type

  if t == "agent_start" then
    M.start_spinner()
  elseif t == "agent_settled" then
    M.stop_spinner()
  elseif t == "message_start" then
    local msg = evt.message
    if type(msg) == "table" and msg.role == "assistant" then M.header "Pi" end
  elseif t == "message_update" then
    local e = evt.assistantMessageEvent
    if type(e) == "table" then
      if e.type == "text_delta" and type(e.delta) == "string" then
        M.append_text(e.delta)
      elseif M._cfg.render_thinking and e.type == "thinking_delta" and type(e.delta) == "string" then
        M.append_text(e.delta, "PiNvimThinking")
      elseif M._cfg.render_thinking and e.type == "thinking_start" then
        M.append_lines({ "### thinking" }, "PiNvimThinking")
      end
    end
  elseif t == "tool_execution_start" then
    local name = tostring(evt.toolName or "?")
    M.append_lines({ "", "⚙ " .. name .. args_summary(name, evt.args) }, "PiNvimTool")
  elseif t == "tool_execution_end" then
    local text = result_text(evt.result)
    if text ~= "" then
      M.append_lines(
        truncate_lines(text, M._cfg.tool_result_lines),
        evt.isError and "PiNvimError" or "PiNvimToolResult"
      )
    end
    if evt.isError then M.append_lines({ "! tool failed: " .. tostring(evt.toolName) }, "PiNvimError") end
  elseif t == "turn_end" then
    M.append_lines { "" }
  elseif t == "compaction_start" then
    M.note "compacting context…"
  elseif t == "compaction_end" then
    M.note "context compacted"
  elseif t == "auto_retry_start" then
    M.note(("retrying (attempt %s)…"):format(tostring(evt.attempt)))
  elseif t == "host_error" then
    M.stop_spinner()
    M.show_error(tostring(evt.message))
  end

  M.scroll_to_bottom()
end

--- Keep visible chat windows pinned to the bottom while streaming, unless
--- the user has scrolled up to read (cursor above the last 10 lines).
function M.scroll_to_bottom()
  if not M._cfg.auto_scroll then return end
  local count = vim.api.nvim_buf_line_count(M.buf)
  for _, win in ipairs(vim.fn.win_findbuf(M.buf)) do
    local cursor = vim.api.nvim_win_get_cursor(win)
    if cursor[1] >= count - 10 then pcall(vim.api.nvim_win_set_cursor, win, { count, 0 }) end
  end
end

-- ---------------------------------------------------------------------------
-- Spinner: animated working indicator while the agent runs (agent_start →
-- agent_settled). Rendered as a virtual line below the last buffer line so
-- it never interferes with streamed content.
-- ---------------------------------------------------------------------------

local SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

function M.start_spinner()
  if M._spinner.timer then return end
  M.ensure_buf()
  local timer = vim.uv.new_timer()
  M._spinner.timer = timer
  timer:start(0, 90, vim.schedule_wrap(function() M._render_spinner() end))
end

function M._render_spinner()
  local s = M._spinner
  if not (M.buf and vim.api.nvim_buf_is_valid(M.buf)) then
    M.stop_spinner()
    return
  end
  if s.mark then pcall(vim.api.nvim_buf_del_extmark, M.buf, M.spinner_ns, s.mark) end
  local count = vim.api.nvim_buf_line_count(M.buf)
  s.mark = vim.api.nvim_buf_set_extmark(M.buf, M.spinner_ns, count - 1, 0, {
    virt_lines = { { { " " .. SPINNER_FRAMES[s.frame] .. " pi is working…  (<leader>ax aborts)", "PiNvimSpinner" } } },
  })
  s.frame = (s.frame % #SPINNER_FRAMES) + 1
end

function M.stop_spinner()
  local s = M._spinner
  if s.timer then
    s.timer:stop()
    s.timer:close()
    s.timer = nil
  end
  if s.mark and M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    pcall(vim.api.nvim_buf_del_extmark, M.buf, M.spinner_ns, s.mark)
  end
  s.mark = nil
  s.frame = 1
end

---@param msg table
---@return string
local function message_text(msg)
  local content = msg.content
  if type(content) == "string" then return content end
  if type(content) == "table" then
    local parts = {}
    for _, block in ipairs(content) do
      if type(block) == "table" and block.type == "text" and type(block.text) == "string" then
        parts[#parts + 1] = block.text
      end
    end
    return table.concat(parts, "\n")
  end
  return ""
end

--- Replay history after switching sessions (text only; tool calls collapse).
---@param messages unknown
function M.replay(messages)
  M.ensure_buf()
  with_modifiable(function() vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, { "" }) end)
  if type(messages) ~= "table" then return end
  for _, msg in ipairs(messages) do
    if type(msg) == "table" then
      local text = message_text(msg)
      if text ~= "" then
        if msg.role == "user" then
          M.echo_user(text)
        elseif msg.role == "assistant" then
          M.header "Pi"
          M.append_lines(vim.split(text, "\n", { plain = true }))
        end
      end
    end
  end
  M.note "history replayed (text only)"
  M.scroll_to_bottom()
end

return M
