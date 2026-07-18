--- Chat rendering: the panel's transcript buffer. Owns all chat-buffer
--- mutations (engineering rule 1). The buffer backs a NON-FOCUSABLE float —
--- it is a read-only transcript surface, not an editor pane (lua.md rule 9).
---
--- Rendering: clean role separators, collapsed thinking, concealed code
--- fences, subtle code background. No raw markdown headers.
local M = {
  ---@type integer|nil
  buf = nil,
  ns = vim.api.nvim_create_namespace "pi_nvim_chat",
  spinner_ns = vim.api.nvim_create_namespace "pi_nvim_spinner",
  style_ns = vim.api.nvim_create_namespace "pi_nvim_style",
  ---@type PiNvimConfig|nil
  _cfg = nil,
  _spinner = { timer = nil, frame = 1, mark = nil, message = nil },
  ---@type { lnum: integer, lines: integer }|nil
  _thinking = nil,
}

---@param cfg PiNvimConfig
function M.setup(cfg)
  M._cfg = cfg
  math.randomseed(os.time())
  vim.api.nvim_set_hl(0, "PiNvimUserHeader", { link = "Title", default = true })
  vim.api.nvim_set_hl(0, "PiNvimPiHeader", { link = "Special", default = true })
  vim.api.nvim_set_hl(0, "PiNvimTool", { link = "Statement", default = true })
  vim.api.nvim_set_hl(0, "PiNvimToolResult", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "PiNvimThinking", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "PiNvimNote", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "PiNvimError", { link = "ErrorMsg", default = true })
  vim.api.nvim_set_hl(0, "PiNvimSpinner", { link = "Statement", default = true })
  local float_bg = vim.api.nvim_get_hl(0, { name = "NormalFloat", link = false }).bg
  if float_bg then
    vim.api.nvim_set_hl(0, "PiNvimCode", { bg = float_bg, default = true })
  else
    vim.api.nvim_set_hl(0, "PiNvimCode", { link = "NormalFloat", default = true })
  end
end

---@return integer
function M.ensure_buf()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then return M.buf end
  M.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M.buf].buftype = "nofile"
  vim.bo[M.buf].bufhidden = "hide"
  vim.bo[M.buf].swapfile = false
  vim.bo[M.buf].filetype = "markdown"
  -- Transcript: read-only for the user (lua.md rule 9). No `readonly` flag —
  -- it W10-warns on our own transient-unlock writes.
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

---@param from integer 0-indexed inclusive
---@param to integer 0-indexed exclusive
---@param hl string|nil
local function hl_lines(from, to, hl)
  if not hl then return end
  for lnum = from, to - 1 do
    vim.api.nvim_buf_set_extmark(M.buf, M.ns, lnum, 0, { line_hl_group = hl })
  end
end

--- Panel-aware truncation. Virtual text and one-line summaries never wrap
--- (lua.md rule 11) — anything longer gets cut with an ellipsis.
---@param text string
---@return string
local function fit_width(text)
  local width = M._cfg.width
  local wins = M.buf and vim.fn.win_findbuf(M.buf) or {}
  if #wins > 0 then width = vim.api.nvim_win_get_width(wins[1]) end
  if #text <= width - 2 then return text end
  return text:sub(1, math.max(1, width - 5)) .. "…"
end

---@param lines string[]
---@param hl string|nil
---@param lines string[]
---@param hl string|nil
---@return integer start_lnum 0-indexed line where the first line landed
function M.append_lines(lines, hl)
  if #lines == 0 then return vim.api.nvim_buf_line_count(M.buf) end
  local count = vim.api.nvim_buf_line_count(M.buf)
  if count == 1 and vim.api.nvim_buf_get_lines(M.buf, 0, 1, false)[1] == "" and lines[1] == "" then
    lines = vim.list_slice(lines, 2)
    if #lines == 0 then return count end
  end
  with_modifiable(function() vim.api.nvim_buf_set_lines(M.buf, count, count, false, lines) end)
  hl_lines(count, count + #lines, hl)
  return count
end

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

--- Role separator: a clean rule line, not a markdown header. Trailing blank
--- line keeps streamed text off the rule itself; only the rule is tinted.
---@param role "You"|"Pi"
local function separator(role)
  local hl = role == "You" and "PiNvimUserHeader" or "PiNvimPiHeader"
  local start = M.append_lines { "", ("── %s "):format(role) .. string.rep("─", 20), "" }
  hl_lines(start + 1, start + 2, hl)
end

--- Locally echo what the user sent (the SDK does not re-emit user messages
--- in a way the chat renders; echoing also shows what was attached).
---@param text string
---@param attached_note string|nil
function M.echo_user(text, attached_note)
  separator "You"
  M.append_lines(vim.split(text, "\n", { plain = true }))
  if attached_note then M.append_lines({ attached_note }, "PiNvimNote") end
end

--- System note line (session switches, compaction, retries).
---@param text string
function M.note(text) M.append_lines({ "", "— " .. text }, "PiNvimNote") end

--- Error line.
---@param text string
function M.show_error(text) M.append_lines({ "", "! " .. text }, "PiNvimError") end

-- ---------------------------------------------------------------------------
-- Thinking: collapsed by default (a single dim line with a line count).
-- config.render_thinking = true streams the raw dimmed text instead.
-- ---------------------------------------------------------------------------

--- Finalize a collapsed thinking block, if one is open.
local function finalize_thinking()
  local t = M._thinking
  if not t then return end
  M._thinking = nil
  with_modifiable(
    function()
      vim.api.nvim_buf_set_lines(
        M.buf,
        t.lnum,
        t.lnum + 1,
        false,
        { ("∙ thought (%d lines)"):format(math.max(t.lines, 1)) }
      )
    end
  )
  hl_lines(t.lnum, t.lnum + 1, "PiNvimThinking")
end

---@param delta string
local function thinking_delta(delta)
  if M._cfg.render_thinking then
    M.append_text(delta, "PiNvimThinking")
    return
  end
  if not M._thinking then
    M.append_lines({ "∙ thinking…" }, "PiNvimThinking")
    M._thinking = { lnum = vim.api.nvim_buf_line_count(M.buf) - 1, lines = 0 }
  end
  local _, newlines = delta:gsub("\n", "\n")
  M._thinking.lines = M._thinking.lines + newlines + 1
end

-- ---------------------------------------------------------------------------
-- Code fence styling: conceal ``` fence lines, tint block interiors.
-- Scans a trailing window of the buffer; cheap and idempotent.
-- ---------------------------------------------------------------------------

function M._restyle()
  local count = vim.api.nvim_buf_line_count(M.buf)
  local from = math.max(0, count - 300)
  vim.api.nvim_buf_clear_namespace(M.buf, M.style_ns, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(M.buf, from, count, false)
  local in_code = false
  for i, line in ipairs(lines) do
    local lnum = from + i - 1
    if line:match "^%s*```" then
      vim.api.nvim_buf_set_extmark(M.buf, M.style_ns, lnum, 0, { conceal_lines = "" })
      in_code = not in_code
    elseif in_code then
      vim.api.nvim_buf_set_extmark(M.buf, M.style_ns, lnum, 0, { line_hl_group = "PiNvimCode" })
    end
  end
end

-- ---------------------------------------------------------------------------
-- Spinner: animated working indicator (agent_start → agent_settled).
-- A virtual line below the content — never interferes with the stream.
-- ---------------------------------------------------------------------------

local SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

function M.start_spinner()
  if M._spinner.timer then return end
  M.ensure_buf()
  local messages = M._cfg.working_messages
  M._spinner.message = messages[math.random(#messages)]
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
  local text = fit_width(" " .. SPINNER_FRAMES[s.frame] .. " " .. (s.message or "Loading") .. "…")
  s.mark = vim.api.nvim_buf_set_extmark(M.buf, M.spinner_ns, count - 1, 0, {
    virt_lines = { { { text, "PiNvimSpinner" } } },
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
  s.message = nil
end

-- ---------------------------------------------------------------------------
-- Tool call rendering
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- Event rendering
-- ---------------------------------------------------------------------------

--- Render one forwarded agent event into the transcript.
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
    if type(msg) == "table" and msg.role == "assistant" then separator "Pi" end
  elseif t == "message_update" then
    local e = evt.assistantMessageEvent
    if type(e) == "table" then
      if e.type == "text_start" then
        finalize_thinking()
        -- Each text block starts on a fresh line — otherwise the stream
        -- continues the thought summary (or tool output) line.
        local count = vim.api.nvim_buf_line_count(M.buf)
        if (vim.api.nvim_buf_get_lines(M.buf, count - 1, count, false)[1] or "") ~= "" then M.append_lines { "" } end
      elseif e.type == "text_delta" and type(e.delta) == "string" then
        M.append_text(e.delta)
      elseif e.type == "thinking_delta" and type(e.delta) == "string" then
        thinking_delta(e.delta)
      elseif e.type == "thinking_end" then
        finalize_thinking()
      end
    end
  elseif t == "tool_execution_start" then
    local name = tostring(evt.toolName or "?")
    M.append_lines({ "", fit_width("⚙ " .. name .. args_summary(name, evt.args)) }, "PiNvimTool")
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

  M._restyle()
  M.scroll_to_bottom()
end

--- Keep the panel pinned to the bottom while streaming, unless the user has
--- scrolled up to read (cursor above the last 10 lines).
function M.scroll_to_bottom()
  if not M._cfg.auto_scroll then return end
  local count = vim.api.nvim_buf_line_count(M.buf)
  for _, win in ipairs(vim.fn.win_findbuf(M.buf)) do
    local cursor = vim.api.nvim_win_get_cursor(win)
    if cursor[1] >= count - 10 then pcall(vim.api.nvim_win_set_cursor, win, { count, 0 }) end
  end
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
          separator "Pi"
          M.append_lines(vim.split(text, "\n", { plain = true }))
        end
      end
    end
  end
  M.note "history replayed (text only)"
  M._restyle()
  M.scroll_to_bottom()
end

return M
